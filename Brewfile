# ---- Brewfile (CORE / shared tier) ----
#
# This installs the everyday tools for using Claude Code as your main way
# of getting work done: talking to Linear, Confluence, git, and building
# small internal tools, plus a nicer-looking terminal to run it all in.
#
# It deliberately leaves out software developers use to write and test
# code by hand (linters, language servers, editors like neovim, terminal
# multiplexers). If you're not writing code yourself, you'll never need
# to type those commands, so there's no reason to install them.
#
# Install with:
#   brew bundle --file=~/.local/share/chezmoi/Brewfile
#
# Check what's missing without installing anything:
#   brew bundle check --file=~/.local/share/chezmoi/Brewfile --no-upgrade
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

# ---- Shell & terminal ----
# Makes the terminal itself nicer to read and use: autocomplete-style
# suggestions as you type, color-coded commands, and a fast fuzzy search
# (fzf) over your command history and files.
brew "zsh-autosuggestions"
brew "zsh-syntax-highlighting"
brew "fzf"
brew "bat"

# ---- Dotfiles / runtime management ----
# chezmoi is what applied this whole setup and keeps it up to date.
# mise manages background language runtimes that some Claude Code
# projects need (Node, Python, etc.) so you don't have to install or
# babysit them by hand.
brew "chezmoi"
brew "mise"

# ---- Tools Claude Code itself will call on your behalf ----
# jq: lets Claude Code read and edit JSON/config files cleanly.
# ripgrep (rg): fast text search across a project's files.
# gh: the GitHub command line tool, for git-based automation (opening
#     pull requests, checking status, etc.) driven through Claude.
brew "jq"
brew "ripgrep"
brew "gh"

# ---- Netlify (where Claude will deploy small webapps it builds you) ----
# Netlify's free tier explicitly allows the kind of "an employee builds
# a small internal tool" use case this laptop is for. Its command line
# tool lets Claude Code publish a site or app without you touching a
# dashboard.
brew "netlify-cli"

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
# laptop. Confirm Claude Code is approved before installing.
cask "claude-code"
# MDM: dev-tool installs sometimes need IT approval on a locked-down
# fleet, and some companies mandate a specific hardened/managed build of
# VS Code instead of the vanilla cask.
cask "visual-studio-code"
# MDM: Slack is very often pushed by IT already (SSO-enrolled, managed
# updates). Installing this cask on top of an existing managed install is
# usually harmless but redundant - check first.
cask "slack"

# ---- Fonts ----
# MDM: font casks are generally low-risk and rarely blocked, but font
# installation still needs a Homebrew-managed /Library or ~/Library path,
# which some strict endpoint-security tools flag on first install.
#
# This is the one font iTerm2's Anthropic profile actually references.
# (A second "mono" variant used to be listed here too; it's gone because
# nothing in this repo uses it.)
cask "font-fira-code-nerd-font"

# ---- What got cut from the old, developer-focused version of this file ----
#
# - tap "schpet/tap" and brew "schpet/tap/linear": the official Linear
#   MCP server (https://mcp.linear.app/mcp) does everything this CLI did
#   for Claude-driven work, without needing a git branch or a browser
#   tab open. Dropping the tap is also a small security win on a managed
#   laptop: one less third-party (non-Homebrew-core) source trusted.
# - git-town, pre-commit: branch-workflow and commit-hook tooling for
#   people writing and reviewing code by hand.
# - neovim, tmux: a terminal text editor and a terminal multiplexer.
#   Claude Code and VS Code cover editing; there's no separate terminal
#   session to multiplex.
# - coreutils: GNU replacements for macOS's built-in file utilities,
#   useful for shell scripting, not for day-to-day Claude-driven work.
# - base64, sevenzip, mmv, imagemagick: command-line file/archive/image
#   utilities meant to be typed and scripted by hand.
# - cask "claude" (the Claude desktop app) and cask "gpg-suite-no-mail":
#   neither is needed for the CLI-driven workflow this laptop is set up
#   for, and gpg-suite-no-mail installs a macOS system extension, which
#   is one of the things most likely to be blocked outright on a
#   managed Mac.
# - actionlint, mprocs, pnpm, pyright, uv: already moved to mise before
#   this rewrite (see ~/.config/mise/config.toml); developer-only tools
#   regardless.
