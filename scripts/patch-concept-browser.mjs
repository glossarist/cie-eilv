// Apply local patches over installed npm packages.
//
// The published @glossarist/concept-browser@0.7.87 was republished with a
// use-concept-edges.ts that imports GenericHyperedge — a symbol the pinned
// glossarist@0.4.26 does not export. The same was true at glossarist/iala-vocab;
// their working tree has a patched copy that uses an adapter pattern instead.
//
// This script applies that patch from patches/use-concept-edges.ts over the
// installed file. Run after `npm install`.

import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = join(__dirname, "..");
const target = join(root, "node_modules/@glossarist/concept-browser/src/composables/use-concept-edges.ts");
const source = join(root, "patches/use-concept-edges.ts");

if (!existsSync(source)) {
  console.error(`patch-concept-browser: source patch not found: ${source}`);
  process.exit(1);
}
if (!existsSync(target)) {
  console.error(`patch-concept-browser: target not installed: ${target}`);
  console.error("Run `npm install` first.");
  process.exit(1);
}

const patch = readFileSync(source, "utf8");
writeFileSync(target, patch);
console.log(`patch-concept-browser: applied ${source} → ${target}`);
