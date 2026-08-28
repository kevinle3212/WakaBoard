#!/usr/bin/env node
// Verification oracles for the non-test gates in GATES.md.
//
// Written in Node rather than shell for one reason: the absence checks below decide
// whether something is *not* present, and `grep`'s exit code is easy to invert by
// accident and is not consistent across the BSD, GNU, and shim variants that may be
// on PATH. A wrong answer here would certify a gate that is actually failing.
//
// Every absence check is controlled: `--self-test` plants a known violation and
// asserts the detector sees it, so a detector that can never fail is caught at
// authoring time rather than at report time.

import { readFileSync, existsSync, readdirSync, statSync, lstatSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { join, relative, extname } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(fileURLToPath(import.meta.url), "..", "..");

// --- helpers ---------------------------------------------------------------

const read = (p) => readFileSync(join(ROOT, p), "utf8");
const exists = (p) => existsSync(join(ROOT, p));

/** Every file under `dir` matching one of `extensions`, skipping build output. */
function walk(dir, extensions, out = []) {
  const absolute = join(ROOT, dir);
  if (!existsSync(absolute)) return out;
  for (const entry of readdirSync(absolute)) {
    if (entry.startsWith(".") || entry === "DerivedData") continue;
    const full = join(absolute, entry);
    const rel = relative(ROOT, full);
    if (statSync(full).isDirectory()) walk(rel, extensions, out);
    else if (extensions.includes(extname(entry))) out.push(rel);
  }
  return out;
}

const failures = [];
const fail = (gate, message) => failures.push(`${gate}: ${message}`);

/** Asserts `condition`, recording a failure with `message` when it does not hold. */
function check(gate, condition, message) {
  if (!condition) fail(gate, message);
  return condition;
}

function finish(token) {
  if (failures.length === 0) {
    console.log(token);
    process.exit(0);
  }
  for (const failure of failures) console.error(`FAIL ${failure}`);
  console.error(`\n${failures.length} check(s) failed.`);
  process.exit(1);
}

// --- detectors (shared with --self-test so the controls exercise real code) ---

/** Source files that ship to a user: not tests, not previews. */
function shippingSwiftFiles() {
  return [...walk("Sources", [".swift"]), ...walk("Apps", [".swift"]), ...walk("Widgets", [".swift"])];
}

/**
 * Force-unwraps in shipping code, excluding those that are provably safe.
 *
 * `URL(string:)!` on a string literal is allowed only where a comment marks it, and
 * `try!` is never allowed. Lines inside `#Preview` blocks are excluded because
 * previews do not ship.
 */
function findForceUnwraps(text) {
  const hits = [];
  const lines = text.split("\n");
  let inPreview = 0;
  lines.forEach((line, index) => {
    if (/#Preview\b/.test(line)) inPreview = 1;
    if (inPreview > 0) {
      inPreview += (line.match(/\{/g) || []).length - (line.match(/\}/g) || []).length;
      if (inPreview <= 0) inPreview = 0;
      return;
    }
    const stripped = line.replace(/\/\/.*$/, "");
    // Allow the documented canonical-URL constants, which are literal and tested.
    if (/allow-force-unwrap/.test(line)) return;
    // `try!`, or a trailing `!` on an expression — excluding `!=` and prefix negation.
    // One finding per line: both patterns match `try! foo()`, and reporting the same
    // line twice would make a control asserting an exact count fail spuriously.
    const forced = /\btry!\s/.test(stripped) || /[A-Za-z0-9_\)\]]\!(?!=)(\s|$|\)|,|\.|;)/.test(stripped);
    if (forced) hits.push({ line: index + 1, text: line.trim() });
  });
  return hits;
}

/** Credential-shaped literals assigned in source. */
function findSecretLiterals(text) {
  const pattern = /(api[_-]?key|secret|token|password|bearer)\s*[:=]\s*"([A-Za-z0-9\/_+=-]{16,})"/gi;
  return [...text.matchAll(pattern)].map((m) => m[0]);
}

