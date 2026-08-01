// Post-build font swap: replace concept-browser's hardcoded DM Sans URL and
// font-family declarations with Raleway across every generated HTML and CSS
// asset.
//
// The concept-browser v0.7.87 build pipeline bakes DM Sans / DM Serif Display
// / JetBrains Mono into every static HTML page's <head> AND every CSS rule,
// ignoring the site-config.yml branding.fonts setting. CIE's brand font is
// Raleway (https://fonts.google.com/specimen/Raleway). Until upstream honors
// the config, we swap both the <link> URL and the font-family declarations
// post-build.

import { readdirSync, readFileSync, writeFileSync, existsSync } from "node:fs";
import { join, extname } from "node:path";

const dist = join(process.cwd(), "dist");

if (!existsSync(dist)) {
  console.error("install-fonts: dist/ not found. Run `npm run build` first.");
  process.exit(1);
}

// Raleway weights: 400 (regular), 500 (medium), 600 (semibold), 700 (bold),
// plus italic 400 for emphasis in body copy. JetBrains Mono retained for
// code/mono contexts.
const ralewayUrl =
  "https://fonts.googleapis.com/css2" +
  "?family=Raleway:ital,wght@0,400;0,500;0,600;0,700;1,400" +
  "&family=JetBrains+Mono:wght@400;500&display=swap";

const dmSansUrlPattern =
  /https:\/\/fonts\.googleapis\.com\/css2\?family=DM[^"]+/g;

// Font-family declaration swaps. Serif headers (DM Serif Display) get Raleway
// too — CIE uses Raleway everywhere. Fraunces is a fallback for adoc-rendered
// headings; swap as well for consistency.
const fontFamilySwaps = [
  [/\bDM Sans\b/g, "Raleway"],
  [/\bDM Serif Display\b/g, "Raleway"],
  [/\bFraunces\b/g, "Raleway"],
  [/\bSource Sans 3\b/g, "Raleway"],
  [/\bSource Serif 4\b/g, "Raleway"],
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

function swapText(original) {
  let out = original.replace(dmSansUrlPattern, ralewayUrl);
  for (const [pattern, replacement] of fontFamilySwaps) {
    out = out.replace(pattern, replacement);
  }
  return out;
}

const htmlFiles = walk(dist, (n) => extname(n) === ".html");
const cssFiles = walk(join(dist, "_astro"), (n) => extname(n) === ".css")
  .filter((p) => existsSync(p));

let touched = 0;
for (const path of [...htmlFiles, ...cssFiles]) {
  const original = readFileSync(path, "utf8");
  const swapped = swapText(original);
  if (swapped !== original) {
    writeFileSync(path, swapped);
    touched += 1;
  }
}

console.log(
  `install-fonts: swapped to Raleway in ${touched} file(s) ` +
  `(${htmlFiles.length} HTML, ${cssFiles.length} CSS scanned)`,
);

