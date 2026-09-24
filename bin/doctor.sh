#!/bin/bash
# doctor.sh - verifies a dotfiles-core setup is healthy.
#
# Run it from a clone of this repo, or via `chezmoi source-path` to find
# the repo, e.g.:
#   "$(chezmoi source-path)/bin/doctor.sh"
#
# Every check prints PASS, WARN, or FAIL in plain English, with a specific
# next step when something's wrong. No stack traces. Exits non-zero if any
# check FAILs (WARN does not affect the exit code).
#
# shellcheck disable=SC2088
# (Several PASS/FAIL messages below use a literal "~/..." for readability
# in human-facing output - these are display strings, not paths being
# expanded, so the tilde is intentionally not expanded.)
set -uo pipefail

# ---- output helpers --------------------------------------------------------
if [ -t 1 ]; then
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_BOLD=$'\033[1m'; C_RESET=$'\033[0m'
else
  C_RED=""; C_GREEN=""; C_YELLOW=""; C_BOLD=""; C_RESET=""
fi

FAILURES=0
WARNINGS=0

pass() { printf "  %s[PASS]%s %s\n" "$C_GREEN" "$C_RESET" "$1"; }
warn() { printf "  %s[WARN]%s %s\n" "$C_YELLOW" "$C_RESET" "$1"; WARNINGS=$((WARNINGS + 1)); }
fail() {
  printf "  %s[FAIL]%s %s\n" "$C_RED" "$C_RESET" "$1"
  if [ -n "${2:-}" ]; then
    printf "         %sFix:%s %s\n" "$C_BOLD" "$C_RESET" "$2"
  fi
  FAILURES=$((FAILURES + 1))
}
section() { printf "\n%s%s%s\n" "$C_BOLD" "$1" "$C_RESET"; }

HOME_DIR="${HOME}"
SOURCE_DIR="${CHEZMOI_SOURCE_DIR:-}"
if [ -z "$SOURCE_DIR" ] && command -v chezmoi >/dev/null 2>&1; then
  SOURCE_DIR="$(chezmoi source-path 2>/dev/null || true)"
fi
if [ -z "$SOURCE_DIR" ]; then
  # Fall back to "this script lives in <source>/bin/doctor.sh".
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
  SOURCE_DIR="$(dirname "$SCRIPT_DIR")"
fi

# =============================================================================
section "Homebrew"
# =============================================================================
if command -v brew >/dev/null 2>&1; then
  pass "Homebrew is installed ($(command -v brew))."

  BREWFILE="${SOURCE_DIR}/Brewfile"
  if [ -f "$BREWFILE" ]; then
    if brew bundle check --file="$BREWFILE" --no-upgrade >/dev/null 2>&1; then
      pass "All core Brewfile packages are installed."
    else
      fail "Some core Brewfile packages are missing." \
        "Run: brew bundle --file=\"$BREWFILE\""
    fi
  else
    warn "Could not find Brewfile at ${BREWFILE} to check against."
  fi
else
  fail "Homebrew is not installed." \
    "Run: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
fi

# =============================================================================
section "chezmoi"
# =============================================================================
if command -v chezmoi >/dev/null 2>&1; then
  pass "chezmoi is installed ($(command -v chezmoi))."
  ACTUAL_SOURCE="$(chezmoi source-path 2>/dev/null || true)"
  if [ -n "$ACTUAL_SOURCE" ]; then
    pass "chezmoi source directory: ${ACTUAL_SOURCE}"
  else
    warn "Could not determine chezmoi's source directory (is it initialized?)."
  fi
else
  fail "chezmoi is not installed." "Run: brew install chezmoi"
fi

