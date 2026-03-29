#!/usr/bin/env bash
# SessionStart hook: auto-update agent-context + sync plugins
# Runs at every Claude Code session start via .claude/settings.json hook
set -euo pipefail

REPO="lx-wnk/Agent-Context"
BASE_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
CONTEXT_DIR="$BASE_DIR/.agent-context"
VERSION_FILE="$CONTEXT_DIR/.version"
PLUGINS_FILE="$CONTEXT_DIR/plugins.json"
SETTINGS_FILE="$BASE_DIR/.claude/settings.json"

messages=()

# --- Part 1: Auto-update check ---
current_version="0.0.0"
[[ -f "$VERSION_FILE" ]] && current_version="$(cat "$VERSION_FILE" | tr -d '[:space:]')"

latest_json="$(curl -sf "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null || true)"
if [[ -n "$latest_json" ]] && command -v jq &>/dev/null; then
  latest_version="$(echo "$latest_json" | jq -r '.tag_name // empty' | sed 's/^v//')"
  tarball_url="$(echo "$latest_json" | jq -r '.tarball_url // empty')"

  if [[ -n "$latest_version" && "$latest_version" != "$current_version" && -n "$tarball_url" ]]; then
    tmp_dir="$(mktemp -d)"
    trap 'rm -rf "$tmp_dir"' EXIT

    if curl -sfL "$tarball_url" | tar xz -C "$tmp_dir" --strip-components=1 2>/dev/null; then
      # Copy shared files
      [[ -f "$tmp_dir/context/agent-startup.md" ]]       && cp "$tmp_dir/context/agent-startup.md"       "$CONTEXT_DIR/agent-startup.md"
      [[ -f "$tmp_dir/context/layer0-agent-workflow.md" ]] && cp "$tmp_dir/context/layer0-agent-workflow.md" "$CONTEXT_DIR/layer0-agent-workflow.md"
      [[ -f "$tmp_dir/context/base-principles.md" ]]      && cp "$tmp_dir/context/base-principles.md"      "$CONTEXT_DIR/base-principles.md"
      [[ -f "$tmp_dir/plugins.json" ]]                    && cp "$tmp_dir/plugins.json"                    "$CONTEXT_DIR/plugins.json"

      # Self-update this script
      if [[ -f "$tmp_dir/scripts/agent-context-update.sh" ]]; then
        mkdir -p "$CONTEXT_DIR/scripts"
        cp "$tmp_dir/scripts/agent-context-update.sh" "$CONTEXT_DIR/scripts/agent-context-update.sh"
        chmod +x "$CONTEXT_DIR/scripts/agent-context-update.sh"
      fi

      echo "$latest_version" > "$VERSION_FILE"
      messages+=("Agent context updated $current_version → $latest_version")
    fi

    rm -rf "$tmp_dir"
    trap - EXIT
  fi
fi

# --- Part 2: Plugin sync ---
if command -v jq &>/dev/null && [[ -f "$PLUGINS_FILE" ]]; then
  if [[ ! -f "$SETTINGS_FILE" ]]; then
    mkdir -p "$(dirname "$SETTINGS_FILE")"
    echo '{}' > "$SETTINGS_FILE"
  fi

  added=()
  while IFS= read -r plugin; do
    existing="$(jq -r --arg p "$plugin" '.enabledPlugins[$p] // empty' "$SETTINGS_FILE")"
    if [[ -z "$existing" ]]; then
      tmp="$(jq --arg p "$plugin" '.enabledPlugins[$p] = true' "$SETTINGS_FILE")"
      echo "$tmp" > "$SETTINGS_FILE"
      added+=("$plugin")
    fi
  done < <(jq -r '.[]' "$PLUGINS_FILE")

  if [[ ${#added[@]} -gt 0 ]]; then
    messages+=("Synced ${#added[@]} new plugin(s)")
  fi
fi

# --- Output ---
if [[ ${#messages[@]} -gt 0 ]]; then
  combined="$(IFS='; '; echo "${messages[*]}")"
  printf '{"systemMessage":"%s"}\n' "$combined"
fi
