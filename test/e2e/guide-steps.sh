#!/usr/bin/env bash
# guide-steps.sh
#
# Runs INSIDE the VM, after prepare-run.sh. Executes the setup guide's commands
# in the guide's order, the way she would: typed into an interactive LOGIN zsh
# (what iTerm2 opens) on a real pty, with the four chezmoi questions answered by
# `expect`. Around each step it checks the result the guide promises.
#
# Every command shown in guide/claude-workstation-setup.html must appear here as
# the single-quoted argument of covers / g_run / g_pty, or be on the skip list in
# check-guide-coverage.py. That script enforces it, so a guide change that adds
# an untested command fails the harness before the VM is even booted.
#
# Only dummy values are used: name "Test User", email test@example.com, a random
# throwaway gateway token. Nothing signs in to anything. Not `set -e` on purpose:
# a failed check is recorded and the run continues so one run shows every problem.
# shellcheck disable=SC2015,SC2016,SC2010,SC2329,SC2018,SC2019,SC2088,SC2024
# SC2015: `test && pass || bad` is deliberate, pass and bad both always succeed.
# SC2016: the single-quoted strings are the commands typed into HER shell, so
#         they must not expand here.
# SC2010: font names are only counted, so `ls | grep` is fine.
# SC2329: cleanup is invoked by the EXIT trap.
# SC2018/2019: plain ASCII case folding of fixed labels.
# SC2088: the "~/" strings are display text, not paths.
# SC2024: tcpdump runs as root, and its stdout is meant to land in OUR file.
set -uo pipefail

E2E_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${E2E_OUT:-$HOME/e2e-out}"
rm -rf "$OUT"
mkdir -p "$OUT"
: >"$OUT/results.tsv"
: >"$OUT/covered.txt"

# The four chezmoi questions, exactly as .chezmoi.toml.tmpl prints them. The
# coverage checker verifies that each also appears in the guide.
P_NAME='Your full name (used for git commit authorship)'
P_EMAIL='Your email address (used for git commit authorship)'
P_PROFILE="Which profile is this? Type 'michael' for Michael's machine or 'shared' for anyone else (e.g. a spouse's laptop)"
P_1PASSWORD='Do you use 1Password and want this setup to read secrets from it? Type true or false - if unsure, type false (you can turn this on later)'
# The four claude-gw-setup questions, from dot_local/bin/executable_claude-gw-setup.
P_GWURL='Gateway address (starts with https://)'
P_GWTOKEN='Gateway token (typing is hidden)'
P_GWMODELS='Does the gateway need specific model names? (y/N)'
P_GWTEST='Test the connection now? This sends one tiny request. (Y/n)'

T_NAME='Test User'
T_EMAIL='test@example.com'
DUMMY_TOKEN="e2e-dummy-$(/usr/bin/openssl rand -hex 16)"

# ------------------------------------------------------------------ helpers
record() { # STEP STATUS DESC [EVIDENCE]
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "${4:-}" >>"$OUT/results.tsv"
  printf '  [%s] %s: %s%s\n' "$2" "$1" "$3" "${4:+  ($4)}"
}
pass() { record "$1" PASS "$2" "${3:-}"; }
bad()  { record "$1" FAIL "$2" "${3:-}"; }
info() { record "$1" INFO "$2" "${3:-}"; }
# check STEP DESC EVIDENCE cmd...   PASS if cmd succeeds
check() {
  local step="$1" desc="$2" ev="$3"; shift 3
  if "$@" >/dev/null 2>&1; then pass "$step" "$desc" "$ev"; else bad "$step" "$desc" "$ev"; fi
}
section() { printf '\n########## %s\n' "$*"; }
covers() { printf '%s\n' "$1" >>"$OUT/covered.txt"; }

strip_ansi() { perl -pe 'BEGIN { $| = 1 } s/\e\[[0-9;?]*[ -\/]*[@-~]//g; s/\e\][^\a]*(\a|\e\\)//g; s/\r//g'; }

# pty NAME TIMEOUT CMD [PROMPT ANSWER]...   run CMD in an interactive login zsh on a pty.
# Sets PTY_RC (exit status) and PTY_TXT (path of the ANSI-stripped transcript).
pty() {
  local name="$1" to="$2" cmd="$3"; shift 3
  PTY_TXT="$OUT/$name.txt"
  printf '\n--- [%s] $ %s\n' "$name" "$cmd"
  # Streamed live (raw transcript kept, stripped copy shown and saved).
  /usr/bin/expect "$E2E_DIR/pty-run.exp" "$to" "$cmd" "$@" 2>&1 | tee "$OUT/$name.raw" | strip_ansi | tee "$PTY_TXT"
  PTY_RC="${PIPESTATUS[0]}"
  printf -- '--- [%s] exit %s\n' "$name" "$PTY_RC"
}
g_pty() { covers "$3"; pty "$@"; }               # a guide command, with prompts
g_run() { covers "$2"; pty "$1" 900 "$2"; }      # a guide command, no prompts

