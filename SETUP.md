# Setup

## What you're getting

This sets up a themed terminal (iTerm2, in a dark palette that matches
Claude Code), a useful two-line shell prompt, a set of everyday
command-line tools (search, JSON, GitHub, etc.), and colorized/highlighted
output in your shell and in `cat`. Claude Code's own color theme is set to
match the same palette.

It will not touch anything specific to Michael's own machine or work.
Everything here is shared, public, and safe to run on any Mac, including
a company-managed one.

## Before you start

### macOS and admin rights

This expects a reasonably current macOS with `zsh` as the default shell
(that's been the default since macOS Catalina, but a managed work laptop
can override it, so it's worth checking, see Troubleshooting below).

You will need your account's admin password (or an admin nearby) for:

- Installing Homebrew (it creates directories under `/opt/homebrew` or
  `/usr/local` and needs permission to do that once).
- Any Homebrew "cask" (GUI app) that shows a Gatekeeper/security prompt on
  first install.
- Approving the GPG system extension, if you install it.

### IT / MDM heads-up

If this is a company-managed ("MDM") Mac, skim this list **before you
start** so you can file one IT ticket instead of five. Each of these can
be blocked or need approval on a locked-down fleet:

- Installing Homebrew itself.
- Installing fonts (the Nerd Font casks).
- Installing iTerm2.
- Installing the 1Password and 1Password CLI casks (many companies push
  their own managed build of 1Password already; a second copy can
  conflict).
- Installing the Slack cask (same reasoning: often already pushed by IT).
- Installing `gpg-suite-no-mail`, which installs a macOS system extension.
  This is one of the most likely things to be blocked outright.
- Installing the `schpet/tap` Homebrew tap (a third-party, non-Apple,
  non-Homebrew-core source). Some security policies only allow vetted
  taps.

None of this stops the rest of the setup. The scripts are written to log
a clear "needs IT approval" message for anything blocked and keep going,
so you'll still end up with a working shell and terminal even if a few
apps are missing. You can install those later once IT signs off.

### Time estimate

30 to 60 minutes if everything installs cleanly. Add time if you need to
file an IT ticket and wait on an approval, most of that is waiting, not
active work.

## Setup steps

Each step below is self-contained and safe to re-run. If something fails,
fix the specific thing called out in "if this fails," then re-run that
same step, you don't need to start over.

### Step 1: Install the Xcode Command Line Tools

This repo doesn't script this step (Homebrew's own installer would ask
for it if it's missing), but it's faster to do it up front.

```bash
xcode-select --install
```

**You should see:** a macOS dialog asking to install the developer
tools. Click "Install," accept the license, and wait for it to finish
(a few minutes).

**If this fails:** if you instead see "command line tools are already
installed," you're done, skip to Step 2. If the dialog never appears,
run `xcode-select -p` to check whether it's already installed
(prints a path) or not (prints nothing / errors).

### Step 2: Install Homebrew

Homebrew installs to a different location depending on your Mac's chip.
The official installer detects this automatically; you only need to know
which `shellenv` command to run afterward.

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

**You should see:** a wall of installer output ending with a "Next
steps" section. It may ask for your password (this is the one admin-
rights moment from the checklist above).

**If this fails:** on a managed Mac, this is the single most likely
thing to be blocked by IT. If it errors out or hangs asking for
permissions you don't have, stop here and see Troubleshooting.

Once it finishes, make Homebrew available in this terminal window:

```bash
if [ -d "/opt/homebrew" ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
else
  eval "$(/usr/local/bin/brew shellenv)"
fi
```

**You should see:** no output. Confirm it worked with `brew --version`.

This only affects your current terminal window. Once you finish Step 4,
the managed `~/.zshrc` puts Homebrew on your `PATH` automatically for
every future terminal, so you won't need to repeat this.

### Step 3: Install chezmoi

