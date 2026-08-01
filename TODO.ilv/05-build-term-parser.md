# 05 — Build the term-page parser

## Goal

Extract structured fields from a single term page's HTML. This is the most
nuanced step — the parser is the load-bearing contract between the raw scrape
and the Glossarist YAML.

## Input

Raw HTML as fetched by `ApiClient.fetch_term(termid)`. The relevant slice
is inside `<article class="node node--type-eilvterm ...">`, specifically
the `.field--name-body` div.

## Output: `CieEilv::TermEntry` (value object)

```ruby
module CieEilv
  class TermEntry < Struct.new(
    :termid,
    :designation,        # String, required — the canonical designation
    :usage_info,         # String?, e.g. "psychophysical" — content of first <...>
    :part_of_speech,     # String?, one of: "noun", "adj", "verb", "pl", nil
    :symbol,             # String?, from the 2nd TermEntry paragraph if present
    :definition,         # String, required — definition text (HTML-light)
    :notes,              # Array<String> — note bodies, "Note N to entry: " stripped
    :cross_refs,         # Array<String> — termids referenced via /eilvterm/<id> anchors
    :raw_html,           # String — the original .field--name-body inner HTML, for debugging
    keyword_init: true
  )
  end
end
```

## File: `lib/cie_eilv/term_parser.rb`

```ruby
module CieEilv
  class TermParser
    NOTE_LABEL_RE = /\ANote \d+ to entry:\s*/.freeze
    PRIOR_NUMBER_RE = /\AThis entry was numbered ([-0-9.]+) in (IEC 60050-845:1987|CIE S 017:2011)\.\z/.freeze

    # Parse +html+ (a full term page) given +termid+. Returns CieEilv::TermEntry.
    def self.parse(html, termid:)
      doc = Nokogiri::HTML(html)
      body = doc.at_css("article.node--type-eilvterm .field--name-body")
      raise ParseError, "no .field--name-body in term page #{termid}" if body.nil?

      term_entries = body.css("p.TermEntry").to_a
      definition_node = body.at_css("p.Definition")
      note_nodes = body.css("p.Note").to_a

      designation, usage_info, part_of_speech = extract_designation(term_entries.first)
      symbol = term_entries[1] ? clean_text(term_entries[1].text) : nil
      definition = definition_node ? clean_text(definition_node.inner_html) : ""

      notes = note_nodes
        .map { |n| clean_note(n) }
        .reject { |n| n.nil? || n.empty? }

      cross_refs = body.css("a[href^='/eilvterm/']").map { |a|
        a["href"].sub(%r{\A/eilvterm/}, "")
      }.uniq

      TermEntry.new(
        termid: termid,
        designation: designation,
        usage_info: usage_info,
        part_of_speech: part_of_speech,
        symbol: symbol,
        definition: definition,
        notes: notes,
        cross_refs: cross_refs,
        raw_html: body.inner_html
      )
    end

    private

    # Split a <p class="TermEntry"> into (designation, usage_info, part_of_speech).
    # The TermDesc <span>, if present, holds ", <usage> POS" after the designation.
    def self.extract_designation(term_entry_node)
      return ["", nil, nil] if term_entry_node.nil?
      term_desc = term_entry_node.at_css("span.TermDesc")
      designation = clean_text(term_entry_node.clone.tap { |n| n.css("span.TermDesc").remove }.text)

      usage_info = nil
      part_of_speech = nil
      if term_desc
        suffix = clean_text(term_desc.text)
        # suffix starts with ", " — strip it
        suffix = suffix.sub(/\A,\s*/, "")
        # extract first <...> as usage_info
        if suffix =~ /<([^>]+)>/
          usage_info = $1.strip
          suffix = suffix.sub(/<[^>]+>\s*/, "")
        end
        # what remains, if a single word, is the part_of_speech
        part_of_speech = suffix.strip.empty? ? nil : suffix.strip
        # normalize "pl" — leave as-is; the schema distinguishes plural-only
      end
      [designation, usage_info, part_of_speech]
    end

    # Convert an HTML fragment to plain-text-ish markdown for definition/notes.
    # Strip Drupal wrapper tags, collapse whitespace, but preserve <a href="/eilvterm/...">
    # anchors as {id, designation} inline-ref syntax (handled in step 10's CrossRefLinker).
    # Here: just clean text + leave anchors intact (linker runs later).
    def self.clean_text(html_fragment)
      return "" if html_fragment.nil?
      s = html_fragment.to_s
      # Drupal uses <italic> instead of <i> — normalize to <i>
      s = s.gsub(/<italic>/, "<i>").gsub(/<\/italic>/, "</i>")
      # collapse &nbsp;
      s = s.gsub(/&nbsp;/, " ")
      # Nokogiri round-trip to strip outer whitespace
      doc = Nokogiri::HTML::DocumentFragment.parse(s)
      clean_inner_text(doc)
    end

    def self.clean_inner_text(node)
      # Walk the tree; emit text with minimal HTML preserved (<a>, <i>, <sub>, <sup>)
      ...
    end

    def self.clean_note(note_node)
      # Remove the <span class="NoteLabel">Note N to entry: </span> prefix.
      label = note_node.at_css("span.NoteLabel")
      label&.remove
      text = clean_text(note_node.inner_html)
      # strip any leading "Note N to entry: " that survived (belt and suspenders)
      text = text.sub(NOTE_LABEL_RE, "")
      text&.strip
    end
  end
end
```

