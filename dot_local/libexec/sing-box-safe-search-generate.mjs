#!/usr/bin/env node

import { readFile, writeFile } from "node:fs/promises";
import { isIP } from "node:net";
import { join } from "node:path";

const [configPath, outputPath, sourcesDirectory] = process.argv.slice(2);
if (!configPath || !outputPath) {
  console.error("Usage: sing-box-safe-search-generate.mjs <rule-subscriptions.json> <output.json> [sources-directory]");
  process.exit(2);
}

const config = JSON.parse(await readFile(configPath, "utf8"));
if (config.version !== 1 || !Array.isArray(config.subscriptions) || typeof config.dns_rewrite !== "object") {
  throw new Error("Invalid rule-subscriptions.json: expected version 1, dns_rewrite, and subscriptions");
}

const ttl = config.dns_rewrite.ttl ?? 300;
if (!Number.isInteger(ttl) || ttl < 0 || ttl > 86400) {
  throw new Error("Invalid rule-subscriptions.json: dns_rewrite.ttl must be an integer from 0 to 86400");
}
const suppressLocalDiscovery = config.dns_rewrite.suppress_local_discovery ?? true;
if (typeof suppressLocalDiscovery !== "boolean") {
  throw new Error("Invalid rule-subscriptions.json: dns_rewrite.suppress_local_discovery must be a boolean");
}
const routeOutbound = config.route?.final;
if (typeof routeOutbound !== "string" || !routeOutbound) {
  throw new Error("Invalid rule-subscriptions.json: route.final must name the safe-search outbound");
}

const domainPattern = /^(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/;
const tagPattern = /^[a-z0-9][a-z0-9-]*$/;
const subscriptionTags = new Set();
const mappings = new Map();

function normalizeMapping(rawMapping, source) {
  const domain = typeof rawMapping.domain === "string" ? rawMapping.domain.toLowerCase().replace(/\.$/, "") : "";
  const recordType = rawMapping.record_type;
  const target = typeof rawMapping.target === "string" ? rawMapping.target.toLowerCase().replace(/\.$/, "") : "";
  if (!domainPattern.test(domain)) {
    throw new Error(`${source}: invalid domain: ${domain}`);
  }
  if (recordType !== "CNAME" && recordType !== "A" && recordType !== "AAAA") {
    throw new Error(`${source}: invalid record type: ${recordType}`);
  }
  if (recordType === "CNAME" ? !domainPattern.test(target) : isIP(target) === 0) {
    throw new Error(`${source}: invalid ${recordType} target: ${target}`);
  }
  return { domain, recordType, target };
}

function addMapping(mapping, source) {
  const existing = mappings.get(mapping.domain);
  if (existing && JSON.stringify(existing) !== JSON.stringify(mapping)) {
    throw new Error(`${source}: conflicting safe-search rewrite for ${mapping.domain}`);
  }
  mappings.set(mapping.domain, mapping);
}

const localMappings = config.dns_rewrite.local_mappings ?? [];
if (!Array.isArray(localMappings)) {
  throw new Error("Invalid rule-subscriptions.json: dns_rewrite.local_mappings must be an array");
}
for (const mapping of localMappings) {
  addMapping(normalizeMapping(mapping, "local safe-search rewrite"), "local safe-search rewrite");
}

for (const subscription of config.subscriptions.filter(({ type }) => type === "dns-rewrite")) {
  if (!tagPattern.test(subscription.tag ?? "") || typeof subscription.enabled !== "boolean" || subscription.format !== "adguard-dnsrewrite" || typeof subscription.url !== "string" || !subscription.url) {
    throw new Error("Invalid safe-search subscription: each entry needs a valid tag and URL");
  }
  if (subscriptionTags.has(subscription.tag)) {
    throw new Error(`Duplicate safe-search subscription tag: ${subscription.tag}`);
  }
  subscriptionTags.add(subscription.tag);
  if (!subscription.enabled) continue;
  if (!sourcesDirectory) throw new Error("A sources directory is required when safe search is enabled");

  const sourcePath = join(sourcesDirectory, `${subscription.tag}.source`);
  const lines = (await readFile(sourcePath, "utf8")).split(/\r?\n/);
  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index].trim();
    if (!line || line.startsWith("#")) continue;

    const match = line.match(/^\|([^|*^]+)\^\$dnsrewrite=NOERROR;(CNAME|A|AAAA);([^;\s]+)$/);
    if (!match) {
      throw new Error(`${subscription.tag}:${index + 1}: unsupported DNS rewrite: ${line}`);
    }

    const source = `${subscription.tag}:${index + 1}`;
    addMapping(normalizeMapping({ domain: match[1], record_type: match[2], target: match[3] }, source), source);
  }
}

const rules = [];
const routeDomainsByTarget = new Map();
if (suppressLocalDiscovery) {
  // macOS probes these unicast DNS-SD discovery names continuously. Public and
  // ordinary LAN resolvers commonly leave them unanswered, which otherwise
  // produces a 10-second timeout and a warning for every probe.
  rules.push({
    domain_regex: ["^(?:b|db|r|dr|lb)\\._dns-sd\\._udp\\..+\\.(?:in-addr|ip6)\\.arpa$"],
    action: "predefined",
    rcode: "NXDOMAIN",
  });
}
for (const { domain, recordType, target } of mappings.values()) {
  if (!routeDomainsByTarget.has(target)) routeDomainsByTarget.set(target, new Set());
  routeDomainsByTarget.get(target).add(domain);

  if (recordType === "CNAME") {
    rules.push({
      domain,
      action: "predefined",
      answer: [`${domain}. ${ttl} IN CNAME ${target}.`],
    });
    continue;
  }

  rules.push({
    domain,
    query_type: recordType,
    action: "predefined",
    answer: [`${domain}. ${ttl} IN ${recordType} ${target}`],
  });
  // A fixed-address family endpoint only controls its own address family.
  // Suppress the other family so it cannot resolve to the unrestricted site.
  rules.push({
    domain,
    query_type: recordType === "A" ? "AAAA" : "A",
    action: "predefined",
    rcode: "NOERROR",
  });
}

// DNS rewriting alone is insufficient when the selected proxy re-resolves the
// original hostname. Preserve the safe-search endpoint at the route boundary
// while leaving the browser's TLS SNI and HTTP Host untouched.
const routeRules = [...routeDomainsByTarget.entries()]
  .sort(([left], [right]) => left.localeCompare(right))
  .map(([target, domains]) => ({
    domain: [...domains].sort(),
    action: "route",
    outbound: routeOutbound,
    override_address: target,
  }));

await writeFile(outputPath, `${JSON.stringify({ dns: { rules }, route: { rules: routeRules } }, null, 2)}\n`, { mode: 0o600 });
