#!/usr/bin/env node
// Layered-vs-flat baseline report for an installed project (repo tool, not shipped).
//
//   measure-baseline.mjs [--dir PATH] [--conf PATH] [--json]
//
// Counts with check-token-budget.mjs, so the gate and the measurement share one definition.
//
// Three sets:
//   layered    the always-on set as the gate resolves it (@-import closure, SESSION_START_FILES,
//              INCLUDE_FILES)
//   on-demand  project knowledge pulled only when a task's keywords match it
//   flat       layered + on-demand — one file holding everything, the pre-layering shape
//
// Usage:
//   measure-baseline.mjs [--dir PATH] [--conf PATH] [--json]
//
// Exit codes: 0 = measured, 2 = usage/config error.

import { existsSync, statSync, readdirSync, accessSync, constants } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { loadConf, resolveFileSet, audit, jsonEscape } from "./check-token-budget.mjs";

const AC = ".agent-context";

function isReadableDir(p) {
  try {
    return statSync(p).isDirectory();
  } catch {
    return false;
  }
}
function isReadableFile(p) {
  try {
    accessSync(p, constants.R_OK);
    return statSync(p).isFile();
  } catch {
    return false;
  }
}

function parseArgs(argv) {
  let dir = ".";
  let conf = "";
  let json = false;
  let i = 0;
  while (i < argv.length) {
    const a = argv[i];
    if (a === "--dir") {
      if (i + 1 >= argv.length) fail("Error: --dir requires an argument");
      dir = argv[i + 1];
      i += 2;
    } else if (a.startsWith("--dir=")) {
      dir = a.slice("--dir=".length);
      i += 1;
    } else if (a === "--conf") {
      if (i + 1 >= argv.length) fail("Error: --conf requires an argument");
      conf = argv[i + 1];
      i += 2;
    } else if (a.startsWith("--conf=")) {
      conf = a.slice("--conf=".length);
      i += 1;
    } else if (a === "--json") {
      json = true;
      i += 1;
    } else {
      fail(`Unknown argument: ${a}`);
    }
  }
  return { dir, conf, json };
}

function fail(message) {
  console.error(message);
  process.exit(2);
}

// A file that already loads at startup is not "on demand" — collected recursively under
// dir (relative to ROOT), *.md and map.json, memory/archive pruned entirely.
function collect(dirAbs, archiveAbs, out) {
  if (!isReadableDir(dirAbs)) return;
  for (const entry of readdirSync(dirAbs, { withFileTypes: true })) {
    const abs = path.join(dirAbs, entry.name);
    if (abs === archiveAbs) continue;
    if (entry.isDirectory()) collect(abs, archiveAbs, out);
    else if (entry.isFile() && (entry.name.endsWith(".md") || entry.name === "map.json")) out.push(abs);
  }
}

function pct(a, b) {
  return b === 0 ? "0.0" : ((a * 100) / b).toFixed(1);
}

function padEnd(v, w) {
  return String(v).padEnd(w);
}
function padStart(v, w) {
  return String(v).padStart(w);
}
function row(a, b, c, d, e) {
  return `  ${padEnd(a, 24)} ${padStart(b, 6)} ${padStart(c, 11)} ${padStart(d, 10)} ${padStart(e, 9)}`;
}

