# 07 — Transform parsed terms into Glossarist YAML

## Goal

For every cached term page, run `TermParser`, then build a Glossarist v3
multi-doc YAML file under `datasets/cie-2020/concepts/<termid>.yaml`.

## File: `scripts/transform_terms.rb`

```ruby
#!/usr/bin/env ruby
require "cie_eilv"
require "json"
require "fileutils"
require "securerandom"

INDEX = "reference-docs/scraped/terms/index.json"
PAGES_DIR = "reference-docs/scraped/terms/pages"
OUT_DIR = "datasets/cie-2020/concepts"
FileUtils.mkdir_p(OUT_DIR)

URN = "urn:cie:ilv:cie-2020"

index = JSON.parse(File.read(INDEX))
index.each do |entry|
  termid = entry["termid"]
  html_path = File.join(PAGES_DIR, "#{termid}.html")
  raise "Missing cached page: #{html_path}" unless File.exist?(html_path)

  html = File.read(html_path)
  term = CieEilv::TermParser.parse(html, termid: termid)

  managed = build_managed_concept(term)
  localized = build_localized_concept(term)

  yaml = [managed.to_h, localized.to_h].map { |h| YAML.dump(h) }.join
  File.write(File.join(OUT_DIR, "#{termid}.yaml"), yaml)
end

puts "Wrote #{index.length} concept files to #{OUT_DIR}/"

def build_managed_concept(term)
  section = term.termid.split("-")[1]    # "21" from "17-21-012"
  Glossarist::V3::ManagedConcept.new(
    id: SecureRandom.uuid_v5(URN, term.termid),  # stable UUID per termid
    termid: term.termid,
    status: :valid,
    domains: [
      { concept_id: "section-#{section}", source: URN, ref_type: :section }
    ],
    sources: [
      {
        origin: { ref: { source: "CIE S 017:2020" }, link: "https://cie.co.at/eilvterm/#{term.termid}" },
        type: :authoritative
      }
    ]
  )
end

def build_localized_concept(term)
  sources = [
    { origin: { ref: { source: "CIE S 017:2020" } }, type: :authoritative }
  ]
  sources.concat(extract_prior_numbering_sources(term))

  terms = [{
    type: :expression,
    normative_status: :preferred,
    designation: term.designation
  }]
  terms[0][:usage_info] = term.usage_info if term.usage_info
  terms[0][:part_of_speech] = term.part_of_speech if term.part_of_speech
  if term.symbol
    terms << { type: :symbol, normative_status: :preferred, designation: term.symbol }
  end

  Glossarist::V3::LocalizedConcept.new(
    id: "#{term.termid}-eng",
    language_code: :eng,
    terms: terms,
    definition: [{ content: term.definition }],
    notes: term.notes.map { |n| { content: n } },
    examples: [],
    sources: sources
  )
end

# Extract prior-numbering notes into structured sources.
# A note matching PRIOR_NUMBER_RE yields:
#   { origin: { ref: { source: "IEC 60050-845:1987", id: "845-01-06" } }, type: :authoritative }
# The verbatim note is ALSO preserved in notes[] (set in build_localized_concept).
def extract_prior_numbering_sources(term)
  term.notes.filter_map do |note|
    if note =~ CieEilv::TermParser::PRIOR_NUMBER_RE
      { origin: { ref: { source: $2, id: $1 } }, type: :authoritative }
    end
  end
end
```

### Designation/usage_info/part_of_speech mapping

The Glossarist v3 schema supports both `usage_info` and `part_of_speech` on
a term. Verify the exact attribute names by inspecting the loaded
`Glossarist::V3::*` class — do NOT guess. If the schema only has
`part_of_speech` and no `usage_info`, fold usage_info into the designation
(e.g. `light, <psychophysical>`).

This is the one place where reading the gem source is required:

```bash
bundle exec ruby -e 'require "glossarist"; p Glossarist::V3::LocalizedConcept.attributes'
```

If `usage_info` is not a declared attribute, store the TermDesc suffix
verbatim in the designation instead:

```ruby
designation: term.usage_info ? "#{term.designation}, <#{term.usage_info}>" : term.designation
```

### Stable managed-concept IDs

The managed concept's `id` field needs to be a stable identifier across
re-runs (so cross-edition links, if ever added, resolve consistently).
`SecureRandom.uuid_v5(URN, termid)` produces a deterministic UUID from the
termid — same input → same UUID. Use the dataset URN as the namespace.

