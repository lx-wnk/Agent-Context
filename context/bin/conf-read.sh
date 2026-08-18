#!/usr/bin/env bash
# Whitelisted, non-evaluating reader for the project-owned .conf files
# (.agent-context/budget.conf, .agent-context/hooks.conf).
#
# Sourced, never executed:
#   . "$(cd "$(dirname "$0")" && pwd)/conf-read.sh"
#   conf_load "$CONF" MAX_EFFECTIVE_LINES INCLUDE_FILES
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
# A key is "set" when it is present and its quoting is closed; a key that is absent, or
# whose quote never closes, counts as unset and leaves the caller's default in place.

# _conf_scan <file> <key>...
# Parses <file> in a single awk pass for every named key. For each key that is set, the
# literal value lands in the holding variable _conf_v_<key> and <key> is appended to
# _conf_found. Both are the outputs of this function and are deliberately global.
#
# The awk program keeps its scanning state per key, so the keys are read exactly as
# independent single-key passes would read them: an unclosed quote swallows the rest of the
# file for its own key only, and never hides a later key from the others.
#
# Values cross back line-tagged (`K<TAB>key`, then one `V<TAB>chunk` per line of the value)
# rather than as `key=value`, because a value may legally contain whitespace, `=`, quotes and
# newlines. Splitting on newline and re-joining on newline is exactly inverse, so the value
# round-trips byte-for-byte, and the shell reads the stream as data — it is never evaluated.
_conf_scan() {
    local _conf_file="$1"
    shift
    _conf_found=""
    [ -f "$_conf_file" ] || return 0
    [ "$#" -gt 0 ] || return 0

    local _conf_line _conf_key="" _conf_val="" _conf_first=1
    while IFS= read -r _conf_line; do
        case "$_conf_line" in
            "K"$'\t'*)
                if [ -n "$_conf_key" ]; then
                    printf -v "_conf_v_$_conf_key" '%s' "$_conf_val"
                    _conf_found="$_conf_found $_conf_key"
                fi
                _conf_key="${_conf_line#K$'\t'}"
                _conf_val=""
                _conf_first=1
                ;;
            "V"$'\t'*)
                if [ "$_conf_first" -eq 1 ]; then
                    _conf_val="${_conf_line#V$'\t'}"
                    _conf_first=0
                else
                    _conf_val="$_conf_val
${_conf_line#V$'\t'}"
                fi
                ;;
        esac
    done < <(awk -v keys="$*" '
        BEGIN { nk = split(keys, K, " ") }
        {
            s = $0
            sub(/^[ \t]+/, "", s)
            sub(/^export[ \t]+/, "", s)
            for (i = 1; i <= nk; i++) {
                k = K[i]
                if (inrange[k]) {
                    p = index($0, q[k])
                    if (p > 0) { result[k] = val[k] substr($0, 1, p - 1); found[k] = 1; inrange[k] = 0 }
                    else { val[k] = val[k] $0 "\n" }
                    continue
                }
                if (substr(s, 1, length(k) + 1) != k "=") continue
                rest = substr(s, length(k) + 2)
                first = substr(rest, 1, 1)
                if (first == "\"" || first == "'"'"'") {
                    q[k] = first
                    body = substr(rest, 2)
                    p = index(body, q[k])
                    if (p > 0) { result[k] = substr(body, 1, p - 1); found[k] = 1 }
                    else { inrange[k] = 1; val[k] = body "\n" }
                    continue
                }
                # Bare value: the shell would end it at the first unquoted whitespace too,
                # which is also what strips a trailing `# comment`.
                sub(/[ \t].*$/, "", rest)
                result[k] = rest
                found[k] = 1
            }
        }
        END {
            for (i = 1; i <= nk; i++) {
                k = K[i]
                if (!found[k]) continue
                printf "K\t%s\n", k
                n = split(result[k], L, "\n")
                for (j = 1; j <= n; j++) printf "V\t%s\n", L[j]
            }
        }
    ' "$_conf_file")

    if [ -n "$_conf_key" ]; then
        printf -v "_conf_v_$_conf_key" '%s' "$_conf_val"
        _conf_found="$_conf_found $_conf_key"
    fi
    return 0
}

# _conf_chomp <value> — result in _conf_chomped.
# The assigning entry points used to route the value through `$(conf_get …)`, and command
# substitution drops every trailing newline. A conf may legally end a quoted value on its own
# line, so keep stripping them here or `KEY="v<newline>"` starts arriving one byte longer.
_conf_chomp() {
    _conf_chomped="$1"
    while [ "${_conf_chomped%$'\n'}" != "$_conf_chomped" ]; do
        _conf_chomped="${_conf_chomped%$'\n'}"
    done
}

# conf_load <file> <key>...
# Assigns every key that is set to the shell variable of the same name, in one pass over the
# file. A key that is not set is left untouched, so the caller keeps its built-in default.
# Always returns 0: "the file does not mention this key" is the normal case, not an error.
conf_load() {
    local _conf_f="$1"
    shift
    _conf_scan "$_conf_f" "$@"
    local _conf_k _conf_ref
    for _conf_k in $_conf_found; do
        _conf_ref="_conf_v_$_conf_k"
        # Indirect expansion, not eval — the value is copied, never interpreted.
        _conf_chomp "${!_conf_ref}"
        printf -v "$_conf_k" '%s' "$_conf_chomped"
    done
    return 0
}

# conf_get <file> <key>
# Return: 0 and the value on stdout when the key is set (an empty value is still 0);
#         1 when the key is absent, the file is missing, or a quote is never closed.
conf_get() {
    local _conf_ref="_conf_v_$2"
    _conf_scan "$1" "$2"
    [ -n "$_conf_found" ] || return 1
    printf '%s' "${!_conf_ref}"
}

# conf_get_into <varname> <file> <key>
# Assigns only when the key is set, so the caller keeps its built-in default otherwise.
# `printf -v` writes the variable by name without evaluating the value.
conf_get_into() {
    local _conf_ref="_conf_v_$3"
    _conf_scan "$2" "$3"
    [ -n "$_conf_found" ] || return 1
    _conf_chomp "${!_conf_ref}"
    printf -v "$1" '%s' "$_conf_chomped"
}
