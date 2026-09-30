#!/bin/bash
# cask-detect.sh - shared "is this already on the machine?" detection.
#
# Sourced (never executed) by:
#   - bin/doctor.sh, to report present-but-not-brew-managed casks as WARN
#   - run_once_before_02-brew-bundle-core.sh, to leave those casks out of
#     `brew bundle` so it never tries to install a second copy
#
# One implementation, two callers, so the two can never disagree about what
# "already installed" means.
#
# Environment (all optional):
#   BREW_BIN   absolute path to brew (default: whatever `brew` resolves to)
#   HOME_DIR   the home directory to look in (default: $HOME)
#
# Deliberately no `set` options here: this file is sourced into scripts that
# choose their own.

# cask_outside_brew CASK: decide whether a cask brew does NOT manage is
# nonetheless present on this machine. On success prints ONE line,
# "<kind><TAB><description>", where kind is app | font | bin, and returns 0;
# returns 1 (prints nothing) if it is genuinely absent or cannot be
# determined. The ground truth is brew's own cask metadata
# (`brew info --cask --json=v2`), which lists exactly the artifacts the cask
# would install, so the check follows whatever the cask really ships instead
# of a hand-kept name table:
#   - app artifacts: the named .app bundle exists in /Applications or
#     ~/Applications (installed by IT, drag-installed, or by the vendor's
#     updater).
#   - font artifacts: EVERY listed font file exists in ~/Library/Fonts or
#     /Library/Fonts. All-or-nothing on purpose: a partial family is not
#     "present", and brew installs fonts as plain files in ~/Library/Fonts,
#     so file presence is the same thing brew itself would have produced.
#   - binary artifacts (only for casks with no app or font, e.g.
#     1password-cli): EVERY binary the cask declares must resolve to an
#     absolute path on PATH. One stray match is not enough, and the
#     description lists each resolved path so it is clear where the tool
#     really came from. The claude-code casks are deliberately excluded
#     here: they are handled by claude_on_path below, which answers a
#     different question ("is ANY claude present?").
# Casks with no detectable artifact return 1 and stay "missing". Needs jq;
# without it nothing is softened. If `brew info` fails, returns 1: the
# caller keeps the cask, which is the safe fallback.
cask_outside_brew() {
  local cask="$1" info app font bin dir found resolved desc
  local home_dir="${HOME_DIR:-$HOME}"
  local -a apps=() fonts=() bins=()
  command -v jq >/dev/null 2>&1 || return 1
  info="$("${BREW_BIN:-brew}" info --cask --json=v2 "$cask" 2>/dev/null)" || return 1
  while IFS= read -r app; do
    [ -n "$app" ] && apps+=("$app")
  done < <(printf '%s' "$info" | jq -r '.casks[0].artifacts[]? | select(type == "object") | .app[]? | select(type == "string")' 2>/dev/null)
  while IFS= read -r font; do
    [ -n "$font" ] && fonts+=("$font")
  done < <(printf '%s' "$info" | jq -r '.casks[0].artifacts[]? | select(type == "object") | .font[]? | select(type == "string")' 2>/dev/null)
  while IFS= read -r bin; do
    [ -n "$bin" ] && bins+=("$bin")
  done < <(printf '%s' "$info" | jq -r '.casks[0].artifacts[]? | select(type == "object") | .binary[]? | select(type == "string")' 2>/dev/null)

  if [ ${#apps[@]} -gt 0 ]; then
    app="${apps[0]}"
    for dir in "/Applications" "${home_dir}/Applications"; do
      if [ -d "${dir}/${app}" ]; then
        printf 'app\t%s/%s\n' "$dir" "$app"
        return 0
      fi
    done
    return 1
  fi

  if [ ${#fonts[@]} -gt 0 ]; then
    for font in "${fonts[@]}"; do
      found=0
      for dir in "${home_dir}/Library/Fonts" "/Library/Fonts"; do
        if [ -e "${dir}/${font}" ]; then
          found=1
          break
        fi
      done
      [ "$found" -eq 1 ] || return 1
    done
    printf 'font\t%s font file(s) in Library/Fonts\n' "${#fonts[@]}"
    return 0
  fi

  case "$cask" in
    claude-code | claude-code@*) return 1 ;;
  esac
  if [ ${#bins[@]} -gt 0 ]; then
    desc=""
    for bin in "${bins[@]}"; do
      resolved="$(command -v "${bin##*/}" 2>/dev/null)"
      # Only an on-disk path counts; an alias or function name does not.
      case "$resolved" in
        /*) ;;
        *) return 1 ;;
      esac
      desc="${desc:+${desc}, }${bin##*/} at ${resolved}"
    done
    printf 'bin\t%s\n' "$desc"
    return 0
  fi
  return 1
}

# cask_display_name CASK: the friendly name brew lists for a cask
# ("Visual Studio Code", "1Password CLI"). Falls back to the cask token when
# brew or jq cannot say.
cask_display_name() {
  local cask="$1" name=""
  if command -v jq >/dev/null 2>&1; then
    name="$("${BREW_BIN:-brew}" info --cask --json=v2 "$cask" 2>/dev/null |
      jq -r '.casks[0].name[0] // empty' 2>/dev/null)" || name=""
  fi
  printf '%s\n' "${name:-$cask}"
}

# is_claude_code_cask CASK: true for the Claude Code casks (stable and @latest).
is_claude_code_cask() {
  case "$1" in
    claude-code | claude-code@*) return 0 ;;
  esac
  return 1
}

# claude_on_path: if ANY `claude` resolves to an on-disk path on PATH
# (native installer, npm, a Homebrew cask, anything), print that path and
# return 0. Returns 1 (prints nothing) if none does. The source of the
# install does not matter: the goal is never to lay a second Claude Code on
# top of a working one. An alias or function name does not count.
claude_on_path() {
  local resolved
  resolved="$(command -v claude 2>/dev/null)" || return 1
  case "$resolved" in
    /*)
      printf '%s\n' "$resolved"
      return 0
      ;;
  esac
  return 1
}

# resolve_symlinks PATH: print PATH with every symlink in the final component
# followed (portable: macOS's stock tools have no `readlink -f` on older
# releases). Used to see where a `claude` on PATH really lives.
resolve_symlinks() {
  local p="$1" target dir hops=0
  while [ -L "$p" ] && [ "$hops" -lt 40 ]; do
    target="$(readlink "$p")" || break
    case "$target" in
      /*) p="$target" ;;
      *) p="$(dirname "$p")/${target}" ;;
    esac
    hops=$((hops + 1))
  done
  dir="$(cd -P "$(dirname "$p")" 2>/dev/null && pwd)" || {
    printf '%s\n' "$p"
    return 0
  }
  printf '%s/%s\n' "$dir" "$(basename "$p")"
}

# claude_caskroom_cask PATH: if PATH is (a symlink into) a Homebrew Caskroom,
# print the cask it belongs to (e.g. claude-code@latest) and return 0;
# otherwise return 1. Homebrew symlinks a cask's binary from
# <prefix>/bin/claude into <prefix>/Caskroom/<cask>/<version>/.
claude_caskroom_cask() {
  local real rest
  real="$(resolve_symlinks "$1")"
  case "$real" in
    */Caskroom/*)
      rest="${real#*/Caskroom/}"
      printf '%s\n' "${rest%%/*}"
      return 0
      ;;
  esac
  return 1
}
