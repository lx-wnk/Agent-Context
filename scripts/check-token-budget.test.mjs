// node:test port of tests/check-token-budget-unit.sh — same fixtures, same expectations,
// against the Node CLI (scripts/check-token-budget.mjs) instead of the bash engine.

import { test, after } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync, rmSync, mkdirSync, cpSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { loadConf, countEffective, resolveFileSet, audit } from "./check-token-budget.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ENGINE = path.join(__dirname, "check-token-budget.mjs");
const REPO_ROOT = path.join(__dirname, "..");

const tmpRoots = [];
function mkTmp() {
  const d = mkdtempSync(path.join(tmpdir(), "ctb-test-"));
  tmpRoots.push(d);
  return d;
}
after(() => {
  for (const d of tmpRoots) rmSync(d, { recursive: true, force: true });
});

function run(args, opts = {}) {
  const res = spawnSync(process.execPath, [ENGINE, ...args], { cwd: opts.cwd, encoding: "utf8" });
  return { stdout: res.stdout, stderr: res.stderr, code: res.status };
}
function runIn(dir, args) {
  return run(args, { cwd: dir });
}
function countTotal(file) {
  const { stdout } = run(["--max", "99999", file]);
  const line = stdout.split("\n").find((l) => l.includes("TOTAL"));
  assert.ok(line, `no TOTAL line in:\n${stdout}`);
  return line.trim().split(/\s+/)[0];
}

// 1. Plain instruction lines are counted.
test("plain lines counted", () => {
  const t = mkTmp();
  writeFileSync(path.join(t, "f.md"), "rule one\nrule two\nrule three\n");
  assert.equal(countTotal(path.join(t, "f.md")), "3");
});

// 2. Blank lines are ignored.
test("blank lines not counted", () => {
  const t = mkTmp();
  writeFileSync(path.join(t, "f.md"), "rule one\n\n\nrule two\n");
  assert.equal(countTotal(path.join(t, "f.md")), "2");
});

// 3. Single-line HTML comments are ignored.
test("single-line HTML comment skipped", () => {
  const t = mkTmp();
  writeFileSync(path.join(t, "f.md"), "<!-- a comment -->\nrule one\n");
  assert.equal(countTotal(path.join(t, "f.md")), "1");
});

// 4. Multi-line HTML comments are ignored.
test("multi-line HTML comment skipped", () => {
  const t = mkTmp();
  writeFileSync(path.join(t, "f.md"), "<!--\nblock comment line\nstill comment\n-->\nrule one\n");
  assert.equal(countTotal(path.join(t, "f.md")), "1");
});

// 5. Markdown table separator rows are ignored, but header/data rows count.
test("table separator skipped, header+data counted", () => {
  const t = mkTmp();
  writeFileSync(path.join(t, "f.md"), "| Col A | Col B |\n| ----- | ----- |\n| x | y |\n");
  assert.equal(countTotal(path.join(t, "f.md")), "2");
});

// 6. Horizontal-rule dividers are ignored.
test("horizontal rules skipped", () => {
  const t = mkTmp();
  writeFileSync(path.join(t, "f.md"), "rule one\n---\n===\n***\nrule two\n");
  assert.equal(countTotal(path.join(t, "f.md")), "2");
});

// 7. Over-budget input exits 1.
test("over-budget exits 1", () => {
  const t = mkTmp();
  writeFileSync(path.join(t, "f.md"), "a\nb\nc\nd\n");
  const { code } = run(["--max", "2", "--quiet", path.join(t, "f.md")]);
  assert.equal(code, 1);
});

// 8. Within-budget input exits 0.
test("within-budget exits 0", () => {
  const t = mkTmp();
  writeFileSync(path.join(t, "f.md"), "a\nb\n");
  const { code } = run(["--max", "5", "--quiet", path.join(t, "f.md")]);
  assert.equal(code, 0);
});

// 9. Conf-driven path: INCLUDE_FILES + MAX_EFFECTIVE_LINES read from conf.
test("conf-driven run within budget exits 0", () => {
  const t = mkTmp();
  writeFileSync(path.join(t, "layer.md"), "a\nb\nc\n");
  writeFileSync(path.join(t, "budget.conf"), `MAX_EFFECTIVE_LINES=10\nINCLUDE_FILES="${t}/layer.md"\n`);
  const { code } = runIn(t, ["--conf", path.join(t, "budget.conf"), "--quiet"]);
  assert.equal(code, 0);
});