# =============================================================================
section "oh-my-zsh (anti-fork-drift guard)"
# =============================================================================
OMZ_DIR="${HOME_DIR}/.oh-my-zsh"
if [ -d "$OMZ_DIR" ]; then
  pass "~/.oh-my-zsh is present."
  if [ -d "$OMZ_DIR/.git" ]; then
    ORIGIN_URL="$(git -C "$OMZ_DIR" remote get-url origin 2>/dev/null || echo "")"
    case "$ORIGIN_URL" in
      *ohmyzsh/ohmyzsh*)
        pass "~/.oh-my-zsh's origin is the real ohmyzsh/ohmyzsh (no fork drift)."
        ;;
      *)
        fail "~/.oh-my-zsh's origin is NOT ohmyzsh/ohmyzsh (origin: ${ORIGIN_URL:-<none>})." \
          "Re-run 'chezmoi apply' and answer 'y' to the fork-backup prompt, or run: mv ~/.oh-my-zsh ~/.oh-my-zsh.bak && chezmoi apply"
        ;;
    esac
  else
    fail "~/.oh-my-zsh exists but is not a git repository." \
      "Move it aside (mv ~/.oh-my-zsh ~/.oh-my-zsh.bak) and run: chezmoi apply"
  fi
else
  fail "~/.oh-my-zsh is missing." "Run: chezmoi apply"
fi

# =============================================================================
section "Theme files"
# =============================================================================
if [ -n "${ZSH_CUSTOM:-}" ] && [ "$ZSH_CUSTOM" = "${HOME_DIR}/.oh-my-zsh-custom" ]; then
  pass "\$ZSH_CUSTOM is correctly set to ${ZSH_CUSTOM}."
elif [ -d "${HOME_DIR}/.oh-my-zsh-custom" ]; then
  warn "\$ZSH_CUSTOM is not set in this shell, but ~/.oh-my-zsh-custom exists. Open a new terminal tab and re-run this check."
else
  fail "Neither \$ZSH_CUSTOM nor ~/.oh-my-zsh-custom is set up." "Run: chezmoi apply"
fi

for f in prompt.zsh theme-colors.zsh; do
  if [ -f "${HOME_DIR}/.oh-my-zsh-custom/${f}" ]; then
    pass "${f} is present in \$ZSH_CUSTOM."
  else
    fail "${f} is missing from ~/.oh-my-zsh-custom." "Run: chezmoi apply"
  fi
done

# =============================================================================
section "Fonts"
# =============================================================================
FONT_FOUND=0
if command -v fc-list >/dev/null 2>&1; then
  if fc-list 2>/dev/null | grep -qi "FiraCode Nerd Font"; then
    FONT_FOUND=1
  fi
elif [ -d "${HOME_DIR}/Library/Fonts" ]; then
  if find "${HOME_DIR}/Library/Fonts" /Library/Fonts -iname "*FiraCode*Nerd*" 2>/dev/null | grep -q .; then
    FONT_FOUND=1
  fi
fi

if [ "$FONT_FOUND" -eq 1 ]; then
  pass "FiraCode Nerd Font files are installed."
else
  fail "FiraCode Nerd Font does not appear to be installed." \
    "Run: brew install --cask font-fira-code-nerd-font"
fi

# The iTerm2 profile pins a specific PostScript name. If that exact face
# doesn't resolve, iTerm2 silently falls back to a system default and the
# glyphs below will render as tofu boxes even though "a" Nerd Font is
# installed.
PS_NAME="FiraCodeNFM-Reg"
PS_FOUND=0
if command -v system_profiler >/dev/null 2>&1; then
  if system_profiler SPFontsDataType 2>/dev/null | grep -qi "$PS_NAME"; then
    PS_FOUND=1
  fi
fi
if [ "$PS_FOUND" -eq 1 ]; then
  pass "The exact font iTerm2's profile references (${PS_NAME}) resolves."
else
  warn "Could not confirm the PostScript name '${PS_NAME}' resolves on this system." \
    "If glyphs below look wrong, open Font Book, search 'Fira Code', and confirm a 'FiraCodeNFM-Reg' style is installed and enabled."
fi

