#!/bin/sh
set -eu

source_root=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
wrapper="$source_root/dot_local/libexec/executable_sing-box-start-when-network-ready"
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/sing-box-network-ready.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM

printf '%s\n' '{"outbounds":[{"server":"bad.proxy"},{"server":"good.proxy"}]}' > "$test_dir/private.json"
printf '%s\n' '#!/bin/sh' 'count=0' '[ ! -f "$ROUTE_COUNT" ] || count=$(cat "$ROUTE_COUNT")' 'count=$((count + 1))' 'printf "%s\n" "$count" > "$ROUTE_COUNT"' '[ "$count" -gt 1 ] || exit 1' 'printf "%s\n" "interface: en0"' > "$test_dir/route"
printf '%s\n' '#!/bin/sh' 'case "$*" in *bad.proxy*) exit 0 ;; esac' 'printf "%s\n" "example.test. 60 IN A 192.0.2.1"' > "$test_dir/dig"
printf '%s\n' '#!/bin/sh' 'exit 0' > "$test_dir/sleep"
printf '%s\n' '#!/bin/sh' 'if [ "$(cat "$ROUTE_COUNT")" -le 3 ]; then echo "inet 192.0.2.2"; else echo "inet 192.0.2.3"; fi' > "$test_dir/ifconfig"
printf '%s\n' '#!/bin/sh' '[ "$(cat "$ROUTE_COUNT")" -gt 2 ] || exit 1' 'echo "<BODY>Success</BODY>"' > "$test_dir/curl"
chmod +x "$test_dir/ifconfig" "$test_dir/curl"
printf '%s\n' '#!/bin/sh' 'printf "%s\n" "$*" > "$TARGET_MARKER"' > "$test_dir/target"
chmod +x "$test_dir/route" "$test_dir/dig" "$test_dir/sleep" "$test_dir/target"

ROUTE_COUNT="$test_dir/route-count" \
TARGET_MARKER="$test_dir/target-marker" \
SING_BOX_ROUTE_COMMAND="$test_dir/route" \
SING_BOX_DIG_COMMAND="$test_dir/dig" \
SING_BOX_SLEEP_COMMAND="$test_dir/sleep" \
SING_BOX_IFCONFIG_COMMAND="$test_dir/ifconfig" \
SING_BOX_CURL_COMMAND="$test_dir/curl" \
SING_BOX_JQ_COMMAND="$(command -v jq)" \
"$wrapper" "$test_dir/private.json" "$test_dir/target" run -c example.json >/dev/null

# Missing route, unreachable network, then an address change must all delay startup.
[ "$(cat "$test_dir/route-count")" -eq 5 ]
[ "$(cat "$test_dir/target-marker")" = 'run -c example.json' ]