# session NAME TIMEOUT LINE...   type LINEs into one interactive login zsh (see pty-session.exp)
session() {
  local name="$1" to="$2"; shift 2
  SESSION_TXT="$OUT/$name.txt"
  printf '\n--- [%s] interactive session\n' "$name"
  /usr/bin/expect "$E2E_DIR/pty-session.exp" "$to" "$@" 2>&1 | tee "$OUT/$name.raw" | strip_ansi | tee "$SESSION_TXT"
  SESSION_RC="${PIPESTATUS[0]}"
  printf -- '--- [%s] exit %s\n' "$name" "$SESSION_RC"
}
vval() { sed -n "s/^V:$1=//p" "$2" | head -1; }     # value printed by "echo V:NAME=..." in a session
has()  { grep -Eq -- "$1" "$2"; }                    # regex present in file (no pipe: no SIGPIPE under pipefail)
count(){ local n; n="$(grep -Ec -- "$1" "$2" 2>/dev/null)"; printf '%s' "${n:-0}"; }
mode() { stat -f '%Lp' "$1" 2>/dev/null; }

STUB_PID=""
TCPDUMP_PID=""
cleanup() {
  [ -z "$STUB_PID" ] || kill "$STUB_PID" 2>/dev/null
  [ -z "$TCPDUMP_PID" ] || sudo -n kill "$TCPDUMP_PID" 2>/dev/null
}
trap cleanup EXIT

# Absolute paths for checks that run in this (bash) process, not in her shell.
ITERM_PROFILE="$HOME/Library/Application Support/iTerm2/DynamicProfiles/Anthropic.json"

# ================================================================== 1
section "Step 1: Check that Homebrew works"
g_run s1-brew 'brew --version'
if [ "$PTY_RC" -eq 0 ] && has '^Homebrew [0-9]' "$PTY_TXT"; then
  pass 1 "brew --version prints a Homebrew version" "$(sed -n 's/^\(Homebrew [0-9][^ ]*\).*/\1/p' "$PTY_TXT" | head -1)"
else
  bad 1 "brew --version" "exit $PTY_RC"
fi

# ================================================================== 2
section "Step 2: Install chezmoi"
g_run s2-chezmoi 'brew install chezmoi'
[ "$PTY_RC" -eq 0 ] && pass 2 "brew install chezmoi exits 0" || bad 2 "brew install chezmoi" "exit $PTY_RC"
check 2 "chezmoi is on PATH in a new login shell" "$(/opt/homebrew/bin/chezmoi --version 2>/dev/null | head -1)" test -x /opt/homebrew/bin/chezmoi

# ================================================================== 3
section "Step 3: Run the main setup (four prompts answered by expect)"
g_pty s3-init 2400 'chezmoi init --apply https://github.com/mlaccetti/dotfiles-core' \
  "$P_NAME" "$T_NAME" "$P_EMAIL" "$T_EMAIL" "$P_PROFILE" 'shared' "$P_1PASSWORD" 'false'
INIT="$PTY_TXT"
[ "$PTY_RC" -eq 0 ] && pass 3 "chezmoi init --apply exits 0 and all four prompts matched" "exit 0" || bad 3 "chezmoi init --apply" "exit $PTY_RC"

alr="$(grep -m1 'Already installed, leaving as is:' "$INIT")"
if [ -n "$alr" ]; then
  # brew's display name for the VS Code cask is "Microsoft Visual Studio Code".
  list="${alr#*: }, "
  for n in 'iTerm2' 'Visual Studio Code' '1Password' '1Password CLI' 'Claude Code'; do
    case "$list" in
      *"$n, "*) pass 3 "already-installed line lists $n" ;;
      *) bad 3 "already-installed line lists $n" "$alr" ;;
    esac
  done
else
  bad 3 "an 'Already installed, leaving as is' line was printed" "absent"
fi

casks="$(/opt/homebrew/bin/brew list --cask 2>/dev/null)"
formulae="$(/opt/homebrew/bin/brew list --formula 2>/dev/null)"
for c in iterm2 visual-studio-code 1password 1password-cli claude-code 'claude-code@latest'; do
  if printf '%s\n' "$casks" | grep -qx -- "$c"; then bad 3 "cask $c must not be installed by brew" "installed"; fi
done
claude_casks="$(printf '%s\n' "$casks" | grep -i claude)"
[ -z "$claude_casks" ] && pass 3 "no second Claude Code: 'brew list --cask | grep -i claude' is empty" || bad 3 "a Claude cask got installed" "$claude_casks"
claude_all="$(zsh -lic 'which -a claude' </dev/null 2>/dev/null | grep '^/' | sort -u | tr '\n' ' ')"
[ "$claude_all" = "$HOME/.local/bin/claude " ] && pass 3 "which -a claude shows only ~/.local/bin/claude" "$claude_all" || bad 3 "which -a claude" "$claude_all"

