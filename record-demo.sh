#!/usr/bin/env bash
set -euo pipefail

# record-demo.sh
# Records Terminal Stampede demo as an asciinema cast and converts to GIF.
# Shows multi-agent orchestration with visual boot sequence and runtime capture.
# Usage: ./record-demo.sh
# Requirements: asciinema, tmux, (optional) agg for GIF conversion
# Output: assets/demo.cast (and assets/demo.gif if agg is installed)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CAST_FILE="$SCRIPT_DIR/assets/demo.cast"
GIF_FILE="$SCRIPT_DIR/assets/demo.gif"

echo "🦬 Recording Terminal Stampede demo..."
echo ""

# Clean up
tmux kill-session -t stampede-demo 2>/dev/null || true
rm -f /tmp/stampede-demo-start /tmp/stampede-demo-attach-*.sh

# Create a combined script that does boot intro + tmux attach
cat > /tmp/stampede-record.sh << 'RECEOF'
#!/usr/bin/env bash
set -euo pipefail

G="\033[38;5;220m"; GN="\033[38;5;46m"
MT="\033[38;5;240m"; TX="\033[38;5;252m"
B="\033[1m"; R="\033[0m"

clear
printf "\033[?25l"
trap 'printf "\033[?25h\033[0m"' EXIT

# Logo
printf "${G}"
cat << 'ART'

       ╭━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━╮
       ┃                                                                 ┃
       ┃    t e r m i n a l                                              ┃
       ┃      _____ _                                   _                ┃
       ┃     / ____| |                                 | |               ┃
       ┃    | (___ | |_ __ _ _ __ ___  _ __   ___  __| | ___            ┃
       ┃     \___ \| __/ _` | '_ ` _ \| '_ \ / _ \/ _` |/ _ \           ┃
       ┃     ____) | || (_| | | | | | | |_) |  __/ (_| |  __/           ┃
       ┃    |_____/ \__\__,_|_| |_| |_| .__/ \___|\__,_|\___|           ┃
       ┃                               |_|            DEMO MODE          ┃
       ┃                                                                 ┃
       ╰━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━╯
ART
printf "${R}"
sleep 2

printf "\n"
printf "  ${B}${TX}🦬 One terminal. 8 AI agents. All running at the same time.${R}\n"
printf "\n"
sleep 2

CHECKS=("Initializing fleet" "Loading task manifests" "Spawning 8 AI agents" "Connecting monitors" "Engaging stampede")
for c in "${CHECKS[@]}"; do
  printf "  ${MT}[${R}${GN}✓${R}${MT}]${R} ${TX}${c}${R}\n"
  sleep 0.3
done
sleep 0.5

printf "\n  "
for i in $(seq 0 50); do
  PCT=$((i * 100 / 50))
  FILLED=$(printf '█%.0s' $(seq 1 $((i+1))))
  EMPTY=""
  [[ $i -lt 50 ]] && EMPTY=$(printf '░%.0s' $(seq 1 $((50 - i))))
  printf "\r  ${G}${FILLED}${R}${MT}${EMPTY}${R} ${B}${TX}${PCT}%%${R}"
  sleep 0.01
done
printf "\n"

printf "\n  ${B}${G}⚡ STAMPEDE ONLINE${R}\n\n"
sleep 1

# Signal workers and attach
touch /tmp/stampede-demo-start
printf "\033[?25h"
tmux attach -t stampede-demo
RECEOF
chmod +x /tmp/stampede-record.sh

# Launch demo in background (fast speed, no Terminal.app)
"$SCRIPT_DIR/bin/stampede-demo.sh" --speed fast 2>/dev/null &
sleep 3

# Record with asciinema
echo "Recording... (will auto-stop after 30 seconds)"
asciinema rec "$CAST_FILE" \
  --cols 120 --rows 40 \
  --idle-time-limit 2 \
  --command "timeout 30 /tmp/stampede-record.sh || true" \
  --overwrite

echo ""
echo "✅ Cast saved to $CAST_FILE"
echo ""

# Convert to GIF if agg is available
if command -v agg &>/dev/null; then
  agg --cols 120 --rows 40 "$CAST_FILE" "$GIF_FILE"
  echo "✅ GIF saved to $GIF_FILE"
else
  echo "💡 To convert to GIF, install agg:"
  echo "   brew install agg"
  echo "   agg $CAST_FILE $GIF_FILE"
fi
