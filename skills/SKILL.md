---
name: stampede
description: >
  Cross-terminal multi-agent orchestration. Splits complex tasks into parallel
  work units dispatched to independent Copilot CLI agents via tmux panes with
  filesystem IPC, atomic operations, dead agent recovery, and conflict-aware synthesis.
tools:
  - bash
  - grep
  - glob
  - view
  - edit
  - create
  - sql
  - ask_user
  - task
  - read_agent
  - list_agents
---

# Stampede — Multi-Agent Orchestrator

You are the orchestrator for a fleet of autonomous AI agents running in separate
tmux panes. You decompose user requests into parallel tasks, dispatch them via
filesystem IPC, monitor progress, recover dead agents, and synthesize results.

**You are a SKILL. Agents run in separate terminal panes. Never confuse the two.**

## Command Grammar

| Pattern | Action |
|---------|--------|
| `stampede [N agents on] REPO [with model MODEL] [: task descriptions]` | Launch new run |
| `stampede resume [RUN_ID]` | Resume interrupted run |
| `stampede status [RUN_ID]` | Show run status |
| `stampede teardown [RUN_ID]` | Tear down agents and clean up |

**Defaults:** agents = 3 (max 8), model = `claude-sonnet-4-5`, repo = cwd

If tasks are listed after `:` (semicolon-separated), create one task per description.
If no tasks given, analyze the repo and auto-generate them.

**Greeting:** When the user says just "stampede" with no arguments, use `ask_user` with:
> "🦬 What repo and tasks? Example: `stampede 8 agents on ~/dev/my-app : add tests; fix errors; update docs`"

---

## STEP 0 — SQL SCHEMA (run on every invocation)

Always initialize SQL tables first. This ensures state survives crashes. <!-- Landmine #11 -->

```sql
CREATE TABLE IF NOT EXISTS stampede_runs (
    run_id TEXT PRIMARY KEY,
    objective TEXT NOT NULL,
    repo_path TEXT NOT NULL,
    model TEXT NOT NULL,
    worker_count INTEGER NOT NULL,
    total_tasks INTEGER NOT NULL,
    completed_tasks INTEGER DEFAULT 0,
    failed_tasks INTEGER DEFAULT 0,
    status TEXT DEFAULT 'running' CHECK(status IN ('running','completed','failed','paused')),
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS stampede_tasks (
    task_id TEXT PRIMARY KEY,
    run_id TEXT NOT NULL,
    title TEXT NOT NULL,
    objective TEXT NOT NULL,
    status TEXT DEFAULT 'queued' CHECK(status IN ('queued','claimed','done','failed','requeued')),
    worker_id TEXT,
    generation INTEGER DEFAULT 0,
    branch TEXT,
    files_changed TEXT,
    summary TEXT,
    duration_sec REAL,
    error TEXT,
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now')),
    FOREIGN KEY (run_id) REFERENCES stampede_runs(run_id)
);

CREATE TABLE IF NOT EXISTS stampede_workers (
    worker_id TEXT,
    run_id TEXT NOT NULL,
    pane_index INTEGER,
    pid INTEGER,
    status TEXT DEFAULT 'running' CHECK(status IN ('running','dead','completed')),
    tasks_completed INTEGER DEFAULT 0,
    last_seen TEXT DEFAULT (datetime('now')),
    PRIMARY KEY (worker_id, run_id)
);
```

---

## STEP 1 — PARSE THE REQUEST

Extract from the user's natural-language prompt:

| Field | Source | Default |
|---|---|---|
| `objective` | what the user wants done | *(required)* |
| `repo_path` | repository path (resolve `~`) | cwd |
| `worker_count` | "N agents" | 3 (max 8) |
| `model` | "with model X" | claude-sonnet-4-5 |

If `stampede resume [RUN_ID]` → skip to STEP 9.
If `stampede status` → query SQL + filesystem, report.
If `stampede teardown [RUN_ID]` → run `~/bin/stampede.sh --teardown --run-id RUN_ID`.
If ambiguous → use `ask_user` to clarify scope and objective.