# =============================================================================
section "Glyph rendering test (look at this line yourself)"
# =============================================================================
# Raw \xHH UTF-8 byte sequences are used (instead of literal glyphs in this
# source file, or bash 4+'s $'\uXXXX') so this renders correctly even under
# macOS's stock /bin/bash (3.2).
printf "    Powerline separators: \xee\x82\xb0 \xee\x82\xb2 \xee\x82\xb1 \xee\x82\xb3\n"
printf "    Nerd Font icons:      \xef\x84\x93 \xef\x81\xbb \xef\x80\x85 \xef\x84\xa1\n"
printf "    Emoji:                \xf0\x9f\x9a\x80 \xe2\x9c\x85 \xf0\x9f\x8e\xa8 \xf0\x9f\x94\xa5\n"
echo ""
echo "    ^ CONFIRM VISUALLY: if any of the shapes above show as a"
echo "      hollow/empty box (\"tofu\"), the terminal is not using a Nerd"
echo "      Font. Fix: in iTerm2, Settings > Profiles > Anthropic > Text,"
echo "      set the font to 'FiraCode Nerd Font Mono' and try again."

# =============================================================================
section "iTerm2 Dynamic Profile"
# =============================================================================
PROFILE_PATH="${HOME_DIR}/Library/Application Support/iTerm2/DynamicProfiles/Anthropic.json"
if [ -f "$PROFILE_PATH" ]; then
  if command -v jq >/dev/null 2>&1 && jq empty "$PROFILE_PATH" >/dev/null 2>&1; then
    pass "iTerm2 Dynamic Profile is installed and is valid JSON."
  elif command -v jq >/dev/null 2>&1; then
    fail "iTerm2 Dynamic Profile exists but is not valid JSON." \
      "Re-copy it: cp \"${SOURCE_DIR}/iterm2/Anthropic.json\" \"${PROFILE_PATH}\""
  else
    warn "iTerm2 Dynamic Profile is installed, but jq isn't available to validate its JSON."
  fi
else
  fail "iTerm2 Dynamic Profile is not installed." \
    "Run: mkdir -p \"${HOME_DIR}/Library/Application Support/iTerm2/DynamicProfiles\" && cp \"${SOURCE_DIR}/iterm2/Anthropic.json\" \"${PROFILE_PATH}\""
fi

# =============================================================================
section "Claude Code theme"
# =============================================================================
CLAUDE_THEME_FILE="${HOME_DIR}/.claude/themes/anthropic.json"
CLAUDE_SETTINGS="${HOME_DIR}/.claude/settings.json"
if [ -f "$CLAUDE_THEME_FILE" ]; then
  pass "Claude Code theme file is present."
else
  fail "Claude Code theme file is missing." "Run: chezmoi apply"
fi

if [ -f "$CLAUDE_SETTINGS" ] && command -v jq >/dev/null 2>&1; then
  THEME_VALUE="$(jq -r '.theme // empty' "$CLAUDE_SETTINGS" 2>/dev/null || true)"
  if [ "$THEME_VALUE" = "custom:anthropic" ]; then
    pass "settings.json references the Anthropic theme."
  else
    fail "settings.json does not reference the Anthropic theme (found: '${THEME_VALUE:-<unset>}')." \
      "Run: jq '.theme = \"custom:anthropic\"' \"$CLAUDE_SETTINGS\" > /tmp/settings.json && mv /tmp/settings.json \"$CLAUDE_SETTINGS\""
  fi
elif [ ! -f "$CLAUDE_SETTINGS" ]; then
  fail "~/.claude/settings.json does not exist." "Run: chezmoi apply (this creates a minimal one)"
else
  warn "jq isn't available to check settings.json's theme key."
fi

# =============================================================================
section "bat / zsh-syntax-highlighting"
# =============================================================================
# BAT_THEME and ZSH_HIGHLIGHT_HIGHLIGHTERS are zsh-side state (the latter is
# a zsh array that isn't exported), so they may not be visible to this
# bash script's own environment even when correctly configured. Ask a
# fresh interactive zsh - the same kind of shell a new terminal tab opens -
# rather than trusting doctor.sh's own inherited environment.
if command -v zsh >/dev/null 2>&1; then
  ZSH_BAT_THEME="$(zsh -i -c 'print -r -- "$BAT_THEME"' 2>/dev/null || true)"
  ZSH_HIGHLIGHTERS="$(zsh -i -c 'print -r -- "${ZSH_HIGHLIGHT_HIGHLIGHTERS[*]}"' 2>/dev/null || true)"
