#!/usr/bin/env bash
# prepare-run.sh
#
# Runs INSIDE a fresh clone (sandbox-preinstalled or sandbox-base), before the guide
# starts. E2E_SCENARIO says which: "preinstalled" (default) or "fresh".
# provision-preinstalled.sh put the preinstalled VM in its starting state (apps already
# installed); the fresh VM is the untouched Cirrus image (Homebrew, no apps). This
# script makes the run faithful rather than easy: it removes everything the Cirrus CI
# image ships that would hide a missing-dependency bug, and gives the shell exactly
# the startup files a typical Mac has.
#
#   1. brew update (Phoenix runs current Homebrew; the image's is old)
#   2. uninstall the image's CI tooling (jq, gh, mise, node, ...), so that every
#      tool used after setup was provided BY the setup
#   3. ~/.zprofile = the Homebrew installer's line. preinstalled only: ~/.zshrc =
#      the native Claude installer's PATH line. fresh: no ~/.zshrc at all.
#
# Not idempotent by design: it runs once per throwaway clone.
# No credentials are used.
# shellcheck disable=SC2016
# (SC2016: the quoted lines written to ~/.zprofile and ~/.zshrc must stay literal.)
set -uo pipefail

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

log()  { printf '\n==> %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
removed() { printf 'REMOVED\t%s\t%s\n' "$1" "$2"; }

SCENARIO="${E2E_SCENARIO:-preinstalled}"
case "$SCENARIO" in preinstalled | fresh) ;; *) fail "unknown E2E_SCENARIO '$SCENARIO'" ;; esac
echo "scenario: $SCENARIO"

BREW=/opt/homebrew/bin/brew
[ -x "$BREW" ] || fail "no Homebrew at $BREW"
eval "$("$BREW" shellenv)"

# The image's ~/.zprofile exports HOMEBREW_NO_AUTO_UPDATE=1 and friends. A typical
# Mac does not, so make sure this process does not inherit them either.
unset HOMEBREW_NO_AUTO_UPDATE HOMEBREW_NO_INSTALL_CLEANUP

# ---------------------------------------------------------------- 1. brew update
log "brew update"
before="$("$BREW" --version | head -1)"
"$BREW" update 2>&1 | tail -5
after="$("$BREW" --version | head -1)"
echo "HOMEBREW_BEFORE=${before}"
echo "HOMEBREW_AFTER=${after}"

# ---------------------------------------------------------------- 2. remove image CI tooling
log "Removing image CI tooling that would mask missing-dependency bugs"

# reason per formula. Everything here is either installed by the setup's
# Brewfile, called by a run_once_/run_onchange_ script or by doctor.sh, or is a
# Node/Ruby runtime the setup is supposed to provide through mise.
remove_formula() {
  local f="$1" why="$2"
  if "$BREW" list --formula "$f" >/dev/null 2>&1; then
    if "$BREW" uninstall --formula --ignore-dependencies --force "$f" >/dev/null 2>&1; then
      removed "brew formula $f" "$why"
    else
      fail "could not uninstall formula $f"
    fi
  fi
}
remove_formula jq            "Brewfile formula; run_once_before_02, run_once_after_10/30 and doctor.sh call it"
remove_formula gh            "Brewfile formula; doctor.sh and Step 8d use it"
remove_formula yq            "same job as jq; hides a missing jq/yq dependency"
remove_formula mise          "Brewfile formula; run_onchange_after_25 installs Node through it"
remove_formula node          "must come from mise (Step 3), not the image"
remove_formula node@24       "must come from mise (Step 3), not the image"
remove_formula rbenv         "image Ruby version manager, competes with mise"
remove_formula ruby-build    "rbenv plugin"
remove_formula awscli        "image CI tool; oh-my-zsh aws plugin would find it"
remove_formula git-lfs       "image CI tool; oh-my-zsh git-lfs plugin would find it"
remove_formula chezmoi       "Brewfile formula; Step 2 must be what installs it"
remove_formula fzf           "Brewfile formula"
remove_formula bat           "Brewfile formula"
remove_formula ripgrep       "Brewfile formula"
remove_formula zsh-autosuggestions       "Brewfile formula"
remove_formula zsh-syntax-highlighting   "Brewfile formula"
remove_formula wget          "image CI tool"
remove_formula gitlab-runner "image CI agent"
remove_formula 'buildkite-agent@3' "image CI agent"
remove_formula otel-cli      "image CI tool"
remove_formula tart-guest-agent "image CI agent"
remove_formula cmake         "image build tool"
remove_formula gcc           "image build tool"

