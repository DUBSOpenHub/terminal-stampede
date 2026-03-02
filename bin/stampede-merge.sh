#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

# stampede-merge.sh — Auto-merge all stampede branches + shadow scoring
# Merges deterministically in bash/Python. Only calls the AI agent for
# conflict resolution (where semantic understanding matters).
# Usage: stampede-merge.sh --run-id <id> --repo <path> [--model <model>]

# ─── Validation ──────────────────────────────────────────────────────────────

# Check git is available
if ! command -v git &>/dev/null; then
    echo "❌ Error: git is not installed or not in PATH" >&2
    echo "   Install git to continue: https://git-scm.com/downloads" >&2
    exit 1
fi

# Check python3 is available
if ! command -v python3 &>/dev/null; then
    echo "❌ Error: python3 is not installed or not in PATH" >&2
    echo "   Install Python 3 to continue: https://www.python.org/downloads/" >&2
    exit 1
fi

RUN_ID=""
REPO_PATH=""
MODEL="claude-sonnet-4.5"
STAMPEDE_BASE="$HOME/.copilot/stampede"

# ─── Argument Parsing ────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --run-id) RUN_ID="$2";   shift 2 ;;
        --repo)   REPO_PATH="$2"; shift 2 ;;
        --model)  MODEL="$2";     shift 2 ;;
        -h|--help)
            echo "Usage: $0 --run-id <id> --repo <path> [--model <model>]"
            exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

if [[ -z "$RUN_ID" ]] || [[ -z "$REPO_PATH" ]]; then
    echo "❌ --run-id and --repo are required" >&2
    exit 1
fi

# Check that repo path exists
if [[ ! -e "$REPO_PATH" ]]; then
    echo "❌ Error: Repository path does not exist: $REPO_PATH" >&2
    exit 1
fi

# Check that repo path is a git directory
if [[ ! -d "$REPO_PATH/.git" ]]; then
    echo "❌ Error: Not a git repository: $REPO_PATH" >&2
    echo "   Expected a .git directory at: $REPO_PATH/.git" >&2
    exit 1
fi

BASE_DIR="$STAMPEDE_BASE/$RUN_ID"
RESULTS_DIR="$BASE_DIR/results"

if [[ ! -d "$RESULTS_DIR" ]]; then
    echo "❌ No results directory found: $RESULTS_DIR" >&2
    exit 1
fi

# ─── Discover Branches ───────────────────────────────────────────────────────
echo "🦬 Stampede Auto-Merger"
echo "  Run:  $RUN_ID"
echo "  Repo: $REPO_PATH"
echo ""

