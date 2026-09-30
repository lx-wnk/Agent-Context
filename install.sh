#!/usr/bin/env bash
# zsh sets $0 to the sourced file, which defeats the BASH_SOURCE guard at the bottom of this file.
if [ -z "${BASH_VERSION:-}" ]; then
    echo "Error: install.sh requires bash — run it with: bash install.sh" >&2
    # shellcheck disable=SC2317  # exit is reached when executed rather than sourced
    return 1 2>/dev/null || exit 1
fi
set -euo pipefail

FORCE=0

# Returns 0 if the file contains only the @AGENTS.md (or @../AGENTS.md) bootstrap pointer.
# Uses awk for line count to correctly handle files without a trailing newline.
is_bootstrap_only() {
    local file="$1"
    [ -f "$file" ] || return 1
    grep -qE '@(\.\./)?AGENTS\.md' "$file" && \
        [ "$(awk 'END{print NR}' "$file")" -le 5 ] && \
        [ "$(grep -cve '^[[:space:]]*$' "$file")" -eq \
          "$(grep -cxE '[[:space:]]*@(\.\./)?AGENTS\.md[[:space:]]*' "$file")" ]
}

# Claude Code resolves @imports relative to the importing file, so .claude/CLAUDE.md must step up.
bootstrap_pointer() {
    case "$1" in
        .claude/*) echo "@../AGENTS.md" ;;
        *) echo "@AGENTS.md" ;;
    esac
}

# Replaces a whole line equal to $2 (a trailing CR is kept) with $3; symlinks are never written through.
rewrite_exact_line() {
    local file="$1" old="$2" new="$3" tmp
    [ -f "$file" ] && [ ! -L "$file" ] || return 0
    grep -qxE "$(printf '%s' "$old" | sed 's/[.[\*^$/]/\\&/g')"$'\r'"?" "$file" || return 0
    tmp=$(mktemp "$file.XXXXXX") || return 1
    awk -v o="$old" -v n="$new" '{ if ($0 == o) print n; else if ($0 == o "\r") print n "\r"; else print }' \
        "$file" > "$tmp" && cat "$tmp" > "$file"
    rm -f "$tmp"
    echo "Migrated $file: $old → $new"
}

# Inside .agent-context/, `@.agent-context/<path>` always resolves to .agent-context/.agent-context/<path>,
# so every such import becomes `@<path>` wherever it sits in a line. An `@` only counts as an import at
# line start or after whitespace, `(` or `>`; code spans and fenced blocks are left alone.
strip_nested_imports() {
    local file="$1" tmp
    [ -f "$file" ] && [ ! -L "$file" ] || return 0
    grep -q '@\.agent-context/' "$file" || return 0
    tmp=$(mktemp "$file.XXXXXX") || return 1
    awk '
        function fix(s,    out, i, prev) {
            out = ""
            while ((i = index(s, "@.agent-context/")) > 0) {
                prev = i > 1 ? substr(s, i - 1, 1) : (out == "" ? "" : substr(out, length(out), 1))
                if (prev == "" || prev ~ /[ \t(>]/) out = out substr(s, 1, i)
                else out = out substr(s, 1, i + 15)
                s = substr(s, i + 16)
            }
            return out s
        }
        /^[ \t]*```/ { fence = !fence; print; next }
        fence { print; next }
        {
            n = split($0, part, "`")
            line = ""
            for (j = 1; j <= n; j++) line = line (j > 1 ? "`" : "") (j % 2 ? fix(part[j]) : part[j])
            print line
        }
    ' "$file" > "$tmp"
    if cmp -s "$tmp" "$file"; then
        rm -f "$tmp"
        return 0
    fi
    cat "$tmp" > "$file"
    rm -f "$tmp"
    echo "Migrated $file: nested @.agent-context/ imports → importer-relative"
}

# Rewrites the root-relative imports that installs before 0.9.1 shipped; code spans stay untouched.
migrate_import_paths() {
    rewrite_exact_line ".claude/CLAUDE.md" "@AGENTS.md" "@../AGENTS.md"
    strip_nested_imports ".agent-context/layer2-project-core.md"
    strip_nested_imports ".agent-context/layer3-guidebook.md"
}

# The per-developer hook settings must never be committed; installs that predate them lack the line.
ensure_hooks_local_conf_ignored() {
    [ -d .agent-context ] || return 0
    [ -f .gitignore ] && grep -qxF '/.agent-context/hooks.local.conf' .gitignore && return 0
    if [ -s .gitignore ] && [ "$(tail -c 1 .gitignore | wc -l)" -eq 0 ]; then
        printf '\n' >> .gitignore
    fi
    printf '/.agent-context/hooks.local.conf\n' >> .gitignore
    echo "Added /.agent-context/hooks.local.conf to .gitignore"
}

# Since 0.10 these keys only take effect from hooks.local.conf; hooks configured the old way are now off.
warn_committed_hook_keys() {
    local conf=".agent-context/hooks.conf"
    [ -f "$conf" ] && [ ! -f .agent-context/hooks.local.conf ] || return 0
    grep -qE '^[[:space:]]*(export[[:space:]]+)?(HOOKS_ENABLED=["'"'"']?1|(TEST_CMD|FORMAT_CMD)=["'"'"']?[^"'"'"'[:space:]])' "$conf" || return 0
    echo "Note: $conf sets HOOKS_ENABLED, TEST_CMD or FORMAT_CMD — these now only take effect from"
    echo "      .agent-context/hooks.local.conf (gitignored, per developer). The format, test-gate and scope hooks stay off until you move them there."
}

# Returns 0 if all critical project-owned template files are present.
# Adding a new template to templates/ requires a matching entry here.
# tests/check-template-coverage.sh auto-reads this list — no changes needed there.
missing_critical_templates() {
    for _tmpl in "AGENTS.md" \
                 ".agent-context/layer1-bootstrap.md" \
                 ".agent-context/layer2-project-core.md" \
                 ".agent-context/layer3-guidebook.md" \
                 ".agent-context/skills/index.md" \
                 ".agent-context/knowledge-map.md"; do
        [ -f "$_tmpl" ] || echo "$_tmpl"
    done
}

check_critical_templates() {
    [ -z "$(missing_critical_templates)" ]
}

update_claude_md() {
    local updated=0 pointer
    for loc in ".claude/CLAUDE.md" "CLAUDE.md"; do
        [ -f "$loc" ] || continue
        if [ -L "$loc" ]; then
            echo "Skipped $loc — it is a symlink; its target is left as is."
            continue
        fi
        if is_bootstrap_only "$loc"; then
            continue
        fi
        pointer=$(bootstrap_pointer "$loc")
        printf '%s\n' "$pointer" > "$loc"
        echo "Updated $loc → $pointer"
        updated=1
    done
    if [ "$updated" -eq 0 ] && [ ! -f ".claude/CLAUDE.md" ] && [ ! -f "CLAUDE.md" ]; then
        mkdir -p .claude
        pointer=$(bootstrap_pointer .claude/CLAUDE.md)
        printf '%s\n' "$pointer" > .claude/CLAUDE.md
        echo "Created .claude/CLAUDE.md → $pointer"
    fi
}

# 0 when $1 is a higher x.y.z than $2 (leading v ignored); both must be valid version strings.
version_gt() {
    local IFS=. a b i
    read -r -a a <<< "${1#v}"
    read -r -a b <<< "${2#v}"
    for i in 0 1 2; do
        [ "$((10#${a[i]}))" -gt "$((10#${b[i]}))" ] && return 0
        [ "$((10#${a[i]}))" -lt "$((10#${b[i]}))" ] && return 1
    done
    return 1
}

validate_version_string() {
    [[ "$1" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

resolve_release_url() {
    validate_version_string "${1:-}" || return 1
    echo "https://github.com/lx-wnk/Agent-Context/archive/refs/tags/$1.tar.gz"
}

# The first released heading (## [x.y.z]) of a clone's CHANGELOG; [Unreleased] is skipped.
changelog_version() {
    sed -n 's/^## \[\([^]]*\)\].*/\1/p' "$1/CHANGELOG.md" 2>/dev/null \
        | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' | head -n 1 || true
}