### Objective Templates

Sharpen each task objective based on detected type. <!-- Landmine #24 -->

| Type | Detected When | Template |
|---|---|---|
| `audit` | "audit", "check", "scan", "lint" | "Audit {scope} for {criteria}. Report: file, line, severity, fix." |
| `review` | "review", "critique" | "Review {scope}. Each finding: location, issue, severity 1-5, suggested fix." |
| `analyze` | "analyze", "understand" | "Analyze {scope}. Produce: summary, key patterns, dependencies, risks." |
| `test` | "test", "coverage", "spec" | "Write tests for {scope}. Cover: happy path, edge cases, error handling." |
| `document` | "document", "docs" | "Document {scope}. Include: purpose, API surface, usage examples." |
| `refactor` | "refactor", "clean" | "Refactor {scope}. Preserve behavior. Show: what, why, before/after." |
| `generic` | fallback | Use the user's exact wording as the objective. |

---

## STEP 2 — GENERATE RUN ID AND DIRECTORIES

```python
python3 -c '
import datetime, os

run_id = f"run-{datetime.datetime.now().strftime("%Y%m%d-%H%M%S")}"
base = os.path.expanduser(f"~/.copilot/stampede/{run_id}")

for d in ["queue", "claimed", "results", "logs", "pids"]:
    os.makedirs(f"{base}/{d}", exist_ok=True)

print(f"RUN_ID={run_id}")
print(f"BASE={base}")
'
```

<!-- Landmine #20: run-YYYYMMDD-HHMMSS format prevents collisions -->
<!-- Landmine #23: All directories created before any operations -->

All coordination uses these directories — zero infrastructure, pure filesystem IPC:
- `queue/` — tasks waiting to be claimed
- `claimed/` — tasks being worked on
- `results/` — completed task outputs
- `logs/` — per-worker JSONL logs + orchestrator log
- `pids/` — worker PID files for liveness checks

---

## STEP 3 — GATHER REPO CONTEXT

Collect context ONCE. Embed in every manifest so agents start warm. <!-- Landmine #8 -->

```bash
cd REPO_PATH

# README excerpt
README_EXCERPT=$(head -200 README.md 2>/dev/null || echo "No README found")

# Directory tree (pruned)
TREE=$(find . -maxdepth 3 \
  -not -path '*node_modules*' -not -path '*venv*' \
  -not -path '*.git/*' -not -path '*__pycache__*' -not -path '*dist*' \
  | sed 's#^\./##' | head -150)

# Detect test command
if [ -f package.json ]; then
  TEST_CMD=$(python3 -c "import json; d=json.load(open('package.json')); print(d.get('scripts',{}).get('test','npm test'))")
elif [ -f pyproject.toml ] || [ -d tests ]; then TEST_CMD="pytest -q"
elif [ -f go.mod ]; then TEST_CMD="go test ./..."
elif [ -f Makefile ] && grep -q '^test:' Makefile; then TEST_CMD="make test"
else TEST_CMD=""
fi
```

---

## STEP 4 — SPLIT WORK INTO TASK MANIFESTS

Create non-overlapping task manifests. Each task gets exclusive file ownership. <!-- Landmine #6 -->

Use python3 for ALL JSON operations. <!-- Landmine #1: Never use echo/printf for JSON -->

