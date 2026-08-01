# 08 — Hand-curated section table

## Goal

A single source of truth for the 12 ILV section names (term-id prefix `17-21`
through `17-32`), so the register builder (step 09) can attach human-readable
labels to the section tree.

## Why hand-curated

The e-ILV listing page does **not** emit section headers — sections are
implied by the term-id prefix only. The section titles are part of CIE S
017:2020's table of contents but are not exposed as data on the free site.

The authoritative source is the CIE S 017:2020 standard document (paid) or
the section index on the CIE website. Where a section title cannot be
verified against the standard, fall back to a short numeric label and flag
it for editor review.

## File: `lib/cie_eilv/sections.rb`

```ruby
module CieEilv
  module Sections
    # Term-id section prefix → human-readable section title.
    # Sourced from CIE S 017:2020 ILV table of contents.
    # If a title is unverified, it is marked TODO and falls back to numeric.
    TABLE = {
      "21" => "Electromagnetic radiation and optical radiation",
      "22" => "Visual perception",
      "23" => "Colorimetry",
      "24" => "Optical properties of materials and media",
      "25" => "Radiometric and photometric measurement",
      "26" => "Actinic effects of optical radiation",
      "27" => "Optical radiation sources and lighting equipment",
      "28" => "Lamp components and ancillaries",
      "29" => "Lighting and daylighting",
      "30" => "Luminaires and lighting equipment",
      "31" => "Visual signalling",
      "32" => "Imaging technology"
    }.freeze

    def self.title_for(section_prefix)
      TABLE[section_prefix] || "Section #{section_prefix}"
    end

    def self.all
      TABLE.keys.sort
    end
  end
end
```

### Verification protocol for section titles

Before merging, the section titles MUST be cross-checked against an
authoritative CIE source. Options, in order of preference:

1. **CIE S 017:2020 standard TOC** (paid). If you have access, this is
   authoritative.
2. **CIE website section index** at `https://cie.co.at/publications/international-lighting-vocabulary-ilv`
   or similar — sometimes lists section titles in the marketing blurb.
3. **The e-ILV term list itself**: scan all term designations in section N
   and infer the topic. This is the least authoritative; use only as a
   last resort and flag the title as `[unverified]`.

Run this one-off check during this step:

```bash
bundle exec ruby -e '
  require "json"
  idx = JSON.parse(File.read("reference-docs/scraped/terms/index.json"))
  idx.group_by { |t| t["termid"].split("-")[1] }.each do |sec, terms|
    puts "Section #{sec} (#{terms.length} terms):"
    puts "  first 3: #{terms.first(3).map { |t| t["listing_designation"] }.join(", ")}"
  end
'
```

The first 3 designations per section give a sanity-check on the topic.

### Per-section term counts (as of probe date)

For reference, the probe in 2026-08 found these section sizes (subject to
upstream drift — re-run the script above for the live numbers):

| Section | Title (proposed) | Term count |
|---|---|---|
| 21 | Electromagnetic radiation and optical radiation | 114 |
| 22 | Visual perception | 125 |
| 23 | Colorimetry | 86 |
| 24 | Optical properties of materials and media | 143 |
| 25 | Radiometric and photometric measurement | 116 |
| 26 | Actinic effects of optical radiation | 87 |
| 27 | Optical radiation sources and lighting equipment | 136 |
| 28 | Lamp components and ancillaries | 64 |
| 29 | Lighting and daylighting | 187 |
| 30 | Luminaires and lighting equipment | 73 |
| 31 | Visual signalling | 148 |
| 32 | Imaging technology | 68 |

Total ≈ 1,347. Re-derive from the live index before merging.

## Specs (`spec/sections_spec.rb`)

Cases:

1. `Sections.title_for("21")` returns a non-empty String.
2. `Sections.title_for("99")` returns `"Section 99"` (the fallback).
3. `Sections.all` returns the 12 keys `["21", "22", ..., "32"]` in order.
4. Every value in `Sections::TABLE` is a non-empty String with no leading or
   trailing whitespace.

## Verification

```bash
bundle exec rspec spec/sections_spec.rb
bundle exec ruby -e 'require "cie_eilv"; puts CieEilv::Sections::TABLE'
```

Eyeball the printed table against the CIE source you verified titles
against. If any title is `[unverified]`, open a follow-up issue before
merge.

## Do not

- Do NOT derive section titles from a web scrape of a non-CIE source.
   Wikipedia, third-party lighting glossaries, etc. are not authoritative
   for the ILV.
- Do NOT add subsections. The ILV term-id format is `17-XX-YYY` — only one
   level of section. If CIE introduces subsections in a future edition,
   the term-id format will change and the parser must be updated.
- Do NOT translate section titles in this step. The free e-ILV is
   English-only. Translations belong to a future multilingual edition.
