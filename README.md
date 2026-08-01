# CIE e-ILV

[![Deploy](https://github.com/glossarist/cie-eilv/actions/workflows/build_deploy.yml/badge.svg)](https://github.com/glossarist/cie-eilv/actions/workflows/build_deploy.yml)

The CIE e-ILV is a Glossarist Concept Browser edition of the **CIE International Lighting Vocabulary (ILV)**, 2nd edition (CIE S 017:2020), published by the International Commission on Illumination. It deploys to <https://www.glossarist.org/cie-eilv/>.

The deployment pattern follows [`glossarist/iala-vocab`](https://github.com/glossarist/iala-vocab).

## Repository structure

```
datasets/cie-2020/      # the dataset (authoritative, hand-curated via scrape)
  concepts/*.yaml       # Glossarist v3 multi-doc YAML per concept
  register.yaml         # dataset metadata + section tree
lib/cie_eilv/           # typed Ruby library (autoloaded, model-driven)
scripts/                # pipeline entry points (thin wrappers around lib/)
site-config.yml         # deployment config (datasets, branding, basePath)
cie_eilv.gemspec        # path-gem spec — referenced from Gemfile
```

See [`CLAUDE.md`](./CLAUDE.md) for the full architecture: `ApiClient` / `TermIndex` / `TermParser` / `TermEntry` / `ConceptBuilder` / `ConceptFile` / `RegisterBuilder` / `CrossRefLinker` / `Auditor`.

## Building locally

### Prerequisites

- Node.js 20+ and npm
- Ruby 3.0+ and Bundler

### Install

```bash
npm install                       # concept-browser + glossarist JS deps
bundle install                    # Ruby deps (glossarist, httparty, nokogiri, rspec)
```

### Generate and dev

```bash
npm run generate                  # reads site-config.yml → public/site-config.json + datasets.json
npm run dev                       # vite dev server at http://localhost:5173/cie-eilv/
```

`npm run dev` runs `generate` first; `npm run build` does not — always run `generate` after editing `site-config.yml` or any concept YAML.

### Production build

```bash
npm run build                     # produces dist/ for GH Pages
```

### Test

```bash
bundle exec rspec                 # spec suite for lib/cie_eilv/ (real models, no doubles)
bundle exec ruby scripts/audit_terms.rb   # exit 0 = clean, exit 1 = schema/URI errors
```

## Updating the dataset

The dataset is a snapshot of the free e-ILV. To regenerate from upstream `cie.co.at`:

```bash
bundle exec ruby scripts/scrape_term_list.rb
bundle exec ruby scripts/scrape_term_pages.rb
bundle exec ruby scripts/transform_terms.rb
bundle exec ruby -e 'require "cie_eilv"; CieEilv::CrossRefLinker.new.run!'
bundle exec ruby scripts/generate_register.rb
bundle exec ruby scripts/audit_terms.rb
```

See [`CLAUDE.md`](./CLAUDE.md) "Data pipeline" for details.

## License

Term content copyright © CIE 2020. Code under the same license terms as the Glossarist project.
