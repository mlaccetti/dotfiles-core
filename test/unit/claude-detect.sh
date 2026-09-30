#!/usr/bin/env bash
# Unit test for bin/lib/cask-detect.sh: Claude Code detection.
#
# A Claude Code installed by the native installer lives in ~/.local/bin (or the
# older ~/.claude/local) and the installer only SUGGESTS putting that on PATH.
# claude_present must see it either way, so the bootstrap never installs a
# second copy. claude_on_path must stay PATH-only.
#
# Runs in a scratch HOME. Touches nothing else.
# shellcheck disable=SC2088
# (SC2088: the "~/" in test names is display text, not a path.)
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$HERE/../../bin/lib/cask-detect.sh"
FAILS=0
ok() { printf 'ok   %s\n' "$1"; }
no() { printf 'FAIL %s\n' "$1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/claude-detect.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export HOME_DIR="$TMP/home"
mkdir -p "$HOME_DIR/.local/bin" "$HOME_DIR/.claude/local" "$TMP/onpath"
# A PATH with the basics but no claude.
export PATH="/usr/bin:/bin"
# shellcheck source=../../bin/lib/cask-detect.sh
. "$LIB"

expect_absent() { # NAME FUNC
  if out="$("$2")"; then no "$1: expected not found, got '$out'"; else ok "$1"; fi
}
expect_found() { # NAME FUNC WANTED_PATH
  if out="$("$2")" && [ "$out" = "$3" ]; then ok "$1"; else no "$1: expected '$3', got '$out'"; fi
}

expect_absent "nothing installed: claude_present is empty" claude_present
expect_absent "nothing installed: claude_native_install is empty" claude_native_install

# Native installer location, NOT on PATH.
printf '#!/bin/sh\necho 0.0.0\n' >"$HOME_DIR/.local/bin/claude"
expect_absent "not executable: does not count" claude_present
chmod +x "$HOME_DIR/.local/bin/claude"
expect_found "~/.local/bin/claude off PATH is present" claude_present "$HOME_DIR/.local/bin/claude"
expect_found "claude_native_install finds ~/.local/bin/claude" claude_native_install "$HOME_DIR/.local/bin/claude"
expect_absent "claude_on_path stays PATH-only (off PATH)" claude_on_path

# Older "local" install location.
rm -f "$HOME_DIR/.local/bin/claude"
printf '#!/bin/sh\necho 0.0.0\n' >"$HOME_DIR/.claude/local/claude"
chmod +x "$HOME_DIR/.claude/local/claude"
expect_found "~/.claude/local/claude off PATH is present" claude_present "$HOME_DIR/.claude/local/claude"

# A directory named claude is not an install.
rm -f "$HOME_DIR/.claude/local/claude"
mkdir -p "$HOME_DIR/.local/bin/claude"
expect_absent "a directory named claude does not count" claude_present
rmdir "$HOME_DIR/.local/bin/claude"

# On PATH (any install method) still wins and is reported as such.
printf '#!/bin/sh\necho 0.0.0\n' >"$TMP/onpath/claude"
chmod +x "$TMP/onpath/claude"
PATH="$TMP/onpath:$PATH"
expect_found "claude on PATH is present" claude_present "$TMP/onpath/claude"
expect_found "claude_on_path finds it" claude_on_path "$TMP/onpath/claude"

if [ "$FAILS" -eq 0 ]; then echo "claude-detect: OK"; exit 0; fi
echo "claude-detect: $FAILS failure(s)"
exit 1
