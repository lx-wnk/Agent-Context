#!/usr/bin/env node
// Node port of context/bin/check-token-budget.sh — dependency-free, same CLI/behavior.
// See that file for the full spec; this keeps the same file-set resolution, effective-line
// counting, caps, stdout/stderr texts, --json shape and exit codes (0 within, 1 over hard,
// 2 usage/config error).

import { readFileSync, existsSync, statSync } from "node:fs";
import path from "node:path";
import { homedir } from "node:os";
import { fileURLToPath } from "node:url";

const CONF_KEYS = ["MAX_EFFECTIVE_LINES", "MAX_EFFECTIVE_LINES_HARD", "SESSION_START_FILES", "INCLUDE_FILES"];

export class UsageError extends Error {}
export class ConfigError extends Error {}

// ---- conf parsing, mirroring context/bin/conf-read.sh's non-evaluating grammar ----
// KEY=bare (ends at first whitespace), KEY="..."/KEY='...' (may span lines), last wins,
// leading `export ` and leading whitespace tolerated. A conf is DATA, never executed.
export function loadConf(confPath) {
  const out = {};
  if (!existsSync(confPath)) return out;
  const raw = readFileSync(confPath, "utf8");
  const lines = raw.split("\n");
  if (raw.endsWith("\n")) lines.pop();

  const state = {}; // key -> { quote, val }
  const result = {};
  const found = new Set();

  for (const withCr of lines) {
    const line = withCr.endsWith("\r") ? withCr.slice(0, -1) : withCr;
    let s = line.replace(/^[ \t]+/, "").replace(/^export[ \t]+/, "");

    for (const key of CONF_KEYS) {
      const st = state[key];
      if (st) {
        const p = line.indexOf(st.quote);
        if (p === -1) {
          st.val += line + "\n";
          continue;
        }
        if (p > 0 && line[p - 1] === "\\") {
          found.delete(key);
          console.error(`conf-read: ${confPath}: escaped quote in ${key} is not supported — key ignored`);
        } else {
          result[key] = st.val + line.slice(0, p);
          found.add(key);
        }
        delete state[key];
        continue;
      }

      const prefix = `${key}=`;
      if (!s.startsWith(prefix)) continue;
      const rest = s.slice(prefix.length);
      const first = rest[0];
      if (first === '"' || first === "'") {
        const body = rest.slice(1);
        const p = body.indexOf(first);
        if (p === -1) {
          state[key] = { quote: first, val: body + "\n" };
        } else if (p > 0 && body[p - 1] === "\\") {
          found.delete(key);
          console.error(`conf-read: ${confPath}: escaped quote in ${key} is not supported — key ignored`);
        } else {
          result[key] = body.slice(0, p);
          found.add(key);
        }
      } else {
        result[key] = rest.replace(/[ \t].*$/, "");
        found.add(key);
      }
    }
  }

  for (const key of CONF_KEYS) {
    if (found.has(key)) out[key] = chomp(result[key]);
  }
  return out;
}

function chomp(value) {
  let v = value;
  while (v.endsWith("\n")) v = v.slice(0, -1);
  return v;
}

function splitConfList(value) {
  if (!value) return [];
  return value.split(/\s+/).filter(Boolean);
}

// Normalizes a path string (`.`/`..`/empty segments), no filesystem access.
export function normalizePath(p) {
  const abs = p.startsWith("/");
  const stack = [];
  for (const seg of p.split("/")) {
    if (seg === "" || seg === ".") continue;
    if (seg === "..") {
      if (stack.length > 0 && stack[stack.length - 1] !== "..") stack.pop();
      else if (!abs) stack.push("..");
      continue;
    }
    stack.push(seg);
  }
  const out = stack.join("/");
  return abs ? `/${out}` : out === "" ? "." : out;
}

// One raw @-import path per file, in file order. Imports in code spans or fenced blocks are
// ignored. `<!--` handling lives in countEffective, not here — these are independent scans.
export function extractImports(text) {
  const fenceRe = /^ {0,3}(```|~~~)/;
  const tokenRe = /(^|[\s(>|])@([^\s)|]+)/;
  const imports = [];
  let fence = false;
  for (let line of text.split(/\r?\n/)) {
    if (fenceRe.test(line)) {
      fence = !fence;
      continue;
    }
    if (fence) continue;
    line = line.replace(/`[^`]*`/g, "");
    let rest = line;
    let m;
    while ((m = tokenRe.exec(rest))) {
      imports.push(m[2]);
      rest = rest.slice(m.index + m[0].length);
    }
  }
  return imports;
}

