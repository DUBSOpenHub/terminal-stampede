#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

# stampede.sh — Launcher for Terminal Stampede agent fleet
# Creates a tmux session with one pane per agent + a monitor pane.
# Usage:
#   stampede.sh --run-id <id> --count <n> --repo <path> [--model <model>]
#   stampede.sh --teardown --run-id <id>

# ─── Defaults ────────────────────────────────────────────────────────────────
RUN_ID=""
WORKER_COUNT=3
REPO_PATH=""
MODEL="claude-haiku-4.5"
MODELS=""  # comma-separated list for multi-model rotation
TEARDOWN=false
NO_ATTACH=false
DRY_RUN=false
PREFLIGHT=false
AGENT_CMD=""  # Custom CLI agent command (default: GitHub Copilot CLI)
# Run directory lives INSIDE the repo (.stampede/) so agents can access it.
# Content exclusion policies block ~/.copilot/ but repos are always accessible.
STAMPEDE_BASE=""  # set after REPO_PATH is known

# ─── Argument Parsing ────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --run-id)    RUN_ID="$2";       shift 2 ;;
        --count)     WORKER_COUNT="$2"; shift 2 ;;
        --repo)      REPO_PATH="$2";    shift 2 ;;
        --model)     MODEL="$2";        shift 2 ;;
        --models)    MODELS="$2";       shift 2 ;;
        --teardown)  TEARDOWN=true;     shift   ;;
        --no-attach) NO_ATTACH=true;    shift   ;;
        --dry-run)   DRY_RUN=true;      shift   ;;
        --preflight) PREFLIGHT=true;    shift   ;;
        --agent-cmd) AGENT_CMD="$2";    shift 2 ;;
        -h|--help)
            echo "Usage: $0 --run-id <id> --count <n> --repo <path> [--model <model>] [--models m1,m2,m3]"
            echo ""
            echo "Options:"
            echo "  --run-id <id>      Run identifier (format: run-YYYYMMDD-HHMMSS)"
            echo "  --count <n>        Number of workers (default: 3)"
            echo "  --repo <path>      Repository path (must be a git repo)"
            echo "  --model <model>    AI model to use (default: claude-haiku-4.5)"
            echo "  --models <list>    Comma-separated models for rotation"
            echo "  --teardown         Stop the session and cleanup"
            echo "  --no-attach        Don't auto-attach to tmux session"
            echo "  --dry-run          Show what would run without creating the session"
            echo "  --preflight        Test that agents can access the queue before launching"
            echo "  --agent-cmd <cmd>  Custom CLI agent command template (default: GitHub Copilot CLI)"
            echo "                     Use {prompt} and {model} as placeholders."
            echo "                     Example: --agent-cmd 'claude -p \"{prompt}\"'"
            echo "  -h, --help         Show this help"
            exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# ─── Process Tree Walker ─────────────────────────────────────────────────────
# Landmine #16: pane PID != worker PID; walk tree to leaf.
find_leaf_pid() {
    local pid="$1"
    local child
    while true; do
        child="$(pgrep -P "$pid" 2>/dev/null | head -n1 || true)"
        [[ -z "$child" ]] && break
        pid="$child"
    done
    echo "$pid"
}

# ─── 8-Prerequisite Validation ───────────────────────────────────────────────
# Landmine #22: missing prereqs cause silent fleet no-ops.
check_prereqs() {
    local fail=0
    local bins=(tmux python3 jq openssl git bash)
    local optional_bins=(watch gh)

    for bin in "${bins[@]}"; do
        if command -v "$bin" &>/dev/null; then
            echo "  ✅ $bin"
        else
            echo "  ❌ $bin — MISSING" >&2
            fail=1
        fi
    done

    for bin in "${optional_bins[@]}"; do
        if command -v "$bin" &>/dev/null; then
            echo "  ✅ $bin (optional)"
        else
            echo "  ⚠️  $bin — not found (monitor pane will be skipped)"
        fi
    done

    # gh copilot is optional — only needed if using Copilot CLI as the agent
    if [[ -z "$AGENT_CMD" ]]; then
        if command -v gh &>/dev/null; then
            if gh copilot --help &>/dev/null 2>&1; then
                echo "  ✅ gh copilot extension (default agent)"
            else
                echo "  ⚠️  gh copilot extension not found (install with: gh extension install github/gh-copilot)"
                echo "     Or use --agent-cmd to specify a different CLI agent"
            fi
        else
            echo "  ⚠️  gh — not found (needed for default Copilot CLI agent, or use --agent-cmd)"
        fi
    else
        echo "  ✅ Custom agent command configured"
    fi

    if [[ "$fail" -eq 1 ]]; then
        echo "Prerequisite check failed. Install missing tools." >&2
        exit 1
    fi
    echo "All prerequisites satisfied."
}