# git-credential-manager rewrites ~/.gitconfig with a credential helper.
if "$BREW" list --cask git-credential-manager >/dev/null 2>&1; then
  if "$BREW" uninstall --cask --force git-credential-manager >/dev/null 2>&1; then
    removed "brew cask git-credential-manager" "image tool; wrote credential helpers into ~/.gitconfig"
  else
    fail "could not uninstall cask git-credential-manager"
  fi
fi

# Third-party taps the image added (buildkite, otel-cli, openai). A typical Mac has none,
# and Homebrew 7 prints a tap-trust warning on every command while they exist.
for tap in $("$BREW" tap 2>/dev/null); do
  if "$BREW" untap --force "$tap" >/dev/null 2>&1; then removed "brew tap $tap" "image CI tap; Homebrew 7 warns about untrusted taps on every command"; fi
done

# Non-brew copies. preinstalled: /usr/local/bin/op is the vendor-installed 1Password CLI
# the scenario starts with, so keep it. fresh: there must be no op at all.
for f in /usr/local/bin/*; do
  [ -e "$f" ] || continue
  case "$(basename "$f")" in
    op) if [ "$SCENARIO" = fresh ]; then sudo rm -f "$f" && removed "$f" "fresh Mac has no 1Password CLI"; fi ;;
    git-credential-manager | git-credential-manager-core)
      sudo rm -f "$f" && removed "$f" "leftover from the removed cask" ;;
    jq | gh | yq | mise | node | npm | npx | rbenv | aws | git-lfs | chezmoi | fzf | bat | rg)
      sudo rm -f "$f" && removed "$f" "non-brew copy of a tool the setup provides" ;;
    *) echo "KEPT	$f	unrecognised, left alone" ;;
  esac
done
for d in "$HOME/.rbenv" "$HOME/.local/share/mise" "$HOME/.config/mise" "$HOME/Library/pnpm" "$HOME/.nvm"; do
  if [ -e "$d" ]; then rm -rf "$d" && removed "$d" "image runtime manager state"; fi
done
for f in "$HOME/.local/bin"/*; do
  [ -e "$f" ] || continue
  case "$(basename "$f")" in
    claude) if [ "$SCENARIO" = fresh ]; then rm -f "$f" && removed "$f" "fresh Mac has no Claude Code"; fi ;;
    *) rm -f "$f" && removed "$f" "not part of a typical Mac" ;;
  esac
done
if [ -f "$HOME/.profile" ]; then rm -f "$HOME/.profile" && removed "$HOME/.profile" "image PATH additions (node@24, pnpm)"; fi

# The image's ~/.gitconfig has credential-manager and LFS filter sections and no
# identity. There is no identity from the setup yet, so start from an empty file
# (the git-identity script must be the thing that sets it).
: >"$HOME/.gitconfig"
removed "$HOME/.gitconfig contents" "credential-manager/LFS sections from the removed tools"

# ---------------------------------------------------------------- 3. shell startup files
log "Shell startup files"
# Exactly what the Homebrew installer tells you to add to ~/.zprofile.
printf '%s\n' 'eval "$(/opt/homebrew/bin/brew shellenv)"' >"$HOME/.zprofile"
echo "--- ~/.zprofile"; cat "$HOME/.zprofile"
if [ "$SCENARIO" = preinstalled ]; then
  # Exactly what the Claude Code native installer tells you to add.
  printf '%s\n' 'export PATH="$HOME/.local/bin:$PATH"' >"$HOME/.zshrc"
  echo "--- ~/.zshrc"; cat "$HOME/.zshrc"
else
  # A Mac with only Homebrew has no ~/.zshrc until the setup writes one.
  if [ -e "$HOME/.zshrc" ]; then rm -f "$HOME/.zshrc" && removed "$HOME/.zshrc" "fresh Mac has no ~/.zshrc"; fi
  echo "--- ~/.zshrc: absent"
fi

# ---------------------------------------------------------------- verify
log "Verify the starting state"
errs=0
say() { printf '%s\n' "$*"; }

# Tools the setup must provide. In a login interactive zsh none may resolve.
for t in jq gh yq mise node npm npx rbenv aws git-lfs chezmoi fzf bat rg; do
  where="$(zsh -lic "command -v $t" </dev/null 2>/dev/null | tail -1)"
  # macOS itself ships /usr/bin/jq (since macOS 15), so that one is legitimate.
  if [ "$t" = jq ] && [ "$where" = /usr/bin/jq ]; then
    say "note: jq resolves to /usr/bin/jq, which macOS itself provides (every Mac has it)"
    continue
  fi
  if [ -n "$where" ]; then
    say "FAIL: '$t' still resolves to $where"
    errs=$((errs + 1))
  fi
done
[ "$errs" -eq 0 ] && say "none of the tools the setup provides resolve before the run"

resolved="$(zsh -lic 'command -v claude brew' </dev/null 2>/dev/null)"
say "zsh -lic 'command -v claude brew':"
say "$resolved"
case "$resolved" in */opt/homebrew/bin/brew*) ;; *) say "FAIL: brew does not resolve"; errs=$((errs + 1)) ;; esac
if [ "$SCENARIO" = preinstalled ]; then
  case "$resolved" in *"$HOME/.local/bin/claude"*) ;; *) say "FAIL: claude does not resolve"; errs=$((errs + 1)) ;; esac