function toAbs(cwd, p) {
  return path.isAbsolute(p) ? p : path.join(cwd, p);
}
function isFile(cwd, p) {
  try {
    return statSync(toAbs(cwd, p)).isFile();
  } catch {
    return false;
  }
}
function readText(cwd, p) {
  return readFileSync(toAbs(cwd, p), "utf8");
}

// resolveFileSet({cwd, conf, files}) -> {files, unimported, dangling}
// Explicit `files` is the whole set (no walk). Otherwise: the @-import closure walked from
// .claude/CLAUDE.md and ./CLAUDE.md (each import relative to the importing file), plus
// conf.SESSION_START_FILES, plus conf.INCLUDE_FILES (its entries not reached by the walk are
// returned in `unimported`), deduplicated.
export function resolveFileSet({ cwd, conf = {}, files = [] }) {
  if (files.length > 0) {
    return { files: [...files], unimported: [], dangling: [] };
  }

  const seen = new Set();
  const resultFiles = [];
  const dangling = [];

  const addFile = (p) => {
    if (seen.has(p)) return false;
    seen.add(p);
    resultFiles.push(p);
    return true;
  };

  const walk = (root) => {
    const queue = [root];
    while (queue.length) {
      const cur = queue.shift();
      if (!addFile(cur)) continue;
      for (const imp of extractImports(readText(cwd, cur))) {
        let target;
        if (imp.startsWith("/")) target = imp;
        else if (imp.startsWith("~/")) target = path.join(homedir(), imp.slice(2));
        else target = `${path.dirname(cur)}/${imp}`;
        target = normalizePath(target);
        if (isFile(cwd, target)) queue.push(target);
        else dangling.push(`  ${cur} -> @${imp}`);
      }
    }
  };

  for (const root of [".claude/CLAUDE.md", "CLAUDE.md"]) {
    if (isFile(cwd, root)) walk(root);
  }

  for (const f of splitConfList(conf.SESSION_START_FILES)) {
    addFile(normalizePath(f));
  }

  const unimported = [];
  for (const raw of splitConfList(conf.INCLUDE_FILES)) {
    const f = normalizePath(raw);
    if (addFile(f)) unimported.push(f);
  }

  return { files: resultFiles, unimported, dangling };
}

// Counts effective instruction lines: skips blank lines, HTML comments (single- and
// multi-line; `<!--` inside a code span is text; an unclosed comment hides nothing — the
// agent still loads those lines, so they count), table separator rows, and horizontal rules.
export function countEffective(text) {
  const lines = text.split(/\r?\n/);
  if (text.endsWith("\n")) lines.pop();

  let inComment = false;
  let n = 0;
  let pending = 0;

  for (const raw of lines) {
    let rest = raw;
    let out = "";
    let closed = false;
    const touched0 = inComment;
    let touched = touched0;

    while (rest !== "") {
      if (inComment) {
        const p = rest.indexOf("-->");
        if (p === -1) break;
        rest = rest.slice(p + 3);
        inComment = false;
        closed = true;
      } else {
        const p = commentStart(rest);
        if (p === -1) {
          out += rest;
          break;
        }
        out += rest.slice(0, p);
        rest = rest.slice(p + 4);
        inComment = true;
        touched = true;
      }
    }

    const visible = isEffectiveLine(out);
    if (visible) n++;
    if (inComment) {
      if (closed) pending = 0;
      if (!visible && isEffectiveLine(raw)) pending++;
    } else if (touched) {
      pending = 0;
    }
  }

  if (inComment) n += pending;
  return n;
}

function isEffectiveLine(s) {
  const trimmed = s.trim();
  if (trimmed === "") return false;
  if (/^\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)+\|?$/.test(trimmed)) return false;
  if (/^(-{3,}|={3,}|\*{3,})$/.test(trimmed)) return false;
  return true;
}

