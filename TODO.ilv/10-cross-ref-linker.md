# 10 — Cross-reference linker

## Goal

Rewrite the `<a href="/eilvterm/17-XX-YYY">designation</a>` anchors that
appear inside `definition` and `notes` content into Glossarist inline-ref
syntax `{17-XX-YYY, designation}`, so the concept-browser can render them
as hyperlinks to the target concept.

This is a **second pass** over the dataset, after `transform_terms.rb`
has written all the YAML files. It must be **idempotent** — re-running on
already-linked data touches zero files.

## Why a separate pass

`transform_terms.rb` preserves anchors verbatim because the target concept
file may not exist yet (concepts are written one at a time, in termid
order, and a definition can reference a later termid). The linker runs
after all files exist, so it can resolve every reference.

Separating concerns also makes the transformer simpler: it does
HTML→struct→YAML only, no cross-resolution logic.

## File: `lib/cie_eilv/cross_ref_linker.rb`

```ruby
module CieEilv
  class CrossRefLinker
    CONCEPTS_DIR = "datasets/cie-2020/concepts".freeze
    ANCHOR_RE = /<a\s+href="\/eilvterm\/(17-\d{2}-\d{3})"[^>]*>(.*?)<\/a>/m.freeze

    def run!
      designations = load_designation_index   # termid → designation

      touched = 0
      each_concept_file do |cf|
        changed = false
        cf.localized.each do |loc|
          next if loc.language_code != :eng
          rewrite_field(loc, :definition, designations) { |c| loc.changed? || c }
          # Operate on definition and notes arrays of {content: "..."}
          if rewrite_definition(loc, designations)
            changed = true
          end
          if rewrite_notes(loc, designations)
            changed = true
          end
        end
        if changed
          cf.mark_dirty!
          touched += 1
        end
        cf.save!
      end
      $stderr.puts "CrossRefLinker: touched #{touched} files"
      touched
    end

    private

    # Build termid → designation map from the on-disk YAML files.
    # Reads only the first term of each localized concept's first doc.
    def load_designation_index
      idx = {}
      Dir.glob("#{CONCEPTS_DIR}/*.yaml").each do |path|
        cf = ConceptFile.new(path)
        loc = cf.find_localized(:eng)
        next unless loc && loc.terms&.first
        termid = cf.managed.termid
        idx[termid] = loc.terms.first.designation
      end
      idx
    end

    def each_concept_file
      Dir.glob("#{CONCEPTS_DIR}/*.yaml").each do |path|
        yield ConceptFile.new(path)
      end
    end

    # Returns true if any definition content was rewritten.
    def rewrite_definition(loc, designations)
      changed = false
      loc.definition ||= []
      loc.definition.each do |entry|
        new = rewrite_string(entry[:content], designations)
        if new != entry[:content]
          entry[:content] = new
          changed = true
        end
      end
      changed
    end

    # Returns true if any note content was rewritten.
    def rewrite_notes(loc, designations)
      changed = false
      loc.notes ||= []
      loc.notes.each do |entry|
        new = rewrite_string(entry[:content], designations)
        if new != entry[:content]
          entry[:content] = new
          changed = true
        end
      end
      changed
    end

    # Replace each <a href="/eilvterm/ID">text</a> with {ID, text}.
    # If text contains the designation from the index, prefer the index's
    # canonical designation (handles minor whitespace drift).
    def rewrite_string(str, designations)
      return str if str.nil?
      str.gsub(ANCHOR_RE) do |match|
        termid = $1
        anchor_text = $2.strip
        designation = designations[termid] || anchor_text
        "{#{termid}, #{designation}}"
      end
    end
  end
end
```

## File: `scripts/link_cross_refs.rb`

```ruby
#!/usr/bin/env ruby
require "cie_eilv"

touched = CieEilv::CrossRefLinker.new.run!
puts "Done. #{touched} files updated."
```

### Glossarist inline-ref syntax

The concept-browser's `extractInlineRefs` recognizes a `{ref, designation}`
form (single-brace) and a `{{ref, designation}}` form (double-brace). The
single-brace form requires a `refPrefixMap` config entry for the ref type;
the double-brace form is dispatched by `parseMention` kind without config.

**Verify the exact syntax** by inspecting the concept-browser source or
an IALA concept file that already uses cross-refs:

```bash
grep -rn '{17-' ../iala-vocab/datasets/iala-2023/concepts/ | head -5
grep -rn '{{17-' ../iala-vocab/datasets/iala-2023/concepts/ | head -5
```

IALA's `transform_iala.rb` uses `{{termid, designation}}` (double-brace)
for numeric mentions. Match that convention here.

### Idempotency

After the first run, the YAML contains `{17-21-002, optical radiation}`
— no more `<a href="/eilvterm/...">` anchors. Re-running the linker:

1. `load_designation_index` still works (reads from YAML).
2. `ANCHOR_RE` finds zero matches (no anchors left).
3. `rewrite_string` returns the input unchanged.
4. `cf.dirty?` stays false; `save!` writes nothing.

Verify with a spec: run the linker twice, assert zero writes on the
second run.

### Cross-refs to missing concepts

If a definition references `17-99-999` which doesn't exist in the dataset
(shouldn't happen with the live e-ILV, but defensive), `load_designation_index`
returns `nil` for that termid and `rewrite_string` falls back to the anchor
text as the designation. The auditor (step 11) catches this as a
"cross-concept ref does not resolve" error.

## Specs (`spec/cross_ref_linker_spec.rb`)

Use `Dir.mktmpdir` + small fixture YAML files (2–3 concepts that reference
each other).

Cases:

1. Two concepts A and B, A's definition contains
   `<a href="/eilvterm/B">b's name</a>`. After `run!`, A's definition
   contains `{B, b's name}` and B is untouched.
2. Re-running `run!` on the post-link dataset touches zero files
   (idempotency).
3. Anchor with attribute order variation (`<a class="x" href="/eilvterm/B">`)
   is still rewritten.
4. Anchor whose text doesn't match the target's canonical designation is
   rewritten using the canonical designation from the index (text drift
   tolerance).
5. Concept with no cross-refs is untouched.

## Verification

```bash
bundle exec rspec spec/cross_ref_linker_spec.rb
bundle exec ruby scripts/link_cross_refs.rb
grep -rn '{17-' datasets/cie-2020/concepts/ | head -5
grep -rn 'eilvterm/' datasets/cie-2020/concepts/ | head -5   # should be empty
```

The second grep (anchors still present) should return zero matches after
the linker runs.

## Do not

- Do NOT rewrite anchors in the `notes` field's prior-numbering notes.
   Those reference IEC 60050 / CIE S 017:2011 ids, not `/eilvterm/` URLs,
   so they're not matched by `ANCHOR_RE` anyway — but be explicit.
- Do NOT rewrite the `<a href="...">ciecb@cie.co.at</a>` mailto-style
   anchors in boilerplate. The selector `href^='/eilvterm/'` excludes them.
- Do NOT batch the linker with the transformer. They are separate passes
   for a reason — the linker needs the full dataset loaded to resolve refs.
