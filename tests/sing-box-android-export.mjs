import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'android-export-test-'));
const exporter = new URL('../dot_local/libexec/sing-box-android-export.mjs', import.meta.url).pathname;
const write = (name, value) => {
  const file = path.join(root, name);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify(value));
  return file;
};
try {
  const source = write('rule.json', { version: 4, rules: [{ domain_suffix: ['blocked.example'] }] });
  const binary = path.join(root, 'rules.srs');
  execFileSync('sing-box', ['rule-set', 'compile', '--output', binary, source]);
  write('config/sing-box/config.d/00-base.json', { route: { rules: [
    { process_name: 'dnscrypt-proxy', outbound: 'direct' },
    { port: 53, action: 'hijack-dns' }, { port: 853, action: 'reject' }, { action: 'sniff' },
  ] } });
  write('data/sing-box/private/10-outbounds.json', { outbounds: [
    { type: 'direct', tag: 'direct' },
    { type: 'shadowsocks', tag: 'proxy', server: 'proxy.example', server_port: 443,
      method: 'aes-128-gcm', password: 'test-private-password' },
  ] });
  write('data/sing-box/generated/20-route.json', {
    dns: { rules: [{ rule_set: 'blocked', action: 'reject' }] },
    route: { final: 'proxy', rule_set: [{ type: 'local', format: 'binary', tag: 'blocked', path: binary }],
      rules: [{ domain: ['proxy.example'], outbound: 'direct' },
        { rule_set: 'blocked', action: 'reject' }, { ip_version: 6, outbound: 'proxy' }] },
  });
  write('data/sing-box/generated/30-safe-search.json', {
    dns: { rules: [{ domain: 'search.example', action: 'predefined', answer: ['search.example. 300 IN A 192.0.2.1'] }] },
    route: { rules: [{ domain: ['search.example'], action: 'route', outbound: 'proxy', override_address: '192.0.2.1' }] },
  });
  const run = () => execFileSync('node', [exporter, path.join(root, 'config'), path.join(root, 'data')], { stdio: 'pipe' });
  run();
  const exports = path.join(root, 'data/sing-box/android');
  const output = path.join(exports, fs.readdirSync(exports)[0]);
  const proxy = JSON.parse(fs.readFileSync(path.join(output, 'android-proxy.json')));
  const directText = fs.readFileSync(path.join(output, 'android-direct.json'), 'utf8');
  const direct = JSON.parse(directText);
  assert.equal(proxy.route.final, 'proxy');
  assert.equal(direct.route.final, 'direct');
  assert(!directText.includes('test-private-password'));
  assert.deepEqual(direct.outbounds, [{ type: 'direct', tag: 'direct' }]);
  assert(direct.route.rules.every(rule => !rule.outbound || rule.outbound === 'direct'));
  assert.deepEqual(proxy.route.rule_set, direct.route.rule_set);
  assert.equal(proxy.route.rule_set[0].type, 'inline');
  assert(!JSON.stringify(proxy).includes(root));
  assert(!JSON.stringify(proxy).includes('process_name'));
  assert(!JSON.stringify(proxy).includes('127.0.0.1'));
  assert.equal(proxy.dns.servers[0].detour, undefined);
  assert.equal(direct.dns.servers[0].detour, undefined);
  assert.deepEqual(proxy.dns.rules, direct.dns.rules);
  const rules = proxy.route.rules;
  assert(rules.findIndex(rule => rule.rule_set === 'blocked') < rules.findIndex(rule => rule.override_address));
  assert(rules.findIndex(rule => rule.override_address) < rules.findIndex(rule => rule.ip_version === 6));
  assert.equal(fs.statSync(path.join(output, 'android-proxy.json')).mode & 0o777, 0o600);
  // A failed export must leave the previously validated export intact.
  fs.unlinkSync(binary);
  assert.throws(run);
  assert.equal(fs.readdirSync(exports).length, 1);
  console.log('Android export tests passed (real core validation, parity, routing, credentials, failure cleanup).');
} finally { fs.rmSync(root, { recursive: true, force: true }); }
