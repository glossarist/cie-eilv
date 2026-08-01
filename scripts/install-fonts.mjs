// Partial workaround for glossarist/concept-browser#166.
//
// The 0.7.102 build-time fix for branding.fonts (commit 5ab04a92) correctly
// derives the Google Fonts URL from siteConfig, BUT its <style is:global>
// block uses JS template-literal syntax (${fontHeader} / ${fontBody}) which
// Astro does not interpolate inside <style> tags. The literal text ends up
// in the compiled CSS, the :root override silently fails, and the page
// still renders DM Sans.
//
// This script post-processes dist/ to substitute the broken literals with
// the configured family and to rewrite component-scoped font-family rules
// that bypass --font-body / --font-header.
//
// Delete this script once concept-browser#166 is fixed and released.

import { readdirSync, readFileSync, writeFileSync, existsSync } from "node:fs";
import { join, extname } from "node:path";

const dist = join(process.cwd(), "dist");

if (!existsSync(dist)) {
  console.error("install-fonts: dist/ not found. Run `npm run build` first.");
  process.exit(1);
}

const raleway = "Raleway";

// Substitution table.
// 1. The broken literal "${fontHeader}" / "${fontBody}" emitted by
//    Default.astro's <style is:global> block — replace with the family.
// 2. Component-scoped font-family declarations that bypass the variables.
const textSwaps = [
  [/--font-header:\s*\$\{fontHeader[^;}]*;?/g, `--font-header: '${raleway}', Georgia, serif;`],
  [/--font-body:\s*\$\{fontBody[^;}]*;?/g, `--font-body: '${raleway}', system-ui, sans-serif;`],
  [/\bDM Sans\b/g, raleway],
  [/\bDM Serif Display\b/g, raleway],
  [/\bFraunces\b/g, raleway],
  [/\bSource Sans 3\b/g, raleway],
  [/\bSource Serif 4\b/g, raleway],
];

function walk(dir, predicate) {
  const out = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) {
      out.push(...walk(full, predicate));
    } else if (predicate(entry.name)) {
      out.push(full);
    }
  }
  return out;
}

function applySwaps(original) {
  let out = original;
  for (const [pattern, replacement] of textSwaps) {
    out = out.replace(pattern, replacement);
  }
  return out;
}

const targets = [
  ...walk(dist, (n) => extname(n) === ".html"),
  ...walk(join(dist, "_astro"), (n) => extname(n) === ".css"),
];

let touched = 0;
for (const path of targets) {
  const original = readFileSync(path, "utf8");
  const swapped = applySwaps(original);
  if (swapped !== original) {
    writeFileSync(path, swapped);
    touched += 1;
  }
}

console.log(`install-fonts: applied Raleway substitution in ${touched}/${targets.length} file(s)`);
