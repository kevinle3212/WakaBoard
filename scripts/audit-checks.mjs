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

/** First-party links that confuse the owner's GitHub and LinkedIn handles. */
function findOwnerLinkIssues(text) {
  const issues = [];
  if (/github\.com\/lekevin1(?:\/|\b)/i.test(text)) {
    issues.push("the LinkedIn handle lekevin1 is incorrectly used as a GitHub owner");
  }
  return issues;
}

/** String literals that spell out a percentage instead of using the compact symbol. */
function findSpelledPercentStrings(text) {
  return [...text.matchAll(/"([^"\\]*(?:\\.[^"\\]*)*)"/g)]
    .map((match) => match[1])
    .filter((value) => /\bpercent\b/i.test(value));
}


// --- detectors for the multi-platform and design gates ---------------------

/**
 * Ad-hoc spacing and corner radii in a shipping view.
 *
 * A design system that any view may opt out of is a suggestion, not a system, and
 * two screens whose padding differs by two points is exactly the drift nobody
 * notices until every screen is slightly wrong. A genuine exception — a hit target
 * measured against the live accessibility tree, for instance — is allowed with a
 * `design-exempt:` comment on the same line that says why.
 */
function findDesignLiterals(text) {
  const hits = [];
  text.split("\n").forEach((line, index) => {
    if (line.includes("design-exempt:")) return;
    const stripped = line.replace(/\/\/.*$/, "");
    const padding = /\.padding\(\s*(?:\.\w+\s*,\s*)?-?\d/.test(stripped);
    const radius = /cornerRadius:\s*-?\d/.test(stripped);
    if (padding || radius) hits.push({ line: index + 1, text: stripped.trim() });
  });
  return hits;
}

/** An unguarded `import WidgetKit`, which cannot compile on tvOS. */
function findUnguardedWidgetKitImports(text) {
  const lines = text.split("\n");
  const hits = [];
  lines.forEach((line, index) => {
    if (!/^\s*import WidgetKit\s*$/.test(line)) return;
    const preceding = lines.slice(Math.max(0, index - 3), index).join("\n");
    if (!/#if\s+canImport\(WidgetKit\)/.test(preceding)) hits.push(index + 1);
  });
  return hits;
}

/** Repository files that look like WakaTime artwork rather than WakaBoard's own. */
function findWakaTimeArtwork() {
  const images = [...walk("Apps", [".png", ".jpg", ".jpeg", ".svg", ".pdf"]),
                  ...walk("docs", [".png", ".jpg", ".jpeg", ".svg", ".pdf"]),
                  ...walk("Config", [".png", ".jpg", ".jpeg", ".svg", ".pdf"]),
                  ...walk("Widgets", [".png", ".jpg", ".jpeg", ".svg", ".pdf"])];
  return images.filter((file) => /wakatime/i.test(file));
}

/**
 * Words that stay lowercase inside a title unless they open or close it.
 *
 * Chicago-style title case, which is what "Selected Period" and "Daily Average"
 * already are. Anything not on this list is capitalised.
 */
const TITLE_MINOR_WORDS = new Set([
  "a", "an", "and", "as", "at", "but", "by", "for", "from", "in", "into", "nor",
  "of", "on", "onto", "or", "over", "per", "the", "to", "up", "via", "with", "vs"
]);

/** Tokens that are identifiers or proper nouns and keep whatever case they have. */
const CASING_LITERALS = new Set([
  "WakaTime", "WakaBoard", "API", "iPhone", "iPad", "Mac", "macOS", "iOS", "watchOS",
  "tvOS", "visionOS", "VoiceOver", "7-Day"
]);

/** Whether `value` reads as a Title Cased heading. */
function isTitleCase(value) {
  const words = value.split(/\s+/).filter(Boolean);
  if (words.length === 0) return false;
  return words.every((word, index) => {
    const bare = word.replace(/^[("']+|[)"',.:;?!]+$/g, "");
    if (bare.length === 0) return true;
    if (CASING_LITERALS.has(bare)) return true;
    if (/^\d/.test(bare)) return true;
    if (bare === bare.toUpperCase()) return true;
    // A domain or an identifier keeps whatever case it has: "Open wakatime.com" is
    // correct and "Open Wakatime.Com" is not.
    if (bare.includes(".") && bare === bare.toLowerCase()) return true;
    // Minor words may be either case. Chicago lowercases them, Apple capitalises the
    // particle in "Sign In", and arbitrating between the two houses is not what this
    // check is for — the major words are.
    if (TITLE_MINOR_WORDS.has(bare.toLowerCase())) return true;
    return bare[0] === bare[0].toUpperCase();
  });
}

/**
 * Every string literal that is presented to a user as a title or a heading.
 *
 * Enumerated by the construct that renders it rather than guessed at: a heuristic
 * over every string in the codebase would flag half the log messages and none of
 * the real headings.
 */
const TITLE_CONSTRUCTS = [
  /\.navigationTitle\("([^"\\]+)"\)/g,
  /Section\("([^"\\]+)"\)/g,
  /\.configurationDisplayName\("([^"\\]+)"\)/g,
  /\btitle:\s*"([^"\\]+)"/g,
  /\.tabItem\s*\{\s*Label\("([^"\\]+)"/g
];

function findTitleStrings(text) {
  const hits = [];
  for (const pattern of TITLE_CONSTRUCTS) {
    for (const match of text.matchAll(pattern)) {
      hits.push({ value: match[1], index: match.index });
    }
  }
  return hits;
}

/** Titles that are not Title Cased, or that end in sentence punctuation. */
function findCasingViolations(text) {
  return findTitleStrings(text)
    .filter(({ value }) => !isTitleCase(value) || /[.!?]$/.test(value))
    .map(({ value }) => value);
}

/**
 * Sentences that do not read as sentences.
 *
 * A "sentence" here is any user-facing string of four or more words carrying a
 * terminal full stop — the shape of the explanatory copy this app is full of. It
 * must open with a capital, and it must not be Title Cased, because a Title Cased
 * sentence is the single most common way an interface starts sounding like a
 * brochure.
 */
function findSentenceViolations(text) {
  const hits = [];
  for (const match of text.matchAll(/(\+?\s*)"([A-Za-z][^"\\]{20,}\.)"/g)) {
    // A literal continuing a `+`-concatenated string is half of a sentence, not a
    // sentence: it legitimately starts lower-case and ends mid-thought.
    if (match[1].includes("+")) continue;
    const value = match[2];
    const words = value.replace(/\.$/, "").split(/\s+/).filter(Boolean);
    if (words.length < 4) continue;
    if (value[0] !== value[0].toUpperCase()) { hits.push(value); continue; }
    // Words short enough to be capitalised or not in either style carry no signal,
    // and neither do names that are always capitalised.
    const telling = words.slice(1)
      .map((word) => word.replace(/^[("']+|[)"',.:;?!]+$/g, ""))
      .filter((word) => word.length >= 3 && !CASING_LITERALS.has(word) && /^[A-Za-z]/.test(word));
    if (telling.length < 3) continue;
    if (telling.every((word) => word[0] === word[0].toUpperCase())) hits.push(value);
  }
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

  // The views must actually apply the target-size constant they document. Read
  // across the whole view layer rather than one file: the layer was one 749-line
  // file until the platform shells arrived, and naming that file here is how this
  // check would quietly stop looking at most of the app.
  const views = shippingSwiftFiles().filter((file) => file.startsWith("Sources/WakaUI/"));
  const ui = views.map(read).join("\n");
  const applications = (ui.match(/WakaAccessibility\.minimumTargetSize/g) || []).length;
  check(gate, applications >= 6, `minimumTargetSize applied only ${applications} times in the view layer`);
  const components = read("Sources/WakaUI/WakaComponents.swift");
  check(gate, /minWidth:\s*WakaAccessibility\.minimumTargetSize/.test(components),
    "segmented-control labels can expose a target narrower than 44 points");
  const liveAudit = read("scripts/ax-audit.swift");
  check(gate, /var visited = \["Overview"\]/.test(liveAudit),
    "the live audit does not inspect the shell's initial Overview destination");
  check(gate, /if visited\.count < screens\.count[\s\S]*?exit\(1\)/.test(liveAudit),
    "the live audit can pass without reaching every destination");
  check(gate, /accessibilityReduceMotion/.test(ui), "Reduce Motion is not honored in the view layer");
  // Every chart carries a text alternative, on every platform.
  check(gate, /accessibilityLabel/.test(read("Sources/WakaUI/WakaCharts.swift")),
    "the charts carry no accessibility labels");
  check(gate, findSpelledPercentStrings(read("Sources/WakaUI/WakaAccessibility.swift")).length === 0,
    "an accessibility label spells out percent instead of using %");
  finish("ACCESSIBILITY_OK");
}

/**
 * Reads a PNG's IHDR: its pixel dimensions and whether it carries an alpha
 * channel. Colour types 4 and 6 are the two that include alpha.
 *
 * Enough of the format to police the icon set without adding a dependency to a
 * repository whose whole point is that it ships nothing it does not need.
 */
function pngHeader(relativePath) {
  const bytes = readFileSync(join(ROOT, relativePath));
  const signature = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  if (bytes.length < 26 || !bytes.subarray(0, 8).equals(signature)) return null;
  const colourType = bytes[25];
  return {
    width: bytes.readUInt32BE(16),
    height: bytes.readUInt32BE(20),
    hasAlpha: colourType === 4 || colourType === 6
  };
}

/**
 * The app icon must exist, be complete, and stay the shape each platform
 * requires. Xcode does not fail a build for a missing or malformed icon — it
 * ships an app with a blank tile and the rejection arrives from App Review
 * instead, which is far too late to be a useful signal.
 */
function appIcon(gate) {
  const set = "Apps/WakaBoardApp/Assets.xcassets/AppIcon.appiconset";
  if (!check(gate, exists(`${set}/Contents.json`), `${set}/Contents.json is missing`)) return;

  const images = JSON.parse(read(`${set}/Contents.json`)).images ?? [];
  check(gate, images.length >= 11,
    `AppIcon declares ${images.length} images; expected the iOS entry plus ten macOS entries`);

  for (const image of images) {
    const file = `${set}/${image.filename}`;
    if (!check(gate, exists(file), `AppIcon declares ${image.filename}, which does not exist`)) continue;

    const header = pngHeader(file);
    if (!check(gate, header !== null, `${image.filename} is not a readable PNG`)) continue;

    const points = Number(image.size.split("x")[0]);
    const expected = points * Number((image.scale ?? "1x").replace("x", ""));
    check(gate, header.width === expected && header.height === expected,
      `${image.filename} is ${header.width}x${header.height}; the catalog declares ${expected}x${expected}`);

    // App Store Connect rejects an iOS marketing icon that carries alpha; the
    // macOS entries require it, since the icon supplies its own silhouette.
    if (image.idiom === "mac") {
      check(gate, header.hasAlpha, `${image.filename} has no alpha channel, so its corners cannot be transparent`);
    } else {
      check(gate, !header.hasAlpha, `${image.filename} carries an alpha channel, which App Store Connect rejects`);
    }
  }

  // An asset catalog that no target names is compiled and then ignored.
  const project = read("project.yml");
  const wired = (project.match(/ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon/g) ?? []).length;
  // Four, not five: tvOS wants a layered Brand Assets stack rather than a flat
  // image, and `TODO.md` carries that as real unbuilt work rather than a wired
  // setting pointing at an icon set tvOS cannot use.
  check(gate, wired === 4,
    `project.yml names the app icon in ${wired} target(s); the iOS, macOS, watchOS, and visionOS app targets each need it`);
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
  appIcon(gate);
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
  check(gate, /^env:\s*\n\s*DEVELOPER_DIR:\s*\/Applications\/Xcode_26\.3\.app\/Contents\/Developer/m.test(text),
    "CI does not select the installed Swift 6.2-compatible Xcode 26.3 toolchain");
  check(gate, /name: Verify the acceptance ledger[\s\S]*?fetch-depth:\s*0/.test(text),
    "the acceptance-ledger job uses a shallow checkout and cannot verify historical audit anchors");
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
      // Every platform with an app target must actually be built. A target added to
      // `project.yml` and forgotten here compiles for nobody until someone opens it
      // in Xcode.
      for (const sdk of ["watchos", "appletvos", "xros"]) {
        check(gate, script.includes(sdk), `build-all.sh does not build for ${sdk}`);
      }
      check(gate, /SWIFT_TREAT_WARNINGS_AS_ERRORS=YES/.test(script), "build-all.sh does not treat warnings as errors");
      check(gate, /BUILD_ALL_OK/.test(script), "build-all.sh emits no success token");
    }
  } else {
    check(gate, /xcodebuild/.test(text), "CI never builds the app targets, only the package");
  }
  check(gate, /audit-checks\.mjs|gate-check/.test(text), "CI does not run the gate checks");
  check(gate, /swift test/.test(text), "CI does not run the test suite");
  // Every gate this script can run must be run. A gate that exists and is never
  // invoked is a check nobody performs, which is worse than no check at all because
  // it reads as coverage.
  for (const name of Object.keys(commands)) {
    if (name.startsWith("--")) continue;
    check(gate, new RegExp(`audit-checks\\.mjs ${name}(\\s|$)`, "m").test(text),
      `CI never runs the ${name} gate`);
  }
  check(gate, /snapshot-check\.sh/.test(text), "CI does not render the screens");

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

// --- gates added for WakaTime credit, every platform, and the design pass ---

/** Files whose copy is read by a user and therefore governed by the casing rule. */
function userFacingSwiftFiles() {
  return shippingSwiftFiles();
}

/**
 * WakaTime is credited everywhere its data is shown, not only in a licence file.
 *
 * The ethical bar and the legal one are different: the licence covers redistribution
 * of code, and this covers telling a person which service measured the number they
 * are looking at. A reader who lands on one screen should be able to tell without
 * opening Settings.
 */
function attribution() {
  const gate = "H1";
  if (!check(gate, exists("ATTRIBUTION.md"), "ATTRIBUTION.md is missing")) return finish("ATTRIBUTION_OK");
  const doc = read("ATTRIBUTION.md");
  for (const phrase of [
    "https://wakatime.com",
    "not affiliated with",
    "wakatime.com/legal/logos-and-trademark-usage",
    "wakatime.com/terms",
    CONTACT
  ]) {
    check(gate, doc.includes(phrase), `ATTRIBUTION.md does not mention ${phrase}`);
  }
  check(gate, /\*\*Effective date:\*\*/.test(doc), "ATTRIBUTION.md has no effective date");
  for (const placeholder of PLACEHOLDERS) {
    check(gate, !doc.includes(placeholder), `ATTRIBUTION.md still contains the placeholder "${placeholder}"`);
  }
  // Every endpoint the client actually reads has to be listed, or the document is
  // describing a different app than the one that ships.
  const client = read("Sources/WakaCore/Networking.swift");
  for (const path of [...client.matchAll(/"(\/api\/v1\/users\/current[^"\\]*)"/g)].map((m) => m[1])) {
    const endpoint = path.replace(/\/\\\(.*$/, "");
    check(gate, doc.includes(endpoint), `ATTRIBUTION.md does not list the endpoint ${endpoint}`);
  }

  check(gate, /ATTRIBUTION\.md/.test(read("README.md")), "README.md does not link ATTRIBUTION.md");
  check(gate, /ATTRIBUTION\.md/.test(read("NOTICE")), "NOTICE does not point at ATTRIBUTION.md");

  // The credit has to be in the product, not only in the repository.
  const components = read("Sources/WakaUI/WakaComponents.swift");
  check(gate, /provided by WakaTime/i.test(components),
    "no shipping view states that the data is provided by WakaTime");
  const settings = read("Sources/WakaUI/WakaScreens.swift");
  check(gate, /LegalLink\(title: "Attribution and Credit", file: "ATTRIBUTION"\)/.test(settings),
    "Settings does not link the attribution document");
  check(gate, (settings.match(/WakaTimeCredit\(/g) ?? []).length >= 4,
    "the WakaTime credit does not appear on enough screens");
  const readme = read("README.md");
  check(gate, readme.includes("https://github.com/kevinle3212"),
    "README.md does not credit Kevin's canonical GitHub profile");
  check(gate, readme.includes("https://www.linkedin.com/in/lekevin1"),
    "README.md does not credit Kevin's canonical LinkedIn profile");
  check(gate, components.includes("https://github.com/kevinle3212/WakaBoard"),
    "legal links do not resolve to the canonical public repository");
  check(gate, settings.includes("https://github.com/kevinle3212")
    && settings.includes("https://www.linkedin.com/in/lekevin1"),
    "the app's About section does not credit both canonical owner profiles");
  for (const file of ["README.md", "Sources/WakaUI/WakaComponents.swift", "Sources/WakaUI/WakaScreens.swift"]) {
    for (const issue of findOwnerLinkIssues(read(file))) fail(gate, `${file}: ${issue}`);
  }
  const widgets = read("Widgets/WakaBoardWidgets/WakaBoardWidgets.swift");
  check(gate, (widgets.match(/WakaTime/g) ?? []).length >= 3,
    "the widgets do not credit WakaTime");
  finish("ATTRIBUTION_OK");
}

/**
 * WakaBoard's use of the WakaTime name stays inside WakaTime's published policy.
 *
 * The policy permits the name in a description and as a link, and forbids the
 * artwork outright. The only way to keep the second half true over time is to fail
 * the build when a WakaTime image is added.
 */
function trademark() {
  const gate = "H2";
  const artwork = findWakaTimeArtwork();
  check(gate, artwork.length === 0,
    `these files look like WakaTime artwork, which the policy does not permit: ${artwork.join(", ")}`);

  // Markdown wraps the quoted policy across lines, so compare on collapsed
  // whitespace rather than on the file's own line breaks.
  const doc = read("ATTRIBUTION.md").replace(/^>\s?/gm, "").replace(/\s+/g, " ");
  check(gate, /Retrieved \d+ \w+ \d{4}/.test(doc),
    "ATTRIBUTION.md quotes the trademark policy without a retrieval date");
  check(gate, /duplicates functionality found in an existing WakaTime software/.test(doc),
    "ATTRIBUTION.md does not quote the clause that actually puts this project at risk");
  check(gate, /honest caveat|The honest caveat/i.test(doc),
    "ATTRIBUTION.md does not state the naming risk plainly");

  for (const file of ["NOTICE", "README.md", "ATTRIBUTION.md", "TERMS.md"]) {
    check(gate, /not affiliated with/i.test(read(file)), `${file} does not disclaim affiliation`);
  }
  finish("TRADEMARK_OK");
}

/** The platform set declared in `Package.swift` and in `project.yml`. */
const EXPECTED_PLATFORMS = ["macOS", "iOS", "watchOS", "tvOS", "visionOS"];

/**
 * Every platform is declared in both build systems and shaped for its own hardware.
 *
 * A platform added to one file and forgotten in the other is invisible until
 * somebody tries to build it, and the two shells that must not be a shrunk copy of
 * the desktop one are the two nobody tests by hand.
 */
function platforms() {
  const gate = "H4";
  const manifest = read("Package.swift");
  const project = read("project.yml");

  for (const platform of EXPECTED_PLATFORMS) {
    check(gate, new RegExp(`\\.${platform.replace(/^./, (c) => c.toLowerCase())}\\(`).test(manifest),
      `Package.swift does not declare ${platform}`);
    check(gate, new RegExp(`^\\s{4}${platform}: "`, "m").test(project),
      `project.yml declares no deployment target for ${platform}`);
    check(gate, project.includes(`WakaBoardApp_${platform}:`),
      `project.yml has no application target for ${platform}`);
    check(gate, project.includes(`WakaCore_${platform}:`) && project.includes(`WakaUI_${platform}:`),
      `project.yml is missing a library target for ${platform}`);
  }

  // tvOS has no WidgetKit at all, so a tvOS widget target would never build.
  check(gate, !project.includes("WakaBoardWidgets_tvOS"),
    "project.yml declares a tvOS widget extension, but tvOS ships no WidgetKit");
  for (const platform of ["iOS", "macOS", "watchOS", "visionOS"]) {
    check(gate, project.includes(`WakaBoardWidgets_${platform}:`),
      `project.yml has no widget extension for ${platform}`);
  }

  // …which is only possible if the shared model never imports WidgetKit unguarded.
  for (const file of shippingSwiftFiles()) {
    if (file.startsWith("Widgets/")) continue;
    for (const line of findUnguardedWidgetKitImports(read(file))) {
      fail(gate, `${file}:${line} imports WidgetKit without a canImport guard, so tvOS cannot compile`);
    }
  }

  // The watch and the television get shells of their own.
  const shell = read("Sources/WakaUI/WakaShell.swift");
  check(gate, /#if !os\(watchOS\) && !os\(tvOS\)/.test(shell),
    "the split-view shell is not excluded from watchOS and tvOS");
  check(gate, /#if os\(watchOS\)/.test(shell) && /struct WatchShell/.test(shell),
    "there is no watchOS-specific shell");
  check(gate, /#if os\(tvOS\)/.test(shell) && /struct TelevisionShell/.test(shell),
    "there is no tvOS-specific shell");
  // A television has no pull-to-refresh gesture; the button must be reachable instead.
  const screens = read("Sources/WakaUI/WakaScreens.swift");
  check(gate, /#if !os\(tvOS\)\s*\n\s*\.refreshable/.test(screens),
    "refreshable is not excluded on tvOS, which has no pull gesture");
  check(gate, /RefreshToolbarItem/.test(screens), "no explicit Refresh control exists");

  check(gate, exists("Config/WakaBoard-Watch-Info.plist"), "the watchOS app has no Info.plist");
  check(gate, /WKApplication/.test(read("Config/WakaBoard-Watch-Info.plist")),
    "the watchOS Info.plist does not declare WKApplication");
  finish("PLATFORMS_OK");
}

/**
 * The design tokens are used, and no view invents its own spacing.
 *
 * Also the home of the responsive-layout fixes, which were written once, left
 * uncommitted in a side worktree, and would otherwise be lost a second time.
 */
function design() {
  const gate = "H9";
  if (!check(gate, exists("Sources/WakaUI/WakaDesign.swift"), "the design token file is missing")) {
    return finish("DESIGN_OK");
  }
  const tokens = read("Sources/WakaUI/WakaDesign.swift");
  for (const token of ["enum Spacing", "enum Radius", "enum Palette", "wakaCard", "densityStep"]) {
    check(gate, tokens.includes(token), `the token file declares no ${token}`);
  }
  // The palette must be a recorded, validated selection rather than a guess.
  check(gate, /validate_palette\.js/.test(tokens),
    "the palette does not record the validator it was checked with");
  check(gate, /categoricalDark/.test(tokens) && /categoricalLight/.test(tokens),
    "the palette has no separate dark selection");

  for (const file of shippingSwiftFiles()) {
    if (file.endsWith("WakaDesign.swift")) continue;
    for (const hit of findDesignLiterals(read(file))) {
      fail(gate, `${file}:${hit.line} uses an ad-hoc spacing or radius: ${hit.text}`);
    }
  }

  // The responsive fixes, each one a defect that was found on a real device.
  const components = read("Sources/WakaUI/WakaComponents.swift");
  check(gate, /minimumScaleFactor/.test(components), "MetricCard can still truncate a long value");
  check(gate, /layoutPriority\(1\)/.test(components), "a long row name can still squeeze out its duration");
  const charts = read("Sources/WakaUI/WakaCharts.swift");
  check(gate, /desiredCount: 4/.test(charts), "chart axes are unbounded and will overlap at 90 days");
  const shell = read("Sources/WakaUI/WakaShell.swift");
  check(gate, /navigationSplitViewColumnWidth/.test(shell), "the macOS sidebar width is unbounded");
  check(gate, /minWidth: 640/.test(shell), "the macOS window has no minimum size");
  check(gate, /windowResizability/.test(read("Apps/WakaBoardApp/WakaBoardApp.swift")),
    "the macOS window can be resized below its content");
  const screens = read("Sources/WakaUI/WakaScreens.swift");
  const settings = screens.slice(screens.indexOf("struct WakaSettingsView"), screens.indexOf("// MARK: - Shared scaffolding"));
  check(gate, !/\bForm\s*\{/.test(settings),
    "Settings still uses platform Form columns that detach headings from their content on macOS");
  check(gate, /SettingsSection\(/.test(settings),
    "Settings does not use the app's grouped vertical section composition");
  finish("DESIGN_OK");
}

/**
 * The detailed Breakdown surface must stay bounded as a selected period grows.
 *
 * API response bounds permit many buckets. Charts deliberately fold their tail, and
 * the list must keep its own tail virtualized rather than eagerly constructing every
 * row before the user can scroll to it. The source-level assertion complements the
 * render snapshots, which use representative data rather than a production-size list.
 */
function findBreakdownPerformanceIssues(text) {
  const breakdown = text.slice(text.indexOf("struct WakaBreakdownView"), text.indexOf("// MARK: - Insights"));
  const issues = [];
  if (!breakdown.includes("LazyVStack(alignment: .leading")) {
    issues.push("the Breakdown detail list eagerly constructs every row");
  }
  const rankingCalls = breakdown.match(/model\.ranked\(model\.selectedDimension\)/g) ?? [];
  if (rankingCalls.length !== 1) {
    issues.push(`the Breakdown render recalculates its ranking ${rankingCalls.length} times instead of once`);
  }
  if (!breakdown.includes("AnalyticsEngine.topBuckets(usage)")) {
    issues.push("the Breakdown charts do not reuse the already-ranked data");
  }
  return issues;
}

function performance() {
  const gate = "H20";
  for (const issue of findBreakdownPerformanceIssues(read("Sources/WakaUI/WakaScreens.swift"))) {
    fail(gate, issue);
  }
  finish("PERFORMANCE_OK");
}

/**
 * Every chart is framed, titled, and readable without seeing it.
 *
 * A `Chart` with no text alternative is invisible to VoiceOver, and three of the
 * palette's light-mode hues fall below 3:1 against white — which the method permits
 * only where the figures are also written down. Both obligations are discharged by
 * the same wrapper, so the check is that no chart escapes it.
 */
function charts() {
  const gate = "H14";
  const file = "Sources/WakaUI/WakaCharts.swift";
  if (!check(gate, exists(file), "the charts file is missing")) return finish("CHARTS_OK");
  const text = read(file);

  // Count the framed figures, not the `Chart(` calls: the activity ribbon is a
  // plain grid rather than a Swift Charts plot, because Swift Charts draws a
  // one-column heatmap as hairlines. It is still a figure and still framed.
  const figures = (text.match(/ChartFrame\(/g) ?? []).length;
  check(gate, figures >= 9, `expected at least 9 framed figures, found ${figures}`);
  check(gate, /struct ChartFrame/.test(text), "there is no shared chart frame");
  check(gate, /\.accessibilityLabel\("\\\(title\)\. \\\(summary\)"\)/.test(text),
    "the chart frame does not carry the chart's content as text");
  check(gate, /Text\(summary\)/.test(text),
    "the chart frame does not print the summary, which is what the light-mode palette requires");

  for (const name of [
    "ActivityChart", "ShareChart", "ComparisonChart", "CumulativeChart",
    "WeekdayChart", "ActivityRibbon", "ActivityBalanceChart", "WeeklyTotalsChart",
    "DailyTrendChart"
  ]) {
    check(gate, new RegExp(`struct ${name}: View`).test(text), `${name} is missing`);
  }
  const comparisonChart = text.match(/public struct ComparisonChart: View \{([\s\S]*?)\n\}\n\n\/\/ MARK: - Cumulative/)?.[1] ?? "";
  check(gate, /\.chartYAxis\s*\{/.test(comparisonChart),
    "ComparisonChart leaves category-label placement to a resizing-sensitive default");
  check(gate, /AxisMarks\(position:\s*\.leading\)/.test(comparisonChart) && /AxisValueLabel\s*\{/.test(comparisonChart),
    "ComparisonChart category labels are not reserved on the leading axis");
  const shareChart = text.match(/public struct ShareChart: View \{([\s\S]*?)\n\}\n\n\/\/ MARK: - Comparison/)?.[1] ?? "";
  check(gate, /\.chartOverlay\s*\{/.test(shareChart),
    "ShareChart does not position its total through the chart plot geometry");
  check(gate, /proxy\.plotFrame/.test(shareChart),
    "ShareChart centers its total on the chart-plus-legend frame instead of the donut plot frame");
  // Every chart type must define its own text alternative.
  for (const [, body] of text.matchAll(/struct (\w+): View \{([\s\S]*?)\n\}/g)) {
    if (!body.includes("Chart(") && !body.includes("ChartFrame(")) continue;
    check(gate, /private var summary: String/.test(body) || /let summary/.test(body),
      "a chart view defines no summary");
  }

  // A chart outside this file has escaped the frame that guarantees all of the above.
  for (const other of shippingSwiftFiles()) {
    if (other === file) continue;
    check(gate, !/\bChart\(/.test(read(other)),
      `${other} draws a chart outside the shared chart frame`);
  }
  finish("CHARTS_OK");
}

/**
 * Titles are Title Cased and sentences are sentences.
 *
 * Mechanical because a manual sweep of a hundred strings is right once and wrong
 * again on the next change.
 */
function casing() {
  const gate = "H18";
  for (const file of userFacingSwiftFiles()) {
    const text = read(file);
    for (const value of findCasingViolations(text)) {
      fail(gate, `${file} has the title "${value}", which is not Title Case`);
    }
    for (const value of findSentenceViolations(text)) {
      fail(gate, `${file} has the sentence "${value}", which does not read as a sentence`);
    }
  }
  // The two headings the owner named explicitly, as a canary on the sweep itself.
  const screens = read("Sources/WakaUI/WakaScreens.swift");
  for (const heading of ["Selected Period", "Daily Average", "Top Project", "Top Language"]) {
    check(gate, screens.includes(`"${heading}"`), `the dashboard no longer uses the heading "${heading}"`);
  }
  finish("CASING_OK");
}

function selfTest() {
  const controls = [
    ["force-unwrap", () => findForceUnwraps('let x = foo!\n').length === 1],
    ["try!", () => findForceUnwraps('try! doThing()\n').length === 1],
    ["force-unwrap negative control", () => findForceUnwraps('if a != b { return !c }\n').length === 0],
    ["preview exclusion", () => findForceUnwraps('#Preview {\n  let x = foo!\n}\n').length === 0],
    ["secret literal", () => findSecretLiterals('let apiKey = "abcdef0123456789xyz"').length === 1],
    ["secret negative control", () => findSecretLiterals('let apiKey = key').length === 0],
    ["fixture leak", () => findFixtureLeaks("let d = WakaDashboard.fixture").length === 1],
    ["fixture negative control", () => findFixtureLeaks("// WakaDashboard.fixture").length === 0],
    ["owner links accept distinct canonical profiles", () => findOwnerLinkIssues(
      "https://github.com/kevinle3212 https://www.linkedin.com/in/lekevin1"
    ).length === 0],
    ["owner links reject a LinkedIn handle as GitHub owner", () => findOwnerLinkIssues(
      "https://github.com/lekevin1/WakaBoard"
    ).length === 1],
    ["compact percentage accepts symbol", () => findSpelledPercentStrings('"42% of the selected period"').length === 0],
    ["compact percentage rejects word", () => findSpelledPercentStrings('"42 percent of the selected period"').length === 1],
    ["png alpha", () => pngHeader("Apps/WakaBoardApp/Assets.xcassets/AppIcon.appiconset/icon-mac-512x512@2x.png")?.hasAlpha === true],
    ["png alpha negative control", () => pngHeader("Apps/WakaBoardApp/Assets.xcassets/AppIcon.appiconset/icon-ios-1024.png")?.hasAlpha === false],
    ["png dimensions", () => pngHeader("Apps/WakaBoardApp/Assets.xcassets/AppIcon.appiconset/icon-ios-1024.png")?.width === 1024],
    ["design literal", () => findDesignLiterals(".padding(11)\n").length === 1],
    ["design literal negative control", () => findDesignLiterals(".padding(WakaDesign.Spacing.tight)\n").length === 0],
    ["design-exempt escape", () => findDesignLiterals(".padding(.vertical, 14) // design-exempt: measured hit target\n").length === 0],
    ["settings layout accepts grouped sections", () => {
      const source = "struct WakaSettingsView { SettingsSection(title: \"Account\") {} }\n// MARK: - Shared scaffolding";
      const body = source.slice(source.indexOf("struct WakaSettingsView"), source.indexOf("// MARK: - Shared scaffolding"));
      return !/\bForm\s*\{/.test(body) && /SettingsSection\(/.test(body);
    }],
    ["settings layout rejects platform form columns", () => {
      const source = "struct WakaSettingsView { Form { Section(\"Account\") {} } }\n// MARK: - Shared scaffolding";
      const body = source.slice(source.indexOf("struct WakaSettingsView"), source.indexOf("// MARK: - Shared scaffolding"));
      return /\bForm\s*\{/.test(body) && !/SettingsSection\(/.test(body);
    }],
    ["unguarded WidgetKit", () => findUnguardedWidgetKitImports("import Foundation\nimport WidgetKit\n").length === 1],
    ["guarded WidgetKit negative control", () => findUnguardedWidgetKitImports("#if canImport(WidgetKit)\nimport WidgetKit\n#endif\n").length === 0],
    ["title case", () => isTitleCase("Selected Period") && isTitleCase("Daily Average") && isTitleCase("Top Project")],
    ["title case minor words", () => isTitleCase("Where to Find Your Key") && isTitleCase("Terms of Service")],
    ["title case rejects sentence case", () => !isTitleCase("Selected period")],
    ["casing violation", () => findCasingViolations('.navigationTitle("Daily average")').length === 1],
    ["casing negative control", () => findCasingViolations('.navigationTitle("Daily Average")').length === 0],
    ["casing rejects a full stop in a title", () => findCasingViolations('Section("Data Source.")').length === 1],
    ["sentence violation", () => findSentenceViolations('"Usage Time Is Not A Measure Of Proficiency."').length === 1],
    ["sentence negative control", () => findSentenceViolations('"Usage time is not a measure of proficiency."').length === 0],
    ["performance accepts a virtualized single ranking", () => findBreakdownPerformanceIssues(
      "struct WakaBreakdownView { let usage = model.ranked(model.selectedDimension); AnalyticsEngine.topBuckets(usage); LazyVStack(alignment: .leading) {} }\n// MARK: - Insights"
    ).length === 0],
    ["performance detects eager duplicate ranking", () => findBreakdownPerformanceIssues(
      "struct WakaBreakdownView { let a = model.ranked(model.selectedDimension); let b = model.ranked(model.selectedDimension) }\n// MARK: - Insights"
    ).length === 3],
    ["chart centering accepts plot-frame geometry", () => {
      const source = "public struct ShareChart: View {\n  Chart([]) {}.chartOverlay { proxy in if let frame = proxy.plotFrame {} }\n}\n\n// MARK: - Comparison";
      const body = source.match(/public struct ShareChart: View \{([\s\S]*?)\n\}\n\n\/\/ MARK: - Comparison/)?.[1] ?? "";
      return /\.chartOverlay\s*\{/.test(body) && /proxy\.plotFrame/.test(body);
    }],
    ["chart centering rejects chart-wide overlay", () => {
      const source = "public struct ShareChart: View {\n  Chart([]) {}.overlay { Text(\"Total\") }\n}\n\n// MARK: - Comparison";
      const body = source.match(/public struct ShareChart: View \{([\s\S]*?)\n\}\n\n\/\/ MARK: - Comparison/)?.[1] ?? "";
      return !/\.chartOverlay\s*\{/.test(body) && !/proxy\.plotFrame/.test(body);
    }],
    ["comparison labels accept a reserved leading axis", () => {
      const source = "public struct ComparisonChart: View {\n  Chart([]) {}.chartYAxis { AxisMarks(position: .leading) { AxisValueLabel { Text(\"Name\") } } }\n}\n\n// MARK: - Cumulative";
      const body = source.match(/public struct ComparisonChart: View \{([\s\S]*?)\n\}\n\n\/\/ MARK: - Cumulative/)?.[1] ?? "";
      return /\.chartYAxis\s*\{/.test(body) && /AxisMarks\(position:\s*\.leading\)/.test(body) && /AxisValueLabel\s*\{/.test(body);
    }],
    ["comparison labels reject default axis placement", () => {
      const source = "public struct ComparisonChart: View {\n  Chart([]) {}\n}\n\n// MARK: - Cumulative";
      const body = source.match(/public struct ComparisonChart: View \{([\s\S]*?)\n\}\n\n\/\/ MARK: - Cumulative/)?.[1] ?? "";
      return !/\.chartYAxis\s*\{/.test(body) && !/AxisValueLabel\s*\{/.test(body);
    }],
    ["artwork detector negative control", () => findWakaTimeArtwork().length === 0]
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
  accessibility, apple, license, hygiene, ci,
  attribution, trademark, platforms, design, charts, casing,
  performance,
  "--self-test": selfTest
};

const command = process.argv[2];
if (!command || !commands[command]) {
  console.error(`usage: audit-checks.mjs <${Object.keys(commands).join("|")}>`);
  process.exit(2);
}
commands[command]();
