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
sing-box-managed dns-sync
sing-box-managed check
sing-box-managed run
sing-box-managed status
```

On macOS, DNS is sent to a local `dnscrypt-proxy` listener on
`127.0.0.1:53`. `compile`, `update`, and `dns-sync` refresh its OISD NSFW and
local blocking rules together with an allowlist for proxy server hostnames.
The generated sing-box route also places those exact proxy hostnames before
category blocks, so a risky-TLD rule cannot reject the proxy's own DNS lookup.
`chezmoi apply` installs sing-box and dnscrypt-proxy, validates and deploys the
DNS configuration, registers its startup service, and points the en0 network
service at localhost.

On macOS, chezmoi also installs a root LaunchDaemon for sing-box with
`KeepAlive`, so the proxy starts at boot and recovers after an
unexpected exit. If a manually started instance is already running during
installation, it is left untouched and launchd takes over at the next boot.
Before creating the TUN interface, the launch service waits for a default
route, a working local dnscrypt-proxy response, and a resolvable proxy endpoint
to pass twice. It also checks a usable physical IPv4 address and an HTTP
connectivity response bound to that interface (Apple, with Microsoft fallback).
Changing interface, gateway, or address resets the stability count. If both
connectivity services are unavailable, startup waits and logs the reason.
Run `sing-box-managed doctor` during an outage to compare local DNS, normal
routing, physical-interface connectivity, and Google Safe Search. The command
does not change network settings; it sends diagnostic requests to those sites.
`status` also reports the independent dnscrypt-proxy process and launch service,
and whether the browser security profile can be found. `doctor` verifies local
block responses for the configured example domains and inspects Chrome/Edge
managed policy files. Policy files are not proof of runtime enforcement: confirm
with `chrome://policy` or `edge://policy`. Safari is not covered by the profile.

Use `sing-box-managed --help` (or `<command> --help`) for grouped commands.
Use `start`, `stop`, and `restart` for daily service management. `start` uses
launchd when installed; otherwise it reports that the background process has
no automatic restart. Use `run` for foreground debugging (Ctrl+C stops it),
after stopping any existing service. `run` takes no arguments; use `start`
instead of the removed `-d` / `--background` options.
`logs -n 100` prints recent lines and `logs -n 100 -f` follows the log.
Unknown or extra arguments exit with code 2 before taking action.
Status is grouped by component; doctor uses PASS/FAIL/CHECK/SKIP rows.
`Launch service` (loaded) and `Autostart` (enabled/disabled) are independent.
Without a sing-box process, status distinguishes an active launcher from a
previous failed exit; exit codes/signals are historical, not proof of a loop.
Exit codes: 0 means no definite failure was found, 1 means a required process
is absent or a definite check failed, and 2 means invalid arguments.
UNKNOWN, SKIP and CHECK results do not imply success and do not alone cause
exit 1. For example, an HTTP access-denied response is CHECK, whereas a
connection failure is FAIL. Browser runtime enforcement remains UNKNOWN.
Restart waits up to eight seconds for a process; a process being present does
not itself prove network health. Waiting reasons are timestamped and logged
only when they change.
The sing-box log is checked once per minute; after it exceeds 5 MiB, only the
newest 1 MiB is retained. No rotated archives are kept.

Edit the relevant file in `rules.d/` through chezmoi. Each enabled route rule
set compiles to its own `.srs` file outside the repository.

Code layout: `sing-box-managed` owns argument parsing, rule compilation and
service operations. Status and diagnostics are loaded on demand from
`~/.local/libexec/sing-box-diagnostics.sh`; the network-readiness launcher stays
independent. Rendering helpers only print; diagnostic aggregation is reset for
each report. An active launcher takes precedence over historical exit errors.