If `SecureRandom` doesn't expose `uuid_v5` in your Ruby version, use the
`uuidtools` gem or hand-roll the UUID v5 algorithm (RFC 4122 §4.3) — it's
about 10 lines.

### Prior-numbering extraction

The regex `PRIOR_NUMBER_RE` matches:

```
This entry was numbered 845-01-06 in IEC 60050-845:1987.
This entry was numbered 17-659 (2.) in CIE S 017:2011.
This entry was numbered 17-392 in CIE S 017:2011.
```

Captures:

- `$1` = legacy id (`845-01-06`, `17-659 (2.)`, `17-392`)
- `$2` = prior standard name (`IEC 60050-845:1987`, `CIE S 017:2011`)

Both end up as a `sources[]` entry. The verbatim note text is preserved
verbatim in `notes[]` — readers see both forms.

### Output sample

`datasets/cie-2020/concepts/17-21-012.yaml`:

```yaml
---
id: 6f2e1a8b-...
termid: 17-21-012
status: valid
domains:
- concept_id: section-21
  source: urn:cie:ilv:cie-2020
  ref_type: section
sources:
- origin:
    ref:
      source: CIE S 017:2020
    link: https://cie.co.at/eilvterm/17-21-012
  type: authoritative
---
id: 17-21-012-eng
language_code: eng
terms:
- type: expression
  normative_status: preferred
  designation: light
  usage_info: psychophysical
  part_of_speech: noun
definition:
- content: radiation that is considered from the point of view of its ability to excite
    the visual system
notes:
- content: The term "light" is sometimes used for <a href="/eilvterm/17-21-002">optical
    radiation</a> extending outside the visible range, but this usage is not recommended.
- content: This entry was numbered 845-01-06 in IEC 60050-845:1987.
- content: This entry was numbered 17-659 (2.) in CIE S 017:2011.
examples: []
sources:
- origin:
    ref:
      source: CIE S 017:2020
  type: authoritative
- origin:
    ref:
      source: IEC 60050-845:1987
      id: 845-01-06
  type: authoritative
- origin:
    ref:
      source: CIE S 017:2011
      id: 17-659 (2.)
  type: authoritative
```

The `<a href="/eilvterm/17-21-002">optical radiation</a>` anchor in the
first note is preserved as-is at this stage. Step 10's `CrossRefLinker`
rewrites it into `{17-21-002, optical radiation}` Glossarist inline-ref
syntax in a second pass.

## Specs (`spec/transform_terms_spec.rb`)

Extract `build_managed_concept` / `build_localized_concept` /
`extract_prior_numbering_sources` into `lib/cie_eilv/transformer.rb` so
they're testable. The script becomes a thin loop.

Cases:

1. `build_managed_concept(term_for("17-21-012"))` →
   `termid == "17-21-012"`,
   `domains.first.concept_id == "section-21"`,
   `sources.first.origin.link == "https://cie.co.at/eilvterm/17-21-012"`.
2. `build_localized_concept(term_for("17-21-012"))` →
   `language_code == :eng`,
   `terms.first.designation == "light"`,
   `terms.first.usage_info == "psychophysical"`,
   `terms.first.part_of_speech == "noun"`,
   `notes.length == 3`.
3. `extract_prior_numbering_sources(...)` for 17-21-012 returns 2 sources
   (IEC 60050-845 + CIE S 017:2011).
4. For 17-21-025, the localized concept has TWO terms (expression + symbol
   `λ`).
5. Idempotency: re-running the script on an already-transformed dataset
   produces byte-identical YAML (sort keys, stable order).

## Verification

```bash
bundle exec rspec spec/transform_terms_spec.rb
bundle exec ruby scripts/transform_terms.rb
ls datasets/cie-2020/concepts/ | wc -l    # ~1300
head -20 datasets/cie-2020/concepts/17-21-012.yaml
```

The first 20 lines of the sample should match the structure above. Spot-check
3–5 files by eye against the source term page.

## Do not

- Do NOT generate a random UUID per run — that breaks cross-edition linking
   and pollutes git diffs. Use UUID v5 with the termid as the name.
- Do NOT delete the verbatim prior-numbering notes when extracting them
   into `sources[]`. They are user-visible provenance.
- Do NOT inline the script logic into `transform_terms.rb`. The script is
   a thin loop; the building logic lives in `lib/cie_eilv/transformer.rb`
   so it's spec-able.
