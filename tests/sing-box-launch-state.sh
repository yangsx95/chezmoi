#!/bin/sh
set -eu

source_root=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/sing-box-launch-state.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM

printf '%s\n' '#!/bin/sh' '[ "$1" = print ] && exit 0' 'exit 1' > "$test_dir/launchctl"
printf '%s\n' '#!/bin/sh' 'exit 1' > "$test_dir/pgrep"
chmod +x "$test_dir/launchctl" "$test_dir/pgrep"

output=$(PATH="$test_dir:$PATH" "$source_root/dot_local/bin/executable_sing-box-managed" status)
printf '%s\n' "$output" | grep -q 'Service: starting or retrying'
printf '%s\n' "$output" | grep -q 'Startup: enabled and managed by launchd'
