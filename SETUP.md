# Setup

## What this gets you

Once this is done, you'll be able to open a terminal window, type a
plain-English request to Claude Code, and have it do the work. A few
examples of what that looks like once everything below is connected:

- "Summarize the open Linear issues in the Onboarding project and tell me
  which ones are blocked."
- "Draft a Confluence page from these meeting notes and put it in the
  Product space."
- "Build a small dashboard for this week's signups, following the
  deployment steps on the Deploying page in Confluence."

Claude does the typing, clicking, and API calls. You describe what you
want in your own words. The rest of this document is the one-time setup
to make that possible, plus a themed terminal so it's pleasant to look
at while you work.

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
(that's been the default since macOS Catalina, but a Mac set up by
someone else can use a different shell, so it's worth checking, see
Troubleshooting below).

You will need the password for your Mac's administrator account for:

- Installing Homebrew (it creates directories under `/opt/homebrew` or
  `/usr/local` and needs permission to do that once).
- Any Homebrew "cask" (GUI app) that shows a Gatekeeper/security prompt on
  first install.

### If an install is blocked

Some Macs restrict which software can be installed. If any install in
this guide is blocked on yours, ask whoever manages your Mac to approve
it. These are the installs most likely to be restricted:

- Homebrew itself.
- The Nerd Font used for terminal icons.
- iTerm2.
- The 1Password and 1Password CLI casks (a second copy can conflict if
  1Password is already installed another way).
- The Slack cask (same reasoning).

Apps that are already on the Mac (iTerm2, 1Password, and so on) are
detected and left alone rather than reinstalled, so an existing copy
won't be touched.

None of this stops the rest of the setup. The scripts log a clear
message for anything blocked and keep going, so you'll still end up with
a working shell and terminal even if a few apps are missing. You can
install those later once they're approved.

### Time estimate

