# Setup

## What this gets you

Once this is done, you'll be able to open a terminal window, type a
plain-English request to Claude Code, and have it do the work. A few
examples of what that looks like once everything below is connected:

- "Summarize the open Linear issues in the Onboarding project and tell me
  which ones are blocked."
- "Draft a Confluence page from these meeting notes and put it in the
  Product space."
- "Look up the Acme Corp account in Salesforce and tell me when their
  contract renews."
- "Build me a small internal dashboard that shows this week's signups,
  and put it somewhere I can share a link to."

Claude does the typing, clicking, and API calls. You describe what you
want in your own words. The rest of this document is the one-time setup
to make that possible, plus a themed terminal so it's pleasant to look
at while you work.

## Ask for these first

Three things here need someone else to act, not you. None of them block
the rest of this guide, so start these now and keep going; they can
finish in the background while you work through the steps below.

### 1. Ask your Atlassian admin to enable MCP access

Confluence and Jira don't have a plain command-line tool, so this setup
connects to them through Atlassian's own "Remote MCP" server instead.
That has to be turned on for your organization by whoever administers
your Atlassian/Jira account. Send them this:

> Hi, I'd like to use Claude Code with our Atlassian (Confluence/Jira)
> account. Could you confirm that Atlassian's Remote MCP server (Rovo) is
> enabled for our organization? Once it is, I'll connect from my own
> laptop with `claude mcp add --transport http atlassian
> https://mcp.atlassian.com/v2/mcp` and sign in with my own login, so no
> credentials need to be shared with me directly.

### 2. Ask your Salesforce admin whether hosted MCP applies to you (optional)

You can query Salesforce today with a command-line tool no matter what
edition your org is on (see Step 12 below). Salesforce also offers a
more capable "Hosted MCP" server, but it currently requires Enterprise
Edition or higher. It's worth asking now so you know which path you're
on:

> Hi, I'd like to connect Claude Code to our Salesforce org. Do we have
> Enterprise Edition or higher? If so, is Salesforce's Hosted MCP Server
> available for our org? If not, I'll use the standard `sf` command-line
> tool instead, which works on any edition.

### 3. Ask IT to confirm browser sign-in (SSO) is allowed for these tools

Several of the connections below work by opening a browser window and
having you log in normally (this is called OAuth, it's the same kind of
"sign in with your company account" flow you already use for other
apps). On some company laptops, security software blocks this kind of
sign-in for new tools until it's allow-listed. Send this before you hit
Step 9:

> Hi, I'm setting up Claude Code to connect to Linear, Atlassian, GitHub,
> Netlify, and Salesforce using each service's official sign-in flow (the
> same "log in with your company account" popup you'd see anywhere
> else). Could you confirm our SSO/security policy allows browser-based
> sign-in for these, or let me know if any of them need to be
> allow-listed first?

## Before you start

### What "the terminal" is, for anyone who's never used one

The Terminal (or, on this setup, **iTerm2**) is an app where you type
commands instead of clicking buttons, and it prints text back at you.
That's it. There's no hidden danger in typing a command; it does exactly
what it says, nothing more.

A few things that'll make the rest of this less unfamiliar:

- A gray box below like the one under this paragraph is a **command**.
  Every one of them in this guide has its own **Run** button; click it
  (or copy the text into your terminal and press Return) to execute it.
- After you run a command, text usually scrolls by. That's normal, it's
  the program telling you what it's doing. You don't need to read all of
  it unless something says "FAIL" or "error."
- If a command finishes and just gives you your prompt back with no
  error, that almost always means it worked. Silence is success, not a
  sign that something's stuck.
- Commands are case-sensitive and space-sensitive. If you're typing
  instead of clicking Run, copy them exactly.

```bash
echo "This is a command. Running it just prints this sentence back to you."
```

**You should see:** the same sentence printed back, then your prompt
again. That's the whole loop you'll repeat for the rest of this guide.

### macOS and admin rights