// 10. Conf max can be overridden by --max.
test("--max overrides conf (exits 1 at max 1)", () => {
  const t = mkTmp();
  writeFileSync(path.join(t, "layer.md"), "a\nb\nc\n");
  writeFileSync(path.join(t, "budget.conf"), `MAX_EFFECTIVE_LINES=10\nINCLUDE_FILES="${t}/layer.md"\n`);
  const { code } = runIn(t, ["--conf", path.join(t, "budget.conf"), "--max", "1", "--quiet"]);
  assert.equal(code, 1);
});

// 11. Soft/hard caps: a 5-line file between a soft cap of 3 and a hard cap of 10 WARNS but passes.
test("over soft but under hard -> WARN + exit 0", () => {
  const t = mkTmp();
  writeFileSync(path.join(t, "f.md"), "a\nb\nc\nd\ne\n");
  writeFileSync(
    path.join(t, "soft.conf"),
    `MAX_EFFECTIVE_LINES=3\nMAX_EFFECTIVE_LINES_HARD=10\nINCLUDE_FILES="${t}/f.md"\n`,
  );
  const { code, stderr } = runIn(t, ["--conf", path.join(t, "soft.conf"), "--quiet"]);
  assert.equal(code, 0);
  assert.match(stderr, /WARN/);
});

// 12. Over the hard cap -> exit 1.
test("over hard cap -> exit 1", () => {
  const t = mkTmp();
  writeFileSync(path.join(t, "f.md"), "a\nb\nc\nd\ne\n");
  writeFileSync(
    path.join(t, "hard.conf"),
    `MAX_EFFECTIVE_LINES=2\nMAX_EFFECTIVE_LINES_HARD=4\nINCLUDE_FILES="${t}/f.md"\n`,
  );
  const { code } = runIn(t, ["--conf", path.join(t, "hard.conf"), "--quiet"]);
  assert.equal(code, 1);
});

// 13. No hard cap in the conf -> hard defaults to 250, not to the soft cap (old project confs).
test("no hard cap -> over soft only warns, hard_cap defaults to 250", () => {
  const t = mkTmp();
  writeFileSync(path.join(t, "f.md"), "a\nb\nc\nd\ne\n");
  writeFileSync(path.join(t, "nohard.conf"), `MAX_EFFECTIVE_LINES=4\nINCLUDE_FILES="${t}/f.md"\n`);
  const { code, stderr } = runIn(t, ["--conf", path.join(t, "nohard.conf"), "--quiet"]);
  assert.equal(code, 0);
  assert.match(stderr, /WARN/);
  const { stdout } = runIn(t, ["--conf", path.join(t, "nohard.conf"), "--json"]);
  assert.equal(JSON.parse(stdout).hard_cap, 250);

  const bigLines = Array.from({ length: 251 }, (_, i) => `rule ${i + 1}`).join("\n") + "\n";
  writeFileSync(path.join(t, "big.md"), bigLines);
  writeFileSync(path.join(t, "nohard-big.conf"), `MAX_EFFECTIVE_LINES=200\nINCLUDE_FILES="${t}/big.md"\n`);
  const { code: bigCode } = runIn(t, ["--conf", path.join(t, "nohard-big.conf"), "--quiet"]);
  assert.equal(bigCode, 1);
});

// 14. The conf is DATA, not a script. It is parsed for the keys this gate needs and never executed.
test("conf payload is never executed, parsed keys still apply", () => {
  const t = mkTmp();
  writeFileSync(path.join(t, "layer.md"), "a\nb\nc\n");
  const canary = path.join(t, "PAYLOAD_RAN");
  writeFileSync(
    path.join(t, "payload.conf"),
    `MAX_EFFECTIVE_LINES=10\nINCLUDE_FILES="${t}/layer.md"\ntouch ${canary}\n`,
  );
  const { code } = runIn(t, ["--conf", path.join(t, "payload.conf"), "--quiet"]);
  assert.equal(code, 0);
  assert.equal(existsSync(canary), false);
});

// 15. --list resolves the closure without counting it.
test("--list prints the resolved file set, exits 0 even over budget", () => {
  const t = mkTmp();
  writeFileSync(path.join(t, "one.md"), "a\n");
  writeFileSync(path.join(t, "two.md"), "b\n");
  writeFileSync(path.join(t, "list.conf"), `MAX_EFFECTIVE_LINES=1\nINCLUDE_FILES="\n${t}/one.md\n${t}/two.md\n"\n`);
  const { stdout, code } = runIn(t, ["--list", "--conf", path.join(t, "list.conf")]);
  assert.equal(stdout.trim().split("\n").length, 2);
  assert.equal(code, 0);
});

