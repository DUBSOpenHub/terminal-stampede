#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
#  ⚡ TERMINAL STAMPEDE — Live Dashboard Renderer
#  Premium terminal-native dashboard for multi-agent orchestration
#  Usage:  ./dashboard.sh [--demo]
#  Works with bash 3.2+ (macOS default), supports truecolor terminals
# ═══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

# ── ANSI Color Tokens ─────────────────────────────────────────────────────────
R=$'\033[0m'; BO=$'\033[1m'; DI=$'\033[2m'
GO=$'\033[38;2;245;166;35m'; GB=$'\033[38;2;255;215;0m'; GD=$'\033[38;2;184;134;11m'
TX=$'\033[38;2;232;232;237m'; TS=$'\033[38;2;152;152;166m'; TD=$'\033[38;2;92;92;110m'
SW=$'\033[38;2;74;222;128m'; SI=$'\033[38;2;100;116;139m'; SD=$'\033[38;2;56;189;248m'
SF=$'\033[38;2;248;113;113m'; SC=$'\033[38;2;251;146;60m'; SP=$'\033[38;2;192;132;252m'
TL='╭'; TR='╮'; BLF='╰'; BR='╯'; VT='│'
SF_FRAMES=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')

DEMO_MODE=false
STAMPEDE_DIR="${STAMPEDE_DIR:-/tmp/stampede}"
for arg in "$@"; do case "$arg" in --demo) DEMO_MODE=true;; esac; done

hide_cursor() { printf '\033[?25l'; }
show_cursor() { printf '\033[?25h'; }
at()          { printf '\033[%d;%dH' "$1" "$2"; }
cls()         { printf '\033[2J\033[H'; }
rep() {
  local c="$1" n="$2" out=""
  (( n <= 0 )) && return
  local i; for (( i=0; i<n; i++ )); do out="${out}${c}"; done
  printf '%s' "$out"
}
trunc() {
  local s="$1" m="$2"
  if (( ${#s} > m )); then printf '%s' "${s:0:$((m-1))}…"
  else printf "%-${m}s" "$s"; fi
}

# Agent State (parallel indexed arrays — bash 3 compatible)
N=0
A_ID=(); A_ST=(); A_TK=(); A_BR=(); A_PG=(); A_TOK=(); A_EL=(); A_ACT=()
SPIN=0; T0=$(date +%s)

clr() {
  case "$1" in
    working) printf '%s' "$SW";; idle) printf '%s' "$SI";; done) printf '%s' "$SD";;
    failed) printf '%s' "$SF";; conflict) printf '%s' "$SC";; claiming) printf '%s' "$SP";;
    *) printf '%s' "$TD";;
  esac
}
ico() {
  case "$1" in
    working) printf '●';; idle) printf '○';; done) printf '✓';; failed) printf '✗';;
    conflict) printf '⚠';; claiming) printf '%s' "${SF_FRAMES[$SPIN]}";;
    *) printf '○';;
  esac
}
add_agent() {
  A_ID[$N]="$1"; A_ST[$N]="$2"; A_TK[$N]="$3"; A_BR[$N]="$4"
  A_PG[$N]="$5"; A_TOK[$N]="$6"; A_EL[$N]="$7"; A_ACT[$N]="$8"
  N=$((N + 1))
}

load_demo() {
  N=0; A_ID=(); A_ST=(); A_TK=(); A_BR=(); A_PG=(); A_TOK=(); A_EL=(); A_ACT=()
  add_agent "alpha"   "working"  "Implement JWT auth"   "stampede/jwt-auth"   "$((RANDOM%55+20))" "$((RANDOM%120+30))" "$((RANDOM%7+1))m$((RANDOM%59))s" "Editing auth.ts"
  add_agent "bravo"   "working"  "Build REST API"       "stampede/api"        "$((RANDOM%55+20))" "$((RANDOM%120+30))" "$((RANDOM%7+1))m$((RANDOM%59))s" "POST /api/users"
  add_agent "charlie" "done"     "Add DB migrations"    "stampede/db-migrate" "100" "187" "5m12s" "14 migrations done ✓"
  add_agent "delta"   "working"  "Create React dash"    "stampede/react-dash" "$((RANDOM%55+20))" "$((RANDOM%80+30))"  "$((RANDOM%7+1))m$((RANDOM%59))s" "Building StatusGrid"
  add_agent "echo"    "claiming" "Set up CI/CD"         "stampede/cicd"       "8"   "2"   "0m04s" "Claiming task..."
  add_agent "foxtrot" "working"  "Write integ tests"    "stampede/integ-test" "$((RANDOM%55+20))" "$((RANDOM%120+30))" "$((RANDOM%7+1))m$((RANDOM%59))s" "47/62 tests pass"
  add_agent "golf"    "failed"   "Config Docker"        "stampede/docker"     "0"   "0"   "—"     "Port 5432 conflict"
  add_agent "hotel"   "idle"     "Add WebSocket"        "stampede/websocket"  "0"   "0"   "—"     "Waiting for task"
  SPIN=$(( (SPIN + 1) % 10 ))
}