else
  ZSH_BAT_THEME=""
  ZSH_HIGHLIGHTERS=""
fi

if [ -n "$ZSH_BAT_THEME" ]; then
  pass "\$BAT_THEME is set in a fresh shell (${ZSH_BAT_THEME})."
else
  fail "\$BAT_THEME is not set in a fresh interactive shell." \
    "Confirm dot_oh-my-zsh-custom/theme-colors.zsh exists and \$ZSH_CUSTOM/theme-colors.zsh is being auto-sourced by oh-my-zsh."
fi

if printf '%s\n' "$ZSH_HIGHLIGHTERS" | grep -qiw "brackets"; then
  pass "\$ZSH_HIGHLIGHT_HIGHLIGHTERS includes 'brackets' in a fresh shell."
else
  fail "\$ZSH_HIGHLIGHT_HIGHLIGHTERS does not include 'brackets' in a fresh shell." \
    "Confirm zsh-syntax-highlighting is loaded as a plugin AFTER theme-colors.zsh runs, and that it's last in the plugins=(...) list."
fi

# =============================================================================
section "mise and shim ordering"
# =============================================================================
if command -v mise >/dev/null 2>&1; then
  pass "mise is installed."

  # Ask a fresh interactive zsh (which runs `mise activate`) whether it
  # considers itself active, and where it resolves each tool - this is
  # the PATH ordering dot_zshrc.tmpl's shim-reordering fix is meant to
  # guarantee, so it needs to be checked in that same kind of shell.
  if command -v zsh >/dev/null 2>&1; then
    MISE_ACTIVE="$(zsh -i -c 'print -r -- "${MISE_SHELL:-}"' 2>/dev/null || true)"
  else
    MISE_ACTIVE=""
  fi

  if [ -n "$MISE_ACTIVE" ]; then
    pass "mise is active in a fresh interactive shell (MISE_SHELL=${MISE_ACTIVE})."
  else
    fail "mise does not appear active in a fresh interactive shell." \
      "Confirm 'eval \"\$(mise activate zsh)\"' runs unconditionally near the end of dot_zshrc.tmpl."
  fi

  for tool in claude python3; do
    if command -v zsh >/dev/null 2>&1; then
      RESOLVED="$(zsh -i -c "command -v ${tool}" 2>/dev/null || true)"
    else
      RESOLVED="$(command -v "$tool" 2>/dev/null || true)"
    fi
    if [ -z "$RESOLVED" ]; then
      warn "'${tool}' does not resolve to anything on PATH (may not be installed)."
    elif printf '%s' "$RESOLVED" | grep -q "/mise/shims/"; then
      fail "'${tool}' resolves to a mise shim (${RESOLVED}), not Homebrew." \
        "Check PATH ordering: mise's shims dir should come AFTER Homebrew's bin dirs. See the comment in dot_zshrc.tmpl above the 'path=' lines."
    else
      pass "'${tool}' resolves to ${RESOLVED} (not a mise shim)."
    fi
  done
else
  warn "mise is not installed - skipping shim-ordering checks."
fi

# =============================================================================
section "Required CLIs"
# =============================================================================
for cli in bat fzf gh jq rg nvim mise op linear claude; do
  if command -v "$cli" >/dev/null 2>&1; then
    pass "'${cli}' is installed."
  else
    fail "'${cli}' is not installed." "Run: brew bundle --file=\"${SOURCE_DIR}/Brewfile\" (or brew install ${cli})"
  fi
done

# =============================================================================
section "Summary"
# =============================================================================
if [ "$FAILURES" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
  printf "%s%s%s\n" "$C_GREEN" "Everything looks good!" "$C_RESET"
elif [ "$FAILURES" -eq 0 ]; then
  printf "%sNo failures, but %d warning(s) above worth a look.%s\n" "$C_YELLOW" "$WARNINGS" "$C_RESET"
else
  printf "%s%d check(s) failed, %d warning(s). See \"Fix:\" lines above.%s\n" "$C_RED" "$FAILURES" "$WARNINGS" "$C_RESET"
fi

exit "$FAILURES"
