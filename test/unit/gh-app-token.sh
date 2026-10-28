#!/usr/bin/env bash
# Unit test for dot_local/bin/executable_gh, the gh wrapper that gives coding
# agents a GitHub App token instead of your own gh login.
#
# Runs the wrapper in a scratch HOME against a stub `op` (1Password), a stub
# `gh-token` and a stub real `gh` that records the GH_TOKEN it was handed. No
# network, no 1Password, no real sleeps: the clock comes from
# GH_APP_TOKEN_NOW, and the concurrency case waits on FIFOs, not timers.
# Touches nothing else.
# shellcheck disable=SC2015,SC2016
# (SC2015: `check && ok ... || no ...` is safe because ok always succeeds.
# SC2016: the stub scripts are single-quoted on purpose, so their $-expressions
# expand when the stubs run, not here.)
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAPPER="$HERE/../../dot_local/bin/executable_gh"
FAILS=0
ok() { printf 'ok   %s\n' "$1"; }
no() { printf 'FAIL %s\n' "$1"; FAILS=$((FAILS + 1)); }

TMP="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/gh-app-token.XXXXXX")" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

# Start from a clean slate: this test may itself run inside an agent session.
unset CLAUDECODE CODEX_THREAD_ID CODEX_SANDBOX CURSOR_AGENT ANTIGRAVITY_AGENT GEMINI_CLI \
  GH_TOKEN GITHUB_TOKEN GH_REPO GH_HOST GH_APP_TOKEN_ENABLE GH_APP_TOKEN_DISABLE \
  GH_APP_TOKEN_DEBUG GH_APP_TOKEN_REAL_GH
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/home/.config" XDG_CACHE_HOME="$TMP/home/.cache"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$TMP/gitconfig" GIT_CEILING_DIRECTORIES="$TMP"
export STUB_LOG="$TMP/log"
NOW=1800000000 # 2027-01-15T08:00:00Z
export GH_APP_TOKEN_NOW="$NOW" STUB_EXPIRES_AT="2027-01-15T09:00:00Z"
mkdir -p "$HOME" "$STUB_LOG" "$TMP/wrap" "$TMP/stubs" "$TMP/real" "$TMP/nogit"
: >"$TMP/gitconfig"
cp "$WRAPPER" "$TMP/wrap/gh"
chmod +x "$TMP/wrap/gh"
W="$TMP/wrap/gh"
CACHE="$XDG_CACHE_HOME/gh-app-token"
CONFIG="$XDG_CONFIG_HOME/gh-app-token/apps"
ALL="$TMP/all-output" # everything the wrapper ever printed, checked for secrets at the end
: >"$ALL"

# Stub 1Password: op read op://Vault/<item>/<field>. Item names have spaces on
# purpose, since real vault and item names often do.
cat >"$TMP/stubs/op" <<'EOF'
#!/bin/bash
[ "$1" = read ] || exit 2
printf '%s\n' "$2" >>"$STUB_LOG/op.log"
if [ -n "${STUB_OP_FAIL:-}" ]; then
  echo '[ERROR] 2027/01/15 08:00:00 not currently signed in' >&2
  exit 1
fi
item="${2%/*}"
item="${item##*/}"
case "${2##*/}" in
  app_id) printf 'id-%s\n' "$item" ;;
  installation_id) printf 'inst-%s\n' "$item" ;;
  private_key) printf -- '-----BEGIN RSA PRIVATE KEY-----\nKEYMATERIAL-%s\n-----END RSA PRIVATE KEY-----\n' "$item" ;;
  *) echo "[ERROR] no field ${2##*/}" >&2; exit 1 ;;
esac
EOF

# The token mimics GitHub's current installation tokens: compact "token":"..."
# and a long body with "." and "-" (a 383-character token broke the first
# version, which only accepted [A-Za-z0-9_]).
# Stub gh-token: checks it was handed the key of the right App, optionally
# blocks on a gate FIFO, and prints gh-token's JSON with a token named after
# the App and the mint number.
cat >"$TMP/stubs/gh-token" <<'EOF'
#!/bin/bash
[ "$1" = generate ] || exit 2
shift
app="" inst="" key=""
while [ $# -gt 0 ]; do
  case "$1" in
    --app-id) app="$2"; shift 2 ;;
    --installation-id) inst="$2"; shift 2 ;;
    --key) key="$2"; shift 2 ;;
    *) shift ;;
  esac
done
item="${app#id-}"
keydata="$(cat "$key" 2>/dev/null)"
case "$keydata" in
  *"KEYMATERIAL-$item"*) ;;
  *) echo "unable to parse key from PEM to RSA format" >&2; exit 1 ;;
