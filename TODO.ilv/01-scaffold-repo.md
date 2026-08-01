# 01 — Scaffold the repo

## Goal

Reproduce the `iala-vocab` repo skeleton so the rest of the pipeline has a
home. No business logic in this step — just files and directory layout.

## Files to create

### `Gemfile`

Copy the structure from `../iala-vocab/Gemfile` and adapt:

```ruby
source "https://rubygems.org"

gem "glossarist"          # Glossarist::V3::* model classes
gem "httparty"            # HTTPS client
gem "nokogiri"            # HTML parsing
gem "digest"

group :development do
  gem "rspec"
  gem "rubocop"
end
```

### `cie_eilv.gemspec`

Copy `../iala-vocab/iala_vocab.gemspec`, replace `IalaVocab` → `CieEilv`,
`iala_vocab` → `cie_eilv`, summary/description to CIE e-ILV wording. Set
`spec.bindir` and `executables` to empty (no bin commands).

### `lib/cie_eilv.rb`

Parent namespace with autoloads — copy the pattern from
`../iala-vocab/lib/iala_vocab.rb`. Declare autoloads for every class listed
in CLAUDE.md "Public classes" (ApiClient, TermIndex, TermParser, TermEntry,
ConceptFile, RegisterBuilder, Auditor, CrossRefLinker, plus Sections).

**Important**: never `require_relative` for code under `lib/`. Only the
parent `lib/cie_eilv.rb` may `require "glossarist"` and the standard library.

### `lib/cie_eilv/version.rb`

```ruby
module CieEilv
  VERSION = "0.1.0"
end
```

Reference `VERSION` from the gemspec via `require_relative "lib/cie_eilv/version"`
inside the gemspec (this is the one permitted `require_relative` — gemspecs
run before the gem is loaded).

### `package.json`

Copy `../iala-vocab/package.json` and adapt:
- `name`: `cie-eilv`
- `version`: `0.1.0`
- Keep `@glossarist/concept-browser` dependency and the same `scripts` block
  (`generate`, `dev`, `build`). The `file:` reference to a local
  concept-browser checkout is fine to keep — CI rewrites it.

### `site-config.yml`

Minimal first version — full branding comes in step 12:

```yaml
id: cie
domain: www.glossarist.org/cie-eilv
uri_base: https://www.glossarist.org/cie-eilv
base_path: /cie-eilv/
title: CIE e-ILV
subtitle: International Lighting Vocabulary (CIE S 017:2020)
description: Terminology from the CIE International Lighting Vocabulary
ui_languages:
- code: eng
  label: English
datasets:
- id: cie-2020
  title: CIE S 017:2020 ILV
  description: >-
    The International Lighting Vocabulary, 2nd edition (CIE S 017:2020).
    Free electronic edition provided by the CIE at https://cie.co.at/e-ilv.
  local_path: datasets/cie-2020
  ref: CIE S 017:2020
  owner: CIE
  color: '#003366'
routing: []
branding:
  primary_color: '#003366'
  dark_color: '#001a33'
  fonts:
    header: { family: Source Serif 4, source: google, weights: [400, 600] }
    body: { family: Source Sans 3, source: google, weights: [400, 500, 700] }
  owner_name: CIE
  owner_url: https://cie.co.at
features:
  news: false
  stats: true
  graph: true
  about: true
  search: true
  powered_by: { title: Glossarist, url: https://glossarist.org }
pages:
- type: about
  route: about
  title: About
  icon: info
  source: about-eng.md
defaults:
  language: eng
dataset_groups:
- id: cie
  label: CIE International Lighting Vocabulary
  kind: flat
  current: cie-2020
  datasets:
  - cie-2020
  color: '#003366'
copyright: CIE
```

Note `kind: flat` (not `lineage`) — this repo has one edition.

### `about-eng.md`

One-paragraph about page describing the source (CIE S 017:2020), the
free e-ILV site, and the copyright holder. Will be expanded in step 12.

### `.gitignore`

Copy `../iala-vocab/.gitignore`. Key entries:

```
/.bundle/
/.datasets/
/dist/
/node_modules/
/reference-docs/
/public/site-config.json
/public/datasets.json
/public/pages/*.json
*.gem
```

`reference-docs/` is gitignored — it is data provenance, not source. See
CLAUDE.md "Gitignored but load-bearing".

### Directory layout

```
datasets/cie-2020/
  concepts/          # empty; populated in step 07
  register.yaml      # written in step 09
lib/cie_eilv/         # empty; classes added in steps 02, 03, 05, 06, 08–11
scripts/              # empty; entry points added in steps 03, 04, 07, 09, 11
spec/                 # empty; specs added per-step (TDD)
spec/fixtures/        # cached HTML fixtures for parser tests
public/images/        # logo dir (logo added in step 12)
.github/workflows/    # workflow added in step 12
```

### `README.md`

The current README is a stub (`= CIE e-ILV\n\nCopyright CIE.`). Expand it to
mirror `../iala-vocab/README.md` structure: title, deploy badge placeholder,
description, repo-structure block, build/test commands. Keep it short —
the long-form docs live in `CLAUDE.md`.

## Verification

```bash
bundle install                                        # gems resolve
bundle exec ruby -e 'require "cie_eilv"'              # parent namespace loads
bundle exec rspec                                     # 0 examples, 0 failures (no specs yet)
node -e "console.log(require('./package.json').name)" # prints "cie-eilv"
```

All four commands must exit 0. Do not proceed to step 02 if `require "cie_eilv"`
fails — the autoloads are broken and every downstream step will fail.

## Do not

- Do NOT create the `Edition` / `EditionSeries` classes. This is a single
  edition repo (see CLAUDE.md "Edition model").
- Do NOT add a `routes.rb` or any Rails-ism. This is a library + scripts.
- Do NOT commit `Gemfile.lock` yet — it will be regenerated as deps are added.
  Actually, do commit it once `bundle install` succeeds; lockfiles belong in VCS
  for libraries (contrary to apps) so consumers get reproducible installs.
