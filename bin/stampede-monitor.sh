#!/usr/bin/env bash
# stampede-monitor.sh — Live monitor for Terminal Stampede runs
# Shows progress, alerts on stuck agents, celebrates completion.
set -euo pipefail

RUN_ID="${1:?Usage: stampede-monitor.sh <run-id>}"
BASE="$HOME/.copilot/stampede/$RUN_ID"
PIDS_DIR="$BASE/pids"
TOTAL_TASKS=$(find "$BASE/queue" "$BASE/claimed" "$BASE/results" -name "*.json" -not -name ".tmp-*" -type f 2>/dev/null | wc -l | tr -d ' ')
STUCK_THRESHOLD=180  # seconds without progress = stuck
BELL=$'\a'
ALERTED_FILE="$BASE/.alerted"  # track which agents already belled
RUNTIME_STATS="$BASE/runtime-stats.json"  # Layer 1 shadow scoring data
STUCK_COUNTS="$BASE/.stuck-counts"  # track per-agent stuck events
touch "$ALERTED_FILE" 2>/dev/null || true
touch "$STUCK_COUNTS" 2>/dev/null || true

# Initialize runtime stats
python3 -c "
import json, os
stats_path = '$RUNTIME_STATS'
if not os.path.exists(stats_path):
    fleet_path = '$BASE/fleet.json'
    fleet = {}
    if os.path.exists(fleet_path):
        with open(fleet_path) as f:
            fleet = json.load(f)
    agents = {}
    for wid, info in fleet.items():
        agents[wid] = {
            'model': info.get('model', 'unknown'),
            'task_id': None,
            'start_time': None,
            'end_time': None,
            'duration_seconds': None,
            'stuck_count': 0,
            'files_changed': 0
        }
    with open(stats_path, 'w') as f:
        json.dump({'agents': agents}, f, indent=2)
" 2>/dev/null || true

declare -A LAST_ACTIVITY 2>/dev/null || true  # bash 3 fallback

show_banner() {
    printf "\033[1;33m"
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║         🦬 T E R M I N A L   S T A M P E D E 🦬      ║"
    echo "║                                                      ║"
    echo "║  🦬  $TOTAL_TASKS tasks · $(basename "$BASE") · LIVE     ║"
    echo "╚══════════════════════════════════════════════════════╝"
    printf "\033[0m"
    echo ""
}

