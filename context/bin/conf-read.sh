#!/usr/bin/env bash
# Whitelisted, non-evaluating reader for the project-owned .conf files
# (.agent-context/budget.conf, .agent-context/hooks.conf).
#
# Sourced, never executed:
#   . "$(cd "$(dirname "$0")" && pwd)/conf-read.sh"
#   conf_get_into MAX_EFFECTIVE_LINES "$CONF" MAX_EFFECTIVE_LINES || true
#
# A conf is project-owned content that can arrive via `git pull` from a repository the
# developer does not control. `. "$CONF"` runs every command in it as the developer, so
# nothing here evaluates: a value is copied out literally. No command substitution, no
# parameter expansion, no conditionals — a conf carries data, not code. The caller names
# each key it wants, so the set of readable keys is the caller's whitelist; every other
# line in the file is ignored.
#
# Grammar, per key (the LAST assignment wins, matching shell override order):
#   KEY=bare          value ends at the first whitespace; `KEY=1 # note` yields `1`
#   KEY="value"       may span lines until the closing double quote
#   KEY='value'       may span lines until the closing single quote
# A leading `export ` and leading whitespace are tolerated. No whitespace is allowed
# around `=`, because the shell does not allow it either.
#
# Return: 0 and the value on stdout when the key is set (an empty value is still 0);
#         1 when the key is absent, the file is missing, or a quote is never closed.

# conf_get <file> <key>
conf_get() {
    [ -f "$1" ] || return 1
    awk -v key="$2" '
        function finish(v) { result = v; found = 1 }
        {
            if (inrange) {
                p = index($0, q)
                if (p > 0) { finish(val substr($0, 1, p - 1)); inrange = 0 }
                else { val = val $0 "\n" }
                next
            }
            s = $0
            sub(/^[ \t]+/, "", s)
            sub(/^export[ \t]+/, "", s)
            if (substr(s, 1, length(key) + 1) != key "=") next
            rest = substr(s, length(key) + 2)
            first = substr(rest, 1, 1)
            if (first == "\"" || first == "'"'"'") {
                q = first
                body = substr(rest, 2)
                p = index(body, q)
                if (p > 0) { finish(substr(body, 1, p - 1)) }
                else { inrange = 1; val = body "\n" }
                next
            }
            # Bare value: the shell would end it at the first unquoted whitespace too,
            # which is also what strips a trailing `# comment`.
            sub(/[ \t].*$/, "", rest)
            finish(rest)
        }
        END { if (found) printf "%s", result; exit (found ? 0 : 1) }
    ' "$1"
}

# conf_get_into <varname> <file> <key>
# Assigns only when the key is present, so the caller keeps its built-in default otherwise.
# `printf -v` writes the variable by name without evaluating the value.
conf_get_into() {
    local _cri_var="$1" _cri_val
    _cri_val=$(conf_get "$2" "$3") || return 1
    printf -v "$_cri_var" '%s' "$_cri_val"
}