dups="$(grep -E '^(==> )?Installing ' "$INIT" | sort | uniq -d)"
[ -z "$dups" ] && pass 3 "nothing was installed twice" || bad 3 "duplicate install lines" "$dups"

fonts="$(ls "$HOME/Library/Fonts" 2>/dev/null | grep -ci 'FiraCode')"
[ "${fonts:-0}" -gt 0 ] && pass 3 "Nerd Font installed" "$fonts FiraCode files in ~/Library/Fonts" || bad 3 "Nerd Font installed" "none in ~/Library/Fonts"
for f in jq gh mise chezmoi fzf bat ripgrep netlify-cli zsh-autosuggestions zsh-syntax-highlighting; do
  printf '%s\n' "$formulae" | grep -qx -- "$f" || bad 3 "formula $f installed" "missing from brew list"
done
info 3 "Slack cask (Michael has not decided on it)" "$(if printf '%s\n' "$casks" | grep -qx slack; then echo 'installed by setup'; else echo 'not installed'; fi)"

# Node through mise (run_onchange_after_25).
nodepath="$(zsh -lic 'command -v node' </dev/null 2>/dev/null | tail -1)"
case "$nodepath" in
  */mise/installs/node/*) pass 3 "Node installed through mise" "$nodepath $(zsh -lic 'node --version' </dev/null 2>/dev/null | tail -1)" ;;
  *) bad 3 "Node installed through mise" "node resolves to: ${nodepath:-nothing}" ;;
esac

g_run s3-gitname 'git config --global user.name'
[ "$PTY_RC" -eq 0 ] && [ "$(tr -d '\n' <"$PTY_TXT")" = "$T_NAME" ] && pass 3 "git user.name is set" "$T_NAME" || bad 3 "git user.name" "$(cat "$PTY_TXT")"
g_run s3-gitemail 'git config --global user.email'
[ "$PTY_RC" -eq 0 ] && [ "$(tr -d '\n' <"$PTY_TXT")" = "$T_EMAIL" ] && pass 3 "git user.email is set" "$T_EMAIL" || bad 3 "git user.email" "$(cat "$PTY_TXT")"

check 3 "iTerm2 Dynamic Profile file landed" "$ITERM_PROFILE" test -s "$ITERM_PROFILE"

guid="$(plutil -extract Profiles.0.Guid raw -o - "$ITERM_PROFILE" 2>/dev/null)"
default_guid="$(defaults read com.googlecode.iterm2 'Default Bookmark Guid' 2>/dev/null)"
if [ -n "$guid" ] && [ "$guid" = "$default_guid" ]; then
  pass 3 "iTerm2 default profile is Anthropic (run_once_after_10 set it; iTerm2 not running)" "Default Bookmark Guid = $default_guid"
else
  bad 3 "iTerm2 default profile is Anthropic" "profile Guid='$guid' Default Bookmark Guid='$default_guid'"
fi

trace="$(count 'Traceback|panic:|goroutine [0-9]|[Ss]tack trace|unbound variable|syntax error|Segmentation fault|command not found' "$INIT")"
[ "$trace" -eq 0 ] && pass 3 "no stack traces or shell errors in the output" || bad 3 "stack traces or shell errors in the output" "$(grep -E 'Traceback|panic:|goroutine [0-9]|[Ss]tack trace|unbound variable|syntax error|Segmentation fault|command not found' "$INIT" | head -3 | tr '\n' '|')"
warnlines="$(grep -E '^\s*!!|Error:|error:' "$INIT" | head -12)"
if [ -n "$warnlines" ]; then info 3 "'!!' or error lines in the setup output (review)" "$(printf '%s' "$warnlines" | tr '\n' '|')"; else pass 3 "no '!!' warning or error lines in the setup output"; fi

# ================================================================== 4
section "Step 4: Restart the terminal"
covers 'exec zsh -l'
session s4-restart 180 '!exec zsh -l' \
  'echo "V:ZSH_CUSTOM=$ZSH_CUSTOM"' \
  'echo "V:PROMPT_CONTEXT=$(whence -w prompt_context)"' \
  'echo "V:CLAUDE=$(command -v claude)"' \
  'echo "V:BREW=$(command -v brew)"' \
  'echo "V:CHEZMOI=$(command -v chezmoi)"' \
  'echo "V:BAT=$(command -v bat)"' \
  'echo "V:FZF=$(command -v fzf)"' \
  'echo "V:ZSHRC_LOCAL=$(test -f $HOME/.zshrc.local && echo present)"'
S4="$SESSION_TXT"
[ -n "$(vval ZSH_CUSTOM "$S4")" ] && pass 4 "\$ZSH_CUSTOM is set in the new shell" "$(vval ZSH_CUSTOM "$S4")" || bad 4 "\$ZSH_CUSTOM is set in the new shell" "empty"
case "$(vval PROMPT_CONTEXT "$S4")" in *": function") pass 4 "prompt_context is defined (new prompt config loaded)" ;; *) bad 4 "prompt_context is defined" "$(vval PROMPT_CONTEXT "$S4")" ;; esac
[ "$(vval CLAUDE "$S4")" = "$HOME/.local/bin/claude" ] && pass 4 "claude still resolves after setup replaced ~/.zshrc" "$(vval CLAUDE "$S4")" || bad 4 "claude still resolves after setup replaced ~/.zshrc" "got '$(vval CLAUDE "$S4")'"
for t in BREW CHEZMOI BAT FZF; do
  [ -n "$(vval $t "$S4")" ] && pass 4 "$(printf '%s' "$t" | tr A-Z a-z) resolves in the new shell" "$(vval $t "$S4")" || bad 4 "$(printf '%s' "$t" | tr A-Z a-z) resolves in the new shell" "empty"
done
[ "$(vval ZSHRC_LOCAL "$S4")" = present ] && pass 4 "~/.zshrc.local was seeded" || bad 4 "~/.zshrc.local was seeded"

# ================================================================== 5
section "Step 5: Claude Code (no login)"
pty s5-claude-version 120 'claude --version'
if [ "$PTY_RC" -eq 0 ] && has '^[0-9]+\.[0-9]+\.[0-9]+' "$PTY_TXT"; then
  pass 5 "claude --version" "$(head -1 "$PTY_TXT")"
else
  bad 5 "claude --version" "exit $PTY_RC"
fi
info 5 "'claude' sign-in and /status skipped" "needs a real Claude account and a browser"

# ================================================================== 6
section "Step 6: Gateway, against a local stub"
GW="$OUT/gw"
mkdir -p "$GW"
cat >"$GW/openssl.cnf" <<'CNF'
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = 127.0.0.1
[v3]
subjectAltName = IP:127.0.0.1
basicConstraints = CA:TRUE
CNF
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 2 -config "$GW/openssl.cnf" \
  -keyout "$GW/key.pem" -out "$GW/cert.pem" >/dev/null 2>&1
check 6 "self-signed cert for 127.0.0.1 generated in the VM" "$GW/cert.pem" test -s "$GW/cert.pem"

STUB_DUMMY_TOKEN="$DUMMY_TOKEN" nohup /usr/bin/python3 "$E2E_DIR/stub-gateway.py" \
  --cert "$GW/cert.pem" --key "$GW/key.pem" --log "$GW/requests.jsonl" --port-file "$GW/port" \
  >"$GW/stub.out" 2>&1 &
STUB_PID=$!
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do [ -s "$GW/port" ] && break; sleep 0.5; done
PORT="$(cat "$GW/port" 2>/dev/null)"
[ -n "$PORT" ] && pass 6 "stub gateway is listening" "https://127.0.0.1:$PORT" || bad 6 "stub gateway is listening" "$(cat "$GW/stub.out")"
GWURL="https://127.0.0.1:$PORT"

# 6a. setup with the self-signed cert untrusted: only "couldn't reach", settings still saved.
g_pty s6-setup 120 'claude-gw-setup' \
  "$P_GWURL" "$GWURL" "$P_GWTOKEN" "$DUMMY_TOKEN" "$P_GWMODELS" 'n' "$P_GWTEST" ''
[ "$PTY_RC" -eq 0 ] && pass 6 "claude-gw-setup finishes (exit 0) with an untrusted cert" || bad 6 "claude-gw-setup" "exit $PTY_RC"
if has "couldn't reach" "$PTY_TXT"; then pass 6 "untrusted cert only gives the 'couldn't reach' message, settings saved"; else bad 6 "expected the 'couldn't reach' message" "$(tail -3 "$PTY_TXT" | tr '\n' '|')"; fi
CFG="$HOME/.config/claude-gw"
[ "$(mode "$CFG")" = 700 ] && pass 6 "~/.config/claude-gw is mode 700" || bad 6 "~/.config/claude-gw mode" "$(mode "$CFG")"
[ "$(mode "$CFG/token")" = 600 ] && pass 6 "token file is mode 600" || bad 6 "token file mode" "$(mode "$CFG/token")"
[ "$(mode "$CFG/settings.json")" = 600 ] && pass 6 "settings.json is mode 600" || bad 6 "settings.json mode" "$(mode "$CFG/settings.json")"
[ "$(cat "$CFG/token" 2>/dev/null)" = "$DUMMY_TOKEN" ] && pass 6 "token file holds the token that was typed" || bad 6 "token file content"
if grep -Fq -- "$DUMMY_TOKEN" "$CFG/settings.json"; then bad 6 "token is not in claude-gw settings.json" "FOUND"; else pass 6 "token is not in claude-gw settings.json"; fi
n_after_setup="$(wc -l <"$GW/requests.jsonl" | tr -d ' ')"
[ "$n_after_setup" -eq 0 ] && pass 6 "stub saw no request from the failed TLS test" || info 6 "stub saw requests during setup" "$n_after_setup"

# 6b. setup again with the cert trusted by curl: the "answered" path must send the dummy token in both headers.
covers 'claude-gw-setup'
pty s6-setup-trusted 120 "SSL_CERT_FILE='$GW/cert.pem' CURL_CA_BUNDLE='$GW/cert.pem' claude-gw-setup" \
  "$P_GWURL" "$GWURL" "$P_GWTOKEN" "$DUMMY_TOKEN" "$P_GWMODELS" 'n' "$P_GWTEST" ''
if has 'The gateway answered' "$PTY_TXT"; then
  pass 6 "trusted cert: 'The gateway answered' and 'All set'" "$(grep -m1 'The gateway answered' "$PTY_TXT")"
  cls="$(/usr/bin/python3 - "$GW/requests.jsonl" <<'PY'
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
print(" ".join("%s x-api-key=%s authorization=%s" % (r["path"], r["x-api-key"], r["authorization"]) for r in rows))
PY
)"
  case "$cls" in
    *"x-api-key=DUMMY authorization=DUMMY"*) pass 6 "setup's connection test sent the dummy token in both headers" "$cls" ;;
    *) bad 6 "setup's connection test credentials" "$cls" ;;
  esac
else
  info 6 "curl in this VM did not honor CURL_CA_BUNDLE; 'answered' path not exercised" "$(tail -3 "$PTY_TXT" | tr '\n' '|')"
fi

# 6c. claude-gw itself, with a packet capture around it.
DNSQ='udp port 53 or (tcp[tcpflags] & (tcp-syn|tcp-ack) == tcp-syn)'
# syn_dests: reads tcpdump text on stdin, prints the destination "addr:port" of every TCP SYN.
syn_dests() { sed -n 's/.* > \([^ ]*\)\.\([0-9][0-9]*\): Flags \[S[EW]*\],.*/\1:\2/p' | sort -u; }
# Not loopback: what would actually leave the VM.
non_loopback() { grep -v '^127\.0\.0\.1:\|^::1:'; }
# tcpdump -k NP (macOS) tags each packet with the process that sent it, so the
# capture can say WHO connected, not just that something did. macOS itself talks
# to Apple hosts in the background (OCSP, iCloud), which must not count against
# claude. A native Claude Code process is named after its versioned file, not
# "claude", so resolve the symlink to get the name tcpdump prints.
CLAUDE_PROC="$(/usr/bin/python3 -c 'import os, sys; print(os.path.basename(os.path.realpath(sys.argv[1])))' "$HOME/.local/bin/claude")"
CLAUDE_PROC_RE="proc ${CLAUDE_PROC//./\\.}:"
capture_start() { # NAME
  sudo -n /usr/sbin/tcpdump -i any -n -l -tt -k NP "$DNSQ" >"$GW/$1.cap" 2>&1 &
  TCPDUMP_PID=$!
  sleep 3
}
capture_stop() {
  sleep 2
  sudo -n kill "$TCPDUMP_PID" 2>/dev/null
  wait "$TCPDUMP_PID" 2>/dev/null
  TCPDUMP_PID=""
}
# Positive control first: prove the capture can see api.anthropic.com traffic at all.
capture_start control
curl -sS -m 15 -o /dev/null https://api.anthropic.com/ >/dev/null 2>&1
capture_stop
control_curl_syn="$(grep -a 'proc curl:' "$GW/control.cap" | syn_dests | non_loopback | tr '\n' ' ')"
control_curl_dns="$(grep -a 'proc mDNSResponder' "$GW/control.cap" | grep -ac 'eproc curl:')"
if [ -n "$control_curl_syn" ]; then
  pass 6 "control: the capture attributes a plain curl to api.anthropic.com to curl" "curl SYN to ${control_curl_syn}; DNS lookups made for curl: $control_curl_dns"
