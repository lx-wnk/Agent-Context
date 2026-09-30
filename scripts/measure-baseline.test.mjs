// node:test port of tests/check-measure-baseline-unit.sh — same fixtures, same expectations,
// against the Node CLI (scripts/measure-baseline.mjs) instead of the bash script.

import { test, after } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync, rmSync, mkdirSync, cpSync, renameSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ENGINE = path.join(__dirname, "measure-baseline.mjs");
const REPO_ROOT = path.join(__dirname, "..");

const tmpRoots = [];
function mkTmp() {
  const d = mkdtempSync(path.join(tmpdir(), "mb-test-"));
  tmpRoots.push(d);
  return d;
}
after(() => {
  for (const d of tmpRoots) rmSync(d, { recursive: true, force: true });
});

function run(args) {
  const res = spawnSync(process.execPath, [ENGINE, ...args], { encoding: "utf8" });
  return { stdout: res.stdout, stderr: res.stderr, code: res.status };
}
function runMeasure(dir) {
  return run(["--dir", dir]);
}

// Builds a minimal installed tree: the ten @-imported files plus the two SESSION_START_FILES
// session-start reads, 2 effective lines each, plus whatever on-demand content the caller adds.
function mkProject() {
  const d = mkTmp();
  mkdirSync(path.join(d, ".agent-context", "memory"), { recursive: true });
  mkdirSync(path.join(d, ".agent-context", "skills"), { recursive: true });
  mkdirSync(path.join(d, ".claude"), { recursive: true });
  cpSync(
    path.join(REPO_ROOT, "templates", ".agent-context", "budget.conf"),
    path.join(d, ".agent-context", "budget.conf"),
  );
  writeFileSync(path.join(d, ".claude", "CLAUDE.md"), "line one\n@../AGENTS.md\n");
  writeFileSync(path.join(d, "AGENTS.md"), "line one\n@.agent-context/agent-startup.md\n");
  let prev = "agent-startup.md";
  const chain = [
    "layer0-agent-workflow.md",
    "layer1-bootstrap.md",
    "layer2-project-core.md",
    "layer3-guidebook.md",
    "base-principles.md",
    "knowledge-map.md",
    "skills/index.md",
  ];
  for (const f of chain) {
    writeFileSync(path.join(d, ".agent-context", prev), `line one\n@${f}\n`);
    prev = f;
  }
  writeFileSync(path.join(d, ".agent-context", "skills", "index.md"), "line one\n\nline two\n");
  writeFileSync(path.join(d, ".agent-context", "memory", "lessons.md"), "line one\n\nline two\n");
  writeFileSync(path.join(d, ".agent-context", "memory", "preferences.md"), "line one\n\nline two\n");
  return d;
}

// Pulls one column out of a table row (1-based, awk-style: field 1 is the first whitespace
// token). Anchored at line start so prose below the table cannot match.
function rowField(out, want, col) {
  const line = out.split("\n").find((l) => l.startsWith(`  ${want}`));
  assert.ok(line, `no row for '${want}' in:\n${out}`);
  return line.trim().split(/\s+/)[col - 1];
}

// 1. A bare install has twelve always-on files at 2 effective lines each and nothing on demand.
test("bare install: 12 layered files, 24 lines, nothing on demand, flat equals layered", () => {
  const P = mkProject();
  const { stdout: out } = runMeasure(P);
  assert.equal(rowField(out, "layered", 3), "12");
  assert.equal(rowField(out, "layered", 4), "24");
  assert.equal(rowField(out, "on-demand", 3), "0");
  assert.equal(rowField(out, "flat", 4), "24");
});

// 2. Memory, nested memory, skills, and the shared on-demand docs all land in the lazy set.
test("on-demand picks up memory, skills, delegation, memory-maintenance, map.json", () => {
  const P = mkProject();
  mkdirSync(path.join(P, ".agent-context", "memory", "billing"), { recursive: true });
  mkdirSync(path.join(P, ".agent-context", "skills", "foo"), { recursive: true });
  writeFileSync(path.join(P, ".agent-context", "memory", "people.md"), "a\nb\nc\n");
  writeFileSync(path.join(P, ".agent-context", "memory", "billing", "notes.md"), "a\nb\nc\n");
  writeFileSync(path.join(P, ".agent-context", "skills", "foo", "SKILL.md"), "a\nb\nc\n");
  writeFileSync(path.join(P, ".agent-context", "agent-delegation.md"), "a\nb\nc\n");
  writeFileSync(path.join(P, ".agent-context", "memory-maintenance.md"), "a\nb\nc\n");
  writeFileSync(path.join(P, ".agent-context", "map.json"), '{"nodes":[]}\n');
  const { stdout: out } = runMeasure(P);
  assert.equal(rowField(out, "on-demand", 3), "6");
  assert.equal(rowField(out, "on-demand", 4), "16");
  assert.equal(rowField(out, "flat", 4), "40");
});

