#!/bin/bash
# Sets git's global user.name/user.email from the name/email chezmoi
# collected at `chezmoi init` time (see .chezmoi.toml.tmpl) - but ONLY if
# git doesn't already have an identity configured.
#
# This is a WORK laptop that may already have a git identity set by IT or
# by the employer's onboarding. A chezmoi-managed ~/.gitconfig would risk
# clobbering that, so this script never manages ~/.gitconfig as a whole -
# it sets user.name/user.email individually via `git config --global`,
# and only the ones that are missing. An existing identity is never
# overwritten.
#
# Note: chezmoi does NOT export custom [data] values (like .name/.email)
# as CHEZMOI_* environment variables to scripts - only its own built-in
# fields do (CHEZMOI_SOURCE_DIR, CHEZMOI_OS, etc. - run `chezmoi data` and
# look under the "chezmoi" key to see the full list). The only reliable
# way to read what was prompted at init time is `chezmoi data`, piped
# through jq.
set -euo pipefail

echo "==> [git identity] Checking git commit identity..."

if ! command -v git >/dev/null 2>&1; then
  echo "    !! git is not installed - skipping. Nothing to configure."
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "    !! jq is not installed - can't safely read the name/email chezmoi"
  echo "    !! collected at init time."
  echo "    !! ACTION NEEDED: install jq (it's in the core Brewfile), then"
  echo "    !! re-run 'chezmoi apply', or set git identity by hand:"
  echo "    !!   git config --global user.name \"Your Name\""
  echo "    !!   git config --global user.email \"you@example.com\""
  exit 0
fi

CHEZMOI_BIN="${CHEZMOI_EXECUTABLE:-chezmoi}"

if ! command -v "$CHEZMOI_BIN" >/dev/null 2>&1; then
  echo "    !! Could not find the chezmoi executable - skipping."
  exit 0
fi

DATA="$("$CHEZMOI_BIN" data 2>/dev/null || echo "")"

if [ -z "$DATA" ]; then
  echo "    !! Could not read chezmoi's collected data - skipping."
  echo "    !! ACTION NEEDED: set git identity by hand if needed:"
  echo "    !!   git config --global user.name \"Your Name\""
  echo "    !!   git config --global user.email \"you@example.com\""
  exit 0
fi

NAME="$(printf '%s' "$DATA" | jq -r '.name // empty')"
EMAIL="$(printf '%s' "$DATA" | jq -r '.email // empty')"

EXISTING_NAME="$(git config --global --get user.name 2>/dev/null || true)"
EXISTING_EMAIL="$(git config --global --get user.email 2>/dev/null || true)"

if [ -n "$EXISTING_NAME" ] && [ -n "$EXISTING_EMAIL" ]; then
  echo "    git already has a global name AND email - leaving both untouched:"
  echo "      user.name  = ${EXISTING_NAME}"
  echo "      user.email = ${EXISTING_EMAIL}"
  exit 0
fi

if [ -n "$EXISTING_NAME" ]; then
  echo "    user.name is already set to '${EXISTING_NAME}' - leaving it untouched."
elif [ -n "$NAME" ]; then
  git config --global user.name "$NAME"
  echo "    Set user.name = ${NAME}"
else
  echo "    !! chezmoi has no name on record (unexpected) - skipping user.name."
  echo "    !! ACTION NEEDED: git config --global user.name \"Your Name\""
fi

if [ -n "$EXISTING_EMAIL" ]; then
  echo "    user.email is already set to '${EXISTING_EMAIL}' - leaving it untouched."
elif [ -n "$EMAIL" ]; then
  git config --global user.email "$EMAIL"
  echo "    Set user.email = ${EMAIL}"
else
  echo "    !! chezmoi has no email on record (unexpected) - skipping user.email."
  echo "    !! ACTION NEEDED: git config --global user.email \"you@example.com\""
fi

exit 0