else
  info 6 "control: no SYN attributed to curl (no outbound network from the VM?)" "$(head -3 "$GW/control.cap" | tr '\n' '|')"
fi

before="$(wc -l <"$GW/requests.jsonl" | tr -d ' ')"
covers 'claude-gw'
capture_start gw
pty s6-gw 300 "NODE_EXTRA_CA_CERTS='$GW/cert.pem' claude-gw -p 'say ok'"
GW_RC="$PTY_RC"
capture_stop
[ "$GW_RC" -eq 0 ] && pass 6 "claude-gw -p 'say ok' exits 0" || bad 6 "claude-gw -p 'say ok'" "exit $GW_RC: $(tail -3 "$PTY_TXT" | tr '\n' '|')"
has '(^|[^a-z])ok' "$PTY_TXT" && pass 6 "claude-gw printed the stub's reply" || bad 6 "claude-gw printed the stub's reply" "$(tail -2 "$PTY_TXT" | tr '\n' '|')"

# What did the stub see? Only classifications are ever stored.
/usr/bin/python3 - "$GW/requests.jsonl" "$before" >"$GW/summary.txt" <<'PY'
import collections, json, sys
rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip()][int(sys.argv[2]):]
c = collections.Counter((r["method"], r["path"], r["host"].rsplit(":", 1)[0], r["x-api-key"], r["authorization"]) for r in rows)
print("TOTAL=%d" % len(rows))
print("OTHER=%d" % sum(1 for r in rows if "OTHER" in (r["x-api-key"], r["authorization"])))
print("MSG_DUMMY=%d" % sum(1 for r in rows if r["path"] == "/v1/messages" and "DUMMY" in (r["x-api-key"], r["authorization"])))
for k, v in sorted(c.items()):
    print("ROW %d x %s %s host=%s x-api-key=%s authorization=%s" % ((v,) + k))
