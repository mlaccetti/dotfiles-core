#!/usr/bin/env bash
# test/e2e/run.sh
#
# End-to-end test of the setup guide, on your Mac (the host), in a fresh
# throwaway macOS VM. One command:
#
#     test/e2e/run.sh [preinstalled|fresh|all] [--rebuild] [--keep]
#
# Two scenarios (default: preinstalled):
#   preinstalled  a Mac where iTerm2, VS Code, 1Password, op and Claude Code are
#                 already installed, none of them through Homebrew
#   fresh         a Mac with Homebrew and nothing else: setup must install everything
#
# What it does:
#   1. checks prerequisites (Apple silicon, Tart, ssh, free disk)
#   2. check-guide-coverage.py: every command on the guide is tested or skipped
#      with a reason (fails here, before any VM boots, if the guide changed),
#      then the unit tests in test/unit
#   3. preinstalled only: builds the "sandbox-preinstalled" VM if it does not
#      exist (slow, once). fresh clones "sandbox-base" (Homebrew only) directly.
#   4. clones the scenario's VM to sandbox-run-<scenario>-<timestamp>
#      (copy-on-write, seconds), boots it headless
#   5. copies the in-VM scripts in and runs prepare-run.sh, then guide-steps.sh
#   6. copies the report back, checks that every declared command really ran
#   7. deletes the clone (unless --keep) and exits non-zero on any failure
#
# The guide runs the PUBLIC repo: `chezmoi init --apply
# https://github.com/mlaccetti/dotfiles-core`, exactly as a reader will. So a fix
# has to be merged to the default branch before this run can see it.
#
# No real credentials ever enter the VM. See README.md.
# shellcheck disable=SC2029,SC2329
# (SC2029: the remote commands are fixed strings. SC2329: cleanup runs from the EXIT trap.)
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

BASE_IMAGE="${E2E_BASE_IMAGE:-ghcr.io/cirruslabs/macos-tahoe-base:latest}"
BASE_VM="${E2E_BASE_VM:-sandbox-base}"
PREINSTALLED_VM="${E2E_PREINSTALLED_VM:-sandbox-preinstalled}"
MIN_FREE_GB_RUN=25
MIN_FREE_GB_BUILD=60

KEEP=0
REBUILD=0
REPORT_DIR=""
SCENARIOS=""
while [ $# -gt 0 ]; do
  case "$1" in
    preinstalled | fresh | all) [ -z "$SCENARIOS" ] || { echo "only one scenario may be given" >&2; exit 2; }; SCENARIOS="$1" ;;
    --keep) KEEP=1 ;;
    --rebuild) REBUILD=1 ;;
    --report-dir) shift; REPORT_DIR="${1:-}" ;;
    -h | --help)
      cat <<'USAGE'
Usage: test/e2e/run.sh [preinstalled|fresh|all] [--keep] [--rebuild] [--report-dir DIR]

  preinstalled    (default) apps already installed, none through Homebrew
  fresh           Homebrew only; the guide's setup must install everything
  all             both, one after the other

  --keep          leave the sandbox-run-<scenario>-<timestamp> VM on disk for debugging
  --rebuild       delete and rebuild sandbox-preinstalled from sandbox-base
                  (no effect on fresh, which clones sandbox-base directly)
  --report-dir D  write the reports to D/<scenario> (default: test/e2e/reports/<timestamp>/<scenario>)

Exit status: 0 = every check passed, 1 = a check failed, 2 = could not run.
USAGE
      exit 0
      ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

[ -n "$SCENARIOS" ] || SCENARIOS=preinstalled
STAMP="$(date +%Y%m%d-%H%M%S)"
RUN_VM=""
REPORTS_ROOT="${REPORT_DIR:-$HERE/reports/$STAMP}"
REPORT_DIR="$REPORTS_ROOT"
mkdir -p "$REPORTS_ROOT" || exit 2

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'run.sh: %s\n' "$*" >&2; exit 2; }

