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
elif [[ -d "$HOME/.stampede/$RUN_ID" ]]; then
    BASE="$HOME/.stampede/$RUN_ID"
else
    echo "ERROR: Cannot find run directory for $RUN_ID" >&2
    exit 1
fi
PIDS_DIR="$BASE/pids"
# Count total unique tasks across all directories (handles tasks that moved between dirs)
TOTAL_TASKS=$(find "$BASE/queue" "$BASE/claimed" "$BASE/results" -name "*.json" -not -name ".tmp-*" -not -name "state.json" -not -name "fleet.json" -not -name "runtime-stats.json" -not -name "merge-report.json" -type f 2>/dev/null | xargs -I{} basename {} | sort -u | wc -l | tr -d ' ')
# Fallback: read from state.json if available
if [[ -f "$BASE/state.json" ]]; then
    STATE_TOTAL=$(python3 -c "import json; s=json.load(open('$BASE/state.json')); print(s.get('total_tasks', 0))" 2>/dev/null || echo 0)
    [[ "$STATE_TOTAL" -gt "$TOTAL_TASKS" ]] && TOTAL_TASKS="$STATE_TOTAL"
fi
[[ "$TOTAL_TASKS" -eq 0 ]] && TOTAL_TASKS=1  # prevent div-by-zero
STUCK_THRESHOLD=120  # seconds without progress = stuck
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
                # Check if this is a completed agent vs a crashed one
                # If no tasks remain in queue/claimed, agent finished normally
                local remaining_tasks=$(find "$BASE/queue" "$BASE/claimed" -name "*.json" -type f 2>/dev/null | wc -l | tr -d ' ')
                if [[ "$remaining_tasks" -eq 0 ]]; then
                    ICON="\033[38;5;46m✓"; WC="\033[38;5;46m"; STATUS_WORD="done  "
                else
                    ICON="\033[38;5;203m✕"; WC="\033[38;5;203m"; STATUS_WORD="dead  "
                fi
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
    local SESSION_NAME="stampede-${RUN_ID}"
    
    # Collapse all agent panes — zoom monitor pane to fullscreen
    # Kill agent panes (they're done), leaving just the monitor
    local pane_count=$(tmux list-panes -t "$SESSION_NAME" 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$pane_count" -gt 1 ]]; then
        # Kill all panes except pane 0 (monitor), starting from the highest index
        for ((p = pane_count - 1; p >= 1; p--)); do
            tmux kill-pane -t "$SESSION_NAME:0.$p" 2>/dev/null || true
        done
    fi
    
    # Play completion sound
    afplay /System/Library/Sounds/Glass.aiff 2>/dev/null &
    
    sleep 0.5
    clear
    
    local G="\033[38;5;220m"; local GN="\033[38;5;46m"
    local MT="\033[38;5;240m"; local TX="\033[38;5;252m"
    local B="\033[1m"; local R="\033[0m"; local CY="\033[38;5;51m"
    
    # ─── Completion banner ───
    printf "${GN}"
    echo ""
    echo "     ╔══════════════════════════════════════════════════════╗"
    echo "     ║                                                      ║"
    echo "     ║        🎉  S T A M P E D E   C O M P L E T E  🎉    ║"
    echo "     ║                                                      ║"
    echo "     ╚══════════════════════════════════════════════════════╝"
    printf "${R}"
    echo ""
    
    # ─── Summary ───
    local done_count=$(find "$BASE/results" -name "*.json" -not -name ".tmp-*" -type f 2>/dev/null | wc -l | tr -d ' ')
    local ELAPSED=$(( $(date +%s) - START_TIME ))
    local MINS=$((ELAPSED/60)); local SECS=$((ELAPSED%60))
    
    printf "  ${B}${TX}✅ ${done_count}/${TOTAL_TASKS} tasks completed in ${MINS}m${SECS}s${R}\n"
    echo ""
    
    # ─── Per-task results with summaries ───
    printf "  ${G}── Results ──${R}\n"
    for rf in "$BASE/results"/*.json; do
        [ -f "$rf" ] || continue
        local tid=$(python3 -c "import json; print(json.load(open('$rf')).get('task_id','?'))" 2>/dev/null || echo "?")
        local status=$(python3 -c "import json; print(json.load(open('$rf')).get('status','?'))" 2>/dev/null || echo "?")
        local title=$(python3 -c "import json; r=json.load(open('$rf')); print(r.get('summary','')[:80])" 2>/dev/null || echo "")
        local branch=$(python3 -c "import json; print(json.load(open('$rf')).get('branch',''))" 2>/dev/null || echo "")
        if [[ "$status" == "done" ]]; then
            printf "    ${GN}✅${R} ${B}${TX}${tid}${R}  ${MT}→ ${branch}${R}\n"
            [[ -n "$title" ]] && printf "       ${TX}${title}${R}\n"
        else
            printf "    ${R}\033[38;5;203m❌${R} ${B}${TX}${tid}${R}  ${MT}— ${status}${R}\n"
        fi
    done
    
    # ─── Agent stats ───
    echo ""
    printf "  ${G}── Agents ──${R}\n"
    local finished=0 dead=0
    local remaining_tasks=$(find "$BASE/queue" "$BASE/claimed" -name "*.json" -type f 2>/dev/null | wc -l | tr -d ' ')
    for pf in "$PIDS_DIR"/worker-*.pid; do
        [ -f "$pf" ] || continue
        local wpid=$(cat "$pf")
        if kill -0 "$wpid" 2>/dev/null; then
            ((finished++))
        elif [[ "$remaining_tasks" -eq 0 ]]; then
            ((finished++))
        else
            ((dead++))
        fi
    done
    printf "    ${GN}🟢 $finished finished${R}"
    [[ $dead -gt 0 ]] && printf "  ${R}\033[38;5;203m·  🔴 $dead failed${R}"
    echo ""
    
    # ─── Branches ready ───
    echo ""
    local branch_count=$(cd "$REPO_PATH" 2>/dev/null && git branch --list 'stampede/task-*' 2>/dev/null | wc -l | tr -d ' ')
    local repo_name=$(basename "${REPO_PATH:-$(pwd)}" 2>/dev/null)
    if [[ "$branch_count" -gt 0 ]]; then
        printf "  ${G}── Branches ──${R}\n"
        printf "    ${TX}${branch_count} branches ready to merge on ${repo_name}${R}\n"
        echo ""
    fi
    
    # ─── Next steps ───
    printf "  ${CY}╭──────────────────────────────────────────────────╮${R}\n"
    printf "  ${CY}│${R}                                                  ${CY}│${R}\n"
    printf "  ${CY}│${R}  ${B}${TX}Go back to your CLI session for:${R}                ${CY}│${R}\n"
    printf "  ${CY}│${R}    ${TX}• Full report and shadow scores${R}                ${CY}│${R}\n"
    printf "  ${CY}│${R}    ${TX}• Auto-merge all branches into one${R}             ${CY}│${R}\n"
    printf "  ${CY}│${R}    ${TX}• Model leaderboard update${R}                     ${CY}│${R}\n"
    printf "  ${CY}│${R}                                                  ${CY}│${R}\n"
    printf "  ${CY}╰──────────────────────────────────────────────────╯${R}\n"
    echo ""
    printf "  ${MT}This window will close in 60 seconds. Press any key to close now.${R}\n"
    printf "  ${MT}To run again: stampede.sh or type 'stampede' in your CLI agent. 🦬${R}\n"
    
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
    
    # Stuck agent detection
    stuck_found=false
    for pf in "$PIDS_DIR"/worker-*.pid; do
        [ -f "$pf" ] || continue
        wid=$(basename "$pf" .pid)
        wpid=$(cat "$pf")
        
        if kill -0 "$wpid" 2>/dev/null; then
            # Check if any claimed task for this worker is stale
            local is_stuck=false
            for cf in "$BASE/claimed"/*.json; do
                [[ -f "$cf" ]] || continue
                if [[ "$(uname)" == "Darwin" ]]; then
                    claim_age=$(( $(date +%s) - $(stat -f %m "$cf") ))
                else
                    claim_age=$(( $(date +%s) - $(stat -c %Y "$cf") ))
                fi
                if [[ $claim_age -gt $STUCK_THRESHOLD ]]; then
                    is_stuck=true
                    break
                fi
            done
            
            if $is_stuck; then
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
                
                # Highlight the stuck agent's tmux pane with red border
                local agent_idx=${wid#worker-}
                tmux select-pane -t "${SESSION_NAME:-stampede-${RUN_ID}}:0.${agent_idx}" \
                    -P 'fg=default,bg=default' 2>/dev/null || true
                tmux set-option -p -t "${SESSION_NAME:-stampede-${RUN_ID}}:0.${agent_idx}" \
                    pane-border-style "fg=colour203" 2>/dev/null || true
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
