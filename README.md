# dotfiles-core

A shared, public [chezmoi](https://www.chezmoi.io/) dotfiles repo for a
consistent macOS shell and terminal setup - oh-my-zsh, a themed prompt,
iTerm2, and Claude Code, all driven by one color palette.

## Who this is for

Anyone setting up a Mac who wants this shell/terminal experience, without
any personal-secret configuration. This repo is public and intentionally
contains **zero** secrets, credentials, or private detail. Anything like
that lives in a machine-local `~/.zshrc.local` instead (never committed,
never synced).

## What setup asks

`chezmoi init` asks three plain-English questions: your full name and your
email address (both used for git commit authorship), and whether you use
1Password and want this setup to read secrets from it.

Everything else is the same for every machine. Optional tools are detected
rather than configured: for example, SDKMAN is initialized only if it is
already installed. Anything personal or machine-specific never goes in this
repo; it belongs in your own `~/.zshrc.local` (see `dot_zshrc_local.example`
for a starter template).

## Setup

See [`SETUP.md`](./SETUP.md) for step-by-step installation instructions,
and run `bin/doctor.sh` afterward to verify everything's working.

## GitHub App tokens for coding agents

Coding agents run a lot of `gh`, and by default every call spends your own
login's 5,000 requests an hour. The `gh` in `~/.local/bin` is a small wrapper
in front of Homebrew's: inside an agent session it runs the real `gh` with a
GitHub App installation token for the account that owns the target
repository, so agents spend the App's limit instead. Outside agent sessions,
and until you set it up, it hands every call straight to the real `gh`.

It knows an agent session by `CLAUDECODE` (Claude Code), `CODEX_THREAD_ID` or
`CODEX_SANDBOX` (Codex CLI), `CURSOR_AGENT` (Cursor's agent),
`ANTIGRAVITY_AGENT` (agy) or `GEMINI_CLI` (Gemini CLI). Tokens are minted by
[`gh-token`](https://github.com/Link-/gh-token) (installed through mise) from
an App key kept in 1Password, cached for their hour in `~/.cache/gh-app-token`,
and never printed. If a token cannot be minted, an agent's `gh` fails with a
one-line fix instead of falling back to your login.

Each account gets one line in `~/.config/gh-app-token/apps`: the owner, a Tab,
and the 1Password item holding `app_id`, `installation_id` and `private_key`.
The first line is the default, used for any other owner:

```text
your-org	op://Your Vault/your-org GitHub App
```

SETUP.md, Step 14, walks through creating the Apps. These variables adjust it:

| Variable | Meaning |
| --- | --- |
| `GH_APP_TOKEN_ENABLE=1` | Treat this as an agent session (for a harness with no marker) |
| `GH_APP_TOKEN_DISABLE=1` | Use your own login, even in an agent session |
| `GH_APP_TOKEN_DEBUG=1` | Explain each decision on stderr (never shows a token) |
| `GH_APP_TOKEN_REAL_GH` | Path of the real `gh` (default: the next `gh` on PATH) |

An explicit `GH_TOKEN` or `GITHUB_TOKEN` always wins.

## Reclaiming disk space

`disk-tidy` (installed to `~/.local/bin`) reclaims space that developer tools
leave behind. Each step uses the tool's own cleanup where one exists:

- **worktrees**: git worktrees that are safe to drop (see below)
- **logs**: `.log` files in `~/Library/Logs` over a size limit, truncated
  rather than deleted
- **xcode**: simulators whose runtime is gone, and DerivedData unused for a
  while
- **playwright**: old browser builds, keeping the newest of each browser
- **tools**: `brew cleanup`, `mise prune`, `pnpm store prune`,
  `npm cache verify`, `uv cache prune` and `pre-commit gc`, for whichever are
  installed
- **docker**: dangling images and build cache older than a week; containers
  and volumes are untouched
- **transcripts**: Codex and Cursor agent transcripts past an age limit

Apart from those logs and transcripts, everything it removes is rebuilt or
re-downloaded on demand. It leaves Claude Code and Gradle alone: Claude Code
prunes its own transcripts through `cleanupPeriodDays` in `settings.json`, and
Gradle cleans up its own caches.

A worktree is removed only when all of these hold:

- it is clean, with no uncommitted or untracked changes
- its branch is merged into origin's default branch, or was deleted upstream
- it has had no commit or checkout for at least 2 days
- it is not locked (`git worktree lock`)
- no running process has its working directory inside it
- no other git checkout is nested inside it
- it holds no untracked `.env*`, `.db`, `.sqlite` or `.sqlite3` file, even in
  an ignored folder

The branch is always kept, so `git worktree add <path> <branch>` brings the
worktree back. Only checkouts under `DISK_TIDY_ROOTS` are looked at.

```sh
disk-tidy                        # dry run: show what would be cleaned
disk-tidy --apply                # clean
disk-tidy --only worktrees,logs  # run only the named steps
disk-tidy schedule               # run `disk-tidy --apply` weekly
disk-tidy unschedule             # remove that schedule
```

`schedule` adds a launchd agent (macOS only) that runs on Sundays at 10:00, or
at the next wake, and logs to `~/Library/Logs/disk-tidy.log`. On other systems
it prints the command to add to cron instead.

Settings come from the environment or from `~/.config/disk-tidy/config`, a
shell file of `VAR=value` lines that takes precedence over the environment.
The scheduled run does not see your shell's environment, so put settings for
it in the file.

| Variable | Default | Meaning |
| --- | --- | --- |
| `DISK_TIDY_ROOTS` | `~/workspace` | Colon-separated folders holding git checkouts |
| `DISK_TIDY_DEPTH` | `2` | How deep under each root to look for checkouts |
| `DISK_TIDY_WORKTREE_IDLE_DAYS` | `2` | Days without a commit or checkout before a worktree can go |
| `DISK_TIDY_LOG_MAX_MB` | `1024` | Size above which a log file is truncated |
| `DISK_TIDY_DERIVED_DATA_DAYS` | `14` | Days unused before Xcode DerivedData is removed |
| `DISK_TIDY_TRANSCRIPT_DAYS` | `30` | Age in days at which Codex and Cursor transcripts are removed |
