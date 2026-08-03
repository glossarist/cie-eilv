// Post-generate favicon installer.
//
// concept-browser generate emits public/favicon-links.html from
// site-config.yml branding.favicon.icons, but strips query strings
// from hrefs. This script restores the ?v=<version> cache-busting
// suffix and copies canonical favicon files from assets/favicons/
// to public/.
//
// Run after `npm run generate`. Idempotent.

import fs from 'fs';
import path from 'path';

const ROOT = process.cwd();
const SOURCE_DIR = path.join(ROOT, 'assets/favicons');
const PUBLIC_DIR = path.join(ROOT, 'public');
const LINKS_HTML = path.join(PUBLIC_DIR, 'favicon-links.html');

const FAVICON_FILES = [
  'favicon.svg',
  'favicon-96x96.png',
  'favicon.ico',
  'apple-touch-icon.png',
  'web-app-manifest-192x192.png',
  'web-app-manifest-512x512.png',
  'site.webmanifest',
];

// Read basePath + version from site-config.yml. The version is the
// ?v= cache-busting token — bump when favicons change.
function readConfig() {
  const yml = fs.readFileSync(path.join(ROOT, 'site-config.yml'), 'utf-8');
  const baseMatch = yml.match(/^base_path:\s*(\S+)/m);
  const basePath = baseMatch ? baseMatch[1].replace(/['"]/g, '').replace(/\/+$/, '') : '';
  return { basePath };
}

const VERSION = '20260802';
const { basePath } = readConfig();

// Copy canonical favicons to public/.
fs.mkdirSync(PUBLIC_DIR, { recursive: true });
for (const file of FAVICON_FILES) {
  const src = path.join(SOURCE_DIR, file);
  const dst = path.join(PUBLIC_DIR, file);
  if (!fs.existsSync(src)) {
    console.warn(`install-favicons: source missing: ${src}`);
    continue;
  }
  fs.copyFileSync(src, dst);
}

// Rewrite favicon-links.html with cache-busting suffix.
const prefix = basePath ? `${basePath}/` : '/';
const links = [
  { rel: 'icon', type: 'image/png', sizes: '96x96', href: 'favicon-96x96.png' },
  { rel: 'icon', type: 'image/svg+xml', href: 'favicon.svg' },
  { rel: 'shortcut icon', href: 'favicon.ico' },
  { rel: 'apple-touch-icon', sizes: '180x180', href: 'apple-touch-icon.png' },
  { rel: 'manifest', href: 'site.webmanifest' },
];

const html = links
  .map((icon) => {
    const attrs = Object.entries(icon)
      .map(([k, v]) => `${k}="${v}"`)
      .join(' ');
    const href = `${prefix}${icon.href}?v=${VERSION}`;
    return `    <link ${attrs.replace(/href="[^"]*"/, `href="${href}"`)} />`;
  })
  .join('\n') + '\n';

fs.writeFileSync(LINKS_HTML, html);
console.log(`install-favicons: wrote ${LINKS_HTML} with ${links.length} links (v=${VERSION})`);
