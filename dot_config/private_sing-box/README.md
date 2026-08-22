# sing-box personal configuration

This directory is managed by chezmoi. It contains only public configuration and
small personal rule sources.

Large downloaded sources, compiled rule sets, update metadata, previous versions,
and private outbounds are deliberately stored outside the repository under
`~/.local/share/sing-box/`.

`rule-subscriptions.json` contains only global routing and DNS settings.
`rules.d/` contains the policy definitions, one JSON file per category such as
`40-games.json` or `30-gambling.json`. A category file can contain both remote
sources (`sources`, with their URL and format) and hand-maintained sing-box
rules (`local_rules`). Change a rule set's `enabled` value, then run
`sing-box-managed update`. Advertising and tracking subscriptions are not
defined.

`dns_rewrite.suppress_local_discovery` answers macOS unicast DNS-SD discovery
probes locally so unsupported reverse-discovery queries do not wait 10 seconds
and continuously emit timeout warnings.

DNS-rewrite subscriptions also generate route destination overrides. The
browser keeps the original hostname for TLS, while the selected proxy connects
to the safe-search target instead of resolving the unrestricted hostname again.

The downloaded lists and generated configurations stay outside the repository.
`compile` and `update` both download, compile, validate, and apply every enabled
category. A failed download or validation leaves the running configuration
untouched.

DNS enforcement is generated ahead of all content rules: TCP/UDP port 53 is
hijacked into the sing-box DNS module, TCP/UDP port 853 is rejected, and HaGeZi's
DoH-only domain and IP lists block known encrypted-DNS endpoints after protocol
sniffing. These lists do not include HaGeZi's broader VPN/proxy or advertising
categories.

On this macOS host the DNS module uses the local DHCP resolver bound to `en0`.
Binding the physical interface prevents the upstream DNS connection from being
captured again by the TUN port-53 hijack.

Example category file:

```json
{
  "version": 1,
  "category": "Games",
  "rule_sets": [{
    "tag": "games",
    "type": "route-rule",
    "enabled": true,
    "priority": 200,
    "action": "block",
    "sources": [{"format": "domain-list", "url": "https://example.com/games.txt"}],
    "local_rules": [{"domain_suffix": ["example-game.com"]}]
  }]
}
```

Lower `priority` values run first. Route-source formats are `hosts`,
`domain-list`, `ip-list`, `clash`, and native sing-box `source` JSON.
DNS-rewrite rule sets use `adguard-dnsrewrite`.

Commands:

```sh
sing-box-managed compile
sing-box-managed update
sing-box-managed check
sing-box-managed run
sing-box-managed status
```

Edit the relevant file in `rules.d/` through chezmoi. Each enabled route rule
set compiles to its own `.srs` file outside the repository.