# ---------------------------------------------------------------- ssh helpers
# The VM's documented login is admin/admin. SSH_ASKPASS is used instead of
# sshpass because sshpass lost the password-prompt race on about 1 connection in
# 10. Host key checking and agent keys are off on purpose: this VM is throwaway,
# its host key changes on every clone, and no host key may ever be offered to it.
ASKPASS_DIR="$(mktemp -d "${TMPDIR:-/tmp}/e2e-askpass.XXXXXX")" || die "mktemp failed"
printf '#!/bin/sh\necho admin\n' >"$ASKPASS_DIR/askpass.sh"
chmod 700 "$ASKPASS_DIR" "$ASKPASS_DIR/askpass.sh"
SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PubkeyAuthentication=no
  -o "PreferredAuthentications=password,keyboard-interactive" -o NumberOfPasswordPrompts=1
  -o ConnectTimeout=10 -o ServerAliveInterval=30 -o ServerAliveCountMax=60 -o LogLevel=ERROR)
vm_ssh() { # IP cmd...
  local ip="$1"; shift
  SSH_ASKPASS="$ASKPASS_DIR/askpass.sh" SSH_ASKPASS_REQUIRE=force ssh "${SSH_OPTS[@]}" "admin@$ip" "$@" </dev/null
}
vm_scp() { # scp args...
  SSH_ASKPASS="$ASKPASS_DIR/askpass.sh" SSH_ASKPASS_REQUIRE=force scp -r "${SSH_OPTS[@]}" "$@"
}