esac
[ "$inst" = "inst-$item" ] || { echo "wrong installation id" >&2; exit 1; }
printf 'app=%s keypath=%s\n' "$app" "$key" >>"$STUB_LOG/mint.log"
n="$(wc -l <"$STUB_LOG/mint.log" | tr -d ' ')"
if [ -n "${STUB_GATE:-}" ]; then read -r _ <"$STUB_GATE"; fi
if [ -n "${STUB_MINT_FAIL:-}" ]; then
  echo "failed generating installation token: unexpected status code: 401" >&2
  exit 1
fi
printf '{\n  "token":"ghs_%s_%s.eyJhbGciOiJSUzI1NiJ9-real-format.c2lnbmF0dXJl-x",\n  "expires_at": "%s",\n  "permissions": {\n    "metadata": "read"\n  }\n}\n' \
  "$(printf '%s' "$item" | tr -c 'A-Za-z0-9' _)" "$n" "$STUB_EXPIRES_AT"
EOF

# Stub real gh: records the GH_TOKEN it received and its arguments, prints nothing.
cat >"$TMP/real/gh" <<'EOF'
#!/bin/bash
printf '%s\t%s\n' "${GH_TOKEN-<unset>}" "$*" >>"$STUB_LOG/gh.log"
EOF
chmod +x "$TMP/stubs/op" "$TMP/stubs/gh-token" "$TMP/real/gh"

BASE_PATH="/usr/bin:/bin:/usr/sbin:/sbin"
export PATH="$TMP/wrap:$TMP/stubs:$TMP/real:$BASE_PATH"

mkdir -p "$(dirname "$CONFIG")"
# acme is the default account (first line). Octo-Org is written with capitals
# to show owners match case-insensitively.
printf '# test accounts\n\nacme\top://Test Vault/acme app\nOcto-Org\top://Test Vault/octo app\n' >"$CONFIG"

ACME="ghs_acme_app_"
OCTO="ghs_octo_app_"
# The body the stub gh-token appends after the per-mint counter.
TOKSUFFIX=".eyJhbGciOiJSUzI1NiJ9-real-format.c2lnbmF0dXJl-x"

mints() { if [ -f "$STUB_LOG/mint.log" ]; then wc -l <"$STUB_LOG/mint.log" | tr -d ' '; else echo 0; fi; }
reset_cache() { rm -rf "$CACHE" "$STUB_LOG/mint.log" "$STUB_LOG/op.log"; }

# call [VAR=value ...] -- [gh args ...]: run the wrapper from $CWD. Sets RC,
# OUT, ERR, CALLED (times the real gh ran) and GOT (the GH_TOKEN it received).
CWD="$TMP/nogit"
call() {
  local envs=()
  while [ $# -gt 0 ] && [ "$1" != -- ]; do
    envs+=("$1")
    shift
  done
  shift
  : >"$STUB_LOG/gh.log"
  (cd "$CWD" && env ${envs[@]+"${envs[@]}"} "$W" "$@") >"$TMP/out" 2>"$TMP/err"
  RC=$?
  OUT="$(cat "$TMP/out")"
  ERR="$(cat "$TMP/err")"
  cat "$TMP/out" "$TMP/err" >>"$ALL"
  CALLED="$(wc -l <"$STUB_LOG/gh.log" | tr -d ' ')"
  GOT="$(cut -f1 "$STUB_LOG/gh.log" | tail -n 1)"
}

# expect NAME PREFIX: the real gh ran once with a GH_TOKEN starting PREFIX
# (or exactly "<unset>").
expect() {
  if [ "$RC" -ne 0 ] || [ "$CALLED" != 1 ]; then
    no "$1 (exit $RC, real gh ran $CALLED times, stderr: $ERR)"
    return
  fi
  case "$GOT" in
    "$2"*) ok "$1" ;;
    *) no "$1 (real gh got GH_TOKEN '${GOT}', wanted '$2...')" ;;
  esac
}

# ---- hand-over cases ------------------------------------------------------------
reset_cache
call -- pr list
expect "outside an agent session: real gh, no GH_TOKEN" "<unset>"
[ "$(mints)" = 0 ] && [ ! -f "$STUB_LOG/op.log" ] && ok "outside an agent session: no mint, no 1Password" ||
  no "outside an agent session: minted or read 1Password"
