#!/usr/bin/env bash
# smoke-test.sh — Quick sanity check that stampede can launch and complete
# Run before committing changes to catch regressions early.
# Usage: ./tests/smoke-test.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

REPO_PATH=$(mktemp -d)
cd "$REPO_PATH" && git init -q && echo "test" > README.md && git add -A && git commit -q -m "init"

RUN_ID="run-smoke-$(date +%s)"
mkdir -p .stampede/$RUN_ID/{queue,claimed,results,logs,scripts,pids}

python3 -c "
import json
t = {'task_id': 'task-001', 'title': 'Smoke test', 'objective': 'Say SMOKE_OK and exit.', 'repo_path': '$REPO_PATH', 'generation': 0}
with open('.stampede/$RUN_ID/queue/task-001.json', 'w') as f: json.dump(t, f)
s = {'run_id': '$RUN_ID', 'base': '$REPO_PATH/.stampede/$RUN_ID', 'repo_path': '$REPO_PATH', 'model': 'claude-haiku-4.5', 'worker_count': 1, 'total_tasks': 1, 'phase': 'running'}
with open('.stampede/$RUN_ID/state.json', 'w') as f: json.dump(s, f)
"

echo "🧪 Smoke test: launching 1 agent..."
bash "$SCRIPT_DIR/bin/stampede.sh" --run-id "$RUN_ID" --count 1 --repo "$REPO_PATH" --model claude-haiku-4.5 --no-attach 2>&1 | tail -5

# Wait up to 90s for result
for i in $(seq 1 18); do
    sleep 5
    if [[ -f "$REPO_PATH/.stampede/$RUN_ID/results/task-001.json" ]]; then
        status=$(python3 -c "import json; print(json.load(open('$REPO_PATH/.stampede/$RUN_ID/results/task-001.json'))['status'])" 2>/dev/null)
        echo "✅ Smoke test PASSED ($((i*5))s) — status: $status"
        tmux kill-session -t "stampede-$RUN_ID" 2>/dev/null
        rm -rf "$REPO_PATH"
        exit 0
    fi
done

echo "❌ Smoke test FAILED — no result after 90s"
tmux kill-session -t "stampede-$RUN_ID" 2>/dev/null
rm -rf "$REPO_PATH"
exit 1