```python
python3 -c '
import json, os

run_id = "THE_RUN_ID"
base = "THE_BASE_DIR"
objective = """THE_OBJECTIVE"""
repo_path = "THE_REPO_PATH"
repo_context = {
    "readme_excerpt": """THE_README"""[:8000],
    "tree": """THE_TREE"""[:12000],
    "test_command": "THE_TEST_CMD"
}

scope_files = []  # populated from glob/grep analysis of repo
worker_count = WORKER_COUNT
chunk_size = max(1, len(scope_files) // worker_count)
chunks = [scope_files[i:i+chunk_size] for i in range(0, len(scope_files), chunk_size)]

for idx, chunk in enumerate(chunks):
    task_id = f"task-{idx+1:03d}"
    manifest = {
        "task_id": task_id,
        "run_id": run_id,
        "title": f"Process group {idx+1}",
        "objective": objective,
        "generation": 0,
        "files": chunk,
        "repo_path": repo_path,
        "branch": f"stampede/{task_id}",
        "repo_context": repo_context,
        "constraints": {
            "max_result_words": 500,
            "branch_prefix": "stampede",
            "no_main_commits": True
        },
        "context": {
            "total_tasks": len(chunks),
            "task_index": idx,
            "related_tasks": [f"task-{j+1:03d}" for j in range(len(chunks)) if j != idx]
        }
    }
    path = os.path.join(base, "queue", f"{task_id}.json")
    with open(path, "w") as f:
        json.dump(manifest, f, indent=2)
    print(f"Created {path}")
'
```

Insert the run and each task into SQL:

```sql
INSERT INTO stampede_runs (run_id, objective, repo_path, model, worker_count, total_tasks)
VALUES ('RUN_ID', 'OBJECTIVE', 'REPO', 'MODEL', N, T);

INSERT INTO stampede_tasks (task_id, run_id, title, objective, branch)
VALUES ('task-001', 'RUN_ID', 'title', 'objective', 'stampede/task-001');
-- repeat for each task
```

---

## STEP 5 — PERSIST STATE FOR CRASH RECOVERY

Write `state.json` after every state-changing step. <!-- Landmine #10 -->

```python
python3 -c '
import json, os, glob as g, time

base = "THE_BASE_DIR"
state = {
    "run_id": "THE_RUN_ID",
    "base": base,
    "objective": "THE_OBJECTIVE",
    "repo_path": "THE_REPO_PATH",
    "model": "THE_MODEL",
    "worker_count": WORKER_COUNT,
    "total_tasks": TOTAL_TASKS,
    "phase": "stampedeing",
    "tasks": {
        "queued": [os.path.basename(f).replace(".json","")
                   for f in sorted(g.glob(f"{base}/queue/*.json"))],
        "claimed": [os.path.basename(f).replace(".json","")
                    for f in sorted(g.glob(f"{base}/claimed/*.json"))],
        "completed": [os.path.basename(f).replace(".json","")
                      for f in sorted(g.glob(f"{base}/results/*.json"))]
    },
    "workers": [],
    "updated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
}

with open(f"{base}/state.json", "w") as f:
    json.dump(state, f, indent=2)
'
```

### state.json Shape

```json
{
  "run_id": "run-20250715-143022",
  "base": "~/.copilot/stampede/run-20250715-143022",
  "objective": "...",
  "repo_path": "/abs/path",
  "model": "claude-sonnet-4-5",
  "phase": "stampedeing|running|synthesizing|completed",
  "tasks": { "queued": [], "claimed": [], "completed": [] },
  "workers": [{ "worker_id": "a1b2c3", "pid": 12345, "status": "alive" }],
  "updated_at": "ISO-8601"
}
```

---

## STEP 6 — LAUNCH AGENTS

Invoke the launcher with `bash(mode="async", detach=true)` and `--no-attach` (the skill handles window opening): <!-- Landmine #21 -->

```bash
chmod +x ~/bin/stampede.sh
~/bin/stampede.sh \
  --run-id THE_RUN_ID \
  --count WORKER_COUNT \
  --repo THE_REPO_PATH \
  --model THE_MODEL \
  --no-attach
```

Wait 5 seconds, then verify the tmux session exists:

```bash
tmux has-session -t "stampede-THE_RUN_ID" 2>/dev/null && echo "FLEET_RUNNING" || echo "FLEET_FAILED"
```

**IMMEDIATELY after confirming FLEET_RUNNING**, open a Terminal window so the user can watch. Run this with `bash` (NOT detached — needs GUI access):

```bash
ATTACH_SCRIPT=$(mktemp /tmp/stampede-attach-XXXXXX.sh)
cat > "$ATTACH_SCRIPT" << 'EOF'
#!/usr/bin/env bash
clear
echo "🦬 Connecting to Terminal Stampede..."
sleep 0.5
tmux attach -t stampede-THE_RUN_ID
EOF
chmod +x "$ATTACH_SCRIPT"
open -a Terminal "$ATTACH_SCRIPT"
```

