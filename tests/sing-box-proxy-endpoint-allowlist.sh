#!/bin/sh
set -eu

data_home=${XDG_DATA_HOME:-"$HOME/.local/share"}
private_config="$data_home/sing-box/private/10-outbounds.json"
route_config="$data_home/sing-box/generated/20-route.json"

[ -f "$private_config" ]
[ -f "$route_config" ]

jq -e --slurpfile private "$private_config" '
  ($private[0].outbounds
    | map(.server? // empty | select(type == "string" and test("[A-Za-z]")))
    | unique) as $endpoints
  | ($endpoints | length) > 0
  and .route.rules[0].domain == $endpoints
  and .route.rules[0].outbound == "direct"
  and .dns.rules[0].domain == $endpoints
  and .dns.rules[0].action == "route"
  and .dns.rules[0].server == "dns-direct"
' "$route_config" >/dev/null
