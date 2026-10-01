# ---- Brewfile (CORE / shared tier) ----
#
# This installs the everyday tools for using Claude Code as your main way
# of getting work done: talking to Linear, Confluence, git, and building
# small tools, plus a nicer-looking terminal to run it all in.
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
# ---- A note for a Mac that restricts installs ----
#
# Every line below flagged "Restricted installs" is a place where a Mac
# that limits what software can be installed is likely to get in the way:
# blocked installs, software-restriction/Gatekeeper policy, or something
# already installed another way (so a second, brew-installed copy could
# conflict or just be redundant). None of this is fatal - the bootstrap
# scripts in this repo are written to log a clear "install blocked"
# message and keep going rather than aborting the whole setup. If an
# install is blocked, ask whoever manages your Mac, or comment out the
# lines you don't need.
#
# Even Homebrew itself can be restricted (installing to /opt/homebrew or
# /usr/local needs admin rights). See run_once_before_00-install-homebrew.sh.

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

# ---- GUI apps ----
cask "iterm2"
# Restricted installs: 1Password may already be installed another way (for
# example from the App Store or its own installer). A second brew-installed
# copy can conflict with an existing install - skip these two lines if
# 1Password is already on the machine.
cask "1password"
cask "1password-cli"
# Restricted installs: some Macs block new command-line tools. If this one is
# blocked, ask whoever manages your Mac.
# The @latest channel cask conflicts with the stable `claude-code` cask (both
# own the `claude` binary), so a machine runs exactly one of them.
cask "claude-code@latest"
# Restricted installs: dev-tool installs are sometimes blocked on a Mac that
# restricts software. Skip this line if VS Code is already installed.
cask "visual-studio-code"
# Restricted installs: Slack may already be installed another way. Installing
# this cask on top of an existing install is usually harmless but redundant -
# check first.
cask "slack"

# ---- Fonts ----
# Restricted installs: font casks are generally low-risk and rarely blocked,
# but font installation still needs a Homebrew-managed /Library or ~/Library
# path, which some strict security tools flag on first install.
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
#   tab open. Dropping the tap is also a small security win: one less
#   third-party (non-Homebrew-core) source trusted.
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
#   neither is needed for the CLI-driven workflow this Mac is set up
#   for, and gpg-suite-no-mail installs a macOS system extension, which
#   is one of the things most likely to be blocked outright on a Mac that
#   restricts installs.
# - actionlint, mprocs, pnpm, pyright, uv: already moved to mise before
#   this rewrite (see ~/.config/mise/config.toml); developer-only tools
#   regardless.
