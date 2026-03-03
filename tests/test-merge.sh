#!/usr/bin/env bash
# Smoke test for stampede-merge.sh
# Tests: seal verification, ancestor detection, fuzzy branch matching, per-agent scoring
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
MERGE="$REPO/bin/stampede-merge.sh"
RUN_ID="run-test-smoke"
BASE="$REPO/.stampede/$RUN_ID"
PASS=0
FAIL=0

cleanup() {
    cd "$REPO"
    git checkout main -q 2>/dev/null || true
    git branch -D stampede/task-smoke-001 stampede/task-smoke-002-work \
        "stampede/merged-$RUN_ID" 2>/dev/null || true
    rm -rf "$BASE"
}
trap cleanup EXIT

ok()   { PASS=$((PASS + 1)); echo "  ✅ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ❌ $1"; }

echo "🧪 Stampede merge smoke tests"
echo ""

# ─── Setup ────────────────────────────────────────────────────────────────────
cleanup 2>/dev/null
mkdir -p "$BASE"/{queue,claimed,results,logs,sealed-tests}
echo '{"run_id":"'"$RUN_ID"'","total_tasks":2,"repo_path":"'"$REPO"'","phase":"running"}' > "$BASE/state.json"

cd "$REPO"
git checkout main -q

# Branch 1: standard name
git checkout -b stampede/task-smoke-001 -q
echo "<!-- smoke test -->" >> CONTRIBUTING.md
git add -A && git commit -m "stampede(task-smoke-001): test" -q

# Branch 2: non-standard name (tests fuzzy match)
git checkout main -q
git checkout -b stampede/task-smoke-002-work -q
echo "<!-- smoke test -->" >> CODE_OF_CONDUCT.md
git add -A && git commit -m "stampede(task-smoke-002): test" -q
git checkout main -q

# Result JSONs — task-smoke-002 has wrong branch name (triggers fuzzy match)
for tid in task-smoke-001 task-smoke-002; do
    if [ "$tid" = "task-smoke-001" ]; then
        branch="stampede/task-smoke-001"
        files='["CONTRIBUTING.md"]'
    else
        branch="stampede/task-smoke-002"
        files='["CODE_OF_CONDUCT.md"]'
    fi
    cat > "$BASE/results/$tid.json" << RESULT
{"task_id":"$tid","run_id":"$RUN_ID","worker_id":"worker-test","status":"done",
 "generation":0,"branch":"$branch","files_changed":$files,
 "summary":"Test change","word_count":2,"completed_at":"2026-01-01T00:00:00Z"}
RESULT
done

# Sealed tests
cat > "$BASE/sealed-tests/task-smoke-001.sh" << 'SEAL'
#!/usr/bin/env bash
grep -q "smoke test" CONTRIBUTING.md
SEAL
cat > "$BASE/sealed-tests/task-smoke-002.sh" << 'SEAL'
#!/usr/bin/env bash
grep -q "smoke test" CODE_OF_CONDUCT.md
SEAL
chmod +x "$BASE/sealed-tests/"*.sh

# Seal hash
find "$BASE/sealed-tests" -name "*.sh" -print0 | sort -z | while IFS= read -r -d '' f; do shasum -a 256 < "$f"; done | shasum -a 256 > "$BASE/sealed-tests/.seal-hash"

# ─── Test 1: Full merge succeeds ─────────────────────────────────────────────
echo "Test 1: Full merge"
output=$("$MERGE" --run-id "$RUN_ID" --repo "$REPO" 2>&1) || true

# ─── Test 2: Seal verified ───────────────────────────────────────────────────
echo "Test 2: Seal verification"
echo "$output" | grep -q "Seal verified" && ok "Seal hash verified" || fail "Seal hash not verified"

# ─── Test 3: Fuzzy branch match ──────────────────────────────────────────────
echo "Test 3: Fuzzy branch matching"
echo "$output" | grep -q "using stampede/task-smoke-002-work" && ok "Fuzzy match found -work branch" || fail "Fuzzy branch match failed"

# ─── Test 4: Shadow Score 0% ────────────────────────────────────────────────
echo "Test 4: Sealed test scoring"
echo "$output" | grep -q "Shadow Score: 0%" && ok "Shadow Score 0% (perfect)" || fail "Shadow Score not 0%"

# ─── Test 5: Per-agent test_impact = 10 ─────────────────────────────────────
echo "Test 5: Per-agent sealed scoring"
echo "$output" | grep -q "50.0" && ok "Agent scored 50/50 with sealed pass" || fail "Agent score not 50/50"

# ─── Test 6: Tamper detection ────────────────────────────────────────────────
echo "Test 6: Tamper detection"
echo "# tampered" >> "$BASE/sealed-tests/task-smoke-001.sh"
cd "$REPO" && git checkout main -q && git branch -D "stampede/merged-$RUN_ID" 2>/dev/null || true
output2=$("$MERGE" --run-id "$RUN_ID" --repo "$REPO" 2>&1) || true
echo "$output2" | grep -q "SEAL BROKEN" && ok "Tamper detected" || fail "Tamper not detected"

# Restore sealed test for remaining tests
cat > "$BASE/sealed-tests/task-smoke-001.sh" << 'SEAL'
#!/usr/bin/env bash
grep -q "smoke test" CONTRIBUTING.md
SEAL
find "$BASE/sealed-tests" -name "*.sh" -print0 | sort -z | while IFS= read -r -d '' f; do shasum -a 256 < "$f"; done | shasum -a 256 > "$BASE/sealed-tests/.seal-hash"

# ─── Test 7: Ancestor detection ──────────────────────────────────────────────
echo "Test 7: Ancestor detection"
cd "$REPO" && git checkout main -q && git branch -D "stampede/merged-$RUN_ID" 2>/dev/null || true
git merge stampede/task-smoke-001 -q --no-edit 2>/dev/null
output3=$("$MERGE" --run-id "$RUN_ID" --repo "$REPO" 2>&1) || true
echo "$output3" | grep -q "already in main" && ok "Ancestor branch skipped" || fail "Ancestor not skipped"
git reset --hard HEAD~1 -q

# ─── Results ─────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Results: $PASS passed, $FAIL failed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
