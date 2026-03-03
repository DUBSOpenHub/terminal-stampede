#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════════
# 🦬 Terminal Stampede — Demo Mode
# One command. Zero API calls. Full visual experience.
# Usage: stampede-demo.sh [--workers N] [--speed fast|normal|slow]
# ═══════════════════════════════════════════════════════════════════

WORKERS=8
SPEED="normal"
SESSION="stampede-demo"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workers|-w) WORKERS="$2"; shift 2 ;;
    --speed|-s)   SPEED="$2"; shift 2 ;;
    --help|-h)    echo "Usage: stampede-demo.sh [--workers 3-8] [--speed fast|normal|slow]"; exit 0 ;;
    *) shift ;;
  esac
done

[[ $WORKERS -lt 1 ]] && WORKERS=3
[[ $WORKERS -gt 8 ]] && WORKERS=8

case "$SPEED" in
  fast)   TICK=0.15; PHASE_WAIT=0.5 ;;
  slow)   TICK=1.2; PHASE_WAIT=5 ;;
  *)      TICK=0.4; PHASE_WAIT=2 ;;
esac

# Kill existing demo session
tmux has-session -t "$SESSION" 2>/dev/null && tmux kill-session -t "$SESSION"

# Clean up start signal from previous runs
rm -f /tmp/stampede-demo-start

# ─── Task definitions ───────────────────────────────────────────
TASKS=(
  "Add user authentication module"
  "Implement rate limiting middleware"
  "Create database migration scripts"
  "Add WebSocket real-time events"
  "Build CI/CD pipeline config"
  "Write integration test suite"
  "Add OpenAPI documentation"
  "Implement caching layer"
)

MODELS=(
  "claude-sonnet-4.5"
  "claude-sonnet-4.5"
  "gpt-5.1-codex"
  "claude-sonnet-4.5"
  "claude-haiku-4.5"
  "claude-sonnet-4.5"
  "gpt-5.1-codex"
  "claude-sonnet-4.5"
)

FILES_0="src/auth/login.ts src/auth/jwt.ts src/middleware/auth.ts"
FILES_1="src/middleware/rate-limit.ts src/config/limits.ts tests/rate-limit.test.ts"
FILES_2="db/migrations/001_users.sql db/migrations/002_sessions.sql db/seed.ts"
FILES_3="src/ws/handler.ts src/ws/events.ts src/ws/rooms.ts"
FILES_4=".github/workflows/ci.yml .github/workflows/deploy.yml Dockerfile"
FILES_5="tests/integration/api.test.ts tests/integration/auth.test.ts tests/fixtures/data.ts"
FILES_6="docs/openapi.yaml src/routes/docs.ts scripts/gen-docs.sh"
FILES_7="src/cache/redis.ts src/cache/strategy.ts src/middleware/cache.ts"

# ─── Create agent simulator scripts ─────────────────────────────
for IDX in $(seq 1 "$WORKERS"); do
  TASK="${TASKS[$((IDX-1))]}"
  MODEL="${MODELS[$((IDX-1))]}"
  eval "FILES=\$FILES_$((IDX-1))"
  BRANCH="stampede/task-$(printf '%03d' "$IDX")"
  SCRIPT="/tmp/stampede-demo-w${IDX}.sh"

  cat > "$SCRIPT" << WORKER_EOF
#!/usr/bin/env bash
set -euo pipefail

G="\033[38;5;220m"; GN="\033[38;5;46m"
AM="\033[38;5;214m"; BL="\033[38;5;39m"; MT="\033[38;5;240m"
TX="\033[38;5;252m"; B="\033[1m"; R="\033[0m"

TICK=${TICK}
PW=${PHASE_WAIT}

say() { printf "%b\n" "\$1"; sleep \$TICK; }

# Wait for start signal (intro screen must finish first)
while [[ ! -f /tmp/stampede-demo-start ]]; do
  sleep 0.3
done

# Stagger start
sleep \$(echo "${IDX} * 0.4 + 0.3" | bc)

say "\${B}\${G}⚡ Agent ${IDX} starting\${R}"
say "\${MT}Model: ${MODEL}\${R}"
say "\${MT}Task:  ${TASK}\${R}"
sleep \$TICK

