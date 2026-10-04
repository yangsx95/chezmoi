import fs from 'node:fs';
import { spawnSync } from 'node:child_process';

const [file, physicalInterface, core] = process.argv.slice(2);
if (!file || !physicalInterface || !core) throw new Error('Expected config, physical interface and core path');
const config = JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, ''));
config.route.auto_detect_interface = false;
config.route.default_interface = physicalInterface;
config.route.default_domain_resolver = 'dns-direct';
for (const outbound of config.outbounds) {
  if (outbound.type === 'urltest') outbound.url = 'https://www.gstatic.com/generate_204';
}
const direct = config.dns.servers.find(s => s.tag === 'dns-direct');
if (!direct) throw new Error('Missing bootstrap DNS server');
// DNS server dial fields support bind_interface; an empty direct detour does not.
delete direct.detour;
direct.bind_interface = physicalInterface;
config.dns.servers = config.dns.servers.filter(s => s.tag !== 'dns-proxy');
config.dns.servers.push({ type: 'https', tag: 'dns-proxy', server: '1.1.1.1',
  path: '/dns-query', tls: { enabled: true, server_name: 'cloudflare-dns.com' }, detour: config.route.final });
config.dns.final = 'dns-proxy';
// A predefined CNAME-only answer is not recursively completed by the core.
// Windows getaddrinfo then fails even though the alias target resolves.
// Resolve normally and keep the existing route override for Safe Search.
const rewrittenDomains = new Set(config.route.rules.filter(r => r.override_address)
  .flatMap(r => Array.isArray(r.domain) ? r.domain : [r.domain]).filter(Boolean));
config.dns.rules = config.dns.rules.filter(rule => {
  const domains = Array.isArray(rule.domain) ? rule.domain : [rule.domain];
  return !(rule.action === 'predefined' && domains.every(d => rewrittenDomains.has(d))
    && rule.answer?.length && rule.answer.every(answer => /\sIN\s+CNAME\s/i.test(answer)));
});
// The existing first DNS rule exempts exact proxy endpoint names from filtering
// and routes them to bootstrap DNS, preventing recursive proxy resolution.
const endpoints = config.outbounds.filter(o => o.server).map(o => o.server);
const bootstrap = config.dns.rules.find(r => r.server === 'dns-direct' && Array.isArray(r.domain));
if (bootstrap) bootstrap.domain = [...new Set([...bootstrap.domain, ...endpoints])];
else config.dns.rules.unshift({ domain: endpoints, action: 'route', server: 'dns-direct' });
config.log = { ...config.log, level: 'info', timestamp: true };
const candidate = file + '.next';
fs.writeFileSync(candidate, JSON.stringify(config, null, 2) + '\n');
const result = spawnSync(core, ['check', '-c', candidate], { stdio: 'inherit', windowsHide: true });
if (result.error || result.status !== 0) { fs.unlinkSync(candidate); throw new Error('Prepared configuration failed validation'); }
fs.copyFileSync(file, file + '.before-prepare');
fs.renameSync(candidate, file);
console.log(`Physical uplink: ${physicalInterface}; proxied DNS enabled.`);
