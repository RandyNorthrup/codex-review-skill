#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";

const args = process.argv.slice(2);

if (args.includes("--version")) {
  process.stdout.write("codex-cli 0.149.0\n");
  process.exit(0);
}

if (args[0] === "login" && args[1] === "status") {
  process.stdout.write("Logged in using CI test double\n");
  process.exit(0);
}

const execIndex = args.indexOf("exec");
if (execIndex < 0) {
  process.stderr.write(`fake-codex: unsupported arguments: ${args.join(" ")}\n`);
  process.exit(2);
}

function requirePair(flag, value, beforeExec) {
  const index = args.findIndex(
    (argument, position) => argument === flag && args[position + 1] === value,
  );
  if (index < 0 || (beforeExec ? index >= execIndex : index <= execIndex)) {
    const placement = beforeExec ? "before" : "after";
    process.stderr.write(
      `fake-codex: expected ${flag} ${value} ${placement} exec\n`,
    );
    process.exit(2);
  }
}

requirePair("-s", "read-only", true);
requirePair("-a", "never", true);
requirePair("--disable", "plugins", true);
requirePair("--disable", "apps", true);
requirePair("--disable", "hooks", true);
requirePair("-c", "mcp_servers={}", true);

for (const required of [
  "--skip-git-repo-check",
  "--ephemeral",
]) {
  const index = args.indexOf(required);
  if (index <= execIndex) {
    process.stderr.write(`fake-codex: expected ${required} after exec\n`);
    process.exit(2);
  }
}
if (args.includes("--ignore-user-config")) {
  process.stderr.write(
    "fake-codex: --ignore-user-config breaks Windows read-only target access\n",
  );
  process.exit(2);
}
const modelIndex = args.indexOf("-m", execIndex + 1);
if (modelIndex < 0 || !args[modelIndex + 1]) {
  process.stderr.write("fake-codex: missing model after exec\n");
  process.exit(2);
}
if (args.includes("--dangerously-bypass-approvals-and-sandbox")) {
  process.stderr.write("fake-codex: dangerous sandbox bypass is forbidden\n");
  process.exit(2);
}

const outputIndex = args.indexOf("-o");
if (outputIndex <= execIndex || !args[outputIndex + 1]) {
  process.stderr.write("fake-codex: missing -o result path\n");
  process.exit(2);
}

const prompt = fs.readFileSync(0, "utf8");
let answer = "OK";
if (prompt.includes("sample.py")) {
  requirePair("-c", "model_reasoning_effort=xhigh", false);
  const directoryIndex = args.indexOf("-C");
  if (directoryIndex < 0 || directoryIndex >= execIndex || !args[directoryIndex + 1]) {
    process.stderr.write("fake-codex: full review requires -C before exec\n");
    process.exit(2);
  }
  const samplePath = path.join(args[directoryIndex + 1], "sample.py");
  if (!fs.existsSync(samplePath)) {
    process.stderr.write(`fake-codex: sample file missing at ${samplePath}\n`);
    process.exit(2);
  }
  const sample = fs.readFileSync(samplePath, "utf8");
  if (!sample.includes("range(len(items) - 1)") || !sample.includes("/ len(items)")) {
    process.stderr.write("fake-codex: planted defects are missing from sample.py\n");
    process.exit(2);
  }
  answer = [
      "- High — sample.py:3: Off-by-one loop skips the last item.",
      "- High — sample.py:5: Empty input causes division by zero.",
    ].join("\n");
} else if (prompt.trim() !== "Reply with exactly OK") {
  process.stderr.write("fake-codex: unexpected probe prompt\n");
  process.exit(2);
}

const outputPath = path.resolve(args[outputIndex + 1]);
fs.mkdirSync(path.dirname(outputPath), { recursive: true });
fs.writeFileSync(outputPath, `${answer}\n`, "utf8");
process.stdout.write(`${answer}\n`);