CURRENT_VM=""
cleanup() {
  local rc=$?
  if [ -n "$CURRENT_VM" ]; then
    if [ "$KEEP" -eq 1 ] && [ "$CURRENT_VM" = "$RUN_VM" ]; then
      echo "run.sh: --keep given, leaving VM $CURRENT_VM (delete with: tart stop $CURRENT_VM; tart delete $CURRENT_VM)"
    else
      tart stop "$CURRENT_VM" >/dev/null 2>&1
      tart delete "$CURRENT_VM" >/dev/null 2>&1 && echo "run.sh: deleted VM $CURRENT_VM"
    fi
  fi
  rm -rf "$ASKPASS_DIR"
  exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

vm_exists() { tart list --source local --quiet 2>/dev/null | grep -qx -- "$1"; }

# boot_vm NAME: start headless, wait for an IP and for ssh; sets VM_IP.
boot_vm() {
  local name="$1"
  tart run --no-graphics "$name" >"$REPORT_DIR/tart-$name.log" 2>&1 &
  VM_IP="$(tart ip "$name" --wait 240 2>/dev/null)" || die "VM $name got no IP (see $REPORT_DIR/tart-$name.log)"
  for _ in $(seq 1 60); do
    if vm_ssh "$VM_IP" true 2>/dev/null; then return 0; fi
    sleep 3
  done
  die "ssh to $name ($VM_IP) never came up"
}

free_gb() { df -g "$HOME" | awk 'NR==2 {print $4}'; }

# ---------------------------------------------------------------- 1. prerequisites
log "Prerequisites"
[ "$(uname -m)" = arm64 ] || die "needs an Apple silicon Mac (uname -m is $(uname -m))"
[ "$(sysctl -n kern.hv_support 2>/dev/null)" = 1 ] || die "Hypervisor.framework is not available (sysctl kern.hv_support is not 1)"
command -v tart >/dev/null 2>&1 || die "tart not found on PATH. Install it from the release tarball, see test/e2e/README.md"
for tool in ssh scp python3 awk; do command -v "$tool" >/dev/null 2>&1 || die "$tool not found"; done
echo "tart $(tart --version)"
FREE="$(free_gb)"
need="$MIN_FREE_GB_RUN"
if ! vm_exists "$BASE_VM"; then
  need="$MIN_FREE_GB_BUILD"
elif [ "$SCENARIOS" != fresh ] && { [ "$REBUILD" -eq 1 ] || ! vm_exists "$PREINSTALLED_VM"; }; then
  need="$MIN_FREE_GB_BUILD"
fi
[ "${FREE:-0}" -ge "$need" ] || die "only ${FREE}GB free, need ${need}GB (see README: disk needs)"
echo "free disk: ${FREE}GB (need ${need}GB)"

# ---------------------------------------------------------------- 2. guide coverage
log "Guide coverage (every command on the guide is tested or skipped with a reason)"
python3 "$HERE/check-guide-coverage.py" | tee "$REPORTS_ROOT/coverage-static.txt"
[ "${PIPESTATUS[0]}" -eq 0 ] || die "guide coverage check failed: update test/e2e/guide-steps.sh or the skip list in check-guide-coverage.py"

# ---------------------------------------------------------------- 2b. unit tests
log "Unit tests (test/unit, seconds, no VM)"
for t in "$HERE"/../unit/*.sh; do
  bash "$t" 2>&1 | tee -a "$REPORTS_ROOT/unit.txt"
  [ "${PIPESTATUS[0]}" -eq 0 ] || { echo "run.sh: unit test failed: $t" >&2; exit 1; }
done

# ---------------------------------------------------------------- 3. the preinstalled image
# The Cirrus base image is a Mac with Homebrew and no apps (checked: no iTerm2,
# VS Code, 1Password, op, Claude or Nerd Font). The fresh scenario therefore
# clones sandbox-base as it is. The preinstalled scenario needs the apps put on
# first, which is slow, so it is done once and kept as sandbox-preinstalled.
build_preinstalled() {
  if [ "$REBUILD" -eq 1 ] && vm_exists "$PREINSTALLED_VM"; then
    log "Rebuilding: deleting $PREINSTALLED_VM"
    tart delete "$PREINSTALLED_VM" || die "could not delete $PREINSTALLED_VM"
  fi
  vm_exists "$PREINSTALLED_VM" && return 0
  log "Building $PREINSTALLED_VM (one time; the first image pull is about 33 GB)"
  if ! vm_exists "$BASE_VM"; then
    tart clone "$BASE_IMAGE" "$BASE_VM" || die "could not pull $BASE_IMAGE"
  fi
  # Provision a throwaway clone, never the base: the base must stay the vendor
  # image so a rebuild always proves the script from a clean start.
  local build_vm="sandbox-build-${STAMP}"
  tart clone "$BASE_VM" "$build_vm" || die "could not clone $BASE_VM"
  CURRENT_VM="$build_vm"
  boot_vm "$build_vm"
  vm_scp "$HERE/provision-preinstalled.sh" "admin@$VM_IP:provision-preinstalled.sh" || die "could not copy the provisioning script"
  vm_ssh "$VM_IP" 'bash ~/provision-preinstalled.sh' 2>&1 | tee "$REPORTS_ROOT/provision.log"
  [ "${PIPESTATUS[0]}" -eq 0 ] || die "provisioning failed (see $REPORTS_ROOT/provision.log)"
  tart stop "$build_vm" >/dev/null 2>&1
  tart rename "$build_vm" "$PREINSTALLED_VM" || die "could not rename $build_vm to $PREINSTALLED_VM"
  CURRENT_VM=""
}

# ---------------------------------------------------------------- 4-6. one scenario
# run_scenario NAME: sets SCENARIO_RESULT (0 = pass, 1 = a check failed).
run_scenario() {
  local scen="$1" source_vm
  case "$scen" in
    preinstalled) build_preinstalled; source_vm="$PREINSTALLED_VM" ;;
    fresh)
      vm_exists "$BASE_VM" || { log "Pulling $BASE_IMAGE as $BASE_VM (about 33 GB)"; tart clone "$BASE_IMAGE" "$BASE_VM" || die "could not pull $BASE_IMAGE"; }
      source_vm="$BASE_VM" ;;
  esac
  REPORT_DIR="$REPORTS_ROOT/$scen"
  mkdir -p "$REPORT_DIR" || die "could not create $REPORT_DIR"
  SCENARIO_RESULT=0

  RUN_VM="sandbox-run-${scen}-${STAMP}"
  log "[$scen] Fresh VM: $RUN_VM (clone of $source_vm)"
  tart clone "$source_vm" "$RUN_VM" || die "could not clone $source_vm"
  CURRENT_VM="$RUN_VM"
  boot_vm "$RUN_VM"
  echo "booted, ip $VM_IP"

  log "[$scen] Copying the in-VM scripts"
  vm_ssh "$VM_IP" 'rm -rf ~/e2e ~/e2e-out && mkdir -p ~/e2e' || die "could not prepare ~/e2e in the VM"
  vm_scp "$HERE/prepare-run.sh" "$HERE/guide-steps.sh" "$HERE/stub-gateway.py" "$HERE/pty-run.exp" "$HERE/pty-session.exp" \
    "admin@$VM_IP:e2e/" || die "could not copy scripts into the VM"

  log "[$scen] prepare-run.sh (make the VM faithful)"
  vm_ssh "$VM_IP" "E2E_SCENARIO=$scen bash ~/e2e/prepare-run.sh" 2>&1 | tee "$REPORT_DIR/prepare-run.log"
  if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    echo "run.sh: prepare-run.sh failed" >&2
    SCENARIO_RESULT=1
  fi

  if [ "$SCENARIO_RESULT" -eq 0 ]; then
    log "[$scen] guide-steps.sh (the guide, in order)"
    vm_ssh "$VM_IP" "E2E_SCENARIO=$scen bash ~/e2e/guide-steps.sh" 2>&1 | tee "$REPORT_DIR/guide-steps.log"
    [ "${PIPESTATUS[0]}" -eq 0 ] || SCENARIO_RESULT=1
  fi

  log "[$scen] Collecting the report"
  vm_scp "admin@$VM_IP:e2e-out" "$REPORT_DIR/" >/dev/null 2>&1 || echo "run.sh: could not copy ~/e2e-out back" >&2
  if [ -s "$REPORT_DIR/e2e-out/covered.txt" ]; then
    python3 "$HERE/check-guide-coverage.py" --executed "$REPORT_DIR/e2e-out/covered.txt" | tee "$REPORT_DIR/coverage.txt"
    [ "${PIPESTATUS[0]}" -eq 0 ] || SCENARIO_RESULT=1
  fi

  log "[$scen] Result"
  if [ -s "$REPORT_DIR/e2e-out/summary.txt" ]; then cat "$REPORT_DIR/e2e-out/summary.txt"; fi
  echo "report: $REPORT_DIR"
  if [ "$SCENARIO_RESULT" -eq 0 ]; then echo "e2e[$scen]: PASS"; else echo "e2e[$scen]: FAIL"; fi

  # Delete this scenario's clone now (unless --keep), so two scenarios never
  # hold two clones at once.
  if [ "$KEEP" -eq 1 ]; then
    echo "run.sh: --keep given, leaving VM $RUN_VM (delete with: tart stop $RUN_VM; tart delete $RUN_VM)"
    CURRENT_VM=""
  else
    tart stop "$RUN_VM" >/dev/null 2>&1
    tart delete "$RUN_VM" >/dev/null 2>&1 && echo "run.sh: deleted VM $RUN_VM"
    CURRENT_VM=""
  fi
}

if [ "$SCENARIOS" = all ]; then LIST="preinstalled fresh"; else LIST="$SCENARIOS"; fi
RESULT=0
SUMMARY=""
for scen in $LIST; do
  run_scenario "$scen"
  SUMMARY="${SUMMARY}  ${scen}: $([ "$SCENARIO_RESULT" -eq 0 ] && echo PASS || echo FAIL)"$'\n'
  [ "$SCENARIO_RESULT" -eq 0 ] || RESULT=1
done

log "Result"
printf '%s' "$SUMMARY"
if [ "$RESULT" -eq 0 ]; then echo "e2e: PASS"; else echo "e2e: FAIL"; fi
exit "$RESULT"
