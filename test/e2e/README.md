# End-to-end test of the setup guide

This runs every command on `guide/claude-workstation-setup.html` (the guide a
reader follows), in order, inside a fresh macOS virtual machine. It answers the
three setup questions the way a reader would, then checks what each step promises.
There are two scenarios, two different starting states:

| Scenario | The Mac it starts from | What it proves |
|---|---|---|
| `preinstalled` (default) | Homebrew, plus iTerm2, VS Code, 1Password, `op` and Claude Code already installed, none through Homebrew | setup leaves existing apps alone, never lays a second Claude Code on top, and the doctor reports them as WARN |
| `fresh` | Homebrew and nothing else | setup installs iTerm2, VS Code, 1Password, `op`, Claude Code and the Nerd Font through Homebrew, with exactly one `claude`, and the doctor has no WARN |

```sh
test/e2e/run.sh                  # preinstalled; exit 0 = green, 1 = a check failed, 2 = could not run
test/e2e/run.sh fresh            # the Homebrew-only Mac
test/e2e/run.sh all              # both, one after the other
test/e2e/run.sh fresh --keep     # leave the VM on disk to poke at (delete it yourself afterwards)
test/e2e/run.sh --rebuild        # rebuild the sandbox-preinstalled image first
```

Environment overrides: `E2E_BASE_IMAGE` (the OCI image to pull, default
`ghcr.io/cirruslabs/macos-tahoe-base:latest`), `E2E_BASE_VM` (default `sandbox-base`),
`E2E_PREINSTALLED_VM` (default `sandbox-preinstalled`).

The guide runs the public repo (`chezmoi init --apply
https://github.com/mlaccetti/dotfiles-core`), exactly as a reader will. A fix
therefore has to be merged to the default branch before a run can see it.

## Prerequisites

- An Apple silicon Mac, macOS 13 or newer, with `sysctl kern.hv_support` printing `1`.
- Tart 2.32.1 (the VM tool) on `PATH`, installed from the release tarball (below).
- Free disk: about 60 GB the first time (the image pull is roughly 33 GB, and
  the base and preinstalled VMs are about 35 GB each on paper), then about 25 GB per
  run. Clones share blocks through APFS copy-on-write, so `du` and `tart list`
  overstate the real cost. `run.sh` checks this before it starts.
- `ssh`, `scp`, `python3` (all ship with macOS). No `sshpass`: the harness logs
  in with `SSH_ASKPASS`, because `sshpass` lost its password-prompt race on
  about one connection in ten.

### Why Tart comes from the release tarball, not Homebrew

`brew install cirruslabs/cli/tart` fails on Homebrew 7 because the tap formula
declares `depends_on :macos => :ventura` (`tart.rb:22`), which Homebrew 7
rejects. Install the signed, notarized release instead:

```sh
mkdir -p ~/.local/tart ~/.local/bin && cd ~/.local/tart
curl -fLO https://github.com/cirruslabs/tart/releases/download/2.32.1/tart.tar.gz
echo "8554ab4f7fc12afe52f9b7e3093a935673cbac737a83973d2db7a0683c814529  tart.tar.gz" | shasum -a 256 -c   # must print: tart.tar.gz: OK
tar xzf tart.tar.gz
ln -sf ~/.local/tart/tart.app/Contents/MacOS/tart ~/.local/bin/tart
tart --version                                                    # 2.32.1
codesign -dvv ~/.local/tart/tart.app 2>&1 | grep -E 'Authority|TeamIdentifier'
# expect: Developer ID Application: Cirrus Labs, Inc. (9M2P8L4D89)
```

If the checksum does not match, stop and do not run anything from the tarball.
`~/.local/bin` must be on `PATH`.

Tart is Fair Source software (not open source): free for personal use and for
small setups, with paid tiers above a size threshold. Read the license at
https://github.com/cirruslabs/tart before you use it commercially.

## What happens in a run