// 3. Archived memory is history, not context — it must not inflate the on-demand set.
test("memory/archive excluded from on-demand", () => {
  const P = mkProject();
  mkdirSync(path.join(P, ".agent-context", "memory", "archive"), { recursive: true });
  writeFileSync(path.join(P, ".agent-context", "memory", "people.md"), "a\nb\nc\n");
  writeFileSync(path.join(P, ".agent-context", "memory", "archive", "2026-W01.md"), "x\ny\nz\nq\nw\ne\n");
  const { stdout: out } = runMeasure(P);
  assert.equal(rowField(out, "on-demand", 3), "1");
  assert.equal(rowField(out, "on-demand", 4), "3");
});

// 4. skills/index.md is always-on; discovering it under skills/ must not double-count it.
test("always-on skills/index.md not counted twice", () => {
  const P = mkProject();
  const { stdout: out } = runMeasure(P);
  assert.equal(rowField(out, "on-demand", 3), "0");
});

// 5. JSON mode reports the same split.
test("json mode: layered, on_demand, flat, kept_out_pct", () => {
  const P = mkProject();
  writeFileSync(path.join(P, ".agent-context", "memory", "people.md"), "a\nb\nc\n");
  const { stdout } = run(["--dir", P, "--json"]);
  const js = JSON.parse(stdout);
  assert.equal(js.layered.effective_lines, 24);
  assert.equal(js.on_demand.effective_lines, 3);
  assert.equal(js.flat.effective_lines, 27);
  assert.equal(js.on_demand.bytes, 6);
  assert.equal(js.on_demand.est_tokens, 2);
  const expectedTokens = Math.ceil(js.layered.bytes / 4);
  assert.equal(js.layered.est_tokens, expectedTokens);
  assert.equal(js.flat.bytes, js.layered.bytes + 6);
  assert.equal(js.kept_out_pct_of_flat.effective_lines, 11.1);
  const expectedPct = Number((200 / (2 + js.layered.est_tokens)).toFixed(1));
  assert.equal(js.kept_out_pct_of_flat.est_tokens, expectedPct);
});

// 5b. --conf is resolved against --dir, and a file it lists is layered, not on-demand.
test("--conf resolved against --dir; a listed file is layered not on-demand", () => {
  const P = mkProject();
  writeFileSync(path.join(P, ".agent-context", "memory", "people.md"), "a\nb\nc\n");
  writeFileSync(path.join(P, "custom.conf"), 'SESSION_START_FILES=".agent-context/memory/people.md"\n');
  const { stdout: out } = run(["--dir", P, "--conf", "custom.conf"]);
  assert.equal(rowField(out, "layered", 3), "11");
  assert.equal(rowField(out, "layered", 4), "23");
  assert.equal(rowField(out, "on-demand", 3), "2");
});

// 5c. Paths are data: spaces do not split a file, quotes and backslashes in the root stay valid JSON.
test("space in a file name counted as one file; quotes/backslashes in root stay valid JSON", () => {
  const P = mkProject();
  writeFileSync(path.join(P, ".agent-context", "memory", "my notes.md"), "a\nb\nc\n");
  const { stdout: out } = runMeasure(P);
  assert.equal(rowField(out, "on-demand", 3), "1");
  assert.equal(rowField(out, "on-demand", 4), "3");

  const Q = path.join(mkTmp(), 'we"ird\\dir');
  renameSync(P, Q);
  const { stdout } = run(["--dir", Q, "--json"]);
  const js = JSON.parse(stdout);
  assert.equal(js.root, Q);
});

// 6. A directory that is not a project fails loudly rather than reporting zeros.
test("missing budget.conf exits 2", () => {
  const P = mkProject();
  rmSync(path.join(P, ".agent-context", "budget.conf"));
  const { code } = runMeasure(P);
  assert.equal(code, 2);
});

test("missing --dir exits 2", () => {
  const { code } = run(["--dir", "/nonexistent/path/for/test"]);
  assert.equal(code, 2);
});

test("unknown option exits 2", () => {
  const { code } = run(["--bogus"]);
  assert.equal(code, 2);
});

test("--dir without a value exits 2", () => {
  const { code } = run(["--dir"]);
  assert.equal(code, 2);
});

test("--conf without a value exits 2", () => {
  const { code } = run(["--conf"]);
  assert.equal(code, 2);
});