// 16. --json carries totals and per-file rows, and keeps the gate's verdict.
test("--json reports totals, bytes, tokens, status", () => {
  const t = mkTmp();
  writeFileSync(path.join(t, "f.md"), "a\nb\nc\n");
  const js = JSON.parse(run(["--json", "--max", "99999", path.join(t, "f.md")]).stdout);
  assert.equal(js.total_effective_lines, 3);
  assert.equal(js.total_bytes, 6);
  assert.equal(js.total_est_tokens, 2);
  assert.equal(js.status, "pass");

  const js2 = JSON.parse(run(["--json", "--max", "1", path.join(t, "f.md")]).stdout);
  assert.equal(js2.status, "fail");
});

// 17. A missing file is reported as absent rather than silently dropped from the array.
test("--json lists a missing file as absent", () => {
  const t = mkTmp();
  writeFileSync(path.join(t, "f.md"), "a\n");
  const js = JSON.parse(run(["--json", "--max", "99999", path.join(t, "f.md"), path.join(t, "gone.md")]).stdout);
  assert.equal(js.files.length, 2);
  assert.equal(js.files.filter((f) => f.present === false).length, 1);
});

// 18. FP-74: comment removal is shortest-match, and an unclosed comment does not hide lines.
test("FP-74: shortest-match comment removal, unclosed comment counts every line", () => {
  const t = mkTmp();
  writeFileSync(path.join(t, "f.md"), "<!-- a --> keep <!-- b -->\n");
  assert.equal(countTotal(path.join(t, "f.md")), "1");

  writeFileSync(path.join(t, "f.md"), "<!-- a --> <!-- b -->\n");
  assert.equal(countTotal(path.join(t, "f.md")), "0");

  writeFileSync(path.join(t, "f.md"), "a\n<!--\nb\nc\nd\n");
  assert.equal(countTotal(path.join(t, "f.md")), "5");

  writeFileSync(path.join(t, "f.md"), "a\n<!-- note\nb\n-->\nc\n");
  assert.equal(countTotal(path.join(t, "f.md")), "2");

  writeFileSync(path.join(t, "f.md"), "use `<!--` for notes\nrule two\nrule three\n");
  assert.equal(countTotal(path.join(t, "f.md")), "3");
});

// 19. Import walk: the set is what Claude Code loads.
function mkProj() {
  const d = mkTmp();
  mkdirSync(path.join(d, ".claude"), { recursive: true });
  mkdirSync(path.join(d, ".agent-context"), { recursive: true });
  writeFileSync(path.join(d, ".claude", "CLAUDE.md"), "# P\n\n@../AGENTS.md\n");
  writeFileSync(
    path.join(d, "AGENTS.md"),
    "a\n@.agent-context/layer2.md\n| x | @.agent-context/tbl.md |\nsee `@code-span.md` here\n```\n@fenced.md\n```\n",
  );
  writeFileSync(path.join(d, ".agent-context", "layer2.md"), "l2\n@base-principles.md\n");
  writeFileSync(path.join(d, ".agent-context", "base-principles.md"), "bp\n");
  writeFileSync(path.join(d, ".agent-context", "tbl.md"), "t\n");
  writeFileSync(path.join(d, "base-principles.md"), "decoy\n");
  writeFileSync(path.join(d, "code-span.md"), "x\n");
  writeFileSync(path.join(d, "fenced.md"), "x\n");
  writeFileSync(path.join(d, "extra.md"), "extra one\nextra two\n");
  writeFileSync(path.join(d, "budget.conf"), "MAX_EFFECTIVE_LINES=100\n");
  return d;
}

test("walk resolves imports relative to the importing file", () => {
  const P = mkProj();
  const listed = runIn(P, ["--list", "--conf", "budget.conf"]).stdout.trim().split("\n").sort();
  assert.deepEqual(listed, [
    ".agent-context/base-principles.md",
    ".agent-context/layer2.md",
    ".agent-context/tbl.md",
    ".claude/CLAUDE.md",
    "AGENTS.md",
  ]);
  const js = JSON.parse(runIn(P, ["--json", "--conf", "budget.conf"]).stdout);
  assert.equal(js.total_effective_lines, 13);
  const listedStr = runIn(P, ["--list", "--conf", "budget.conf"]).stdout;
  assert.equal(/code-span\.md|fenced\.md/.test(listedStr), false);
});