/** References to fixture/sample data from a non-preview, non-test context. */
function findFixtureLeaks(text) {
  const names = ["WakaDashboard.fixture", "sampleProjects", "sampleLanguages", "WakaFixtures"];
  const hits = [];
  text.split("\n").forEach((line, index) => {
    const stripped = line.replace(/\/\/.*$/, "");
    for (const name of names) {
      if (stripped.includes(name)) hits.push({ line: index + 1, name });
    }
  });
  return hits;
}

// --- gate implementations --------------------------------------------------

function audit() {
  const gate = "G1";
  if (!check(gate, exists("docs/AUDIT.md"), "docs/AUDIT.md is missing")) return finish("AUDIT_OK");
  const text = read("docs/AUDIT.md");

  // The audit documents the code as it was *before* this change, so its line
  // references must resolve against the audited commit, not the current tree.
  // Checking them against the current tree would fail for every line the audit
  // caused to move — and would silently pass anchors that were never real.
  const commitMatch = text.match(/commit `([0-9a-f]{7,40})`/);
  if (!check(gate, commitMatch, "AUDIT.md does not name the audited commit")) return finish("AUDIT_OK");
  const commit = commitMatch[1];

  const fileAt = (file) => {
    try {
      return execFileSync("git", ["show", `${commit}:${file}`], { cwd: ROOT, encoding: "utf8" });
    } catch {
      return null;
    }
  };

  try {
    execFileSync("git", ["cat-file", "-e", `${commit}^{commit}`], { cwd: ROOT, stdio: "ignore" });
  } catch {
    fail(gate, `the audited commit ${commit} is not present in this repository`);
    return finish("AUDIT_OK");
  }

  const anchors = [...text.matchAll(/`((?:Sources|Apps|Widgets|Tests|Config|docs|\.github)\/[^`:]+):(\d+)`/g)];
  check(gate, anchors.length >= 15, `expected at least 15 file:line anchors, found ${anchors.length}`);

  for (const [, file, lineText] of anchors) {
    const content = fileAt(file);
    if (content === null) {
      fail(gate, `audit cites ${file}, which did not exist at ${commit}`);
      continue;
    }
    const lineCount = content.split("\n").length;
    if (Number(lineText) > lineCount) {
      fail(gate, `audit cites ${file}:${lineText}, but that file had ${lineCount} lines at ${commit}`);
    }
  }

  for (const severity of ["Critical", "High", "Medium", "Low"]) {
    check(gate, text.includes(severity), `audit is missing the ${severity} severity section`);
  }
  check(gate, /What remains open/i.test(text), "audit does not state what remains open");
  finish("AUDIT_OK");
}

function noFixtureLeak() {
  const gate = "G2";
  for (const file of shippingSwiftFiles()) {
    for (const hit of findFixtureLeaks(read(file))) {
      fail(gate, `${file}:${hit.line} references fixture data (${hit.name}) in shipping code`);
    }
  }
  // The model must not be able to fabricate a loaded state without data.
  const model = read("Sources/WakaUI/WakaUIModel.swift");
  check(gate, !/func refresh\(\)[^}]*\{\s*state = \.loaded\s*\}/s.test(model),
    "refresh() assigns .loaded without loading anything");
  check(gate, model.includes("environment.repository.days("),
    "the model never calls the repository, so it cannot be showing real data");
  finish("NO_FIXTURE_LEAK_OK");
}

const LEGAL_DOCUMENTS = {
  "TERMS.md": ["Limitation of liability", "Governing law", "Apple App Store", "AS IS"],
  "PRIVACY.md": ["Legal basis", "Your rights", "International transfers", "Children"],
  "RETENTION.md": ["Retention schedule", "90 days", "7 days", "How deletion actually works"],
  "ACCESSIBILITY.md": ["WCAG 2.2", "EN 301 549", "Conformance status", "Feedback"],
  "DISCLAIMER.md": ["No warranty", "Limitation of liability", "cannot be excluded"],
  "SECURITY.md": ["Reporting a vulnerability", "Threat model", "Residual risks"]
};

const CONTACT = "KevinLe3212@gmail.com";
const PLACEHOLDERS = [
  "[YOUR NAME]", "[CONTACT EMAIL]", "[JURISDICTION]", "TODO", "FIXME",
  "[yyyy]", "[name of copyright owner]", "example.invalid", "your-email@"
];

function legal() {
  const gate = "G11";
  for (const [file, required] of Object.entries(LEGAL_DOCUMENTS)) {
    if (!check(gate, exists(file), `${file} is missing`)) continue;
    const text = read(file);
    check(gate, text.includes(CONTACT), `${file} does not name the real contact address`);
    for (const phrase of required) {
      check(gate, text.toLowerCase().includes(phrase.toLowerCase()), `${file} is missing "${phrase}"`);
    }
    for (const placeholder of PLACEHOLDERS) {
      check(gate, !text.includes(placeholder), `${file} still contains the placeholder "${placeholder}"`);
    }
    check(gate, /\*\*Effective date:\*\*|\*\*Last updated:\*\*/.test(text), `${file} has no effective/updated date`);
  }
  // Governing law must be concrete.
  const terms = read("TERMS.md");
  check(gate, /State of Oregon/.test(terms), "TERMS.md does not name a governing jurisdiction");
  finish("LEGAL_OK");
}

const REGIMES = {
  "GDPR": /GDPR/,
  "UK GDPR": /UK GDPR/,
  "CCPA/CPRA": /CCPA\/CPRA|CPRA/,
  "PIPEDA": /PIPEDA/,
  "LGPD": /LGPD/,
  "PIPL": /PIPL/,
  "APPI": /APPI/,
  "PIPA": /PIPA/,
  "PDPA": /PDPA/,
  "DPDP": /DPDP/,
  "Australian Privacy Act": /Privacy Act 1988|Australian Privacy Principles/,
  "ePrivacy": /ePrivacy|PECR/,
  "Cyber Resilience Act": /Cyber Resilience Act/,
  "COPPA": /COPPA/
};

function compliance() {
  const gate = "G12";
  const text = read("PRIVACY.md");
  for (const [name, pattern] of Object.entries(REGIMES)) {
    check(gate, pattern.test(text), `PRIVACY.md does not address ${name}`);
  }
  // Substance, not just the acronym.
  check(gate, /Art\. 6\(1\)\(b\)/.test(text), "PRIVACY.md states no GDPR Art. 6 lawful basis");
  check(gate, /right to (know|erasure)|Erasure/i.test(text), "PRIVACY.md does not enumerate data-subject rights");
  check(gate, /30\s+days/.test(text), "PRIVACY.md commits to no response deadline");
  check(gate, /Data Not Collected/.test(text), "PRIVACY.md does not state the App Store privacy label");
  finish("COMPLIANCE_OK");
}

function accessibility() {
  const gate = "G13";
  const text = read("ACCESSIBILITY.md");
  check(gate, /WCAG 2\.2/.test(text), "no WCAG 2.2 target stated");
  check(gate, /EN 301 549/.test(text), "no EN 301 549 reference");
  check(gate, /European Accessibility Act/.test(text), "EAA position not stated");
  check(gate, /ADA|Section 508/.test(text), "US position not stated");
  // The claim must be qualified, since no device pass has been run.
  check(gate, /Partially conformant/i.test(text), "conformance claim is not qualified as partial");
  check(gate, /Known gaps/i.test(text), "no known-gaps section");

  // The claim must be backed by real assertions, not prose.
  check(gate, exists("Tests/WakaUITests/AccessibilityTests.swift"), "no accessibility test file");
  const tests = read("Tests/WakaUITests/AccessibilityTests.swift");
  const testCount = (tests.match(/@Test\(/g) || []).length;
  check(gate, testCount >= 7, `expected at least 7 accessibility assertions, found ${testCount}`);

  // The views must actually apply the target-size constant they document.
  const ui = read("Sources/WakaUI/WakaUI.swift");
  const applications = (ui.match(/WakaAccessibility\.minimumTargetSize/g) || []).length;
  check(gate, applications >= 6, `minimumTargetSize applied only ${applications} times in the view layer`);
  check(gate, /accessibilityReduceMotion/.test(ui), "Reduce Motion is not honored in the view layer");
  finish("ACCESSIBILITY_OK");
}

function apple() {
  const gate = "G14";
  for (const manifest of ["Config/PrivacyInfo.xcprivacy", "Config/PrivacyInfo-Widgets.xcprivacy"]) {
    if (!check(gate, exists(manifest), `${manifest} is missing`)) continue;
    const text = read(manifest);
    check(gate, /NSPrivacyTracking/.test(text), `${manifest} omits NSPrivacyTracking`);
    check(gate, /NSPrivacyCollectedDataTypes/.test(text), `${manifest} omits NSPrivacyCollectedDataTypes`);
    check(gate, /NSPrivacyAccessedAPICategoryUserDefaults/.test(text),
      `${manifest} does not declare the UserDefaults required-reason API`);
    check(gate, /CA92\.1/.test(text), `${manifest} declares no reason code for UserDefaults`);
  }
  for (const plist of ["Config/WakaBoard-Info.plist", "Config/WakaBoardWidgets-Info.plist"]) {
    const text = read(plist);
    check(gate, /ITSAppUsesNonExemptEncryption/.test(text), `${plist} omits the export-compliance key`);
  }
  // Both manifests must be wired into the generated project, or they never ship.
  const project = read("project.yml");
  check(gate, /PrivacyInfo\.xcprivacy/.test(project), "project.yml does not include the app privacy manifest");
  check(gate, /PrivacyInfo-Widgets\.xcprivacy/.test(project), "project.yml does not include the widget privacy manifest");
  finish("APPLE_OK");
}

function license() {
  const gate = "G19";
  if (!check(gate, exists("LICENSE"), "LICENSE is missing")) return finish("LICENSE_OK");
  const text = read("LICENSE");
  // The full licence, not the short boilerplate notice the scaffold shipped.
  check(gate, text.includes("END OF TERMS AND CONDITIONS"), "LICENSE is truncated: no END OF TERMS AND CONDITIONS");
  for (const section of [
    "1. Definitions.", "2. Grant of Copyright License.", "3. Grant of Patent License.",
    "4. Redistribution.", "5. Submission of Contributions.", "6. Trademarks.",
    "7. Disclaimer of Warranty.", "8. Limitation of Liability.", "9. Accepting Warranty or Additional Liability."
  ]) {
    check(gate, text.includes(section), `LICENSE is missing section "${section}"`);
  }
  check(gate, text.split("\n").length >= 200, "LICENSE is shorter than the canonical Apache-2.0 text");
  check(gate, /Copyright 2026 Kevin Le/.test(text), "LICENSE appendix copyright is not filled in");
  check(gate, !/\[yyyy\]|\[name of copyright owner\]/.test(text), "LICENSE still contains appendix placeholders");

  check(gate, exists("NOTICE"), "NOTICE is missing");
  if (exists("NOTICE")) {
    const notice = read("NOTICE");
    check(gate, /Kevin Le/.test(notice), "NOTICE does not name the copyright holder");
    check(gate, /WakaTime/.test(notice), "NOTICE omits the WakaTime trademark notice");
  }
  check(gate, /Apache-2\.0|Apache License/.test(read("README.md")), "README does not state the licence");
  finish("LICENSE_OK");
}

function hygiene() {
  const gate = "G17";
  const files = shippingSwiftFiles();

  for (const file of files) {
    const text = read(file);
    for (const literal of findSecretLiterals(text)) {
      fail(gate, `${file} contains a credential-shaped literal: ${literal.slice(0, 40)}`);
    }
    for (const hit of findForceUnwraps(text)) {
      fail(gate, `${file}:${hit.line} force-unwraps in shipping code: ${hit.text.slice(0, 80)}`);
    }
  }

  // Config and CI must not carry secrets either.
  for (const file of [...walk("Config", [".plist", ".xcconfig", ".entitlements"]), ...walk(".github", [".yml"])]) {
    for (const literal of findSecretLiterals(read(file))) {
      fail(gate, `${file} contains a credential-shaped literal: ${literal.slice(0, 40)}`);
    }
  }

  // No world-writable path in the tracked tree.
  for (const dir of ["Sources", "Apps", "Widgets", "Tests", "Config", "scripts", "docs", ".github"]) {
    const absolute = join(ROOT, dir);
    if (!existsSync(absolute)) continue;
    const mode = lstatSync(absolute).mode & 0o777;
    if (mode & 0o002) fail(gate, `${dir} is world-writable (mode ${mode.toString(8)})`);
  }

  finish("HYGIENE_OK");
}

function ci() {
  const gate = "G18";
  const path = ".github/workflows/ci.yml";
  if (!check(gate, exists(path), `${path} is missing`)) return finish("CI_OK");
  const text = read(path);

  check(gate, /permissions:\s*\n\s*contents: read/.test(text), "CI does not declare least-privilege permissions");
  check(gate, /timeout-minutes:/.test(text), "CI declares no job timeout");
  check(gate, /concurrency:/.test(text), "CI has no concurrency group, so superseded runs are not cancelled");
  check(gate, /persist-credentials: false/.test(text), "checkout does not disable credential persistence");
  // CI may build directly or delegate to the script; either way the app targets must
  // actually be built, so follow through to the script rather than accepting the
  // mere mention of it.
  if (/scripts\/build-all\.sh/.test(text)) {
    check(gate, exists("scripts/build-all.sh"), "CI calls scripts/build-all.sh, which does not exist");
    if (exists("scripts/build-all.sh")) {
      const script = read("scripts/build-all.sh");
      check(gate, /xcodebuild/.test(script), "build-all.sh never invokes xcodebuild");
      check(gate, /platform=macOS/.test(script), "build-all.sh does not build for macOS");
      check(gate, /platform=iOS Simulator/.test(script), "build-all.sh does not build for iOS");
      check(gate, /SWIFT_TREAT_WARNINGS_AS_ERRORS=YES/.test(script), "build-all.sh does not treat warnings as errors");
      check(gate, /BUILD_ALL_OK/.test(script), "build-all.sh emits no success token");
    }
  } else {
    check(gate, /xcodebuild/.test(text), "CI never builds the app targets, only the package");
  }
  check(gate, /audit-checks\.mjs|gate-check/.test(text), "CI does not run the gate checks");
  check(gate, /swift test/.test(text), "CI does not run the test suite");

  // Every action must be pinned to a 40-character commit SHA.
  const uses = [...text.matchAll(/uses:\s*(\S+)/g)].map((m) => m[1]);
  check(gate, uses.length > 0, "CI uses no actions at all, which is unexpected");
  for (const action of uses) {
    check(gate, /@[0-9a-f]{40}$/.test(action), `action is not pinned to a commit SHA: ${action}`);
  }
  finish("CI_OK");
}

// --- controls --------------------------------------------------------------

/**
 * Proves each absence detector can actually see a violation.
 *
 * An absence check that always passes certifies nothing. These plant a known
 * positive and assert the detector fires, which is the control the gate ledger
 * requires for every negative assertion.
 */
function selfTest() {
  const controls = [
    ["force-unwrap", () => findForceUnwraps('let x = foo!\n').length === 1],
    ["try!", () => findForceUnwraps('try! doThing()\n').length === 1],
    ["force-unwrap negative control", () => findForceUnwraps('if a != b { return !c }\n').length === 0],
    ["preview exclusion", () => findForceUnwraps('#Preview {\n  let x = foo!\n}\n').length === 0],
    ["secret literal", () => findSecretLiterals('let apiKey = "abcdef0123456789xyz"').length === 1],
    ["secret negative control", () => findSecretLiterals('let apiKey = key').length === 0],
    ["fixture leak", () => findFixtureLeaks("let d = WakaDashboard.fixture").length === 1],
    ["fixture negative control", () => findFixtureLeaks("// WakaDashboard.fixture").length === 0]
  ];
  let ok = true;
  for (const [name, run] of controls) {
    const passed = run();
    console.log(`${passed ? "ok  " : "FAIL"} control: ${name}`);
    if (!passed) ok = false;
  }
  if (!ok) process.exit(1);
  console.log("SELF_TEST_OK");
}

// --- dispatch --------------------------------------------------------------

const commands = {
  audit, "no-fixture-leak": noFixtureLeak, legal, compliance,
  accessibility, apple, license, hygiene, ci, "--self-test": selfTest
};

const command = process.argv[2];
if (!command || !commands[command]) {
  console.error(`usage: audit-checks.mjs <${Object.keys(commands).join("|")}>`);
  process.exit(2);
}
commands[command]();