[chezmoi](https://www.chezmoi.io/) is the tool that manages everything
else in this repo.

```bash
brew install chezmoi
```

**You should see:** Homebrew download and install a `chezmoi` formula,
ending in something like "🍺  chezmoi was successfully installed."

**If this fails:** run `brew doctor` and follow what it recommends, then
retry. If Homebrew itself isn't working, go back to Step 2.

### Step 4: Run `chezmoi init --apply`

This is the main step. It asks four short questions, then installs the
Homebrew packages, applies all the dotfiles, and configures iTerm2 and
Claude Code.

```bash
chezmoi init --apply https://github.com/mlaccetti/dotfiles-core
```

You'll be asked four questions, in this exact order. Here's what each one
means and what to type:

1. **`Your full name (used for git commit authorship)`**
   Type your name, e.g. `Jane Laccetti`.

2. **`Your email address (used for git commit authorship)`**
   Type the email you want associated with your commits.

   > Note: these two answers do get written to your global git config
   > automatically during `chezmoi apply`, but only for whichever of
   > name and email you don't already have set. On a work laptop, IT's
   > onboarding may have already configured a git identity, and this
   > deliberately won't overwrite it. Once setup finishes, check what
   > you actually ended up with:
   > `git config --global user.name` and
   > `git config --global user.email`. If either isn't what you want,
   > set it yourself:
   > `git config --global user.name "Your Name"` and
   > `git config --global user.email "you@example.com"`.

3. **`Which profile is this? Type 'michael' for Michael's machine or 'shared' for anyone else (e.g. a spouse's laptop)`**
   Type `shared`.

4. **`Do you use 1Password and want this setup to read secrets from it? Type true or false - if unsure, type false (you can turn this on later)`**
   Type `false` unless you already use the 1Password CLI (`op`) and know
   you want chezmoi to read secrets from it. You can change your mind
   later by running `chezmoi init` again.

   Note: this only affects whether chezmoi is configured to *talk* to
   1Password later. The 1Password app and its command-line tool still
   get installed by Homebrew in the next part of this step either way
   (see the IT heads-up above).

**You should see:** after the four questions, a long stream of output:
Homebrew installing/checking packages (this is the slowest part, several
minutes), a check for `~/.oh-my-zsh` (safe to ignore on a brand-new
machine), then chezmoi writing your dotfiles, then notes about the
iTerm2 profile and Claude Code theme being installed.

**If this fails:**
- If a specific Homebrew formula or cask fails partway through, that's
  expected on a managed Mac (see the IT heads-up). The script keeps
  going; note which package failed and either get it approved or ignore
  it for now. `bin/doctor.sh` (Step 8) will tell you what's still
  missing.
- If you mistype an answer to question 3, `chezmoi init` will print an
  error and stop (`profile must be 'michael' or 'shared'`). Just run the
  command again.
- You can safely re-run `chezmoi init --apply https://github.com/mlaccetti/dotfiles-core`
  at any time. It re-asks the four questions and rewrites chezmoi's own
  config, but never overwrites your dotfiles incorrectly.

### Step 5: Restart your shell

Your `~/.zshrc` changed. Open a new terminal tab or window, or run:

```bash
exec zsh -l
```

**You should see:** your prompt reappear, now themed (colored segments,
git branch info, etc.) instead of the plain default prompt.

**If this fails:** if the new prompt doesn't show up, double-check you
actually opened a *new* shell (an old tab keeps its old environment).

### Step 6: Select the iTerm2 profile

`chezmoi apply` already copied the Anthropic color profile into iTerm2's
Dynamic Profiles folder. iTerm2 has to be told to actually use it, this
part can't be scripted.

```bash
killall iTerm2 2>/dev/null; open -a iTerm
```

**You should see:** iTerm2 quit and reopen.

Now select the profile manually:

1. Open **iTerm2 > Settings** (older versions call this **Preferences**)
   **> Profiles**.
2. Click **Anthropic** in the profile list on the left.
3. To make it the default for every new window, click the gear icon
   ("Other Actions") at the bottom of that list and choose **Set as
   Default**. Otherwise, right-click any tab and choose **Edit Session >
   Profile > Anthropic** to switch just that tab.

**If this fails:** if "Anthropic" doesn't appear in the profile list at
all, see Troubleshooting.

### Step 7: Verify the Claude Code theme

`chezmoi apply` already set this for you. Confirm it took:

```bash
jq -r '.theme' "$HOME/.claude/settings.json"
```

**You should see:** `custom:anthropic`.

**If this fails:** if you see `null`, an empty result, or an error,
re-run `chezmoi apply` (no need to redo `chezmoi init`). If `jq` itself
isn't found, open a new terminal (Step 5) or check that Homebrew
finished installing (Step 4).

### Step 8: Run the doctor script

This checks everything above in one shot.

```bash
bash "$(chezmoi source-path)/bin/doctor.sh"
```

**You should see:** a series of sections, each with `[PASS]`, `[WARN]`,
or `[FAIL]` lines, ending in a summary. `[WARN]` is informational and
fine to ignore for now; `[FAIL]` lines each include a specific "Fix:"
line telling you the exact command to run next.

**If this fails:** work through the `[FAIL]` lines top to bottom, each
one has its own fix. Re-run the script after each fix to confirm.

## The glyph check

Partway through `bin/doctor.sh`'s output, under **"Glyph rendering test
(look at this line yourself)"**, you'll see three lines: a row of
arrow-like separators, a row of small icons, and a row of emoji. This is
the one check you have to eyeball yourself, the script can't verify it
for you.

**Correct:** the separators look like solid triangular arrows connecting
one color block to the next (like the segments in your prompt), the icon
row shows small recognizable glyphs (not letters), and the emoji row
shows actual color emoji (a rocket, a checkmark, etc.).

**Broken:** any of those show up as a hollow rectangle ("tofu"), or a
question mark inside a diamond. That means the terminal isn't actually
using the Nerd Font, even if a Nerd Font is technically installed
somewhere on the system.

**What to do about it:**

1. Confirm you completed Step 6 and the current tab is actually using
   the **Anthropic** profile (not some other default).
2. In iTerm2, go to **Settings > Profiles > Anthropic > Text** and
   confirm the font is set to **FiraCode Nerd Font Mono**. If it shows a
   different font, set it explicitly and re-run `bin/doctor.sh`.
3. If it's still wrong, open **Font Book**, search for "Fira Code," and
   confirm a style named **FiraCodeNFM-Reg** (or similar) shows up and
   is enabled. If it's missing, reinstall the font:
   `brew install --cask font-fira-code-nerd-font`, then quit and reopen
   iTerm2.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Homebrew install hangs, errors, or is refused | Corporate/MDM policy blocks new software installs | File an IT ticket to approve Homebrew (or have IT install it for you), then re-run Step 2 and Step 4. |
| Glyphs show as boxes or question marks | Nerd Font not installed, or iTerm2 profile/font not selected | See "The glyph check" above. |
| "Anthropic" profile doesn't appear in iTerm2's Profiles list | The Dynamic Profile file wasn't copied (Step 4 didn't finish, or iTerm2's Application Support folder is locked down by MDM) | Run `bash "$(chezmoi source-path)/bin/doctor.sh"` and check the "iTerm2 Dynamic Profile" section for the exact fix, or manually run: `mkdir -p "$HOME/Library/Application Support/iTerm2/DynamicProfiles" && cp "$(chezmoi source-path)/iterm2/Anthropic.json" "$HOME/Library/Application Support/iTerm2/DynamicProfiles/Anthropic.json"`, then restart iTerm2. |
| `chezmoi apply` fails with a 1Password-related error | You answered `true` to the 1Password question, and something (a private overlay, or a future version of this repo) is calling `onepasswordRead` while the `op` CLI isn't signed in | Run `op signin` and re-run `chezmoi apply`, or run `chezmoi init` again and answer `false` if you don't need 1Password integration. As shipped today, nothing in this repo actually calls `onepasswordRead`, so this shouldn't come up unless you've added something yourself. |
| Your shell doesn't look like zsh, or `~/.zshrc` doesn't seem to apply | Your default shell isn't zsh (some managed Macs override this) | Check with `echo $SHELL` (expect `/bin/zsh`). If it's something else, run `chsh -s /bin/zsh` and open a new terminal. If that command is blocked by MDM, ask IT to set your default shell. |
| A command like `bat`, `fzf`, or `chezmoi` says "command not found" right after install | You're still in the old shell from before Homebrew/chezmoi was on `PATH` | Open a brand-new terminal window (not just a new tab in some setups), or run `exec zsh -l`. |
| Not sure what belongs in `~/.zshrc.local` | It's easy to confuse with the managed `~/.zshrc` | See "Making it yours" below. |

## Making it yours: `~/.zshrc.local`

`~/.zshrc.local` is yours. It's not part of this repo, chezmoi never
manages it, and `chezmoi apply` will never read, overwrite, or even look
at it. Your managed `~/.zshrc` sources it automatically, so anything you
put there takes effect in every new terminal.

It was created for you automatically the first time you ran
`chezmoi init --apply`, copied from `dot_zshrc_local.example` in this
repo. After that first copy, it's left alone permanently, edit it
however you like.

Use it for anything specific to you or this machine: work tools, personal
aliases, secrets, or things you're just trying out. A few examples:

```bash
# A simple alias
alias gs="git status"
```

```bash
# An environment variable
export MY_COMPANY_API_URL="https://api.example-work.com"
```

```bash
# A small function
greet() {
  echo "Hello, $1! It's $(date +'%A %H:%M')."
}
```

See `dot_zshrc_local.example` in this repo for a fuller starter template
with more worked examples.

## For AI agents

This section is a compact execution contract. Steps are numbered to
match the human-facing steps above. Run them in order.

**Hard rule: on any step marked "requires human" below, stop and ask a
human before proceeding. Do not guess, fabricate a name/email, click
through a GUI dialog on the agent's behalf, or assume an IT approval
that hasn't happened.**

| Step | Command | Verify (expect exit 0 unless noted) | Interactive? |
|---|---|---|---|
| 1. Xcode CLT | Check first: `xcode-select -p`. Only if that fails: `xcode-select --install` | `xcode-select -p` prints a path | **Requires human.** The install pops a GUI dialog and license the agent cannot click through. |
| 2. Homebrew | `NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"` | `command -v brew` | May require a human for the sudo password, unless the agent already has passwordless sudo. `NONINTERACTIVE=1` is documented, official Homebrew installer behavior (verified against the installer script), not something this repo adds. |
| 2b. shellenv | `if [ -d /opt/homebrew ]; then eval "$(/opt/homebrew/bin/brew shellenv)"; else eval "$(/usr/local/bin/brew shellenv)"; fi` | `command -v brew` | No. |
| 3. chezmoi | `brew install chezmoi` | `command -v chezmoi` | No. |
| 4. `chezmoi init --apply` | See below. | `test -f "$HOME/.zshrc" && test -f "$HOME/.claude/themes/anthropic.json"` | **Requires human for the answers** (see below). Homebrew package failures inside this step are non-fatal by design; collect them and report to the human rather than retrying blindly. |
| 5. Restart shell | `exec zsh -l` (or open a fresh shell for subsequent commands) | `[ "$ZSH_CUSTOM" = "$HOME/.oh-my-zsh-custom" ]` | No. |
| 6. iTerm2 profile selection | None (GUI-only). | N/A | **Requires human.** No CLI can select an iTerm2 profile as active/default. |
| 7. Claude theme | (already set in step 4) | `[ "$(jq -r '.theme' "$HOME/.claude/settings.json")" = "custom:anthropic" ]` | No. |
| 8. doctor.sh | `bash "$(chezmoi source-path)/bin/doctor.sh"` | exit code `0` | The script itself is non-interactive, but its "Glyph rendering test" section requires a **human** to look at the output and judge it (see below). |

### Driving `chezmoi init` non-interactively

By default, `chezmoi init` reads its four questions from the terminal
and will hang waiting for input if run with no human attached. This was
verified against the installed `chezmoi` binary (v2.72.2) and the
upstream `init` command reference: `chezmoi init` supports
`--promptString` and `--promptBool` flags that take *exact prompt
text* as the key.

**Do not fabricate a name or email.** Those are personal data belonging
to the person this machine is for. Stop and ask a human for:

- their full name
- their email address
- confirmation that profile should be `shared` (it should be, for any
  machine that isn't Michael's own, but confirm rather than assume)
- whether they want 1Password integration (`true`/`false`); default to
  `false` if they're unsure, per the prompt's own wording

Once you have all four answers, re-read `.chezmoi.toml.tmpl` immediately
before building the command. The `--promptString`/`--promptBool` keys
must match that file's prompt text **exactly, character for character**;
if a maintainer edits the wording, this command silently breaks (chezmoi
just prompts interactively for the mismatched one instead of erroring,
which will still hang a non-interactive agent). Do not reuse a cached
copy of the prompt text from an earlier session.

```bash
chezmoi init --apply \
  --promptString "Your full name (used for git commit authorship)=FULL_NAME,Your email address (used for git commit authorship)=EMAIL_ADDRESS,Which profile is this? Type 'michael' for Michael's machine or 'shared' for anyone else (e.g. a spouse's laptop)=shared" \
  --promptBool "Do you use 1Password and want this setup to read secrets from it? Type true or false - if unsure, type false (you can turn this on later)=false" \
  https://github.com/mlaccetti/dotfiles-core
```

Replace `FULL_NAME` and `EMAIL_ADDRESS` with the human's actual answers.
If either answer, once substituted, could contain a literal comma, the
`stringToString` flag parsing will misparse it, if that happens, fall
back to asking the human to run `chezmoi init` themselves interactively.

### Steps that need a human, summarized

- **Step 1**, if the Xcode Command Line Tools aren't already installed
  (GUI dialog and license).
- **Step 2**, if Homebrew needs a sudo password the agent doesn't have.
- **Step 4**, for the name, email, and profile confirmation (never
  invent these).
- **Step 6**, entirely (iTerm2 profile selection is GUI-only).
- **Step 8's glyph section**, for visual confirmation that the Nerd Font
  glyphs render correctly rather than as tofu boxes.
- Any Homebrew package in Step 4 that fails because it needs IT/MDM
  approval: report which package and why, don't retry it yourself.
