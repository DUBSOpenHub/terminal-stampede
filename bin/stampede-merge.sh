#!/usr/bin/env bash
set -euo pipefail

# stampede-merge.sh — Auto-merge all stampede branches into one combined branch
# Usage: stampede-merge.sh --run-id <id> --repo <path> [--model <model>]

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
        # Verify branch exists in git
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

BRANCH_LIST=$(IFS=,; echo "${SORTED_BRANCHES[*]}")

# ─── Launch Merger Agent ─────────────────────────────────────────────────────
PROMPT="You are the stampede merger for run ${RUN_ID}. FOLLOW YOUR AGENT INSTRUCTIONS EXACTLY.
RUN_DIR=${BASE_DIR}
REPO_PATH=${REPO_PATH}
BRANCHES=${BRANCH_LIST}
Merge all branches into stampede/merged-${RUN_ID}. Sort by file count (already sorted). Resolve conflicts using task descriptions from ${RESULTS_DIR}/*.json. Write merge report to ${BASE_DIR}/merge-report.json."

echo "🦬 Launching merger agent..."
echo "  Model: $MODEL"
echo "  Merge order: ${SORTED_BRANCHES[*]}"
echo ""

cd "$REPO_PATH"
gh copilot -- \
    --agent stampede-merger \
    --model "$MODEL" \
    --allow-all-tools \
    --autopilot \
    --max-autopilot-continues 30 \
    --no-ask-user \
    -p "$PROMPT"

# ─── Report Results ──────────────────────────────────────────────────────────
echo ""
if [[ -f "$BASE_DIR/merge-report.json" ]]; then
    echo "🦬 Merge Report:"
    python3 -c "
import json
with open('$BASE_DIR/merge-report.json') as f:
    report = json.load(f)
s = report.get('summary', {})
print(f\"  ✅ Clean merges:    {s.get('clean', 0)}\")
print(f\"  🔧 Resolved:       {s.get('resolved', 0)}\")
print(f\"  ⚠️  Skipped:        {s.get('skipped', 0)}\")
print(f\"  📌 Merged branch:  {report.get('merged_branch', '?')}\")
for b, info in report.get('branches', {}).items():
    status = info.get('status', '?')
    icon = {'clean': '✅', 'resolved': '🔧', 'skipped': '⚠️'}.get(status, '❓')
    detail = ''
    if status == 'resolved':
        detail = f\" ({info.get('conflicts_resolved', 0)} conflicts resolved)\"
    elif status == 'skipped':
        detail = f\" — {info.get('reason', 'unknown')}\"
    print(f\"    {icon} {b}{detail}\")
" 2>/dev/null || echo "  (merge report exists but couldn't parse)"
else
    echo "⚠️  No merge report found — check agent output above"
fi

echo ""
echo "═══════════════════════════════════════════"
echo "  🦬 Merge complete!"
echo "  Review: git log --oneline stampede/merged-${RUN_ID}"
echo "  Diff:   git diff main...stampede/merged-${RUN_ID}"
echo "═══════════════════════════════════════════"
