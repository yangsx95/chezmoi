#!/bin/bash
set -euo pipefail
root=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# Load only function definitions: no host detection, installation, or HOME changes.
sed -n '/^init_or_update_chezmoi() {/,/^}/p; /^run_step() {/,/^}/p; /^print_summary() {/,/^}/p; /^install_mise_tools() {/,/^}/p' "$root/setup.sh" > "$tmp/functions"
source "$tmp/functions"
RED='' GREEN='' YELLOW='' CYAN='' NC=''
export CALL_LOG="$tmp/calls"
chezmoi() {
    printf '%s\n' "$*" >> "$CALL_LOG"
    case "$1" in
        source-path) echo /mock/source ;;
        status) printf '%s' "${TARGET_STATUS:-}" ;;
        update) return "${UPDATE_CODE:-0}" ;;
    esac
}
git() {
    case "$*" in
        *rev-parse*) return 0 ;;
        *status*) printf '%s' "${SOURCE_STATUS:-}" ;;
        *) echo 'unexpected Git mutation' >&2; return 99 ;;
    esac
}
SOURCE_STATUS=' M tracked'
if init_or_update_chezmoi ignored; then exit 1; fi
! grep -q '^update' "$CALL_LOG"
SOURCE_STATUS='?? untracked'
if init_or_update_chezmoi ignored; then exit 1; fi
SOURCE_STATUS=''
TARGET_STATUS='M  .zshrc'
if init_or_update_chezmoi ignored; then exit 1; fi
! grep -q '^update' "$CALL_LOG"
TARGET_STATUS=' M .zshrc'
init_or_update_chezmoi ignored
grep -qx update "$CALL_LOG"
! grep -q -- --force "$CALL_LOG"
UPDATE_CODE=1
if init_or_update_chezmoi ignored; then exit 1; fi
! grep -q '^init' "$CALL_LOG"
STEP_RESULTS=() FAILED_STEPS=0
fail_midway() { false; touch "$tmp/should-not-exist"; }
run_step broken optional fail_midway
[ ! -e "$tmp/should-not-exist" ]
[ "$FAILED_STEPS" -eq 1 ]
skip_step() { return 20; }
run_step skipped optional skip_step
[[ "${STEP_RESULTS[1]}" == '跳过: skipped' ]]
mise() { return 7; }
run_step tools optional install_mise_tools
[ "$FAILED_STEPS" -eq 2 ]
set +e
( run_step critical required fail_midway; touch "$tmp/continued" ) > "$tmp/summary"
code=$?
set -e
[ "$code" -eq 1 ]
[ ! -e "$tmp/continued" ]
grep -q '失败: critical' "$tmp/summary"
printf 'setup safety tests passed\n'
