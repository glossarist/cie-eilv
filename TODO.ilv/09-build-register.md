# 09 — Build the register

## Goal

Emit `datasets/cie-2020/register.yaml` — the dataset-level metadata file
that the concept-browser reads to render the site index, navigation, and
section tree.

## File: `lib/cie_eilv/register_builder.rb`

```ruby
module CieEilv
  class RegisterBuilder
    DATASET_ID = "cie-2020".freeze
    URN = "urn:cie:ilv:cie-2020".freeze

    attr_reader :out_path

    def initialize(out_path: "datasets/cie-2020/register.yaml")
      @out_path = out_path
    end

    # Build the register from the term index + section table.
    # Writes +out_path+. Returns the register Hash.
    def run!
      index = JSON.parse(File.read("reference-docs/scraped/terms/index.json"))
      section_counts = count_by_section(index)

      register = {
        schema_type: "glossarist",
        schema_version: "3",
        id: DATASET_ID,
        ref: "CIE S 017:2020 ILV: International Lighting Vocabulary, 2nd edition",
        year: 2020,
        urn: URN,
        status: "current",
        owner: "CIE",
        source_repo: "https://github.com/glossarist/cie-eilv",
        tags: %w[lighting illumination photometry colorimetry cie ilv],
        languages: ["eng"],
        language_order: ["eng"],
        ordering: "systematic",
        description: {
          eng: "The International Lighting Vocabulary (ILV), 2nd edition (CIE S 017:2020). " \
               "Free electronic edition provided by the CIE at https://cie.co.at/e-ilv."
        },
        sections: build_section_tree(section_counts)
      }

      File.write(out_path, YAML.dump(register))
      register
    end

    private

    def count_by_section(index)
      index.each_with_object(Hash.new(0)) do |entry, counts|
        section = entry["termid"].split("-")[1]
        counts[section] += 1
      end
    end

    def build_section_tree(counts)
      Sections.all.map do |sec|
        {
          id: sec,
          names: { eng: Sections.title_for(sec) },
          children: []
        }
      end
    end
  end
end
```

## File: `scripts/generate_register.rb`

```ruby
#!/usr/bin/env ruby
require "cie_eilv"

register = CieEilv::RegisterBuilder.new.run!
puts "Wrote register to #{CieEilv::RegisterBuilder::DATASET_ID}/register.yaml"
puts "Sections: #{register[:sections].length}"
```

### Why the term count isn't in `register.yaml`

The concept-browser counts terms per section dynamically from the concept
files. Putting a static count in `register.yaml` would drift from reality
as concepts are added or retired. The register only carries the section
**tree** (ids + titles); the counts come from the filesystem.

### Section tree shape

The concept-browser expects `sections` to be a recursive list:

```yaml
sections:
- id: '21'
  names:
    eng: Electromagnetic radiation and optical radiation
  children: []
```

`id` is the section prefix (String, quoted because YAML will otherwise
parse `"21"` as int 21). `names` is a language-keyed hash — only `eng`
for this repo. `children: []` is required even when empty (no subsections).

### Description is multilingual even when the dataset is English-only

The `description` field is a `{lang => text}` hash, mirroring the IALA
convention. For this repo only `eng` is populated. If CIE ever exposes a
French or German edition, additional language keys slot in without
schema changes.

## Specs (`spec/register_builder_spec.rb`)

Use a `Dir.mktmpdir` to write the register into an isolated location.
Provide a small fake `index.json` fixture under the tmpdir.

Cases:

1. `RegisterBuilder.new(out_path: tmp).run!` writes a file at `tmp`.
2. The written YAML parses back to a Hash with `id == "cie-2020"`,
   `year == 2020`, `urn == "urn:cie:ilv:cie-2020"`,
   `status == "current"`, `languages == ["eng"]`.
3. `sections` has 12 entries; `sections.first[:id] == "21"`,
   `sections.first[:names][:eng]` matches `Sections.title_for("21")`.
4. Every `section[:id]` is a String (not Integer) — guard against YAML
   numeric coercion by checking `.is_a?(String)` after round-trip.
5. `schema_type == "glossarist"` and `schema_version == "3"`.

## Verification

```bash
bundle exec rspec spec/register_builder_spec.rb
bundle exec ruby scripts/generate_register.rb
cat datasets/cie-2020/register.yaml | head -20
```

The first 20 lines should show the top-level keys in stable order. Confirm
that `id: '21'` is quoted (not `id: 21`).

## Do not

- Do NOT embed term counts in the section tree. The browser derives them.
- Do NOT sort sections alphabetically — sort by numeric id (21, 22, …, 32),
   matching the ILV's systematic ordering. `Sections.all` returns them in
   the right order; preserve it.
- Do NOT add `dataset_groups` to `register.yaml`. That key lives in
   `site-config.yml`, not the dataset register.