[ -z "$OUT$ERR" ] && ok "outside an agent session: prints nothing of its own" || no "outside an agent session printed: $OUT$ERR"
call -- api user -q .login
[ "$(cut -f2 "$STUB_LOG/gh.log")" = "api user -q .login" ] && ok "arguments reach the real gh unchanged" ||
  no "arguments changed: $(cut -f2 "$STUB_LOG/gh.log")"

call CLAUDECODE=1 GH_TOKEN=explicit-token -- pr list
expect "an explicit GH_TOKEN wins" "explicit-token"
call CLAUDECODE=1 GITHUB_TOKEN=explicit-token -- pr list
expect "an explicit GITHUB_TOKEN wins (gh gets no GH_TOKEN)" "<unset>"
call CLAUDECODE=1 GH_APP_TOKEN_DISABLE=1 -- pr list
expect "GH_APP_TOKEN_DISABLE=1 opts out" "<unset>"
call CLAUDECODE=1 -- --version
expect "gh --version needs no token" "<unset>"
call CLAUDECODE=1 -- help
expect "gh help needs no token" "<unset>"
[ "$(mints)" = 0 ] && ok "no mint for any hand-over case" || no "a hand-over case minted"

mv "$CONFIG" "$CONFIG.off"
call CLAUDECODE=1 -- pr list
expect "no config file: real gh with your own login" "<unset>"
mv "$CONFIG.off" "$CONFIG"

# ---- agent session markers ----------------------------------------------------------
reset_cache
call CLAUDECODE=1 -- pr list
expect "CLAUDECODE: App token of the default account" "$ACME"
for marker in CODEX_THREAD_ID=019a-thread CODEX_SANDBOX=seatbelt CURSOR_AGENT=1 ANTIGRAVITY_AGENT=1 GEMINI_CLI=1 GH_APP_TOKEN_ENABLE=1; do
  call "$marker" -- pr list
  expect "${marker%%=*}: App token" "$ACME"
done
[ "$(mints)" = 1 ] && ok "one mint, then the cached token for every later call" || no "minted $(mints) times, wanted 1"
call GH_APP_TOKEN_ENABLE=0 -- pr list
expect "GH_APP_TOKEN_ENABLE=0 is not an opt-in" "<unset>"

# ---- which account -----------------------------------------------------------------------
target() { # NAME PREFIX GH-ARGS...: in an agent session, gh ARGS uses PREFIX's App
  local name="$1" want="$2"
  shift 2
  call CLAUDECODE=1 -- "$@"
  expect "$name" "$want"
}
target "-R OWNER/REPO" "$OCTO" -R octo-org/x pr list
target "--repo=OWNER/REPO" "$OCTO" pr list --repo=octo-org/x
target "--repo OWNER/REPO" "$OCTO" pr list --repo octo-org/x
target "-ROWNER/REPO" "$OCTO" pr list -Rocto-org/x
target "-R HOST/OWNER/REPO" "$OCTO" pr list -R github.com/octo-org/x
target "-R with a URL" "$OCTO" pr list -R https://github.com/octo-org/x
target "owners match case-insensitively" "$OCTO" pr list -R OCTO-ORG/x
target "gh api repos/OWNER/..." "$OCTO" api repos/octo-org/x/pulls
target "gh api /repos/OWNER/..." "$OCTO" api /repos/octo-org/x
target "gh api orgs/OWNER/... after a flag value" "$OCTO" api -H "Accept: application/json" orgs/octo-org/teams
target "gh api users/OWNER" "$OCTO" api users/octo-org
target "gh api with a full API URL" "$OCTO" api --method GET https://api.github.com/repos/octo-org/x
target "gh api graphql -F owner=OWNER" "$OCTO" api graphql -F owner=octo-org -f query=q
target "a github.com URL argument" "$OCTO" pr view https://github.com/octo-org/x/pull/1
target "gh repo view OWNER/REPO" "$OCTO" repo view octo-org/x
target "a flag after -- is not -R" "$ACME" pr list -- -R octo-org/x

call CLAUDECODE=1 GH_REPO=octo-org/x -- issue list
expect "GH_REPO" "$OCTO"
call CLAUDECODE=1 GH_REPO=octo-org/x -- issue list -R acme/x
expect "-R beats GH_REPO" "$ACME"
call CLAUDECODE=1 GH_REPO=acme/x -- pr view https://github.com/octo-org/x/pull/2
expect "a URL argument beats GH_REPO" "$OCTO"

for form in "git@github.com:octo-org/x.git" "https://github.com/octo-org/x.git" "ssh://git@github.com/octo-org/x.git"; do
  rm -rf "$TMP/repo"
  git init -q "$TMP/repo"
  git -C "$TMP/repo" remote add origin "$form"
  CWD="$TMP/repo"
  call CLAUDECODE=1 -- pr list
  expect "git origin $form" "$OCTO"
