#!/bin/sh
set -eu

source_root=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
export SING_BOX_DIAGNOSTICS_MODULE="$source_root/dot_local/libexec/sing-box-diagnostics.sh"
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/sing-box-launch-state.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM

printf '%s\n' '#!/bin/sh' 'if [ "$1" = print-disabled ]; then echo '\''"com.yangshunxiang.sing-box" => disabled'\''; exit 0; fi' '[ "$1" = print ] || exit 1' '[ "${TEST_NO_PID:-0}" = 1 ] || echo "pid = 123"' 'echo "last exit code = ${TEST_EXIT:-0}"' > "$test_dir/launchctl"
printf '%s\n' '#!/bin/sh' 'exit 1' > "$test_dir/pgrep"
chmod +x "$test_dir/launchctl" "$test_dir/pgrep"

result=0
output=$(PATH="$test_dir:$PATH" "$source_root/dot_local/bin/executable_sing-box-managed" status) || result=$?
[ "$result" -eq 1 ]
printf '%s\n' "$output" | grep -q 'Service .*starting (launcher active)'
printf '%s\n' "$output" | grep -q 'Autostart .*disabled'
printf '%s\n' "$output" | grep -q 'Launch service .*loaded'
printf '%s\n' "$output" | grep -q '^dnscrypt-proxy$'

result=0
output=$(TEST_NO_PID=1 TEST_EXIT=78 PATH="$test_dir:$PATH" "$source_root/dot_local/bin/executable_sing-box-managed" status) || result=$?
[ "$result" -eq 1 ]
printf '%s\n' "$output" | grep -q 'Service .*exited; launchd may retry'
printf '%s\n' "$output" | grep -q 'Last exit .*78'

# A current launcher takes precedence over a historical failure.
output=$(TEST_EXIT=78 PATH="$test_dir:$PATH" "$source_root/dot_local/bin/executable_sing-box-managed" status) || true
printf '%s\n' "$output" | grep -q 'Service .*starting (launcher active)'
printf '%s\n' "$output" | grep -q 'Previous exit .*78'

# Stopping sing-box must not suppress independent DNS/profile status.
printf '%s\n' '#!/bin/sh' 'exit 1' > "$test_dir/launchctl"
printf '%s\n' '#!/bin/sh' 'exit 1' > "$test_dir/profiles"
chmod +x "$test_dir/profiles"
result=0
output=$(PATH="$test_dir:$PATH" "$source_root/dot_local/bin/executable_sing-box-managed" status) || result=$?
[ "$result" -eq 1 ]
printf '%s\n' "$output" | grep -q 'Service .*not running'
printf '%s\n' "$output" | grep -q '^dnscrypt-proxy$'
printf '%s\n' "$output" | grep -q 'Profile .*UNKNOWN'