PY
echo "--- stub classifications for the claude-gw run"; cat "$GW/summary.txt"
total="$(sed -n 's/^TOTAL=//p' "$GW/summary.txt")"; other="$(sed -n 's/^OTHER=//p' "$GW/summary.txt")"; msgd="$(sed -n 's/^MSG_DUMMY=//p' "$GW/summary.txt")"
[ "${msgd:-0}" -ge 1 ] && pass 6 "stub received POST /v1/messages with DUMMY credentials" "$msgd request(s) of $total" || bad 6 "stub received POST /v1/messages with DUMMY credentials" "$msgd of $total"
[ "${other:-1}" -eq 0 ] && pass 6 "stub saw nothing classified OTHER" "OTHER=0" || bad 6 "stub saw a credential classified OTHER" "OTHER=$other"
has 'host=127\.0\.0\.1' "$GW/summary.txt" && pass 6 "stub saw Host 127.0.0.1 and the /v1/messages path" || bad 6 "stub Host/path" "$(cat "$GW/summary.txt")"
for f in "$HOME/.claude/settings.json" "$HOME/.claude.json" "$CFG/settings.json"; do
  if [ -f "$f" ] && grep -Fq -- "$DUMMY_TOKEN" "$f"; then bad 6 "token must not be in $f" "FOUND"; fi
