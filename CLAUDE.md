# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo does

Ports the **CIE e-ILV** (electronic International Lighting Vocabulary, published by the International Commission on Illumination at `https://cie.co.at/e-ilv`) to a Glossarist Concept Browser site, deployed to GitHub Pages under the glossarist umbrella (sibling of [`glossarist/iala-vocab`](https://github.com/glossarist/iala-vocab)).

The e-ILV is the free, online edition of **CIE S 017:2020 ILV: International Lighting Vocabulary, 2nd edition**. Each term lives at `https://cie.co.at/eilvterm/<term-id>` (e.g. `https://cie.co.at/eilvterm/17-21-012`). The site is English-only — French and German translations are part of the paid standard (CIE S 017:2020) and are NOT exposed on the free site. There is no MediaWiki API; the only network surface is plain HTTPS GETs against `cie.co.at`.

The full term list — ~1,300 terms across 12 sections (term-id prefix `17-21` through `17-32`) — fits on a single HTML page at `https://cie.co.at/e-ilv` with **no pagination**. Term IDs follow `17-<section>-<number>` where section is a two-digit zero-padded number; sections are implied by the prefix, not by explicit headers in the listing.

## Architecture

Mirror the structure of `glossarist/iala-vocab` (a sibling repo) for consistency. Parent namespace `module CieEilv` is declared in `lib/cie_eilv.rb`; every public class is autoloaded from there (never use `require_relative` for code under `lib/`). `scripts/` are thin entry points that load the library via `bundle exec`.

The library uses `Glossarist::V3::*` model classes throughout for concept serialization. No hand-rolled `to_h` / `from_h` — all (de)serialization goes through the framework (see global CLAUDE.md).

### Public classes

| Class | Responsibility |
|---|---|
| `CieEilv::ApiClient` | Plain HTTP client for `cie.co.at` with on-disk MD5 cache. No API — just GET the page HTML. |
| `CieEilv::TermIndex` | Parses the `/e-ilv` listing page into `{term_id, listing_designation}` records. |
| `CieEilv::TermParser` | Parses a single term page HTML into the structural fields (designation, usage, part_of_speech, definition, notes, cross-concept links). |
| `CieEilv::TermEntry` | Immutable value object: termid, designation, usage_info, part_of_speech, definition, notes[], examples[], sources[], supersession_history[]. |
| `CieEilv::ConceptFile` | Multi-doc YAML stream read/write with dirty tracking via `Glossarist::V3::*`. |
| `CieEilv::RegisterBuilder` | Emits `register.yaml` from the term-id section prefix + section title table. |
| `CieEilv::Auditor` | Per-concept invariant validation (termid present/unique, `terms[]` non-empty, `definition[]` has content). |
| `CieEilv::CrossRefLinker` | Resolves the inline `/eilvterm/17-XX-YYY` anchors in definitions and notes into Glossarist `{17-XX-YYY, designation}` inline-ref syntax for the concept-browser. |

### Forbidden patterns

- `Object#send` to call private methods
- `instance_variable_set` / `instance_variable_get`
- `respond_to?` for type checking
- `require_relative` for code under `lib/` (use autoload declared in the parent file)
- `double()` / `instance_double` in specs — real model instances only
- Hand-rolled `to_h` / `from_h` / `serialize` / `deserialize` on model classes

## Edition model

Unlike `iala-vocab` (which has 9 cumulative editions with a `supersedes` chain), the e-ILV is a **single edition** snapshot: CIE S 017:2020, published 2020-12. There is no lineage and no `dataset_groups` of `kind: lineage` — `site-config.yml` declares one dataset (`cie-2020`) and one flat `dataset_groups` entry pointing at it.

Historical numbering is captured per-concept, not as separate editions: each term page carries 0–3 `Note N to entry: This entry was numbered X in <prior standard>` notes for the IEC 60050-845:1987 and CIE S 017:2011 predecessors. The transformer emits these as `dates: [{type: …, …}]` plus a structured `sources[]` entry pointing at the prior standard — they are NOT separate datasets. See "Prior-numbering handling" below.

### Updating the dataset

CIE publishes a new edition every several years (last: 2011, then 2020). When a future CIE S 017:202X appears:

1. Add a new dataset directory `datasets/cie-<year>/`.
2. Add an `Edition` entry and convert this repo to the lineage model (copy the pattern from `iala-vocab`'s `EditionSeries` + `CrossEditionLinker`).
3. Re-scrape from `cie.co.at` (the prior edition's pages will be archived under `reference-docs/scraped/editions/cie-2020/`).

Until then, this repo is intentionally simpler than `iala-vocab`.

## e-ILV HTML structure (the load-bearing contract)

The Drupal 10 site at `cie.co.at` exposes each term page with this exact markup inside `<article class="node node--type-eilvterm ...">`:

```html
<div class="... field field--name-body ...">
  <p class="TermEntry">light<span class="TermDesc">, &lt;psychophysical&gt; noun</span></p>
  <p class="TermEntry"><span class="TermDesc"><italic>λ</italic></span></p>  <!-- symbol entry, optional -->
  <p class="Definition">radiation that is considered from the point of view of its ability to excite the visual system</p>
  <p class="Note"></p>                                                    <!-- empty Note separator, always present -->
  <p class="Note"><span class="NoteLabel">Note 1 to entry: </span>The term "light" is sometimes used for <a href="/eilvterm/17-21-002">optical radiation</a> extending outside the visible range, but this usage is not recommended.</p>
  <p class="Note"><span class="NoteLabel">Note 2 to entry: </span>This entry was numbered 845-01-06 in IEC 60050-845:1987.</p>
  <p class="Note"><span class="NoteLabel">Note 3 to entry: </span>This entry was numbered 17-659 (2.) in CIE S 017:2011.</p>
</div>
```

Field semantics:

- **`TermEntry`** — one or more paragraphs holding the **designation** (bold on the rendered page). The first `TermEntry` is the canonical designation. A second `TermEntry` (when present) holds a symbol/abbreviation (e.g. `λ` for wavelength, `tj` for LED junction temperature).
- **`TermDesc`** — `<span>` sibling to the designation within the first `TermEntry`. Contains the suffix `, <usage info> part-of-speech` (e.g. `, <psychophysical> noun`, `, <of a quantity> adj`, `, pl` for plurale tantum). Always starts with `, ` when present.
  - **Usage info** is everything inside the first `<...>` (angle brackets, HTML-escaped as `&lt;…&gt;`). May be absent.
  - **Part of speech** is the trailing word: `noun`, `adj`, `verb`, or absent. `pl` (plural-only) appears as a bare token without angle brackets (e.g. `cones, pl`).
- **`Definition`** — single paragraph. May contain `<a href="/eilvterm/17-XX-YYY">…</a>` cross-references.
- **`Note`** — zero or more paragraphs. The first `Note` is always empty (a separator artifact). Real notes carry a `<span class="NoteLabel">Note N to entry: </span>` prefix.
- **Examples / symbols / units** — NOT a separate CSS class. The e-ILV encodes formulae, units, and worked examples as numbered Notes (e.g. 17-21-025 Note 3 is the wavelength formula `λ = v / ν`, Note 4 explains units). The transformer treats all numbered Notes uniformly as `notes[]`.

Cross-concept links appear as `<a href="/eilvterm/<id>">designation</a>` inside `Definition` and `Note` paragraphs. `CrossRefLinker` rewrites these into Glossarist `{<id>, <designation>}` inline-ref syntax so the concept-browser renders them as hyperlinks to the target concept.

## Concept YAML schema (Glossarist v3, multi-document)

Each file in `datasets/cie-2020/concepts/` is a multi-doc YAML stream:

- **Doc 1 — managed concept**: `id`, `termid` (the `17-XX-YYY` code), `status: valid`, `domains[]` (points at `section-<n>` via the dataset URN), `sources[]` (authoritative ref to CIE S 017:2020).
- **Docs 2+ — localized concepts**: `id` = `<termid>-<lang>`, `language_code: eng`, `terms[]` (`type: expression`, `designation`, `normative_status: preferred`, optional `usage_info`, optional `part_of_speech`), `definition[]` (`content`), optional `notes[]`, optional `examples[]`, `sources[]`.

The English-only edition emits exactly one localized doc (`-eng`) per managed concept.

### Prior-numbering handling

Notes that match the regex `/\AThis entry was numbered ([-0-9.]+) in (IEC 60050-845:1987|CIE S 017:2011)\.\z/` are **dual-purpose**:

1. Kept verbatim in `notes[]` so the rendered page shows the legacy numbering.
2. Also extracted into a structured `sources[]` entry on the localized concept: `{origin: {ref: {source: "<prior standard>", id: "<legacy id>"}}, type: authoritative}`.

This lets future tooling build a cross-edition map without re-parsing note text. The 2020→2011 and 2020→IEC-60050-845 transitions are encoded in the source graph, not as separate datasets.

## The data pipeline (run scripts in this order)

Two-phase scrape → transform with local caching. Re-runs are incremental: cached pages are skipped.

1. **`scrape_term_list.rb`** — GET `https://cie.co.at/e-ilv`, parse with Nokogiri, walk `.views-row a[href^="/eilvterm/"]`, write `reference-docs/scraped/terms/index.json` (`[{termid, listing_designation}, …]`). Listing designation includes the `, <usage> part-of-speech` suffix from the listing page — used for sanity-checking against the per-page parser.
2. **`scrape_term_pages.rb`** — for each termid in `terms/index.json`, GET `https://cie.co.at/eilvterm/<id>`, cache raw HTML at `reference-docs/scraped/terms/pages/<termid>.html`. Rate-limited (default 0.2s, override with `CIE_API_DELAY`).
3. **`transform_terms.rb`** — for each cached page, `CieEilv::TermParser` extracts the structured fields and writes a Glossarist v3 multi-doc YAML at `datasets/cie-2020/concepts/<termid>.yaml`.
4. **`CieEilv::CrossRefLinker.new.run!`** — second pass over the dataset, rewriting `<a href="/eilvterm/17-XX-YYY">` anchors in `definition` and `notes` content into Glossarist `{17-XX-YYY, designation}` inline-ref syntax. Idempotent.
5. **`generate_register.rb`** — emits `datasets/cie-2020/register.yaml` via `CieEilv::RegisterBuilder`. Section tree is built from the term-id section prefix (`17-21`→section 21, …, `17-32`→section 32) and the section title table in `lib/cie_eilv/sections.rb`.
6. **`audit_terms.rb`** (or `CieEilv::Auditor.new.run!`) — validates per-concept (termid present/unique, `terms[]` non-empty, `definition[]` has content) and per-dataset (no duplicate termids, every cross-concept ref resolves to a real concept file). Exits non-zero on errors — GH Pages build should fail closed on this.

## HTTP client

`lib/cie_eilv/api_client.rb` is the only network surface. Every request is cached by `MD5(canonical_url)` under `reference-docs/api-cache/<hash>.html`. **Once cached, the cache is the source of truth — edits to upstream `cie.co.at` will not be picked up until you delete the cache file.** To force re-fetch, delete the relevant cached file (or all of `reference-docs/api-cache/`).

- `RATE_LIMIT_DELAY` defaults to `0.2s` between requests; override with `CIE_API_DELAY=<seconds>`.
- Retries on 5xx with exponential backoff (3 attempts). 4xx raises immediately.
- Always send a `User-Agent: Mozilla/5.0` header — the Drupal backend returns a 403 to default Ruby HTTParty UA in some configs.

## Configuration & deployment

- **`site-config.yml`** — canonical config (id `cie`, basePath `/cie-eilv/`, branding, datasets, features, pages). `npm run generate` turns this into `public/site-config.json` and `public/datasets.json`.
- **`about-eng.md`** — markdown source for the About page, registered via `pages: [{type: about, source: about-eng.md}]` in `site-config.yml`. Becomes `public/pages/about.json` after `generate`.
- **`.github/workflows/build_deploy.yml`** — runs on push to `main`, on PR, on `workflow_dispatch`, and on `repository_dispatch: deploy`. Installs concept-browser from npm (rewriting the `file:` reference in `package.json`), runs `npx concept-browser build`, uploads `dist/` as the Pages artifact, and deploys on `main`.
- **`basePath: /cie-eilv/`** — every URL is under this prefix because the site lives at `www.glossarist.org/cie-eilv/`, not a root domain.

## Gitignored but load-bearing

`.gitignore` excludes these directories — they are not disposable:

- **`reference-docs/`** — cached HTTP responses and pipeline outputs. Top-level layout:
  - `api-cache/<hash>.html` — raw HTTP cache keyed by `MD5(URL)`.
  - `scraped/terms/index.json` — term list produced by `scrape_term_list.rb`.
  - `scraped/terms/pages/<termid>.html` — per-term page HTML.
  - `reports/` — pipeline diagnostics.
  - Required to re-run transform/audit without hitting the network. Treat as data provenance, not build output.
- **`dist/`** — `concept-browser build` output.
- **`.datasets/`** — concept-browser intermediate working dir.

If you need to regenerate `datasets/` from scratch, you must first populate `reference-docs/` by running the scraper — the transformer does not call the network.

## Common commands

```bash
npm install                  # concept-browser + glossarist JS deps
bundle install               # ruby deps for scraper/transformer (httparty, nokogiri, glossarist)

npm run generate             # reads site-config.yml → public/site-config.json + datasets.json
npm run dev                  # vite dev server at http://localhost:5173
npm run build                # produces dist/ for GH Pages

bundle exec ruby scripts/audit_terms.rb         # exit 0 = clean, exit 1 = schema errors
bundle exec rspec                               # spec suite for lib/cie_eilv/ (real models, no doubles)
```

`npm run dev` runs `generate` first; `npm run build` does not. Always `npm run generate` after editing `site-config.yml` or any concept YAML.

The Vite config is loaded from `node_modules/@glossarist/concept-browser/vite.config.ts` with `NODE_PATH` pointed at the package's own `node_modules` — do not collapse these into a plain `vite` invocation.

## Known gotchas

- The `views-row` rows on the `/e-ilv` listing page use a single `<a href="/eilvterm/…">` per row — there is no per-section header. Sections are derived purely from the term-id prefix.
- The `<p class="Note"></p>` immediately after `<p class="Definition">…</p>` is always empty and is a separator artifact, not a real note. The parser skips it.
- The `TermDesc` suffix always starts with `, ` (comma-space). Strip this when extracting `usage_info` and `part_of_speech`.
- The `<italic>` tag is non-standard HTML (should be `<i>` or `<em>`). Nokogiri parses it as an unknown element — handle explicitly when serializing definition/note content as plain text or markdown.
- Some term pages have a second `<p class="TermEntry">` for a symbol/abbreviation (e.g. 17-21-025 has `λ`, 17-27-068 has `tj`). The first `TermEntry` is always the canonical designation; treat subsequent ones as additional `terms[]` entries of `type: symbol` if the Glossarist schema supports it, otherwise fold into the first term's designation.
- The legacy numbering notes (`This entry was numbered X in <prior standard>.`) appear in regular Note paragraphs alongside substantive notes — do not strip them. They carry provenance.
- HTML entities for angle brackets in usage info (`&lt;psychophysical&gt;`) decode to `<psychophysical>` — preserve these literally in the `usage_info` field; the concept-browser renders them as expected.
