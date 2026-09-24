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
| 6. iTerm2 profile selection | None (GUI-only). | N/A | **Requires human.** No CLI can select an iTerm2 profile as active/default. |
| 7. Claude theme | (already set in step 4) | `[ "$(jq -r '.theme' "$HOME/.claude/settings.json")" = "custom:anthropic" ]` | No. |
| 8. doctor.sh | `bash "$(chezmoi source-path)/bin/doctor.sh"` | exit code `0` | The script itself is non-interactive, but its "Glyph rendering test" section requires a **human** to look at the output and judge it (see below). See the caveat below: this may legitimately exit non-zero on a fresh `shared`-profile machine. |
| 9. Linear MCP | `claude mcp add --transport http linear-server https://mcp.linear.app/mcp` | `claude mcp list` shows `linear-server` connected | **Requires human** to complete the browser OAuth login. |
| 10. Atlassian MCP | `claude mcp add --transport http atlassian https://mcp.atlassian.com/v2/mcp` | `claude mcp list` shows `atlassian` connected | **Requires human** for the browser OAuth login, and requires the org's Atlassian admin to have already enabled Rovo/MCP (do not assume this; ask). |
| 11. Salesforce CLI (optional) | `npm install -g @salesforce/cli` then `sf org login web` | `sf --version`; `sf org list` shows the org | **Requires human** for the browser OAuth login. Skip entirely if the human doesn't use Salesforce. |
| 12. GitHub / Netlify | `gh auth login` and `netlify login` | `gh auth status`; `netlify status` | **Requires human** for both browser OAuth logins. |

### Doctor script caveat

`bin/doctor.sh`'s "Required CLIs" section checks for `nvim`, `linear`,
and `op` in addition to tools this Brewfile still installs. As of this
rewrite, the shared-tier Brewfile intentionally no longer installs
neovim or the `schpet/tap/linear` CLI (the Linear MCP server supersedes
it), so a correctly-set-up `shared`-profile machine will show `[FAIL]`
for `nvim` and `linear`, and `bin/doctor.sh` will exit non-zero even
though nothing is actually wrong. `op` will only resolve if the human
answered `true` to the 1Password question in step 4. Report these as
expected, not as setup failures, and do not attempt to install neovim or
the `schpet/tap` tap to silence them; that would reintroduce the
tooling this rewrite intentionally removed. Fixing `doctor.sh` itself is
a separate, deliberate change outside this document's scope, flag it to
a human instead of patching it inline.

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
- **Steps 9 through 12**, entirely: every one of them is a browser OAuth
  login the agent cannot complete on the human's behalf.
- **Step 10**, additionally: confirm the human's Atlassian admin has
  enabled Rovo/MCP before attempting the connection; don't assume it.
- Any Homebrew package in Step 4 that fails because it needs IT/MDM
  approval: report which package and why, don't retry it yourself.
