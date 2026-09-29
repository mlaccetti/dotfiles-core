#!/bin/bash
# Installs the Anthropic iTerm2 Dynamic Profile by copying it into
# iTerm2's DynamicProfiles directory, then (only when iTerm2 is NOT running)
# makes it iTerm2's default profile by writing its Guid to the
# "Default Bookmark Guid" preference.
#
# Why iTerm2 must not be running: iTerm2 keeps preferences in memory and
# rewrites them on quit, so a value written while it runs is overwritten.
# This script never quits or kills iTerm2; if it is running it says so and
# leaves the default alone.
#
# Why this works: "Default Bookmark Guid" is iTerm2's preference key for the
# default profile (KEY_DEFAULT_GUID in ITAddressBookMgr.h). On launch iTerm2
# reads it, loads the Dynamic Profiles, and if one of them has that Guid,
# re-applies it as the default (ITAddressBookMgr.m, "One of the dynamic
# profiles has the default guid"), so a Dynamic Profile Guid is a valid value.
#
# Idempotent: it only writes when the stored default differs from the
# profile's Guid. NOTE for chezmoi: run_once_ scripts are keyed by the
# SHA-256 of their content, so editing this file makes chezmoi run it once
# more on machines that ran the older version. That re-run is safe.
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
else
  echo "    !! Could not write to: ${DEST_DIR}"
  echo "    !! This can happen if iTerm2's Application Support folder is"
  echo "    !! restricted by MDM/managed-app policy, or iTerm2 isn't installed."
  echo "    !! ACTION NEEDED: check permissions on that folder, or copy"
  echo "    !! ${SRC_PROFILE} there by hand once iTerm2 is installed."
  exit 0
fi

# ---- Make Anthropic the default profile ------------------------------------
# ITERM2_DEFAULTS_DOMAIN exists so the write can be tested against a scratch
# plist path instead of the real iTerm2 preferences.
ITERM_DOMAIN="${ITERM2_DEFAULTS_DOMAIN:-com.googlecode.iterm2}"
PROFILE_GUID=""
if command -v jq >/dev/null 2>&1; then
  PROFILE_GUID="$(jq -r '[.Profiles[]? | select(.Name == "Anthropic") | .Guid][0] // empty' "$SRC_PROFILE" 2>/dev/null || true)"
fi
if [ -z "$PROFILE_GUID" ] && command -v plutil >/dev/null 2>&1; then
  # plutil reads JSON too; the profile is the first (only) entry.
  PROFILE_GUID="$(plutil -extract Profiles.0.Guid raw -o - "$SRC_PROFILE" 2>/dev/null || true)"
fi

echo ""
if [ -z "$PROFILE_GUID" ]; then
  echo "    !! Could not read the profile Guid from ${SRC_PROFILE} (need jq or plutil)."
  echo "    !! Set the default by hand: iTerm2 > Settings > Profiles > Anthropic >"
  echo "    !! Other Actions > Set as Default."
else
  CURRENT_GUID="$(defaults read "$ITERM_DOMAIN" "Default Bookmark Guid" 2>/dev/null || true)"
  if [ "$CURRENT_GUID" = "$PROFILE_GUID" ]; then
    echo "    The Anthropic profile is already iTerm2's default profile."
  elif pgrep -x iTerm2 >/dev/null 2>&1; then
    echo "    iTerm2 is running, so the default profile was NOT changed: iTerm2"
    echo "    saves its preferences on quit and would overwrite the value."
    echo "    ACTION NEEDED, either:"
    echo "      - quit iTerm2 (Cmd-Q), reopen it, and re-run this script:"
    echo "          bash \"\$(chezmoi source-path)/run_once_after_10-install-iterm2-profile.sh\""
    echo "      - or set it by hand: iTerm2 > Settings > Profiles > Anthropic >"
    echo "        Other Actions > Set as Default."
    echo "    (chezmoi will not re-run this script by itself.)"
  elif defaults write "$ITERM_DOMAIN" "Default Bookmark Guid" -string "$PROFILE_GUID"; then
    if [ "$(defaults read "$ITERM_DOMAIN" "Default Bookmark Guid" 2>/dev/null || true)" = "$PROFILE_GUID" ]; then
      echo "    Set the Anthropic profile as iTerm2's default (takes effect when"
      echo "    iTerm2 next starts; verify with bin/doctor.sh)."
    else
      echo "    !! Wrote the default profile but could not read it back."
      echo "    !! Set it by hand: iTerm2 > Settings > Profiles > Anthropic > Other Actions > Set as Default."
    fi
  else
    echo "    !! 'defaults write' failed. Set the default by hand: iTerm2 >"
    echo "    !! Settings > Profiles > Anthropic > Other Actions > Set as Default."
  fi
fi

exit 0