show_completion() {
    clear
    printf "\033[1;32m"
    echo ""
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║                                                      ║"
    echo "║        🎉  S T A M P E D E   C O M P L E T E  🎉    ║"
    echo "║                                                      ║"
    echo "╚══════════════════════════════════════════════════════╝"
    printf "\033[0m"
    echo ""
    
    # Summary
    local done_count=$(find "$BASE/results" -name "*.json" -not -name ".tmp-*" -type f 2>/dev/null | wc -l | tr -d ' ')
    echo "  ✅ Tasks completed:  $done_count / $TOTAL_TASKS"
    echo ""
    
    # Per-task results
    echo "  ── Results ──"
    for rf in "$BASE/results"/*.json; do
        [ -f "$rf" ] || continue
        local tid=$(python3 -c "import json; print(json.load(open('$rf')).get('task_id','?'))" 2>/dev/null || echo "?")
        local status=$(python3 -c "import json; print(json.load(open('$rf')).get('status','?'))" 2>/dev/null || echo "?")
        if [[ "$status" == "done" ]]; then
            echo "    ✅ $tid — complete"
        else
            echo "    ⚠️  $tid — $status"
        fi
    done
    
    # Worker stats
    echo ""
    echo "  ── Agents ──"
    local alive=0 dead=0
    for pf in "$PIDS_DIR"/worker-*.pid; do
        [ -f "$pf" ] || continue
        local wid=$(basename "$pf" .pid)
        local wpid=$(cat "$pf")
        if kill -0 "$wpid" 2>/dev/null; then
            ((alive++))
        else
            ((dead++))
        fi
    done
    echo "    🟢 $alive finished  ·  🔴 $dead failed"
    
    echo ""
    printf "\033[1;36m"
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║                                                      ║"
    echo "║  👈 Go back to your Copilot CLI session for the      ║"
    echo "║     full report, shadow scores, and auto-merge.      ║"
    echo "║                                                      ║"
    echo "║  🦬 Auto-merge available — merges all branches into  ║"
    echo "║     one and scores each agent's work quality.        ║"
    echo "║                                                      ║"
    echo "╚══════════════════════════════════════════════════════╝"
    printf "\033[0m"
    echo ""
    printf "\033[2m"
    echo "  To run another stampede, just type 'stampede' in"
    echo "  your Copilot CLI and go again. 🦬"
    echo ""
    echo "  This window will close automatically in 60 seconds."
    echo "  Press any key to close now."
    printf "\033[0m"
    
    # Play completion sound
    afplay /System/Library/Sounds/Glass.aiff 2>/dev/null &
    
    # Wait for keypress or timeout
    read -t 60 -n 1 2>/dev/null || true
    exit 0
}

# ─── Main Loop ────────────────────────────────────────────────────────────────
while true; do
    clear
    show_banner
    
    # Count status
    queued=$(find "$BASE/queue" -name "*.json" -type f 2>/dev/null | wc -l | tr -d ' ')
    claimed=$(find "$BASE/claimed" -name "*.json" -type f 2>/dev/null | wc -l | tr -d ' ')
    done_count=$(find "$BASE/results" -name "*.json" -not -name ".tmp-*" -type f 2>/dev/null | wc -l | tr -d ' ')
    
    # Progress bar
    if [[ $TOTAL_TASKS -gt 0 ]]; then
        pct=$((done_count * 100 / TOTAL_TASKS))
        filled=$((pct * 40 / 100))
        empty=$((40 - filled))
        printf "  ⚙️  ["
        printf "\033[1;33m"
        printf '%0.s█' $(seq 1 $filled 2>/dev/null) 2>/dev/null || true
        printf "\033[0m"
        printf '%0.s░' $(seq 1 $empty 2>/dev/null) 2>/dev/null || true
        printf "] %d%% (%d/%d)\n" "$pct" "$done_count" "$TOTAL_TASKS"
    fi
    echo ""
    
    # Fleet status
    echo "  📋 Queue: $queued  ·  🔧 Active: $claimed  ·  ✅ Done: $done_count"
    echo ""
    
    # Worker health check
    echo "  ── Agents ──"
    stuck_found=false
    for pf in "$PIDS_DIR"/worker-*.pid; do
        [ -f "$pf" ] || continue
        wid=$(basename "$pf" .pid)
        wpid=$(cat "$pf")
        
        if kill -0 "$wpid" 2>/dev/null; then
            # Check if this worker has been alive too long without producing a result
            # Use the PID file modification time as a proxy
            if [[ "$(uname)" == "Darwin" ]]; then
                pid_age=$(( $(date +%s) - $(stat -f %m "$pf") ))
            else
                pid_age=$(( $(date +%s) - $(stat -c %Y "$pf") ))
            fi
            
            if [[ $pid_age -gt $STUCK_THRESHOLD ]] && [[ $claimed -gt 0 ]]; then
                printf "    \033[1;31m┌──────────────────────────────────────────┐\033[0m\n"
                printf "    \033[1;31m│ 🔴 $wid (PID $wpid) — STUCK (%ds) ⚠️   │\033[0m\n" "$pid_age"
                printf "    \033[1;31m│     May need help! Ctrl-B z to zoom     │\033[0m\n"
                printf "    \033[1;31m└──────────────────────────────────────────┘\033[0m\n"
                # Bell once per stuck agent, not every loop
                if ! grep -q "^${wid}$" "$ALERTED_FILE" 2>/dev/null; then
                    printf "$BELL"
                    echo "$wid" >> "$ALERTED_FILE"
                    # Layer 1: increment stuck count for this agent
                    python3 -c "
import json
try:
    with open('$RUNTIME_STATS') as f: stats = json.load(f)
    if '$wid' in stats.get('agents', {}):
        stats['agents']['$wid']['stuck_count'] = stats['agents']['$wid'].get('stuck_count', 0) + 1
    with open('$RUNTIME_STATS', 'w') as f: json.dump(stats, f, indent=2)
except: pass
" 2>/dev/null || true
                fi
                stuck_found=true
            else
                printf "    \033[32m🟢 $wid (PID $wpid) — working\033[0m\n"
            fi
        else
            printf "    \033[2m⬛ $wid (PID $wpid) — finished\033[0m\n"
        fi
    done
    
    if $stuck_found; then
        echo ""
        printf "    \033[1;31m⚠️  STUCK AGENT DETECTED — Zoom in (Ctrl-B z) to check!\033[0m\n"
    fi
    
    # Active tasks
    echo ""
    echo "  ── Active Tasks ──"
    for cf in "$BASE/claimed"/*.json; do
        [ -f "$cf" ] || { echo "    (none)"; break; }
        tid=$(python3 -c "import json; print(json.load(open('$cf')).get('task_id','?'))" 2>/dev/null || echo "?")
        desc=$(python3 -c "import json; print(json.load(open('$cf')).get('description','')[:50])" 2>/dev/null || echo "?")
        echo "    🔧 $tid: $desc"
    done
    
    # Completed tasks  
    echo ""
    echo "  ── Completed ──"
    for rf in "$BASE/results"/*.json; do
        [ -f "$rf" ] || { echo "    (none yet)"; break; }
        tid=$(python3 -c "import json; print(json.load(open('$rf')).get('task_id','?'))" 2>/dev/null || echo "?")
        echo "    ✅ $tid"
    done
    
    echo ""
    printf "\033[2m  Updated: $(date +%H:%M:%S)  ·  Ctrl-B z to zoom a pane  ·  Ctrl-B d to detach\033[0m\n"
    
    # Check if all done
    if [[ $done_count -ge $TOTAL_TASKS ]] && [[ $TOTAL_TASKS -gt 0 ]]; then
        # Layer 1: Finalize runtime stats with task mappings and completion times
        python3 -c "
import json, os, time

stats_path = '$RUNTIME_STATS'
results_dir = '$BASE/results'
try:
    with open(stats_path) as f:
        stats = json.load(f)

    # Map workers to tasks and capture file counts from results
    for rf in sorted(os.listdir(results_dir)):
        if not rf.endswith('.json') or rf.startswith('.tmp-'):
            continue
        with open(os.path.join(results_dir, rf)) as f:
            result = json.load(f)
        wid = result.get('worker_id', '')
        if wid in stats.get('agents', {}):
            stats['agents'][wid]['task_id'] = result.get('task_id')
            stats['agents'][wid]['end_time'] = result.get('completed_at')
            files = result.get('files_changed', [])
            stats['agents'][wid]['files_changed'] = len(files) if isinstance(files, list) else files

    # Calculate durations from PID file creation time (start) to result time
    pids_dir = '$PIDS_DIR'
    for wid, info in stats.get('agents', {}).items():
        pid_file = os.path.join(pids_dir, wid + '.pid')
        if os.path.exists(pid_file):
            start = os.path.getmtime(pid_file)
            info['start_time'] = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(start))
            if info.get('end_time'):
                from datetime import datetime
                try:
                    end = datetime.strptime(info['end_time'], '%Y-%m-%dT%H:%M:%SZ')
                    info['duration_seconds'] = int(end.timestamp() - start)
                except: pass

    with open(stats_path, 'w') as f:
        json.dump(stats, f, indent=2)
except Exception as e:
    pass
" 2>/dev/null || true
        sleep 2
        show_completion
    fi
    
    sleep 5
done
