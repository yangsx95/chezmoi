#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir -p "$work/definitions" "$work/rules"
cat > "$work/definitions/test.json" <<'JSON'
{"rule_sets":[
{"tag":"remote","type":"route-rule","enabled":true,"action":"block","sources":[{"format":"hosts"}]},
{"tag":"disabled","type":"route-rule","enabled":false,"action":"block","sources":[]},
{"tag":"route-only","type":"route-rule","enabled":true,"action":"block","dns_block":false,"sources":[]},
{"tag":"ips","type":"route-rule","enabled":true,"action":"block","sources":[{"format":"ip-list"}]},
{"tag":"direct","type":"route-rule","enabled":true,"action":"direct","sources":[]}]}
JSON
cat > "$work/input.json" <<'JSON'
{"version":4,"rules":[{"domain":["exact.example"],"domain_suffix":["zone.example",".children.example"],"domain_keyword":["keyword"],"ip_cidr":["192.0.2.0/24"]}]}
JSON
printf '%s\n' '{"outbounds":[{"server":"proxy.example"},{"server":"192.0.2.1"}]}' > "$work/private.json"
sing-box rule-set compile --output "$work/rules/remote.srs" "$work/input.json" >/dev/null
node "$repo/dot_local/libexec/sing-box-dnscrypt-generate.mjs" "$work/definitions" "$work/rules" "$work/private.json" "$work/block" "$work/allow"
for expected in '=exact.example' 'zone.example' '?*.children.example' '*keyword*'; do
  grep -Fxq "$expected" "$work/block"
done
[ "$(sed '/^#/d;/^$/d' "$work/block" | wc -l | tr -d ' ')" = 4 ]
grep -Fxq '=proxy.example' "$work/allow"
! grep -q '192.0.2' "$work/allow"
# Unsupported semantics must fail without replacing valid outputs.
cp "$work/block" "$work/before"
printf '%s\n' '{"version":4,"rules":[{"domain_regex":[".*example"]}]}' > "$work/input.json"
sing-box rule-set compile --output "$work/rules/remote.srs" "$work/input.json" >/dev/null
if node "$repo/dot_local/libexec/sing-box-dnscrypt-generate.mjs" "$work/definitions" "$work/rules" "$work/private.json" "$work/block" "$work/allow" 2>"$work/error"; then
  exit 1
fi
grep -q 'unsupported DNS conversion field domain_regex' "$work/error"
cmp "$work/before" "$work/block"
printf '%s\n' 'DNS rule sync tests passed.'
