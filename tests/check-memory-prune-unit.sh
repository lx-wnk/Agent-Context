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

# 14. Symlinks: the pre-recursive scan followed them via the `for f in */*.md` glob, so a project
# whose memory dir is a symlink, or that shares a single lessons.md, must keep working.
t=$(mk_tmp); mkdir -p "$t/real"
seed_one linked "Behind a symlinked dir" "$t/real/lessons.md"
ln -s "$t/real" "$t/memory"
bash "$PRUNE" --dir "$t/memory" --conf "$t/absent.conf" --apply >/dev/null 2>&1
assert_file_not_contains "symlinked memory dir is scanned" "$t/real/lessons.md" "Behind a symlinked dir"

# A symlink that resolves back INTO the memory tree is still rewritten at its target — mv over
# the link would swap a deliberately shared file for a private copy. Targets outside the tree
# are a different case, covered by test 24.
t=$(mk_tmp); mkdir -p "$t/memory/shared"
seed_one shared "Shared lesson entry" "$t/memory/shared/lessons.md"
ln -s "$t/memory/shared/lessons.md" "$t/memory/lessons.md"
bash "$PRUNE" --dir "$t/memory" --conf "$t/absent.conf" --apply >/dev/null 2>&1
assert_file_not_contains "in-tree symlink is pruned at its target" "$t/memory/shared/lessons.md" "Shared lesson entry"
[ -L "$t/memory/lessons.md" ] \
    && pass "rewrite keeps the symlink, replacing the target" \
    || fail "rewrite keeps the symlink, replacing the target" "link was replaced by a regular file"

# 15. An unreadable file must not abort the scan — `done < "$file"` under set -e exits 1, which
# is outside the declared 0/2 contract, and every later file is silently skipped.
if [ "$(id -u)" -eq 0 ]; then
    pass "unreadable file skipped, scan continues (skipped: running as root)"
    pass "unreadable file keeps the exit code at 0 (skipped: running as root)"
else
    t=$(mk_tmp); mkdir -p "$t/memory"
    seed_one a "Alpha expired" "$t/memory/aaa.md"
    seed_one b "Bravo expired" "$t/memory/bbb.md"
    seed_one c "Charlie expired" "$t/memory/ccc.md"
    chmod 000 "$t/memory/bbb.md"
    bash "$PRUNE" --dir "$t/memory" --conf "$t/absent.conf" --apply >/dev/null 2>&1
    rc=$?
    assert_file_not_contains "unreadable file skipped, scan continues" "$t/memory/ccc.md" "Charlie expired"
    [ "$rc" -eq 0 ] && pass "unreadable file keeps the exit code at 0" || fail "unreadable file keeps the exit code at 0" "got exit $rc"
    chmod 644 "$t/memory/bbb.md"
fi

# 16. A rewrite that cannot happen after the archive append leaves a duplicate. That must be a
# loud exit 2, not a set -e death at exit 1 (mktemp path) and not a silent exit 0 (cp/mv path).
if [ "$(id -u)" -eq 0 ]; then
    pass "failed rewrite exits 2 (skipped: running as root)"
    pass "failed rewrite names both copies (skipped: running as root)"
else
    t=$(mk_tmp); mkdir -p "$t/memory"
    seed_one ro "Read-only dir entry" "$t/memory/lessons.md"
    chmod 555 "$t/memory"
    err=$(bash "$PRUNE" --dir "$t/memory" --archive "$t/archive" --conf "$t/absent.conf" --apply 2>&1 >/dev/null)
    rc=$?
    chmod 755 "$t/memory"
    [ "$rc" -eq 2 ] && pass "failed rewrite exits 2" || fail "failed rewrite exits 2" "got exit $rc"
    printf '%s' "$err" | grep -qF "BOTH in" \
        && pass "failed rewrite names both copies" \
        || fail "failed rewrite names both copies" "stderr was: $err"
fi