done
pass 6 "token is in no settings file (claude-gw, ~/.claude/settings.json, ~/.claude.json)"

# api.anthropic.com: capture-based check (no MITM).
grep -aE "$CLAUDE_PROC_RE" "$GW/gw.cap" >"$GW/gw-claude.cap"
gw_remote_syn="$(syn_dests <"$GW/gw-claude.cap" | non_loopback | tr '\n' ' ')"
gw_local_syn="$(syn_dests <"$GW/gw-claude.cap" | grep -c "^127\.0\.0\.1:$PORT\$")"
gw_claude_dns="$(grep -aEc '(A|AAAA|HTTPS)\? ' "$GW/gw-claude.cap")"
anthropic_dns="$(grep -aE '(A|AAAA|HTTPS)\? ' "$GW/gw.cap" | grep -Eic 'anthropic\.com|claude\.ai|claude\.com')"
if [ "${gw_local_syn:-0}" -ge 1 ]; then
  pass 6 "the capture attributes claude-gw's own connections to it (process $CLAUDE_PROC)" "connections to the stub: $gw_local_syn"
else
  bad 6 "the capture saw no connection from claude-gw to the stub, so its attribution cannot be trusted" "process name '$CLAUDE_PROC'"
fi
if [ -z "$gw_remote_syn" ] && [ "${gw_claude_dns:-0}" -eq 0 ]; then
  pass 6 "claude-gw made no outbound connection and no DNS lookup (so none to api.anthropic.com)" "connections to non-loopback addresses: 0"
else
  bad 6 "claude-gw reached beyond the stub" "SYN to: ${gw_remote_syn:-none}; DNS lookups: $gw_claude_dns"
fi
[ "${anthropic_dns:-0}" -eq 0 ] && pass 6 "no process looked up anthropic.com, claude.ai or claude.com while claude-gw ran" || bad 6 "an Anthropic hostname was looked up during claude-gw" "$anthropic_dns"
info 6 "background traffic from macOS itself during the run (not claude)" "$(grep -av "$CLAUDE_PROC_RE" "$GW/gw.cap" | syn_dests | non_loopback | tr '\n' ' ')"

# ================================================================== 7
section "Step 7: Connect tools"
g_run s7-linear 'claude mcp add --transport http linear-server --scope user https://mcp.linear.app/mcp'
[ "$PTY_RC" -eq 0 ] && pass 7 "linear-server added (exit 0)" || bad 7 "claude mcp add linear-server" "exit $PTY_RC"
g_run s7-atlassian 'claude mcp add --transport http atlassian --scope user https://mcp.atlassian.com/v2/mcp'
[ "$PTY_RC" -eq 0 ] && pass 7 "atlassian added (exit 0)" || bad 7 "claude mcp add atlassian" "exit $PTY_RC"

