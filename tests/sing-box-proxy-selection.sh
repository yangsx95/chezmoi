#!/bin/sh
set -eu

repo=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/sing-box-proxy-selection.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
config="$work/config/sing-box"
data="$work/data/sing-box"
mkdir -p "$config/config.d" "$config/rules.d" "$data/generated" "$data/private" "$data/rules" "$work/bin"

cat > "$config/rule-subscriptions.json" <<'JSON'
{"version":1,"route":{"final":"proxy","auto_detect_interface":true},"dns_rewrite":{"ttl":300,"suppress_local_discovery":true,"local_mappings":[]}}
JSON
cat > "$config/rules.d/test.json" <<'JSON'
{"version":1,"category":"Test","allow_domains":["dns.example"],"rule_sets":[{"tag":"direct-ip","name":"Direct IP","type":"route-rule","enabled":true,"priority":1,"action":"direct","sources":[],"local_rules":[]}]}
JSON
printf '%s\n' '{}' > "$config/config.d/00-base.json"
printf '%s\n' '{}' > "$data/generated/30-safe-search.json"
cat > "$data/private/10-outbounds.json" <<'JSON'
{"outbounds":[
  {"tag":"Test Node A","type":"shadowsocks","server":"a.example"},
  {"tag":"Test Node B","type":"shadowsocks","server":"b.example"},
  {"tag":"proxy","type":"urltest","outbounds":["Test Node A","Test Node B"]},
  {"tag":"direct","type":"direct"},
  {"tag":"block","type":"block"}
]}
JSON
printf '%s\n' '#!/bin/sh' 'exit 0' > "$work/bin/sing-box"
printf '%s\n' '#!/bin/sh' 'printf "%s\n" "$*" >> "$TEST_SUDO_LOG"' '"$@"' > "$work/bin/sudo"
printf '%s\n' '#!/bin/sh' 'exit 0' > "$work/bin/launchctl"
printf '%s\n' '#!/bin/sh' 'exit 0' > "$work/bin/pgrep"
chmod +x "$work/bin/sing-box" "$work/bin/sudo" "$work/bin/launchctl" "$work/bin/pgrep"

export XDG_CONFIG_HOME="$work/config"
export XDG_DATA_HOME="$work/data"
export TEST_SUDO_LOG="$work/sudo.log"
PATH="$work/bin:$PATH"
export PATH
manager="$repo/dot_local/bin/executable_sing-box-managed"

output=$("$manager" proxy-list)
printf '%s\n' "$output" | grep -Fq '*   0  auto'
printf '%s\n' "$output" | grep -Fq '1  Test Node A'
printf '%s\n' "$output" | grep -Fq '2  Test Node B'

"$manager" proxy-use 2 >/dev/null
[ "$(cat "$data/proxy-selection")" = 'Test Node B' ]
jq -e '
  .route.final == "Test Node B"
  and (.route.rules[] | select(.ip_version == 6).outbound) == "Test Node B"
  and ((.route.rules | map(.rule_set == "direct-ip") | index(true)) < (.route.rules | map(.ip_version == 6) | index(true)))
' "$data/generated/20-route.json" >/dev/null
jq -e '.route.rules[0].domain == ["a.example", "b.example"] and (.dns.rules[0].domain | index("dns.example")) != null and .dns.rules[0].strategy == "ipv4_only"' "$data/generated/20-route.json" >/dev/null
grep -Fq 'launchctl kickstart -k system/com.yangshunxiang.sing-box' "$work/sudo.log"
"$manager" proxy-list | grep -Fq '*   2  Test Node B'

"$manager" proxy-use 'Test Node A' >/dev/null
[ "$(cat "$data/proxy-selection")" = 'Test Node A' ]
jq -e '.route.final == "Test Node A"' "$data/generated/20-route.json" >/dev/null

"$manager" proxy-use auto >/dev/null
[ "$(cat "$data/proxy-selection")" = proxy ]
jq -e '.route.final == "proxy"' "$data/generated/20-route.json" >/dev/null

code=0
"$manager" proxy-use missing >/dev/null 2>&1 || code=$?
[ "$code" -eq 2 ]
[ "$(cat "$data/proxy-selection")" = proxy ]

printf '%s\n' 'Proxy selection tests passed.'
