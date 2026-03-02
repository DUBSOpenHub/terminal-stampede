#!/usr/bin/env bash
# Terminal Stampede — ANSI Color Reference
# Source this file: source stampede-colors.sh
C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'

# Brand gold
C_GOLD=$'\033[38;2;245;166;35m'
C_GOLD_BRIGHT=$'\033[38;2;255;215;0m'
C_GOLD_DIM=$'\033[38;2;184;134;11m'

# Backgrounds
C_BG_SURFACE=$'\033[48;2;18;18;26m'

# Text
C_TEXT=$'\033[38;2;232;232;237m'
C_TEXT_SEC=$'\033[38;2;152;152;166m'
C_TEXT_DIM=$'\033[38;2;92;92;110m'

# Status
C_WORKING=$'\033[38;2;74;222;128m'
C_IDLE=$'\033[38;2;100;116;139m'
C_DONE=$'\033[38;2;56;189;248m'
C_FAILED=$'\033[38;2;248;113;113m'
C_CONFLICT=$'\033[38;2;251;146;60m'
C_CLAIMING=$'\033[38;2;192;132;252m'
