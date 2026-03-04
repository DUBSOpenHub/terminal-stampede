#!/usr/bin/env bash
# shellcheck shell=bash
# stampede-monitor.sh — Live progress for Terminal Stampede runs
set -uo pipefail

RUN_ID="${1:?Usage: stampede-monitor.sh <run-id> [base-dir]}"
if [[ -n "${2:-}" ]] && [[ -d "$2" ]]; then
    BASE="$2"
elif [[ -d ".stampede/$RUN_ID" ]]; then
    BASE=".stampede/$RUN_ID"
elif [[ -d "$HOME/.stampede/$RUN_ID" ]]; then
    BASE="$HOME/.stampede/$RUN_ID"
elif [[ -d "$HOME/.copilot/stampede/$RUN_ID" ]]; then
    BASE="$HOME/.copilot/stampede/$RUN_ID"
else
    echo "ERROR: Cannot find run directory for $RUN_ID" >&2
    exit 1
fi

PIDS_DIR="$BASE/pids"
START_TIME=$(date +%s)
BELL=$'\a'
ALERTED=""
ALL_DEAD_SINCE=""

# Total tasks from state.json or filesystem
TOTAL_TASKS=0
if [[ -f "$BASE/state.json" ]]; then
    TOTAL_TASKS=$(python3 -c "import json; print(json.load(open('$BASE/state.json')).get('total_tasks', 0))" 2>/dev/null || echo 0)
fi
if [[ "$TOTAL_TASKS" -eq 0 ]]; then
    TOTAL_TASKS=$(find "$BASE/queue" "$BASE/claimed" "$BASE/results" -maxdepth 1 -name "task-*.json" -type f 2>/dev/null | sort -u | wc -l | tr -d ' ')
fi
[[ "$TOTAL_TASKS" -eq 0 ]] && TOTAL_TASKS=1

# Colors
G="\033[38;5;220m"; GN="\033[38;5;46m"; AM="\033[38;5;214m"
RD="\033[38;5;203m"; MT="\033[38;5;240m"; TX="\033[38;5;252m"
CY="\033[38;5;51m"
B="\033[1m"; R="\033[0m"; BG="\033[48;5;233m"