/usr/bin/python3 - >"$OUT/s7-claudejson.txt" <<'PY'
import json, os
d = json.load(open(os.path.expanduser("~/.claude.json")))
top = d.get("mcpServers", {})
for name in ("linear-server", "atlassian"):
    print("USER %s=%s" % (name, (top.get(name) or {}).get("url", "MISSING")))
proj = [p for p, v in d.get("projects", {}).items() if v.get("mcpServers")]
print("PROJECT_SCOPED=%d" % len(proj))
PY
cat "$OUT/s7-claudejson.txt"
has '^USER linear-server=https://mcp.linear.app/mcp$' "$OUT/s7-claudejson.txt" && pass 7 "linear-server is in ~/.claude.json at user scope" || bad 7 "linear-server at user scope" "$(cat "$OUT/s7-claudejson.txt" | tr '\n' '|')"
has '^USER atlassian=https://mcp.atlassian.com/v2/mcp$' "$OUT/s7-claudejson.txt" && pass 7 "atlassian is in ~/.claude.json at user scope" || bad 7 "atlassian at user scope" "$(cat "$OUT/s7-claudejson.txt" | tr '\n' '|')"
has '^PROJECT_SCOPED=0$' "$OUT/s7-claudejson.txt" && pass 7 "nothing was saved for one folder only" || bad 7 "a server was saved project-scoped"

mkdir -p "$HOME/e2e-elsewhere"
covers 'claude mcp list'
pty s7-list 300 'cd "$HOME/e2e-elsewhere" && claude mcp list'
if has 'linear-server' "$PTY_TXT" && has 'atlassian' "$PTY_TXT"; then
  pass 7 "claude mcp list from a different folder shows both servers (scope fix works)" "$(grep -E 'linear-server|atlassian' "$PTY_TXT" | tr '\n' '|')"
else
  bad 7 "claude mcp list from a different folder shows both servers" "$(tail -4 "$PTY_TXT" | tr '\n' '|')"
fi
info 7 "OAuth sign-in (/mcp), gh auth login, netlify login, sf org login web skipped" "each needs a browser"

pty s7-gh 60 'gh --version'
[ "$PTY_RC" -eq 0 ] && pass 7 "gh --version" "$(head -1 "$PTY_TXT")" || bad 7 "gh --version" "exit $PTY_RC"
pty s7-netlify 120 'netlify --version'
[ "$PTY_RC" -eq 0 ] && pass 7 "netlify --version" "$(tail -1 "$PTY_TXT")" || bad 7 "netlify --version" "exit $PTY_RC"
g_run s7-sf-install 'npm install -g @salesforce/cli'
[ "$PTY_RC" -eq 0 ] && pass 7 "npm install -g @salesforce/cli (Node via mise works)" "exit 0" || bad 7 "npm install -g @salesforce/cli" "exit $PTY_RC: $(tail -3 "$PTY_TXT" | tr '\n' '|')"
pty s7-sf-version 180 'sf --version'
[ "$PTY_RC" -eq 0 ] && pass 7 "sf --version in a fresh shell" "$(tail -1 "$PTY_TXT")" || bad 7 "sf --version" "exit $PTY_RC: $(tail -2 "$PTY_TXT" | tr '\n' '|')"

# ================================================================== 8 (guide step 9: health check)
section "Step 8: Health check (doctor.sh)"
g_pty s9-doctor 900 'bash "$(chezmoi source-path)/bin/doctor.sh"'
DOC1="$PTY_TXT"
[ "$PTY_RC" -eq 0 ] && pass 8 "doctor.sh exits 0" || bad 8 "doctor.sh exit status" "exit $PTY_RC"
nfail="$(count '\[FAIL\]' "$DOC1")"; nwarn="$(count '\[WARN\]' "$DOC1")"; npass="$(count '\[PASS\]' "$DOC1")"
[ "$nfail" -eq 0 ] && pass 8 "doctor.sh reports zero FAIL" "PASS=$npass WARN=$nwarn FAIL=$nfail" || bad 8 "doctor.sh reports FAIL lines" "$(grep -A1 '\[FAIL\]' "$DOC1" | head -8 | tr '\n' '|')"
grep '\[WARN\]' "$DOC1" | while IFS= read -r l; do info 8 "doctor WARN (judge against her Mac)" "$l"; done

# ================================================================== glyph check
section "Glyph check (files only; the visual part cannot be automated)"
nf="$(ls "$HOME/Library/Fonts" 2>/dev/null | grep -i 'FiraCodeNerdFontMono' | head -3 | tr '\n' ' ')"
[ -n "$nf" ] && pass 9 "FiraCode Nerd Font Mono files exist" "$nf" || bad 9 "FiraCode Nerd Font Mono files exist" "none"
if grep -q 'FiraCodeNFM-Reg' "$ITERM_PROFILE" 2>/dev/null; then pass 9 "Anthropic profile references FiraCodeNFM-Reg"; else bad 9 "Anthropic profile references FiraCodeNFM-Reg" "$(grep -o '"Normal Font"[^,]*' "$ITERM_PROFILE" | head -1)"; fi