# ─── Teardown ─────────────────────────────────────────────────────────────────
# Landmine #24: teardown must target session-specific PIDs only.
do_teardown() {
    if [[ -z "$RUN_ID" ]]; then
        echo "ERROR: --run-id required for teardown" >&2
        exit 1
    fi

    local session_name="stampede-${RUN_ID}"
    # Search for run dir in repo (.stampede/) or legacy (~/.copilot/stampede/)
    local base_dir=""
    if [[ -n "$REPO_PATH" ]] && [[ -d "$REPO_PATH/.stampede/${RUN_ID}" ]]; then
        base_dir="$REPO_PATH/.stampede/${RUN_ID}"
    elif [[ -d "$REPO_PATH/.stampede/${RUN_ID}" ]]; then
        base_dir="$REPO_PATH/.stampede/${RUN_ID}"
    elif [[ -d "$HOME/.copilot/stampede/${RUN_ID}" ]]; then
        base_dir="$HOME/.copilot/stampede/${RUN_ID}"
    elif [[ -d "$HOME/.stampede/${RUN_ID}" ]]; then
        base_dir="$HOME/.stampede/${RUN_ID}"
    fi

    echo "Tearing down stampede session: $session_name"

    if [[ -d "$base_dir/pids" ]]; then
        for pidfile in "$base_dir/pids"/*.pid; do
            [[ -f "$pidfile" ]] || continue
            local wpid
            wpid=$(cat "$pidfile" 2>/dev/null || true)
            if [[ -n "$wpid" ]]; then
                if kill -0 "$wpid" 2>/dev/null; then
                    kill "$wpid" 2>/dev/null || true
                    echo "  ✓ Stopped worker PID $wpid"
                fi
            fi
        done
        rm -f "$base_dir/pids"/*.pid 2>/dev/null
        echo "  ✓ Cleaned PID files"
    fi

    if tmux has-session -t "$session_name" 2>/dev/null; then
        tmux kill-session -t "$session_name"
        echo "  ✓ Terminated tmux session $session_name"
    else
        echo "  ⚠ No tmux session $session_name found"
    fi

    if [[ -f "$base_dir/state.json" ]]; then
        python3 -c "
import json, time
p = '$base_dir/state.json'
with open(p) as f: state = json.load(f)
state['phase'] = 'torn_down'
state['updated_at'] = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
with open(p, 'w') as f: json.dump(state, f, indent=2)
"
        echo "  ✓ Updated state.json → torn_down"
    fi

    echo "Teardown complete."
    exit 0
}

# ─── Preflight Check ─────────────────────────────────────────────────────────
# Verifies agents can actually read the queue by spawning a test agent.
do_preflight() {
    echo ""
    echo "🦬 Preflight Check"
    echo "═══════════════════════════════════════════"
    local fail=0

    # 1. Prerequisites
    echo "  ── Prerequisites ──"
    check_prereqs

    # 2. Run directory
    echo ""
    echo "  ── Run Directory ──"
    if [[ -d "$BASE_DIR/queue" ]]; then
        local tc
        tc=$(find "$BASE_DIR/queue" -name '*.json' -type f 2>/dev/null | wc -l | tr -d ' ')
        echo "  ✅ Queue exists ($tc tasks)"
    else
        echo "  ❌ Queue not found: $BASE_DIR/queue"
        fail=1
    fi

    # 3. Git repo
    echo ""
    echo "  ── Repository ──"
    if git -C "$REPO_PATH" rev-parse --git-dir &>/dev/null; then
        local branch
        branch=$(git -C "$REPO_PATH" rev-parse --abbrev-ref HEAD 2>/dev/null)
        echo "  ✅ Git repo on branch: $branch"
    else
        echo "  ❌ Not a git repo: $REPO_PATH"
        fail=1
    fi

    # 4. Agent access test — the critical check
    echo ""
    echo "  ── Agent Access (content exclusion test) ──"
    # Write a canary file in the queue, ask the agent to read it
    local canary="$BASE_DIR/queue/.preflight-canary"
    echo "stampede-preflight-ok" > "$canary"

    local agent_output
    if [[ -n "$AGENT_CMD" ]]; then
        echo "  ⚠️  Custom agent command — skipping automated access test"
        echo "     Verify your agent can read: $BASE_DIR/queue/"
        rm -f "$canary"
    else
        agent_output=$(cd "$REPO_PATH" && gh copilot -- \
            --agent stampede-agent \
            --model "${MODEL}" \
            --allow-all-tools \
            --autopilot \
            --max-autopilot-continues 2 \
            --no-ask-user \
            -p "Read the file at $canary and print its contents. Only print the file contents, nothing else." 2>&1 | head -20)

        rm -f "$canary"

        if echo "$agent_output" | grep -q "stampede-preflight-ok"; then
            echo "  ✅ Agent can read queue directory"
        elif echo "$agent_output" | grep -qi "permission denied\|content exclusion"; then
            echo "  ❌ Agent BLOCKED by content exclusion policy"
            echo "     The queue is at: $BASE_DIR"
            echo "     Agents cannot read files outside the repo."
            echo ""
            echo "  💡 Fix: ensure .stampede/ is inside the repo (not ~/.copilot/)"
            fail=1
        else
            echo "  ⚠️  Agent response unclear — check manually:"
            echo "$agent_output" | head -5 | sed 's/^/     /'
        fi
    fi

    # 5. Model availability
    echo ""
    echo "  ── Model ──"
    if echo "$agent_output" | grep -qi "invalid\|not found\|not available"; then
        echo "  ❌ Model '$MODEL' may not be available"
        fail=1
    else
        echo "  ✅ Model: $MODEL"
    fi

    # Result
    echo ""
    echo "═══════════════════════════════════════════"
    if [[ $fail -eq 0 ]]; then
        echo "  ✅ PREFLIGHT PASSED — ready to stampede"
    else
        echo "  ❌ PREFLIGHT FAILED — fix issues above"
    fi
    echo "═══════════════════════════════════════════"
    exit $fail
}

# ─── Main ─────────────────────────────────────────────────────────────────────

if ! $DRY_RUN && ! $PREFLIGHT; then
    echo "Checking prerequisites..."
    check_prereqs
fi

if $TEARDOWN; then
    do_teardown
fi

if [[ -z "$RUN_ID" ]]; then
    echo "ERROR: --run-id is required" >&2
    exit 1
fi

if [[ -z "$REPO_PATH" ]]; then
    echo "ERROR: --repo is required" >&2
    exit 1
fi

# Validate run_id format (Landmine #20)
if ! [[ "$RUN_ID" =~ ^run-[0-9]{8}-[0-9]{6}$ ]]; then
    echo "ERROR: Invalid --run-id format: $RUN_ID (expected run-YYYYMMDD-HHMMSS)" >&2
    exit 1
fi

if ! [[ "$WORKER_COUNT" =~ ^[0-9]+$ ]] || [[ "$WORKER_COUNT" -lt 1 ]]; then
    echo "ERROR: --count must be integer >= 1" >&2
    exit 1
fi

if [[ ! -d "$REPO_PATH/.git" ]] && ! git -C "$REPO_PATH" rev-parse --git-dir &>/dev/null; then
    echo "ERROR: --repo must be a git repository: $REPO_PATH" >&2
    exit 1
fi

# Run directory inside the repo — agents can always access repo files
STAMPEDE_BASE="$REPO_PATH/.stampede"
BASE_DIR="${STAMPEDE_BASE}/${RUN_ID}"
SESSION_NAME="stampede-${RUN_ID}"
PIDS_DIR="${BASE_DIR}/pids"

# Preflight mode: test agent access and exit
if $PREFLIGHT; then
    do_preflight
fi

# Count tasks (for both dry-run and live run)
if [[ -d "${BASE_DIR}/queue" ]]; then
    TASK_COUNT=$(find "${BASE_DIR}/queue" -name '*.json' -type f 2>/dev/null | wc -l | tr -d ' ')
else
    TASK_COUNT=0
fi

# Dry-run mode: print config and exit
if $DRY_RUN; then
    echo "════════════════════════════════════════════════════════"
    echo "  🦬 STAMPEDE DRY RUN"
    echo "════════════════════════════════════════════════════════"
    echo ""
    echo "  Run ID:       $RUN_ID"
    echo "  Repo:         $REPO_PATH"
    echo "  Worker Count: $WORKER_COUNT"
    
    IFS=',' read -ra MODEL_LIST_PREVIEW <<< "${MODELS:-$MODEL}"
    if [[ ${#MODEL_LIST_PREVIEW[@]} -gt 1 ]]; then
        echo "  Models:       ${MODEL_LIST_PREVIEW[*]} (rotating)"
    else
        echo "  Model:        ${MODEL_LIST_PREVIEW[0]}"
    fi
    
    echo "  Tasks:        $TASK_COUNT"
    echo "  Session:      $SESSION_NAME"
    echo "  Base Dir:     $BASE_DIR"
    echo ""
    
    if [[ ! -d "$BASE_DIR" ]]; then
        echo "  ⚠️  Run directory does not exist: $BASE_DIR"
    elif [[ "$TASK_COUNT" -eq 0 ]]; then
        echo "  ⚠️  No tasks in queue"
    else
        echo "  ✅ Run directory exists with $TASK_COUNT tasks ready"
    fi
    
    echo ""
    echo "  Would create tmux session with:"
    for ((i = 1; i <= WORKER_COUNT; i++)); do
        worker_model_idx=$(( (i - 1) % ${#MODEL_LIST_PREVIEW[@]} ))
        worker_model="${MODEL_LIST_PREVIEW[$worker_model_idx]}"
        echo "    • Worker $i → $worker_model"
    done
    echo ""
    echo "════════════════════════════════════════════════════════"
    exit 0
fi

if [[ ! -d "$BASE_DIR" ]]; then
    echo "ERROR: Run directory not found: $BASE_DIR" >&2
    exit 1
fi

if [[ "$TASK_COUNT" -eq 0 ]]; then
    echo "ERROR: No tasks in queue (${BASE_DIR}/queue)" >&2
    exit 1
fi

mkdir -p "$PIDS_DIR"

# Prevent duplicate sessions (Landmine #12)
if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    echo "⚠ Existing session $SESSION_NAME found. Tearing down for fresh launch."
    tmux kill-session -t "$SESSION_NAME"
    sleep 1
fi

# ─── Model Rotation ──────────────────────────────────────────────────────────
# Parse --models into an array for per-worker model assignment
IFS=',' read -ra MODEL_LIST <<< "${MODELS:-$MODEL}"
MODEL_COUNT=${#MODEL_LIST[@]}

echo "Launching stampede fleet: $WORKER_COUNT workers"
echo "  Run ID:  $RUN_ID"
echo "  Repo:    $REPO_PATH"
echo "  Tasks:   $TASK_COUNT"
echo "  Session: $SESSION_NAME"
if [[ $MODEL_COUNT -gt 1 ]]; then
    echo "  Models:  ${MODEL_LIST[*]} (rotating across $WORKER_COUNT workers)"
else
    echo "  Model:   ${MODEL_LIST[0]} × $WORKER_COUNT"
fi
echo ""

# Write fleet.json so the monitor knows which model each worker runs
python3 -c "
import json
models = '${MODELS:-$MODEL}'.split(',')
fleet = {}
for i in range(1, ${WORKER_COUNT} + 1):
    m = models[(i - 1) % len(models)]
    fleet[f'worker-{i}'] = {'model': m, 'slot': i}
with open('${BASE_DIR}/fleet.json', 'w') as f:
    json.dump(fleet, f, indent=2)
"

get_worker_model() {
    local worker_num="$1"
    local idx=$(( (worker_num - 1) % MODEL_COUNT ))
    echo "${MODEL_LIST[$idx]}"
}

# ─── Build Worker Command ────────────────────────────────────────────────────
build_worker_script() {
    local worker_num="$1"
    local worker_model
    worker_model=$(get_worker_model "$worker_num")
    local script="${BASE_DIR}/scripts/agent-${worker_num}.sh"
    local prompt="You are stampede agent #${worker_num} for run ${RUN_ID}. FOLLOW YOUR AGENT INSTRUCTIONS EXACTLY. Claim ONE task at a time from ${BASE_DIR}/queue/ via atomic mv to ${BASE_DIR}/claimed/. Fully complete each task before claiming the next. Write results atomically to ${BASE_DIR}/results/. Log to ${BASE_DIR}/logs/. Your repo is ${REPO_PATH}. Work until queue is empty then exit."

    cat > "$script" << AGENTEOF
#!/usr/bin/env bash
cd ${REPO_PATH}
echo '⚡ ${worker_model} · Claiming task...'
AGENTEOF

    if [[ -n "$AGENT_CMD" ]]; then
        local cmd="${AGENT_CMD}"
        cmd="${cmd//\{prompt\}/$prompt}"
        cmd="${cmd//\{model\}/$worker_model}"
        echo "$cmd" >> "$script"
    else
        cat >> "$script" << AGENTEOF
gh copilot -- \\
  --agent stampede-agent \\
  --model ${worker_model} \\
  --allow-all-tools \\
  --autopilot \\
  --max-autopilot-continues 30 \\
  --no-ask-user \\
  -p "${prompt}"
AGENTEOF
    fi

    cat >> "$script" << 'AGENTEOF'
echo '⚡ Done.'
sleep 86400
AGENTEOF
    chmod +x "$script"
    echo "$script"
}

# ─── Create tmux Session with Monitor as pane 0 (top-left) ───────────────────

# Enable remain-on-exit so crashed panes stay visible for debugging
tmux_create_session() {
    tmux new-session -d -s "$SESSION_NAME" -x 220 -y 50 "$1"
    tmux set-option -t "$SESSION_NAME" remain-on-exit on 2>/dev/null || true
}

# Monitor pane starts the session (ensures top-left position)
if [[ -x "$HOME/bin/stampede-monitor.sh" ]]; then
MONITOR_CMD="$HOME/bin/stampede-monitor.sh ${RUN_ID} ${BASE_DIR}"
tmux_create_session "$MONITOR_CMD"
elif command -v watch &>/dev/null; then
MONITOR_CMD="watch -n5 'printf \"\033[1;33m\"; \
     echo \"╔══════════════════════════════════════════════════════╗\"; \
     echo \"║  📊 STAMPEDE MONITOR                                ║\"; \
     echo \"║  🏷️  RUN: ${RUN_ID}                  ║\"; \
     echo \"║  📂 REPO: $(basename ${REPO_PATH})                                ║\"; \
     echo \"╚══════════════════════════════════════════════════════╝\"; \
     printf \"\033[0m\"; echo; \
     echo \"📋 Queued:  \$(find ${BASE_DIR}/queue -name *.json -type f 2>/dev/null | wc -l | tr -d \" \")\"; \
     echo \"🔧 Claimed: \$(find ${BASE_DIR}/claimed -name *.json -type f 2>/dev/null | wc -l | tr -d \" \")\"; \
     echo \"✅ Done:    \$(find ${BASE_DIR}/results -name *.json -not -name .tmp-* -type f 2>/dev/null | wc -l | tr -d \" \")\"; \
     echo; echo \"── Task Assignments ──\"; \
     for cf in ${BASE_DIR}/claimed/*.json; do \
         [ -f \"\$cf\" ] || continue; \
         tid=\$(python3 -c \"import json; print(json.load(open(\\\"\$cf\\\")).get(\\\"task_id\\\",\\\"?\"))\" 2>/dev/null); \
         who=\$(python3 -c \"import json; print(json.load(open(\\\"\$cf\\\")).get(\\\"claimed_by\\\",\\\"?\"))\" 2>/dev/null); \
         ttl=\$(python3 -c \"import json; print(json.load(open(\\\"\$cf\\\")).get(\\\"title\\\",\\\"?\"))\" 2>/dev/null); \
         echo \"  🔧 \$tid → \$who: \$ttl\"; \
     done; \
     for rf in ${BASE_DIR}/results/*.json; do \
         [ -f \"\$rf\" ] || { echo \"  (none yet)\"; break; }; \
         tid=\$(python3 -c \"import json; print(json.load(open(\\\"\$rf\\\")).get(\\\"task_id\\\",\\\"?\"))\" 2>/dev/null); \
         echo \"  ✅ \$tid — complete\"; \
     done; \
     echo; echo \"── Workers ──\"; \
     for pf in ${PIDS_DIR}/worker-*.pid; do \
         [ -f \"\$pf\" ] || continue; \
         wid=\$(basename \"\$pf\" .pid); \
         wpid=\$(cat \"\$pf\"); \
         if kill -0 \"\$wpid\" 2>/dev/null; then \
             echo \"  🟢 \$wid (PID \$wpid) — alive\"; \
         else \
             echo \"  🔴 \$wid (PID \$wpid) — dead\"; \
         fi; \
     done; \
     echo; echo \"── Recent Logs ──\"; \
     tail -3 ${BASE_DIR}/logs/*.jsonl 2>/dev/null || echo \"  No logs yet\"; \
     echo; echo \"Updated: \$(date +%H:%M:%S)\"'"
tmux_create_session "$MONITOR_CMD"
else
FIRST_SCRIPT=$(build_worker_script 1)
tmux_create_session "$FIRST_SCRIPT"
fi

# Add worker panes
START_INDEX=1
if ! command -v watch &>/dev/null; then
    START_INDEX=2  # worker 1 is already pane 0
fi

for ((i = START_INDEX; i <= WORKER_COUNT; i++)); do
    WORKER_SCRIPT=$(build_worker_script "$i")
    tmux split-window -t "$SESSION_NAME" "$WORKER_SCRIPT"
    tmux select-layout -t "$SESSION_NAME" tiled 2>/dev/null || true
    sleep 1
done

# Set pane titles for border identification
# Bright cyan borders stand out from code output
tmux set-option -t "$SESSION_NAME" pane-border-status top 2>/dev/null || true
tmux set-option -t "$SESSION_NAME" pane-border-style "fg=colour240" 2>/dev/null || true
tmux set-option -t "$SESSION_NAME" pane-active-border-style "fg=colour51" 2>/dev/null || true
tmux set-option -t "$SESSION_NAME" pane-border-format \
    '#[fg=colour214,bold] ⚡ #{pane_title} #[default]' 2>/dev/null || true

# Name each pane — just model and task name, no "Agent #N"
PANE_IDX=0
if command -v watch &>/dev/null; then
    tmux select-pane -t "$SESSION_NAME:0.0" -T "📊 Monitor" 2>/dev/null || true
    PANE_IDX=1
fi

# Read task titles from queue to label each pane with its task
TASK_NAMES=()
for qf in $(ls -1 "${BASE_DIR}/queue/"*.json 2>/dev/null | sort); do
    tname=$(python3 -c "import json; print(json.load(open('$qf')).get('title','task'))" 2>/dev/null || echo "task")
    TASK_NAMES+=("$tname")
done

for ((i = 1; i <= WORKER_COUNT; i++)); do
    task_label="${TASK_NAMES[$((i-1))]:-task}"
    worker_model=$(get_worker_model "$i")
    tmux select-pane -t "$SESSION_NAME:0.${PANE_IDX}" \
        -T "Agent #${i} · ${worker_model} · ${task_label}" 2>/dev/null || true
    PANE_IDX=$((PANE_IDX + 1))
done

tmux select-layout -t "$SESSION_NAME" tiled 2>/dev/null || true

# ─── Note: --autopilot flag in agent scripts handles autonomous mode ──────────
# BTab (Shift+Tab) removed — it conflicts with --autopilot flag and kills agents

# ─── PID Capture with Process Tree Walking ────────────────────────────────────
# Landmine #16: walk process tree to find actual worker PIDs
echo "Capturing worker PIDs..."
sleep 5

WORKER_INDEX=0
for pane_pid in $(tmux list-panes -t "$SESSION_NAME" -F '#{pane_pid}'); do
    WORKER_INDEX=$((WORKER_INDEX + 1))

    if [[ "$WORKER_INDEX" -gt "$WORKER_COUNT" ]]; then
        break
    fi

    LEAF_PID=$(find_leaf_pid "$pane_pid")
    WORKER_TAG="worker-${WORKER_INDEX}"

    echo "$LEAF_PID" > "${PIDS_DIR}/${WORKER_TAG}.pid"
    echo "  Worker $WORKER_INDEX → PID $LEAF_PID (pane PID $pane_pid)"
done

# ─── Fleet Status Summary ────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════"
echo "  🦬 STAMPEDE FLEET LAUNCHED"
echo "═══════════════════════════════════════════"
echo ""

LAUNCHED=0
for pf in "${PIDS_DIR}"/worker-*.pid; do
    if [[ -f "$pf" ]]; then
        PID=$(cat "$pf")
        NAME=$(basename "$pf" .pid)
        if kill -0 "$PID" 2>/dev/null; then
            echo "  ✅ $NAME (PID $PID) — running"
            LAUNCHED=$((LAUNCHED + 1))
        else
            echo "  ❌ $NAME (PID $PID) — failed to start"
        fi
    fi
done

echo ""
echo "  Workers launched: $LAUNCHED / $WORKER_COUNT"
echo "  Tasks in queue:   $TASK_COUNT"
echo "  Monitor pane:     active (refreshes every 5s)"
echo "  Tmux session:     $SESSION_NAME"
echo ""
echo "  View:      tmux attach -t $SESSION_NAME"
echo "  Teardown:  $0 --teardown --run-id $RUN_ID"
echo ""
echo "═══════════════════════════════════════════"

# ─── Auto-Attach ──────────────────────────────────────────────────────────────
# Opens a new Terminal window attached to the tmux session so you can watch live.
# Use --no-attach to suppress (e.g., when called from an orchestrator skill).
if ! $NO_ATTACH; then
    ATTACHED=false
    if [[ "$(uname)" == "Darwin" ]]; then
        rm -f /tmp/stampede-attach-*.sh 2>/dev/null || true
        # Write task list to a temp file (avoids quoting issues with & in titles)
        TASK_FILE="/tmp/stampede-tasks-${RUN_ID}.txt"
        if [[ -d "${BASE_DIR}/queue" ]]; then
            (cd "${BASE_DIR}/queue" && for qf in *.json; do
                [ -f "$qf" ] || continue
                python3 -c "import json; t=json.load(open('$qf')); print(f\"  ▸ {t['task_id']}: {t['title']}\")" 2>/dev/null
            done) > "$TASK_FILE"
        fi
        ATTACH_SCRIPT="/tmp/stampede-attach-${RUN_ID}.sh"
        cat > "$ATTACH_SCRIPT" << ATTACHEOF
#!/usr/bin/env bash
clear
printf "\033[?25l"
trap 'printf "\033[?25h\033[0m"' EXIT

afplay /System/Library/Sounds/Blow.aiff 2>/dev/null &
osascript -e 'tell application "System Events" to tell process "Terminal" to set value of attribute "AXFullScreen" of window 1 to true' 2>/dev/null &

G="\033[38;5;220m"; GN="\033[38;5;46m"
MT="\033[38;5;240m"; TX="\033[38;5;252m"
B="\033[1m"; R="\033[0m"

printf "\${G}"
cat << 'ART'

       ╭━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━╮
       ┃                                                                 ┃
       ┃    t e r m i n a l                                              ┃
       ┃      _____ _                                   _                ┃
       ┃     / ____| |                                 | |               ┃
       ┃    | (___ | |_ __ _ _ __ ___  _ __   ___  __| | ___            ┃
       ┃     \___ \| __/ _\` | '_ \` _ \| '_ \ / _ \/ _\` |/ _ \           ┃
       ┃     ____) | || (_| | | | | | | |_) |  __/ (_| |  __/           ┃
       ┃    |_____/ \__\__,_|_| |_| |_| .__/ \___|\__,_|\___|           ┃
       ┃                               |_|                               ┃
       ┃                                                                 ┃
       ╰━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━╯
ART
printf "\${R}"
sleep 1

printf "\n  \${B}\${TX}🦬 ${WORKER_COUNT} agents · ${TASK_COUNT} tasks · $(basename ${REPO_PATH})\${R}\n\n"
sleep 0.5

if [[ -f "$TASK_FILE" ]] && [[ -s "$TASK_FILE" ]]; then
  cat "$TASK_FILE"
  printf "\n"
  sleep 1
fi

CHECKS=("Initializing fleet" "Loading ${TASK_COUNT} task manifests" "Spawning ${WORKER_COUNT} agents" "Connecting monitors" "Engaging stampede")
for c in "\${CHECKS[@]}"; do
  printf "  \${MT}[\${R}\${GN}✓\${R}\${MT}]\${R} \${TX}\${c}\${R}\n"
  sleep 0.3
done
sleep 0.3

printf "\n  "
BAR_W=50
for i in \$(seq 0 \$BAR_W); do
  PCT=\$((i * 100 / BAR_W))
  FILLED=\$(printf '█%.0s' \$(seq 1 \$((i+1))))
  EMPTY=""
  [[ \$i -lt \$BAR_W ]] && EMPTY=\$(printf '░%.0s' \$(seq 1 \$((BAR_W - i))))
  printf "\r  \${G}\${FILLED}\${R}\${MT}\${EMPTY}\${R} \${B}\${TX}\${PCT}%%\${R}"
  sleep 0.02
done
printf "\n"
sleep 0.3

printf "\n  \${B}\${GN}⚡ STAMPEDE ONLINE\${R}  \${MT}${WORKER_COUNT} agents deployed\${R}\n\n"
printf "  \${MT}Attaching in 3...\${R}"; sleep 1
printf "\r  \${MT}Attaching in 2...\${R}"; sleep 1
printf "\r  \${MT}Attaching in 1...\${R}"; sleep 1

printf "\033[?25h"
tmux attach -t $SESSION_NAME
ATTACHEOF
        chmod +x "$ATTACH_SCRIPT"
        open -a Terminal "$ATTACH_SCRIPT" 2>/dev/null && ATTACHED=true
    elif command -v gnome-terminal &>/dev/null; then
        gnome-terminal -- tmux attach -t "$SESSION_NAME" 2>/dev/null &
        ATTACHED=true
    elif command -v xterm &>/dev/null; then
        xterm -e "tmux attach -t $SESSION_NAME" 2>/dev/null &
        ATTACHED=true
    fi

    if $ATTACHED; then
        echo "📺 Opened Terminal attached to $SESSION_NAME"
    else
        echo ""
        echo "═══════════════════════════════════════════"
        echo "  👀 TO WATCH YOUR AGENTS WORK:"
        echo ""
        echo "  tmux attach -t $SESSION_NAME"
        echo ""
        echo "  (Ctrl-B z to zoom a pane, Ctrl-B d to detach)"
        echo "═══════════════════════════════════════════"
    fi
fi
