#!/bin/sh
set -eu

test_dir=$(mktemp -d "${TMPDIR:-/tmp}/sing-box-log-limit.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM
log_file="$test_dir/sing-box.log"
limiter="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)/dot_local/libexec/executable_sing-box-log-limit"

dd if=/dev/zero of="$log_file" bs=1024 count=10 2>/dev/null
"$limiter" "$log_file" 8192 2048
[ "$(stat -f %z "$log_file")" -eq 2048 ]

printf 'unchanged\n' > "$log_file"
before=$(stat -f %z "$log_file")
"$limiter" "$log_file" 8192 2048
[ "$(stat -f %z "$log_file")" -eq "$before" ]
