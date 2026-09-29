#!/usr/bin/env bash
# tests/check-install-smoke.sh — offline install smoke test.
#
# Simulates a real install WITHOUT network, a release tag, or a claude session: it derives the
# shared-file list from the SAME download table the real installer uses (.prompts/setup-prompt.md
# Step 2), copies each source from the working tree into a target dir, lays down the project-owned
# templates, then runs the installed gates. This both proves the installed layout works AND catches
# download-table drift (a new shared file that was never wired into the table fails here).
#
# Usage:
#   bash tests/check-install-smoke.sh [TARGET_DIR]
# With no TARGET_DIR a temp dir is used and removed on exit. Pass a path to keep the tree for
# inspection (e.g. bash tests/check-install-smoke.sh /tmp/ac-install).
#
# Exit: 0 = install layout valid and gates pass, 1 = a problem (missing source, gate failure).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROMPT="$REPO_ROOT/.prompts/setup-prompt.md"

PASS=0
FAIL=0
pass() { printf "  PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
fail() { printf "  FAIL  %s\n    => %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }

# Target: explicit arg (kept) or a temp dir (auto-removed).
KEEP=1
TARGET="${1:-}"
if [ -z "$TARGET" ]; then
    TARGET="$(mktemp -d "${TMPDIR:-/tmp}/ac-install.XXXXXX")"
    KEEP=0
fi
cleanup() { [ "$KEEP" -eq 0 ] && [ -d "$TARGET" ] && rm -rf "$TARGET"; }
trap cleanup EXIT
mkdir -p "$TARGET"

echo "=== install smoke test (offline) ==="
echo "  target: $TARGET"
echo ""

# 1. Project-owned scaffold: templates/ maps to the project root (.agent-context, .claude, AGENTS.md).
cp -R "$REPO_ROOT/templates/." "$TARGET/" 2>/dev/null \
    && pass "templates scaffold copied" || fail "templates scaffold copied" "cp failed"

# 2. Shared files: derive (source -> dest) from the setup-prompt Step 2 download table and copy
#    each source from the working tree. A missing source is a hard failure (table drift).
table_rows="$(awk '/^\| *Source path/{t=1;next} t&&/^\| *`/{n=split($0,a,"`"); if(a[2]&&a[4]) print a[2]"\t"a[4]} t&&!/^\|/{t=0}' "$PROMPT")"
row_count="$(printf '%s\n' "$table_rows" | grep -c . || true)"
[ "$row_count" -ge 1 ] && pass "parsed $row_count shared-file rows from download table" \
    || fail "parse download table" "no rows found in $PROMPT"

# 2a. Drift check: every tracked shared file (context/** plus the two review prompts) needs a
#     table row. Catches a row removed from the table while the file itself stays tracked.
table_sources="$(printf '%s\n' "$table_rows" | awk -F'\t' '{print $1}' | sort -u)"
expected_shared="$({ git -C "$REPO_ROOT" ls-files context/; printf '%s\n' ".prompts/decision-review-prompt.md" ".prompts/memory-review-prompt.md"; } | sort -u)"
missing_from_table="$(comm -23 <(printf '%s\n' "$expected_shared") <(printf '%s\n' "$table_sources"))"
[ -z "$missing_from_table" ] && pass "every tracked shared file is wired into the Step 2 table" \
    || fail "shared files wired into table" "missing from table: $(printf '%s' "$missing_from_table" | tr '\n' ' ')"
extra_in_table="$(comm -13 <(printf '%s\n' "$expected_shared") <(printf '%s\n' "$table_sources"))"
[ -z "$extra_in_table" ] && pass "no table row points outside the tracked shared-file set" \
    || fail "table rows match tracked shared-file set" "extra in table: $(printf '%s' "$extra_in_table" | tr '\n' ' ')"

# 2b. Drift check: the curl block must fetch exactly the sources listed in the table (the two
#     `for` loops expand their $_cmd / $_hook items). Catches a curl line removed or added
#     without a matching table row, in either direction.
curl_sources="$(awk '
    /^## Step 2: Install Shared Files/ { insec = 1 }
    /^## Step 3: Template Files/ { insec = 0 }
    insec && /^for [A-Za-z_][A-Za-z0-9_]* in / {
        line = $0
        sub(/^for /, "", line)
        p = index(line, " in ")
        var = substr(line, 1, p - 1)
        rest = substr(line, p + 4)
        sub(/;.*/, "", rest)
        forlist[var] = rest
        next
    }
    insec {
        idx = index($0, "Agent-Context/<tag>/")
        if (idx == 0) next
        rest = substr($0, idx + length("Agent-Context/<tag>/"))
        q = index(rest, "\"")
        if (q == 0) next
        path = substr(rest, 1, q - 1)
        d = index(path, "$")
        if (d == 0) { print path; next }
        prefix = substr(path, 1, d - 1)
        var = substr(path, d + 1)
        n = split(forlist[var], items, " ")
        for (i = 1; i <= n; i++) print prefix items[i]
    }
' "$PROMPT" | sort -u)"
missing_from_curl="$(comm -23 <(printf '%s\n' "$table_sources") <(printf '%s\n' "$curl_sources"))"
[ -z "$missing_from_curl" ] && pass "every table source is fetched by the curl block" \
    || fail "curl block fetches every table source" "missing from curl block: $(printf '%s' "$missing_from_curl" | tr '\n' ' ')"
extra_in_curl="$(comm -13 <(printf '%s\n' "$table_sources") <(printf '%s\n' "$curl_sources"))"
[ -z "$extra_in_curl" ] && pass "curl block fetches no source outside the table" \
    || fail "curl block matches table sources" "extra in curl block: $(printf '%s' "$extra_in_curl" | tr '\n' ' ')"

missing_src=0
copied=0
while IFS="$(printf '\t')" read -r src dst; do
    [ -n "$src" ] || continue
    if [ ! -f "$REPO_ROOT/$src" ]; then
        fail "source exists for $dst" "missing working-tree file: $src"
        missing_src=1
        continue
    fi
    mkdir -p "$TARGET/$(dirname "$dst")"
    cp "$REPO_ROOT/$src" "$TARGET/$dst" || { fail "copy $src" "cp failed"; missing_src=1; continue; }
    copied=$((copied + 1))
done <<EOF
$table_rows
EOF
[ "$missing_src" -eq 0 ] && pass "all $copied shared sources present and copied" \
    || fail "all shared sources present" "one or more download-table sources missing from the tree"

# 3. Make the installed scripts executable, as the real installer's chmod step does.
chmod +x "$TARGET"/.agent-context/bin/*.sh "$TARGET"/.agent-context/hooks/*.sh 2>/dev/null || true

# 4. Every destination from the table must now exist in the target.
missing_dst=0
while IFS="$(printf '\t')" read -r src dst; do
    [ -n "$dst" ] || continue
    [ -f "$TARGET/$dst" ] || { fail "installed file present" "$dst missing in target"; missing_dst=1; }
done <<EOF
$table_rows
EOF
[ "$missing_dst" -eq 0 ] && pass "every download-table destination is present in the target" \
    || fail "all destinations present" "see above"

# 5. Gates run in the installed tree (cwd = target so the conf's project-relative paths resolve).
if ( cd "$TARGET" && bash .agent-context/bin/check-token-budget.sh --quiet ); then
    pass "always-on token-budget gate passes in installed tree"
else
    fail "token-budget gate" "check-token-budget.sh exited non-zero in the installed tree"
fi

# 6. @-import closure: Claude Code resolves each `@path` relative to the importing file. Walk it from
#    the entry point and require (a) every import to exist, (b) every SESSION_START_FILES / INCLUDE_FILES
#    entry to exist, (c) the gate's counted set to equal the walked closure plus both lists, and (d) no
#    note on a correctly configured install.
TARGET_P="$(cd "$TARGET" && pwd -P)"
queue=".claude/CLAUDE.md"
loaded=""
dangling=""
while [ -n "$queue" ]; do
    rel="${queue%%$'\n'*}"
    [ "$queue" = "$rel" ] && queue="" || queue="${queue#*$'\n'}"
    case $'\n'"$loaded"$'\n' in *$'\n'"$rel"$'\n'*) continue ;; esac
    loaded="${loaded:+$loaded$'\n'}$rel"
    dir="$(dirname "$TARGET_P/$rel")"
    while IFS= read -r imp; do
        imp="${imp%$'\r'}"
        imp="${imp#@}"
        imp="${imp%"${imp##*[![:space:]]}"}"
        abs_dir="$(cd "$dir/$(dirname "$imp")" 2>/dev/null && pwd -P)" || abs_dir=""
        if [ -z "$abs_dir" ] || [ ! -f "$abs_dir/$(basename "$imp")" ]; then
            dangling="${dangling:+$dangling, }$rel -> @$imp"
            continue
        fi
        next_file="$abs_dir/$(basename "$imp")"
        queue="${queue:+$queue$'\n'}${next_file#"$TARGET_P"/}"
    done < <(grep -E '^@[^[:space:]]+[[:space:]]*$' "$TARGET_P/$rel")
done
[ -z "$dangling" ] && pass "every @-import resolves relative to its importing file" \
    || fail "@-import closure" "dangling: $dangling"
conf_list() { awk -v k="$1" '$0 ~ "^" k "=\"" {f=1;next} f&&/^"/{exit} f&&NF{print $1}' "$TARGET/.agent-context/budget.conf"; }
listed_files="$(printf '%s\n%s\n' "$(conf_list SESSION_START_FILES)" "$(conf_list INCLUDE_FILES)" | grep .)"
[ -n "$listed_files" ] && pass "budget.conf lists session-start reads" || fail "session-start reads" "SESSION_START_FILES and INCLUDE_FILES both empty"
missing_inc=""
while IFS= read -r inc; do
    [ -n "$inc" ] && [ ! -f "$TARGET/$inc" ] && missing_inc="$missing_inc $inc"
done <<EOF
$listed_files
EOF
[ -z "$missing_inc" ] && pass "every SESSION_START_FILES / INCLUDE_FILES entry exists" \
    || fail "listed entries exist" "missing:$missing_inc"
expected="$(printf '%s\n%s\n' "$loaded" "$listed_files" | grep . | sort -u)"
counted="$(cd "$TARGET" && bash .agent-context/bin/check-token-budget.sh --list 2>/dev/null | sort)"
if [ "$counted" = "$expected" ]; then
    pass "gate counts the walked @-closure plus SESSION_START_FILES and INCLUDE_FILES"
else
    fail "gate set vs closure + listed files" "counted: $(printf '%s\n' "$counted" | tr '\n' ' ') expected: $(printf '%s\n' "$expected" | tr '\n' ' ')"
fi
notes="$(cd "$TARGET" && bash .agent-context/bin/check-token-budget.sh --quiet 2>&1 >/dev/null | grep -c 'note:')"
[ "$notes" = "0" ] && pass "installed gate prints no note" || fail "installed gate prints no note" "$notes note line(s)"

# Map gate with no map yet must exit 2 (no map.json) — proves the validator installed and runs.
mc=0
( cd "$TARGET" && bash .agent-context/bin/check-map-budget.sh --quiet >/dev/null 2>&1 ) || mc=$?
[ "$mc" -eq 2 ] && pass "map-budget gate present and reports no-map (exit 2)" \
    || fail "map-budget gate" "expected exit 2 (no map.json), got $mc"

echo ""
echo "================================================"
TOTAL=$((PASS + FAIL))
printf "Results: %d/%d passed\n" "$PASS" "$TOTAL"
[ "$KEEP" -eq 1 ] && echo "(target kept at $TARGET)"
[ "$FAIL" -eq 0 ] && { echo "ALL PASSED"; exit 0; } || { echo "FAILED"; exit 1; }
