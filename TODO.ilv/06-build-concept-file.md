# 06 — Build the ConceptFile abstraction

## Goal

A thin wrapper around Glossarist v3 multi-doc YAML streams with dirty tracking.
The transformer (step 07) uses it to write per-concept files; the linker
(step 10) and auditor (step 11) use it to read+modify+write back.

## Why a wrapper

Glossarist's `Glossarist::V3::*` model classes handle serialization, but a
concept file on disk is a **multi-doc YAML stream** (managed concept doc +
N localized concept docs). The wrapper:

1. Parses the stream into a list of model instances.
2. Tracks which docs were modified (`dirty?`).
3. Writes back only if dirty (idempotent re-runs of the linker).
4. Provides a stable API the rest of the lib targets, decoupled from
   Glossarist internals.

## File: `lib/cie_eilv/concept_file.rb`

```ruby
module CieEilv
  class ConceptFile
    attr_reader :path, :docs

    # Load +path+ (a multi-doc YAML stream). +docs+ is an Array of
    # Glossarist::V3::ManagedConcept or LocalizedConcept instances.
    def initialize(path)
      @path = path
      @docs = load_docs
      @dirty = false
    end

    def dirty? = @dirty

    # Mark dirty; called by callers after mutating +docs+.
    def mark_dirty! = @dirty = true

    # The managed concept (first doc).
    def managed = docs.first

    # Localized concepts (all docs after the first).
    def localized = docs[1..] || []

    # Find a localized doc by language_code.
    def find_localized(lang) = localized.find { |d| d.language_code == lang }

    # Append a localized doc, mark dirty.
    def append_localized(doc)
      docs << doc
      mark_dirty!
    end

    # Write back to +path+ if dirty. Multi-doc YAML: "---\n" + per-doc YAML,
    # joined by "\n". Returns true if written, false if skipped (not dirty).
    def save!
      return false unless dirty?
      stream = docs.map { |d| YAML.dump(d.to_h) }.join
      File.write(path, stream)
      @dirty = false
      true
    end

    private

    def load_docs
      return [] unless File.exist?(path)
      raw = File.read(path)
      YAML.load_stream(raw).map do |hash|
        # Distinguish managed vs localized by presence of :language_code
        # (managed concepts have no language_code).
        if hash.key?(:language_code) || hash.key?("language_code")
          Glossarist::V3::LocalizedConcept.from_hash(hash)
        else
          Glossarist::V3::ManagedConcept.from_hash(hash)
        end
      end
    end
  end
end
```

### Why this is NOT hand-rolled serialization

`ConceptFile` does not define `to_h` / `from_h` on a model class. It calls
the framework's `to_h` / `from_hash` on `Glossarist::V3::*` instances. The
wrapper just orchestrates stream-level read/write. This is the boundary the
global CLAUDE.md allows.

If at any point you're tempted to add `def to_h` to `ConceptFile` itself —
stop. ConceptFile is not a model; it's a file handle. Callers that need the
hash use `cf.managed.to_h` / `cf.localized.map(&:to_h)`.

### Multi-doc YAML stream format

Ruby's `YAML.dump(obj)` prepends `---`. Joining `YAML.dump(d1)` and
`YAML.dump(d2)` already produces a valid stream:

```
---
id: 17-21-012
termid: 17-21-012
...
---
id: 17-21-012-eng
language_code: eng
...
```

Do NOT add a leading `---` manually — `YAML.dump` does it. (IALA's
`transform_iala.rb` has belt-and-suspenders code that adds `---` anyway;
we don't need to copy that quirk.)

### Dirty tracking semantics

- Initial load: `dirty? == false`.
- Caller mutates `docs[i]` directly → caller must call `mark_dirty!`. The
  wrapper does not intercept mutations (no `method_missing` magic).
- `append_localized` and similar helpers call `mark_dirty!` internally.
- `save!` is a no-op when `dirty? == false`. The linker relies on this
  for idempotency.

## Specs (`spec/concept_file_spec.rb`)

Use **real** `Glossarist::V3::*` instances. No doubles.

Cases:

1. **Round-trip**: build a `ManagedConcept` + one `LocalizedConcept`, write
   via `ConceptFile.new(path).save!`, reload, verify the loaded `docs`
   equal the originals (compare `to_h` of each).
2. **Dirty on append**: after `append_localized(...)`, `dirty? == true`;
   after `save!`, `dirty? == false`.
3. **No-write when clean**: `ConceptFile.new(path)` of an existing file,
   call `save!` without changes, returns `false`, file mtime unchanged.
4. **Distinguish managed vs localized**: load a real fixture, verify
   `managed.is_a?(Glossarist::V3::ManagedConcept)`,
   `localized.first.is_a?(Glossarist::V3::LocalizedConcept)`.
5. **`find_localized("eng")`** returns the English doc, `find_localized("deu")`
   returns `nil` (this repo is English-only).

Use `Dir.mktmpdir` for the write path; clean up in `after(:each)`.

## Verification

```bash
bundle exec rspec spec/concept_file_spec.rb
```

All cases pass. No network needed.

## Do not

- Do NOT subclass `Glossarist::V3::ManagedConcept` or `LocalizedConcept`.
   Compose, don't inherit — the framework classes are not designed for
   subclassing and you'd be locked into their internal shape.
- Do NOT add per-attribute accessor shortcuts like `cf.termid`. Force
   callers to go through `cf.managed.termid` — explicit is better than
   magic delegation here.
- Do NOT swallow `YAML.load_stream` errors. If a concept file is corrupt,
   raise loudly; the auditor (step 11) reports it, but the file loader
   itself must not silently return `[]`.