done
call CLAUDECODE=1 -- api 'repos/{owner}/{repo}/pulls'
expect "gh api repos/{owner}/... falls back to the git origin" "$OCTO"
call CLAUDECODE=1 -- pr list -R acme/x
expect "-R beats the git origin" "$ACME"
CWD="$TMP/nogit"
call CLAUDECODE=1 -- api 'repos/{owner}/{repo}/pulls'
expect "no owner anywhere: the default account" "$ACME"

call CLAUDECODE=1 -- pr list -R stranger/x
expect "an owner with no App uses the default account's App" "$ACME"
[ -z "$ERR" ] && ok "  ...and says nothing about it without GH_APP_TOKEN_DEBUG" || no "unknown owner printed: $ERR"
call CLAUDECODE=1 GH_APP_TOKEN_DEBUG=1 -- pr list -R stranger/x
case "$ERR" in
  *stranger*"default account"*acme*) ok "  ...and says so with GH_APP_TOKEN_DEBUG=1" ;;
  *) no "GH_APP_TOKEN_DEBUG=1 did not explain the default fallback: $ERR" ;;
esac

# ---- the cache -----------------------------------------------------------------------------
reset_cache
call CLAUDECODE=1 -- pr list
expect "first call mints" "${ACME}1"
call CLAUDECODE=1 GH_APP_TOKEN_NOW=$((NOW + 2900)) -- pr list
expect "11 minutes left: the cached token" "${ACME}1"
call CLAUDECODE=1 GH_APP_TOKEN_NOW=$((NOW + 3000)) -- pr list
expect "10 minutes left: a fresh token" "${ACME}2"
[ "$(mints)" = 2 ] && ok "re-minted exactly once near expiry" || no "minted $(mints) times, wanted 2"
call CLAUDECODE=1 -- pr list -R octo-org/x
expect "each account has its own cached token" "${OCTO}3"
mode() { stat -f %Lp "$1" 2>/dev/null || stat -c %a "$1"; }
[ "$(mode "$CACHE")" = 700 ] && ok "cache folder is 0700" || no "cache folder mode $(mode "$CACHE")"
[ "$(mode "$CACHE/acme.token")" = 600 ] && ok "cache file is 0600" || no "cache file mode $(mode "$CACHE/acme.token")"
chmod 755 "$CACHE"
call CLAUDECODE=1 -- pr list
[ "$(mode "$CACHE")" = 700 ] && ok "a loosened cache folder is tightened again" || no "cache folder left at $(mode "$CACHE")"
keypath="$(sed -n 's/.*keypath=//p' "$STUB_LOG/mint.log" | head -n 1)"
case "$keypath" in
  /dev/fd/* | /proc/*) ok "the key reaches gh-token through a pipe ($keypath)" ;;
  *) no "the key was passed as a file on disk: $keypath" ;;
esac

# ---- concurrent calls mint once ------------------------------------------------------------
# The first call holds the lock and blocks inside gh-token on a gate. The test
# waits (on a FIFO, no timer) until the other four report they are waiting for
# that lock, then opens the gate. All five must get the one token.
reset_cache
EV="$TMP/events"
GATE="$TMP/gate"
mkfifo "$EV" "$GATE"
exec 7<>"$EV" 8<>"$GATE"
await() { # TEXT COUNT: read events until TEXT was seen COUNT times
  local n=0 line
  while [ "$n" -lt "$2" ]; do
    IFS= read -r -t 20 line <&7 || return 1
    case "$line" in *"$1"*) n=$((n + 1)) ;; esac
  done
}
: >"$STUB_LOG/gh.log"
conc() {
  (cd "$TMP/nogit" && CLAUDECODE=1 GH_APP_TOKEN_DEBUG=1 STUB_GATE="$GATE" "$W" pr list 2>&1 >>"$TMP/conc-out") |
    tee -a "$ALL" >"$EV" &
}
conc
await "minting a token for acme" 1 && ok "concurrent: the first call takes the lock and mints" ||
  no "concurrent: the first call never started minting"
for _ in 1 2 3 4; do conc; done
await "waiting for another gh call" 4 && ok "concurrent: the other four wait for the lock" ||
  no "concurrent: the other calls did not wait for the lock"
# One line per call, so a broken lock (five minters at the gate) cannot hang the test.
printf 'go\ngo\ngo\ngo\ngo\n' >&8
wait
exec 7>&- 8>&-
[ "$(mints)" = 1 ] && ok "concurrent: five calls, one mint" || no "concurrent: minted $(mints) times"
[ "$(cut -f1 "$STUB_LOG/gh.log" | sort -u)" = "${ACME}1${TOKSUFFIX}" ] && [ "$(wc -l <"$STUB_LOG/gh.log" | tr -d ' ')" = 5 ] &&
  ok "concurrent: all five got that token" || no "concurrent: gh got $(cut -f1 "$STUB_LOG/gh.log" | sort | uniq -c | tr '\n' ' ')"
cat "$TMP/conc-out" >>"$ALL"

# ---- fail closed -------------------------------------------------------------------------------
fails_closed() { # NAME WANT-IN-MESSAGE
  if [ "$RC" -ne 0 ] && [ "$CALLED" = 0 ]; then ok "$1: exits non-zero without running gh"; else
    no "$1: exit $RC, real gh ran $CALLED times"
  fi
  if [ "$(printf '%s\n' "$ERR" | wc -l | tr -d ' ')" = 1 ] && [[ "$ERR" == *acme* ]] && [[ "$ERR" == *"Fix:"* ]] && [[ "$ERR" == *"$2"* ]]; then
    ok "$1: one line naming the account and the fix"
  else
    no "$1: message was: $ERR"
  fi
}
reset_cache
call CLAUDECODE=1 STUB_MINT_FAIL=1 -- pr list
fails_closed "gh-token fails" "status code: 401"
call CLAUDECODE=1 STUB_OP_FAIL=1 -- pr list
fails_closed "1Password is locked" "op signin"
call CLAUDECODE=1 PATH="$TMP/wrap:$TMP/real:$BASE_PATH" -- pr list
fails_closed "op is missing" "1password-cli"
mkdir -p "$TMP/oponly"
cp "$TMP/stubs/op" "$TMP/oponly/op"
call CLAUDECODE=1 PATH="$TMP/wrap:$TMP/oponly:$TMP/real:$BASE_PATH" -- pr list
fails_closed "gh-token is missing" "mise install"
call CLAUDECODE=1 -- pr list
call CLAUDECODE=1 STUB_MINT_FAIL=1 GH_APP_TOKEN_NOW=$((NOW + 3500)) -- pr list
fails_closed "an expiring cached token is not used when the re-mint fails" "status code: 401"
mkdir -p "$TMP/badcfg/gh-app-token"
printf 'acme\tTest Vault/acme app\n' >"$TMP/badcfg/gh-app-token/apps"
call CLAUDECODE=1 XDG_CONFIG_HOME="$TMP/badcfg" -- pr list
fails_closed "a reference that is not op://" "op://"

# ---- finding the real gh -----------------------------------------------------------------------
mkdir -p "$TMP/wrap2" "$TMP/real2"
ln -s "$W" "$TMP/wrap2/gh"
call PATH="$TMP/wrap:$TMP/wrap2:$TMP/wrap:$TMP/stubs:$TMP/real:$BASE_PATH" -- pr list
expect "skips itself, a symlink to itself and repeats on PATH" "<unset>"
printf '#!/bin/bash\nprintf "real2\\t%%s\\n" "$*" >>"$STUB_LOG/gh.log"\n' >"$TMP/real2/gh"
chmod +x "$TMP/real2/gh"
call GH_APP_TOKEN_REAL_GH="$TMP/real2/gh" -- pr list
[ "$GOT" = real2 ] && ok "GH_APP_TOKEN_REAL_GH picks the real gh" || no "GH_APP_TOKEN_REAL_GH ignored (got '$GOT')"
call PATH="$TMP/wrap:$TMP/stubs:$BASE_PATH" -- pr list
[ "$RC" = 127 ] && [[ "$ERR" == *"no real gh"* ]] && ok "no real gh: exit 127 with a fix" || no "no real gh: exit $RC, $ERR"

# ---- secrets ----------------------------------------------------------------------------------
if grep -q 'ghs_' "$ALL"; then no "a token appeared on stdout or stderr"; else ok "no token ever on stdout or stderr"; fi
if grep -q 'KEYMATERIAL' "$ALL"; then no "key material appeared on stdout or stderr"; else ok "no key material ever on stdout or stderr"; fi
if grep -rq 'KEYMATERIAL' "$HOME" 2>/dev/null; then no "key material was written under HOME"; else ok "the key never touched disk"; fi

if [ "$FAILS" -eq 0 ]; then echo "gh-app-token: OK"; exit 0; fi
echo "gh-app-token: $FAILS failure(s)"
exit 1
