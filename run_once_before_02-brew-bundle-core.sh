#!/bin/bash
# Installs the core (shared) Homebrew tier from this repo's Brewfile.
#
# Not using `set -e` for the whole script on purpose: one blocked cask
# (e.g. corporate/MDM Gatekeeper policy) should not abort the rest of
# `chezmoi apply`.
set -uo pipefail

echo "==> [brew bundle] Installing/checking core Homebrew packages..."

# run_once_before_00 may have installed Homebrew moments ago. It ran
# `brew shellenv` in its own process, which this fresh process never sees, so
# on a brand-new Apple Silicon Mac (/opt/homebrew/bin is not on the default
# PATH) `command -v brew` fails even though brew is installed. Fall back to
# the standard install locations, then load brew's environment.
BREW_BIN="$(command -v brew 2>/dev/null || true)"
if [ -z "$BREW_BIN" ]; then
  for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [ -x "$candidate" ]; then
      BREW_BIN="$candidate"
      eval "$("$BREW_BIN" shellenv)"
      break
    fi
  done
fi

if [ -z "$BREW_BIN" ]; then
  echo "    !! Homebrew isn't installed (see the previous step's output)."
  echo "    !! ACTION NEEDED: install Homebrew, then run:"
  echo "    !!   brew bundle --file=\"\$(chezmoi source-path)/Brewfile\""
  echo "    Skipping brew bundle for now."
  exit 0
fi

echo "    Using Homebrew: ${BREW_BIN}"

SOURCE_DIR="${CHEZMOI_SOURCE_DIR:-$HOME/.local/share/chezmoi}"
BREWFILE="${SOURCE_DIR}/Brewfile"

if [ ! -f "$BREWFILE" ]; then
  echo "    !! Could not find Brewfile at: ${BREWFILE}"
  echo "    !! Skipping brew bundle - run it manually once you locate it:"
  echo "    !!   brew bundle --file=/path/to/Brewfile"
  exit 0
fi

echo "    Using Brewfile: ${BREWFILE}"

# ---- Leave already-installed apps alone -----------------------------------
# `brew bundle` errors on a cask whose .app is already in /Applications ("It
# seems there is already an App at ..."), and would lay a SECOND Claude Code
# on top of one installed another way (native installer, npm), shadowing it
# on PATH and triggering a fresh Gatekeeper prompt. So before bundling, build
# a filtered copy of the Brewfile without the casks whose artifact is already
# on this machine. The detection is shared with bin/doctor.sh
# (bin/lib/cask-detect.sh) so the two can never disagree.
#
# Any trouble (no lib, no jq, `brew info` failing for a cask) falls back to
# the old behavior for that cask: keep it in the bundle.
BUNDLE_FILE="$BREWFILE"
FILTERED=""
DETECT_LIB="${SOURCE_DIR}/bin/lib/cask-detect.sh"

# entry_continues LINE: true if a Brewfile entry does not end on LINE: a
# trailing comma or backslash, or a brace/bracket/paren left open. Tracks
# the open depth in the global ENTRY_DEPTH across the lines of one entry.
entry_continues() {
  local line="$1" opens closes
  opens="${line//[^\{\[\(]/}"
  closes="${line//[^\}\]\)]/}"
  ENTRY_DEPTH=$((ENTRY_DEPTH + ${#opens} - ${#closes}))
  [ "$ENTRY_DEPTH" -gt 0 ] && return 0
  case "$line" in
    *, | *\\) return 0 ;;
  esac
  return 1
}

# filter_brewfile SRC DEST: copy SRC to DEST, dropping every cask that is
# already present (with any continuation lines of its entry). Appends the
# friendly names of what was dropped to the global SKIPPED (comma separated).
filter_brewfile() {
  local src="$1" dest="$2" line cask name dropping=0
  # Held in a variable, not written inline, so it parses the same under
  # macOS's stock bash 3.2 (quoting inside an inline =~ pattern differs).
  local cask_re='^[[:space:]]*cask[[:space:]]+["'"'"']([^"'"'"']+)["'"'"']'
  SKIPPED=""
  ENTRY_DEPTH=0
  : >"$dest" || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$dropping" -eq 1 ]; then
      entry_continues "$line" || dropping=0
      continue
    fi
    if [[ "$line" =~ $cask_re ]]; then
      cask="${BASH_REMATCH[1]}"
      if cask_already_present "$cask"; then
        name="$(cask_display_name "$cask")"
        SKIPPED="${SKIPPED:+${SKIPPED}, }${name}"
        ENTRY_DEPTH=0
        entry_continues "$line" && dropping=1
        continue
      fi
    fi
    printf '%s\n' "$line" >>"$dest" || return 1
  done <"$src"
}

# cask_already_present CASK: true if this cask should be left out of the
# bundle because what it installs is already here.
cask_already_present() {
  local cask="$1"
  if is_claude_code_cask "$cask"; then
    # ANY `claude` on PATH, whatever its source: never install a second one.
    claude_on_path >/dev/null
    return $?
  fi
  cask_outside_brew "$cask" >/dev/null
}

if [ -f "$DETECT_LIB" ]; then
  # shellcheck source=bin/lib/cask-detect.sh
  . "$DETECT_LIB"
  export BREW_BIN
  # The per-cask check reads brew's cask metadata with jq. jq is a Brewfile
  # formula anyway; on a Mac that has Homebrew but not jq yet, get it first
  # (small, and it would be installed by the bundle regardless). If that
  # fails, the app checks are skipped and the bundle runs unfiltered.
  if ! command -v jq >/dev/null 2>&1; then
    echo "    Installing jq first (used to check which apps you already have)..."
    "$BREW_BIN" install jq >/dev/null 2>&1 || true
  fi
  FILTERED="$(mktemp "${TMPDIR:-/tmp}/Brewfile.filtered.XXXXXX" 2>/dev/null || true)"
  if [ -n "$FILTERED" ]; then
    trap 'rm -f "$FILTERED"' EXIT
    if filter_brewfile "$BREWFILE" "$FILTERED"; then
      BUNDLE_FILE="$FILTERED"
      if [ -n "$SKIPPED" ]; then
        echo "    Already installed, leaving as is: ${SKIPPED}"
      fi
    else
      echo "    (Could not check for already-installed apps; using the full Brewfile.)"
    fi
  fi
else
  echo "    (Could not find ${DETECT_LIB}; using the full Brewfile.)"
fi

if "$BREW_BIN" bundle --file="$BUNDLE_FILE"; then
  echo "    Core packages installed/verified."
else
  echo "    !! One or more packages failed to install."
  echo "    !! This can happen on a corporate/MDM-managed Mac when a cask"
  echo "    !! (an app installer) requires IT approval, or when Gatekeeper/"
  echo "    !! notarization policy blocks it."
  echo "    !! ACTION NEEDED: check the output above for which formula/cask"
  echo "    !! failed, ask IT for approval if needed, then re-run:"
  echo "    !!   brew bundle --file=\"${BREWFILE}\""
  echo "    Continuing with the rest of the setup."
fi

exit 0
