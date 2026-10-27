#!/usr/bin/env bash
# Unit test for dot_local/bin/executable_disk-tidy.
#
# Builds a scratch origin, a checkout and one worktree per case, then checks
# that a dry run touches nothing and --apply removes exactly the clean,
# merged-or-gone, idle worktrees while keeping every branch. Also checks the
# Playwright, log and transcript steps against a scratch HOME.
#
# Runs in a scratch HOME. Touches nothing else.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIDY="$HERE/../../dot_local/bin/executable_disk-tidy"
FAILS=0
ok() { printf 'ok   %s\n' "$1"; }
no() { printf 'FAIL %s\n' "$1"; FAILS=$((FAILS + 1)); }
present() { if [ -e "$2" ]; then ok "$1"; else no "$1: $2 is gone"; fi; }
absent() { if [ -e "$2" ]; then no "$1: $2 still there"; else ok "$1"; fi; }

TMP="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/disk-tidy.XXXXXX")" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/home/.config"
mkdir -p "$HOME"
# Isolate git from the user's config and hooks.
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$TMP/gitconfig"
git config --file "$GIT_CONFIG_GLOBAL" user.name test
git config --file "$GIT_CONFIG_GLOBAL" user.email test@example.com
git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch main
export DISK_TIDY_ROOTS="$TMP/ws" DISK_TIDY_WORKTREE_IDLE_DAYS=2

old() { # make a worktree look idle for 10 days
  touch -t "$(date -v-10d +%Y%m%d%H%M 2>/dev/null || date -d '10 days ago' +%Y%m%d%H%M)" \
    "$(git -C "$1" rev-parse --absolute-git-dir)/logs/HEAD"
}

g() { git -C "$REPO" "$@" >/dev/null 2>&1; }
git init -q --bare "$TMP/origin.git"
REPO="$TMP/ws/app"
git clone -q "$TMP/origin.git" "$REPO" 2>/dev/null
g commit --allow-empty -m init && g push -u origin main
WT="$REPO/.worktrees"

# merged: commit landed on main.
g worktree add -b merged "$WT/merged" main
git -C "$WT/merged" commit -q --allow-empty -m feature
g merge --ff-only merged && g push origin main
old "$WT/merged"

# gone: pushed, then the remote branch was deleted (squash-merge style).
g worktree add -b gone "$WT/gone" main
git -C "$WT/gone" commit -q --allow-empty -m squashed
git -C "$WT/gone" push -q -u origin gone 2>/dev/null
g push origin --delete gone
old "$WT/gone"

# dirty: merged but has an untracked file.
g worktree add -b dirty "$WT/dirty" main
touch "$WT/dirty/notes"
old "$WT/dirty"

# unpushed: has a commit that exists nowhere else.
g worktree add -b unpushed "$WT/unpushed" main
git -C "$WT/unpushed" commit -q --allow-empty -m wip
old "$WT/unpushed"

# fresh: merged-looking but just created, so an agent may be about to use it.
g worktree add -b fresh "$WT/fresh" main

# locked: merged and idle, but explicitly locked.
g worktree add -b locked "$WT/locked" main
g worktree lock "$WT/locked"
old "$WT/locked"

# Ignored build output does not make a worktree dirty.
printf 'node_modules/\n' >"$REPO/.gitignore" && g add .gitignore && g commit -m ignore && g push origin main
mkdir -p "$WT/merged/node_modules/pkg"

"$TIDY" --only worktrees >/dev/null
present "dry run keeps merged" "$WT/merged"
present "dry run keeps gone" "$WT/gone"

"$TIDY" --only worktrees --apply >/dev/null
absent "removes clean merged worktree" "$WT/merged"
absent "removes clean worktree whose branch was deleted upstream" "$WT/gone"
present "keeps worktree with untracked files" "$WT/dirty"
present "keeps worktree with unpushed commits" "$WT/unpushed"
present "keeps recently created worktree" "$WT/fresh"
present "keeps locked worktree" "$WT/locked"
for b in merged gone; do
  if git -C "$REPO" rev-parse -q --verify "refs/heads/$b" >/dev/null; then ok "keeps branch $b"; else no "branch $b deleted"; fi
done

# Playwright: newest build of each browser stays.
PW="$HOME/.cache/ms-playwright"
mkdir -p "$PW/chromium-1200" "$PW/chromium-1248" "$PW/chromium_headless_shell-1248" "$PW/webkit-2359" "$PW/mcp-chrome"
"$TIDY" --only playwright --apply >/dev/null
absent "removes older chromium build" "$PW/chromium-1200"
present "keeps newest chromium build" "$PW/chromium-1248"
present "keeps the only headless shell build" "$PW/chromium_headless_shell-1248"
present "keeps non-browser folders" "$PW/mcp-chrome"

# Logs: only files over the limit are truncated, and they are kept.
mkdir -p "$HOME/Library/Logs/App"
dd if=/dev/zero of="$HOME/Library/Logs/App/big.log" bs=1048576 count=3 2>/dev/null
printf 'small\n' >"$HOME/Library/Logs/App/small.log"
DISK_TIDY_LOG_MAX_MB=2 "$TIDY" --only logs --apply >/dev/null
if [ -f "$HOME/Library/Logs/App/big.log" ] && [ ! -s "$HOME/Library/Logs/App/big.log" ]; then ok "truncates oversized log"; else no "oversized log not truncated"; fi
if [ -s "$HOME/Library/Logs/App/small.log" ]; then ok "leaves small log alone"; else no "small log changed"; fi

# Transcripts: old Codex rollouts and fully old Cursor chats go.
mkdir -p "$HOME/.codex/sessions/2026/01/01" "$HOME/.cursor/chats/p/oldchat" "$HOME/.cursor/chats/p/newchat"
touch -t 202601010000 "$HOME/.codex/sessions/2026/01/01/rollout-a.jsonl" "$HOME/.cursor/chats/p/oldchat/store.db" "$HOME/.cursor/chats/p/newchat/meta.json"
touch "$HOME/.codex/sessions/2026/01/01/rollout-new.jsonl" "$HOME/.cursor/chats/p/newchat/store.db"
"$TIDY" --only transcripts --apply >/dev/null
absent "removes old Codex transcript" "$HOME/.codex/sessions/2026/01/01/rollout-a.jsonl"
present "keeps recent Codex transcript" "$HOME/.codex/sessions/2026/01/01/rollout-new.jsonl"
absent "removes Cursor chat with nothing recent" "$HOME/.cursor/chats/p/oldchat"
present "keeps Cursor chat with recent activity" "$HOME/.cursor/chats/p/newchat/meta.json"

if "$TIDY" --only nope >/dev/null 2>&1; then no "unknown step should fail"; else ok "rejects unknown step"; fi

[ "$FAILS" -eq 0 ] && { echo "all passed"; exit 0; }
echo "$FAILS failed"; exit 1
