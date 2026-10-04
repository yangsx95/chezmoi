import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { spawnSync } from 'node:child_process';

const [command, requested] = process.argv.slice(2);
const data = path.join(process.env.XDG_DATA_HOME || path.join(os.homedir(), '.local/share'), 'sing-box');
const configFile = path.join(data, 'windows-config.json');
const selectionFile = path.join(data, 'proxy-selection');
const privateConfig = JSON.parse(fs.readFileSync(path.join(data, 'private/10-outbounds.json'), 'utf8'));
const group = privateConfig.outbounds.find(o => o.tag === 'proxy' && ['urltest', 'selector'].includes(o.type));
if (!group) throw new Error('Missing proxy group');
const nodes = group.outbounds;
const current = fs.existsSync(selectionFile) ? fs.readFileSync(selectionFile, 'utf8').trim() : 'proxy';
if (current !== 'proxy' && !nodes.includes(current)) throw new Error('Saved proxy node is no longer available');
if (command === 'list') {
  console.log(`Current: ${current === 'proxy' ? 'auto' : current}`);
  for (const [i, tag] of ['proxy', ...nodes].entries()) console.log(`${tag === current ? '*' : ' '} ${i} ${i === 0 ? 'auto' : tag}`);
} else if (command === 'use') {
  let selected = requested === 'auto' ? 'proxy' : requested;
  if (/^\d+$/.test(requested || '')) selected = nodes[Number(requested) - 1];
  if (!selected || (selected !== 'proxy' && !nodes.includes(selected))) throw new Error('Unknown proxy node; use proxy-list');
  const config = JSON.parse(fs.readFileSync(configFile, 'utf8'));
  const previous = config.route.final;
  config.outbounds = privateConfig.outbounds;
  config.route.final = selected;
  for (const rule of config.route.rules) {
    if (rule.outbound === previous && (rule.ip_version === 6 || rule.override_address)) rule.outbound = selected;
  }
  for (const server of config.dns.servers) if (server.tag === 'dns-proxy') server.detour = selected;
  const candidate = configFile + '.next';
  fs.writeFileSync(candidate, JSON.stringify(config, null, 2) + '\n');
  const core = path.join(process.env.LOCALAPPDATA, 'Microsoft/WinGet/Links/sing-box.exe');
  const result = spawnSync(core, ['check', '-c', candidate], { stdio: 'inherit', windowsHide: true });
  if (result.error || result.status !== 0) { fs.unlinkSync(candidate); throw new Error('Configuration validation failed'); }
  fs.copyFileSync(configFile, configFile + '.before-selection');
  fs.renameSync(candidate, configFile);
  fs.writeFileSync(selectionFile, selected + '\n');
  console.log(`Proxy selected: ${selected === 'proxy' ? 'auto' : selected}. Restart a running instance to apply.`);
} else throw new Error('Expected list or use <auto|INDEX|NAME>');
