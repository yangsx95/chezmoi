#!/bin/sh
set -eu

data_home=${XDG_DATA_HOME:-"$HOME/.local/share"}
config_home=${XDG_CONFIG_HOME:-"$HOME/.config"}
private_config="$data_home/sing-box/private/10-outbounds.json"
route_config="$data_home/sing-box/generated/20-route.json"
rules_config_dir="$config_home/sing-box/rules.d"

[ -f "$private_config" ]
[ -f "$route_config" ]

policy_allowlist=$(jq -c -s '[.[] | (.allow_domains // [])[]] | unique' "$rules_config_dir"/*.json)
jq -e --slurpfile private "$private_config" --argjson policy_allowlist "$policy_allowlist" '
  ($private[0].outbounds
    | map(.server? // empty | select(type == "string" and test("[A-Za-z]")))
    | unique) as $endpoints
  | (($endpoints + $policy_allowlist) | unique) as $direct_domains
  | ($endpoints | length) > 0
  and ($policy_allowlist | length) > 0
  and .route.rules[0].domain == $direct_domains
  and .route.rules[0].outbound == "direct"
  and .dns.rules[0].domain == $direct_domains
  and .dns.rules[0].action == "route"
  and .dns.rules[0].server == "dns-direct"
' "$route_config" >/dev/null