This expects a reasonably current macOS with `zsh` as the default shell
(that's been the default since macOS Catalina, but a managed work laptop
can override it, so it's worth checking, see Troubleshooting below).

You will need your account's admin password (or an admin nearby) for:

- Installing Homebrew (it creates directories under `/opt/homebrew` or
  `/usr/local` and needs permission to do that once).
- Any Homebrew "cask" (GUI app) that shows a Gatekeeper/security prompt on
  first install.

### IT / MDM heads-up

If this is a company-managed ("MDM") Mac, skim this list **before you
start** so you can file one IT ticket instead of five. Each of these can
be blocked or need approval on a locked-down fleet:

- Installing Homebrew itself.
- Installing the Nerd Font used for terminal icons.
- Installing iTerm2.
- Installing the 1Password and 1Password CLI casks (many companies push
  their own managed build of 1Password already; a second copy can
  conflict).
- Installing the Slack cask (same reasoning: often already pushed by IT).

None of this stops the rest of the setup. The scripts are written to log
a clear "needs IT approval" message for anything blocked and keep going,
so you'll still end up with a working shell and terminal even if a few
apps are missing. You can install those later once IT signs off.

### Time estimate

30 to 60 minutes if everything installs cleanly, plus however long the
service connections in Steps 9 to 12 take (each is a couple of minutes
once you're signed in). Add time if you're waiting on one of the "ask
first" items above, most of that is waiting, not active work.

## Setup steps

Each step below is self-contained and safe to re-run. If something
fails, fix the specific thing called out in "if this fails," then re-run
that same step. You don't need to start over.

### Step 1: Install the Xcode Command Line Tools

This is a small set of developer tools Apple ships that a few things
below rely on quietly in the background. You'll never interact with it
directly.

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

Homebrew is the tool that installs everything else in this guide. Think
of it as an app store you run from the terminal.

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
else in this repo: it downloads the config files and runs the install
steps in the right order.

```bash
brew install chezmoi
```

**You should see:** Homebrew download and install a `chezmoi` formula,
ending in something like "chezmoi was successfully installed."

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
Dynamic Profiles folder. iTerm2 has to be told to actually use it; this
part is a menu, not a command, so there's nothing to click Run on here.

```bash
killall iTerm2 2>/dev/null; open -a iTerm
```

**You should see:** iTerm2 quit and reopen.

Now select the profile manually, through the menus, step by step:

1. Click the **iTerm2** menu at the top of the screen, then **Settings**
   (older versions call this **Preferences**), then **Profiles**.
2. Click **Anthropic** in the list of profiles on the left.
3. To make it the default for every new window: click the small gear
   icon ("Other Actions") at the bottom of that list, then choose
   **Set as Default**.

That gear-icon step is the one that matters: without it, this profile
only applies to windows you switch by hand. There's no command that can
do this for you; it's a one-time menu click.

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
the one check you have to eyeball yourself; the script can't verify it
for you.

**Correct:** the separators look like solid triangular arrows connecting
one color block to the next (like the segments in your prompt), the icon
row shows small recognizable pictures (a cloud, a folder, and so on, not
letters or symbols you don't recognize), and the emoji row shows actual
color emoji (a rocket, a checkmark, etc.).

**Broken ("tofu"):** any of those instead show up as a small hollow
rectangle, or a question mark inside a diamond. Terminal people call
that a "tofu box." It means the terminal isn't actually using the font
this setup installed, even if that font is technically present
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

## Connecting Claude Code to your tools

Everything up to here has been scaffolding, a nice terminal and shell.
This section is the actual point: connecting Claude Code to the places
you do your work, so it can act on your behalf instead of just chatting.

Each one below is a service Claude Code talks to over what's called an
"MCP server," which is just a standard way for Claude to securely read
and act on a service using your own login. You sign in once per service,
normally, in a browser window. Claude never sees your password.

### Step 9: Connect Claude Code to Linear

```bash
claude mcp add --transport http linear-server https://mcp.linear.app/mcp
```

**You should see:** Claude Code print a confirmation that the server
was added, then open (or ask you to open) a browser window to log in to
Linear normally. Approve access there.

**If this fails:** if the browser window never opens or the sign-in is
blocked, that's the SSO issue from "Ask for these first" above; check
with IT. If Claude Code says the command isn't recognized, open a new
terminal window (Claude Code was installed in Step 4).

### Step 10: Connect Claude Code to Confluence and Jira

This uses Atlassian's own official connector. It only works once your
Atlassian admin has enabled it, which is the first "ask for these first"
item above.

```bash
claude mcp add --transport http atlassian https://mcp.atlassian.com/v2/mcp
```

**You should see:** the same pattern as Step 9: a confirmation, then a
browser sign-in to your Atlassian account.

**If this fails:** an error mentioning access being disabled usually
means your admin hasn't enabled Rovo/MCP yet; that's the email from
"Ask for these first," item 1. A sign-in that never completes is
usually the SSO issue from item 3.

### Step 11: Connect Claude Code to Salesforce (optional)

Salesforce has a command-line tool that works on any org edition. Skip
this step entirely if you don't use Salesforce.

```bash
npm install -g @salesforce/cli
```

**You should see:** npm download and install the `sf` command. Confirm
it worked with `sf --version`.

**If this fails:** if `npm` itself isn't found, this laptop doesn't have
Node.js installed yet; ask in your team's Claude Code channel, since
that's normally set up per-project by `mise` rather than here.

Then log in:

```bash
sf org login web
```

**You should see:** a browser window asking you to log in to Salesforce.
After you approve it, the terminal prints which org you're now connected
to.

**If this fails:** a sign-in that never completes is the SSO issue from
"Ask for these first," item 3. If your org turned out to have Enterprise
Edition or higher (item 2), ask whether Salesforce's Hosted MCP Server is
a better fit than this CLI; either way, Claude Code can use whichever
one is connected.

### Step 12: Connect Claude Code to GitHub and Netlify

These cover the other two things in your actual goal: automating git
(opening pull requests, checking status) and deploying small webapps
Claude builds for you.

```bash
gh auth login
```

**You should see:** a prompt asking how you want to authenticate; choose
"Login with a web browser" and follow along. It ends with "Logged in as
your-username."

**If this fails:** the same SSO note applies if your company's GitHub is
behind SSO approval; you may need to authorize the token for your
organization afterward on GitHub's own website.

```bash
netlify login
```

**You should see:** a browser window opens for you to log in to (or
create) a Netlify account, then the terminal confirms you're logged in.

**If this fails:** if `netlify` isn't found, re-run
`brew bundle --file="$(chezmoi source-path)/Brewfile"` to pick up
`netlify-cli`, then open a new terminal.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Homebrew install hangs, errors, or is refused | Corporate/MDM policy blocks new software installs | File an IT ticket to approve Homebrew (or have IT install it for you), then re-run Step 2 and Step 4. |
| Glyphs show as boxes or question marks | Nerd Font not installed, or iTerm2 profile/font not selected | See "The glyph check" above. |
| "Anthropic" profile doesn't appear in iTerm2's Profiles list | The Dynamic Profile file wasn't copied (Step 4 didn't finish, or iTerm2's Application Support folder is locked down by MDM) | Run `bash "$(chezmoi source-path)/bin/doctor.sh"` and check the "iTerm2 Dynamic Profile" section for the exact fix, or manually run: `mkdir -p "$HOME/Library/Application Support/iTerm2/DynamicProfiles" && cp "$(chezmoi source-path)/iterm2/Anthropic.json" "$HOME/Library/Application Support/iTerm2/DynamicProfiles/Anthropic.json"`, then restart iTerm2. |
| `chezmoi apply` fails with a 1Password-related error | You answered `true` to the 1Password question, and something (a private overlay, or a future version of this repo) is calling `onepasswordRead` while the `op` CLI isn't signed in | Run `op signin` and re-run `chezmoi apply`, or run `chezmoi init` again and answer `false` if you don't need 1Password integration. As shipped today, nothing in this repo actually calls `onepasswordRead`, so this shouldn't come up unless you've added something yourself. |
| Your shell doesn't look like zsh, or `~/.zshrc` doesn't seem to apply | Your default shell isn't zsh (some managed Macs override this) | Check with `echo $SHELL` (expect `/bin/zsh`). If it's something else, run `chsh -s /bin/zsh` and open a new terminal. If that command is blocked by MDM, ask IT to set your default shell. |
| A command like `bat`, `fzf`, or `chezmoi` says "command not found" right after install | You're still in the old shell from before Homebrew/chezmoi was on `PATH` | Open a brand-new terminal window (not just a new tab in some setups), or run `exec zsh -l`. |
| A browser sign-in window never opens, or opens and then errors | Corporate SSO or security software is blocking it | This is the item 3 "ask first" issue; confirm with IT that browser-based sign-in is allowed for the specific tool. |
| Not sure what belongs in `~/.zshrc.local` | It's easy to confuse with the managed `~/.zshrc` | See "Making it yours" below. |

## Making it yours: `~/.zshrc.local`

`~/.zshrc.local` is yours. It's not part of this repo, chezmoi never
manages it, and `chezmoi apply` will never read, overwrite, or even look
at it. Your managed `~/.zshrc` sources it automatically, so anything you
put there takes effect in every new terminal.

It was created for you automatically the first time you ran
`chezmoi init --apply`, copied from `dot_zshrc_local.example` in this
repo. After that first copy, it's left alone permanently; edit it
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

## What now

Start Claude Code from any terminal window by running:

```bash
claude
```

Once it's open, check that the services you connected in Steps 9 to 12
are actually reachable:

```bash
claude mcp list
```

**You should see:** each server you added (`linear-server`, `atlassian`,
and so on) marked as connected. If one shows an error instead, re-run
its "connect" step above.

From there, just describe what you want in your own words, the way the
examples at the top of this document did. If you get stuck on anything
in this guide, `bin/doctor.sh` (Step 8) is always safe to re-run and
will point at whatever's actually broken.

If you're running Claude Code itself to drive this setup rather than
doing it by hand, see [`SETUP-agent.md`](./SETUP-agent.md) for a
machine-readable version of these steps.
