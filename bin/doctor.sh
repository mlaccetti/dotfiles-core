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
# Every `zsh -i -c` probe below is bounded: it runs with stdin closed
# (</dev/null) under a ~20s timeout (`timeout`, else `gtimeout`, else a perl
# alarm wrapper, since a bare macOS PATH has none of the first two). A probe
# that times out is reported as `[FAIL] interactive zsh init hung after Ns`
# and the run continues, so a shell startup that blocks (e.g. a CLI waiting
# on an auth prompt in ~/.zshrc) can never hang doctor.sh itself. Values
# passed to a probe are positional arguments, never spliced into the script.
#
# shellcheck disable=SC2088,SC2016
# (SC2088: several PASS/FAIL messages below use a literal "~/..." for
# readability in human-facing output - these are display strings, not paths
# being expanded, so the tilde is intentionally not expanded.
# SC2016: the zsh_probe scripts are single-quoted on purpose, so their
# $-expressions expand in the zsh probe, not in this bash script.)
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
warn() {
  printf "  %s[WARN]%s %s\n" "$C_YELLOW" "$C_RESET" "$1"
  if [ -n "${2:-}" ]; then
    printf "         %sNote:%s %s\n" "$C_BOLD" "$C_RESET" "$2"
  fi
  WARNINGS=$((WARNINGS + 1))
}
fail() {
  printf "  %s[FAIL]%s %s\n" "$C_RED" "$C_RESET" "$1"
  if [ -n "${2:-}" ]; then
    printf "         %sFix:%s %s\n" "$C_BOLD" "$C_RESET" "$2"
  fi
  FAILURES=$((FAILURES + 1))
}
section() { printf "\n%s%s%s\n" "$C_BOLD" "$1" "$C_RESET"; }

HOME_DIR="${HOME}"
DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
SOURCE_DIR="${CHEZMOI_SOURCE_DIR:-}"
if [ -z "$SOURCE_DIR" ] && command -v chezmoi >/dev/null 2>&1; then
  SOURCE_DIR="$(chezmoi source-path 2>/dev/null || true)"
fi
if [ -z "$SOURCE_DIR" ]; then
  # Fall back to "this script lives in <source>/bin/doctor.sh".
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
  SOURCE_DIR="$(dirname "$SCRIPT_DIR")"
fi

# ---- bounded interactive-zsh probes ----------------------------------------
# Seconds an interactive zsh probe may run before it is declared hung.
# DOCTOR_ZSH_TIMEOUT overrides it (used to test the hang path quickly).
ZSH_PROBE_TIMEOUT="${DOCTOR_ZSH_TIMEOUT:-20}"
if command -v timeout >/dev/null 2>&1; then
  BOUND_KIND="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
  BOUND_KIND="gtimeout"
elif command -v perl >/dev/null 2>&1; then
  BOUND_KIND="perl"
else
  BOUND_KIND=""
fi

# run_bounded SECS CMD [ARGS...]: run CMD, killing it after SECS seconds.
# Exits 124 (timeout/gtimeout), 137 (needed SIGKILL), or 142 / 14 (perl's
# SIGALRM) on expiry; 127 if there is no way to bound the command at all.
# GNU timeout (without --foreground) signals the child's whole process group.
run_bounded() {
  local secs="$1"
  shift
  case "$BOUND_KIND" in
    timeout | gtimeout) "$BOUND_KIND" -k 2 "$secs" "$@" ;;
    perl) perl -e 'alarm shift; exec @ARGV' "$secs" "$@" ;;
    *) return 127 ;;
  esac
}

