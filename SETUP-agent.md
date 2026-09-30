# Setup: machine-readable contract for AI agents

This is a compact execution contract for an AI coding agent running this
setup on someone's behalf. It exists so an agent doesn't have to parse
the prose in [`SETUP.md`](./SETUP.md), written for a non-technical human.
Steps are numbered to match that document. Run them in order.

**Hard rule: on any step marked "requires human" below, stop and ask a
human before proceeding. Do not guess, fabricate a name/email, click
through a GUI dialog on the agent's behalf, assume an IT approval that
hasn't happened, or invent a Salesforce/Atlassian/Linear organization
detail.**

| Step | Command | Verify (expect exit 0 unless noted) | Interactive? |
|---|---|---|---|
| 1. Xcode CLT | Check first: `xcode-select -p`. Only if that fails: `xcode-select --install` | `xcode-select -p` prints a path | **Requires human.** The install pops a GUI dialog and license the agent cannot click through. |
| 2. Homebrew | `NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"` | `command -v brew` | May require a human for the sudo password, unless the agent already has passwordless sudo. `NONINTERACTIVE=1` is documented, official Homebrew installer behavior (verified against the installer script), not something this repo adds. |
| 2b. shellenv | `if [ -d /opt/homebrew ]; then eval "$(/opt/homebrew/bin/brew shellenv)"; else eval "$(/usr/local/bin/brew shellenv)"; fi` | `command -v brew` | No. |
| 3. chezmoi | `brew install chezmoi` | `command -v chezmoi` | No. |
| 4. `chezmoi init --apply` | See below. | `test -f "$HOME/.zshrc" && test -f "$HOME/.claude/themes/anthropic.json"` | **Requires human for the answers** (see below). Homebrew package failures inside this step are non-fatal by design; collect them and report to the human rather than retrying blindly. |
| 5. Restart shell | `exec zsh -l` (or open a fresh shell for subsequent commands) | `[ "$ZSH_CUSTOM" = "$HOME/.oh-my-zsh-custom" ]` | No. |
| 6. iTerm2 default profile | Nothing to run: step 4's `run_once_after_10-install-iterm2-profile.sh` sets it automatically. Check with `pgrep -x iTerm2` first. **Never quit or kill iTerm2.** If iTerm2 is not running, it is already done; to retry: `bash "$(chezmoi source-path)/run_once_after_10-install-iterm2-profile.sh"`. | `[ "$(defaults read com.googlecode.iterm2 "Default Bookmark Guid")" = "$(jq -r '.Profiles[0].Guid' "$(chezmoi source-path)/iterm2/Anthropic.json")" ]` | **No, if iTerm2 was not running** during step 4 (the default is set for you). **Requires human if iTerm2 was open**: the script skips the write because iTerm2 would overwrite it on quit, and the agent must not quit the app. The human then quits and reopens iTerm2 and you re-run the script, or they use iTerm2 > Settings > Profiles > Anthropic > Other Actions > Set as Default. |
| 7. Claude theme | (already set in step 4) | `[ "$(jq -r '.theme' "$HOME/.claude/settings.json")" = "custom:anthropic" ]` | No. |
| 8. doctor.sh | `bash "$(chezmoi source-path)/bin/doctor.sh"` | exit code `0` | The script itself is non-interactive, but its "Glyph rendering test" section requires a **human** to look at the output and judge it (see below). See the caveat below: this may legitimately exit non-zero on a fresh `shared`-profile machine. |
| 9. Claude Enterprise sign-in | `claude` (first run; choose the Claude account option, never the Console / API key option) | the human confirms Claude Code reached its prompt after the browser sign-in (do not run `claude` from an agent session to probe login state) | **Requires human.** The first run may block on a GUI Gatekeeper dialog, then asks for a browser login with the human's work email (probably company SSO). |
| 10. Gateway setup | `claude-gw-setup` (installed to `~/.local/bin` by step 4) | `test -f "$HOME/.config/claude-gw/token" && test -f "$HOME/.config/claude-gw/settings.json"` | **Requires human.** It needs the gateway address and a secret token from the human's company, typed with hidden input. Never ask for the token in chat, never handle it, and never read, print, or cat `~/.config/claude-gw/` files. |
| 11. Linear MCP | `claude mcp add --transport http linear-server --scope user https://mcp.linear.app/mcp` | `claude mcp list` shows `linear-server` connected | **Requires human** to complete the browser OAuth login: run `claude`, type `/mcp`, choose `linear-server`, follow the browser sign-in. |
| 12. Atlassian MCP | `claude mcp add --transport http atlassian --scope user https://mcp.atlassian.com/v2/mcp` | `claude mcp list` shows `atlassian` connected | **Requires human** for the browser OAuth login (`/mcp` inside `claude`, as in step 11), and requires the org's Atlassian admin to have already enabled Rovo/MCP (do not assume this; ask). |
| 13. Salesforce CLI (optional) | `npm install -g @salesforce/cli` then `sf org login web` | `sf --version`; `sf org list` shows the org | **Requires human** for the browser OAuth login. Skip entirely if the human doesn't use Salesforce. |
| 14. GitHub / Netlify | `gh auth login` and `netlify login` | `gh auth status`; `netlify status` | **Requires human** for both browser OAuth logins. |