# 17. Only MEMORY_TTL_DEFAULTS is read out of the conf; every other key in it is ignored, so no
# conf key reaches APPLY, MEM_DIR/ARCHIVE_DIR or the shared table. Test 23 covers the other half
# of the same property — that the file is parsed rather than executed. APPLY is asserted on its
# own, so the result cannot pass merely because another key emptied the scan: the default
# dry-run has to survive a conf that asks for a rewrite.
t=$(mk_tmp); seed_defaults "$t/memory"
printf 'APPLY=1\n' > "$t/apply.conf"
bash "$PRUNE" --dir "$t/memory" --conf "$t/apply.conf" >/dev/null 2>&1
assert_file_contains "conf APPLY=1 does not turn dry-run into a rewrite" "$t/memory/lessons.md" "Dated but no ttl"
[ -d "$t/memory/archive" ] && fail "conf APPLY=1 creates no archive" "archive/ exists" || pass "conf APPLY=1 creates no archive"

t=$(mk_tmp); seed_defaults "$t/memory"
cat > "$t/hostile.conf" <<EOF
MEM_DIR="$t/elsewhere"
ARCHIVE_DIR="$t/elsewhere"
SHARED_TTL_DEFAULTS=""
EOF
out=$(bash "$PRUNE" --dir "$t/memory" --conf "$t/hostile.conf" 2>&1)
printf '%s' "$out" | grep -qF "EXPIRED (default 90d)" \
    && pass "conf cannot blank the shared TTL table" \
    || fail "conf cannot blank the shared TTL table" "shared default stopped applying"
# Compared against the conf's target, not against $t/memory — the scan header prints the
# canonicalized path, and on macOS /var is itself a symlink to /private/var.
printf '%s' "$out" | grep -qF "elsewhere" \
    && fail "conf cannot redirect the scanned directory" "scan followed the conf: $out" \
    || pass "conf cannot redirect the scanned directory"

# 18. The `*` catch-all the budget.conf template advertises. Both lines shipped untested.
t=$(mk_tmp); seed_defaults "$t/memory"
printf 'MEMORY_TTL_DEFAULTS="*=90d"\n' > "$t/star.conf"
bash "$PRUNE" --dir "$t/memory" --conf "$t/star.conf" --apply >/dev/null 2>&1
assert_file_not_contains "conf '*' applies to a file in neither table" "$t/memory/glossary.md" "Unclassified file"

t=$(mk_tmp); seed_defaults "$t/memory"
printf 'MEMORY_TTL_DEFAULTS="\n*=90d\nglossary.md=infinite\n"\n' > "$t/star2.conf"
bash "$PRUNE" --dir "$t/memory" --conf "$t/star2.conf" --apply >/dev/null 2>&1
assert_file_contains "exact basename beats the conf '*'" "$t/memory/glossary.md" "Unclassified file"

# 19. The dry-run preview is the safety net before --apply, so it must show the whole line. A
# memory line containing a tab was truncated at the first one while the full line still moved.
t=$(mk_tmp); mkdir -p "$t/memory"
printf '# Lessons\n\n- **[tabbed]** Before\tAFTER_THE_TAB (2020-01-01) ttl:90d source:user conf:med\n' > "$t/memory/lessons.md"
out=$(bash "$PRUNE" --dir "$t/memory" --conf "$t/absent.conf" 2>&1)
printf '%s' "$out" | grep -qF "AFTER_THE_TAB" \
    && pass "preview shows the full line past an embedded tab" \
    || fail "preview shows the full line past an embedded tab" "preview truncated: $out"

# 20. A bare `*` is a config error, and the message must name what the user wrote — unguarded
# word splitting expanded it against the cwd and blamed an unrelated file.
t=$(mk_tmp); seed_defaults "$t/memory"
printf 'MEMORY_TTL_DEFAULTS="*"\n' > "$t/glob.conf"
err=$(cd "$t/memory" && bash "$PRUNE" --dir "$t/memory" --conf "$t/glob.conf" --apply 2>&1 >/dev/null)
rc=$?
[ "$rc" -eq 2 ] && pass "bare '*' in the conf exits 2" || fail "bare '*' in the conf exits 2" "got exit $rc"
printf '%s' "$err" | grep -qF "entry '*' is not key=value" \
    && pass "config error names the literal token, not a globbed filename" \
    || fail "config error names the literal token, not a globbed filename" "stderr was: $err"

# 21. normalize_dir canonicalizes via `cd … && pwd -P` inside a command substitution, whose
# failure printf swallows: an unsearchable --dir silently became the empty string (header
# "Memory decay scan — ", zero files scanned, exit 0), and an --archive whose parent cannot be
# searched silently relocated the archive to the filesystem root ("/arch/<week>.md").
if [ "$(id -u)" -eq 0 ]; then
    pass "unsearchable --dir exits 2 (skipped: running as root)"
    pass "unsearchable --dir names the directory (skipped: running as root)"
    pass "unsearchable --archive parent exits 2 (skipped: running as root)"
    pass "unsearchable --archive parent names the directory (skipped: running as root)"
