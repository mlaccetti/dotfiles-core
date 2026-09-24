#!/bin/bash
# Installs the Anthropic iTerm2 Dynamic Profile by copying it into
# iTerm2's DynamicProfiles directory. iTerm2 must still be told to use
# it (see the printed note below) - that part can't be automated safely.
set -uo pipefail

HOME_DIR="${CHEZMOI_HOME_DIR:-$HOME}"
SOURCE_DIR="${CHEZMOI_SOURCE_DIR:-$HOME/.local/share/chezmoi}"

SRC_PROFILE="${SOURCE_DIR}/iterm2/Anthropic.json"
DEST_DIR="${HOME_DIR}/Library/Application Support/iTerm2/DynamicProfiles"
DEST_PROFILE="${DEST_DIR}/Anthropic.json"

echo "==> [iterm2] Installing the Anthropic Dynamic Profile..."

if [ ! -f "$SRC_PROFILE" ]; then
  echo "    !! Could not find ${SRC_PROFILE} - skipping."
  exit 0
fi

if mkdir -p "$DEST_DIR" && cp "$SRC_PROFILE" "$DEST_PROFILE"; then
  echo "    Installed: ${DEST_PROFILE}"
  echo ""
  echo "    NOTE: restart iTerm2 (or wait a few seconds if it's already"
  echo "    running - Dynamic Profiles are picked up live), then manually"
  echo "    select the 'Anthropic' profile: iTerm2 > Settings > Profiles,"
  echo "    or right-click a tab > Edit Session > Profile > Anthropic."
else
  echo "    !! Could not write to: ${DEST_DIR}"
  echo "    !! This can happen if iTerm2's Application Support folder is"
  echo "    !! restricted by MDM/managed-app policy, or iTerm2 isn't installed."
  echo "    !! ACTION NEEDED: check permissions on that folder, or copy"
  echo "    !! ${SRC_PROFILE} there by hand once iTerm2 is installed."
fi

exit 0