1. **Prerequisites and guide coverage.** `check-guide-coverage.py` pulls every
   `<pre><code>` command out of the guide and fails unless each one is either run
   by `guide-steps.sh` or on the skip list with a reason. So a guide change that
   adds an untested command fails here, before any VM boots. It also checks that
   the prompt texts the test types are the ones on the guide and in the repo.
   It then runs the fast unit tests in `test/unit` (Claude detection and the
   doctor's Fix lines), which need no VM.
2. **The starting image.**
   - `preinstalled`: `sandbox-preinstalled`, built once. If it does not exist,
     `run.sh` clones `sandbox-base` (the untouched Cirrus `macos-tahoe-base`
     image, pulled on first use) to a throwaway `sandbox-build-<timestamp>`,
     boots that, runs `provision-preinstalled.sh` (iTerm2, VS Code, 1Password and
     `op` from vendor downloads, Claude Code from the native installer, no Nerd
     Font, none of them managed by Homebrew), and renames it to
     `sandbox-preinstalled`. The base is never provisioned, so `--rebuild` always
     proves the script from the vendor image. Provisioning takes about 3 minutes
     once the base image is on disk (the first image pull is about 33 GB and is
     the slow part). `--rebuild` does it again.
   - `fresh`: `sandbox-base` itself. It was checked: the Cirrus image already has
     Homebrew (6.0.x) and no iTerm2, VS Code, 1Password, `op`, Claude Code, Claude
     desktop app or Nerd Font (the only cask is `git-credential-manager`, which
     `prepare-run.sh` removes), so no separate "fresh" image is needed.
3. **A throwaway clone, `sandbox-run-<scenario>-<timestamp>`,** is booted
   headless. It is deleted at the end (unless `--keep`). The images are never modified.
4. **`prepare-run.sh` makes the run faithful, not easy.** It updates Homebrew,
   removes the CI tooling the Cirrus image ships (`jq`, `gh`, `yq`, `mise`,
   `node`, `rbenv`, `awscli`, `git-lfs` and the rest, plus everything the Brewfile
   installs), so every tool used afterwards was provided by the setup. It
   then gives the shell the startup files a typical Mac has: Homebrew's `shellenv`
   line in `~/.zprofile` and, for `preinstalled` only, `export PATH="$HOME/.local/bin:$PATH"`
   in `~/.zshrc` (the native Claude installer's line; `fresh` has no `~/.zshrc`),
   nothing else. It prints every removal with its reason, and for `fresh` it
   fails if any of the apps, `op`, `claude` or a Nerd Font is already there.
5. **`guide-steps.sh` runs the guide** in an interactive login zsh on a real pty
   (what iTerm2 opens), with `expect` answering the prompts:
   Homebrew, `chezmoi`, the main setup (name `Test User`, email
   `test@example.com`, 1Password `false`), the shell restart,
   `claude --version`, the optional gateway against a local stub, the MCP
   connections at user scope, the binaries (`gh`, `npm`), `doctor.sh` (must exit 0
   with no FAIL; `preinstalled` allows exactly the WARNs the guide tells you to
   expect, `fresh` allows none), the font and profile files, the
   troubleshooting commands, and a second run of the main setup, `chezmoi apply`
   and `doctor.sh` to prove nothing changes. The step labels in the results are
   the guide's: 1 Homebrew, 2 chezmoi, 3 main setup, 4 restart, 5 iTerm2 look,
   6 Claude, 7 gateway (optional), 8 connect tools, 9 health check; G is the glyph
   check, T the troubleshooting commands, I idempotency.
6. **The report** is copied to `test/e2e/reports/<timestamp>/<scenario>/`
   (git-ignored): `prepare-run.log`, `guide-steps.log`, `coverage.txt` (each guide
   command as executed or skipped with its reason) and `e2e-out/` (every step's
   transcript and `results.tsv`).

### What `fresh` asserts after setup

Each of iTerm2, VS Code, 1Password, `op`, Claude Code and the FiraCode Nerd Font
is present afterwards and owned by Homebrew (the cask is in `brew list --cask`
and the app or binary resolves into `/opt/homebrew/Caskroom`). There is exactly
one `claude`: one Claude cask (`claude-code@latest`), `which -a claude` lists
only `/opt/homebrew/bin/claude`, and there is no `~/.local/bin/claude`. The
Claude desktop app is not part of the guide or the Brewfile, so it is reported
(absent) rather than asserted.

Two things stand in for a person at the keyboard, and both stay inside the
throwaway VM:

- **Gatekeeper.** A real user clicks "Open" once for the Homebrew-installed
  Claude Code (guide Step 6). After setup and before the first `claude` command,
  `guide-steps.sh` simulates that click by running `xattr -dr com.apple.quarantine`
  on `/opt/homebrew/Caskroom/claude-code@latest`. It says so in a comment and
  records the before and after counts. No app is launched by the harness, so no
  other app needs it.
- **Password prompts.** If a cask installer stops at a "Password:" prompt,
  `pty-run.exp` types the VM's own throwaway `admin` password, as a user would
  at the GUI prompt, and prints a line saying it did. The VM's `admin` also has
  passwordless `sudo`, so this is a safety net. Nothing here uses `sudo` on the
  host.

### What both scenarios assert

Doctor reports no FAIL (each WARN is listed in the results and judged against
the scenario), the stub gateway sees only the dummy credential and nothing goes
to Anthropic during `claude-gw`, the iTerm2 default profile is set, and running
the guide's main setup a second time succeeds without re-running any install
script.

### The gateway stub

`stub-gateway.py` is an HTTPS server on `127.0.0.1` with a self-signed
certificate generated inside the VM. It answers `POST /v1/messages` (streaming
and not) with a minimal valid reply. It records only a classification of the
`x-api-key` and `Authorization` headers (`DUMMY` for the dummy token, `OTHER`
for anything else, `NONE` for absent), plus the method, `Host` and path. It never
stores a credential value. The test passes only if `claude-gw` sends `DUMMY`
and the stub sees nothing `OTHER`.

The gateway step is optional in the guide, but it is still run in both scenarios.
To check that Claude Code does not reach `api.anthropic.com` during that run, the
harness captures DNS lookups and outbound TCP SYNs with `tcpdump` (a
non-intercepting capture, not a man in the middle). A positive control first
proves the capture does see a plain `curl` to `api.anthropic.com`.

## Security

No real credential ever enters the VM. The harness copies only its own scripts in;
nothing from your home directory. It uses the name `Test User`, the email
`test@example.com` and a random throwaway token, and it never signs in anywhere.
The VM's documented login is `admin` / `admin` with passwordless `sudo` (never used on the host); the VM is
throwaway and reachable only on Tart's NAT. `ssh` is run with public-key
authentication off so none of your agent's keys can be offered to it, and with
host key checking off because the key changes on every clone.

## What it cannot cover

These need a person, a real account or a real screen:

- **Browser sign-ins.** The Claude account login (`claude`, `/status`), the
  `/mcp` OAuth flow for Linear and Atlassian, and `gh auth login`.
  The binaries are checked (`gh --version`, `npm --version`, and that
  `claude mcp list` shows both servers), not the logins.
- **The iTerm2 GUI.** iTerm2 never runs in the VM. The test proves the profile
  file lands and that the `Default Bookmark Guid` preference matches the profile
  (the iTerm2-closed path). It cannot prove iTerm2 loads the profile, and it
  cannot exercise the "iTerm2 is running, so set the default by hand" menu steps.
- **The glyph check.** The doctor's arrows, icons and emoji have to be looked at.
  The test only proves the FiraCode Nerd Font files exist and the Anthropic
  profile references `FiraCodeNFM-Reg`.
- **The Claude account login and a real gateway.** The gateway is a local stub. A
  real gateway address, token, model names, or a network or VPN it needs are not tested.
- **A real Mac.** Its macOS version, install restrictions (blocked installs, Gatekeeper
  and security dialogs, the browser sign-in policy), an existing git identity, and
  anything else a real machine has that the VM does not. The Gatekeeper "Open" click
  is simulated by removing the quarantine flag in the `fresh` VM, so the real
  dialog and its wording are not tested.
- **`chsh -s /bin/zsh`,** which asks for the account password.
- **Claude Code's first-run questions** (theme, folder trust), which need a
  logged-in interactive session.

## Files

| File | What it is |
|---|---|
| `run.sh` | Host driver: scenario choice, prerequisites, coverage, build, clone, boot, run, report, clean up |
| `provision-preinstalled.sh` | In-VM, one time: puts the base image in the `preinstalled` starting state (apps already installed) |
| `prepare-run.sh` | In-VM, every run: removes CI tooling, sets the shell startup files (per scenario), updates Homebrew |
| `guide-steps.sh` | In-VM: the guide, in order, with the checks (`E2E_SCENARIO` picks the scenario's assertions) |
| `pty-run.exp`, `pty-session.exp` | `expect` drivers: a command with prompts, and a typed interactive session |
| `stub-gateway.py` | The classification-only HTTPS gateway stub |
| `check-guide-coverage.py` | Every guide command is tested or skipped with a reason |
| `../unit/*.sh` | Fast unit tests run first by `run.sh`; no VM |

The guide's source is `guide/claude-workstation-setup.html`, kept in step with the
published artifact. `test/` and `guide/` are in `.chezmoiignore`, so neither is
ever deployed into a home directory.

## Notes on the provisioning script

- Pinned, vendor-official downloads, each verified by SHA-256 and by Developer ID
  team before install: iTerm2 3.7.3, VS Code 1.139.1, 1Password 8.12.36, `op`
  2.39.0. When you bump a pin, update the version, URL and hash together.
- Claude Code comes from `curl -fsSL https://claude.ai/install.sh | bash`, so its
  version is whatever is current when the snapshot is built.
- It fails hard if a hash or signature mismatches, a Nerd Font is present, an app
  carries a quarantine attribute, one of the apps is brew-managed, or the shell is
  not zsh. It uses `ditto` (not `unzip`) so bundle metadata survives, and never
  launches a GUI app or runs `claude`.
- The VM is macOS 26 (Tahoe). macOS ships `/usr/bin/jq`, so `jq` resolving there
  is legitimate and not treated as leftover CI tooling.

## Rebuilding from scratch

`test/e2e/run.sh --rebuild` deletes and rebuilds `sandbox-preinstalled`. To also force
a fresh image pull (about 33 GB), first `tart delete sandbox-base` and the
cached `ghcr.io/cirruslabs/macos-tahoe-base` images. `fresh` has no image of its own,
so `--rebuild` does not apply to it.
