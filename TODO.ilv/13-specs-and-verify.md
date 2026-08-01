# 13 — Specs and end-to-end verification

## Goal

Lock in the contract. Every `lib/` class has specs (real models, no
doubles), and an end-to-end smoke test runs the full pipeline against a
5-term sample so regressions surface before merge.

This step is the **verification gate** for the whole plan. Per the
global CLAUDE.md and the `verification-before-completion` skill: evidence
before assertions. Do not merge until everything below is green.

## Per-class spec inventory (already written alongside each step)

| Step | Spec file | Class under test |
|---|---|---|
| 02 | `spec/api_client_spec.rb` | `CieEilv::ApiClient` |
| 03 | `spec/term_index_spec.rb` | `CieEilv::TermIndex` |
| 05 | `spec/term_parser_spec.rb` | `CieEilv::TermParser` |
| 06 | `spec/concept_file_spec.rb` | `CieEilv::ConceptFile` |
| 07 | `spec/transformer_spec.rb` | `CieEilv::Transformer` (extracted from `scripts/transform_terms.rb`) |
| 08 | `spec/sections_spec.rb` | `CieEilv::Sections` |
| 09 | `spec/register_builder_spec.rb` | `CieEilv::RegisterBuilder` |
| 10 | `spec/cross_ref_linker_spec.rb` | `CieEilv::CrossRefLinker` |
| 11 | `spec/auditor_spec.rb` | `CieEilv::Auditor` |

## Spec helper: `spec/spec_helper.rb`

```ruby
require "cie_eilv"
require "rspec"

RSpec.configure do |c|
  c.expect_with :rspec do |e|
    e.syntax = :expect   # no `should`
  end
end

FIXTURES = File.expand_path("fixtures", __dir__)
def fixture(name) = File.read(File.join(FIXTURES, name))
```

## Fixtures (`spec/fixtures/`)

Capture once, commit to the repo (unlike `reference-docs/`, spec fixtures
ARE source-of-truth for the parser contract and must be in git):

```
spec/fixtures/
  e-ilv-listing.html          # captured in step 03
  terms/17-21-012.html        # designation + usage + POS + 3 notes (1 with cross-ref)
  terms/17-21-025.html        # symbol entry + 7 notes (formula, units, cross-refs)
  terms/17-21-027.html        # adj part-of-speech + usage_info
  terms/17-21-032.html        # usage_info only, no POS
  terms/17-22-002.html        # pl part-of-speech, no usage_info
  terms/17-25-014.html        # no TermDesc span at all
  terms/17-29-062.html        # simple case with 1 prior-numbering note
```

Each fixture pins an HTML variant the parser must handle. If `cie.co.at`
drifts (new Note class, new attribute on `<a>`), capture a new fixture
and update the spec — the existing fixtures stay so we test against the
old shape too.

## End-to-end smoke test

`spec/e2e/smoke_spec.rb`:

```ruby
require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe "end-to-end pipeline" do
  let(:sample_termids) do
    %w[17-21-012 17-21-025 17-21-027 17-22-002 17-29-062]
  end

  it "scrapes, transforms, links, and audits a 5-term sample" do
    Dir.mktmpdir("cie-eilv-e2e") do |tmp|
      Dir.chdir(tmp) do
        # Stage a tiny reference-docs from fixtures
        FileUtils.mkdir_p("reference-docs/scraped/terms/pages")
        index = sample_termids.map { |id|
          FileUtils.cp(File.join(FIXTURES, "terms", "#{id}.html"),
                       "reference-docs/scraped/terms/pages/#{id}.html")
          { termid: id, listing_designation: "" }
        }
        File.write("reference-docs/scraped/terms/index.json", JSON.generate(index))

        # Run pipeline pieces (lib calls, not script shellouts)
        CieEilv::RegisterBuilder.new(out_path: "datasets/cie-2020/register.yaml").run!
        transformer = CieEilv::Transformer.new(out_dir: "datasets/cie-2020/concepts")
        sample_termids.each do |id|
          html = File.read("reference-docs/scraped/terms/pages/#{id}.html")
          term = CieEilv::TermParser.parse(html, termid: id)
          transformer.write_concept(term)
        end
        CieEilv::CrossRefLinker.new.run!

        # Audit must pass
        expect(CieEilv::Auditor.new.run!).to eq(0)

        # Output files exist and have the right shape
        sample_termids.each do |id|
          path = "datasets/cie-2020/concepts/#{id}.yaml"
          expect(File.exist?(path)).to be true
          cf = CieEilv::ConceptFile.new(path)
          expect(cf.managed.termid).to eq(id)
          expect(cf.find_localized(:eng)).not_to be_nil
        end

        # Cross-ref in 17-21-012 is rewritten
        cf = CieEilv::ConceptFile.new("datasets/cie-2020/concepts/17-21-012.yaml")
        note_text = cf.find_localized(:eng).notes.map { |n| n[:content] }.join
        expect(note_text).to include("{17-21-002,")
        expect(note_text).not_to include('href="/eilvterm/')
      end
    end
  end
end
```

This is the single most important spec — it exercises every lib class in
sequence against real fixtures. If it passes, the production pipeline
will pass.

## Run commands

```bash
bundle exec rspec                                    # all specs, fast
bundle exec rspec spec/term_parser_spec.rb           # single spec file
bundle exec rspec spec/term_parser_spec.rb:42        # single example by line
bundle exec ruby scripts/audit_terms.rb              # dataset audit, exit 0
bundle exec ruby -e 'require "cie_eilv"; CieEilv::CrossRefLinker.new.run!'  # idempotency check
```

## Pre-merge checklist

Run all of these and confirm green before opening a PR:

1. `bundle exec rspec` — full suite, 0 failures.
2. `bundle exec ruby scripts/audit_terms.rb` — exits 0.
3. `bundle exec ruby scripts/transform_terms.rb` — idempotent: re-run
   produces no git diff in `datasets/`.
4. `bundle exec ruby -e 'require "cie_eilv"; puts CieEilv::CrossRefLinker.new.run!'`
   — second run prints `touched 0 files`.
5. `npm run generate && npm run dev` — site loads locally, navigate to
   `http://localhost:5173/cie-eilv/`, click a concept, follow a cross-ref.
6. Spot-check 3 concept YAML files by eye against their source term pages.
7. `git status` shows only expected files (no `dist/`, no `node_modules/`,
   no `reference-docs/`, no `public/site-config.json`).

## Coverage expectations

Don't add the `simplecov` gem unless the user asks. The spec inventory
above is the contract — if a class is in `lib/`, it has a spec. Missing
spec = missing class. Audit by listing:

```bash
ls lib/cie_eilv/*.rb | sed 's|lib/cie_eilv/||;s|\.rb||' | sort
ls spec/*_spec.rb | sed 's|spec/||;s|_spec\.rb||' | sort
```

The two lists should match. (Skipping `version.rb`, which has no behavior.)

## Do not

- Do NOT use `double()` or `instance_double` anywhere. Real
   `Glossarist::V3::*` instances only (see global CLAUDE.md).
- Do NOT mock the filesystem in `ConceptFile` / `Auditor` specs. Use
   `Dir.mktmpdir` with real files.
- Do NOT mock `ApiClient` in `term_parser_spec.rb`. The parser takes HTML
   strings as input — pass fixture contents directly, no network needed.
- Do NOT skip the e2e smoke test. It is the only spec that catches
   integration bugs (wrong method name between classes, broken file
   paths, etc.).
- Do NOT mark the work complete until every command in the pre-merge
   checklist is green (verification-before-completion skill).