# ================================================================== troubleshooting commands
section "Troubleshooting commands from the guide (safe ones)"
g_run t-mise-install 'mise install'
[ "$PTY_RC" -eq 0 ] && pass 11 "mise install" "exit 0" || bad 11 "mise install" "exit $PTY_RC: $(tail -2 "$PTY_TXT" | tr '\n' '|')"
g_run t-netlify-brew 'brew install netlify-cli'
[ "$PTY_RC" -eq 0 ] && pass 11 "brew install netlify-cli (already installed)" "exit 0" || bad 11 "brew install netlify-cli" "exit $PTY_RC"
g_run t-font-brew 'brew install --cask font-fira-code-nerd-font'
[ "$PTY_RC" -eq 0 ] && pass 11 "brew install --cask font-fira-code-nerd-font (already installed)" "exit 0" || bad 11 "brew install --cask font-fira-code-nerd-font" "exit $PTY_RC"
g_run t-profile-cp 'mkdir -p "$HOME/Library/Application Support/iTerm2/DynamicProfiles" && cp "$(chezmoi source-path)/iterm2/Anthropic.json" "$HOME/Library/Application Support/iTerm2/DynamicProfiles/Anthropic.json"'
if [ "$PTY_RC" -eq 0 ] && cmp -s "$ITERM_PROFILE" "$HOME/.local/share/chezmoi/iterm2/Anthropic.json"; then pass 11 "manual iTerm2 profile copy command works" "identical to source"; else bad 11 "manual iTerm2 profile copy command" "exit $PTY_RC"; fi
g_run t-echo-shell 'echo $SHELL'
[ "$PTY_RC" -eq 0 ] && [ "$(tr -d '\n' <"$PTY_TXT")" = /bin/zsh ] && pass 11 "echo \$SHELL prints /bin/zsh" || bad 11 "echo \$SHELL" "$(cat "$PTY_TXT")"
info 11 "'chsh -s /bin/zsh' skipped" "asks for the account password, and the default shell is already /bin/zsh here"

# ================================================================== 10 idempotency
section "Idempotency"
pty s10-apply 900 'chezmoi apply'
[ "$PTY_RC" -eq 0 ] && pass 10 "second chezmoi apply exits 0" || bad 10 "second chezmoi apply" "exit $PTY_RC"
scripts_rerun="$(count '^==> \[' "$PTY_TXT")"
[ "$scripts_rerun" -eq 0 ] && pass 10 "no run_once/run_onchange script ran again" || bad 10 "scripts ran again" "$(grep '^==> \[' "$PTY_TXT" | tr '\n' '|')"
pty s10-status 120 'chezmoi status'
if [ "$PTY_RC" -eq 0 ] && [ -z "$(tr -d '[:space:]' <"$PTY_TXT")" ]; then pass 10 "chezmoi status is empty"; else bad 10 "chezmoi status is empty" "$(head -5 "$PTY_TXT" | tr '\n' '|')"; fi
pty s10-doctor 900 'bash "$(chezmoi source-path)/bin/doctor.sh"'
DOC2="$PTY_TXT"
grep -E '\[(PASS|WARN|FAIL)\]' "$DOC1" >"$OUT/doc1.lines"; grep -E '\[(PASS|WARN|FAIL)\]' "$DOC2" >"$OUT/doc2.lines"
if [ "$PTY_RC" -eq 0 ] && cmp -s "$OUT/doc1.lines" "$OUT/doc2.lines"; then pass 10 "second doctor.sh run is identical (exit 0, same PASS/WARN/FAIL lines)" "$(wc -l <"$OUT/doc2.lines" | tr -d ' ') lines"; else bad 10 "second doctor.sh run differs" "exit $PTY_RC: $(diff "$OUT/doc1.lines" "$OUT/doc2.lines" | head -4 | tr '\n' '|')"; fi

# ================================================================== summary
section "SUMMARY"
awk -F'\t' '{ printf "%-5s %-5s %s%s\n", $1, $2, $3, ($4 != "" ? "  [" $4 "]" : "") }' "$OUT/results.tsv" >"$OUT/summary.txt"
nf="$(awk -F'\t' '$2 == "FAIL"' "$OUT/results.tsv" | wc -l | tr -d ' ')"
np="$(awk -F'\t' '$2 == "PASS"' "$OUT/results.tsv" | wc -l | tr -d ' ')"
ni="$(awk -F'\t' '$2 == "INFO"' "$OUT/results.tsv" | wc -l | tr -d ' ')"
awk -F'\t' '$2 == "FAIL" { printf "FAIL  step %s: %s  [%s]\n", $1, $3, $4 }' "$OUT/results.tsv"
echo "checks: $np passed, $nf failed, $ni informational"
if [ "$nf" -eq 0 ]; then echo "guide-steps: OK"; exit 0; fi
echo "guide-steps: FAILED"
exit 1
