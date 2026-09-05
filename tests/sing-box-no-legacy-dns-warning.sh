#!/bin/sh
set -eu

config_home=${XDG_CONFIG_HOME:-"$HOME/.config"}
data_home=${XDG_DATA_HOME:-"$HOME/.local/share"}
base_config="$config_home/sing-box/config.d/00-base.json"
private_config="$data_home/sing-box/private/10-outbounds.json"
route_config="$data_home/sing-box/generated/20-route.json"
safe_search_config="$data_home/sing-box/generated/30-safe-search.json"
probe_dir=$(mktemp -d "${TMPDIR:-/tmp}/sing-box-legacy-dns.XXXXXX")
trap 'rm -rf "$probe_dir"' EXIT HUP INT TERM

jq 'del(.inbounds)' "$base_config" > "$probe_dir/base.json"
sing-box run \
  -c "$probe_dir/base.json" \
  -c "$private_config" \
  -c "$route_config" \
  -c "$safe_search_config" \
  > "$probe_dir/output" 2>&1 &
probe_pid=$!
sleep 1
if kill -0 "$probe_pid" 2>/dev/null; then
  kill -TERM "$probe_pid"
fi
wait "$probe_pid" 2>/dev/null || true

if grep -q 'Legacy Address Filter Fields' "$probe_dir/output"; then
  printf '%s\n' 'Legacy DNS address-filter warning detected.' >&2
  exit 1
fi
if grep -Eq 'FATAL|panic' "$probe_dir/output"; then
  printf '%s\n' 'Isolated sing-box startup failed.' >&2
  exit 1
fi
