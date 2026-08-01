# 12 — Concept-browser deployment

## Goal

Wire the dataset into the Glossarist Concept Browser and ship a deploy
pipeline that publishes to GitHub Pages at
`https://www.glossarist.org/cie-eilv/`.

Pattern: copy the deploy setup from `../iala-vocab/.github/workflows/build_deploy.yml`
and `../iala-vocab/package.json`, swap `iala`/`iala-vocab` → `cie`/`cie-eilv`.

## Files

### `site-config.yml` (final form)

Already drafted in step 01. Confirm or update:

- `id: cie`
- `base_path: /cie-eilv/`
- `datasets[0].id: cie-2020`
- `datasets[0].local_path: datasets/cie-2020`
- `datasets[0].owner: CIE`
- `dataset_groups[0].kind: flat` (NOT `lineage`)
- `dataset_groups[0].current: cie-2020`
- `branding.owner_name: CIE`, `branding.owner_url: https://cie.co.at`
- `copyright: CIE`

### `about-eng.md`

Long-form About page (~300–500 words). Mirror the structure of
`../iala-vocab/about-eng.md` but for CIE/ILV:

1. **What this is**: Glossarist-browseable edition of CIE S 017:2020 ILV.
2. **Source**: e-ILV at `https://cie.co.at/e-ilv`. Link to the paid
   standard in the CIE Webshop for the complete multilingual edition.
3. **Copyright & license**: CIE holds the term content. Terms
   reproduced under CIE's free e-ILV terms. Verify the exact license
   wording with CIE before publishing — do NOT assume CC-BY.
4. **Maintenance**: this dataset is a snapshot of the free e-ILV as of
   `<date>`; for upstream changes, see `cie.co.at`.
5. **Provenance**: every concept file carries an `origin.link` back to
   its `https://cie.co.at/eilvterm/<id>` source page.

### `public/images/`

Add CIE logo SVGs (light + dark). Source from `https://cie.co.at/themes/custom/cie/cie.svg`
or higher-res variants if available. Reference in `site-config.yml`:

```yaml
branding:
  logo:
    alt: CIE
    local_light: public/images/cie-logo-light.svg
    local_dark: public/images/cie-logo-dark.svg
```

If CIE's logo license is unclear, omit `branding.logo` and let the
browser render `owner_name: CIE` as text. **Do not commit a logo you do
not have rights to redistribute.** (See global CLAUDE.md: "NEVER DELETE
source files" and "If cleanup is needed, suggest — do not act.")

### `.github/workflows/build_deploy.yml`

Copy `../iala-vocab/.github/workflows/build_deploy.yml` verbatim, then
find/replace:

- `iala-vocab` → `cie-eilv`
- `iala` → `cie` (in dataset id references only — be careful with
  substring matches; e.g., don't rename `iala-aism.org` references if
  any leaked in)

Workflow shape (mirror IALA):

```yaml
name: Build and Deploy
on:
  push:
    branches: [main]
  pull_request:
  workflow_dispatch:
  repository_dispatch:
    types: [deploy]

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: pages
  cancel-in-progress: true

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: npm
      - uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true
      - run: npm install
      - run: bundle exec ruby scripts/audit_terms.rb
      # Rewrite the file: reference in package.json to a versioned npm install
      # (matches the IALA workflow's published-packages trick).
      - run: node scripts/install-concept-browser.mjs   # if present; else skip
      - run: npx concept-browser build
        env:
          NODE_PATH: ${{ github.workspace }}/node_modules/@glossarist/concept-browser/node_modules
      - uses: actions/upload-pages-artifact@v3
        with:
          path: dist
  deploy:
    needs: build
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    steps:
      - id: deployment
        uses: actions/deploy-pages@v4
```

The audit step gates the build: if `audit_terms.rb` exits non-zero,
no deploy.

### `package.json` (final form)

Already drafted in step 01. Confirm:

```json
{
  "name": "cie-eilv",
  "private": true,
  "version": "0.1.0",
  "scripts": {
    "generate": "concept-browser generate",
    "dev": "concept-browser dev",
    "build": "concept-browser build"
  },
  "dependencies": {
    "@glossarist/concept-browser": "^X.Y.Z"
  }
}
```

Pin the version that matches what `iala-vocab` currently uses — open
`../iala-vocab/package.json` and copy the exact version range.

### GitHub Pages setup

After the first successful workflow run on `main`:

1. Repo Settings → Pages → Source: **GitHub Actions** (not "Deploy from
   a branch").
2. The workflow's `deploy-pages` step publishes the artifact.

The site appears at `https://<org>.github.io/cie-eilv/` first; the
glossarist.org custom path is configured by the glossarist org maintainers
(CNAME / reverse proxy on `www.glossarist.org/cie-eilv/`).

## Specs

No specs here — this step is config + workflow wiring. Verification is
the deploy itself.

## Verification

```bash
npm install
npm run generate               # reads site-config.yml → public/site-config.json + datasets.json
npm run dev                    # local preview at http://localhost:5173/cie-eilv/
# In a browser: verify About page renders, browse to a concept, follow a cross-ref link.
```

Then push to a PR and watch CI:

```bash
gh pr create --title "Deploy CIE e-ILV" --body-file <(cat <<'EOF'
## Summary
- Initial CIE e-ILV dataset (CIE S 017:2020, ~1300 concepts)
- Concept-browser deploy pipeline

## Test plan
- [ ] `bundle exec ruby scripts/audit_terms.rb` exits 0
- [ ] `npm run dev` shows the site locally
- [ ] CI workflow runs green
- [ ] After merge: site reachable at https://www.glossarist.org/cie-eilv/
EOF
)
```

After merge to `main`, confirm the Pages deploy succeeded:

```bash
gh run list --workflow=build_deploy.yml --limit 3
curl -sI https://www.glossarist.org/cie-eilv/ | head -5
```

## Do not

- Do NOT commit `dist/` or `public/site-config.json` — both are
   build artifacts, gitignored. The workflow regenerates them.
- Do NOT skip the audit step in CI. It's the only invariant check
   between a corrupt dataset and a broken production site.
- Do NOT auto-trigger deploys from `repository_dispatch` until
   `glossarist.org` is ready to route the path. Start with
   `push: [main]` + `workflow_dispatch` only.
- Do NOT include AI-attribution trailers in commit messages or PR
   descriptions (see global CLAUDE.md). The user is the sole author.