Tell the user: "🦬 **Stampede is running!** A Terminal window just opened showing your agents working in real time. Come back here when they're done for the full report."

Update state.json phase to `"running"`. Log the event:

```bash
echo '{"ts":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'","event":"fleet_launched","run_id":"RUN_ID","workers":N}' >> "BASE/logs/orchestrator.jsonl"
```

---

## STEP 7 — POLL, MONITOR, AND RECOVER

Core monitoring loop. Poll every 20 seconds until all tasks are terminal.

```python
python3 -c '
import os, json, time

base = "THE_BASE_DIR"
total = TOTAL_TASKS
max_generation = 2

while True:
    queued = [f for f in os.listdir(os.path.join(base, "queue")) if f.endswith(".json")]
    claimed = [f for f in os.listdir(os.path.join(base, "claimed")) if f.endswith(".json")]
    results = [f for f in os.listdir(os.path.join(base, "results")) if f.endswith(".json")]
    done = len(results)

    # Progress bar
    pct = int(done / total * 100) if total > 0 else 0
    filled = pct // 5
    bar = "█" * filled + "░" * (20 - filled)

    # PID heartbeat — Landmine #4, #16
    live, dead_workers = 0, []
    pids_dir = os.path.join(base, "pids")
    if os.path.isdir(pids_dir):
        for pf in os.listdir(pids_dir):
            if not pf.endswith(".pid"):
                continue
            wid = pf.replace(".pid", "")
            try:
                with open(os.path.join(pids_dir, pf)) as f:
                    pid = int(f.read().strip())
                os.kill(pid, 0)  # signal 0 = alive check
                live += 1
            except (ProcessLookupError, ValueError, PermissionError, FileNotFoundError):
                dead_workers.append((wid, os.path.join(pids_dir, pf)))

    print(f"[{bar}] {pct}% ({done}/{total}) | q={len(queued)} c={len(claimed)} | alive={live} dead={len(dead_workers)}")

    if done >= total:
        print("All tasks complete.")
        break

    if len(queued) == 0 and len(claimed) == 0 and done < total:
        print("No pending tasks but incomplete.")
        break

    # Dead worker recovery — Landmine #5
    for wid, pid_path in dead_workers:
        for cf in list(claimed):
            claimed_path = os.path.join(base, "claimed", cf)
            try:
                with open(claimed_path) as f:
                    task = json.load(f)
                if task.get("claimed_by") != wid:
                    continue
                gen = task.get("generation", 0) + 1
                if gen > max_generation:
                    task["status"] = "failed"
                    task["error"] = "max_generation_exceeded"
                    with open(os.path.join(base, "results", cf), "w") as f:
                        json.dump(task, f, indent=2)
                    os.remove(claimed_path)
                else:
                    task["generation"] = gen
                    task.pop("claimed_by", None)
                    task.pop("claimed_at", None)
                    with open(os.path.join(base, "queue", cf), "w") as f:
                        json.dump(task, f, indent=2)
                    os.remove(claimed_path)
            except (json.JSONDecodeError, FileNotFoundError):
                pass
        try:
            os.remove(pid_path)  # Landmine #9
        except FileNotFoundError:
            pass

    # Orphan sweep: stale claims >10min — Landmine #19
    now = time.time()
    for cf in list(os.listdir(os.path.join(base, "claimed"))):
        if not cf.endswith(".json"):
            continue
        claimed_path = os.path.join(base, "claimed", cf)
        try:
            if now - os.path.getmtime(claimed_path) > 600:
                with open(claimed_path) as f:
                    task = json.load(f)
                gen = task.get("generation", 0) + 1
                if gen <= max_generation:
                    task["generation"] = gen
                    task.pop("claimed_by", None)
                    task.pop("claimed_at", None)
                    with open(os.path.join(base, "queue", cf), "w") as f:
                        json.dump(task, f, indent=2)
                    os.remove(claimed_path)
        except (json.JSONDecodeError, FileNotFoundError):
            pass

    time.sleep(20)
'
```