test("root CLAUDE.md is walked when present", () => {
  const P = mkProj();
  writeFileSync(path.join(P, "CLAUDE.md"), "root rule\n");
  const listed = runIn(P, ["--list", "--conf", "budget.conf"]).stdout.trim().split("\n");
  assert.equal(listed.filter((l) => l === "CLAUDE.md").length, 1);
});

// 20. INCLUDE_FILES is optional and additive.
test("INCLUDE_FILES adds an unimported file, deduplicated with the walk", () => {
  const P = mkProj();
  let listed = runIn(P, ["--list", "--conf", "budget.conf"]).stdout;
  assert.equal(/^extra\.md$/m.test(listed), false);

  writeFileSync(P + "/budget.conf", 'MAX_EFFECTIVE_LINES=100\nINCLUDE_FILES="\nextra.md\nAGENTS.md\n"\n');
  listed = runIn(P, ["--list", "--conf", "budget.conf"]).stdout;
  assert.equal(listed.split("\n").filter((l) => l === "extra.md").length, 1);
  assert.equal(listed.split("\n").filter((l) => l === "AGENTS.md").length, 1);

  const js = JSON.parse(runIn(P, ["--json", "--conf", "budget.conf"]).stdout);
  assert.equal(js.total_effective_lines, 15);

  const { stderr } = runIn(P, ["--conf", "budget.conf", "--quiet"]);
  assert.equal(
    stderr.split("\n").filter((l) => l === "note: extra.md is counted from INCLUDE_FILES but not @-imported").length,
    1,
  );
  assert.equal(stderr.split("\n").filter((l) => l.includes("AGENTS.md")).length, 0);
});

// 20a. Over a cap, the verdict says how many lines come from unimported INCLUDE_FILES entries.
test("FAIL names the unimported share; WARN without unimported entries has no share line", () => {
  const P = mkProj();
  writeFileSync(
    P + "/budget.conf",
    'MAX_EFFECTIVE_LINES=13\nMAX_EFFECTIVE_LINES_HARD=14\nINCLUDE_FILES="\nextra.md\n"\n',
  );
  let r = runIn(P, ["--conf", "budget.conf", "--quiet"]);
  assert.equal(r.code, 1);
  assert.match(r.stderr, /2 of them come from INCLUDE_FILES entries no @-import reaches/);
  const js = JSON.parse(runIn(P, ["--json", "--conf", "budget.conf"]).stdout);
  assert.equal(js.unimported_lines, 2);

  writeFileSync(P + "/budget.conf", "MAX_EFFECTIVE_LINES=12\nMAX_EFFECTIVE_LINES_HARD=100\n");
  r = runIn(P, ["--conf", "budget.conf", "--quiet"]);
  assert.equal(/come from INCLUDE_FILES/.test(r.stderr), false);
  const js2 = JSON.parse(runIn(P, ["--json", "--conf", "budget.conf"]).stdout);
  assert.equal(js2.unimported_lines, 0);
});

// 20b. SESSION_START_FILES: deliberate session-start reads without an import — counted, never noted.
test("SESSION_START_FILES adds files, deduplicated, no note printed", () => {
  const P = mkProj();
  writeFileSync(P + "/budget.conf", 'MAX_EFFECTIVE_LINES=100\nSESSION_START_FILES="\nextra.md\nAGENTS.md\n"\n');
  const listed = runIn(P, ["--list", "--conf", "budget.conf"]).stdout.split("\n");
  assert.equal(listed.filter((l) => l === "extra.md").length, 1);
  assert.equal(listed.filter((l) => l === "AGENTS.md").length, 1);
  const js = JSON.parse(runIn(P, ["--json", "--conf", "budget.conf"]).stdout);
  assert.equal(js.total_effective_lines, 15);
  const { stderr } = runIn(P, ["--conf", "budget.conf", "--quiet"]);
  assert.equal(stderr.includes("note:"), false);
});

// 20c. The shipped template conf in an install-shaped tree prints no note at all.
test("template conf run prints no note and counts session-start reads", () => {
  const P = mkProj();
  mkdirSync(path.join(P, ".agent-context", "memory"), { recursive: true });
  writeFileSync(path.join(P, ".agent-context", "memory", "lessons.md"), "lesson\n");
  writeFileSync(path.join(P, ".agent-context", "memory", "preferences.md"), "pref\n");
  cpSync(path.join(REPO_ROOT, "templates/.agent-context/budget.conf"), path.join(P, "budget.conf"));
  const { stderr } = runIn(P, ["--conf", "budget.conf", "--quiet"]);
  assert.equal(stderr.includes("note:"), false);
  const listed = runIn(P, ["--list", "--conf", "budget.conf"]).stdout;
  assert.equal(listed.includes("memory/lessons.md") && listed.includes("memory/preferences.md"), true);
});

