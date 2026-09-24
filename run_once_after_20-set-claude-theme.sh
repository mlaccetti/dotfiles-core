#!/bin/bash
# Sets Claude Code's theme to the Anthropic palette by merging
# "theme": "custom:anthropic" into ~/.claude/settings.json with jq, which
# preserves every other key already in that file. Never clobbers.
set -uo pipefail

HOME_DIR="${CHEZMOI_HOME_DIR:-$HOME}"
CLAUDE_DIR="${HOME_DIR}/.claude"
SETTINGS="${CLAUDE_DIR}/settings.json"

echo "==> [claude code] Setting theme to 'custom:anthropic'..."

if ! command -v jq >/dev/null 2>&1; then
  echo "    !! jq is not installed - can't safely edit settings.json."
  echo "    !! ACTION NEEDED: install jq (it's in the core Brewfile), then"
  echo "    !! re-run 'chezmoi apply', or add this by hand to ${SETTINGS}:"
  echo "    !!   \"theme\": \"custom:anthropic\""
  exit 0
fi

mkdir -p "$CLAUDE_DIR"

if [ ! -f "$SETTINGS" ]; then
  echo "    No existing settings.json found - creating a minimal one."
  echo '{}' > "$SETTINGS"
fi

TMP_FILE="$(mktemp)"
if jq '.theme = "custom:anthropic"' "$SETTINGS" > "$TMP_FILE" 2>/dev/null; then
  mv "$TMP_FILE" "$SETTINGS"
  echo "    Done. Every other key already in settings.json was left untouched."
else
  rm -f "$TMP_FILE"
  echo "    !! Failed to update ${SETTINGS} - is it valid JSON?"
  echo "    !! ACTION NEEDED: fix or back up that file, then re-run 'chezmoi apply'."
fi

exit 0
