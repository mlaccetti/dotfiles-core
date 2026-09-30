#!/usr/bin/env python3
"""Every command on the setup guide must be tested or explicitly skipped.

Extracts each <pre><code> command from guide/claude-workstation-setup.html and
asserts it is either

  * declared in guide-steps.sh, as the single-quoted argument of
    `covers`, `g_run` or `g_pty`, or
  * listed in SKIPPED below with the reason it cannot run in the VM.

It also fails when the harness is stale: a declared command that is no longer on
the guide, a skip entry for a command that is gone, or one of the prompt strings
(P_* variables in guide-steps.sh) that no longer appears in the guide or in the
repo file that prints it.

Static mode (run.sh runs this first, before booting any VM):

    check-guide-coverage.py

After a run, pass the commands the VM actually executed (covered.txt) to also
prove each declared command was reached:

    check-guide-coverage.py --executed e2e-out/covered.txt

Standard library only.
"""

import argparse
import html
import re
import sys
from html.parser import HTMLParser
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent

# Guide commands that cannot run in the VM. Keep the reason honest and specific.
SKIPPED = {
    "claude": "interactive sign-in to a real Claude account (browser OAuth); the VM never logs in. "
              "Its version, gateway and MCP behavior are tested through other commands.",
    "gh auth login": "browser OAuth to GitHub; gh itself is verified with gh --version",
    "netlify login": "browser OAuth to Netlify; netlify itself is verified with netlify --version",
    "sf org login web": "browser OAuth to Salesforce; sf itself is installed and verified with sf --version",
    "chsh -s /bin/zsh": "asks for the account password, and the default shell is already zsh in the VM",
}


class CodeBlocks(HTMLParser):
    """Collect the text of every <pre><code> block."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.blocks = []
        self._pre = False
        self._code = False
        self._buf = []

    def handle_starttag(self, tag, attrs):
        if tag == "pre":
            self._pre = True
        elif tag == "code" and self._pre:
            self._code = True
            self._buf = []

    def handle_endtag(self, tag):
        if tag == "code" and self._code:
            self.blocks.append("".join(self._buf))
            self._code = False
        elif tag == "pre":
            self._pre = False

    def handle_data(self, data):
        if self._code:
            self._buf.append(data)


class VisibleText(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.parts = []
        self._skip = 0

    def handle_starttag(self, tag, attrs):
        if tag in ("script", "style"):
            self._skip += 1

    def handle_endtag(self, tag):
        if tag in ("script", "style") and self._skip:
            self._skip -= 1

    def handle_data(self, data):
        if not self._skip:
            self.parts.append(data)


def norm(text):
    return re.sub(r"\s+", " ", html.unescape(text)).strip()


def guide_commands(page):
    parser = CodeBlocks()
    parser.feed(page)
    commands = []
    for block in parser.blocks:
        for line in block.splitlines():
            line = line.strip()
            if line:
                commands.append(line)
    return commands


def declared_commands(steps_text):
    pat = re.compile(r"^\s*(?:covers\s+|g_run\s+\S+\s+|g_pty\s+\S+\s+\S+\s+)'([^']*)'", re.M)
    return set(pat.findall(steps_text))


def prompts(steps_text):
    pat = re.compile(r"""^(P_[A-Z0-9_]+)=(?:'([^']*)'|"([^"]*)")\s*$""", re.M)
    return [(m.group(1), m.group(2) if m.group(2) is not None else m.group(3)) for m in pat.finditer(steps_text)]


def repo_sources():
    """Text of the repo files that print prompts (never test/ or guide/)."""
    text = []
    for path in REPO.rglob("*"):
        rel = path.relative_to(REPO).parts
        if not path.is_file() or rel[0] in (".git", "test", "guide", ".worktrees", "reports"):
            continue
        try:
            text.append(path.read_text(errors="ignore"))
        except OSError:
            pass
    return "\n".join(text)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    ap.add_argument("--html", default=str(REPO / "guide" / "claude-workstation-setup.html"))
    ap.add_argument("--steps", default=str(HERE / "guide-steps.sh"))
    ap.add_argument("--executed", help="covered.txt written by guide-steps.sh; also require every declared command ran")
    args = ap.parse_args()

    page = Path(args.html).read_text()
    steps_text = Path(args.steps).read_text()
    commands = guide_commands(page)
    unique = list(dict.fromkeys(commands))
    declared = declared_commands(steps_text)
    executed = None
    if args.executed:
        executed = {l.rstrip("\n") for l in Path(args.executed).read_text().splitlines() if l.strip()}

    errors = []
    rows = []
    for cmd in unique:
        n = commands.count(cmd)
        if cmd in declared and cmd in SKIPPED:
            errors.append("both tested and skipped (pick one): " + cmd)
        if cmd in declared:
            if executed is not None and cmd not in executed:
                rows.append((cmd, n, "NOT REACHED", "declared in guide-steps.sh but the VM run never executed it"))
                errors.append("declared but not executed in the run: " + cmd)
            else:
                rows.append((cmd, n, "executed" if executed is not None else "declared", "guide-steps.sh"))
        elif cmd in SKIPPED:
            rows.append((cmd, n, "skipped", SKIPPED[cmd]))
        else:
            rows.append((cmd, n, "MISSING", "not run by guide-steps.sh and not on the skip list"))
            errors.append("guide command is neither tested nor skipped: " + cmd)
    for cmd in sorted(declared - set(unique)):
        errors.append("guide-steps.sh covers a command that is no longer on the guide: " + cmd)
    for cmd in sorted(set(SKIPPED) - set(unique)):
        errors.append("skip list has a command that is no longer on the guide: " + cmd)

    # The prompt strings must be the ones the guide and the repo really use.
    visible = VisibleText()
    visible.feed(page)
    guide_text = norm(" ".join(visible.parts))
    sources = norm(repo_sources()) if (REPO / ".chezmoi.toml.tmpl").exists() else None
    for name, text in prompts(steps_text):
        if norm(text) not in guide_text:
            errors.append("prompt %s is not on the guide: %s" % (name, text))
        if sources is not None and norm(text) not in sources:
            errors.append("prompt %s is not printed by any repo file: %s" % (name, text))

    width = max(len(r[0]) for r in rows) if rows else 10
    width = min(width, 70)
    print("%-*s  %3s  %-11s  %s" % (width, "GUIDE COMMAND", "x", "STATUS", "HOW / WHY"))
    for cmd, n, status, note in rows:
        shown = cmd if len(cmd) <= width else cmd[: width - 3] + "..."
        print("%-*s  %3d  %-11s  %s" % (width, shown, n, status, note))
    n_ok = sum(1 for r in rows if r[2] in ("executed", "declared"))
    n_skip = sum(1 for r in rows if r[2] == "skipped")
    print("\n%d distinct guide commands: %d tested, %d skipped with a reason, %d problem(s)"
          % (len(rows), n_ok, n_skip, len(errors)))
    for e in errors:
        print("ERROR: " + e, file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