load_live() {
  N=0; A_ID=(); A_ST=(); A_TK=(); A_BR=(); A_PG=(); A_TOK=(); A_EL=(); A_ACT=()
  local f nm
  for f in "$STAMPEDE_DIR"/claimed/*.task; do
    [ -f "$f" ] || continue; nm=$(basename "$f" .task)
    add_agent "$nm" "working" "$nm" "stampede/$nm" "$((RANDOM%80+10))" "0" "—" "Processing..."
  done
  for f in "$STAMPEDE_DIR"/results/*.result; do
    [ -f "$f" ] || continue; nm=$(basename "$f" .result)
    add_agent "$nm" "done" "$nm" "stampede/$nm" "100" "0" "done" "Completed"
  done
  for f in "$STAMPEDE_DIR"/queue/*.task; do
    [ -f "$f" ] || continue; nm=$(basename "$f" .task)
    add_agent "$nm" "idle" "$nm" "—" "0" "0" "—" "Queued"
  done
  SPIN=$(( (SPIN + 1) % 10 ))
}

# ═══════════════════════════════════════════════════════════════════════════════
#  RENDER COMPONENTS
# ═══════════════════════════════════════════════════════════════════════════════

draw_header() {
  local W=$1
  local elapsed=$(( $(date +%s) - T0 ))
  local m=$((elapsed/60)) s=$((elapsed%60))
  local nw=0 nd=0 nf=0 i
  for (( i=0; i<N; i++ )); do
    case "${A_ST[$i]}" in working|claiming) nw=$((nw+1));; done) nd=$((nd+1));; failed) nf=$((nf+1));; esac
  done
  at 1 1; printf '%s%s  ⚡ T E R M I N A L   S T A M P E D E%s' "$GB" "$BO" "$R"
  local rp=$((W - 48)); (( rp < 42 )) && rp=42
  at 1 "$rp"
  printf '%s●%s %d active  %s✓%s %d done  ' "$SW" "$TX" "$nw" "$SD" "$TX" "$nd"
  (( nf > 0 )) && printf '%s✗%s %d fail  ' "$SF" "$TX" "$nf"
  printf '%s⏱%s %dm%02ds%s' "$GD" "$TX" "$m" "$s" "$R"
  at 2 1; printf '%s' "$GD"; rep '━' "$W"; printf '%s' "$R"
}

draw_bar() {
  local row=$1 col=$2 w=$3 pct=$4
  local fill=$(( (pct * w) / 100 )); local empty=$(( w - fill ))
  at "$row" "$col"
  if (( fill > 0 )); then
    local s1=$(( fill / 3 )) s2=$(( fill / 3 )) s3=$(( fill - fill/3 - fill/3 ))
    printf '%s' "$GD";  (( s1 > 0 )) && rep '█' "$s1"
    printf '%s' "$GO";  (( s2 > 0 )) && rep '█' "$s2"
    printf '%s' "$GB";  (( s3 > 0 )) && rep '█' "$s3"
  fi
  printf '%s' "$TD"; (( empty > 0 )) && rep '░' "$empty"
  printf '%s' "$R"
}

draw_card() {
  local row=$1 col=$2 w=$3 idx=$4
  local st="${A_ST[$idx]}"; local c; c=$(clr "$st"); local ic; ic=$(ico "$st")
  local inner=$((w - 2)) id="${A_ID[$idx]}" pg="${A_PG[$idx]}"
  local task="${A_TK[$idx]}" branch="${A_BR[$idx]}"
  local act="${A_ACT[$idx]}" tok="${A_TOK[$idx]}" elapsed="${A_EL[$idx]}"

  # Top border
  at "$row" "$col"; printf '%s%s' "$c" "$TL"; rep '─' "$inner"; printf '%s%s' "$TR" "$R"

  # Line 1: icon  name  status
  at $((row+1)) "$col"
  printf '%s%s%s %s%s%s %s%s' "$c" "$VT" "$R" "$c" "$ic" "$R" "$BO$TX" ""
  trunc "$id" $((inner - ${#st} - 5))
  printf '%s %s%s%s %s%s%s' "$R" "$c" "$st" "$R" "$c" "$VT" "$R"

  # Line 2: task
  at $((row+2)) "$col"; printf '%s%s%s  %s' "$c" "$VT" "$R" "$TS"
  trunc "$task" $((inner - 3)); printf '%s' "$R"
  at $((row+2)) $((col+w-1)); printf '%s%s%s' "$c" "$VT" "$R"

  # Line 3: branch + tokens
  at $((row+3)) "$col"; printf '%s%s%s  %s⎇ ' "$c" "$VT" "$R" "$TD"
  trunc "$branch" $((inner - 16))
  (( tok > 0 )) && printf ' %s%3dk tok' "$TD" "$tok"
  printf '%s' "$R"; at $((row+3)) $((col+w-1)); printf '%s%s%s' "$c" "$VT" "$R"

  # Line 4: progress bar
  at $((row+4)) "$col"; printf '%s%s%s ' "$c" "$VT" "$R"
  local bw=$((inner - 8))
  case "$st" in
    working|claiming) draw_bar $((row+4)) $((col+2)) "$bw" "$pg"; printf ' %s%3d%%%s' "$TS" "$pg" "$R";;
    done)   printf '%s' "$SD"; rep '█' "$bw"; printf ' %s100%%%s' "$SD" "$R";;
    failed) printf '%s' "$SF"; rep '░' "$bw"; printf ' %sERR!%s' "$SF" "$R";;
    *)      printf '%s' "$TD"; rep '░' "$bw"; printf '  %s—%s' "$TD" "$R";;
  esac
  at $((row+4)) $((col+w-1)); printf '%s%s%s' "$c" "$VT" "$R"

  # Line 5: activity + elapsed
  at $((row+5)) "$col"; printf '%s%s%s  %s› ' "$c" "$VT" "$R" "$TD"
  trunc "$act" $((inner - 13)); printf ' %s%6s%s' "$TD" "$elapsed" "$R"
  at $((row+5)) $((col+w-1)); printf '%s%s%s' "$c" "$VT" "$R"

  # Bottom border
  at $((row+6)) "$col"; printf '%s%s' "$c" "$BLF"; rep '─' "$inner"; printf '%s%s' "$BR" "$R"
}

draw_overall() {
  local row=$1 col=$2 w=$3 sum=0 nd=0 i
  for (( i=0; i<N; i++ )); do
    sum=$(( sum + ${A_PG[$i]} )); [[ "${A_ST[$i]}" == "done" ]] && nd=$((nd+1))
  done
  local pct=0; (( N > 0 )) && pct=$(( sum / N ))
  at "$row" "$col"; printf '%s%s⚡ OVERALL PROGRESS%s  %s%d/%d tasks%s' "$GB" "$BO" "$R" "$TS" "$nd" "$N" "$R"
  draw_bar $((row+1)) "$col" $((w - 10)) "$pct"
  printf ' %s%s%3d%%%s' "$GB" "$BO" "$pct" "$R"
  at $((row+2)) "$col"
  if (( pct > 0 && pct < 100 )); then
    local e=$(( $(date +%s) - T0 )); local eta=$(( (e * (100 - pct)) / pct ))
    printf '%sETA: ~%dm %02ds remaining%s' "$TD" "$((eta/60))" "$((eta%60))" "$R"
  elif (( pct >= 100 )); then printf '%s%s✓ All tasks completed!%s' "$SD" "$BO" "$R"
  else printf '%sAwaiting agents...%s' "$TD" "$R"; fi
}

draw_sidebar() {
  local row=$1 col=$2 w=$3 total_tok=0 i
  for (( i=0; i<N; i++ )); do total_tok=$(( total_tok + ${A_TOK[$i]} )); done
  local cc=$(( total_tok * 4 / 100 ))

  # Resources
  at "$row" "$col"; printf '%s%s◆ RESOURCES%s' "$GO" "$BO" "$R"
  at $((row+1)) "$col"; printf '%sTokens   %s%dk%s' "$TD" "$TX" "$total_tok" "$R"
  at $((row+2)) "$col"; printf '%sEst Cost %s$%d.%02d%s' "$TD" "$TX" "$((cc/100))" "$((cc%100))" "$R"
  at $((row+3)) "$col"; printf '%sAgents   %s%d%s' "$TD" "$TX" "$N" "$R"

  # Conflicts
  at $((row+5)) "$col"; printf '%s%s⚠ CONFLICTS%s' "$SC" "$BO" "$R"
  if $DEMO_MODE; then
    at $((row+6)) "$col"; printf '%ssrc/config/database.ts%s' "$SC" "$R"
    at $((row+7)) "$col"; printf '%scharlie ↔ foxtrot%s' "$TD" "$R"
    at $((row+8)) "$col"; printf '%sBoth edit lines 15-28%s' "$TD" "$R"
  else
    at $((row+6)) "$col"; printf '%sNone detected%s' "$TD" "$R"
  fi

  # Activity feed
  at $((row+10)) "$col"; printf '%s%s◆ ACTIVITY%s' "$GO" "$BO" "$R"
  if $DEMO_MODE; then
    at $((row+11)) "$col"; printf '%s✓%s charlie    %s14 migrations done%s'  "$SD" "$R" "$TD" "$R"
    at $((row+12)) "$col"; printf '%s●%s alpha      %sWriting JWT verify%s'  "$SW" "$R" "$TD" "$R"
    at $((row+13)) "$col"; printf '%s◐%s echo       %sClaiming CI/CD...%s'   "$SP" "$R" "$TD" "$R"
    at $((row+14)) "$col"; printf '%s●%s foxtrot    %s47/62 tests pass%s'    "$SW" "$R" "$TD" "$R"
    at $((row+15)) "$col"; printf '%s⚠%s system     %sConflict: db.ts%s'     "$SC" "$R" "$TD" "$R"
    at $((row+16)) "$col"; printf '%s●%s bravo      %sPOST /api/users%s'     "$SW" "$R" "$TD" "$R"
    at $((row+17)) "$col"; printf '%s●%s delta      %sStatusGrid comp%s'     "$SW" "$R" "$TD" "$R"
  fi
}

draw_footer() {
  local row=$1 W=$2
  at "$row" 1; printf '%s' "$GD"; rep '━' "$W"; printf '%s' "$R"
  at $((row+1)) 2
  printf '%s[q]%s Quit  %s[r]%s Refresh  %s[z]%s Zoom  %s[c]%s Conflicts  %s[l]%s Logs%s' \
    "$GO" "$TD" "$GO" "$TD" "$GO" "$TD" "$GO" "$TD" "$GO" "$TD" "$R"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  MAIN RENDER
# ═══════════════════════════════════════════════════════════════════════════════

render() {
  local W H
  W=$(tput cols 2>/dev/null || echo 120)
  H=$(tput lines 2>/dev/null || echo 40)
  $DEMO_MODE && load_demo || load_live
  if (( N == 0 )); then
    cls; at $((H/2-1)) $((W/2-16))
    printf '%s%s⚡ No stampede in progress%s' "$GB" "$BO" "$R"
    at $((H/2+1)) $((W/2-20))
    printf '%sWatching: %s%s' "$TD" "$STAMPEDE_DIR" "$R"; return
  fi
  cls; draw_header "$W"

  # Layout
  local sb_w=36 has_sb=0; (( W >= 120 )) && has_sb=1
  local gw=$W; (( has_sb )) && gw=$((W - sb_w - 1))
  local cpr=1; (( gw >= 110 )) && cpr=2
  local cw; if (( cpr == 2 )); then cw=$(( (gw - 3) / 2 )); else cw=$((gw - 2)); fi

  # Agent cards
  local crow=4 ci=0 i
  for (( i=0; i<N; i++ )); do
    local cc=2
    (( cpr == 2 && ci % 2 == 1 )) && cc=$((cw + 4))
    draw_card "$crow" "$cc" "$cw" "$i"
    ci=$((ci+1))
    if (( cpr == 2 )); then (( ci % 2 == 0 )) && crow=$((crow + 8))
    else crow=$((crow + 8)); fi
  done
  (( cpr == 2 && ci % 2 == 1 )) && crow=$((crow + 8))

  # Overall progress
  draw_overall $((crow + 1)) 2 "$gw"

  # Sidebar
  (( has_sb )) && draw_sidebar 4 $((W - sb_w + 1)) "$sb_w"

  # Footer
  draw_footer $((H - 2)) "$W"
}

cleanup() { show_cursor; printf '%s' "$R"; cls; printf '⚡ Stampede dashboard closed.\n'; exit 0; }
trap cleanup EXIT INT TERM

main() {
  hide_cursor
  while true; do
    render
    read -rsn1 -t 1 key 2>/dev/null && { case "$key" in q|Q) break;; esac; } || true
  done
}
main
