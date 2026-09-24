#!/bin/bash
# Anti-fork-drift guard: if ~/.oh-my-zsh has been replaced by a fork at
# some point (e.g. by a plugin manager, or a manual "fix"), this repo's
# .chezmoiexternal.toml expects to manage the REAL ohmyzsh/ohmyzsh repo
# there. Detect a mismatched origin and offer to back the fork up so
# chezmoi can re-clone vanilla oh-my-zsh in its place.
#
# This NEVER deletes anything - at most it renames the directory - and it
# always asks before doing so. Runs as a "before" script so the backup
# happens before chezmoi's own external git-repo management touches the
# directory.
set -uo pipefail

HOME_DIR="${CHEZMOI_HOME_DIR:-$HOME}"
OMZ_DIR="${HOME_DIR}/.oh-my-zsh"

echo "==> [oh-my-zsh] Checking for fork drift..."

if [ ! -d "$OMZ_DIR" ]; then
  echo "    No existing ~/.oh-my-zsh directory. Nothing to check - chezmoi"
  echo "    will clone the real ohmyzsh/ohmyzsh repo there."
  exit 0
fi

if [ ! -d "$OMZ_DIR/.git" ]; then
  echo "    ~/.oh-my-zsh exists but isn't a git repository."
  echo "    ACTION NEEDED: chezmoi manages this as a git-repo external. Move"
  echo "    ~/.oh-my-zsh aside by hand, then re-run 'chezmoi apply'."
  exit 0
fi

ORIGIN_URL="$(git -C "$OMZ_DIR" remote get-url origin 2>/dev/null || echo "")"

case "$ORIGIN_URL" in
  *ohmyzsh/ohmyzsh*)
    echo "    ~/.oh-my-zsh origin ($ORIGIN_URL) is the real upstream. All good."
    exit 0
    ;;
esac

echo "    !! ~/.oh-my-zsh's origin remote is NOT ohmyzsh/ohmyzsh:"
echo "    !!   origin = ${ORIGIN_URL:-<no origin remote configured>}"
echo "    !! This usually means it was replaced by a fork at some point."
echo ""

BACKUP_DIR="${HOME_DIR}/.oh-my-zsh.fork-backup-$(date +%Y%m%d-%H%M%S)"
REPLY=""

if [ -t 0 ] && [ -t 1 ] && [ -r /dev/tty ]; then
  read -r -p "    Move it to ${BACKUP_DIR} and let chezmoi re-clone the real oh-my-zsh? [y/N] " REPLY < /dev/tty
else
  echo "    Not running in an interactive terminal - skipping automatically"
  echo "    rather than guessing. Nothing was changed."
fi

case "$REPLY" in
  [yY]|[yY][eE][sS])
    mv "$OMZ_DIR" "$BACKUP_DIR"
    echo "    Moved. Your old ~/.oh-my-zsh is safe at: ${BACKUP_DIR}"
    echo "    chezmoi will now clone the real oh-my-zsh in its place."
    ;;
  *)
    echo "    Skipped. Nothing was deleted or moved."
    echo "    ACTION NEEDED: to fix this later, back up ~/.oh-my-zsh yourself"
    echo "    (e.g. 'mv ~/.oh-my-zsh ~/.oh-my-zsh.bak') and re-run 'chezmoi apply'"
    echo "    so the real oh-my-zsh can be cloned."
    ;;
esac

exit 0