function main() {
  const opts = parseArgs(process.argv.slice(2));

  if (!isReadableDir(opts.dir)) fail(`Error: --dir '${opts.dir}' is not a directory.`);
  const ROOT = path.resolve(process.cwd(), opts.dir);

  const confDisplay = opts.conf || `${AC}/budget.conf`;
  const confAbs = path.resolve(ROOT, confDisplay);
  if (!isReadableFile(confAbs)) {
    fail(`Error: budget conf '${confDisplay}' not found under ${ROOT} — is Agent-Context installed here?`);
  }

  // The layered set is whatever the gate already considers always-on — never a second list.
  const conf = loadConf(confAbs);
  const { files: layeredFiles, dangling } = resolveFileSet({ cwd: ROOT, conf, files: [] });
  if (dangling.length > 0) {
    console.error("Warning: @-imports that resolve to no file (not counted):");
    for (const line of dangling) console.error(line);
  }
  if (layeredFiles.length === 0) {
    fail(`Error: the @-import walk and the file lists in ${confDisplay} resolved to no files.`);
  }

  // On-demand: the knowledge a flat setup would have to load up front and a layered one does
  // not. memory/archive/ is excluded — archived entries are history, not live context.
  const acAbs = path.join(ROOT, AC);
  const archiveAbs = path.join(acAbs, "memory", "archive");
  const candidates = [];
  collect(path.join(acAbs, "memory"), archiveAbs, candidates);
  collect(path.join(acAbs, "skills"), archiveAbs, candidates);
  for (const name of ["agent-delegation.md", "memory-maintenance.md", "map.json"]) {
    const p = path.join(acAbs, name);
    if (isReadableFile(p)) candidates.push(p);
  }
  const layeredSet = new Set(layeredFiles);
  const onDemandFiles = candidates.map((abs) => path.relative(ROOT, abs)).filter((rel) => !layeredSet.has(rel));

  // Both sets go through the same counter (audit()) — this run measures, it does not judge.
  const layeredAudit = audit({ cwd: ROOT, files: layeredFiles });
  if (layeredAudit.missing_files) console.error("Warning: one or more always-on files are missing — counted as 0.");
  const L_COUNT = layeredFiles.length;
  const L_LINES = layeredAudit.total_effective_lines;
  const L_BYTES = layeredAudit.total_bytes;
  const L_TOKENS = layeredAudit.total_est_tokens;

  let O_COUNT = 0;
  let O_LINES = 0;
  let O_BYTES = 0;
  let O_TOKENS = 0;
  if (onDemandFiles.length > 0) {
    const onDemandAudit = audit({ cwd: ROOT, files: onDemandFiles });
    if (onDemandAudit.missing_files) console.error("Warning: one or more always-on files are missing — counted as 0.");
    O_COUNT = onDemandFiles.length;
    O_LINES = onDemandAudit.total_effective_lines;
    O_BYTES = onDemandAudit.total_bytes;
    O_TOKENS = onDemandAudit.total_est_tokens;
  }

  const F_COUNT = L_COUNT + O_COUNT;
  const F_LINES = L_LINES + O_LINES;
  const F_BYTES = L_BYTES + O_BYTES;
  const F_TOKENS = L_TOKENS + O_TOKENS;

  const PCT_LINES = pct(O_LINES, F_LINES);
  const PCT_TOKENS = pct(O_TOKENS, F_TOKENS);

  if (opts.json) {
    console.log(
      [
        "{",
        `  "root": "${jsonEscape(ROOT)}",`,
        `  "layered":   { "files": ${L_COUNT}, "effective_lines": ${L_LINES}, "bytes": ${L_BYTES}, "est_tokens": ${L_TOKENS} },`,
        `  "on_demand": { "files": ${O_COUNT}, "effective_lines": ${O_LINES}, "bytes": ${O_BYTES}, "est_tokens": ${O_TOKENS} },`,
        `  "flat":      { "files": ${F_COUNT}, "effective_lines": ${F_LINES}, "bytes": ${F_BYTES}, "est_tokens": ${F_TOKENS} },`,
        `  "kept_out_pct_of_flat": { "effective_lines": ${PCT_LINES}, "est_tokens": ${PCT_TOKENS} }`,
        "}",
      ].join("\n"),
    );
    process.exit(0);
  }

  console.log(`Always-on baseline vs. flat equivalent  (${ROOT})`);
  console.log("");
  console.log(row("set", "files", "eff.lines", "bytes", "~tokens"));
  console.log(row("layered (always-on)", L_COUNT, L_LINES, L_BYTES, L_TOKENS));
  console.log(row("on-demand (lazy)", O_COUNT, O_LINES, O_BYTES, O_TOKENS));
  console.log("  -----");
  console.log(row("flat (everything)", F_COUNT, F_LINES, F_BYTES, F_TOKENS));
  console.log("");
  console.log(`  Kept out of every session: ${O_LINES} effective lines · ${O_BYTES} bytes · ~${O_TOKENS} tokens`);
  console.log(`  That is ${PCT_LINES}% of the flat baseline by line, ${PCT_TOKENS}% by estimated token.`);
  console.log("");
  console.log("  ~tokens = ceil(bytes/4), a byte heuristic, not a tokenizer.");
  console.log("  Upper bound: a task that pulls on-demand files pays for exactly those files.");
  process.exit(0);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  main();
}
