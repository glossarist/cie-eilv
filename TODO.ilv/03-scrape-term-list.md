# 03 — Scrape the term list

## Goal

Turn the `/e-ilv` listing page into a flat index of `{termid, listing_designation}`
records, written to `reference-docs/scraped/terms/index.json`. This is the
spine of the pipeline — every downstream step iterates over this index.

## Source

`https://cie.co.at/e-ilv` returns a single HTML page listing ALL ~1,300
terms. There is **no pagination**. The relevant markup per row is:

```html
<div><span><strong><a href="/eilvterm/17-21-001">17-21-001</a></strong>&nbsp;&nbsp;electromagnetic radiation, &lt;phenomenon&gt;
</span>
```

The `<a>` text is the termid; the trailing text in the `<span>` (after
`&nbsp;&nbsp;`) is the listing designation — which **includes** the
`, <usage> part-of-speech` suffix when present.

## File: `lib/cie_eilv/term_index.rb`

```ruby
module CieEilv
  class TermIndex
    # Parse +html+ (the /e-ilv listing page body). Returns Array of
    # {termid: String, listing_designation: String} sorted by termid.
    def self.parse(html)
      doc = Nokogiri::HTML(html)
      rows = doc.css(".views-row a[href^='/eilvterm/']")
      rows.map do |a|
        termid = a.text.strip
        span_text = a.parent.text.strip          # the <span> wrapping <strong><a>
        designation = span_text.sub(/\A#{Regexp.escape(termid)}\s*/, "").strip
        { termid: termid, listing_designation: designation }
      end.sort_by { |r| r[:termid] }
    end

    # Read the cached listing page (via ApiClient) and parse it.
    # Returns the same Array as .parse.
    def self.fetch_and_parse
      parse(ApiClient.fetch_listing)
    end
  end
end
```

### Selection strategy

Two candidate selectors both work:

- `.views-row a[href^='/eilvterm/']` (Drupal Views row)
- `article .field--name-body a[href^='/eilvterm/']`

Use the `.views-row` selector — it is narrower and survives unrelated body
links in the page header. The `[href^='/eilvterm/']` guard excludes any
other anchor in the same row (e.g., the "print" link).

### Edge cases to handle

1. **Designation with `, <usage> POS` suffix** (e.g.
   `light, <psychophysical> noun`). Preserve the suffix verbatim — it is a
   cross-check against the per-page parser in step 05.
2. **Designation with `<...>` only** (e.g. `source, <of optical radiation>` —
   no part of speech). Preserve.
3. **Designation with `pl` only** (e.g. `cones, pl`, `basic colour names, pl`).
   Preserve.
4. **Designation containing the termid twice** — defensive: some Drupal
   templates echo the termid. The `.sub(/\A#{termid}\s*/, "")` strips a
   leading occurrence only.
5. **HTML entities** — `&lt;`, `&gt;`, `&nbsp;`, `&amp;`. Nokogiri's `.text`
   decodes them automatically. Do not re-encode.

## File: `scripts/scrape_term_list.rb`

Thin entry point:

```ruby
#!/usr/bin/env ruby
require "cie_eilv"
require "json"
require "fileutils"

OUT = "reference-docs/scraped/terms/index.json"
FileUtils.mkdir_p(File.dirname(OUT))

records = CieEilv::TermIndex.fetch_and_parse
File.write(OUT, JSON.pretty_generate(records))

puts "Wrote #{records.length} terms to #{OUT}"
puts "First: #{records.first.inspect}"
puts "Last:  #{records.last.inspect}"
```

## Specs (`spec/term_index_spec.rb`)

Use a saved HTML fixture (`spec/fixtures/e-ilv-listing.html`) instead of
hitting the network on every spec run. Capture the fixture once:

```bash
mkdir -p spec/fixtures
bundle exec ruby -e 'require "cie_eilv"; File.write("spec/fixtures/e-ilv-listing.html", CieEilv::ApiClient.fetch_listing)'
```

Cases:

1. `parse(File.read("spec/fixtures/e-ilv-listing.html"))` returns ~1,300 records.
2. First record is `{termid: "17-21-001", listing_designation: "electromagnetic radiation, <phenomenon>"}`.
3. The `light, <psychophysical> noun` entry (termid `17-21-012`) appears with
   its full suffix preserved.
4. A `pl`-only entry like `cones, pl` (termid `17-22-002`) is preserved.
5. Every `termid` matches `/\A17-\d{2}-\d{3}\z/` — fails loudly if a row
   matched by the selector has a malformed id (catches template drift).
6. Termids are unique (no duplicates from the row selector).

## Verification

```bash
bundle exec rspec spec/term_index_spec.rb
bundle exec ruby scripts/scrape_term_list.rb
jq 'length' reference-docs/scraped/terms/index.json   # ~1300
jq '.[0], .[-1]' reference-docs/scraped/terms/index.json
```

The number of terms must match what you see by eye on `https://cie.co.at/e-ilv`.
Spot-check the first and last entries against the listing page in a browser.

## Do not

- Do NOT filter out terms by section in this step. Every term in the listing
  is scraped. Section filtering happens at the register-building stage (step 09)
  and only for display grouping, never for exclusion.
- Do NOT strip the `, <usage> POS` suffix here. It is a sanity-check signal
  for the transformer.
- Do NOT encode HTML entities back into the JSON. `JSON.generate` handles
  UTF-8 cleanly.