# Downloads and extracts release $1; sets SOURCE_ROOT to the extracted tree (removed on exit).
fetch_release() {
    local url dir
    if ! url=$(resolve_release_url "$1"); then
        echo "Error: could not resolve the latest Agent-Context release — no agent was started." >&2
        return 1
    fi
    WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/agent-context-src.XXXXXX")
    trap 'rm -rf "$WORK_DIR"' EXIT
    if ! curl -fsSL --max-time 120 "$url" -o "$WORK_DIR/release.tar.gz"; then
        echo "Error: could not download $url — no agent was started." >&2
        return 1
    fi
    if ! tar -xzf "$WORK_DIR/release.tar.gz" -C "$WORK_DIR"; then
        echo "Error: could not extract $url — no agent was started." >&2
        return 1
    fi
    for dir in "$WORK_DIR"/*/; do
        if [ -f "$dir.prompts/setup-prompt.md" ]; then
            SOURCE_ROOT="${dir%/}"
            return 0
        fi
    done
    echo "Error: $url contains no .prompts/setup-prompt.md — no agent was started." >&2
    return 1
}

# Prints "source<TAB>destination" for each row of the Step 2 download table in <root>'s setup prompt.
shared_file_rows() {
    awk '/^\| *Source path/{t=1;next} t&&/^\| *`/{n=split($0,a,"`"); if(a[2]&&a[4]) print a[2]"\t"a[4]} t&&!/^\|/{t=0}' \
        "$1/.prompts/setup-prompt.md"
}

# A same-named command without an .agent-context/ reference is the user's own.
is_user_owned_command() {
    case "$1" in
        .claude/commands/*) [ -f "$1" ] && ! grep -q '\.agent-context/' "$1" ;;
        *) return 1 ;;
    esac
}

install_shared_files() {
    local root="$1" rows src dst
    rows=$(shared_file_rows "$root")
    if [ -z "$rows" ]; then
        echo "Error: no shared-file table in $root/.prompts/setup-prompt.md" >&2
        return 1
    fi
    while IFS="$(printf '\t')" read -r src dst; do
        case "$dst" in
            *..* | /*) echo "Error: unsafe shared-file destination: $dst" >&2; return 1 ;;
            .agent-context/* | .claude/commands/*) ;;
            *) echo "Error: shared-file destination outside .agent-context/ and .claude/commands/: $dst" >&2; return 1 ;;
        esac
        if [ ! -f "$root/$src" ]; then
            echo "Error: shared file missing from the source: $src" >&2
            return 1
        fi
        if is_user_owned_command "$dst"; then
            echo "Skipping $dst: user-owned command (no .agent-context/ reference)"
            continue
        fi
        mkdir -p "$(dirname "$dst")"
        if ! { cp "$root/$src" "$dst.tmp" && mv "$dst.tmp" "$dst"; }; then
            rm -f "$dst.tmp"
            echo "Error: could not install $dst" >&2
            return 1
        fi
        case "$dst" in
            .agent-context/bin/*.sh | .agent-context/hooks/*.sh) chmod +x "$dst" ;;
        esac
    done <<EOF
$rows
EOF
}

# Returns 0 if every hook script named in template $1 is referenced by a command in settings file $2.
settings_has_hooks() {
    local script
    [ -f "$2" ] || return 1
    while IFS= read -r script; do
        grep -qF "/$script\"" "$2" || return 1
    done <<EOF
$(grep -oE '[A-Za-z0-9_-]+\.sh' "$1")
EOF
}

# Prints settings $2 with each hook entry of template $1 appended whose script no command references yet.
merge_hooks_json() {
    if command -v jq >/dev/null 2>&1; then
        jq --slurpfile t "$1" '
            reduce ($t[0].hooks | to_entries[]) as $ev (.;
              reduce $ev.value[] as $entry (.;
                ($entry.hooks[0].command | split("/") | last) as $script
                | if ([.hooks[]?[]?.hooks[]?.command | strings | select(endswith("/" + $script))] | length) > 0
                  then .
                  else .hooks[$ev.key] = ((.hooks[$ev.key] // []) + [$entry])
                  end))' "$2"
    elif command -v python3 >/dev/null 2>&1; then
        python3 - "$1" "$2" <<'PY'
import json, sys
template = json.load(open(sys.argv[1]))
settings = json.load(open(sys.argv[2]))
hooks = settings.setdefault("hooks", {})
def commands():
    for entries in hooks.values():
        for entry in entries or []:
            for hook in entry.get("hooks", []):
                if isinstance(hook.get("command"), str):
                    yield hook["command"]
for event, entries in template["hooks"].items():
    for entry in entries:
        script = entry["hooks"][0]["command"].rsplit("/", 1)[-1]
        if not any(c.endswith("/" + script) for c in commands()):
            hooks.setdefault(event, []).append(entry)
print(json.dumps(settings, indent=2))
PY
    else
        echo "Error: neither jq nor python3 is available to merge hooks" >&2
        return 1
    fi
}

# Creates .claude/settings.json from the template, or merges in the hooks it lacks; an unmergeable
# file is left untouched and reported.
register_hooks() {
    local template="$1/templates/.claude/settings.json" dst=".claude/settings.json" tmp
    if [ ! -f "$dst" ]; then
        mkdir -p .claude
        cp "$template" "$dst"
        echo "Created $dst with the Agent-Context hooks (secret guard on; the rest off until HOOKS_ENABLED=1)"
        return 0
    fi
    settings_has_hooks "$template" "$dst" && return 0
    if ! command -v jq >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
        HOOKS_UNVERIFIABLE=1
        echo "Note: neither jq nor python3 is available to merge JSON — add the hook entries from"
        echo "      $template to $dst by hand (the secret guard is on by default; the rest stays off until HOOKS_ENABLED=1)."
        return 0
    fi
    tmp=$(mktemp "$dst.XXXXXX")
    if merge_hooks_json "$template" "$dst" > "$tmp" && settings_has_hooks "$template" "$tmp"; then
        cat "$tmp" > "$dst"
        rm -f "$tmp"
        echo "Registered the missing Agent-Context hooks in $dst (secret guard on; the rest off until HOOKS_ENABLED=1)"
        return 0
    fi
    rm -f "$tmp"
    echo "Error: could not merge the Agent-Context hooks into $dst (invalid JSON?) — left unchanged." >&2
    return 1
}

# Deletes shared scripts retired from .agent-context/bin/ that an older install left behind. Only a
# regular file or a symlink at exactly one of these paths is removed — a symlink is unlinked itself,
# its target is never touched — and nothing else in .agent-context/bin/ is touched.
remove_retired_shared_files() {
    local retired=(check-token-budget.sh check-map-budget.sh discovery-digest.sh measure-baseline.sh setup-steps.sh)
    local name path
    for name in "${retired[@]}"; do
        path=".agent-context/bin/$name"
        if [ -f "$path" ] || [ -L "$path" ]; then
            rm -f "$path"
            echo "Removed retired $path"
        fi
    done
}

# Prints every shared file that does not match source $1, every missing critical template, and
# unregistered hooks — one per line; prints nothing when the install is complete.
verify_install() {
    local root="$1" src dst
    while IFS="$(printf '\t')" read -r src dst; do
        [ -n "$dst" ] || continue
        is_user_owned_command "$dst" && continue
        cmp -s "$root/$src" "$dst" || echo "$dst"
    done <<EOF
$(shared_file_rows "$root")
EOF
    missing_critical_templates
    [ "${HOOKS_UNVERIFIABLE:-0}" -eq 1 ] && return 0
    settings_has_hooks "$root/templates/.claude/settings.json" .claude/settings.json \
        || echo ".claude/settings.json (Agent-Context hooks not registered)"
}

# Prints nothing (no cache) for a relative, empty or ..-containing base: a shared /tmp dir is not safe.
resolve_cache_dir() {
    case "$1" in
        */..*) ;;
        /*) echo "$1/agent-context" ;;
    esac
}

CACHE_DIR=$(resolve_cache_dir "${XDG_CACHE_HOME:-${HOME:+$HOME/.cache}}")
CACHE_FILE="${CACHE_DIR:+$CACHE_DIR/latest-version}"
CACHE_TTL=3600

# Set by get_latest_version in the caller's shell — never call it inside $(...), the flags would be lost.
CACHE_STALE=0
LATEST_VERSION=""

get_latest_version() {
    local cached=""
    [ -n "$CACHE_FILE" ] && [ -f "$CACHE_FILE" ] && cached=$(tr -d '[:space:]' < "$CACHE_FILE")
    validate_version_string "$cached" || cached=""
    if [ "$FORCE" -ne 1 ] && [ -n "$cached" ]; then
        local now mtime cache_age
        now=$(date +%s)
        # GNU first: GNU stat reads `-f %m` as --file-system and prints fs info to stdout; BSD rejects -c silently.
        mtime=$(stat -c %Y "$CACHE_FILE" 2>/dev/null || stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0)
        cache_age=$(( now - mtime ))
        # Negative cache_age means the system clock jumped backward — treat as stale.
        if [ "$cache_age" -ge 0 ] && [ "$cache_age" -lt "$CACHE_TTL" ]; then
            LATEST_VERSION="$cached"
            return
        fi
    fi
    local api_response version
    api_response=$(curl -fsSL --max-time 10 \
        "https://api.github.com/repos/lx-wnk/Agent-Context/releases/latest" 2>/dev/null) || true
    version=$(printf '%s\n' "$api_response" | awk -F'"' '/"tag_name"/{for(i=1;i<=NF;i++) if($i=="tag_name"){print $(i+2); exit}}') || true
    if validate_version_string "$version"; then
        # shellcheck disable=SC2174  # only the agent-context dir itself must be private
        if [ -n "$CACHE_DIR" ] && mkdir -p -m 700 "$CACHE_DIR" 2>/dev/null; then
            local tmp_cache
            if tmp_cache=$(mktemp "$CACHE_DIR/latest-version.XXXXXX" 2>/dev/null); then
                if ! { echo "$version" > "$tmp_cache" && mv "$tmp_cache" "$CACHE_FILE"; }; then
                    rm -f "$tmp_cache"
                fi
            fi
        fi
    elif [ -n "$cached" ]; then
        echo "Warning: GitHub API request failed; using stale cached version." >&2
        CACHE_STALE=1
        version="$cached"
    fi
    LATEST_VERSION="$version"
}

# The version file is written only after verification — never by the agent.
restore_version_file() {
    if [ -n "$VERSION_BEFORE_RUN" ]; then
        printf '%s\n' "$VERSION_BEFORE_RUN" > "$VERSION_FILE"
    else
        rm -f "$VERSION_FILE"
    fi
}

# Prints a lowercase v4 UUID, or nothing when none can be generated (claude rejects other session ids).
new_session_id() {
    local id
    id=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null) || return 0
    id=$(printf '%s' "$id" | tr 'A-F' 'a-f')
    [[ "$id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$ ]] && echo "$id"
    return 0
}

usage() {
    cat <<'EOF'
Usage: bash install.sh [--force] [--discover] [--local-source <path>] [--ai-dirs <dirs>]

  --force                 full from-scratch rediscovery, merging into existing knowledge
  --discover              after the run, point to the interactive /discover if no map exists
  --local-source <path>   install from a local Agent-Context clone (env: AGENT_CONTEXT_SOURCE)
  --ai-dirs <dirs>        comma-separated extra AI-doc dirs to treat as migratable
  -h, --help              show this help
EOF
}

main() {
    if ! command -v curl &>/dev/null; then
        echo "Error: curl not found. Install curl and try again." >&2
        exit 1
    fi

    ALLOWED_TOOLS="Read,Write,Edit,Glob,Grep,Agent"
    ALLOWED_TOOLS="$ALLOWED_TOOLS,Bash(mkdir:*),Bash(mv:*),Bash(cp:*),Bash(chmod +x:*)"
    ALLOWED_TOOLS="$ALLOWED_TOOLS,Bash(rm -f:*)"
    ALLOWED_TOOLS="$ALLOWED_TOOLS,Bash(git ls-files:*),Bash(git rm:*),Bash(git status:*),Bash(git log:*)"
    ALLOWED_TOOLS="$ALLOWED_TOOLS,Bash(sha256sum:*),Bash(shasum:*),Bash(echo:*),Bash(printf:*),Bash(cat:*)"
    ALLOWED_TOOLS="$ALLOWED_TOOLS,Bash(grep:*),Bash(wc:*),Bash(head:*),Bash(tail:*),Bash(ls:*),Bash(test:*)"
    LOG=".agent-context/setup.log"
    AGENT_OUTPUT=".agent-context/setup-output.md"
    VERSION_FILE=".agent-context/.agent-context-version"

    SOURCE_ROOT=""
    TARGET_TAG=""
    AI_DIRS=""
    DISCOVER=0
    LOCAL_SOURCE_FLAG=0
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -h | --help) usage; exit 0 ;;
            --ai-dirs=*) AI_DIRS="${1#--ai-dirs=}" ;;
            --ai-dirs)
                case "${2:-}" in
                    "" | -*) echo "Error: --ai-dirs requires a value" >&2; usage >&2; exit 2 ;;
                esac
                AI_DIRS="$2"
                shift
                ;;
            --force) FORCE=1 ;;
            --discover) DISCOVER=1 ;;
            --local-source=*)
                LOCAL_SOURCE_FLAG=1
                AGENT_CONTEXT_SOURCE="${1#--local-source=}"
                ;;
            --local-source)
                LOCAL_SOURCE_FLAG=1
                AGENT_CONTEXT_SOURCE=""
                # A following flag is not a path; leave it for the next iteration.
                case "${2:-}" in
                    "" | -*) ;;
                    *) AGENT_CONTEXT_SOURCE="$2"; shift ;;
                esac
                ;;
            *) echo "Error: unknown option: $1" >&2; usage >&2; exit 2 ;;
        esac
        shift
    done
    if [ "$LOCAL_SOURCE_FLAG" -eq 1 ] && [ -z "$AGENT_CONTEXT_SOURCE" ]; then
        echo "Error: --local-source requires a path" >&2
        exit 1
    fi
    if [ "$LOCAL_SOURCE_FLAG" -eq 0 ] && [ -n "${AGENT_CONTEXT_SOURCE:-}" ]; then
        echo "Note: AGENT_CONTEXT_SOURCE is set — installing from $AGENT_CONTEXT_SOURCE instead of the latest release."
    fi

    if [ -n "${AGENT_CONTEXT_SOURCE:-}" ]; then
        if [ ! -d "$AGENT_CONTEXT_SOURCE" ]; then
            echo "Error: local source directory not found (--local-source / AGENT_CONTEXT_SOURCE): $AGENT_CONTEXT_SOURCE" >&2
            exit 1
        fi
        SOURCE_ROOT=$(realpath "$AGENT_CONTEXT_SOURCE" 2>/dev/null || (cd "$AGENT_CONTEXT_SOURCE" && pwd))
        if [ ! -f "$SOURCE_ROOT/.prompts/setup-prompt.md" ]; then
            echo "Error: not an Agent-Context clone (no .prompts/setup-prompt.md): $SOURCE_ROOT" >&2
            exit 1
        fi
        TARGET_TAG=$(changelog_version "$SOURCE_ROOT")
        if [ -z "$TARGET_TAG" ]; then
            echo "Error: no released version (## [x.y.z]) in $SOURCE_ROOT/CHANGELOG.md" >&2
            exit 1
        fi
    else
        get_latest_version
    fi

    INSTALLED_VERSION=""
    if [ -f "$VERSION_FILE" ]; then
        INSTALLED_VERSION=$(tr -d '[:space:]' < "$VERSION_FILE")
    fi

    migrate_import_paths
    ensure_hooks_local_conf_ignored
    warn_committed_hook_keys

    # Fast-path: skip Claude spawn if already up-to-date.
    # Guards: version match alone is not proof of a complete installation — a CLAUDE.md with
    # real content still needs migration, and missing templates need restoration.
    if [ "$FORCE" -ne 1 ] && [ -f ".agent-context/.agent-context-version" ]; then
        # Strip optional leading 'v' so "v0.5.3" and "0.5.3" compare as equal.
        # An empty INSTALLED_VERSION (e.g. blank version file) intentionally falls through:
        # the equality check is false, so the full update flow runs.
        if [ -n "$LATEST_VERSION" ] && [ "${INSTALLED_VERSION#v}" = "${LATEST_VERSION#v}" ]; then
            _needs_agent=0
            for _loc in ".claude/CLAUDE.md" "CLAUDE.md"; do
                if [ -f "$_loc" ] && ! is_bootstrap_only "$_loc"; then
                    _needs_agent=1
                    break
                fi
            done
            if [ "$_needs_agent" -eq 0 ] && ! check_critical_templates; then
                _needs_agent=1
            fi
            if [ "$_needs_agent" -eq 0 ]; then
                if [ "$CACHE_STALE" -eq 1 ]; then
                    echo "Warning: version check based on stale cached data — run with --force to verify." >&2
                fi
                echo "agent-context is already up to date ($INSTALLED_VERSION). Nothing to do."
                # Creates .claude/CLAUDE.md only when neither location exists yet (fresh install).
                update_claude_md
                exit 0
            fi
            # Fall through: CLAUDE.md has real content to migrate, or template files are missing.
        fi
    fi

    SESSION_ID=$(new_session_id)
    SESSION_ARGS=()
    if [ -n "$SESSION_ID" ]; then
        SESSION_ARGS=(--session-id "$SESSION_ID")
        export CLAUDE_SESSION_ID="$SESSION_ID"
    fi

    if ! command -v claude &>/dev/null; then
        echo "Error: claude CLI not found. Install it from https://claude.ai/code" >&2
        exit 1
    fi

    if [ -z "$SOURCE_ROOT" ]; then
        TARGET_TAG="$LATEST_VERSION"
        if validate_version_string "$INSTALLED_VERSION" && validate_version_string "$TARGET_TAG" \
            && version_gt "$INSTALLED_VERSION" "$TARGET_TAG"; then
            echo "agent-context $INSTALLED_VERSION is newer than the latest release $TARGET_TAG — nothing downgraded."
            exit 0
        fi
        fetch_release "$TARGET_TAG" || exit 1
    fi

    PROMPT_INSTRUCTION="Read $SOURCE_ROOT/.prompts/setup-prompt.md and follow its instructions exactly."
    if [ -z "${AGENT_CONTEXT_SOURCE:-}" ]; then
        PROMPT_INSTRUCTION="$PROMPT_INSTRUCTION TARGET VERSION: $TARGET_TAG — install exactly this release tag in Steps 2 and 3; do not pick another."
    fi
    PROMPT_INSTRUCTION="$PROMPT_INSTRUCTION LOCAL SOURCE MODE: do NOT download from GitHub. Install every template outside .claude/ (Step 3) by copying from the Agent-Context source at $SOURCE_ROOT using the same relative paths (e.g. copy $SOURCE_ROOT/templates/AGENTS.md to AGENTS.md). Skip the remote version lookup and all <tag> URL building; the target version is $TARGET_TAG."
    if [ -n "$AI_DIRS" ]; then
        PROMPT_INSTRUCTION="$PROMPT_INSTRUCTION Additional AI directories to treat as migratable (extends built-in defaults): $AI_DIRS"
    fi
    if [ "$FORCE" -eq 1 ]; then
        PROMPT_INSTRUCTION="$PROMPT_INSTRUCTION FORCE / FULL REDISCOVERY: skip all up-to-date checks and, even on an existing install, run a complete from-scratch discovery — re-scan the entire codebase and rebuild the knowledge inventory at SETUP depth, do not merely reconcile deltas. Merge into the existing memory/decisions/knowledge-map; never delete a still-valid fact (move it, don't lose it)."
    fi
    PROMPT_INSTRUCTION="$PROMPT_INSTRUCTION HEADLESS: no user is present; never wait for input, decide per the prompt's headless rules."
    if validate_version_string "$INSTALLED_VERSION"; then
        PROMPT_INSTRUCTION="$PROMPT_INSTRUCTION INSTALLED VERSION: $INSTALLED_VERSION"
    else
        PROMPT_INSTRUCTION="$PROMPT_INSTRUCTION INSTALLED VERSION: none"
    fi
    PROMPT_INSTRUCTION="$PROMPT_INSTRUCTION INSTALLER MANAGES: shared files, .claude/commands, .claude/settings.json hooks, .claude/CLAUDE.md and the version file — do not write them."

    mkdir -p .agent-context
    install_shared_files "$SOURCE_ROOT" || exit 1
    VERSION_BEFORE_RUN=""
    [ -f "$VERSION_FILE" ] && VERSION_BEFORE_RUN=$(cat "$VERSION_FILE")
    rm -f "$LOG" "$AGENT_OUTPUT"
    : > "$LOG"

    echo "Starting agent-context setup in $(pwd)..."
    if [ -n "$SESSION_ID" ]; then
        echo "Session ID: $SESSION_ID  (run 'claude --resume $SESSION_ID' to resume if needed)"
    fi

    AGENT_CONTEXT_SETUP=1 AI_DIRS="$AI_DIRS" claude -p "$PROMPT_INSTRUCTION" \
        --allowedTools "$ALLOWED_TOOLS" \
        --disallowedTools "WebFetch,WebSearch" \
        --add-dir "$SOURCE_ROOT" \
        --permission-mode acceptEdits \
        --strict-mcp-config \
        --output-format text \
        ${SESSION_ARGS[@]+"${SESSION_ARGS[@]}"} \
        < /dev/null > "$AGENT_OUTPUT" &
    CLAUDE_PID=$!
    # A background job ignores the terminal's SIGINT, so Ctrl-C must stop the agent explicitly.
    trap 'kill "$CLAUDE_PID" 2>/dev/null; restore_version_file; echo "" >&2; echo "Interrupted — the setup agent was stopped; see $LOG." >&2; exit 130' INT TERM

    # The latest log line stays open, so the waiting dots trail the step that is running;
    # the newline is only written once the next line arrives.
    show_progress() {
        local last=0 poll="${AGENT_CONTEXT_POLL_SECS:-5}"

        printf "Waiting for the setup agent"
        while kill -0 "$CLAUDE_PID" 2>/dev/null; do
            # wc -l is correct here: setup.log is always written with printf '%s\n',
            # so it always has a trailing newline. (update_claude_md uses awk because
            # CLAUDE.md may lack a trailing newline — a different case.)
            current=$(wc -l < "$LOG" 2>/dev/null || echo 0)
            if [ "$current" -gt "$last" ]; then
                printf "\n%s" "$(tail -n +"$((last + 1))" "$LOG" | head -n "$((current - last))")"
                last=$current
                grep -q "^\[agent-context\] Done\." "$LOG" 2>/dev/null && break
            else
                printf "."
                sleep "$poll"
            fi
        done

        # Flush remaining lines written after process exits
        current=$(wc -l < "$LOG" 2>/dev/null || echo 0)
        if [ "$current" -gt "$last" ]; then
            printf "\n%s" "$(tail -n +"$((last + 1))" "$LOG")"
        fi
        printf "\n"
    }

    show_progress
    AGENT_EXIT=0
    wait "$CLAUDE_PID" || AGENT_EXIT=$?
    trap - INT TERM
    EXIT_CODE=$AGENT_EXIT
    restore_version_file

    if [ -s "$AGENT_OUTPUT" ]; then
        echo ""
        echo "Setup agent output (last 40 lines):"
        tail -n 40 "$AGENT_OUTPUT"
        echo ""
    fi

    if [ "$EXIT_CODE" -eq 0 ] && ! grep -q "^\[agent-context\] Done\." "$LOG" 2>/dev/null; then
        echo "Error: the setup agent exited without logging '[agent-context] Done.'" >&2
        EXIT_CODE=2
    fi

    # Only run when agent succeeded — a failed mid-migration must not overwrite CLAUDE.md content
    # that hasn't yet been routed to layer files.
    if [ "$EXIT_CODE" -eq 0 ]; then
        update_claude_md
        register_hooks "$SOURCE_ROOT" || true
    fi
    migrate_import_paths
    ensure_hooks_local_conf_ignored

    if [ "$EXIT_CODE" -eq 0 ]; then
        MISSING=$(verify_install "$SOURCE_ROOT")
        if [ -n "$MISSING" ]; then
            echo "Error: installation incomplete — missing or not matching $TARGET_TAG:" >&2
            printf '%s\n' "$MISSING" | sed 's/^/  /' >&2
            EXIT_CODE=2
        else
            remove_retired_shared_files
            printf '%s\n' "$TARGET_TAG" > "$VERSION_FILE"
            echo "Installed Agent-Context $TARGET_TAG (all shared files verified)."
        fi
    fi

    if ! grep -q "^\[agent-context\]" "$LOG" 2>/dev/null; then
        echo "Warning: no progress was logged — Claude may have exited early or encountered an error."
        echo "Use --local-source <clone> for a local install, or check that 'claude' is authenticated."
    fi

    # --discover is a hand-off, not a headless build: a rich map needs fan-out discovery, which runs
    # reliably only in an interactive session. Report the truth instead of faking progress.
    if [ "$DISCOVER" -eq 1 ]; then
        if [ -f ".agent-context/map.json" ]; then
            echo "Discovery map present: .agent-context/map.json"
        else
            echo ""
            echo "No discovery map was built — a rich map needs fan-out discovery, which runs reliably"
            echo "only in an interactive agent session, not this one-shot installer."
            echo "  -> Open this project in Claude Code and run:  /discover"
        fi
    fi

    if [ "$AGENT_EXIT" -ne 0 ]; then
        echo "Error: the setup agent exited with code $AGENT_EXIT — CLAUDE.md was left unchanged; see $LOG and $AGENT_OUTPUT." >&2
    elif [ "$EXIT_CODE" -ne 0 ]; then
        echo "The version file was not updated; see $LOG and $AGENT_OUTPUT." >&2
    else
        rm -f "$LOG" "$AGENT_OUTPUT"
    fi
    exit "$EXIT_CODE"
}

if [[ "${BASH_SOURCE[0]:-$0}" == "$0" ]]; then main "$@"; fi
