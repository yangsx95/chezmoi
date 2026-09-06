#!/bin/sh
set -eu
source_root=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
manager="$source_root/dot_local/bin/executable_sing-box-managed"
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/sing-box-cli.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM
# Any accidental mutation would go through this mock, never the real sudo.
printf '%s\n' '#!/bin/sh' 'touch "$CLI_MUTATION"' 'exit 99' > "$test_dir/sudo"
chmod +x "$test_dir/sudo"
export CLI_MUTATION="$test_dir/mutated"
PATH="$test_dir:$PATH"
export PATH
for command in start stop restart run logs doctor status; do
  "$manager" "$command" --help >/dev/null
  code=0
  "$manager" "$command" --invalid >/dev/null 2>&1 || code=$?
  [ "$code" -eq 2 ]
done
[ ! -e "$CLI_MUTATION" ]
for option in -d --background; do
  code=0
  "$manager" run "$option" >/dev/null 2>&1 || code=$?
  [ "$code" -eq 2 ]
done
[ ! -e "$CLI_MUTATION" ]
mkdir -p "$test_dir/data/sing-box"
printf 'first\nsecond\nthird\n' > "$test_dir/data/sing-box/sing-box.log"
[ "$(XDG_DATA_HOME="$test_dir/data" "$manager" logs -n 1)" = third ]
"$manager" --help >/dev/null
"$manager" >/dev/null
