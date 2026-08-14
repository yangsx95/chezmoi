#!/usr/bin/env node

import fs from "node:fs";
import net from "node:net";

const [inputPath, format, outputPath, desiredAction = "block"] = process.argv.slice(2);
if (!inputPath || !format || !outputPath) {
  console.error("Usage: sing-box-rule-source-compile <input> <format> <output> [block|direct]");
  process.exit(2);
}

const text = fs.readFileSync(inputPath, "utf8");
const values = {
  domain: new Set(),
  domain_suffix: new Set(),
  domain_keyword: new Set(),
  domain_regex: new Set(),
  ip_cidr: new Set(),
};

function cleanDomain(value) {
  return value.trim().toLowerCase().replace(/^\.+/, "").replace(/\.$/, "");
}

function add(field, rawValue) {
  const value = field === "ip_cidr" ? rawValue.trim() : cleanDomain(rawValue);
  if (value) values[field].add(value);
}

function policyMatches(rawPolicy) {
  const policy = (rawPolicy || "").trim().toUpperCase();
  if (policy === "DIRECT") return desiredAction === "direct";
  if (["REJECT", "REJECT-DROP", "REJECT-TINYGIF", "DROP"].includes(policy)) {
    return desiredAction === "block";
  }
  return true;
}

function meaningfulLines() {
  return text.split(/\r?\n/).map((line) => line.trim()).filter(Boolean);
}

if (format === "domain-list") {
  for (const line of meaningfulLines()) {
    if (line.startsWith("#") || line.startsWith("!")) continue;
    if (line.startsWith("full:")) add("domain", line.slice(5));
    else if (line.startsWith("domain:")) add("domain_suffix", line.slice(7));
    else if (line.startsWith("regexp:")) add("domain_regex", line.slice(7));
    else add("domain_suffix", line.split(/\s+/)[0]);
  }
} else if (format === "ip-list") {
  for (const line of meaningfulLines()) {
    if (line.startsWith("#") || line.startsWith("!")) continue;
    const value = line.split(/\s+/)[0];
    const version = net.isIP(value);
    if (version !== 0) add("ip_cidr", `${value}/${version === 4 ? 32 : 128}`);
  }
} else if (format === "hosts") {
  for (const originalLine of meaningfulLines()) {
    const line = originalLine.replace(/\s+#.*$/, "");
    if (!line || line.startsWith("#")) continue;
    const fields = line.split(/\s+/);
    if (fields.length < 2 || net.isIP(fields[0]) === 0) continue;
    for (const domain of fields.slice(1)) {
      const normalized = cleanDomain(domain);
      if (normalized && normalized !== "localhost" && !normalized.endsWith(".localhost")) {
        add("domain_suffix", normalized);
      }
    }
  }
} else if (format === "clash") {
  for (let line of meaningfulLines()) {
    if (line.startsWith("#") || line === "payload:") continue;
    line = line.replace(/^[-\s]+/, "").replace(/^['\"]|['\"]$/g, "");
    const fields = line.split(",").map((field) => field.trim());
    if (fields.length < 2 || !policyMatches(fields[2])) continue;
    switch (fields[0].toUpperCase()) {
      case "DOMAIN": add("domain", fields[1]); break;
      case "DOMAIN-SUFFIX": add("domain_suffix", fields[1]); break;
      case "DOMAIN-KEYWORD": add("domain_keyword", fields[1]); break;
      case "DOMAIN-REGEX": add("domain_regex", fields[1]); break;
      case "IP-CIDR":
      case "IP-CIDR6": add("ip_cidr", fields[1]); break;
      default: break;
    }
  }
} else {
  console.error(`Unsupported parser format: ${format}`);
  process.exit(2);
}

const rule = {};
for (const [field, entries] of Object.entries(values)) {
  if (entries.size > 0) rule[field] = [...entries].sort();
}
const result = { version: 4, rules: Object.keys(rule).length > 0 ? [rule] : [] };
fs.writeFileSync(outputPath, `${JSON.stringify(result)}\n`, { mode: 0o600 });