else
  # fresh: nothing the setup is meant to install may exist yet.
  for t in claude op code; do
    where="$(zsh -lic "command -v $t" </dev/null 2>/dev/null | tail -1)"
    if [ -n "$where" ]; then say "FAIL: '$t' already resolves to $where"; errs=$((errs + 1)); fi
  done
  for app in "iTerm.app" "Visual Studio Code.app" "1Password.app" "Claude.app"; do
    if [ -e "/Applications/$app" ]; then say "FAIL: /Applications/$app already exists"; errs=$((errs + 1)); fi
  done
  # shellcheck disable=SC2010
  if ls "$HOME/Library/Fonts" /Library/Fonts 2>/dev/null | grep -qi nerd; then say "FAIL: a Nerd Font is already installed"; errs=$((errs + 1)); fi
  for c in iterm2 visual-studio-code 1password 1password-cli claude-code 'claude-code@latest' claude font-fira-code-nerd-font; do
    if "$BREW" list --cask "$c" >/dev/null 2>&1; then say "FAIL: cask $c is already installed"; errs=$((errs + 1)); fi
  done
  [ "$errs" -eq 0 ] && say "fresh: no iTerm2, VS Code, 1Password, op, Claude Code, Claude desktop or Nerd Font present"
fi

if pgrep -x iTerm2 >/dev/null 2>&1; then say "FAIL: iTerm2 is running"; errs=$((errs + 1)); fi
if [ -n "$(git config --global --get user.name 2>/dev/null)" ]; then say "FAIL: git identity already set"; errs=$((errs + 1)); fi

[ "$errs" -eq 0 ] || fail "$errs faithfulness check(s) failed"
echo
echo "prepare-run: OK"
