// Install RealFaviconGenerator (RFG) output over concept-browser's defaults.
// Run AFTER `npx concept-browser build` — restores canonical RFG files
// (kept under assets/favicons/) into public/ and dist/, rewrites
// site.webmanifest with the correct BASE_PATH, removes concept-browser's
// auto-generated PNG/ICO cruft, and patches dist/**/*.html to strip the
// CLI-injected favicon <link> tags and inject our RFG markup.
//
// Mirrors glossarist/iala-vocab/scripts/install-favicons.mjs.

import fs from 'fs';
import path from 'path';

const BASE_PATH = (process.env.BASE_PATH || '/').replace(/\/+$/, '') || '';
const ROOT = process.cwd();
const ASSETS_DIR = path.resolve(ROOT, 'assets', 'favicons');
const PUBLIC_DIR = path.resolve(ROOT, 'public');
const DIST_DIR = path.resolve(ROOT, 'dist');

const p = BASE_PATH;

// RFG-recommended markup with a cache-buster query so updates invalidate
// browser caches without renaming the files.
const VERSION = '20260801';
const FAVICON_HTML = [
  `<link rel="icon" type="image/png" href="${p}/favicon-96x96.png?v=${VERSION}" sizes="96x96" />`,
  `<link rel="icon" type="image/svg+xml" href="${p}/favicon.svg?v=${VERSION}" />`,
  `<link rel="shortcut icon" href="${p}/favicon.ico?v=${VERSION}" />`,
  `<link rel="apple-touch-icon" sizes="180x180" href="${p}/apple-touch-icon.png?v=${VERSION}" />`,
  `<link rel="manifest" href="${p}/site.webmanifest?v=${VERSION}" />`,
].join('\n    ');

const KEEP_FILES = [
  'favicon.svg',
  'favicon-96x96.png',
  'favicon.ico',
  'apple-touch-icon.png',
  'web-app-manifest-192x192.png',
  'web-app-manifest-512x512.png',
];

// concept-browser cruft to delete from public/ and dist/.
const CRUFT_FILES = [
  'apple-touch-icon-57x57.png',
  'apple-touch-icon-60x60.png',
  'apple-touch-icon-72x72.png',
  'apple-touch-icon-76x76.png',
  'apple-touch-icon-114x114.png',
  'apple-touch-icon-120x120.png',
  'apple-touch-icon-144x144.png',
  'apple-touch-icon-152x152.png',
  'apple-touch-icon-167x167.png',
  'apple-touch-icon-180x180.png',
  'apple-touch-icon-1024x1024.png',
  'apple-touch-icon-precomposed.png',
  'favicon-16x16.png',
  'favicon-32x32.png',
  'favicon-48x48.png',
  'browserconfig.xml',
];

function siteWebmanifestContent() {
  return JSON.stringify({
    name: 'CIE e-ILV',
    short_name: 'CIE e-ILV',
    icons: [
      { src: `${p}/web-app-manifest-192x192.png`, sizes: '192x192', type: 'image/png', purpose: 'maskable' },
      { src: `${p}/web-app-manifest-512x512.png`, sizes: '512x512', type: 'image/png', purpose: 'maskable' },
    ],
    theme_color: '#004ebc',
    background_color: '#ffffff',
    display: 'standalone',
    start_url: `${p}/`,
  }, null, 2) + '\n';
}

function rm(targetDir, file) {
  const fp = path.join(targetDir, file);
  if (fs.existsSync(fp)) {
    fs.unlinkSync(fp);
    return true;
  }
  return false;
}

function applyFaviconsToDir(targetDir, label) {
  if (!fs.existsSync(targetDir)) return;
  console.log(`\n=== ${label}: ${targetDir} ===`);

  for (const f of KEEP_FILES) {
    const src = path.join(ASSETS_DIR, f);
    if (!fs.existsSync(src)) {
      console.warn(`  ! missing canonical: ${src}`);
      continue;
    }
    fs.copyFileSync(src, path.join(targetDir, f));
  }

  fs.writeFileSync(path.join(targetDir, 'site.webmanifest'), siteWebmanifestContent());

  for (const f of CRUFT_FILES) {
    if (rm(targetDir, f)) console.log(`  - removed ${f}`);
  }
}

function writeFaviconLinksHtml() {
  fs.writeFileSync(path.join(PUBLIC_DIR, 'favicon-links.html'), FAVICON_HTML + '\n');
  console.log(`\n=== public/favicon-links.html ===\n  wrote RFG markup`);
}

function walkHtml(dir) {
  const out = [];
  if (!fs.existsSync(dir)) return out;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      out.push(...walkHtml(full));
    } else if (entry.name.endsWith('.html')) {
      out.push(full);
    }
  }
  return out;
}

function patchHtmlFiles() {
  const files = walkHtml(DIST_DIR);
  let touched = 0;
  for (const file of files) {
    let html = fs.readFileSync(file, 'utf8');
    const original = html;

    // Strip ALL existing favicon-related <link> tags so we don't duplicate.
    html = html.replace(
      /<link[^>]*\brel=["'](icon|apple-touch-icon|apple-touch-icon-precomposed|manifest|shortcut icon)["'][^>]*>\s*/gi,
      ''
    );

    // Inject our markup right after the opening <head>.
    if (/<head[^>]*>/i.test(html)) {
      html = html.replace(/<head([^>]*)>/i, `<head$1>\n    ${FAVICON_HTML}\n  `);
    }

    if (html !== original) {
      fs.writeFileSync(file, html);
      touched += 1;
    }
  }
  console.log(`\n=== patched ${touched}/${files.length} HTML files with RFG markup ===`);
}

if (!fs.existsSync(ASSETS_DIR)) {
  console.error(`! canonical assets missing: ${ASSETS_DIR}`);
  process.exit(1);
}

console.log(`BASE_PATH = "${p || '/'}"`);
applyFaviconsToDir(PUBLIC_DIR, 'public');
applyFaviconsToDir(DIST_DIR, 'dist');
writeFaviconLinksHtml();
patchHtmlFiles();
console.log('\nFavicons installed.');