### Designation extraction — observed variants

Probed against real e-ILV pages (see CLAUDE.md "e-ILV HTML structure"):

| Termid | TermEntry text | TermDesc suffix | designation | usage_info | part_of_speech |
|---|---|---|---|---|---|
| 17-21-012 | `light` | `, <psychophysical> noun` | `light` | `psychophysical` | `noun` |
| 17-21-027 | `spectral` | `, <of a quantity> adj` | `spectral` | `of a quantity` | `adj` |
| 17-21-032 | `source` | `, <of optical radiation>` | `source` | `of optical radiation` | `nil` |
| 17-22-002 | `cones` | `, pl` | `cones` | `nil` | `pl` |
| 17-25-014 | `photometry` | *(no TermDesc span)* | `photometry` | `nil` | `nil` |
| 17-21-025 | `wavelength` | *(no TermDesc)* + 2nd `<p class="TermEntry"><span class="TermDesc"><italic>λ</italic></span></p>` | `wavelength` | `nil` | `nil`, `symbol: "λ"` |

The parser must handle all six cases. The spec table below pins each.

### Note extraction — edge cases

1. **The empty first Note**: every term page has `<p class="Note"></p>` immediately
   after `<p class="Definition">`. The parser must yield `nil` for it and
   `.reject { |n| n.nil? || n.empty? }` filters it out. Verified across
   17-21-012, 17-21-025, 17-29-062.
2. **Multi-paragraph notes**: some notes embed `<br>` line breaks (e.g.
   17-21-025 Note 3 has a `<br>` before the formula). Treat the `<br>` as
   whitespace — collapse to a single space in `clean_text`.
3. **Cross-ref anchors inside notes**: 17-21-012 Note 1 contains
   `<a href="/eilvterm/17-21-002">optical radiation</a>`. Preserve the anchor
   in the note text — `CrossRefLinker` (step 10) rewrites it into
   `{17-21-002, optical radiation}` inline-ref syntax.
4. **Prior-numbering notes**: notes like
   `This entry was numbered 845-01-06 in IEC 60050-845:1987.` are kept verbatim
   in `notes[]`. The transformer (step 07) additionally extracts them into
   `sources[]` — that logic lives in the transformer, not the parser.

### `<italic>` normalization

Drupal emits `<italic>` instead of `<i>`. Nokogiri treats `<italic>` as an
unknown element; `.text` still extracts the inner text, but the markup is lost.
`clean_text` rewrites `<italic>` → `<i>` before the fragment parse so the
Glossarist YAML carries `<i>λ</i>` (renderable as italic in the browser).

## Specs (`spec/term_parser_spec.rb`)

Use saved HTML fixtures per termid. Capture once:

```bash
mkdir -p spec/fixtures/terms
for id in 17-21-012 17-21-025 17-21-027 17-21-032 17-22-002 17-25-014 17-29-062; do
  bundle exec ruby -e "require 'cie_eilv'; File.write('spec/fixtures/terms/$id.html', CieEilv::ApiClient.fetch_term('$id'))"
done
```

Required cases (one `it` block per row of the table above):

1. `parse(...17-21-012...)` → `designation == "light"`,
   `usage_info == "psychophysical"`, `part_of_speech == "noun"`,
   `notes.length == 3`, `notes[0]` starts with `The term "light"`,
   `cross_refs.include?("17-21-002")`.
2. `parse(...17-21-027...)` → `designation == "spectral"`,
   `usage_info == "of a quantity"`, `part_of_speech == "adj"`.
3. `parse(...17-21-032...)` → `usage_info == "of optical radiation"`,
   `part_of_speech == nil`.
4. `parse(...17-22-002...)` → `part_of_speech == "pl"`, `usage_info == nil`.
5. `parse(...17-25-014...)` → no TermDesc span; `usage_info == nil`,
   `part_of_speech == nil`, `designation == "photometry"`.
6. `parse(...17-21-025...)` → `symbol == "λ"`, `notes.length == 7`
   (one of which contains the formula `λ = v / ν`).
7. `parse(...17-29-062...)` → `notes.length == 1` (the prior-numbering note),
   `cross_refs` includes `17-27-001`, `17-30-001`, `17-29-155`, `17-29-068`.
8. **Error case**: `parse("<html></html>", termid: "x")` raises
   `CieEilv::ParseError`.

## Verification

```bash
bundle exec rspec spec/term_parser_spec.rb
bundle exec ruby -e '
  require "cie_eilv"
  html = CieEilv::ApiClient.fetch_term("17-21-012")
  p CieEilv::TermParser.parse(html, termid: "17-21-012")
'
```

The one-liner should print a `TermEntry` struct with `designation: "light"`.

## Do not

- Do NOT extract the prior-numbering info into `sources[]` here. The parser
  is a pure HTML→struct converter. Extraction into Glossarist sources belongs
  to the transformer (step 07).
- Do NOT sort, dedupe, or otherwise munge `cross_refs`. Order matters for
  debugging; dedupe is the only allowed transformation (an anchor may appear
  twice in a note — keep one copy).
- Do NOT silently default `designation` to the termid when TermEntry is
  missing. Raise `ParseError` — a term page without a designation is broken
  upstream and should be investigated, not papered over.