else
    t=$(mk_tmp); mkdir -p "$t/memory"
    seed_one nodir "Unsearchable dir entry" "$t/memory/lessons.md"
    chmod 000 "$t/memory"
    err=$(bash "$PRUNE" --dir "$t/memory" --conf "$t/absent.conf" --apply 2>&1 >/dev/null)
    rc=$?
    chmod 755 "$t/memory"
    [ "$rc" -eq 2 ] && pass "unsearchable --dir exits 2" || fail "unsearchable --dir exits 2" "got exit $rc"
    if printf '%s' "$err" | grep -qF "Error:" && printf '%s' "$err" | grep -qF "$t/memory"; then
        pass "unsearchable --dir names the directory"
    else
        fail "unsearchable --dir names the directory" "stderr was: $err"
    fi

    t=$(mk_tmp); mkdir -p "$t/memory" "$t/locked"
    seed_one noarch "Unsearchable archive parent" "$t/memory/lessons.md"
    chmod 000 "$t/locked"
    err=$(bash "$PRUNE" --dir "$t/memory" --archive "$t/locked/arch" --conf "$t/absent.conf" --apply 2>&1 >/dev/null)
    rc=$?
    chmod 755 "$t/locked"
    [ "$rc" -eq 2 ] && pass "unsearchable --archive parent exits 2" || fail "unsearchable --archive parent exits 2" "got exit $rc"
    if printf '%s' "$err" | grep -qF "Error:" && printf '%s' "$err" | grep -qF "$t/locked"; then
        pass "unsearchable --archive parent names the directory"
    else
        fail "unsearchable --archive parent names the directory" "stderr was: $err"
    fi
fi

# 22. The archive-write path is the other half of the 0/2 contract. mkdir -p, the append to the
# archive file, and the two mktemp calls were unguarded under set -e, so an unwritable archive
# dir or TMPDIR killed the run at exit 1 with a raw "Permission denied". The source file is
# untouched in all three cases, and the message has to say so.
if [ "$(id -u)" -eq 0 ]; then
    pass "unwritable archive dir exits 2 (skipped: running as root)"
    pass "unwritable archive dir names the archive file (skipped: running as root)"
    pass "unwritable archive dir leaves the source intact (skipped: running as root)"
    pass "uncreatable archive dir exits 2 (skipped: running as root)"
    pass "uncreatable archive dir names the directory (skipped: running as root)"
    pass "unwritable TMPDIR exits 2 (skipped: running as root)"
    pass "unwritable TMPDIR names the temp directory (skipped: running as root)"
    pass "unwritable TMPDIR leaves the source intact (skipped: running as root)"