# zsh_probe SCRIPT [ARG...]: run `zsh -i -c SCRIPT ARG...` bounded, stdin
# closed, stderr discarded. Output goes through a temp FILE, not a pipe: a
# process the shell backgrounded (or an orphaned grandchild that outlives the
# killed zsh) would otherwise hold a pipe open and block `$(...)` until it
# exits, defeating the timeout. Sets (not prints, so callers keep the state):
#   PROBE_OUT   captured stdout
#   PROBE_STATE ok | hung | unavailable (no zsh, or nothing to bound it with)
# ARGs are passed positionally to the script ("$@" inside it), never spliced
# into the script text. Callers pad argv with a leading "zsh" so it lands in
# $0.
zsh_probe() {
  local rc tmp
  PROBE_OUT=""
  if ! command -v zsh >/dev/null 2>&1 || [ -z "$BOUND_KIND" ]; then
    PROBE_STATE="unavailable"
    return 0
  fi
  tmp="$(mktemp "${TMPDIR:-/tmp}/doctor-probe.XXXXXX")" || {
    PROBE_STATE="unavailable"
    return 0
  }
  run_bounded "$ZSH_PROBE_TIMEOUT" zsh -i -c "$@" </dev/null >"$tmp" 2>/dev/null
  rc=$?
  # perl's alarm delivers SIGALRM, which zsh itself handles by exiting with
  # status 14 (not the usual 128+14=142), so accept both under that wrapper.
  if [ "$BOUND_KIND" = "perl" ] && [ "$rc" -eq 14 ]; then
    rc=142
  fi
  case "$rc" in
    124 | 137 | 142) PROBE_STATE="hung" ;;
    *)
      PROBE_STATE="ok"
      PROBE_OUT="$(cat "$tmp")"
      ;;
  esac
  rm -f "$tmp"
  return 0
}

# report_zsh_hung WHAT: the standard FAIL for a timed-out probe.
report_zsh_hung() {
  fail "interactive zsh init hung after ${ZSH_PROBE_TIMEOUT}s (while checking ${1})." \
    "Something in ~/.zshrc, ~/.zshrc.local, or oh-my-zsh blocks without a TTY (a CLI waiting on an auth prompt is the usual cause). Find it with: zsh -i -c exit </dev/null"
}

# report_zsh_unavailable WHAT: probes cannot run (no zsh / no bounding tool).
report_zsh_unavailable() {
  warn "Skipped interactive-zsh checks for ${1}: no zsh, or no timeout/gtimeout/perl to bound the probe. Install coreutils (brew install coreutils) so a hung shell startup cannot hang doctor.sh."
}

# =============================================================================
section "Homebrew"
# =============================================================================
# Every formula/cask in the Brewfile is checked individually against what is
# actually on this machine, instead of trusting the all-or-nothing answer of
# `brew bundle check`. That matters when apps like 1Password and Slack were
# installed another way (the App Store, a vendor installer), so brew did not
# install them, but they are there and work fine. Those are a WARN ("present, just
# not managed by Homebrew"), never a FAIL. Only something that is really
# absent is a FAIL.

# brewfile_list FILE KIND: print the names of KIND (formula|cask) entries in
# FILE. Returns brew's exit status so a broken `brew bundle list` is never
# mistaken for "nothing is missing".
brewfile_list() {
  brew bundle list --file="$1" "--$2" 2>/dev/null
}

# brewfile_missing FILE KIND: print the entries brew has not installed.
brewfile_missing() {
  local file="$1" kind="$2" name
  while IFS= read -r name; do
    [ -z "$name" ] && continue
    if ! brew list "--${kind}" --versions "$name" >/dev/null 2>&1; then
      printf '%s\n' "$name"
    fi
  done < <(brewfile_list "$file" "$kind")
}

# Where chezmoi externals put zsh plugins (zsh-autosuggestions and
# zsh-syntax-highlighting): $ZSH_CUSTOM/plugins/<name>. $ZSH_CUSTOM is often
# unset in a bare ssh session, so fall back to its fixed default location.
ZSH_CUSTOM_DIR="${ZSH_CUSTOM:-${HOME_DIR}/.oh-my-zsh-custom}"

# cask_outside_brew, claude_present and the other "is it already here?"
# detection helpers live in bin/lib/cask-detect.sh, shared with
# run_once_before_02-brew-bundle-core.sh so the bootstrap and this check
# always agree on what counts as already installed.
# shellcheck source=lib/cask-detect.sh
. "${DOCTOR_DIR}/lib/cask-detect.sh"

