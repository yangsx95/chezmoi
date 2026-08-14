# sing-box personal configuration

This directory is managed by chezmoi. It contains only public configuration and
small personal rule sources.

Large downloaded sources, compiled rule sets, update metadata, previous versions,
and private outbounds are deliberately stored outside the repository under
`~/.local/share/sing-box/`.

`rule-subscriptions.json` is the single source of truth for every online rule.
Entries with `type: "route-rule"` compile to binary `.srs` route rules, while
entries with `type: "dns-rewrite"` generate safe-search DNS responses. Change an
entry's `enabled` value to select subscriptions, then run `sing-box-managed
update`. Advertising and tracking subscriptions are not defined.

`dns_rewrite.suppress_local_discovery` answers macOS unicast DNS-SD discovery
probes locally so unsupported reverse-discovery queries do not wait 10 seconds
and continuously emit timeout warnings.

DNS-rewrite subscriptions also generate route destination overrides. The
browser keeps the original hostname for TLS, while the selected proxy connects
to the safe-search target instead of resolving the unrestricted hostname again.

The downloaded lists and generated configurations stay outside the repository.
Running `compile` refreshes DNS-rewrite subscriptions and personal rules;
`update` refreshes everything atomically. A failed download or validation leaves
the last working configuration untouched.

DNS enforcement is generated ahead of all content rules: TCP/UDP port 53 is
hijacked into the sing-box DNS module, TCP/UDP port 853 is rejected, and HaGeZi's
DoH-only domain and IP lists block known encrypted-DNS endpoints after protocol
sniffing. These lists do not include HaGeZi's broader VPN/proxy or advertising
categories.

On this macOS host the DNS module uses the local DHCP resolver bound to `en0`.
Binding the physical interface prevents the upstream DNS connection from being
captured again by the TUN port-53 hijack.

Example:

```json
{
  "tag": "entertainment-games",
  "type": "route-rule",
  "enabled": false,
  "priority": 500,
  "action": "block",
  "format": "clash",
  "url": "https://example.com/rules.txt"
}
```

Lower `priority` values run first. Supported formats are `adguard`, `hosts`,
`domain-list`, `ip-list`, `clash`, native sing-box `source` JSON, and
`adguard-dnsrewrite` for DNS-rewrite subscriptions.

Commands:

```sh
sing-box-managed compile
sing-box-managed update
sing-box-managed check
sing-box-managed run
sing-box-managed status
```

Edit `rules-src/manual-allow.json` and `rules-src/manual-block.json` through
chezmoi. Applying chezmoi recompiles them into external `.srs` files.