// 21. A dangling import warns but does not fail the gate.
test("dangling import warns but exits 0", () => {
  const P = mkProj();
  writeFileSync(path.join(P, ".agent-context", "layer2.md"), "l2\n@base-principles.md\n@gone.md\n");
  const { code, stderr } = runIn(P, ["--conf", "budget.conf", "--quiet"]);
  assert.equal(code, 0);
  assert.match(stderr, /gone\.md/);
});

// 22. Usage and config errors exit 2, never 1.
test("usage and config errors exit 2", () => {
  const t = mkTmp();
  writeFileSync(path.join(t, "f.md"), "a\n");
  assert.equal(run([path.join(t, "f.md"), "--max"]).code, 2);
  assert.equal(run([path.join(t, "f.md"), "--conf"]).code, 2);
  assert.equal(run(["--bogus", path.join(t, "f.md")]).code, 2);
  assert.equal(run(["--max", "abc", path.join(t, "f.md")]).code, 2);

  writeFileSync(path.join(t, "bad.conf"), "MAX_EFFECTIVE_LINES=ten\n");
  assert.equal(run(["--conf", path.join(t, "bad.conf"), path.join(t, "f.md")]).code, 2);

  const t2 = mkTmp();
  writeFileSync(path.join(t2, "budget.conf"), "MAX_EFFECTIVE_LINES=10\n");
  const r = runIn(t2, ["--conf", path.join(t2, "budget.conf"), "--quiet"]);
  assert.equal(r.code, 2);
  assert.match(r.stderr, /no files to check/);
});

// 23. Paths are data: backslashes are printed verbatim and JSON-escaped, never interpreted.
test("paths with backslash/tab print verbatim and are JSON-escaped", () => {
  const t = mkTmp();
  const bsName = "a\\nb\\tc.md";
  const tabName = "tab\there.md";
  writeFileSync(path.join(t, bsName), "x\n");
  writeFileSync(path.join(t, tabName), "y\n");
  const out = run(["--max", "99", path.join(t, bsName)]).stdout;
  assert.equal(out.includes(path.join(t, bsName)), true);
  const js = run(["--json", "--max", "99", path.join(t, bsName), path.join(t, tabName)]).stdout;
  assert.equal(js.includes('/a\\\\nb\\\\tc.md"'), true);
  assert.equal(js.includes('tab\\u0009here.md"'), true);
  assert.equal(JSON.parse(js).files.length, 2);
});

// 24. INCLUDE_FILES entries are paths, not globs.
test("INCLUDE_FILES glob is not expanded", () => {
  const t = mkTmp();
  writeFileSync(path.join(t, "one.md"), "a\n");
  writeFileSync(path.join(t, "two.md"), "b\n");
  writeFileSync(path.join(t, "glob.conf"), 'INCLUDE_FILES="*.md"\n');
  const listed = runIn(t, ["--list", "--conf", "glob.conf"]).stdout.trim();
  assert.equal(listed, "*.md");
});

// --- direct unit tests for the exported pure functions ---

test("loadConf: bare, quoted, last-assignment-wins", () => {
  const t = mkTmp();
  const confPath = path.join(t, "c.conf");
  writeFileSync(confPath, 'MAX_EFFECTIVE_LINES=10\nMAX_EFFECTIVE_LINES=20 # comment\nINCLUDE_FILES="a\nb"\n');
  const conf = loadConf(confPath);
  assert.equal(conf.MAX_EFFECTIVE_LINES, "20");
  assert.equal(conf.INCLUDE_FILES, "a\nb");
});

test("loadConf: missing file returns empty object", () => {
  assert.deepEqual(loadConf("/no/such/file.conf"), {});
});

test("countEffective: matches CLI behavior directly", () => {
  assert.equal(countEffective("a\n\nb\n<!-- c -->\n"), 2);
});

test("resolveFileSet: explicit files bypass the walk", () => {
  const result = resolveFileSet({ cwd: "/tmp", conf: {}, files: ["a.md", "b.md"] });
  assert.deepEqual(result, { files: ["a.md", "b.md"], unimported: [], dangling: [] });
});

test("audit: throws ConfigError for a non-integer cap", () => {
  const t = mkTmp();
  writeFileSync(path.join(t, "f.md"), "a\n");
  assert.throws(() => audit({ cwd: t, confPath: "nope.conf", max: "abc", files: [path.join(t, "f.md")] }));
});