function commentStart(s) {
  const masked = s.replace(/`[^`]*`/g, (m) => " ".repeat(m.length));
  return masked.indexOf("<!--");
}

function jsonEscape(str) {
  return str.split("\n").map(jsonEscapeLine).join("\\n");
}
function jsonEscapeLine(s) {
  let out = "";
  for (const ch of s) {
    const code = ch.codePointAt(0);
    if (ch === "\\" || ch === '"') out += `\\${ch}`;
    else if (code >= 1 && code < 32) out += `\\u${code.toString(16).padStart(4, "0")}`;
    else out += ch;
  }
  return out;
}

// audit({cwd, confPath, max, files}) -> the JSON-object data (plus `dangling` and
// `unimportedFiles` for CLI diagnostics). Throws ConfigError for a non-integer cap or an
// empty resolved file set — both are exit-2 conditions for the CLI.
export function audit({ cwd, confPath, max, files = [] }) {
  const resolvedConfPath = confPath === undefined ? undefined : toAbs(cwd, confPath);
  const conf = resolvedConfPath === undefined ? {} : loadConf(resolvedConfPath);

  let soft = conf.MAX_EFFECTIVE_LINES ?? "200";
  let hard = conf.MAX_EFFECTIVE_LINES_HARD ?? "";
  if (max !== undefined && max !== "") {
    soft = String(max);
    hard = String(max);
  }
  if (hard === "") hard = "250";

  for (const [name, value] of [
    ["MAX_EFFECTIVE_LINES", soft],
    ["MAX_EFFECTIVE_LINES_HARD", hard],
  ]) {
    if (!/^[0-9]+$/.test(value)) {
      throw new ConfigError(`Error: ${name} must be an integer, got '${value}'.`);
    }
  }
  const softCap = parseInt(soft, 10);
  let hardCap = parseInt(hard, 10);
  if (hardCap < softCap) hardCap = softCap;

  const { files: resolvedFiles, unimported, dangling } = resolveFileSet({ cwd, conf, files });

  if (resolvedFiles.length === 0) {
    throw new ConfigError(
      `Error: no files to check. No .claude/CLAUDE.md or CLAUDE.md to walk, and no SESSION_START_FILES or INCLUDE_FILES in ${confPath}.`,
    );
  }

  let total = 0;
  let totalBytes = 0;
  let unimportedLines = 0;
  let missing = 0;
  const fileRows = [];

  for (const f of resolvedFiles) {
    const abs = toAbs(cwd, f);
    let buf;
    try {
      buf = readFileSync(abs);
    } catch {
      fileRows.push({ path: f, present: false, effective_lines: 0, bytes: 0 });
      missing = 1;
      continue;
    }
    const bytes = buf.length;
    const effective = countEffective(buf.toString("utf8"));
    total += effective;
    totalBytes += bytes;
    if (unimported.includes(f)) unimportedLines += effective;
    fileRows.push({ path: f, present: true, effective_lines: effective, bytes });
  }

  const estTokens = Math.trunc((totalBytes + 3) / 4);
  let status = "pass";
  if (total > hardCap) status = "fail";
  else if (total > softCap) status = "warn";

  return {
    total_effective_lines: total,
    total_bytes: totalBytes,
    total_est_tokens: estTokens,
    soft_cap: softCap,
    hard_cap: hardCap,
    unimported_lines: unimportedLines,
    missing_files: missing,
    status,
    files: fileRows,
    dangling,
    unimportedFiles: unimported,
  };
}

// ---------------------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------------------

function parseArgs(argv) {
  let conf = ".agent-context/budget.conf";
  let max;
  let quiet = false;
  let json = false;
  let list = false;
  const files = [];
  let i = 0;
  while (i < argv.length) {
    const a = argv[i];
    if (a === "--conf") {
      if (i + 1 >= argv.length) throw new UsageError("Error: --conf requires an argument");
      conf = argv[i + 1];
      i += 2;
    } else if (a.startsWith("--conf=")) {
      conf = a.slice("--conf=".length);
      i += 1;
    } else if (a === "--max") {
      if (i + 1 >= argv.length) throw new UsageError("Error: --max requires an argument");
      max = argv[i + 1];
      i += 2;
    } else if (a.startsWith("--max=")) {
      max = a.slice("--max=".length);
      i += 1;
    } else if (a === "--quiet") {
      quiet = true;
      i += 1;
    } else if (a === "--json") {
      json = true;
      quiet = true;
      i += 1;
    } else if (a === "--list") {
      list = true;
      i += 1;
    } else if (a === "--") {
      i += 1;
      while (i < argv.length) {
        files.push(argv[i]);
        i += 1;
      }
    } else if (a.startsWith("-")) {
      throw new UsageError(`Unknown option: ${a}`);
    } else {
      files.push(a);
      i += 1;
    }
  }
  return { conf, max, quiet, json, list, files };
}

function formatJson(result) {
  const header = [
    "{",
    `  "total_effective_lines": ${result.total_effective_lines},`,
    `  "total_bytes": ${result.total_bytes},`,
    `  "total_est_tokens": ${result.total_est_tokens},`,
    `  "soft_cap": ${result.soft_cap},`,
    `  "hard_cap": ${result.hard_cap},`,
    `  "unimported_lines": ${result.unimported_lines},`,
    `  "missing_files": ${result.missing_files},`,
    `  "status": "${result.status}",`,
    `  "files": [`,
  ];
  const fileLines = result.files.map(
    (f) =>
      `    { "path": "${jsonEscape(f.path)}", "present": ${f.present}, "effective_lines": ${f.effective_lines}, "bytes": ${f.bytes} }`,
  );
  return [...header, fileLines.join(",\n"), "  ]", "}"].join("\n");
}

function printTable(result) {
  console.log("Token-budget audit (effective instruction lines, always-on closure):");
  for (const f of result.files) {
    if (!f.present) console.log(`  MISSING  ${f.path}`);
    else console.log(`  ${String(f.effective_lines).padStart(5)}  ${f.path}`);
  }
  console.log("  -----");
  console.log(
    `  ${String(result.total_effective_lines).padStart(5)}  TOTAL (soft: ${result.soft_cap} · hard: ${result.hard_cap})`,
  );
}

function printUnimportedHint(result) {
  if (result.unimported_lines <= 0) return;
  console.error(
    `      ${result.unimported_lines} of them come from INCLUDE_FILES entries no @-import reaches (see the notes above) —`,
  );
  console.error(
    "      those files never load. Resolve each note first: remove a stale entry, or add the @-import its template has.",
  );
}

function main() {
  let opts;
  try {
    opts = parseArgs(process.argv.slice(2));
  } catch (e) {
    if (e instanceof UsageError) {
      console.error(e.message);
      process.exit(2);
    }
    throw e;
  }

  const cwd = process.cwd();
  let result;
  try {
    result = audit({ cwd, confPath: opts.conf, max: opts.max, files: opts.files });
  } catch (e) {
    if (e instanceof ConfigError) {
      console.error(e.message);
      process.exit(2);
    }
    throw e;
  }

  if (!opts.list && result.unimportedFiles.length > 0) {
    for (const f of result.unimportedFiles) {
      console.error(`note: ${f} is counted from INCLUDE_FILES but not @-imported`);
    }
  }
  if (result.dangling.length > 0) {
    console.error("Warning: @-imports that resolve to no file (not counted):");
    for (const line of result.dangling) console.error(line);
  }

  if (opts.list) {
    for (const f of result.files) console.log(f.path);
    process.exit(0);
  }

  if (opts.json) console.log(formatJson(result));
  if (!opts.quiet) printTable(result);

  if (result.missing_files) {
    console.error("Warning: one or more always-on files are missing — counted as 0.");
  }

  if (result.total_effective_lines > result.hard_cap) {
    console.error(
      `FAIL: always-on baseline is ${result.total_effective_lines} effective lines, over the hard cap of ${result.hard_cap}.`,
    );
    printUnimportedHint(result);
    console.error("      Move optional content behind task-routing (memory/ or skills/) to reduce it.");
    process.exit(1);
  }

  if (result.total_effective_lines > result.soft_cap) {
    console.error(
      `WARN: always-on baseline is ${result.total_effective_lines} effective lines, over the soft target of ${result.soft_cap} (hard cap ${result.hard_cap}).`,
    );
    printUnimportedHint(result);
    console.error("      Consider moving optional content behind task-routing (memory/ or skills/).");
    if (!opts.quiet) console.log("PASS: within the hard cap (soft target exceeded).");
    process.exit(0);
  }

  if (!opts.quiet) console.log("PASS: always-on baseline within budget.");
  process.exit(0);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  main();
}
