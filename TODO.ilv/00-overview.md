# TODO.ilv — CIE e-ILV → Glossarist port plan

This directory contains the step-by-step plan for porting the CIE e-ILV
(https://cie.co.at/e-ilv) to a Glossarist Concept Browser site, modeled on the
sibling repo `glossarist/iala-vocab`.

## Context

- **Source**: CIE S 017:2020 ILV: International Lighting Vocabulary, 2nd edition,
  exposed free at `https://cie.co.at/e-ilv`. English-only on the free site.
- **Term list**: `https://cie.co.at/e-ilv` returns ~1,300 terms on a single HTML
  page (no pagination), grouped implicitly by term-id prefix `17-<section>-<n>`
  (sections 21–32).
- **Per-term page**: `https://cie.co.at/eilvterm/<termid>` (Drupal 10 node).
- **Target**: a `datasets/cie-2020/` Glossarist v3 dataset, deployed as a
  concept-browser site at `https://www.glossarist.org/cie-eilv/`.

## Steps (run in order)

| # | File | What |
|---|---|---|
| 00 | `00-overview.md` | This file. |
| 01 | `01-scaffold-repo.md` | Reproduce the iala-vocab repo skeleton: `Gemfile`, `gemspec`, `package.json`, `site-config.yml`, `.gitignore`, `lib/cie_eilv.rb` with autoloads, `spec/`, `scripts/`, empty `datasets/`. |
| 02 | `02-build-api-client.md` | `lib/cie_eilv/api_client.rb` — MD5-keyed on-disk HTTP cache, rate-limit, retries, UA header. Single network surface for the whole pipeline. |
| 03 | `03-scrape-term-list.md` | `scripts/scrape_term_list.rb` + `lib/cie_eilv/term_index.rb` — parse `/e-ilv` listing into `reference-docs/scraped/terms/index.json`. |
| 04 | `04-scrape-term-pages.md` | `scripts/scrape_term_pages.rb` — GET every `eilvterm/<id>`, cache raw HTML under `reference-docs/scraped/terms/pages/<termid>.html`. |
| 05 | `05-build-term-parser.md` | `lib/cie_eilv/term_parser.rb` + `term_entry.rb` — Nokogiri-driven extraction of designation / usage_info / part_of_speech / definition / notes / cross-concept links. Specs cover all observed HTML variants. |
| 06 | `06-build-concept-file.md` | `lib/cie_eilv/concept_file.rb` — multi-doc YAML stream read/write via `Glossarist::V3::*` with dirty tracking. |
| 07 | `07-transform-terms.md` | `scripts/transform_terms.rb` — TermEntry → Glossarist v3 multi-doc YAML per concept. Includes the dual-purpose "prior numbering" note handling (verbatim note + structured source). |
| 08 | `08-sections-table.md` | `lib/cie_eilv/sections.rb` — hand-curated table of the 12 ILV section names (21–32). Source names from CIE S 017:2020 TOC. |
| 09 | `09-build-register.md` | `lib/cie_eilv/register_builder.rb` + `scripts/generate_register.rb` — emit `register.yaml` with section tree derived from term-id prefixes. |
| 10 | `10-cross-ref-linker.md` | `lib/cie_eilv/cross_ref_linker.rb` — rewrite `/eilvterm/<id>` anchors into Glossarist `{id, designation}` inline-ref syntax. Idempotent. |
| 11 | `11-audit.md` | `lib/cie_eilv/auditor.rb` + `scripts/audit_terms.rb` — per-concept and per-dataset invariant checks. CI gate. |
| 12 | `12-concept-browser-deploy.md` | `site-config.yml`, `about-eng.md`, `.github/workflows/build_deploy.yml`, `package.json`, `public/` assets. Mirrors iala-vocab's deploy setup with `basePath: /cie-eilv/`. |
| 13 | `13-specs-and-verify.md` | `spec/` suite for every `lib/` class (real models, no doubles), plus an end-to-end smoke test that runs the full pipeline against a 5-term sample. |

## Sequencing rules

- Steps 01 → 12 are sequential: each depends on the previous step's output
  (file layout, library class, or scraped data).
- Step 13 (specs) is written alongside steps 02–11 per the TDD skill, but is
  listed last because it is the verification gate before merge.
- Every step ends with a runnable verification command (in the step's
  "Verification" section) — do not mark the step complete until that command
  passes.

## Source-of-truth references

- `../iala-vocab/CLAUDE.md` — sibling repo with the same architecture.
- `../iala-vocab/lib/iala_vocab.rb` — autoload pattern to copy.
- `../iala-vocab/lib/iala_vocab/api_client.rb` — HTTP cache pattern to copy
  (the e-ILV variant drops the MediaWiki API params; it's plain GETs).
- `../iala-vocab/site-config.yml` — site-config schema to copy.
- `../iala-vocab/.github/workflows/build_deploy.yml` — deploy workflow to copy.

## What is explicitly OUT of scope

- **Multi-language**: French and German translations live only in the paid
  CIE S 017:2020 standard. Do not attempt to scrape them from `cie.co.at`;
  they are not exposed on the free site. The dataset ships `eng` only.
- **Cross-edition lineage**: there is one edition (2020). Do not pre-build the
  `EditionSeries` / `CrossEditionLinker` machinery that `iala-vocab` has.
  The "prior numbering" notes carry the historical link to CIE S 017:2011
  and IEC 60050-845:1987 inline; that is sufficient.
- **Image scraping**: the e-ILV term pages are text-only. There are no inline
  figures to download.