30 to 60 minutes if everything installs cleanly, plus however long the
service connections in Steps 9 to 13 take (each is a couple of minutes
once you're signed in).

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

**If this fails:** if it errors out or hangs asking for permissions you
don't have, stop here and see Troubleshooting. This is the install most
likely to be blocked on a Mac that restricts software.

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

This is the main step. It asks three short questions, then installs the
Homebrew packages, applies all the dotfiles, and configures iTerm2 and
Claude Code. It also installs two small commands, `claude-gw-setup` and
`claude-gw`, which you'll only use in Step 10 if you use an LLM gateway.

```bash
chezmoi init --apply https://github.com/mlaccetti/dotfiles-core
```

You'll be asked three questions, in this exact order. Here's what each one
means and what to type:

1. **`Your full name (used for git commit authorship)`**
   Type your name, e.g. `Jane Doe`.

2. **`Your email address (used for git commit authorship)`**
   Type the email you want associated with your commits.

   > Note: these two answers do get written to your global git config
   > automatically during `chezmoi apply`, but only for whichever of
   > name and email you don't already have set. If your Mac already has
   > a git identity configured, this deliberately won't overwrite it.
   > Once setup finishes, check what you actually ended up with:
   > `git config --global user.name` and
   > `git config --global user.email`. If either isn't what you want,
   > set it yourself:
   > `git config --global user.name "Your Name"` and
   > `git config --global user.email "you@example.com"`.

3. **`Do you use 1Password and want this setup to read secrets from it? Type true or false - if unsure, type false (you can turn this on later)`**
   Type `false` unless you already use the 1Password CLI (`op`) and know
   you want chezmoi to read secrets from it. You can change your mind
   later by running `chezmoi init` again.

   Note: this only affects whether chezmoi is configured to *talk* to
   1Password later. The 1Password app and its command-line tool still
   get installed by Homebrew in the next part of this step either way
   (see "If an install is blocked" above).

**You should see:** after the three questions, a long stream of output:
Homebrew installing/checking packages (this is the slowest part, several
minutes; if some of the apps are already on the Mac, it prints an
"Already installed, leaving as is" line naming them and skips them, and
it never installs a second Claude Code if a `claude` command already
works), a check for `~/.oh-my-zsh` (safe to ignore on a brand-new
machine), then chezmoi writing your dotfiles, then notes about the
iTerm2 profile (and whether it could be set as iTerm2's default) and
Claude Code theme being installed. It also installs Node.js (and its
`npm` command) automatically through `mise`, which many small web apps
rely on.

**If this fails:**
- If a specific Homebrew formula or cask fails partway through, that's
  possible if your Mac restricts installs (see "If an install is
  blocked" above). The script keeps going; note which package failed and
  either get it approved or ignore it for now. `bin/doctor.sh` (Step 8) will tell you what's still
  missing.
- You can safely re-run `chezmoi init --apply https://github.com/mlaccetti/dotfiles-core`
  at any time. It re-asks the three questions and rewrites chezmoi's own
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

### Step 6: Confirm the iTerm2 profile is the default

`chezmoi apply` already copied the Anthropic color profile into iTerm2's
Dynamic Profiles folder, and it also tries to make Anthropic iTerm2's
default profile for you. It can only do that if iTerm2 was **not
running** during setup: iTerm2 saves its preferences when it quits, so a
setting written while it is open would be overwritten. (The setup script
never quits iTerm2 for you.)

Check whether it worked:

```bash
defaults read com.googlecode.iterm2 "Default Bookmark Guid"
```

**You should see:** `67AF76AE-1E09-5AC8-966F-6B27A069454B`, which is the
Anthropic profile's ID. Open a new iTerm2 window: it should be themed
with the Anthropic colors.

**If you see a different ID (or an error), or iTerm2 was open during
setup:** the automatic step was skipped, and you only need to do the
manual steps below. They work while iTerm2 is open. This part is a menu,
not a command, so there's nothing to click Run on here.

1. Click the **iTerm2** menu at the top of the screen, then **Settings**
   (older versions call this **Preferences**), then **Profiles**.
2. Click **Anthropic** in the list of profiles on the left.
3. To make it the default for every new window: click the small gear
   icon ("Other Actions") at the bottom of that list, then choose
   **Set as Default**.

That gear-icon step is the one that matters: without it, this profile
only applies to windows you switch by hand.

Alternatively, quit iTerm2 (**iTerm2** menu, then **Quit iTerm2**),
reopen it, and re-run the setup script, which will now set the default
by itself:

```bash
bash "$(chezmoi source-path)/run_once_after_10-install-iterm2-profile.sh"
```

Step 8's `doctor.sh` also checks this and prints a warning (not a
failure) if Anthropic is not the default profile.

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
This section is the actual point: signing in to Claude Code and
connecting it to the places you do your work, so it can act on your
behalf instead of just chatting.

Claude Code itself needs a login (Step 9). Each service after that is
something Claude Code talks to over what's called an "MCP
server," which is just a standard way for Claude to securely read and
act on a service using your own login. You sign in once per service,
normally, in a browser window. Claude never sees your password.

### Step 9: Sign in to Claude Code

Sign in with the account you use for Claude (Pro, Max, Team, or
Enterprise). You'll sign in once here. After that, plain `claude` uses it
every time.

The first time you run `claude`, macOS may show a dialog saying it
can't verify the app. That's expected for software installed outside the
App Store, it doesn't mean anything is wrong. Click **Open** or **Open
Anyway**. If the dialog doesn't offer that button, open **System
Settings > Privacy & Security**, scroll down, and click **Open Anyway**
next to the message about `claude`. This is a one time thing on this
computer; future Claude Code updates will not ask again.

```bash
claude
```

**You should see:** Claude Code ask how you want to log in.

1. Choose the **Claude account** option (the one that mentions Pro, Max,
   Team, or Enterprise). Do **not** choose the Console / API key option.
2. A browser window opens. Sign in with the account you use for Claude.
   If that account uses single sign-on (SSO), you may land on its
   normal login page.
3. Go back to the terminal. Answer any other first-time questions (like
   the color theme or trusting the folder) with the suggested default.

Once you see the Claude Code prompt, you're signed in. Type `/exit` to
leave for now.

**If this fails:** if the browser window never opens or the sign-in is
blocked, ask whoever manages your Mac whether browser sign-in is allowed
for Claude Code. If it says your account has no access, check that your
Claude plan includes Claude Code. If you picked the Console option by
mistake, type `/logout` (this is fine in plain `claude`, just never in
`claude-gw`), then run `claude` again and choose the Claude account
option. If Claude Code says the command isn't recognized, open a new
terminal window (Claude Code was installed in Step 4).

### Step 10 (optional): Set up an LLM gateway

Skip this step if you don't use an LLM gateway. If you do, you set it up
once, and then `claude-gw` uses it. You need the gateway address and
your gateway token from whoever runs your gateway. Ask them for the
model names too, if the gateway needs specific ones. Have these ready.
Ask for the token through a password manager or another secure channel,
not plain chat or email.

```bash
claude-gw-setup
```

It asks you a few questions:

1. **Gateway address.** Paste the address that starts with `https://`.
2. **Gateway token.** Paste your token. Nothing appears on screen while
   you paste or type it. That's on purpose, so nobody looking over your
   shoulder can read it. Press Return when you're done.
3. **Does the gateway need specific model names?** Type `n` unless
   whoever gave you the gateway told you it uses its own model names. If
   they did, type `y` and enter the Opus, Sonnet, and Haiku names you
   were given (press Return to skip one you weren't given).
4. **Test the connection now?** Press Return to say yes. It sends one
   tiny test request to the gateway.

**You should see:** "The gateway answered (HTTP ...), so the address and
token work," then "All set." Your token is saved in a private file only
your account can read (`~/.config/claude-gw/`). It is never written into
your regular Claude Code settings.

**If this fails:**
- "command not found": run `chezmoi apply` to install the commands, then
  open a new terminal window.
- "The gateway rejected the token": the token was mistyped, or it isn't
  valid. Get it again from whoever runs the gateway and re-run
  `claude-gw-setup`. It's safe to re-run at any time.
- "couldn't reach": check the address, and check that you're on the
  network or VPN the gateway needs, if any.
- If Claude Code won't let you use both sign-in methods, a setting such
  as `forceLoginMethod` may be locking it to one. Whoever manages your
  Claude Code settings can change that.

#### Which one to use: `claude` or `claude-gw`

Use `claude` for your Claude account. Use `claude-gw` when you want the
gateway instead. It takes the same commands but signs in with your saved
gateway token, so some Claude.ai features, like apps connected on the
Claude website, won't appear there.

```bash
claude-gw
```

> **Never type `/logout` inside `claude-gw`.** It can sign you out of
> your Claude account, and you'd have to sign in again with `claude`. If
> a gateway session shows a warning about a saved login, ignore it and do
> not log out.

Other things that work differently in `claude-gw`:

- Usage is billed to the gateway, not to your Claude plan.
- Your Linear and Atlassian connections (Steps 11 and 12) work in both,
  because they're added with `--scope user`. Anything connected only
  through the Claude website appears only in plain `claude`.
- Settings that come from your Claude account may not apply.
- Remote control and voice don't work.

Switching is just typing the other name. Nothing to undo: your Claude
sign-in stays saved while you use the gateway.

### Step 11: Connect Claude Code to Linear

This connects Claude Code to Linear.

```bash
claude mcp add --transport http linear-server --scope user https://mcp.linear.app/mcp
```

The `--scope user` part matters. It makes the connection available no
matter which folder you open Claude Code in, and in both `claude` and
`claude-gw`. Without it, Claude Code saves the connection only for the
folder you were in when you ran the command, and it seems to disappear
everywhere else.

**You should see:** Claude Code print a confirmation that the server
was added. It isn't signed in yet, which is the next part.

To sign in, start `claude` (plain `claude`, not `claude-gw`):

```bash
claude
```

Then type `/mcp`, choose **linear-server**, and follow the steps in the
browser window that opens to log in to Linear normally. Approve access
there. When it's done, `/mcp` shows Linear as connected. Type `/exit`
to leave.

**If this fails:** if the browser window never opens or the sign-in is
blocked, ask whoever manages your Mac whether browser sign-in is allowed.
If the browser doesn't open by itself, copy the web address Claude Code
shows and open it yourself.

### Step 12: Connect Claude Code to Confluence and Jira

This uses Atlassian's own official connector. It only works once
Atlassian's Remote MCP server (Rovo) is turned on for your Atlassian
site. If you're not sure it is, ask whoever administers your Atlassian
site.

```bash
claude mcp add --transport http atlassian --scope user https://mcp.atlassian.com/v2/mcp
```

**You should see:** a confirmation that the server was added. Then sign
in the same way as Step 11: run `claude`, type `/mcp`, choose
**atlassian**, and follow the steps in the browser to log in to your
Atlassian account.

**If this fails:** an error mentioning access being disabled usually
means Rovo/MCP isn't turned on for your Atlassian site yet. Ask whoever
administers the site to enable Atlassian's Remote MCP server. A sign-in
that never completes is usually browser sign-in being blocked on your
Mac.

### Step 13: Connect Claude Code to GitHub

This covers automating git: opening pull requests, checking status, and
so on.

```bash
gh auth login
```

**You should see:** a prompt asking how you want to authenticate; choose
"Login with a web browser" and follow along. It ends with "Logged in as
your-username."

**If this fails:** if your GitHub access goes through single sign-on
(SSO), you may need to authorize the login for it afterward, on GitHub's
own website.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Homebrew install hangs, errors, or is refused | Your Mac restricts installing new software | Ask whoever manages your Mac to approve Homebrew (or install it for you), then re-run Step 2 and Step 4. |
| Glyphs show as boxes or question marks | Nerd Font not installed, or iTerm2 profile/font not selected | See "The glyph check" above. |
| "Anthropic" profile doesn't appear in iTerm2's Profiles list | The Dynamic Profile file wasn't copied (Step 4 didn't finish, or iTerm2's Application Support folder isn't writable) | Run `bash "$(chezmoi source-path)/bin/doctor.sh"` and check the "iTerm2 Dynamic Profile" section for the exact fix, or manually run: `mkdir -p "$HOME/Library/Application Support/iTerm2/DynamicProfiles" && cp "$(chezmoi source-path)/iterm2/Anthropic.json" "$HOME/Library/Application Support/iTerm2/DynamicProfiles/Anthropic.json"`, then restart iTerm2. |
| `chezmoi apply` fails with a 1Password-related error | You answered `true` to the 1Password question, and something (a private overlay, or a future version of this repo) is calling `onepasswordRead` while the `op` CLI isn't signed in | Run `op signin` and re-run `chezmoi apply`, or run `chezmoi init` again and answer `false` if you don't need 1Password integration. As shipped today, nothing in this repo actually calls `onepasswordRead`, so this shouldn't come up unless you've added something yourself. |
| Your shell doesn't look like zsh, or `~/.zshrc` doesn't seem to apply | Your default shell isn't zsh (a Mac set up by someone else can use a different one) | Check with `echo $SHELL` (expect `/bin/zsh`). If it's something else, run `chsh -s /bin/zsh` and open a new terminal. If that command is blocked, ask whoever manages your Mac to set your default shell. |
| A command like `bat`, `fzf`, or `chezmoi` says "command not found" right after install | You're still in the old shell from before Homebrew/chezmoi was on `PATH` | Open a brand-new terminal window (not just a new tab in some setups), or run `exec zsh -l`. |
| `claude` produces no output and never finishes (looks frozen) | macOS Gatekeeper is waiting on a security confirmation, possibly behind another window | Look for the dialog (check other windows and **System Settings > Privacy & Security**), approve it, then try again. Pressing Ctrl+C to cancel is safe. |
| A browser sign-in window never opens, or opens and then errors | Single sign-on or security software is blocking it | Ask whoever manages your Mac (or the service you're signing in to) whether browser-based sign-in is allowed for that tool. |
| `claude-gw` says "Run claude-gw-setup first." | The gateway hasn't been set up on this computer yet, or its saved settings were deleted | Run `claude-gw-setup` (Step 10). You'll need the gateway address and token from whoever runs the gateway. |
| The gateway rejects your token ("401", "unauthorized", or "invalid API key") | The saved token is wrong, expired, or was revoked | Get a fresh token from whoever runs the gateway, then run `claude-gw-setup` again and paste it in. |
| A "model not found" (or similar) error in `claude-gw` | The gateway uses its own model names | Ask whoever runs the gateway for its Opus, Sonnet, and Haiku model names, then run `claude-gw-setup` again and answer `y` to the model names question. |
| Your Claude login seems gone after using the gateway (plain `claude` asks you to log in again) | You probably typed `/logout` inside `claude-gw`, which signs you out of your Claude account | Run `claude` and sign in again with your Claude account (Step 9). Then use `claude-gw` without `/logout`. |
| `node` or `npm` says "command not found" | Node.js didn't finish installing in Step 4 (often a network problem) | Run `mise install`, then open a new terminal window and try again. |
| Linear or Atlassian works in one folder but is missing in another | It was added without `--scope user`, so it was saved only for that one folder | Run the connect command again from Step 11 or 12, with `--scope user` as written there. |
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

Use it for anything specific to you or this machine: extra tools,
personal aliases, secrets, or things you're just trying out. A few examples:

```bash
# A simple alias
alias gs="git status"
```

```bash
# An environment variable
export MY_API_URL="https://api.example.com"
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

That uses your Claude account. If you set up an LLM gateway in Step 10,
run `claude-gw` to use it instead (and remember: never type `/logout`
inside it).

Once you're back at a normal terminal prompt, check that the services
you connected in Steps 11 to 13 are actually reachable:

```bash
claude mcp list
```

**You should see:** each server you added (`linear-server`, `atlassian`,
and so on) marked as connected. If one says it needs authentication,
run `claude`, type `/mcp`, choose that server, and follow the browser
sign-in. If one shows an error instead, re-run its "connect" step above.

From there, just describe what you want in your own words, the way the
examples at the top of this document did. If you get stuck on anything
in this guide, `bin/doctor.sh` (Step 8) is always safe to re-run and
will point at whatever's actually broken.

If you're running Claude Code itself to drive this setup rather than
doing it by hand, see [`SETUP-agent.md`](./SETUP-agent.md) for a
machine-readable version of these steps.
