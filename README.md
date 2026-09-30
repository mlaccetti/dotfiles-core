# dotfiles-core

A shared, public [chezmoi](https://www.chezmoi.io/) dotfiles repo for a
consistent macOS shell and terminal setup - oh-my-zsh, a themed prompt,
iTerm2, and Claude Code, all driven by one color palette.

## Who this is for

Anyone setting up a Mac who wants this shell/terminal experience, including
a work/MDM-managed one, without any employer-specific or personal-secret
configuration. This repo is public and intentionally contains **zero**
secrets, credentials, or employer-internal detail. Anything like that lives
in a machine-local `~/.zshrc.local` instead (never committed, never synced).

## What setup asks

`chezmoi init` asks three plain-English questions: your full name and your
email address (both used for git commit authorship), and whether you use
1Password and want this setup to read secrets from it.

Everything else is the same for every machine. Optional tools are detected
rather than configured: for example, SDKMAN is initialized only if it is
already installed. Anything work-specific or personal never goes in this
repo; it belongs in your own `~/.zshrc.local` (see `dot_zshrc_local.example`
for a starter template).

## Setup

See [`SETUP.md`](./SETUP.md) for step-by-step installation instructions,
and run `bin/doctor.sh` afterward to verify everything's working.
