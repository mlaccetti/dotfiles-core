#!/bin/bash
# Installs Homebrew if it isn't already present.
#
# Not using `set -e` for the whole script on purpose: a blocked Homebrew
# install (e.g. corporate/MDM policy) should not abort the rest of
# `chezmoi apply` - your other dotfiles still need to land.
set -uo pipefail

echo "==> [homebrew] Checking for Homebrew..."

if command -v brew >/dev/null 2>&1; then
  echo "    Homebrew is already installed at $(command -v brew). Skipping install."
  exit 0
fi

# Homebrew can be installed but not on this process's PATH (Apple Silicon's
# /opt/homebrew/bin is not on the default PATH, for example). Check the
# standard locations before deciding it is missing and running the installer.
for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
  if [ -x "$candidate" ]; then
    echo "    Homebrew is already installed at ${candidate} (not on PATH yet). Skipping install."
    exit 0
  fi
done

echo "    Homebrew not found. Attempting to install..."

if [ "$(uname -m)" = "arm64" ]; then
  BREW_PREFIX="/opt/homebrew"
else
  BREW_PREFIX="/usr/local"
fi

if /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
  echo "    Homebrew installed successfully."
  if [ -x "${BREW_PREFIX}/bin/brew" ]; then
    eval "$("${BREW_PREFIX}/bin/brew" shellenv)"
  fi
else
  echo "    !! Homebrew install did not complete."
  echo "    !! This is expected on a corporate/MDM-managed Mac if installing"
  echo "    !! new software requires IT approval or is blocked by policy."
  echo "    !! ACTION NEEDED: ask IT to approve/install Homebrew, or install"
  echo "    !! it yourself once you have permission, then re-run: chezmoi apply"
  echo "    Continuing with the rest of the setup (dotfiles will still be applied)."
fi

exit 0