say ""
say "\${GN}✓\${R} Claimed task-$(printf '%03d' "$IDX") from queue"
say "\${BL}●\${R} Creating branch ${BRANCH}"
say "\${MT}\\\$ git checkout -b ${BRANCH}\${R}"
say "\${MT}Switched to new branch '${BRANCH}'\${R}"
sleep \$PW

say ""
say "\${AM}◉\${R} Analyzing repository structure..."
say "\${MT}  Found 47 files, 3,218 lines\${R}"
say "\${MT}  Detected: TypeScript + Node.js\${R}"
say "\${MT}  Test framework: vitest\${R}"
sleep \$PW

say ""
say "\${B}\${TX}Implementing: ${TASK}\${R}"
for f in ${FILES}; do
  sleep \$(echo "\$TICK * 1.5" | bc)
  LINES=\$((RANDOM % 80 + 20))
  say "\${GN}✓\${R} \${f} \${MT}(+\${LINES} lines)\${R}"
done
sleep \$PW

say ""
say "\${BL}●\${R} Running tests..."
say "\${MT}\\\$ npm test\${R}"
sleep \$(echo "\$TICK * 2" | bc)
PASS=\$((RANDOM % 8 + 5))
say "\${GN}✓ \${PASS} tests passed\${R}"
say "\${MT}  All assertions passing\${R}"
sleep \$PW

say ""
say "\${MT}\\\$ git add -A\${R}"
say "\${MT}\\\$ git commit -m \"feat: \$(echo '${TASK}' | tr '[:upper:]' '[:lower:]')\"\${R}"
HASH=\$(head -c 3 /dev/urandom | xxd -p)
say "\${MT}[${BRANCH} \${HASH}] feat: \$(echo '${TASK}' | tr '[:upper:]' '[:lower:]')\${R}"
say "\${MT} $(echo "${FILES}" | wc -w | xargs) files changed\${R}"
sleep \$TICK

say ""
say "\${GN}✓\${R} Wrote result JSON"
say "\${GN}✓\${R} Cleaned up claim file"
sleep \$TICK

say ""
say "\${B}\${GN}⚡ Agent ${IDX} complete.\${R}"

# Keep pane alive
sleep 3600
WORKER_EOF
  chmod +x "$SCRIPT"
done

# ─── Monitor bar with agent roster ───────────────────────────────
# Write agent config so monitor knows numbers + models
cat > /tmp/stampede-demo-agents.conf << 'AGENTCONF'
1|claude-sonnet-4.5|Add user auth
2|claude-sonnet-4.5|Rate limiting
3|gpt-5.1-codex|DB migrations
4|claude-sonnet-4.5|WebSocket events
5|claude-haiku-4.5|CI/CD pipeline
6|claude-sonnet-4.5|Integration tests
7|gpt-5.1-codex|OpenAPI docs
8|claude-sonnet-4.5|Caching layer
AGENTCONF

cat > /tmp/stampede-demo-monitor.sh << 'MONITOR_EOF'
#!/usr/bin/env bash
set -euo pipefail
trap 'printf "\033[?25h\033[0m"; exit 0' SIGINT SIGTERM EXIT
printf "\033[?25l"

G="\033[38;5;220m"; GN="\033[38;5;46m"
AM="\033[38;5;214m"; BL="\033[38;5;39m"; MT="\033[38;5;240m"
TX="\033[38;5;252m"; B="\033[1m"; R="\033[0m"; BG="\033[48;5;233m"
RD="\033[38;5;203m"
SESSION="stampede-demo"
TOTAL=$1
START=$(date +%s)

# Load agent config
declare -a AGENT_MODELS AGENT_TASKS
while IFS='|' read -r num model task; do
  AGENT_MODELS[$num]="$model"
  AGENT_TASKS[$num]="$task"
done < /tmp/stampede-demo-agents.conf

# Short model names for display
shorten_model() {
  echo "$1" | sed 's/claude-sonnet-/c:s-/;s/claude-haiku-/c:h-/;s/gpt-/g:/'
}