# ─── Main Loop ────────────────────────────────────────────────────────────────
while true; do
    queued=$(find "$BASE/queue" -name "task-*.json" -type f 2>/dev/null | wc -l | tr -d ' ')
    claimed=$(find "$BASE/claimed" -name "task-*.json" -type f 2>/dev/null | wc -l | tr -d ' ')
    done_count=$(find "$BASE/results" -name "task-*.json" -type f 2>/dev/null | wc -l | tr -d ' ')
    
    ELAPSED=$(( $(date +%s) - START_TIME ))
    MINS=$((ELAPSED / 60)); SECS=$((ELAPSED % 60))
    pct=$((TOTAL_TASKS > 0 ? done_count * 100 / TOTAL_TASKS : 0))
    
    # Progress bar
    COLS=$(tput cols 2>/dev/null || echo 80)
    BAR_W=$((COLS - 50))
    [[ $BAR_W -lt 10 ]] && BAR_W=10
    FILLED=$((BAR_W * pct / 100)); EMPTY=$((BAR_W - FILLED))
    FILL=""; EMP=""
    [[ $FILLED -gt 0 ]] && FILL=$(printf '█%.0s' $(seq 1 $FILLED))
    [[ $EMPTY -gt 0 ]] && EMP=$(printf '░%.0s' $(seq 1 $EMPTY))
    
    # Status word
    if [[ $done_count -ge $TOTAL_TASKS ]] && [[ $TOTAL_TASKS -gt 0 ]]; then
        ST="${GN}${B}COMPLETE${R}${BG}"
    elif [[ $claimed -gt 0 ]]; then
        ST="${AM}${B}RUNNING${R}${BG}"
    else
        ST="${MT}WAITING${R}${BG}"
    fi
    
    # ─── Draw ─────────────────────────────────────────────────────────────────
    clear
    printf "${BG} ${B}${G}⚡ TERMINAL STAMPEDE${R}${BG}  ${ST}  ${GN}✓${done_count}${R}${BG} ${AM}⚙${claimed}${R}${BG} ${MT}◌${queued}${R}${BG}  ${G}${FILL}${R}${BG}${MT}${EMP}${R}${BG} ${B}${TX}${pct}%%${R}${BG}  ${MT}${MINS}m${SECS}s${R}\n"
    
    # Agent roster from fleet.json
    if [[ -f "$BASE/fleet.json" ]]; then
        idx=0
        SESSION_NAME="stampede-${RUN_ID}"
        while IFS= read -r line; do
            [[ "$line" =~ \"(worker-[0-9]+)\" ]] || continue
            wid="${BASH_REMATCH[1]}"
            idx=$((idx + 1))
            model=$(python3 -c "import json; print(json.load(open('$BASE/fleet.json')).get('$wid',{}).get('model','?'))" 2>/dev/null || echo "?")
            
            # Check tmux pane state — the reliable source of truth
            pane_cmd=$(tmux list-panes -t "$SESSION_NAME" -F '#{pane_index} #{pane_current_command} #{pane_dead}' 2>/dev/null | awk "\$1==$idx {print \$2, \$3}" || echo "unknown 1")
            cmd=$(echo "$pane_cmd" | awk '{print $1}')
            dead=$(echo "$pane_cmd" | awk '{print $2}')
            
            if [[ "$dead" == "1" ]]; then
                ICON="${RD}✕"; WORD="dead"
            elif [[ "$cmd" == "sleep" ]]; then
                ICON="${GN}✓"; WORD="done"
            elif [[ "$cmd" == "bash" ]] || [[ "$cmd" == "gh" ]] || [[ "$cmd" == "python3" ]] || [[ "$cmd" == "node" ]]; then
                ICON="${AM}●"; WORD="active"
            elif [[ $done_count -ge $TOTAL_TASKS ]]; then
                ICON="${GN}✓"; WORD="done"
            else
                ICON="${AM}●"; WORD="active"
            fi
            
            printf "${BG}  ${ICON}${R}${BG} ${TX}Agent #${idx}${R}${BG}  ${ICON}${WORD}${R}${BG}  ${G}${model}${R}\n"
        done < "$BASE/fleet.json"
    fi
    
    # Stuck detection (bell once per agent)
    for cf in "$BASE/claimed"/task-*.json; do
        [[ -f "$cf" ]] || continue
        if [[ "$(uname)" == "Darwin" ]]; then
            age=$(( $(date +%s) - $(stat -f %m "$cf") ))
        else
            age=$(( $(date +%s) - $(stat -c %Y "$cf") ))
        fi
        if [[ $age -gt 120 ]]; then
            tid=$(basename "$cf" .json)
            if [[ "$ALERTED" != *"$tid"* ]]; then
                printf "$BELL"
                ALERTED="$ALERTED $tid"
                printf "${BG} ${RD}⚠ ${tid} stuck (${age}s)${R}\n"
            fi
        fi
    done
    
    # ─── Orphan Recovery ─────────────────────────────────────────────────────
    # If a claimed task has no result and no live agent is working, return it to queue
    if [[ $live_agents -eq 0 ]] && [[ $claimed -gt 0 ]]; then
        for cf in "$BASE/claimed"/task-*.json; do
            [[ -f "$cf" ]] || continue
            tid=$(basename "$cf" .json)
            if [[ ! -f "$BASE/results/${tid}.json" ]]; then
                mv "$cf" "$BASE/queue/${tid}.json" 2>/dev/null && \
                    printf "${BG} ${AM}♻ ${tid} returned to queue (agent died)${R}\n"
            fi
        done
    fi

    # ─── Dead Agent Recovery ─────────────────────────────────────────────────
    # Use tmux pane status — more reliable than stored PIDs
    SESSION_NAME="stampede-${RUN_ID}"
    live_agents=0; total_agents=0; done_agents=0
    while IFS=' ' read -r pidx pcmd pdead; do
        [[ "$pidx" == "0" ]] && continue  # skip monitor pane
        total_agents=$((total_agents + 1))
        if [[ "$pdead" == "1" ]]; then
            : # dead pane
        elif [[ "$pcmd" == "sleep" ]]; then
            done_agents=$((done_agents + 1))
        else
            live_agents=$((live_agents + 1))
        fi
    done < <(tmux list-panes -t "$SESSION_NAME" -F '#{pane_index} #{pane_current_command} #{pane_dead}' 2>/dev/null)

    all_done_or_dead=false
    [[ $total_agents -gt 0 ]] && [[ $live_agents -eq 0 ]] && all_done_or_dead=true

    if $all_done_or_dead && [[ $done_count -lt $TOTAL_TASKS ]] && [[ $queued -eq 0 ]] && [[ $claimed -eq 0 ]]; then
        if [[ -z "$ALL_DEAD_SINCE" ]]; then
            ALL_DEAD_SINCE=$(date +%s)
        fi
    elif $all_done_or_dead && [[ $done_count -ge $TOTAL_TASKS ]]; then
        : # normal completion, handled below
    else
        ALL_DEAD_SINCE=""
    fi

    # ─── Completion ───────────────────────────────────────────────────────────
    is_complete=false; partial=false
    if [[ $done_count -ge $TOTAL_TASKS ]] && [[ $TOTAL_TASKS -gt 0 ]]; then
        is_complete=true
    elif [[ -n "$ALL_DEAD_SINCE" ]]; then
        grace=$(( $(date +%s) - ALL_DEAD_SINCE ))
        if [[ $grace -ge 15 ]] && [[ $done_count -gt 0 ]]; then
            is_complete=true; partial=true
        else
            printf "${BG} ${RD}⚠ All agents dead — completing in $((15 - grace))s${R}\n"
        fi
    fi

    if $is_complete; then
        # Finalize runtime stats
        python3 -c "
import json, os, time
try:
    stats_path = '$BASE/runtime-stats.json'
    if not os.path.exists(stats_path): exit()
    with open(stats_path) as f: stats = json.load(f)
    for rf in sorted(os.listdir('$BASE/results')):
        if not rf.startswith('task-') or not rf.endswith('.json'): continue
        with open(os.path.join('$BASE/results', rf)) as f: result = json.load(f)
        wid = result.get('worker_id', '')
        if wid in stats.get('agents', {}):
            stats['agents'][wid]['task_id'] = result.get('task_id')
            stats['agents'][wid]['end_time'] = result.get('completed_at')
            files = result.get('files_changed', [])
            stats['agents'][wid]['files_changed'] = len(files) if isinstance(files, list) else files
    with open(stats_path, 'w') as f: json.dump(stats, f, indent=2)
except: pass
" 2>/dev/null || true
        
        sleep 2
        afplay /System/Library/Sounds/Glass.aiff 2>/dev/null &
        
        clear
        echo ""
        if $partial; then
            printf "  ${AM}${B}⚡ STAMPEDE PARTIAL${R}  ${MT}${done_count}/${TOTAL_TASKS} tasks · ${MINS}m${SECS}s · some agents died${R}\n\n"
        else
            printf "  ${GN}${B}🎉 STAMPEDE COMPLETE${R}  ${MT}${done_count}/${TOTAL_TASKS} tasks · ${MINS}m${SECS}s${R}\n\n"
        fi
        
        for rf in "$BASE/results"/task-*.json; do
            [ -f "$rf" ] || continue
            tid=$(python3 -c "import json; print(json.load(open('$rf')).get('task_id','?'))" 2>/dev/null || echo "?")
            status=$(python3 -c "import json; print(json.load(open('$rf')).get('status','?'))" 2>/dev/null || echo "?")
            branch=$(python3 -c "import json; print(json.load(open('$rf')).get('branch',''))" 2>/dev/null || echo "")
            title=$(python3 -c "import json; r=json.load(open('$rf')); print(r.get('title', r.get('summary','')[:60]))" 2>/dev/null || echo "")
            files=$(python3 -c "import json; r=json.load(open('$rf')); print(', '.join(r.get('files_changed',[])))" 2>/dev/null || echo "")
            if [[ "$status" == "done" ]]; then
                printf "    ${GN}✅${R} ${TX}${tid}: ${title}${R}  ${MT}→ ${branch}${R}\n"
                [[ -n "$files" ]] && printf "       ${MT}${files}${R}\n"
            else
                printf "    ${RD}❌${R} ${TX}${tid}: ${title} — ${status}${R}\n"
            fi
        done
        
        # Show missing tasks (agents died before finishing)
        if $partial; then
            for i in $(seq 1 $TOTAL_TASKS); do
                tid=$(printf "task-%03d" "$i")
                [[ -f "$BASE/results/${tid}.json" ]] && continue
                printf "    ${RD}💀${R} ${TX}${tid}: agent died — no result${R}\n"
            done
        fi

        # Merge prompt with bison box
        REPO_PATH=$(python3 -c "import json; print(json.load(open('$BASE/state.json')).get('repo_path',''))" 2>/dev/null || echo "")
        if [[ -n "$REPO_PATH" ]] && [[ -x "$HOME/bin/stampede-merge.sh" ]]; then
            echo ""
            echo ""
            printf "  ${B}${CY}╭─────────────────────────────────────────────────╮${R}\n"
            printf "  ${B}${CY}│                                                 │${R}\n"
            printf "  ${B}${CY}│  🦬 Auto-merge + shadow score all branches?     │${R}\n"
            printf "  ${B}${CY}│                                                 │${R}\n"
            printf "  ${B}${CY}╰─────────────────────────────────────────────────╯${R}\n"
            echo ""
            printf "  ${B}${TX}  Press Y to merge, N to skip:${R} "
            read -t 60 -n 1 answer 2>/dev/null || answer="y"
            echo ""
            if [[ "$answer" != "n" ]] && [[ "$answer" != "N" ]]; then
                echo ""
                "$HOME/bin/stampede-merge.sh" --run-id "${RUN_ID}" --repo "${REPO_PATH}" 2>&1
            else
                echo ""
                printf "  ${MT}To merge later:${R}\n"
                printf "  ${TX}stampede-merge.sh --run-id ${RUN_ID} --repo ${REPO_PATH}${R}\n"
                printf "  ${MT}Branches are waiting on the repo — nothing was lost.${R}\n"
            fi
        fi
        
        echo ""
        printf "  ${MT}Press any key to close. Auto-closes in 60s.${R}\n"
        
        read -t 60 -n 1 2>/dev/null || true
        exit 0
    fi
    
    sleep 5
done
