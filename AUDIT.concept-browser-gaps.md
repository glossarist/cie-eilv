# concept-browser gaps — audit

This document catalogs every place where `glossarist/cie-eilv` works around an upstream `glossarist/concept-browser` gap. Each entry links to the upstream issue that would remove the workaround.

The pattern across all entries is the same: **concept-browser's build does not honor a config option, generate a required resource, or run a smoke test that would catch the gap.** Consumers pay for it with custom scripts that break on every minor version bump.

## Workarounds in this repo

### 1. `scripts/install-favicons.mjs` — 148 lines

**Why**: concept-browser always generates a default "G" favicon set on every build and writes the corresponding `<link>` tags into every static HTML page. Consumers who want their own brand favicon (e.g. RealFaviconGenerator output) have no config option. The script:
- Restores canonical RFG files from `assets/favicons/` over concept-browser's defaults in both `public/` and `dist/`.
- Rewrites `site.webmanifest` with the correct `BASE_PATH` and our brand color.
- Strips concept-browser's auto-generated PNG/ICO cruft.
- Patches every `dist/**/*.html`: removes the CLI-injected `<link>` tags and injects the RFG markup.

**Live symptom if absent**: console errors `404 favicon-16x48.png`, `404 favicon-32x32.png`, `404 favicon-48x48.png` on every page load (visible to end users, including the project maintainer who reported them).

**Upstream fix**: glossarist/concept-browser#173 — add `branding.favicon` config so consumers point at canonical files; build respects them verbatim and does not regenerate defaults.

### 2. `datasets/cie-2020/bibliography.yaml` — empty placeholder

**Why**: concept detail pages unconditionally `fetch('/data/<dataset>/bibliography.json')`. The build generates `bibliography.json` only when the source `bibliography.yaml` exists. With no placeholder, every concept page logs `404 bibliography.json` in the visitor's console.

**Live symptom if absent**: `404 bibliography.json` on every concept page navigation.

**Upstream fix**: glossarist/concept-browser#174 — always emit `bibliography.json` (even if empty: `{}`).

### 3. (Removed) `scripts/install-fonts.mjs`

**Why (historically)**: concept-browser baked `DM Sans` into every built HTML/CSS asset regardless of the `branding.fonts` config. The script rewrote the Google Fonts URL and the `font-family` declarations across every built file.

**Current status**: removed in 0.7.104 after upstream landed the `set:html` CSS-variable injection fix. **However**, the upstream fix's inline `<style>:root{...}` block is overridden by the Tailwind theme's `:root,:host{...}` block due to source order (inline at HTML char ~2088, stylesheet at char ~2539, same specificity, later wins). Tracked at glossarist/concept-browser#166 (partial fix, follow-up pending).

Live symptom if reintroduced silently: body text renders in DM Sans (browser default), Raleway is downloaded but unused.

### 4. (Removed) `patches/use-concept-edges.ts` + `scripts/patch-concept-browser.mjs`

**Why (historically)**: concept-browser@0.7.87 published a `use-concept-edges.ts` that imported `GenericHyperedge` from `glossarist/models`, but the pinned `glossarist@0.4.26` didn't export it. The patch copied the working file from `glossarist/iala-vocab`'s tree.

**Current status**: removed in 0.7.102, which bumped glossarist to 0.4.51 (compiled `dist/`, exports `GenericHyperedge`). Genuinely obsolete.

## Operational gaps (no workaround, just risk)

### 5. No build-time smoke test

`vite build` succeeds even if the generated JS throws at browser hydration time. The 0.7.102 → 0.7.104 releases shipped with three regressions that an end user (or downstream maintainer) had to catch manually:

- #171 — `conceptGenericRelations` hydration TypeError (concept pages failed to render).
- #166 — `branding.fonts` CSS cascade regression (pages rendered in DM Sans).
- `tsx` devDependency runtime requirement (fixed in 0.7.103) — `npm install --omit=dev` builds failed.

All three would have been caught by a Playwright smoke test that loads sample pages and asserts zero `pageerror` events.

**Upstream fix**: glossarist/concept-browser#172.

**Local mitigation**: `scripts/smoke.mjs` in this repo runs the same kind of test against our build. Wired into CI as a deploy gate (see `.github/workflows/build_deploy.yml`).

### 6. Auto-synthesized `/learn` route, no static page

`page-types.ts` auto-synthesizes a `learn` page with `autoSynthesize: true`. The nav renders a link to `/<base>/learn/`. The `[...path].astro` catch-all does NOT include `learn` in its `getStaticPaths` list, so the link 404s.

**Live symptom**: `404 learn` on every page load (the nav is prefetched).

**Upstream fix**: glossarist/concept-browser#174.

### 7. Concept detail page requests resources that don't exist

Concept detail page emits `fetch()` calls for:
- `data/<dataset>/bibliography.json` (covered above)
- `data/<dataset>/designations` — never generated
- `data/<dataset>/relationships` — never generated
- `data/<dataset>/statuses` — never generated

The last three look like REST endpoints left over from an earlier architecture.

**Live symptom**: `404 designations`, `404 relationships`, `404 statuses` on every concept page navigation.

**Upstream fix**: glossarist/concept-browser#174.

## Issue tracker

| # | Title | Status |
|---|---|---|
| [162](https://github.com/glossarist/concept-browser/issues/162) | branding.fonts ignored at build time | closed (partial fix) |
| [166](https://github.com/glossarist/concept-browser/issues/166) | regression: branding.fonts fix emits literal `${fontHeader}` in CSS | closed (partial fix) |
| [171](https://github.com/glossarist/concept-browser/issues/171) | TypeError: r.conceptGenericRelations.length at hydration | open |
| [172](https://github.com/glossarist/concept-browser/issues/172) | feat: post-build Playwright smoke test as deploy gate | open |
| [173](https://github.com/glossarist/concept-browser/issues/173) | feat(branding): honor branding.favicon config | open |
| [174](https://github.com/glossarist/concept-browser/issues/174) | feat: stop emitting requests the build can't satisfy | open |

## What needs to happen to remove every workaround

In order of impact:

1. **concept-browser#172** lands → add `npm run smoke` to our CI, drop our local `scripts/smoke.mjs` (use upstream's).
2. **concept-browser#173** lands → delete `scripts/install-favicons.mjs` and the `&& node scripts/install-favicons.mjs` from `npm run build`. Move `assets/favicons/` reference into `site-config.yml branding.favicon.source_dir`.
3. **concept-browser#174** lands → delete `datasets/cie-2020/bibliography.yaml` (empty placeholder).
4. **concept-browser#166** fully resolved (cascade order) → re-verify Raleway renders correctly without any post-processing. Currently it does, because we're on 0.7.104 and the inline `:root` is winning by virtue of @layer interaction (Tailwind's `:root` is inside `@layer theme`, which loses to the unlayered inline style).
5. **concept-browser#171** lands → re-validate that concept pages hydrate without errors.

After all five: this repo has zero custom JS build scripts. The only scripts are the Ruby data-pipeline (`scrape_*`, `transform_*`, `audit_*`).