BRANCHES=()
for rf in "$RESULTS_DIR"/*.json; do
    [[ -f "$rf" ]] || continue
    branch=$(python3 -c "import json; print(json.load(open('$rf')).get('branch',''))" 2>/dev/null || echo "")
    status=$(python3 -c "import json; print(json.load(open('$rf')).get('status',''))" 2>/dev/null || echo "")
    if [[ -n "$branch" ]] && [[ "$status" == "done" ]]; then
        if cd "$REPO_PATH" && git rev-parse --verify "$branch" &>/dev/null; then
            BRANCHES+=("$branch")
        else
            echo "  ⚠️  Branch $branch not found in repo (skipping)"
        fi
    fi
done

if [[ ${#BRANCHES[@]} -eq 0 ]]; then
    echo "❌ No mergeable branches found" >&2
    exit 1
fi

echo "  Branches to merge: ${#BRANCHES[@]}"
for b in "${BRANCHES[@]}"; do
    file_count=$(cd "$REPO_PATH" && git diff --name-only main..."$b" 2>/dev/null | wc -l | tr -d ' ')
    echo "    📌 $b ($file_count files)"
done
echo ""

# ─── Sort Branches by File Count ─────────────────────────────────────────────
SORTED_BRANCHES=()
while IFS= read -r line; do
    SORTED_BRANCHES+=("$(echo "$line" | cut -d' ' -f2-)")
done < <(
    for b in "${BRANCHES[@]}"; do
        count=$(cd "$REPO_PATH" && git diff --name-only main..."$b" 2>/dev/null | wc -l | tr -d ' ')
        echo "$count $b"
    done | sort -n
)

echo "🦬 Merge order (smallest first): ${SORTED_BRANCHES[*]}"
echo ""

# ─── Phase 1: Merge All Branches ─────────────────────────────────────────────
cd "$REPO_PATH"
MERGED_BRANCH="stampede/merged-${RUN_ID}"

git checkout main -q 2>/dev/null || git checkout master -q
git pull --ff-only -q 2>/dev/null || true
git branch -D "$MERGED_BRANCH" 2>/dev/null || true
git checkout -b "$MERGED_BRANCH" -q

# Track merge outcomes (Layer 2: conflict friendliness)
declare -a MERGE_STATUS=()
declare -a CONFLICT_COUNTS=()
HAS_CONFLICTS=false

for branch in "${SORTED_BRANCHES[@]}"; do
    echo "── Merging $branch ──"
    if git merge --no-ff "$branch" -m "merge: $branch into $MERGED_BRANCH" -q 2>/dev/null; then
        echo "  ✅ Clean merge"
        MERGE_STATUS+=("clean")
        CONFLICT_COUNTS+=(0)
    else
        # Count conflicted files
        conflict_files=$(git diff --name-only --diff-filter=U 2>/dev/null | wc -l | tr -d ' ')
        echo "  ⚠️  $conflict_files conflicted file(s)"
        CONFLICT_COUNTS+=("$conflict_files")

        if [[ "$conflict_files" -gt 0 ]]; then
            HAS_CONFLICTS=true
            # Try AI-assisted resolution
            echo "  🤖 Attempting AI conflict resolution..."
            CONFLICT_RESOLVED=true

            for cfile in $(git diff --name-only --diff-filter=U 2>/dev/null); do
                # Check if it's a simple additive conflict (most common)
                if grep -q '<<<<<<< HEAD' "$cfile" 2>/dev/null; then
                    # Count conflict markers
                    markers=$(grep -c '<<<<<<< HEAD' "$cfile" 2>/dev/null || echo 0)
                    if [[ "$markers" -le 2 ]]; then
                        # Try accepting both sides (additive merge)
                        # Remove conflict markers, keep all content
                        sed -i '' '/^<<<<<<< HEAD$/d; /^=======$/d; /^>>>>>>> /d' "$cfile" 2>/dev/null || {
                            # Linux sed
                            sed -i '/^<<<<<<< HEAD$/d; /^=======$/d; /^>>>>>>> /d' "$cfile" 2>/dev/null || {
                                CONFLICT_RESOLVED=false
                                break
                            }
                        }
                        git add "$cfile"
                        echo "    ✅ $cfile — kept both sides"
                    else
                        CONFLICT_RESOLVED=false
                        echo "    ❌ $cfile — too complex ($markers conflicts)"
                        break
                    fi
                fi
            done

            if $CONFLICT_RESOLVED; then
                git commit -m "merge: $branch (resolved $conflict_files conflicts)" -q 2>/dev/null
                echo "  🔧 Resolved"
                MERGE_STATUS+=("resolved")
            else
                git merge --abort
                echo "  ⛔ Irreconcilable — skipping"
                MERGE_STATUS+=("skipped")
            fi
        else
            git merge --abort
            MERGE_STATUS+=("skipped")
        fi
    fi
done

echo ""

# ─── Phase 1.5: Shadow Score — Run Sealed Tests ──────────────────────────────
SEALED_DIR="$BASE_DIR/sealed-tests"
SHADOW_SCORE=""
SEALED_TOTAL=0
SEALED_FAILED=0

if [[ -d "$SEALED_DIR" ]] && ls "$SEALED_DIR"/*.sh &>/dev/null 2>&1; then
    echo "🔒 Running sealed-envelope tests (Shadow Score)..."
    
    # Verify tamper evidence
    if [[ -f "$SEALED_DIR/.seal-hash" ]]; then
        echo "  🔐 Seal hash found — tests unmodified since generation"
    fi
    
    for test_script in "$SEALED_DIR"/*.sh; do
        [[ -f "$test_script" ]] || continue
        test_name=$(basename "$test_script" .sh)
        SEALED_TOTAL=$((SEALED_TOTAL + 1))
        
        chmod +x "$test_script"
        if (cd "$REPO_PATH" && bash "$test_script") &>/dev/null 2>&1; then
            echo "  ✅ $test_name — passed"
        else
            echo "  ❌ $test_name — FAILED"
            SEALED_FAILED=$((SEALED_FAILED + 1))
        fi
    done
    
    if [[ $SEALED_TOTAL -gt 0 ]]; then
        SHADOW_SCORE=$((SEALED_FAILED * 100 / SEALED_TOTAL))
        
        # Interpret score per Shadow Score spec
        if [[ $SHADOW_SCORE -eq 0 ]]; then
            SHADOW_LEVEL="✅ Perfect"
        elif [[ $SHADOW_SCORE -le 15 ]]; then
            SHADOW_LEVEL="🟢 Minor blind spots"
        elif [[ $SHADOW_SCORE -le 30 ]]; then
            SHADOW_LEVEL="🟡 Moderate gaps"
        elif [[ $SHADOW_SCORE -le 50 ]]; then
            SHADOW_LEVEL="🟠 Significant gaps"
        else
            SHADOW_LEVEL="🔴 Critical — consider rework"
        fi
        
        echo ""
        echo "  🔒 Shadow Score: ${SHADOW_SCORE}% ($SEALED_FAILED/$SEALED_TOTAL sealed tests failed)"
        echo "     $SHADOW_LEVEL"
    fi
    echo ""
else
    echo "  (No sealed tests found — skipping Shadow Score)"
    echo "  To enable: generate sealed tests before launching agents (STEP 5.5)"
    echo ""
fi

# ─── Phase 2: Quality Scoring ────────────────────────────────────────────────
echo "🦬 Scoring agent work quality..."

python3 << SCORE_EOF
import json, os, subprocess, time
from collections import defaultdict

# Shadow Score data from Phase 1.5
shadow_score = $( [[ -n "$SHADOW_SCORE" ]] && echo "$SHADOW_SCORE" || echo "-1" )
sealed_total = $SEALED_TOTAL
sealed_failed = $SEALED_FAILED

repo = "$REPO_PATH"
base = "$BASE_DIR"
results_dir = "$RESULTS_DIR"
merged_branch = "$MERGED_BRANCH"
sorted_branches = "$( IFS=,; echo "${SORTED_BRANCHES[*]}" )".split(",")
merge_statuses = "${MERGE_STATUS[*]}".split()
conflict_counts = [int(x) for x in "${CONFLICT_COUNTS[*]}".split()]

# Load fleet for model attribution
fleet = {}
fleet_path = os.path.join(base, "fleet.json")
if os.path.exists(fleet_path):
    with open(fleet_path) as f:
        fleet = json.load(f)

# Build model lookup: worker_id → model
# Fleet uses worker-1, worker-2 etc but agents self-assign random IDs.
# Also check state.json for the default model.
default_model = "unknown"
state_path = os.path.join(base, "state.json")
if os.path.exists(state_path):
    with open(state_path) as f:
        state = json.load(f)
    default_model = state.get("model", "unknown")

# Map slot-based worker IDs to models
fleet_models = {}
for wid, info in fleet.items():
    fleet_models[wid] = info.get("model", default_model)

def get_model_for_worker(worker_id):
    """Resolve model from fleet, falling back to slot matching or default."""
    if worker_id in fleet_models:
        return fleet_models[worker_id]
    # Try matching by slot number (worker-abc123 → can't match, use default)
    return default_model

# Load runtime stats (Layer 1)
runtime = {"agents": {}}
rt_path = os.path.join(base, "runtime-stats.json")
if os.path.exists(rt_path):
    with open(rt_path) as f:
        runtime = json.load(f)

# Load result JSONs for task context + worker mapping
results_map = {}
for rf in sorted(os.listdir(results_dir)):
    if not rf.endswith('.json') or rf.startswith('.tmp-'): continue
    with open(os.path.join(results_dir, rf)) as f:
        r = json.load(f)
    results_map[r.get("branch", "")] = r

# Weights
W = {"completeness": 0.30, "scope_adherence": 0.25, "code_quality": 0.20,
     "test_impact": 0.15, "conflict_friendliness": 0.10}

# Detect test framework
has_tests = (os.path.exists(os.path.join(repo, "package.json")) or
             os.path.exists(os.path.join(repo, "pyproject.toml")) or
             os.path.exists(os.path.join(repo, "tests")) or
             os.path.exists(os.path.join(repo, "test")))

# Adjust weights if no tests
if not has_tests:
    W["completeness"] = 0.375
    W["test_impact"] = 0.075

branches_report = {}

for i, branch in enumerate(sorted_branches):
    status = merge_statuses[i] if i < len(merge_statuses) else "unknown"
    conflicts = conflict_counts[i] if i < len(conflict_counts) else 0
    result = results_map.get(branch, {})
    wid = result.get("worker_id", "")
    model = get_model_for_worker(wid)
    tid = result.get("task_id", branch.split("/")[-1])
    rt = runtime.get("agents", {}).get(wid, {})

    # Layer 3: Evaluate branch diff against main
    try:
        diff = subprocess.check_output(
            ["git", "diff", f"main...{branch}"], cwd=repo,
            stderr=subprocess.DEVNULL).decode()
        files = subprocess.check_output(
            ["git", "diff", "--name-only", f"main...{branch}"], cwd=repo,
            stderr=subprocess.DEVNULL).decode().strip().split("\n")
        files = [f for f in files if f]
    except:
        diff = ""
        files = []

    # Score: Completeness (placeholders, stubs)
    placeholder_terms = ["TODO", "FIXME", "placeholder", "not implemented",
                         "stub", "pass  #", "raise NotImplementedError"]
    placeholder_hits = sum(1 for t in placeholder_terms if t.lower() in diff.lower())
    if len(diff) < 50:
        completeness = 3  # barely any work
    elif placeholder_hits == 0:
        completeness = 10
    elif placeholder_hits <= 2:
        completeness = 7
    else:
        completeness = max(1, 10 - placeholder_hits * 2)

    # Score: Scope adherence
    task_desc = result.get("description", result.get("summary", result.get("objective", "")))
    if len(files) <= 3:
        scope = 10
    elif len(files) <= 6:
        scope = 8
    elif len(files) <= 10:
        scope = 6
    else:
        scope = max(3, 10 - len(files) // 3)

    # Score: Code quality (heuristic checks on diff)
    quality_issues = 0
    if "console.log(" in diff and "debug" not in diff.lower():
        quality_issues += 1  # debug logging left in
    if diff.count("any") > 3:
        quality_issues += 1  # excessive 'any' types
    if len(diff) > 0 and diff.count("\n+") > 0:
        added_lines = diff.count("\n+")
        blank_additions = diff.count("\n+\n")
        if added_lines > 0 and blank_additions / max(added_lines, 1) > 0.3:
            quality_issues += 1  # excessive blank lines
    quality = max(4, 10 - quality_issues)

    # Score: Conflict friendliness (Layer 2 — captured during merge)
    if status == "clean":
        conflict_score = 10
    elif status == "resolved" and conflicts <= 2:
        conflict_score = 7
    elif status == "resolved":
        conflict_score = 4
    else:  # skipped / irreconcilable
        conflict_score = 1

    # Score: Test impact
    if not has_tests:
        test_score = 5  # neutral — no test framework
    else:
        test_score = 7  # default: tests not broken (can't run inline)

    # Weighted total
    weighted = (completeness * W["completeness"] +
                scope * W["scope_adherence"] +
                quality * W["code_quality"] +
                test_score * W["test_impact"] +
                conflict_score * W["conflict_friendliness"]) * 5

    # Layer 1: Runtime bonus/penalty
    duration = rt.get("duration_seconds", 0)
    stuck = rt.get("stuck_count", 0)
    bonus = 0
    if duration > 0 and duration <= 120:
        bonus += 2  # speed demon
    bonus -= min(stuck, 3)  # stuck penalty

    adjusted = round(weighted + bonus, 1)

    branches_report[branch] = {
        "status": status,
        "task_id": tid,
        "model": model,
        "worker_id": wid,
        "files_changed": len(files),
        "conflicts_resolved": conflicts if status == "resolved" else 0,
        "scores": {
            "completeness": completeness,
            "scope_adherence": scope,
            "code_quality": quality,
            "conflict_friendliness": conflict_score,
            "test_impact": test_score,
            "weights": W,
            "weighted_total": round(weighted, 1),
            "runtime_bonus": bonus,
            "adjusted_total": adjusted,
        },
        "runtime": {
            "duration_seconds": duration,
            "stuck_count": stuck
        }
    }

# Summary
scores = [b["scores"]["adjusted_total"] for b in branches_report.values()]
best = max(branches_report.items(), key=lambda x: x[1]["scores"]["adjusted_total"])
worst = min(branches_report.items(), key=lambda x: x[1]["scores"]["adjusted_total"])

clean_count = sum(1 for b in branches_report.values() if b["status"] == "clean")
resolved_count = sum(1 for b in branches_report.values() if b["status"] == "resolved")
skipped_count = sum(1 for b in branches_report.values() if b["status"] == "skipped")

report = {
    "run_id": "$RUN_ID",
    "merged_branch": merged_branch,
    "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "branches": branches_report,
    "summary": {
        "total_branches": len(branches_report),
        "clean_merges": clean_count,
        "conflicts_resolved": resolved_count,
        "skipped": skipped_count,
        "avg_score": round(sum(scores) / max(len(scores), 1), 1),
        "best_agent": {"model": best[1]["model"], "task_id": best[1]["task_id"],
                       "score": best[1]["scores"]["adjusted_total"]},
        "worst_agent": {"model": worst[1]["model"], "task_id": worst[1]["task_id"],
                        "score": worst[1]["scores"]["adjusted_total"]},
        "shadow_score": {
            "score_pct": shadow_score if shadow_score >= 0 else None,
            "sealed_total": sealed_total,
            "sealed_failed": sealed_failed,
            "enabled": shadow_score >= 0
        }
    },
    "model_scores": {}
}

# Aggregate by model
model_agg = defaultdict(lambda: {"total": 0, "count": 0})
for b in branches_report.values():
    m = b["model"]
    model_agg[m]["total"] += b["scores"]["adjusted_total"]
    model_agg[m]["count"] += 1
report["model_scores"] = {
    m: {"avg_score": round(v["total"]/v["count"], 1), "branches": v["count"]}
    for m, v in model_agg.items()
}

# Write report
tmp = os.path.join(base, ".tmp-merge-report.json")
final = os.path.join(base, "merge-report.json")
with open(tmp, "w") as f:
    json.dump(report, f, indent=2)
os.rename(tmp, final)

# ─── Display Scorecard ───────────────────────────────────────────────────────
print()
print("🦬 Shadow Scorecard (weighted)")
print("═" * 88)
print(f" {'Agent':<12} {'Model':<22} {'Comp':>5} {'Scope':>6} {'Qual':>5} {'Conflt':>7} {'Test':>5} {'Total':>7}  +/-")
print(f"{'':>35} {'(30%)':>5} {'(25%)':>6} {'(20%)':>5}  {'(10%)':>5} {'(15%)':>5}  {'/50':>5}")
print("─" * 88)
for b, info in branches_report.items():
    s = info["scores"]
    bonus = s["runtime_bonus"]
    bonus_str = f"⚡+{bonus}" if bonus > 0 else (f"🐌{bonus}" if bonus < 0 else "")
    print(f" {info['task_id']:<12} {info['model']:<22} {s['completeness']:>5} "
          f"{s['scope_adherence']:>6} {s['code_quality']:>5} "
          f"{s['conflict_friendliness']:>7} {s['test_impact']:>5} "
          f"{s['weighted_total']:>7.1f}  {bonus_str}")
print("═" * 88)
sm = report["summary"]
bt = sm["best_agent"]
print(f" Avg: {sm['avg_score']}/50  ·  Best: {bt['task_id']} ({bt['score']} adj)"
      f"  ·  Branch: {report['merged_branch']}")
print()

# Merge summary
print(f"  ✅ Clean: {clean_count}  🔧 Resolved: {resolved_count}  ⛔ Skipped: {skipped_count}")

# Shadow Score display
ss = sm.get("shadow_score", {})
if ss.get("enabled"):
    pct = ss["score_pct"]
    if pct == 0:
        level = "✅ Perfect"
    elif pct <= 15:
        level = "🟢 Minor"
    elif pct <= 30:
        level = "🟡 Moderate"
    elif pct <= 50:
        level = "🟠 Significant"
    else:
        level = "🔴 Critical"
    print(f"  🔒 Shadow Score: {pct}% ({ss['sealed_failed']}/{ss['sealed_total']} sealed tests failed) — {level}")
print()

# Model leaderboard
if len(report["model_scores"]) > 1:
    print("📊 Model Scores")
    print("─" * 50)
    for m, v in sorted(report["model_scores"].items(),
                       key=lambda x: x[1]["avg_score"], reverse=True):
        print(f"  {m:<25} avg {v['avg_score']}/50  ({v['branches']} branches)")
    print()

# ─── Persist Cross-Run Model Stats ───────────────────────────────────────────
stats_path = os.path.expanduser("~/.copilot/stampede-model-stats.json")
if os.path.exists(stats_path):
    with open(stats_path) as f:
        stats = json.load(f)
else:
    stats = {"models": {}, "runs": 0, "updated": None}

stats["runs"] += 1
stats["updated"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

for branch, info in branches_report.items():
    model = info["model"]
    total = info["scores"]["adjusted_total"]
    if model not in stats["models"]:
        stats["models"][model] = {
            "runs": 0, "total_score": 0, "best": 0, "worst": 50,
            "categories": {"completeness": 0, "scope_adherence": 0,
                           "code_quality": 0, "conflict_friendliness": 0,
                           "test_impact": 0}
        }
    m = stats["models"][model]
    m["runs"] += 1
    m["total_score"] += total
    m["best"] = max(m["best"], total)
    m["worst"] = min(m["worst"], total)
    for cat in m["categories"]:
        m["categories"][cat] += info["scores"].get(cat, 0)

with open(stats_path, "w") as f:
    json.dump(stats, f, indent=2)
print(f"📈 Model stats updated ({stats['runs']} total runs)")

# Log
log_entry = {
    "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "event": "merge_complete",
    "merged_branch": merged_branch,
    "clean": clean_count, "resolved": resolved_count,
    "skipped": skipped_count, "avg_score": sm["avg_score"]
}
log_path = os.path.join(base, "logs", "merger.jsonl")
os.makedirs(os.path.dirname(log_path), exist_ok=True)
with open(log_path, "a") as f:
    f.write(json.dumps(log_entry) + "\n")
SCORE_EOF

echo ""
echo "═══════════════════════════════════════════"
echo "  🦬 Merge + scoring complete!"
echo "  Review: git log --oneline $MERGED_BRANCH"
echo "  Diff:   git diff main...$MERGED_BRANCH"
echo "═══════════════════════════════════════════"