else
    t=$(mk_tmp); mkdir -p "$t/memory" "$t/arch"
    seed_one aw "Archive append entry" "$t/memory/lessons.md"
    chmod 555 "$t/arch"
    err=$(bash "$PRUNE" --dir "$t/memory" --archive "$t/arch" --conf "$t/absent.conf" --apply 2>&1 >/dev/null)
    rc=$?
    chmod 755 "$t/arch"
    [ "$rc" -eq 2 ] && pass "unwritable archive dir exits 2" || fail "unwritable archive dir exits 2" "got exit $rc"
    # Matched on the trailing path segment: normalize_dir canonicalizes, and on macOS /var is
    # itself a symlink to /private/var, so the absolute prefix in $t will not match verbatim.
    if printf '%s' "$err" | grep -qF "Error:" && printf '%s' "$err" | grep -qE '/arch/[0-9]{4}-W[0-9]{2}\.md'; then
        pass "unwritable archive dir names the archive file"
    else
        fail "unwritable archive dir names the archive file" "stderr was: $err"
    fi
    assert_file_contains "unwritable archive dir leaves the source intact" "$t/memory/lessons.md" "Archive append entry"

    t=$(mk_tmp); mkdir -p "$t/memory" "$t/parent"
    seed_one mk "Archive mkdir entry" "$t/memory/lessons.md"
    chmod 555 "$t/parent"
    err=$(bash "$PRUNE" --dir "$t/memory" --archive "$t/parent/arch" --conf "$t/absent.conf" --apply 2>&1 >/dev/null)
    rc=$?
    chmod 755 "$t/parent"
    [ "$rc" -eq 2 ] && pass "uncreatable archive dir exits 2" || fail "uncreatable archive dir exits 2" "got exit $rc"
    if printf '%s' "$err" | grep -qF "Error:" && printf '%s' "$err" | grep -qF "/parent/arch"; then
        pass "uncreatable archive dir names the directory"
    else
        fail "uncreatable archive dir names the directory" "stderr was: $err"
    fi

    t=$(mk_tmp); mkdir -p "$t/memory" "$t/notmp"
    seed_one tm "Tmpdir entry" "$t/memory/lessons.md"
    chmod 555 "$t/notmp"
    err=$(TMPDIR="$t/notmp" bash "$PRUNE" --dir "$t/memory" --conf "$t/absent.conf" --apply 2>&1 >/dev/null)
    rc=$?
    chmod 755 "$t/notmp"
    [ "$rc" -eq 2 ] && pass "unwritable TMPDIR exits 2" || fail "unwritable TMPDIR exits 2" "got exit $rc"
    if printf '%s' "$err" | grep -qF "Error:" && printf '%s' "$err" | grep -qF "$t/notmp"; then
        pass "unwritable TMPDIR names the temp directory"
    else
        fail "unwritable TMPDIR names the temp directory" "stderr was: $err"
    fi
    assert_file_contains "unwritable TMPDIR leaves the source intact" "$t/memory/lessons.md" "Tmpdir entry"
fi

# 23. The conf is DATA, not a script. It is parsed for MEMORY_TTL_DEFAULTS and never executed,
# so a budget.conf arriving via `git pull` from an untrusted repository cannot run a command —
# not even in the default dry-run the CHANGELOG recommends as the safe first step.
t=$(mk_tmp); seed_defaults "$t/memory"
canary="$t/PAYLOAD_RAN"
printf 'MEMORY_TTL_DEFAULTS="lessons.md=90d"\ntouch %s\n' "$canary" > "$t/payload.conf"
bash "$PRUNE" --dir "$t/memory" --conf "$t/payload.conf" >/dev/null 2>&1
[ -e "$canary" ] && fail "conf payload is never executed (dry-run)" "the conf command ran" \
    || pass "conf payload is never executed (dry-run)"
bash "$PRUNE" --dir "$t/memory" --conf "$t/payload.conf" --apply >/dev/null 2>&1
[ -e "$canary" ] && fail "conf payload is never executed (--apply)" "the conf command ran" \
    || pass "conf payload is never executed (--apply)"
assert_file_not_contains "the parsed key still applies while the payload is ignored" "$t/memory/lessons.md" "Dated but no ttl"

# A command substitution inside a value is literal text, so it reaches the validator unevaluated
# and is rejected there like any other malformed value.
t=$(mk_tmp); seed_defaults "$t/memory"
printf 'MEMORY_TTL_DEFAULTS="lessons.md=$(touch %s/SUBST_RAN)d"\n' "$t" > "$t/subst.conf"
bash "$PRUNE" --dir "$t/memory" --conf "$t/subst.conf" --apply >/dev/null 2>&1
rc=$?
[ ! -e "$t/SUBST_RAN" ] && [ "$rc" -eq 2 ] \
    && pass "command substitution in a conf value stays literal and exits 2" \
    || fail "command substitution in a conf value stays literal and exits 2" "canary=$([ -e "$t/SUBST_RAN" ] && echo ran || echo absent) rc=$rc"

# 24. A memory file that RESOLVES outside the memory directory is a link-following escape: a
# repository shipping only `memory/lessons.md -> ~/private-notes.md` otherwise reaches any file
# the developer can write, and the archive lives in the repo, so the next push exfiltrates it.
t=$(mk_tmp); mkdir -p "$t/memory" "$t/outside"
seed_one victim "Out-of-tree entry" "$t/outside/lessons.md"
ln -s "$t/outside/lessons.md" "$t/memory/lessons.md"
out=$(bash "$PRUNE" --dir "$t/memory" --conf "$t/absent.conf" 2>/dev/null)
printf '%s' "$out" | grep -qF "Out-of-tree entry" \
    && fail "dry-run does not disclose out-of-tree content" "the preview printed the target's line" \
    || pass "dry-run does not disclose out-of-tree content"
