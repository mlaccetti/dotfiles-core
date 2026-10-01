#!/usr/bin/env bash
# provision-preinstalled.sh
#
# Runs INSIDE the Tart VM (Cirrus Labs macOS base image, user "admin").
# Brings the VM to the "preinstalled" starting state, a Mac where the apps are already
# installed before the setup guide runs:
#   - Homebrew installed (comes with the Cirrus base image; verified here)
#   - iTerm2, Visual Studio Code, 1Password, 1Password CLI (op) installed from
#     vendor downloads, NOT via Homebrew (so `brew list --cask` must not show them)
#   - Claude Code installed with the official native installer, NOT Homebrew
#   - No Nerd Font, no dotfiles/chezmoi/oh-my-zsh, default shell zsh
#
# Idempotent: every step checks current state first. Safe to re-run.
# No credentials are used. No GUI app is launched. Never runs `claude` interactively.
#
# Pinned vendor downloads (verified 2026-09-29). SHA-256 values are pinned so a
# re-run cannot silently pick up different bytes. VS Code's hash is the one the
# vendor publishes via update.code.visualstudio.com/api/update; the others were
# recorded on first download from the vendor URL (trust on first use).
set -euo pipefail

# Refuse to run anywhere but the throwaway sandbox VM: this script changes the machine
# it runs on. kern.hv_vmm_present is 1 on a Tart macOS guest and 0 on the host (checked
# in a sandbox-base clone: guest 1, model VirtualMac2,1; host 0, model Mac14,6), and the
# VM's only account is "admin". Both must hold.
e2e_vm_guard() {
  local vmm user
  vmm="$(/usr/sbin/sysctl -n kern.hv_vmm_present 2>/dev/null)"
  user="$(/usr/bin/id -un 2>/dev/null)"
  if [ "$vmm" != 1 ] || [ "$user" != admin ]; then
    printf '%s: refusing to run: this script is only for the throwaway sandbox VM (kern.hv_vmm_present=%s, user=%s; want 1 and admin)\n' "${0##*/}" "${vmm:-unset}" "${user:-unset}" >&2
    exit 97
  fi
}
e2e_vm_guard
# GUARD_END

# ---------------------------------------------------------------- pins
ITERM_VERSION="3.7.3"
ITERM_URL="https://iterm2.com/downloads/stable/iTerm2-3_7_3.zip"
ITERM_SHA256="eb7a166061e58602e3d4bdf69d92f2c8cf6a63feed002f6adc07128a71c8dc39"
ITERM_TEAM="H7V7XYVQ7D"

VSCODE_VERSION="1.139.1"
VSCODE_URL="https://update.code.visualstudio.com/1.139.1/darwin-arm64/stable"
VSCODE_SHA256="923080bebc194ec178c2a06b61bcb138376776406c23b8bd3e4fc3286f91cba2"
VSCODE_TEAM="UBF8T346G9"

OP_APP_VERSION="8.12.36"
OP_APP_URL="https://cache.agilebits.com/dist/1P/mac8/1Password-8.12.36-aarch64.zip"
OP_APP_SHA256="77d57273afbde862c814860623f0d1145fb85a73fb7e3202e2d1cc49a8372ce4"
OP_TEAM="2BUA8C4S2C"

OP_CLI_VERSION="2.39.0"
OP_CLI_URL="https://cache.agilebits.com/dist/1P/op2/pkg/v2.39.0/op_apple_universal_v2.39.0.pkg"
OP_CLI_SHA256="bde261468f3232484e2738e337e39c674c11a4537f4c6ed314f933eae558a405"

# Claude Code: documented at https://code.claude.com/docs/en/setup
CLAUDE_INSTALL_CMD='curl -fsSL https://claude.ai/install.sh | bash'

WORK="$(mktemp -d "${TMPDIR:-/tmp}/provision.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

log()  { printf '\n==> %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- 0. brew + login shell
log "Homebrew (login shell)"
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi
zsh -lc 'brew --version' || fail "brew not available in a login shell"
export HOMEBREW_NO_AUTO_UPDATE=1

# ---------------------------------------------------------------- helpers
# fetch URL DEST SHA256
fetch() {
  local url="$1" dest="$2" sha="$3" got
  curl -fsSL --retry 3 -o "$dest" "$url"
  got="$(shasum -a 256 "$dest" | awk '{print $1}')"
  [ "$got" = "$sha" ] || fail "sha256 mismatch for $url: expected $sha got $got"
}

# install_app_zip NAME APP_BUNDLE URL SHA TEAM
install_app_zip() {
  local name="$1" app="$2" url="$3" sha="$4" team="$5" zip="$WORK/$1.zip" ex="$WORK/$1.x"
  if [ -d "/Applications/$app" ]; then
    echo "$name: already at /Applications/$app, skipping"
    return
  fi
  fetch "$url" "$zip" "$sha"
  mkdir -p "$ex"
  ditto -x -k "$zip" "$ex"
  [ -d "$ex/$app" ] || fail "$name: $app not found in archive"
  # Verify the vendor's Developer ID signature before installing.
  codesign --verify --deep --strict "$ex/$app" || fail "$name: codesign verify failed"
  # Capture first: `cmd | grep -q` under pipefail can fail on SIGPIPE.
  local sig; sig="$(codesign -dv "$ex/$app" 2>&1)"
  case "$sig" in *"TeamIdentifier=$team"*) ;; *) fail "$name: unexpected TeamIdentifier (wanted $team)";; esac
  sudo ditto "$ex/$app" "/Applications/$app"
  echo "$name: installed to /Applications/$app"
}