HINTS=(
  "👀 Each box below is an autonomous AI agent working in parallel"
  "🖱  Click any agent box to interact with it directly"
  "⌨️  F1-F${TOTAL} zooms an agent fullscreen · F9 returns to grid"
  "🔀 Agents work on separate git branches to avoid conflicts"
  "📡 Zero servers — agents coordinate via filesystem signals"
  "🧪 Each agent runs tests before committing its changes"
  "🦬 Real mode: one command splits any task across AI models"
)

while true; do
  COLS=$(tput cols 2>/dev/null || echo 120)
  printf "\033[H\033[J"

  DONE=0; ACTIVE=0
  declare -a AGENT_STATUS
  for i in $(seq 1 "$TOTAL"); do
    LAST=$(tmux capture-pane -t "${SESSION}:0.$i" -p 2>/dev/null | grep -v '^$' | tail -1 || true)
    if echo "$LAST" | grep -qi "complete\|done"; then
      AGENT_STATUS[$i]="done"
      DONE=$((DONE+1))
    elif echo "$LAST" | grep -qi "error\|fail"; then
      AGENT_STATUS[$i]="error"
    elif echo "$LAST" | grep -qi "test\|npm"; then
      AGENT_STATUS[$i]="testing"
      ACTIVE=$((ACTIVE+1))
    elif echo "$LAST" | grep -qi "commit\|push\|git add"; then
      AGENT_STATUS[$i]="committing"
      ACTIVE=$((ACTIVE+1))
    elif echo "$LAST" | grep -qi "edit\|creat\|writ\|Implementing\|lines)"; then
      AGENT_STATUS[$i]="coding"
      ACTIVE=$((ACTIVE+1))
    elif echo "$LAST" | grep -qi "analyz\|structure\|detect"; then
      AGENT_STATUS[$i]="analyzing"
      ACTIVE=$((ACTIVE+1))
    elif echo "$LAST" | grep -qi "claim\|branch\|checkout"; then
      AGENT_STATUS[$i]="claiming"
      ACTIVE=$((ACTIVE+1))
    elif echo "$LAST" | grep -qi "starting\|Agent"; then
      AGENT_STATUS[$i]="booting"
      ACTIVE=$((ACTIVE+1))
    elif [[ -n "$LAST" ]]; then
      AGENT_STATUS[$i]="active"
      ACTIVE=$((ACTIVE+1))
    else
      AGENT_STATUS[$i]="waiting"
    fi
  done
  QUEUED=$((TOTAL - DONE - ACTIVE))
  [[ $QUEUED -lt 0 ]] && QUEUED=0
  PCT=$((TOTAL==0?0:DONE*100/TOTAL))

  ELAPSED=$(( $(date +%s) - START ))
  MINS=$((ELAPSED/60)); SECS=$((ELAPSED%60))

  if [[ $DONE -ge $TOTAL && $TOTAL -gt 0 ]]; then ST="${GN}${B}COMPLETE${R}${BG}"
  elif [[ $ACTIVE -gt 0 ]]; then ST="${AM}${B}RUNNING${R}${BG}"
  else ST="${BL}${B}STARTING${R}${BG}"; fi

  # Line 1: Title bar with progress
  BAR_W=$((COLS - 55))
  [[ $BAR_W -lt 10 ]] && BAR_W=10
  FILLED=$((BAR_W * PCT / 100)); EMPTY=$((BAR_W - FILLED))
  FILL=""; EMP=""
  [[ $FILLED -gt 0 ]] && FILL=$(printf '█%.0s' $(seq 1 $FILLED))
  [[ $EMPTY -gt 0 ]] && EMP=$(printf '░%.0s' $(seq 1 $EMPTY))

  printf "${BG} ${B}${G}⚡ TERMINAL STAMPEDE${R}${BG}  ${ST}  ${GN}✓${DONE}${R}${BG} ${AM}⚙${ACTIVE}${R}${BG} ${BL}◌${QUEUED}${R}${BG}  ${G}${FILL}${R}${BG}${MT}${EMP}${R}${BG} ${B}${TX}${PCT}%%${R}${BG}  ${MT}${MINS}m${SECS}s${R}${BG}${R}\n"

  # Line 2: Divider
  printf "${BG} ${MT}"
  printf '─%.0s' $(seq 1 $((COLS - 2)))
  printf "${R}\n"

  # Lines 3-10: One agent per line, columnar alignment
  for i in $(seq 1 "$TOTAL"); do
    TASK_NAME="${AGENT_TASKS[$i]:-}"
    MODEL_NAME="${AGENT_MODELS[$i]:-?}"
    S="${AGENT_STATUS[$i]:-waiting}"
    case "$S" in
      done)       ICON="${GN}✓${R}${BG}"; WORD="done  " ; WC="${GN}" ;;
      error)      ICON="${RD}✕${R}${BG}"; WORD="ERROR " ; WC="${RD}" ;;
      testing)    ICON="${BL}⧫${R}${BG}"; WORD="test  " ; WC="${BL}" ;;
      coding)     ICON="${AM}◉${R}${BG}"; WORD="code  " ; WC="${AM}" ;;
      committing) ICON="${GN}◉${R}${BG}"; WORD="commit" ; WC="${GN}" ;;
      analyzing)  ICON="${AM}⟳${R}${BG}"; WORD="scan  " ; WC="${AM}" ;;
      claiming|booting) ICON="${BL}●${R}${BG}"; WORD="boot  " ; WC="${BL}" ;;
      waiting)    ICON="${MT}○${R}${BG}"; WORD="wait  " ; WC="${MT}" ;;
      *)          ICON="${AM}●${R}${BG}"; WORD="active" ; WC="${AM}" ;;
    esac
    # Fixed columns: icon(2) agent#(10) status(8) model(20) task(rest)
    printf "${BG}  ${ICON} ${B}${TX}Agent #${i}${R}${BG}  ${WC}${WORD}${R}${BG}  ${G}%-20s${R}${BG}  ${TX}${TASK_NAME}${R}${BG}${R}\n" "${MODEL_NAME}"
  done

  # Line 11: Divider
  printf "${BG} ${MT}"
  printf '─%.0s' $(seq 1 $((COLS - 2)))
  printf "${R}\n"

  # Line 12: Narration hint or completion
  if [[ $DONE -ge $TOTAL && $TOTAL -gt 0 ]]; then
    printf "${BG} ${GN}${B}All ${TOTAL} agents finished!${R}${BG}  ${MT}Results ready for merge. This was a demo — no real changes were made.${R}\n"
    sleep 3600
  else
    HINT_IDX=$(( (ELAPSED / 6) % ${#HINTS[@]} ))
    printf "${BG} ${G}🦬${R}${BG} ${TX}${HINTS[$HINT_IDX]}${R}\n"
  fi

  sleep 3
done
MONITOR_EOF
chmod +x /tmp/stampede-demo-monitor.sh

# ─── Build tmux session ─────────────────────────────────────────
echo "🦬 Terminal Stampede — Demo Mode"
echo "   Agents: $WORKERS | Speed: $SPEED"
echo ""

tmux new-session -d -s "$SESSION" -x 120 -y 39 "/tmp/stampede-demo-monitor.sh $WORKERS"
tmux rename-window -t "$SESSION" "🦬 Stampede Demo"

# Styling
tmux set-option -t "$SESSION" pane-border-style "fg=colour238"
tmux set-option -t "$SESSION" pane-active-border-style "fg=colour220"
tmux set-option -t "$SESSION" status-style "bg=colour233,fg=colour220"
tmux set-option -t "$SESSION" status-left " ⚡ DEMO "
tmux set-option -t "$SESSION" status-right " 🦬 Terminal Stampede "

# Create agent panes — re-tile after each to keep panes large enough for next split
for i in $(seq 1 "$WORKERS"); do
  if ! tmux split-window -t "$SESSION" "/tmp/stampede-demo-w${i}.sh" 2>/dev/null; then
    # If split fails, try splitting the largest pane instead
    LARGEST=$(tmux list-panes -t "$SESSION" -F '#{pane_index} #{pane_height}' | sort -k2 -rn | head -1 | awk '{print $1}')
    tmux split-window -t "$SESSION:0.$LARGEST" "/tmp/stampede-demo-w${i}.sh"
  fi
  tmux select-layout -t "$SESSION" tiled 2>/dev/null || true
done

# Verify all panes created
PANE_COUNT=$(tmux list-panes -t "$SESSION" | wc -l | xargs)
EXPECTED=$((WORKERS + 1))
if [[ $PANE_COUNT -ne $EXPECTED ]]; then
  echo "⚠ Only $PANE_COUNT/$EXPECTED panes created. Terminal may be too small."
fi

# ─── Apply 2-row grid layout ────────────────────────────────────
sleep 0.5
python3 << PYEOF
import subprocess

W, H = 120, 38
monitor_h = 12
workers = $WORKERS
sep = 1

remaining = H - monitor_h - sep
row1_count = (workers + 1) // 2
row2_count = workers - row1_count

if row2_count > 0:
    row1_h = remaining // 2
    row2_h = remaining - row1_h - sep
else:
    row1_h = remaining
    row2_h = 0

result = subprocess.run(['tmux', 'list-panes', '-t', '$SESSION', '-F', '#{pane_id}'],
                       capture_output=True, text=True)
pids = [int(p.strip().replace('%', '')) for p in result.stdout.strip().split('\n')]

def pane(w, h, x, y, pid): return f"{w}x{h},{x},{y},{pid}"
def hsplit(w, h, x, y, ch): return f"{w}x{h},{x},{y}{{{','.join(ch)}}}"

p0 = pane(W, monitor_h, 0, 0, pids[0])

def make_row(count, h, y, start_idx):
    seps = count - 1
    w_each = (W - seps) // count
    panes = []
    for i in range(count):
        pw = W - (count - 1) * (w_each + 1) if i == count - 1 else w_each
        px = i * (w_each + 1)
        panes.append(pane(pw, h, px, y, pids[start_idx + i]))
    return hsplit(W, h, 0, y, panes)

r1_y = monitor_h + sep
row1 = make_row(row1_count, row1_h, r1_y, 1)

parts = [p0, row1]
if row2_count > 0:
    r2_y = r1_y + row1_h + sep
    row2 = make_row(row2_count, row2_h, r2_y, 1 + row1_count)
    parts.append(row2)

body = f"{W}x{H},0,0[{','.join(parts)}]"
csum = 0
for c in body:
    csum = (csum >> 1) + ((csum & 1) << 15)
    csum = (csum + ord(c)) & 0xFFFF

layout = f"{csum:04x},{body}"
subprocess.run(['tmux', 'select-layout', '-t', '$SESSION', layout])
PYEOF

# ─── Focus mode keybindings ─────────────────────────────────────
for i in $(seq 1 "$WORKERS"); do
  tmux bind-key -T root "F$i" select-pane -t "$SESSION:0.$i" \; resize-pane -Z -t "$SESSION:0.$i"
done
tmux bind-key -T root F9 if-shell "tmux display-message -p '#{window_zoomed_flag}' | grep -q 1" "resize-pane -Z" "select-pane -t $SESSION:0.0"

# ─── Open Terminal window with boot sequence ────────────────────
ATTACH_SCRIPT=$(mktemp /tmp/stampede-demo-attach-XXXXXX.sh)
cat > "$ATTACH_SCRIPT" << ATTACH_EOF
#!/usr/bin/env bash
clear
printf "\033[?25l"
trap 'printf "\033[?25h\033[0m"' EXIT

G="\033[38;5;220m"; DG="\033[38;5;178m"; GN="\033[38;5;46m"
MT="\033[38;5;240m"; TX="\033[38;5;252m"
B="\033[1m"; R="\033[0m"; BG="\033[48;5;233m"

# Typewriter effect
typeout() {
  local text="\$1"
  local delay=\${2:-0.02}
  for (( i=0; i<\${#text}; i++ )); do
    printf "%s" "\${text:\$i:1}"
    sleep \$delay
  done
  printf "\n"
}

# ─── Logo ───
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
       ┃                               |_|            DEMO MODE          ┃
       ┃                                                                 ┃
       ╰━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━╯
ART
printf "\${R}"

sleep 1

# ─── Fullscreen prompt ───
printf "\n"
printf "  \${B}\${G}▶ Expand your terminal to full screen for the best experience.\${R}\n"
printf "  \${MT}  (Cmd+F on Mac, F11 on Linux/Windows)\${R}\n"
printf "\n"
sleep 5

# ─── About (from README) ───
printf "  \${B}\${TX}🦬 One terminal. ${WORKERS} AI agents. All running at the same time.\${R}\n"
printf "\n"
printf "  \${TX}You've been doing AI coding one task at a time. Ask, wait, ask again.\${R}\n"
printf "  \${TX}Terminal Stampede splits your terminal into ${WORKERS} panes, drops an AI agent\${R}\n"
printf "  \${TX}into each one, and lets them all charge through your codebase simultaneously.\${R}\n"
printf "  \${TX}Each agent gets its own brain, its own branch, its own mission.\${R}\n"
printf "  \${TX}You watch them work in real time.\${R}\n"
printf "\n"
sleep 5

printf "  \${G}Zero infrastructure.\${R}  \${TX}No Redis, no Docker, no cloud. Just files and tmux.\${R}\n"
printf "  \${G}Human in the loop.\${R}    \${TX}Every agent runs in a visible pane. Zoom in, type\${R}\n"
printf "                          \${TX}into it, or just watch. You're in the room while\${R}\n"
printf "                          \${TX}it's happening.\${R}\n"
printf "  \${G}tmux is the runtime.\${R}  \${TX}Each pane is a full CLI agent session with its\${R}\n"
printf "                          \${TX}own context window. The filesystem is the\${R}\n"
printf "                          \${TX}message bus. Point it at any repo.\${R}\n"
printf "\n"
sleep 6

# ─── This demo ───
printf "  \${MT}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\${R}\n"
printf "\n"
printf "  \${G}This demo\${R} simulates ${WORKERS} agents building features for a web app.\n"
printf "  No real code changes are made. It's a visual walkthrough.\n"
printf "\n"
sleep 4

# ─── How to interact ───
printf "  \${B}\${G}Here's what you can do:\${R}\n"
printf "\n"
printf "  \${TX}Click any box\${R}      Select that agent and watch it work\n"
printf "  \${TX}F1-F${WORKERS}\${R}            Zoom an agent to full screen\n"
printf "  \${TX}F9\${R}               Return to the grid view\n"
printf "  \${TX}Ctrl+B [\${R}         Scroll up through an agent's history\n"
printf "  \${TX}Type into it\${R}     You can interact with any agent directly\n"
printf "\n"
sleep 5

# ─── System checks (boot sequence) ───
printf "  \${MT}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\${R}\n"
printf "\n"
CHECKS=("Initializing fleet" "Loading task manifests" "Spawning ${WORKERS} AI agents" "Connecting monitors" "Engaging stampede")
for i in "\${!CHECKS[@]}"; do
  printf "  \${MT}[\${R}\${GN}✓\${R}\${MT}]\${R} \${TX}\${CHECKS[\$i]}\${R}"
  sleep 0.5
  printf "\n"
done

sleep 0.5

# ─── Progress bar sweep ───
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

sleep 0.5

printf "\n  \${B}\${G}⚡ STAMPEDE ONLINE\${R}  \${MT}${WORKERS} agents deployed\${R}\n"
printf "\n"
printf "  \${MT}Attaching in 3...\${R}"; sleep 1
printf "\r  \${MT}Attaching in 2...\${R}"; sleep 1
printf "\r  \${MT}Attaching in 1...\${R}"; sleep 1

# Signal agents to start
touch /tmp/stampede-demo-start

printf "\033[?25h"
tmux attach -t stampede-demo
ATTACH_EOF
chmod +x "$ATTACH_SCRIPT"
open -a Terminal "$ATTACH_SCRIPT"

echo ""
echo "🦬 Demo launched! Watch the Terminal window."
echo "   F1-F${WORKERS}: Focus on an agent | F9: Back to grid"