Always pass `--scope user` to `claude mcp add`. The default scope is
`local`, which makes the server available only in the directory where the
command ran, so it would vanish whenever the human opens Claude Code in a
different folder.

### Two ways to run Claude Code

`claude` uses the human's company Claude Enterprise login (step 9).
`claude-gw` uses the company LLM gateway through the token saved in step
10. Both see the MCP servers added with `--scope user`; connectors added
only through the claude.ai website appear only in plain `claude`.

**Never run `/logout` or `/login` inside `claude-gw`, and never type or
send them to it.** They change the stored Enterprise login. If a gateway
session shows a warning about a saved login, ignore it. Never run the real
`claude-gw` from an agent session to test anything, and never print
`~/.claude/settings.json`, `~/.config/claude-gw/token`, or environment
variables that could hold a credential.

The gateway also needs the human's IT team to confirm that Claude Code
managed settings don't force a single login method (`forceLoginMethod` or
`forceLoginOrgUUID`); if they do, one of the two modes is blocked. Ask the
human whether IT has confirmed this rather than assuming.

### Doctor script caveat

`bin/doctor.sh`'s "Required CLIs" section checks for `bat`, `fzf`, `gh`,
`jq`, `rg`, `mise`, `op`, `claude`, `node`, and `npm`. Since commit
`6923336` it no longer checks `nvim` or `linear`, which the shared-tier
Brewfile intentionally does not install, so a correctly set-up
`shared`-profile machine should exit `0`.

`node` and `npm` come from mise, not the Brewfile:
`dot_config/mise/config.toml` pins `node = "lts"`, and
`run_onchange_after_25-mise-install.sh.tmpl` runs `mise install` during
`chezmoi apply`. If either shows `[FAIL]`, run `mise install`, then open
a fresh shell (or `exec zsh -l`) and re-run the doctor. If `mise` itself
is missing, Homebrew was probably blocked by IT: get it installed and run
`brew bundle --file="$(chezmoi source-path)/Brewfile"` first. Report a
persistent failure to the human; do not work around it with a different
Node installer.

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
- **Step 6**, only if iTerm2 was running during step 4 (the default profile
  was not set automatically, and the agent must not quit iTerm2). If it was
  closed, this step is already done.
- **Step 8's glyph section**, for visual confirmation that the Nerd Font
  glyphs render correctly rather than as tofu boxes.
- **Steps 9 through 14**: every sign-in is a browser login the agent
  cannot complete on the human's behalf. (An agent may run the
  `claude mcp add` commands in steps 11 and 12, but not the sign-in that
  follows them.)
- **Step 9**, additionally: the first `claude` invocation on a machine
  may block on a GUI Gatekeeper security prompt the agent cannot click
  through. The symptom is an indefinite hang with no output, not an
  error. The approval is needed once per machine, on the first `claude`
  run after Claude Code is first installed, and it will not recur on
  later upgrades. Recognize this and stop to ask a human rather than
  retrying or waiting it out.
- **Step 10**, entirely: `claude-gw-setup` needs a secret from the
  human's company (the gateway address and token), typed by the human
  with hidden input. The agent never sees or handles the token, and stops
  and asks the human to run it themselves.
- **Steps 11 and 12**, additionally: after the `claude mcp add` command,
  the human must sign in to each server by typing `/mcp` inside `claude`
  and following the browser login.
- **Step 12**, additionally: confirm the human's Atlassian admin has
  enabled Rovo/MCP before attempting the connection; don't assume it.
- Any Homebrew package in Step 4 that fails because it needs IT/MDM
  approval: report which package and why, don't retry it yourself.