# ---------------------------------------------------------------- 1. GUI apps (zip, not brew)
log "iTerm2 $ITERM_VERSION"
install_app_zip iterm2 "iTerm.app" "$ITERM_URL" "$ITERM_SHA256" "$ITERM_TEAM"

log "Visual Studio Code $VSCODE_VERSION"
install_app_zip vscode "Visual Studio Code.app" "$VSCODE_URL" "$VSCODE_SHA256" "$VSCODE_TEAM"

log "1Password $OP_APP_VERSION"
install_app_zip 1password "1Password.app" "$OP_APP_URL" "$OP_APP_SHA256" "$OP_TEAM"

# ---------------------------------------------------------------- 2. 1Password CLI (pkg, not brew)
log "1Password CLI (op) $OP_CLI_VERSION"
if [ -x /usr/local/bin/op ] && [ "$(/usr/local/bin/op --version 2>/dev/null)" = "$OP_CLI_VERSION" ]; then
  echo "op: already $OP_CLI_VERSION at /usr/local/bin/op, skipping"
else
  fetch "$OP_CLI_URL" "$WORK/op.pkg" "$OP_CLI_SHA256"
  pkgsig="$(pkgutil --check-signature "$WORK/op.pkg")"
  case "$pkgsig" in *"($OP_TEAM)"*) ;; *) fail "op.pkg: unexpected signer (wanted team $OP_TEAM)";; esac
  sudo installer -pkg "$WORK/op.pkg" -target /
fi
# A non-login ssh shell has a minimal PATH; make sure /usr/local/bin is on it.
case ":$PATH:" in *":/usr/local/bin:"*) ;; *) export PATH="/usr/local/bin:$PATH";; esac
[ "$(op --version)" = "$OP_CLI_VERSION" ] || fail "op --version is not $OP_CLI_VERSION"
echo "op: $(command -v op) $(op --version)"

# ---------------------------------------------------------------- 3. Claude Code (native installer)
log "Claude Code (native installer)"
export PATH="$HOME/.local/bin:$PATH"
if command -v claude >/dev/null 2>&1; then
  echo "claude: already installed at $(command -v claude), skipping installer"
else
  bash -c "$CLAUDE_INSTALL_CMD"
fi
claude --version || fail "claude --version failed"

# ---------------------------------------------------------------- 4. no Nerd Font
log "Nerd Font absence"
# shellcheck disable=SC2010
if ls ~/Library/Fonts /Library/Fonts 2>/dev/null | grep -i nerd; then
  fail "a Nerd Font is present"
fi
echo "no Nerd Font found (expected)"

# ---------------------------------------------------------------- 5. quarantine / Gatekeeper prompts
log "Quarantine attributes (curl downloads should have none)"
for app in "iTerm.app" "Visual Studio Code.app" "1Password.app"; do
  if xattr -p com.apple.quarantine "/Applications/$app" >/dev/null 2>&1; then
    fail "$app carries com.apple.quarantine; a GUI prompt would appear on launch"
  fi
  echo "$app: no quarantine attribute"
done

# ---------------------------------------------------------------- 6. not managed by brew
log "Homebrew must NOT manage the four apps"
casks="$(zsh -lc 'brew list --cask' 2>/dev/null || true)"
formulae="$(zsh -lc 'brew list --formula' 2>/dev/null || true)"
for c in iterm2 visual-studio-code 1password 1password-cli claude-code claude-code@latest; do
  if grep -qx "$c" <<<"$casks"; then fail "brew cask $c is installed"; fi
done
if grep -qx "1password-cli" <<<"$formulae"; then fail "brew formula 1password-cli is installed"; fi
echo "none of iterm2, visual-studio-code, 1password, 1password-cli, claude-code are brew-managed"

# ---------------------------------------------------------------- 7. shell state sanity
log "Default shell / dotfile state"
echo "SHELL=$SHELL"
[ "$(basename "$SHELL")" = "zsh" ] || fail "default shell is not zsh"
[ ! -d "$HOME/.oh-my-zsh" ] || fail "oh-my-zsh present"
[ ! -d "$HOME/.local/share/chezmoi" ] || fail "chezmoi source dir present"
command -v chezmoi >/dev/null 2>&1 && echo "NOTE: chezmoi binary is on PATH ($(command -v chezmoi))" || true

# ---------------------------------------------------------------- summary
log "SUMMARY"
in_brew() { if grep -qx "$1" <<<"$casks"; then echo yes; else echo no; fi; }
plist_ver() { /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "/Applications/$1/Contents/Info.plist"; }
printf '%-14s %-44s %-9s %s\n' APP PATH VERSION "IN 'brew list --cask'"
printf '%-14s %-44s %-9s %s\n' iTerm2   "/Applications/iTerm.app"             "$(plist_ver iTerm.app)"              "$(in_brew iterm2)"
printf '%-14s %-44s %-9s %s\n' VSCode   "/Applications/Visual Studio Code.app" "$(plist_ver 'Visual Studio Code.app')" "$(in_brew visual-studio-code)"
printf '%-14s %-44s %-9s %s\n' 1Password "/Applications/1Password.app"         "$(plist_ver 1Password.app)"          "$(in_brew 1password)"
printf '%-14s %-44s %-9s %s\n' op       "$(command -v op)"                     "$(op --version)"                     "$(in_brew 1password-cli)"
echo "claude path:    $(command -v claude) -> $(readlink "$(command -v claude)" || true)"
echo "claude version: $(claude --version)"
echo "op --version:   $(op --version)"
echo "brew:           $(zsh -lc 'brew --version' | head -1)"
echo "macOS:          $(sw_vers -productName) $(sw_vers -productVersion) ($(sw_vers -buildVersion)) $(uname -m)"
echo
echo "provision-preinstalled: OK"
