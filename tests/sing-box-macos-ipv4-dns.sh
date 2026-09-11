#!/bin/sh
set -eu

repo=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
rendered=$(mktemp "${TMPDIR:-/tmp}/sing-box-macos-ipv4-dns.XXXXXX")
trap 'rm -f "$rendered"' EXIT HUP INT TERM

chezmoi execute-template < "$repo/dot_config/private_sing-box/config.d/00-base.json.tmpl" > "$rendered"

jq -e '
  .dns.strategy == "ipv4_only"
  and (.dns.rules // []) == []
  and ([.inbounds[] | select(.type == "tun") | .address] == [["198.18.0.1/30"]])
  and ([.route.rules[] | select(.process_name == "WeChat")] == [])
' "$rendered" >/dev/null

printf '%s\n' 'macOS IPv4-only DNS test passed.'