err=$(bash "$PRUNE" --dir "$t/memory" --conf "$t/absent.conf" --apply 2>&1 >/dev/null)
rc=$?
assert_file_contains "out-of-tree symlink target is not rewritten" "$t/outside/lessons.md" "Out-of-tree entry"
printf '%s' "$err" | grep -qF "outside the memory directory" \
    && pass "out-of-tree symlink target is reported" \
    || fail "out-of-tree symlink target is reported" "stderr was: $err"
[ "$rc" -eq 0 ] && pass "out-of-tree symlink keeps the exit code at 0" \
    || fail "out-of-tree symlink keeps the exit code at 0" "got exit $rc"

# 25. `find` emits newline-separated paths, so a directory name containing a newline splits into
# a second, independent path — here a relative one, resolved against the CWD, fully outside the
# memory tree. NUL delimiting makes the separator unforgeable and keeps the real file scannable.
t=$(mk_tmp); mkdir -p "$t/victimdir"
inject_dir="$t/memory/$(printf 'x\nvictimdir')"
mkdir -p "$inject_dir"
seed_one inj "Inside the newline directory" "$inject_dir/lessons.md"
seed_one esc "Injected path entry" "$t/victimdir/lessons.md"
( cd "$t" && bash "$PRUNE" --dir "$t/memory" --conf "$t/absent.conf" --apply ) >/dev/null 2>&1
assert_file_contains "a newline in a directory name injects no second path" "$t/victimdir/lessons.md" "Injected path entry"
assert_file_not_contains "the real file inside the newline directory is still scanned" "$inject_dir/lessons.md" "Inside the newline directory"

# 26. A leading-zero TTL was read as octal. `ttl:09d` raised a fatal arithmetic error that killed
# the read loop while the run still exited 0, so every later entry in the same file was silently
# never archived. Only a leading zero with an 8 or 9 reproduces it — 007d and 030d are valid octal.
t=$(mk_tmp); mkdir -p "$t/memory"
cat > "$t/memory/lessons.md" <<'EOF'
# Lessons Learned

- **[octal]** Leading zero ttl (2020-01-01) ttl:09d source:user conf:med
- **[after]** Expired after the poison line (2020-01-01) ttl:90d source:user conf:med
EOF
err=$(bash "$PRUNE" --dir "$t/memory" --conf "$t/absent.conf" --apply 2>&1 >/dev/null)
rc=$?
[ "$rc" -eq 0 ] && pass "leading-zero ttl keeps the exit code at 0" \
    || fail "leading-zero ttl keeps the exit code at 0" "got exit $rc"
printf '%s' "$err" | grep -qF "value too great" \
    && fail "leading-zero ttl raises no arithmetic error" "stderr was: $err" \
    || pass "leading-zero ttl raises no arithmetic error"
assert_file_not_contains "ttl:09d is read as 9 days, not as octal" "$t/memory/lessons.md" "Leading zero ttl"
assert_file_not_contains "an entry after the leading-zero line is still archived" "$t/memory/lessons.md" "Expired after the poison line"

# The conf side fed the same octal to the arithmetic because the validator admitted it as
# well-formed. It is rejected before any file is touched now.
t=$(mk_tmp); seed_defaults "$t/memory"
before=$(cat "$t/memory/glossary.md")
printf 'MEMORY_TTL_DEFAULTS="glossary.md=09d"\n' > "$t/octal.conf"
bash "$PRUNE" --dir "$t/memory" --conf "$t/octal.conf" --apply >/dev/null 2>&1
rc=$?
[ "$rc" -eq 2 ] && pass "conf value '09d' exits 2" || fail "conf value '09d' exits 2" "got exit $rc"
[ "$(cat "$t/memory/glossary.md")" = "$before" ] \
    && pass "rejected conf value leaves files untouched" \
    || fail "rejected conf value leaves files untouched" "file changed"

echo ""
echo "================================================"
TOTAL=$((PASS + FAIL))
printf "Results: %d/%d passed\n" "$PASS" "$TOTAL"
[ "$FAIL" -eq 0 ] && { echo "ALL PASSED"; exit 0; } || { echo "FAILED"; exit 1; }
