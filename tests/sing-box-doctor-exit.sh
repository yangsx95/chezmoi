#!/bin/sh
set -eu
source_root=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/sing-box-doctor.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM
# Run actual doctor logic with offline fixtures; never touch live networking.
sed '/^command_name=/,$d' "$source_root/dot_local/bin/executable_sing-box-managed" > "$test_dir/functions"
sed 's|/usr/bin/dig|fixture_dig|g; s|/usr/bin/curl|fixture_curl|g; s|/sbin/route|fixture_route|g' "$source_root/dot_local/libexec/sing-box-diagnostics.sh" >> "$test_dir/functions"
printf '%s\n' \
  'status_all() { return 0; }' \
  'browser_policy_diagnostics() { result_row UNKNOWN "Browser runtime" "not checked"; }' \
  'fixture_route() { echo "interface: en0"; }' \
  'fixture_dig() { case "$*" in *example.com*) echo "example.com. 60 IN A 192.0.2.1" ;; *) echo "This query has been locally blocked" ;; esac; }' \
  'fixture_curl() { [ "${FAIL_HTTP:-0}" = 0 ] || return 28; echo "200 0.1s"; }' \
  'report_failed=0' \
  'result_row FAIL "render-only test" "must not affect aggregate" >/dev/null' \
  '[ "$report_failed" -eq 0 ]' \
  'report_failed=1' \
  'doctor_sing_box' >> "$test_dir/functions"
sh "$test_dir/functions" > "$test_dir/output"
grep -q UNKNOWN "$test_dir/output"
if grep -Eq 'gamebus001|pornhub|hongguoduanju' "$test_dir/output"; then exit 1; fi
code=0
FAIL_HTTP=1 sh "$test_dir/functions" > "$test_dir/output" || code=$?
[ "$code" -eq 1 ]
grep -q '\[FAIL' "$test_dir/output"
