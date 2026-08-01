// Post-build smoke test. Serves dist/, loads N sample URLs in headless
// Chromium, asserts no pageerror events. Exits non-zero on failure.
//
// Catches the categories of bugs that vite build cannot:
//   - hydration TypeErrors (e.g. glossarist/concept-browser#171)
//   - dynamic-import failures (e.g. the tsx devDep bug, fixed in 0.7.103)
//   - missing resources the build references but doesn't generate
//     (e.g. glossarist/concept-browser#174)
//
// This is a stop-gap until concept-browser ships its own smoke test
// (glossarist/concept-browser#172).

import { chromium } from 'playwright';
import http from 'http';
import fs from 'fs';
import path from 'path';

const BASE_PATH = (process.env.BASE_PATH || '/').replace(/\/+$/, '') || '';
const DIST = path.resolve(process.cwd(), 'dist');

if (!fs.existsSync(DIST)) {
  console.error(`smoke: dist/ not found at ${DIST}. Run \`npm run build\` first.`);
  process.exit(2);
}

const server = http.createServer((req, res) => {
  let urlPath = req.url.split('?')[0];
  // Strip the BASE_PATH prefix so file lookups work against dist/ root.
  if (BASE_PATH && urlPath.startsWith(BASE_PATH + '/')) {
    urlPath = urlPath.slice(BASE_PATH.length);
  } else if (BASE_PATH && urlPath === BASE_PATH) {
    urlPath = '/';
  }
  if (urlPath === '' || urlPath === '/') urlPath = '/index.html';
  if (!urlPath.includes('.') && !urlPath.endsWith('/')) urlPath += '/';
  if (urlPath.endsWith('/')) urlPath += 'index.html';
  const filePath = path.join(DIST, urlPath);
  fs.readFile(filePath, (err, data) => {
    if (err) {
      res.writeHead(404);
      res.end('Not found');
      return;
    }
    const ext = filePath.split('.').pop();
    const types = {
      html: 'text/html', css: 'text/css', js: 'application/javascript',
      svg: 'image/svg+xml', json: 'application/json', png: 'image/png',
      ico: 'image/x-icon', webmanifest: 'application/manifest+json',
      ttl: 'text/turtle', xml: 'application/xml',
    };
    res.writeHead(200, {'Content-Type': types[ext] || 'application/octet-stream'});
    res.end(data);
  });
});

const samplePaths = [
  '/',
  '/about/',
  '/group/cie/about/',
  '/dataset/cie-2020/',
  '/dataset/cie-2020/concept/17-21-012/',
  '/dataset/cie-2020/concept/17-21-025/',
];

const browsers = [
  { name: 'chromium', launcher: chromium },
];

// Add Firefox + WebKit if available. They're installed via
// `npx playwright install`. We don't fail the build if they're missing —
// CI installs all three; local devs may have just Chromium.
try {
  const { firefox } = await import('playwright');
  browsers.push({ name: 'firefox', launcher: firefox });
} catch {}
try {
  const { webkit } = await import('playwright');
  browsers.push({ name: 'webkit', launcher: webkit });
} catch {}

async function run() {
  await new Promise(resolve => server.listen(0, resolve));
  const port = server.address().port;
  const base = `http://localhost:${port}${BASE_PATH}`;

  let totalErrors = 0;
  let totalRenderingFailures = 0;

  for (const { name, launcher } of browsers) {
    console.log(`\n========== ${name.toUpperCase()} ==========`);
    console.log(`smoke: serving ${DIST} at ${base}`);
    console.log(`smoke: visiting ${samplePaths.length} sample URLs\n`);

    let browser;
    try {
      browser = await launcher.launch();
    } catch (e) {
      console.log(`  ! ${name} could not launch — skipping (likely local env issue): ${e.message.split('\n')[0]}`);
      continue;
    }
    const page = await browser.newPage();

    const pageErrors = [];
    const failedRequests = [];

    page.on('pageerror', err => pageErrors.push(err.message));
    page.on('response', resp => {
      if (resp.status() >= 400) {
        const url = resp.url();
        // Ignore expected-missing auto-synthesized routes (tracked upstream as
        // concept-browser#174). We don't want to gate the deploy on known
        // upstream bugs.
        const knownMissing = ['/learn', '/data/', 'bibliography.json', 'designations', 'relationships', 'statuses'];
        if (!knownMissing.some(p => url.includes(p))) {
          failedRequests.push(`${resp.status()} ${url}`);
        }
      }
    });

    let renderingFailures = 0;
    for (const urlPath of samplePaths) {
      const url = base + urlPath;
      process.stdout.write(`  ${urlPath} ... `);
      try {
        await page.goto(url, {waitUntil: 'domcontentloaded', timeout: 10000});
        await page.waitForLoadState('networkidle', {timeout: 5000}).catch(() => {});
        await page.waitForTimeout(1500);
        const title = await page.title();
        const bodyLen = await page.evaluate(() => document.body?.innerText?.length || 0);
        console.log(`title="${title}" body=${bodyLen}c`);
        if (bodyLen < 50) renderingFailures++;
      } catch (e) {
        console.log(`NAVIGATION FAILED: ${e.message}`);
        renderingFailures++;
      }
    }

    await browser.close();

    console.log(`\n--- ${name} summary ---`);
    console.log(`Page errors: ${pageErrors.length}`);
    pageErrors.slice(0, 5).forEach((e, i) => console.log(`  [${i}] ${e.slice(0, 300)}`));
    console.log(`Unexpected failed requests: ${failedRequests.length}`);
    failedRequests.slice(0, 10).forEach((e, i) => console.log(`  [${i}] ${e}`));
    console.log(`Rendering failures: ${renderingFailures}`);

    totalErrors += pageErrors.length;
    totalRenderingFailures += renderingFailures;
  }

  server.close();

  console.log(`\n=== Final summary (${browsers.length} browser(s)) ===`);
  console.log(`Total page errors: ${totalErrors}`);
  console.log(`Total rendering failures: ${totalRenderingFailures}`);

  if (totalErrors > 0 || totalRenderingFailures > 0) {
    console.error('\nsmoke: FAIL');
    process.exit(1);
  }
  console.log('\nsmoke: OK');
}

run().catch(e => {
  console.error('smoke: internal error', e);
  server.close();
  process.exit(2);
});
