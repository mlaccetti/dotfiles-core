# dotfiles-core

A shared, public [chezmoi](https://www.chezmoi.io/) dotfiles repo for a
consistent macOS shell and terminal setup - oh-my-zsh, a themed prompt,
iTerm2, and Claude Code, all driven by one color palette.

## Who this is for

Anyone setting up a Mac who wants this shell/terminal experience: Michael's
own machines, and anyone else (e.g. a spouse's laptop, including a
work/MDM-managed one) who wants the same baseline without any of Michael's
employer-specific or personal-secret configuration. This repo is public
and intentionally contains **zero** secrets, credentials, or
employer-internal detail - anything like that lives in a machine-local
`~/.zshrc.local` instead (never committed, never synced).

## The two-profile model

`chezmoi init` asks a few plain-English questions, including which
**profile** you are:

- **`michael`** - Michael's own machines. A couple of genuinely
  shared-but-divergent things (like SDKMAN initialization) are gated on
  this profile.
- **`shared`** - anyone else. Gets the same core shell, prompt, theme, and
  tooling, with nothing profile-specific turned on.

Almost everything in this repo is identical for both profiles by design -
profile conditionals are used sparingly, only where two setups genuinely
need to diverge. Anything work-specific or personal is never in this repo
at all; it belongs in your own `~/.zshrc.local` (see
`dot_zshrc_local.example` for a starter template).

## Setup

See [`SETUP.md`](./SETUP.md) for step-by-step installation instructions,
and run `bin/doctor.sh` afterward to verify everything's working.