After loop, update SQL:

```sql
UPDATE stampede_runs
SET completed_tasks = (SELECT COUNT(*) FROM stampede_tasks WHERE run_id = 'RUN_ID' AND status = 'done'),
    failed_tasks = (SELECT COUNT(*) FROM stampede_tasks WHERE run_id = 'RUN_ID' AND status = 'failed'),
    updated_at = datetime('now')
WHERE run_id = 'RUN_ID';
```

Persist state with phase = `"synthesizing"`.

---

## STEP 8 — SYNTHESIZE RESULTS WITH CONFLICT DETECTION

```python
python3 -c '
import json, os
from collections import defaultdict

base = "THE_BASE_DIR"
results_dir = os.path.join(base, "results")
all_results = []
file_owners = defaultdict(list)

for rf in sorted(os.listdir(results_dir)):
    if not rf.endswith(".json"):
        continue
    with open(os.path.join(results_dir, rf)) as f:
        result = json.load(f)
    # Landmine #15: verify run_id
    if result.get("run_id") and result["run_id"] != "THE_RUN_ID":
        continue
    all_results.append(result)
    for fp in result.get("files_changed", result.get("files_modified", [])):
        file_owners[fp].append(result.get("task_id", rf))

# Conflict detection — Landmine #6, #7
conflicts = {fp: tasks for fp, tasks in file_owners.items() if len(tasks) > 1}
if conflicts:
    print("⚠️  CONFLICTS DETECTED:")
    for fp, tasks in conflicts.items():
        print(f"  {fp} ← modified by {tasks}")

branches = [r.get("branch") for r in all_results if r.get("branch")]
if branches:
    print(f"📌 {len(branches)} branches: {branches}")

# Deterministic output sorted by task_id
print("=" * 60)
print("STAMPEDE RESULTS SYNTHESIS")
print("=" * 60)
succeeded = failed = 0
for r in sorted(all_results, key=lambda x: x.get("task_id", "")):
    tid = r.get("task_id", "unknown")
    status = r.get("status", "unknown")
    summary = r.get("summary", "No summary")
    error = r.get("error", "")
    if status in ("done", "completed"):
        succeeded += 1; icon = "✅"
    elif error or status in ("failed", "error"):
        failed += 1; icon = "❌"
    else:
        icon = "⚠️"
    print(f"\n{icon} {tid} [{status}]")
    print(f"   {summary[:500]}")
    if error:
        print(f"   Error: {error}")

print(f"\nTotal: {len(all_results)} | Succeeded: {succeeded} | Failed: {failed}")
if conflicts:
    print(f"Conflicts: {len(conflicts)} files need resolution")
print("=" * 60)
'
```

If conflicts, present to user via `ask_user`. For non-conflicting branches, suggest merge:

```bash
cd REPO_PATH
git checkout main 2>/dev/null || git checkout master
for branch in $(git branch --list 'stampede/*' | tr -d ' '); do
  git merge --no-ff "$branch" -m "Merge $branch" || { echo "Conflict on $branch"; git merge --abort; }
done
```

---

## STEP 9 — CRASH RECOVERY (stampede resume)

```python
python3 -c '
import json, os, glob as g

stampede_dir = os.path.expanduser("~/.copilot/stampede")
run_id = "PROVIDED_OR_EMPTY"

if not run_id:
    runs = sorted(g.glob(f"{stampede_dir}/run-*/state.json"), reverse=True)
    if not runs:
        print("No stampede runs found.")
        exit(1)
    run_id = os.path.basename(os.path.dirname(runs[0]))

base = os.path.join(stampede_dir, run_id)
with open(os.path.join(base, "state.json")) as f:
    state = json.load(f)

# Re-queue all claimed tasks (workers dead after crash)
for cf in os.listdir(os.path.join(base, "claimed")):
    if not cf.endswith(".json"):
        continue
    src = os.path.join(base, "claimed", cf)
    with open(src) as f:
        task = json.load(f)
    gen = task.get("generation", 0) + 1
    task["generation"] = gen
    task.pop("claimed_by", None)
    task.pop("claimed_at", None)
    with open(os.path.join(base, "queue", cf), "w") as f:
        json.dump(task, f, indent=2)
    os.remove(src)
    print(f"Re-queued {cf} (generation {gen})")

remaining = len([f for f in os.listdir(os.path.join(base, "queue")) if f.endswith(".json")])
done = len([f for f in os.listdir(os.path.join(base, "results")) if f.endswith(".json")])
print(f"Resume: {done} done, {remaining} remaining")
'
```

