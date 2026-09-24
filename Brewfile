# ---- Brewfile (CORE / shared tier) ----
#
# Shared baseline toolchain: shell/terminal experience + general dev tooling.
# Anyone setting up a Mac to mirror this machine's basics (e.g. a spouse's
# new laptop) should install from this file.
#
# Install with:
#   brew bundle --file=~/.local/share/chezmoi/Brewfile
#
# Check what's missing without installing anything:
#   brew bundle check --file=~/.local/share/chezmoi/Brewfile --no-upgrade
#
# Lines tagged `# TODO(michael): core or michael-only?` were ambiguous calls
# made during the initial split - triage and move as needed.
#
# ---- A note for a WORK / MDM-managed laptop ----
#
# Every line below flagged "MDM" is a place where a corporate-managed Mac
# is likely to get in the way: blocked installs needing IT approval,
# software-restriction/Gatekeeper policy, or something the company already
# deploys through its own management tooling (so a second, brew-installed
# copy could conflict or just be redundant). None of this is fatal - the
# bootstrap scripts in this repo are written to log a clear "needs IT
# approval" message and keep going rather than aborting the whole setup.
# Before running this on a company laptop, skim the flagged lines and
# comment out anything you know is already handled by IT, or that IT
# policy won't allow.
#
# Even Homebrew itself can be MDM-restricted on some fleets (installing to
# /opt/homebrew or /usr/local may need admin rights or an IT-approved
# installer). See run_once_before_00-install-homebrew.sh.

# ---- Taps ----
# MDM: third-party (non-Homebrew-core) taps are sometimes blocked by
# security policy that only allows vetted sources. If `linear` below fails
# to install, this tap is why - ask IT before adding untrusted taps.
tap "schpet/tap"

# ---- Shell & terminal ----
brew "coreutils"
brew "tmux"
brew "zsh-autosuggestions"
brew "zsh-syntax-highlighting"
brew "fzf"
brew "bat"

# ---- Dotfiles / runtime management ----
brew "chezmoi"
brew "mise"

# ---- General dev tooling ----
brew "jq"
brew "ripgrep"
brew "gh"
brew "git-town"
brew "pre-commit"
# MDM: pulled from the third-party tap above, not homebrew-core.
brew "schpet/tap/linear"

# ---- General file / text utilities ----
brew "base64"
brew "sevenzip"
brew "mmv"
brew "imagemagick"

# ---- Ambiguous - triage ----
# CI linter for GitHub Actions workflows; not everyone touches CI configs.
brew "actionlint" # TODO(michael): core or michael-only?
# Parallel command runner for local dev servers.
brew "mprocs" # TODO(michael): core or michael-only?
# JS/Node package manager; only needed if doing JS/web dev.
brew "pnpm" # TODO(michael): core or michael-only?
# Python static type checker; only needed if doing Python dev.
brew "pyright" # TODO(michael): core or michael-only?
# Fast Python package installer/resolver; only needed if doing Python dev.
brew "uv" # TODO(michael): core or michael-only?

# ---- Editor ----
brew "neovim"

# ---- GUI apps ----
cask "iterm2"
# MDM: many companies deploy 1Password (and require a specific SSO-linked
# build) through their own MDM/app-store channel. A second brew-installed
# copy can conflict with an existing managed install - check with IT
# before installing, or skip these two lines if 1Password is already on
# the machine.
cask "1password"
cask "1password-cli"
# MDM: third-party AI coding tools are frequently subject to a company's
# data-handling/security-review policy before they're allowed on a work
# laptop. Confirm Claude/Claude Code are approved before installing.
cask "claude"
cask "claude-code"
# MDM: dev-tool installs sometimes need IT approval on a locked-down
# fleet, and some companies mandate a specific hardened/managed build of
# VS Code instead of the vanilla cask.
cask "visual-studio-code"
# MDM: Slack is very often pushed by IT already (SSO-enrolled, managed
# updates). Installing this cask on top of an existing managed install is
# usually harmless but redundant - check first.
cask "slack"

# ---- Ambiguous GUI - triage ----
# GPG toolchain, e.g. for signed git commits; not everyone signs commits.
# MDM: GPG Suite can install a system extension / require Keychain access
# that managed-Mac security policy blocks outright. Expect this one to
# need IT approval, or to fail cleanly under MDM.
cask "gpg-suite-no-mail" # TODO(michael): core or michael-only?

# ---- Fonts ----
# MDM: font casks are generally low-risk and rarely blocked, but font
# installation still needs a Homebrew-managed /Library or ~/Library path,
# which some strict endpoint-security tools flag on first install.
cask "font-fira-code-nerd-font"
cask "font-fira-mono-nerd-font"
