#!/usr/bin/env bash
# shellcheck shell=bash
# stampede-monitor.sh — Live monitor for Terminal Stampede runs
# Shows progress, alerts on stuck agents, celebrates completion.
set -euo pipefail

RUN_ID="${1:?Usage: stampede-monitor.sh <run-id> [base-dir]}"
# Accept explicit base dir, or search for it
if [[ -n "${2:-}" ]] && [[ -d "$2" ]]; then
    BASE="$2"
elif [[ -d ".stampede/$RUN_ID" ]]; then
    BASE=".stampede/$RUN_ID"
elif [[ -d "$HOME/.copilot/stampede/$RUN_ID" ]]; then
    BASE="$HOME/.copilot/stampede/$RUN_ID"
else
    echo "ERROR: Cannot find run directory for $RUN_ID" >&2
    exit 1
fi
PIDS_DIR="$BASE/pids"
TOTAL_TASKS=$(find "$BASE/queue" "$BASE/claimed" "$BASE/results" -name "*.json" -not -name ".tmp-*" -type f 2>/dev/null | wc -l | tr -d ' ')
STUCK_THRESHOLD=180  # seconds without progress = stuck
BELL=$'\a'
ALERTED_FILE="$BASE/.alerted"  # track which agents already belled
RUNTIME_STATS="$BASE/runtime-stats.json"  # Layer 1 shadow scoring data
STUCK_COUNTS="$BASE/.stuck-counts"  # track per-agent stuck events
touch "$ALERTED_FILE" 2>/dev/null || true
touch "$STUCK_COUNTS" 2>/dev/null || true
START_TIME=$(date +%s)

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
    local G="\033[38;5;220m"; local GN="\033[38;5;46m"; local AM="\033[38;5;214m"
    local BL="\033[38;5;39m"; local MT="\033[38;5;240m"; local TX="\033[38;5;252m"
    local B="\033[1m"; local R="\033[0m"; local BG="\033[48;5;233m"

    # Count status
    local queued=$(find "$BASE/queue" -name "*.json" -type f 2>/dev/null | wc -l | tr -d ' ')
    local claimed=$(find "$BASE/claimed" -name "*.json" -type f 2>/dev/null | wc -l | tr -d ' ')
    local done_count=$(find "$BASE/results" -name "*.json" -not -name ".tmp-*" -type f 2>/dev/null | wc -l | tr -d ' ')
    local pct=0
    [[ $TOTAL_TASKS -gt 0 ]] && pct=$((done_count * 100 / TOTAL_TASKS))

    local COLS=$(tput cols 2>/dev/null || echo 120)
    local ELAPSED=$(( $(date +%s) - START_TIME ))
    local MINS=$((ELAPSED/60)); local SECS=$((ELAPSED%60))

    # Status word
    local ST
    if [[ $done_count -ge $TOTAL_TASKS && $TOTAL_TASKS -gt 0 ]]; then ST="${GN}${B}COMPLETE${R}${BG}"
    elif [[ $claimed -gt 0 ]]; then ST="${AM}${B}RUNNING${R}${BG}"
    elif [[ $queued -gt 0 ]]; then ST="${BL}${B}QUEUED${R}${BG}"
    else ST="${MT}IDLE${R}${BG}"; fi

    # Title bar with progress
    local BAR_W=$((COLS - 55))
    [[ $BAR_W -lt 10 ]] && BAR_W=10
    local FILLED=$((BAR_W * pct / 100)); local EMPTY=$((BAR_W - FILLED))
    local FILL=""; local EMP=""
    [[ $FILLED -gt 0 ]] && FILL=$(printf '█%.0s' $(seq 1 $FILLED))
    [[ $EMPTY -gt 0 ]] && EMP=$(printf '░%.0s' $(seq 1 $EMPTY))

    printf "${BG} ${B}${G}⚡ TERMINAL STAMPEDE${R}${BG}  ${ST}  ${GN}✓${done_count}${R}${BG} ${AM}⚙${claimed}${R}${BG} ${BL}◌${queued}${R}${BG}  ${G}${FILL}${R}${BG}${MT}${EMP}${R}${BG} ${B}${TX}${pct}%%${R}${BG}  ${MT}${MINS}m${SECS}s${R}${BG}${R}\n"

    # Divider
    printf "${BG} ${MT}"
    printf '─%.0s' $(seq 1 $((COLS - 2)))
    printf "${R}\n"

    # Per-agent roster from fleet.json + tmux pane status
    local SESSION_NAME="stampede-${RUN_ID}"
    local FLEET_FILE="$BASE/fleet.json"

    if [[ -f "$FLEET_FILE" ]]; then
        local agent_idx=0
        while IFS= read -r line; do
            [[ "$line" =~ \"(worker-[0-9]+)\" ]] || continue
            local wid="${BASH_REMATCH[1]}"
            agent_idx=$((agent_idx + 1))
            local model=$(python3 -c "import json; print(json.load(open('$FLEET_FILE')).get('$wid',{}).get('model','?'))" 2>/dev/null || echo "?")

            # Detect status from tmux pane content
            local PANE_LAST=$(tmux capture-pane -t "${SESSION_NAME}:0.${agent_idx}" -p 2>/dev/null | grep -v '^$' | tail -1 || true)
            local ICON STATUS_WORD WC

            # Check filesystem status first
            local task_file=""
            for cf in "$BASE/claimed"/*.json; do
                [[ -f "$cf" ]] || continue
                local cby=$(python3 -c "import json; print(json.load(open('$cf')).get('claimed_by',''))" 2>/dev/null || echo "")
                if [[ "$cby" == "$wid" ]]; then
                    task_file="$cf"
                    break
                fi
            done

            local is_done=false
            for rf in "$BASE/results"/*.json; do
                [[ -f "$rf" ]] || continue
                local rby=$(python3 -c "import json; print(json.load(open('$rf')).get('worker_id',json.load(open('$rf')).get('claimed_by','')))" 2>/dev/null || echo "")
                if [[ "$rby" == "$wid" ]]; then
                    is_done=true
                    break
                fi
            done

            local pid_file="$PIDS_DIR/${wid}.pid"
            local is_alive=false
            if [[ -f "$pid_file" ]]; then
                local wpid=$(cat "$pid_file")
                kill -0 "$wpid" 2>/dev/null && is_alive=true
            fi

            if $is_done; then
                ICON="\033[38;5;46m✓"; WC="\033[38;5;46m"; STATUS_WORD="done  "
            elif ! $is_alive && [[ -f "$pid_file" ]]; then
                ICON="\033[38;5;203m✕"; WC="\033[38;5;203m"; STATUS_WORD="dead  "
            elif echo "$PANE_LAST" | grep -qi "error\|fail\|fatal" 2>/dev/null; then
                ICON="\033[38;5;203m✕"; WC="\033[38;5;203m"; STATUS_WORD="ERROR "
            elif echo "$PANE_LAST" | grep -qi "test\|npm test\|pytest\|vitest" 2>/dev/null; then
                ICON="\033[38;5;39m⧫"; WC="\033[38;5;39m"; STATUS_WORD="test  "
            elif echo "$PANE_LAST" | grep -qi "commit\|push\|git add" 2>/dev/null; then
                ICON="\033[38;5;46m◉"; WC="\033[38;5;46m"; STATUS_WORD="commit"
            elif echo "$PANE_LAST" | grep -qi "edit\|creat\|writ\|Implementing\|lines)" 2>/dev/null; then
                ICON="\033[38;5;214m◉"; WC="\033[38;5;214m"; STATUS_WORD="code  "
            elif echo "$PANE_LAST" | grep -qi "analyz\|structure\|detect\|scan" 2>/dev/null; then
                ICON="\033[38;5;214m⟳"; WC="\033[38;5;214m"; STATUS_WORD="scan  "
            elif [[ -n "$task_file" ]]; then
                ICON="\033[38;5;214m●"; WC="\033[38;5;214m"; STATUS_WORD="active"
            elif $is_alive; then
                ICON="\033[38;5;39m●"; WC="\033[38;5;39m"; STATUS_WORD="boot  "
            else
                ICON="\033[38;5;240m○"; WC="\033[38;5;240m"; STATUS_WORD="wait  "
            fi

            # Get task title
            local task_title=""
            if [[ -n "$task_file" ]]; then
                task_title=$(python3 -c "import json; print(json.load(open('$task_file')).get('title','')[:40])" 2>/dev/null || echo "")
            fi

            printf "${BG}  ${ICON}${R}${BG} ${B}${TX}Agent #${agent_idx}${R}${BG}  ${WC}${STATUS_WORD}${R}${BG}  ${G}%-20s${R}${BG}  ${TX}${task_title}${R}${BG}${R}\n" "${model}"
        done < "$FLEET_FILE"
    fi

    # Divider
    printf "${BG} ${MT}"
    printf '─%.0s' $(seq 1 $((COLS - 2)))
    printf "${R}\n"
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
    
    # Agent stats
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
    
    # Stuck agent detection (keeps bell/alert behavior)
    stuck_found=false
    for pf in "$PIDS_DIR"/worker-*.pid; do
        [ -f "$pf" ] || continue
        wid=$(basename "$pf" .pid)
        wpid=$(cat "$pf")
        
        if kill -0 "$wpid" 2>/dev/null; then
            if [[ "$(uname)" == "Darwin" ]]; then
                pid_age=$(( $(date +%s) - $(stat -f %m "$pf") ))
            else
                pid_age=$(( $(date +%s) - $(stat -c %Y "$pf") ))
            fi
            
            if [[ $pid_age -gt $STUCK_THRESHOLD ]] && [[ $claimed -gt 0 ]]; then
                if ! grep -q "^${wid}$" "$ALERTED_FILE" 2>/dev/null; then
                    printf "$BELL"
                    echo "$wid" >> "$ALERTED_FILE"
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
            fi
        fi
    done
    
    if $stuck_found; then
        printf "\033[48;5;233m \033[38;5;203m⚠ Stuck agent detected — F1-F8 to zoom in and check\033[0m\n"
    fi
    
    # Narration hint
    ELAPSED=$(( $(date +%s) - START_TIME ))
    HINTS=("F1-F8 zooms an agent fullscreen · F9 returns to grid" "Click any agent pane to interact with it directly" "Agents work on separate git branches to avoid conflicts" "Ctrl+B z toggles zoom on the selected pane")
    HINT_IDX=$(( (ELAPSED / 6) % ${#HINTS[@]} ))
    printf "\033[48;5;233m \033[38;5;220m🦬\033[0m\033[48;5;233m \033[38;5;252m${HINTS[$HINT_IDX]}\033[0m\n"
    
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

    # Map agents to tasks and capture file counts from results
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
