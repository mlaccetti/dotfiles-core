#!/usr/bin/env bash
# Unit test for bin/doctor.sh "Fix:" lines.
#
# On a Mac that already has iTerm2, 1Password and Claude Code, a Fix line that
# says to run `brew bundle --file=<whole Brewfile>` re-triggers "It seems
# there is already an App at ..." errors. Fix lines must name only what is
# missing: `brew install <formulae>` and `brew install --cask <casks>`.
#
# Runs doctor.sh in a scratch HOME against a fake `brew` that says nothing is
# installed. Touches nothing else.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
FAILS=0
ok() { printf 'ok   %s\n' "$1"; }
no() { printf 'FAIL %s\n' "$1"; FAILS=$((FAILS + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/doctor-fix.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/home" "$TMP/bin"

# Fake brew: a Brewfile of jq + ripgrep (formulae) and a font + Claude Code
# (casks), none of them installed, and no cask metadata.
cat >"$TMP/bin/brew" <<'BREW'
#!/bin/bash
case "$1" in
  bundle)
    kind=""
    for a in "$@"; do
      case "$a" in --formula) kind=formula ;; --cask) kind=cask ;; esac
    done
    if [ "$kind" = formula ]; then printf 'jq\nripgrep\n'; else printf 'font-fira-code-nerd-font\nclaude-code@latest\n'; fi
    ;;
  list | info) exit 1 ;;
  *) exit 0 ;;
esac
BREW
chmod +x "$TMP/bin/brew"

run_doctor() {
  HOME="$TMP/home" CHEZMOI_SOURCE_DIR="$REPO" DOCTOR_ZSH_TIMEOUT=5 \
    PATH="$TMP/bin:/usr/bin:/bin:/usr/sbin:/sbin" bash "$REPO/bin/doctor.sh" 2>&1
}

OUT="$(run_doctor)"

want() { # NAME REGEX
  if grep -Eq -- "$2" <<<"$OUT"; then ok "$1"; else no "$1 (wanted /$2/)"; fi
}
refuse() { # NAME REGEX
  if grep -Eq -- "$2" <<<"$OUT"; then no "$1 (found /$2/)"; else ok "$1"; fi
}

want   "missing Brewfile items get targeted install commands" \
  'Fix:.*Run: brew install jq ripgrep, then run: brew install --cask font-fira-code-nerd-font claude-code@latest'
want   "missing rg is fixed with the ripgrep formula" "Fix:.*Run: brew install ripgrep"
want   "missing op is fixed with the 1password-cli cask" "Fix:.*Run: brew install --cask 1password-cli"
want   "missing bat is fixed with brew install bat" "Fix:.*Run: brew install bat"
want   "missing claude is fixed with the claude-code@latest cask" "Fix:.*Run: brew install --cask claude-code@latest$"
refuse "no Fix line says to brew bundle the whole Brewfile" 'Fix:.*brew bundle'
refuse "no Fix line mentions brew bundle at all" 'brew bundle --file'

# A Claude Code in the native install location that is not on PATH: say so,
# and do not suggest installing a second copy.
mkdir -p "$TMP/home/.local/bin"
printf '#!/bin/sh\necho 0.0.0\n' >"$TMP/home/.local/bin/claude"
chmod +x "$TMP/home/.local/bin/claude"
OUT="$(run_doctor)"
want   "claude off PATH: reported as installed but not on PATH" "'claude' is installed at .*/.local/bin/claude but its folder is not on your PATH"
refuse "claude off PATH: no second-install suggestion" 'Run: brew install --cask claude-code@latest'
refuse "claude off PATH: Claude Code is not listed as missing from the Brewfile" 'core Brewfile is missing:.*claude-code'

if [ "$FAILS" -eq 0 ]; then echo "doctor-fix-lines: OK"; exit 0; fi
echo "doctor-fix-lines: $FAILS failure(s)"
exit 1
