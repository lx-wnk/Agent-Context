#!/usr/bin/env bash
# tests/run-all.sh — runs every test suite even if one fails, then reports all results.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

suites=(
    tests/install.sh
    tests/check-template-coverage.sh
    tests/check-token-budget.sh
    tests/check-memory-prune-unit.sh
    tests/check-hooks-unit.sh
    tests/check-install-smoke.sh
    tests/check-local-source.sh
)

results=()
failed=0

for suite in "${suites[@]}"; do
    if bash "$suite"; then
        results+=("PASS $suite")
    else
        results+=("FAIL $suite")
        failed=1
    fi
done

if node --test scripts/*.test.mjs; then
    results+=("PASS node --test scripts/*.test.mjs")
else
    results+=("FAIL node --test scripts/*.test.mjs")
    failed=1
fi

echo ""
echo "== Summary =="
for result in "${results[@]}"; do
    echo "$result"
done

exit "$failed"
