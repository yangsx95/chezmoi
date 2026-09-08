#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { isIP } from 'node:net';

const [configHome, dataHome] = process.argv.slice(2);
if (!configHome || !dataHome) throw new Error('Usage: android-export <config-home> <data-home>');
const data = path.join(dataHome, 'sing-box');
const read = file => JSON.parse(fs.readFileSync(file, 'utf8'));
const base = read(path.join(configHome, 'sing-box/config.d/00-base.json'));
const routing = read(path.join(data, 'generated/20-route.json'));
const safe = read(path.join(data, 'generated/30-safe-search.json'));
const privateConfig = read(path.join(data, 'private/10-outbounds.json'));
if (Object.keys(privateConfig).some(key => key !== 'outbounds')) {
  throw new Error('Android export currently supports private outbounds only');
}
// Desktop-only dial options must not be silently carried onto a phone.
function checkPortable(value) {
  if (Array.isArray(value)) return value.forEach(checkPortable);
  if (!value || typeof value !== 'object') return;
  for (const [key, child] of Object.entries(value)) {
    if (['bind_interface', 'bind_ipv4_addr', 'bind_ipv6_addr', 'routing_mark', 'netns',
      'certificate_path', 'key_path', 'process_name', 'process_path', 'process_path_regex'].includes(key)) {
      throw new Error(`Android export cannot migrate field: ${key}`);
    }
    checkPortable(child);
  }
}
checkPortable(privateConfig);
const root = path.join(data, 'android');
fs.mkdirSync(root, { recursive: true, mode: 0o700 });
const output = fs.mkdtempSync(path.join(root, 'export-'));
let complete = false;
try {
  const ruleSets = [];
  for (const set of routing.route.rule_set) {
    if (set.type !== 'local' || set.format !== 'binary') throw new Error(`Unsupported rule set: ${set.tag}`);
    const temporary = path.join(output, 'rule.json');
    execFileSync('sing-box', ['rule-set', 'decompile', '--output', temporary, set.path], { stdio: 'pipe' });
    const decoded = read(temporary);
    checkPortable(decoded);
    ruleSets.push({ type: 'inline', tag: set.tag, rules: decoded.rules });
    fs.unlinkSync(temporary);
  }
  const endpoints = [...new Set(privateConfig.outbounds.map(item => item.server)
    .filter(server => typeof server === 'string' && !isIP(server)))];
  const controls = (base.route.rules ?? []).filter(rule => !rule.process_name);
  checkPortable(controls);
  const dnsRules = [...(routing.dns?.rules ?? []), ...(safe.dns?.rules ?? [])];
  const routeRules = routing.route.rules ?? [];
  const blockRules = routeRules.filter(rule => rule.action === 'reject');
  const otherRules = routeRules.filter(rule => rule.action !== 'reject');
  // Preserve endpoint exemptions, then blocks, then safe-search overrides before
  // the generated IPv6 catch-all or any other general routing rule.
  const endpointRule = endpoints.length ? [{ domain: endpoints, outbound: 'direct' }] : [];
  const isEndpointRule = rule => rule.outbound === 'direct' && rule.domain
    && JSON.stringify([...rule.domain].sort()) === JSON.stringify([...endpoints].sort());
  for (const mode of ['proxy', 'direct']) {
    const direct = mode === 'direct';
    const mapOutbound = rule => direct && rule.outbound ? { ...rule, outbound: 'direct' } : rule;
    const config = {
      log: { level: 'warn' },
      dns: {
        servers: [{ type: 'https', tag: 'dns-direct', server: '223.5.5.5', server_port: 443,
          path: '/dns-query', tls: { enabled: true, server_name: 'dns.alidns.com' } }],
        final: 'dns-direct', rules: dnsRules,
      },
      inbounds: [{ type: 'tun', tag: 'tun-in', address: ['172.19.0.1/30', 'fdfe:dcba:9876::1/126'],
        mtu: 1500, auto_route: true, stack: 'mixed' }],
      outbounds: direct ? [{ type: 'direct', tag: 'direct' }] : privateConfig.outbounds,
      route: {
        auto_detect_interface: true,
        default_domain_resolver: 'dns-direct',
        final: direct ? 'direct' : routing.route.final,
        rules: [...controls, ...endpointRule, ...blockRules,
          ...(safe.route?.rules ?? []).map(mapOutbound),
          ...otherRules.filter(rule => !isEndpointRule(rule)).map(mapOutbound)],
        rule_set: ruleSets,
      },
    };
    checkPortable(config);
    const file = path.join(output, `android-${mode}.json`);
    fs.writeFileSync(file, JSON.stringify(config) + '\n', { mode: 0o600 });
    // Avoid displaying node credentials if the core includes config data in errors.
    try { execFileSync('sing-box', ['check', '-c', file], { stdio: 'pipe' }); }
    catch { throw new Error(`sing-box validation failed for android-${mode}.json; no export published`); }
  }
  const version = execFileSync('sing-box', ['version'], { encoding: 'utf8' }).split('\n')[0];
  fs.writeFileSync(path.join(output, 'README.txt'), `Android / SFA 导入说明\n\n校验内核：${version}\n请使用相同版本的 SFA 内核；本机校验不代替手机实测。\n\n1. 将 android-proxy.json（代理＋过滤）和 android-direct.json（直连＋过滤）传到手机。\n2. 在 SFA 新建本地配置，从文件导入。允许 VPN 权限。\n3. 保持 SFA 运行；无需代理时切换到直连配置，拦截仍然有效。\n4. HyperOS 允许后台运行、自启动并取消电池限制，菜单以手机版本为准。\n5. 不要在 SFA 的应用绕过列表排除需要过滤的应用。系统私人 DNS 设为关闭，浏览器安全 DNS 关闭，避免绕过或冲突。\n6. 先检查普通网站、抖音拦截、Google/YouTube 安全搜索以及 Wi-Fi/移动网络切换。\n\n规则已内嵌，无需复制 .srs 文件或开放下载服务器；文件较大，首次导入和启动可能较慢。\n这是编译规则的快照，不会自动更新；电脑执行 update 后重新 android-export 并导入。\n代理配置含节点凭据，请私下传输，不要提交到 Git 或公开发布。直连配置不含节点凭据。\n`, { mode: 0o600 });
  complete = true;
  console.log(`Android profiles exported (${ruleSets.length} embedded rule sets, ${version}):\n${output}`);
} finally {
  if (!complete) fs.rmSync(output, { recursive: true, force: true });
}
