#!/bin/bash
# Installs the core (shared) Homebrew tier from this repo's Brewfile.
#
# Not using `set -e` for the whole script on purpose: one blocked cask
# (e.g. corporate/MDM Gatekeeper policy) should not abort the rest of
# `chezmoi apply`.
set -uo pipefail

echo "==> [brew bundle] Installing/checking core Homebrew packages..."

# run_once_before_00 may have installed Homebrew moments ago. It ran
# `brew shellenv` in its own process, which this fresh process never sees, so
# on a brand-new Apple Silicon Mac (/opt/homebrew/bin is not on the default
# PATH) `command -v brew` fails even though brew is installed. Fall back to
# the standard install locations, then load brew's environment.
BREW_BIN="$(command -v brew 2>/dev/null || true)"
if [ -z "$BREW_BIN" ]; then
  for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [ -x "$candidate" ]; then
      BREW_BIN="$candidate"
      eval "$("$BREW_BIN" shellenv)"
      break
    fi
  done
fi

if [ -z "$BREW_BIN" ]; then
  echo "    !! Homebrew isn't installed (see the previous step's output)."
  echo "    !! ACTION NEEDED: install Homebrew, then run:"
  echo "    !!   brew bundle --file=\"\$(chezmoi source-path)/Brewfile\""
  echo "    Skipping brew bundle for now."
  exit 0
fi

echo "    Using Homebrew: ${BREW_BIN}"

SOURCE_DIR="${CHEZMOI_SOURCE_DIR:-$HOME/.local/share/chezmoi}"
BREWFILE="${SOURCE_DIR}/Brewfile"

if [ ! -f "$BREWFILE" ]; then
  echo "    !! Could not find Brewfile at: ${BREWFILE}"
  echo "    !! Skipping brew bundle - run it manually once you locate it:"
  echo "    !!   brew bundle --file=/path/to/Brewfile"
  exit 0
fi

echo "    Using Brewfile: ${BREWFILE}"

if "$BREW_BIN" bundle --file="$BREWFILE"; then
  echo "    Core packages installed/verified."
else
  echo "    !! One or more packages failed to install."
  echo "    !! This can happen on a corporate/MDM-managed Mac when a cask"
  echo "    !! (an app installer) requires IT approval, or when Gatekeeper/"
  echo "    !! notarization policy blocks it."
  echo "    !! ACTION NEEDED: check the output above for which formula/cask"
  echo "    !! failed, ask IT for approval if needed, then re-run:"
  echo "    !!   brew bundle --file=\"${BREWFILE}\""
  echo "    Continuing with the rest of the setup."
fi

exit 0
