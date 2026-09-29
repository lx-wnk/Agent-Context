#!/usr/bin/env bash
# tests/run-all.sh — runs every test suite even if one fails, then reports all results.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

suites=(
    tests/install.sh
    tests/check-template-coverage.sh
    tests/check-token-budget-unit.sh
    tests/check-token-budget.sh
    tests/check-measure-baseline-unit.sh
    tests/check-memory-prune-unit.sh
    tests/check-hooks-unit.sh
    tests/check-discovery-digest-unit.sh
    tests/check-map-budget-unit.sh
    tests/check-setup-steps-unit.sh
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

echo ""
echo "== Summary =="
for result in "${results[@]}"; do
    echo "$result"
done

exit "$failed"
