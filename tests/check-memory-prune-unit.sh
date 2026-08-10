#!/usr/bin/env bash
# tests/check-memory-prune-unit.sh — unit tests for context/bin/memory-prune.sh
#
# Verifies decay semantics: expired entries archived, ttl:infinite kept, not-yet-expired
# kept, metadata-less lines kept, dry-run is non-destructive, index.md/todo.md skipped,
# and re-running is idempotent.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PRUNE="$REPO_ROOT/context/bin/memory-prune.sh"

PASS=0
FAIL=0
TMP_ROOTS=()
cleanup() { for d in "${TMP_ROOTS[@]:-}"; do [ -d "$d" ] && rm -rf "$d"; done; }
trap cleanup EXIT
mk_tmp() { local d; d=$(mktemp -d "${TMPDIR:-/tmp}/memprune-test.XXXXXX"); TMP_ROOTS+=("$d"); echo "$d"; }
pass() { printf "  PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
fail() { printf "  FAIL  %s\n    => %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }
assert_file_contains() { grep -qF "$3" "$2" 2>/dev/null && pass "$1" || fail "$1" "missing '$3' in $2"; }
assert_file_not_contains() { grep -qF "$3" "$2" 2>/dev/null && fail "$1" "unexpected '$3' in $2" || pass "$1"; }

# A fixture with one of each class. Dates are far in the past / future so the test is
# stable regardless of the run date (no Date.now coupling).
seed() {
    local dir="$1"
    mkdir -p "$dir"
    cat > "$dir/lessons.md" <<'EOF'
# Lessons Learned

- **[old]** Expired gotcha (2020-01-01) ttl:90d source:discovered conf:med
- **[arch]** Permanent rule (2020-01-01) ttl:infinite source:user conf:high
- **[future]** Long-lived (2099-01-01) ttl:30d source:discovered conf:med
- Plain note without metadata.
EOF
    cat > "$dir/index.md" <<'EOF'
# Memory Index
- **[skip]** index entry (2020-01-01) ttl:90d
EOF
}

# Fixture for default-resolution tests. Covers every branch of resolve_ttl:
# dated-untagged, explicit numeric ttl, explicit infinite, and no date at all.
seed_defaults() {
    local dir="$1"
    mkdir -p "$dir"
    cat > "$dir/lessons.md" <<'EOF'
# Lessons Learned

- **[untagged]** Dated but no ttl (2020-01-01) source:discovered conf:med
- **[explicit]** Short ttl beats the default (2020-01-01) ttl:30d source:user conf:high
- **[infinite]** Explicit infinite survives the default (2020-01-01) ttl:infinite source:user conf:high
- **[undated]** No date at all, immortal by definition source:user conf:low
EOF
    cat > "$dir/people.md" <<'EOF'
# Team & Stakeholders

- **Ada** — Backend lead (2020-01-01) source:user conf:high
EOF
    cat > "$dir/glossary.md" <<'EOF'
# Glossary

- **[term]** Unclassified file, no shared default (2020-01-01) source:user conf:low
EOF
}

echo "=== memory-prune unit tests ==="
echo ""

# 1. Dry-run is non-destructive.
t=$(mk_tmp); seed "$t/memory"
bash "$PRUNE" --dir "$t/memory" >/dev/null 2>&1
assert_file_contains "dry-run keeps expired entry in place" "$t/memory/lessons.md" "Expired gotcha"
[ -d "$t/memory/archive" ] && fail "dry-run creates no archive dir" "archive/ exists" || pass "dry-run creates no archive dir"

# 2. Apply archives expired, keeps the rest.
t=$(mk_tmp); seed "$t/memory"
bash "$PRUNE" --dir "$t/memory" --apply >/dev/null 2>&1
assert_file_not_contains "apply removes expired entry from source" "$t/memory/lessons.md" "Expired gotcha"
assert_file_contains "apply keeps ttl:infinite entry" "$t/memory/lessons.md" "Permanent rule"
assert_file_contains "apply keeps not-yet-expired entry" "$t/memory/lessons.md" "Long-lived"
assert_file_contains "apply keeps metadata-less line" "$t/memory/lessons.md" "Plain note without metadata"
arch=$(find "$t/memory/archive" -name '*.md' | head -1)
assert_file_contains "expired entry moved to archive" "$arch" "Expired gotcha"

# 3. index.md is skipped (never pruned).
assert_file_contains "index.md is not pruned" "$t/memory/index.md" "index entry"

# 4. Idempotent: second apply changes nothing more.
before=$(cat "$t/memory/lessons.md")
bash "$PRUNE" --dir "$t/memory" --apply >/dev/null 2>&1
after=$(cat "$t/memory/lessons.md")
[ "$before" = "$after" ] && pass "second apply is idempotent" || fail "second apply is idempotent" "file changed on re-run"

# 5. Shared defaults: dated-untagged expires, explicit ttl and undated lines survive.
t=$(mk_tmp); seed_defaults "$t/memory"
bash "$PRUNE" --dir "$t/memory" --conf "$t/absent.conf" --apply >/dev/null 2>&1
assert_file_not_contains "shared default expires a dated untagged entry" "$t/memory/lessons.md" "Dated but no ttl"
assert_file_not_contains "explicit ttl:30d still expires" "$t/memory/lessons.md" "Short ttl beats the default"
assert_file_contains "explicit ttl:infinite survives the file default" "$t/memory/lessons.md" "Explicit infinite survives"
assert_file_contains "undated line is never touched" "$t/memory/lessons.md" "No date at all"

# 6. Shared default infinite keeps people.md untouched.
assert_file_contains "shared default infinite keeps the entry" "$t/memory/people.md" "Backend lead"

# 7. A file with no shared default and no conf entry stays immortal.
assert_file_contains "unclassified file has no default" "$t/memory/glossary.md" "Unclassified file"

# 8. Conf key overrides the shared table; unlisted files keep the shared default (merge).
t=$(mk_tmp); seed_defaults "$t/memory"
cat > "$t/budget.conf" <<'EOF'
MEMORY_TTL_DEFAULTS="
lessons.md=infinite
glossary.md=90d
"
EOF
bash "$PRUNE" --dir "$t/memory" --conf "$t/budget.conf" --apply >/dev/null 2>&1
assert_file_contains "conf overrides shared default for lessons.md" "$t/memory/lessons.md" "Dated but no ttl"
assert_file_not_contains "conf adds a default for an unlisted file" "$t/memory/glossary.md" "Unclassified file"
assert_file_contains "unlisted file keeps its shared default (merge)" "$t/memory/people.md" "Backend lead"
# An explicit ttl must beat the file default even when the default is the more permissive one —
# with lessons.md=infinite, only "explicit wins" can expire this entry.
assert_file_not_contains "explicit ttl:30d expires under a file default of infinite" "$t/memory/lessons.md" "Short ttl beats the default"

# 9. Report distinguishes a default-driven expiry from an entry-declared one.
t=$(mk_tmp); seed_defaults "$t/memory"
out=$(bash "$PRUNE" --dir "$t/memory" --conf "$t/absent.conf" 2>&1)
printf '%s' "$out" | grep -qF "EXPIRED (default 90d) → - **[untagged]**" \
    && pass "report marks default-driven expiry" \
    || fail "report marks default-driven expiry" "missing marker in output"
printf '%s' "$out" | grep -qF "EXPIRED → - **[explicit]**" \
    && pass "report leaves entry-declared expiry unmarked" \
    || fail "report leaves entry-declared expiry unmarked" "missing plain marker in output"

# 10. Malformed conf exits 2 and writes nothing.
t=$(mk_tmp); seed_defaults "$t/memory"
before=$(cat "$t/memory/lessons.md")
for bad in 'lessons.md' 'lessons.md=7weeks' 'memory/lessons.md=90d'; do
    printf 'MEMORY_TTL_DEFAULTS="%s"\n' "$bad" > "$t/bad.conf"
    bash "$PRUNE" --dir "$t/memory" --conf "$t/bad.conf" --apply >/dev/null 2>&1
    rc=$?
    [ "$rc" -eq 2 ] && pass "malformed conf '$bad' exits 2" || fail "malformed conf '$bad' exits 2" "got exit $rc"
done
after=$(cat "$t/memory/lessons.md")
[ "$before" = "$after" ] && pass "malformed conf leaves files untouched" || fail "malformed conf leaves files untouched" "file changed"

# 11. Expanded domains are scanned; the archive directory is not re-scanned.
t=$(mk_tmp); mkdir -p "$t/memory/cart"
cat > "$t/memory/lessons.md" <<'EOF'
# Lessons Learned

- **[top]** Top-level expired (2020-01-01) ttl:90d source:discovered conf:med
EOF
cat > "$t/memory/cart/pricing.md" <<'EOF'
# Cart Pricing

- **[nested]** Nested expired (2020-01-01) ttl:90d source:discovered conf:med
EOF
bash "$PRUNE" --dir "$t/memory" --conf "$t/absent.conf" --apply >/dev/null 2>&1
assert_file_not_contains "nested domain file is pruned" "$t/memory/cart/pricing.md" "Nested expired"
arch=$(find "$t/memory/archive" -name '*.md' | head -1)
assert_file_contains "nested entry reaches the archive" "$arch" "Nested expired"

# Re-running must not re-archive what is already in archive/.
lines_before=$(wc -l < "$arch")
bash "$PRUNE" --dir "$t/memory" --conf "$t/absent.conf" --apply >/dev/null 2>&1
lines_after=$(wc -l < "$arch")
[ "$lines_before" -eq "$lines_after" ] \
    && pass "archive/ is excluded from the scan" \
    || fail "archive/ is excluded from the scan" "archive grew from $lines_before to $lines_after lines"

# 12. index.md and todo.md stay skipped at any depth.
t=$(mk_tmp); mkdir -p "$t/memory/cart"
cat > "$t/memory/cart/index.md" <<'EOF'
# Cart Index
- **[skip]** nested index entry (2020-01-01) ttl:90d
EOF
bash "$PRUNE" --dir "$t/memory" --conf "$t/absent.conf" --apply >/dev/null 2>&1
assert_file_contains "nested index.md is skipped" "$t/memory/cart/index.md" "nested index entry"

# 13. Non-canonical paths must not turn the archive into a scan target. `find` normalizes its
# start argument, so an un-normalized --archive/--dir makes the -path exclusion miss and the
# archive rewrite wipes what earlier runs put there. Trailing slashes are what tab-completion
# produces, so this is the common invocation, not an exotic one.
seed_one() {
    printf '# Lessons\n\n- **[%s]** %s (2020-01-01) ttl:90d source:discovered conf:med\n' "$1" "$2" > "$3"
}
check_archive_survives() {
    local label="$1"; shift
    local d; d=$(mk_tmp); mkdir -p "$d/memory"
    seed_one first "First run entry" "$d/memory/lessons.md"
    ( cd "$d" && bash "$PRUNE" "$@" --conf absent.conf --apply ) >/dev/null 2>&1
    seed_one second "Second run entry" "$d/memory/lessons.md"
    ( cd "$d" && bash "$PRUNE" "$@" --conf absent.conf --apply ) >/dev/null 2>&1
    local arch; arch=$(find "$d/memory/archive" -name '*.md' 2>/dev/null | head -1)
    if [ -n "$arch" ] && grep -qF "First run entry" "$arch" && grep -qF "Second run entry" "$arch"; then
        pass "$label"
    else
        fail "$label" "archive lost an earlier entry"
    fi
}
check_archive_survives "trailing-slash --dir keeps the prior archive" --dir "memory/"
check_archive_survives "trailing-slash --archive keeps the prior archive" --dir "memory" --archive "memory/archive/"
check_archive_survives "relative --dir/--archive mix keeps the prior archive" --dir "./memory" --archive "memory/archive"

echo ""
echo "================================================"
TOTAL=$((PASS + FAIL))
printf "Results: %d/%d passed\n" "$PASS" "$TOTAL"
[ "$FAIL" -eq 0 ] && { echo "ALL PASSED"; exit 0; } || { echo "FAILED"; exit 1; }
