#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { execFileSync } from 'node:child_process';

const [definitions, rulesDir, privateConfig, blockOutput, allowOutput] = process.argv.slice(2);
if (!allowOutput) throw new Error('Usage: generator <definitions-dir> <compiled-rules-dir> <private-config> <block-output> <allow-output>');
const sets = fs.readdirSync(definitions).filter(name => name.endsWith('.json')).sort()
  .flatMap(name => JSON.parse(fs.readFileSync(path.join(definitions, name))).rule_sets)
  .filter(set => set.type === 'route-rule' && set.enabled && set.action === 'block'
    && set.dns_block !== false && set.sources.every(source => source.format !== 'ip-list'));
const blocked = new Set();
const entries = value => value == null ? [] : Array.isArray(value) ? value : [value];
function literal(value) {
  if (!value || /[\s*?\[\]#@=]/u.test(value)) throw new Error(`Unsupported domain pattern: ${value}`);
  return value;
}
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'dnscrypt-rules-'));
try {
  for (const set of sets) {
    const output = path.join(temp, `${set.tag}.json`);
    execFileSync('sing-box', ['rule-set', 'decompile', '--output', output, path.join(rulesDir, `${set.tag}.srs`)], { stdio: 'pipe' });
    for (const rule of JSON.parse(fs.readFileSync(output)).rules) {
      // Do not silently broaden logical/conditional rules or drop regex matching.
      for (const key of Object.keys(rule)) {
        if (!['domain', 'domain_suffix', 'domain_keyword', 'ip_cidr'].includes(key)) {
          throw new Error(`${set.tag}: unsupported DNS conversion field ${key}`);
        }
      }
      for (const value of entries(rule.domain)) blocked.add(`=${literal(value)}`);
      for (const value of entries(rule.domain_suffix)) {
        if (value.startsWith('.')) blocked.add(`?*${literal(value)}`);
        else blocked.add(literal(value));
      }
      for (const value of entries(rule.domain_keyword)) blocked.add(`*${literal(value)}*`);
    }
  }
  const allowed = new Set(JSON.parse(fs.readFileSync(privateConfig)).outbounds
    .map(outbound => outbound.server).filter(server => typeof server === 'string' && /[A-Za-z]/.test(server))
    .map(server => `=${literal(server)}`));
  fs.writeFileSync(blockOutput, '# Generated from sing-box DNS blocking rule sets.\n' + [...blocked].sort().join('\n') + '\n');
  fs.writeFileSync(allowOutput, '# Proxy endpoint exceptions (exact domains).\n' + [...allowed].sort().join('\n') + '\n');
  console.log(`dnscrypt-proxy: ${blocked.size} patterns from ${sets.length} rule sets`);
} finally {
  fs.rmSync(temp, { recursive: true, force: true });
}