# check_brewfile FILE LABEL: per-item Brewfile check (see the section header).
check_brewfile() {
  local file="$1" label="$2" name where adopt found kind claude_path claude_cask
  local -a missing=() missing_formulae=() missing_casks=() external=()

  if [ ! -f "$file" ]; then
    warn "Could not find ${label} at ${file} to check against."
    return
  fi
  if ! brewfile_list "$file" formula >/dev/null || ! brewfile_list "$file" cask >/dev/null; then
    warn "Could not read ${label} with 'brew bundle list', so its packages were not checked." \
      "Try: brew bundle list --file=\"${file}\""
    return
  fi

  while IFS= read -r name; do
    [ -z "$name" ] && continue
    # zsh plugins (zsh-autosuggestions, zsh-syntax-highlighting) are
    # delivered by chezmoi externals into $ZSH_CUSTOM/plugins/, not by brew.
    # If the plugin directory exists, the formula is satisfied.
    if [ -d "${ZSH_CUSTOM_DIR}/plugins/${name}" ]; then
      external+=("$name")
      continue
    fi
    missing+=("$name")
    missing_formulae+=("$name")
  done < <(brewfile_missing "$file" formula)

  while IFS= read -r name; do
    [ -z "$name" ] && continue
    # Claude Code: a working `claude` from ANY install method (native
    # installer, npm, the other Homebrew channel) is fine. Only "no claude
    # anywhere on PATH" counts as missing. This is the same rule the
    # bootstrap uses to avoid installing a second copy.
    if is_claude_code_cask "$name" && claude_path="$(claude_present)"; then
      if claude_cask="$(claude_caskroom_cask "$claude_path")"; then
        if [ "$claude_cask" = "$name" ]; then
          warn "Claude Code is present through Homebrew's '${claude_cask}' cask (at ${claude_path}), though brew doesn't list it as installed. That's fine." \
            "It works as installed; nothing is wrong."
        else
          warn "Claude Code is installed through Homebrew as '${claude_cask}' instead of '${name}' (at ${claude_path}). That's fine." \
            "It works as installed; nothing is wrong. Don't add a second copy: two casks fight over the 'claude' command."
        fi
      else
        warn "Claude Code is installed outside Homebrew (at ${claude_path}). That's fine." \
          "It works as installed; nothing is wrong. Don't install the '${name}' cask on top of it: two copies fight over the 'claude' command."
      fi
      continue
    fi
    # Present on disk but not installed through brew (an app from the App Store, a
    # drag-installed app, fonts copied by hand): a WARN, not a missing
    # package.
    if found="$(cask_outside_brew "$name")"; then
      kind="${found%%$'\t'*}"
      where="${found#*$'\t'}"
      # Fonts are plain files with no app to quit; --force re-lays them under
      # brew's control. Apps need to be closed before --adopt. Binary-only
      # casks have nothing to quit or adopt: the tool came from somewhere
      # else, so the choice is to remove that install and let brew own it,
      # or drop the cask.
      case "$kind" in
        font) adopt="Adopt with: brew install --cask --force ${name}" ;;
        bin) adopt="Installed outside Homebrew. To let Homebrew manage it, remove the other install and run: brew install --cask ${name}, or drop it from the Brewfile." ;;
        *) adopt="Adopt with: brew install --cask --adopt ${name} (after quitting the app)" ;;
      esac
      warn "'${name}' is present but not brew-managed (${label}): ${where}." \
        "It works as installed; nothing is wrong. ${adopt}"
      continue
    fi
    missing+=("$name")
    missing_casks+=("$name")
  done < <(brewfile_missing "$file" cask)

  if [ ${#external[@]} -gt 0 ]; then
    pass "${label}: provided by chezmoi in ${ZSH_CUSTOM_DIR}/plugins, not brew: ${external[*]}."
  fi

  if [ ${#missing[@]} -eq 0 ]; then
    pass "All ${label} packages are installed or otherwise present."
  else
    # Suggest installing just what is missing. `brew bundle` over the whole
    # Brewfile would try every cask again, and on a Mac that already has the
    # apps it fails with "It seems there is already an App at ...".
    local fix="" sep=""
    if [ ${#missing_formulae[@]} -gt 0 ]; then
      fix="brew install ${missing_formulae[*]}"
      sep=", then run: "
    fi
    if [ ${#missing_casks[@]} -gt 0 ]; then
      fix="${fix}${sep}brew install --cask ${missing_casks[*]}"
    fi
    fail "${label} is missing: ${missing[*]}." \
      "Run: ${fix}"
  fi
}

if command -v brew >/dev/null 2>&1; then
  pass "Homebrew is installed ($(command -v brew))."
  BREW_BIN="$(command -v brew)"
  export BREW_BIN # read by bin/lib/cask-detect.sh
  check_brewfile "${SOURCE_DIR}/Brewfile" "core Brewfile"
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
# Output is captured first and matched second. `cmd | grep -q` is wrong under
# `set -o pipefail`: grep exits at the first match, the writer (fc-list,
# system_profiler, find) gets SIGPIPE, and the pipeline reports failure even
# though the font IS there. fc-list exists whenever fontconfig does (some Homebrew
# formulae pull it in), so this used to report a false FAIL right after a good install.
FONT_FOUND=0
FONT_FILES="$(find "${HOME_DIR}/Library/Fonts" /Library/Fonts -iname "*FiraCode*Nerd*" 2>/dev/null)"
if [ -n "$FONT_FILES" ]; then
  FONT_FOUND=1
elif command -v fc-list >/dev/null 2>&1; then
  FC_LIST_OUT="$(fc-list 2>/dev/null)"
  if grep -qi "FiraCode Nerd Font" <<<"$FC_LIST_OUT"; then
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
  SP_FONTS_OUT="$(system_profiler SPFontsDataType 2>/dev/null)"
  if grep -qi "$PS_NAME" <<<"$SP_FONTS_OUT"; then
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
    # Is the Anthropic profile iTerm2's DEFAULT (used for new windows/tabs)?
    # Installing a Dynamic Profile does not make it the default; the
    # run_once_after_10 script sets it when iTerm2 is closed. Compare
    # iTerm2's stored default GUID with the profile's own Guid. WARN, not
    # FAIL: it is a preference, and it may simply not be applied yet.
    ANTHROPIC_GUID="$(jq -r '[.Profiles[]? | select(.Name == "Anthropic") | .Guid][0] // empty' "$PROFILE_PATH" 2>/dev/null || true)"
    if [ -z "$ANTHROPIC_GUID" ]; then
      warn "Could not read the Anthropic profile's Guid from ${PROFILE_PATH}; skipping the default-profile check."
    elif ! command -v defaults >/dev/null 2>&1; then
      warn "iTerm2 default-profile check skipped (no 'defaults' command)."
    else
      ITERM_DEFAULT_GUID="$(defaults read com.googlecode.iterm2 "Default Bookmark Guid" 2>/dev/null || true)"
      if [ "$ITERM_DEFAULT_GUID" = "$ANTHROPIC_GUID" ]; then
        pass "The Anthropic profile is iTerm2's default profile."
      else
        warn "The Anthropic profile is NOT iTerm2's default profile (default Guid: '${ITERM_DEFAULT_GUID:-<unset>}', Anthropic Guid: '${ANTHROPIC_GUID}'). Quit iTerm2, then run: defaults write com.googlecode.iterm2 \"Default Bookmark Guid\" -string \"${ANTHROPIC_GUID}\" (or in iTerm2: Settings > Profiles > Anthropic > Other Actions > Set as Default)."
      fi
    fi
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
# Both values come from one bounded interactive-shell spawn.
zsh_probe 'print -r -- "$BAT_THEME"; print -r -- "${ZSH_HIGHLIGHT_HIGHLIGHTERS[*]}"' zsh
ZSH_BAT_THEME="$(printf '%s\n' "$PROBE_OUT" | sed -n '1p')"
ZSH_HIGHLIGHTERS="$(printf '%s\n' "$PROBE_OUT" | sed -n '2p')"

if [ "$PROBE_STATE" = "hung" ]; then
  report_zsh_hung "\$BAT_THEME and \$ZSH_HIGHLIGHT_HIGHLIGHTERS"
elif [ "$PROBE_STATE" = "unavailable" ]; then
  report_zsh_unavailable "\$BAT_THEME and \$ZSH_HIGHLIGHT_HIGHLIGHTERS"
else
  if [ -n "$ZSH_BAT_THEME" ]; then
    pass "\$BAT_THEME is set in a fresh shell (${ZSH_BAT_THEME})."
  else
    fail "\$BAT_THEME is not set in a fresh interactive shell." \
      "Confirm dot_oh-my-zsh-custom/theme-colors.zsh exists and \$ZSH_CUSTOM/theme-colors.zsh is being auto-sourced by oh-my-zsh."
  fi

  if grep -qiw "brackets" <<<"$ZSH_HIGHLIGHTERS"; then
    pass "\$ZSH_HIGHLIGHT_HIGHLIGHTERS includes 'brackets' in a fresh shell."
  else
    fail "\$ZSH_HIGHLIGHT_HIGHLIGHTERS does not include 'brackets' in a fresh shell." \
      "Confirm zsh-syntax-highlighting is loaded as a plugin AFTER theme-colors.zsh runs, and that it's last in the plugins=(...) list."
  fi
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
  #
  # One bounded spawn covers MISE_SHELL plus every tool's `command -v`. Tool
  # names are passed as positional arguments ("$@"), never spliced into the
  # script string, so a tool name can never be interpreted as shell syntax.
  MISE_TOOLS=(claude python3)
  zsh_probe '
    print -r -- "${MISE_SHELL:-}"
    for t in "$@"; do
      print -r -- "$(command -v -- "$t" 2>/dev/null)"
    done
  ' zsh "${MISE_TOOLS[@]}"
  MISE_QUERY="$PROBE_OUT"
  MISE_PROBE_STATE="$PROBE_STATE"
  if [ "$MISE_PROBE_STATE" = "unavailable" ]; then
    # No zsh (or nothing to bound it with): resolve tools in this script's
    # own environment. Line 1 stays blank (no interactive shell to ask).
    MISE_QUERY="
"
    for tool in "${MISE_TOOLS[@]}"; do
      MISE_QUERY="${MISE_QUERY}$(command -v "$tool" 2>/dev/null)
"
    done
  fi
  MISE_ACTIVE="$(printf '%s\n' "$MISE_QUERY" | sed -n '1p')"

  if [ "$MISE_PROBE_STATE" = "hung" ]; then
    report_zsh_hung "mise activation and tool resolution"
  elif [ -n "$MISE_ACTIVE" ]; then
    pass "mise is active in a fresh interactive shell (MISE_SHELL=${MISE_ACTIVE})."
  else
    fail "mise does not appear active in a fresh interactive shell." \
      "Confirm 'eval \"\$(mise activate zsh)\"' runs unconditionally near the end of dot_zshrc.tmpl."
  fi

  line_num=1
  for tool in "${MISE_TOOLS[@]}"; do
    [ "$MISE_PROBE_STATE" = "hung" ] && break
    line_num=$((line_num + 1))
    RESOLVED="$(printf '%s\n' "$MISE_QUERY" | sed -n "${line_num}p")"
    if [ -z "$RESOLVED" ]; then
      warn "'${tool}' does not resolve to anything on PATH (may not be installed)."
    elif grep -q "/mise/shims/" <<<"$RESOLVED"; then
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
# Source of truth: the Brewfile (core tier). This list is every `brew`
# formula there that installs a standalone binary on PATH (bat, fzf, gh,
# jq, ripgrep -> rg, mise), plus the two casks that install a CLI rather
# than a GUI app (1password-cli -> op, claude-code@latest -> claude). chezmoi is
# checked separately above. zsh-autosuggestions and zsh-syntax-highlighting
# are also in the Brewfile but are zsh plugins sourced by the shell, not
# binaries on PATH, so they don't belong here. If the Brewfile changes,
# update this list to match.
# cli_fix CLI: the command that installs just that tool (never the whole
# Brewfile: on a Mac that already has the apps, `brew bundle` errors with
# "It seems there is already an App at ...").
cli_fix() {
  case "$1" in
    rg) echo "brew install ripgrep" ;;
    op) echo "brew install --cask 1password-cli" ;;
    claude) echo "brew install --cask claude-code@latest" ;;
    *) echo "brew install $1" ;;
  esac
}

for cli in bat fzf gh jq rg mise op claude; do
  if command -v "$cli" >/dev/null 2>&1; then
    pass "'${cli}' is installed."
  elif [ "$cli" = "claude" ] && claude_native="$(claude_native_install)"; then
    fail "'claude' is installed at ${claude_native} but its folder is not on your PATH." \
      "Add it to PATH: echo 'export PATH=\"$(dirname "$claude_native"):\$PATH\"' >> ~/.zshrc.local, then open a new terminal window."
  else
    fail "'${cli}' is not installed." "Run: $(cli_fix "$cli")"
  fi
done

# node and npm are not in the Brewfile: mise installs Node.js (which bundles
# npm) from dot_config/mise/config.toml via run_onchange_after_25-mise-install.
# They are required because Claude Code projects (small web apps) need them.
# They have their own loop
# because the fix is `mise install`, not `brew bundle`.
for cli in node npm; do
  if command -v "$cli" >/dev/null 2>&1; then
    pass "'${cli}' is installed."
  else
    fail "'${cli}' is not installed." "Run: mise install (installs Node.js and npm from ~/.config/mise/config.toml). If mise itself is missing, run brew install mise first, then open a new terminal window."
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