Then proceed to STEP 6 (relaunch), then STEP 7 (poll).

---

## STEP 10 — FINALIZE AND CLEANUP

Update state.json and SQL:

```python
python3 -c '
import json, time
path = "THE_BASE_DIR/state.json"
with open(path) as f: state = json.load(f)
state["phase"] = "completed"
state["updated_at"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
with open(path, "w") as f: json.dump(state, f, indent=2)
'
```

```sql
UPDATE stampede_runs
SET status = CASE WHEN failed_tasks = 0 THEN 'completed' ELSE 'failed' END,
    updated_at = datetime('now')
WHERE run_id = 'RUN_ID';
```

Offer: `stampede teardown RUN_ID`, `stampede resume RUN_ID`, branch links.

---

## LANDMINE REFERENCE

| # | Landmine | Mitigation |
|---|----------|------------|
| 1 | Shell JSON escaping | All JSON via Python `json.dump` |
| 2 | Race on task claim | Workers use atomic `mv` (rename on same FS) |
| 3 | Partial result reads | Workers write `.tmp-` then `mv` to final |
| 4 | Worker dies mid-task | `os.kill(pid, 0)` detection + re-queue |
| 5 | Re-queue infinite loop | `max_generation = 2` cap, then mark failed |
| 6 | Overlapping file scopes | Non-overlapping decomposition + conflict detection |
| 7 | Git merge conflicts | Detect overlapping files_changed; abort and flag |
| 8 | Cold agents | Repo context (README, tree, test cmd) in manifests |
| 9 | Stale PID files | Removed after dead worker detection |
| 10 | State lost on crash | state.json persisted at every phase transition |
| 11 | SQL not initialized | IF NOT EXISTS on every invocation |
| 12 | tmux session leak | Teardown; launcher checks for existing |
| 13 | Autopilot runaway | `--max-autopilot-continues 30` on agents |
| 14 | 500-word result blowup | Enforced in worker constraints and agent |
| 15 | Task injection | Verify `run_id` matches when reading files |
| 16 | PID ≠ worker PID | Process tree walking finds leaf PID |
| 17 | Branch name collision | `stampede/{task_id}`, unique per task |
| 18 | Workers finish pre-poll | Poll handles pre-existing results |
| 19 | Stale claims (>10min) | Orphan sweep re-queues old claims |
| 20 | Run directory collision | `run-YYYYMMDD-HHMMSS`, unique per second |
| 21 | Monitor pane dies | `watch` auto-restarts on interval |
| 22 | Glob returns empty | All results checked before iteration |
| 23 | Missing directories | Created in STEP 2 before operations |
| 24 | Objective too vague | Template system sharpens by task_type |

## IMPLEMENTATION CHECKLIST

- [ ] SQL tables exist (STEP 0)
- [ ] Run directory with all 5 subdirectories
- [ ] Task manifests are valid JSON in queue/
- [ ] `~/bin/stampede.sh` is executable
- [ ] `~/.copilot/agents/stampede-worker.agent.md` is installed
- [ ] tmux is available
- [ ] Target repo has .git directory
- [ ] `--max-autopilot-continues 30` on agents
- [ ] Worker model configured (default: claude-sonnet-4-5)

## COMPLETION CRITERIA

- queue/ empty
- claimed/ empty
- Every task has terminal result (done or failed)
- state.json phase is `completed`
- Synthesis includes conflict report (or explicit "none")
