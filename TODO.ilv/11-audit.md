# 11 — Audit

## Goal

Per-concept and per-dataset invariant validation. CI gate: the GH Pages
build fails closed if the audit exits non-zero. Catches transformer drift,
broken cross-refs, and missing fields before they reach production.

## File: `lib/cie_eilv/auditor.rb`

```ruby
module CieEilv
  class Auditor
    CONCEPTS_DIR = "datasets/cie-2020/concepts".freeze

    def run!
      errors = []
      termids_seen = {}

      each_concept_file do |path|
        cf = ConceptFile.new(path)
        errors.concat(validate_managed(cf, path, termids_seen))
        errors.concat(validate_localized(cf, path))
        errors.concat(validate_cross_refs(cf, path))
      end

      errors.concat(validate_dataset_invariants(termids_seen))

      if errors.empty?
        $stderr.puts "Audit: OK"
        0
      else
        $stderr.puts "Audit: #{errors.length} error(s)"
        errors.each { |e| $stderr.puts "  - #{e}" }
        1
      end
    end

    private

    def each_concept_file
      Dir.glob("#{CONCEPTS_DIR}/*.yaml").each { |p| yield p }
    end

    def validate_managed(cf, path, termids_seen)
      errs = []
      m = cf.managed
      if m.nil?
        errs << "#{path}: missing managed concept (doc 1)"
        return errs
      end
      if m.termid.nil? || m.termid.to_s.empty?
        errs << "#{path}: managed termid is empty"
      elsif !m.termid.to_s.match?(/\A17-\d{2}-\d{3}\z/)
        errs << "#{path}: malformed termid '#{m.termid}'"
      elsif termids_seen.key?(m.termid)
        errs << "#{path}: duplicate termid #{m.termid} (also in #{termids_seen[m.termid]})"
      else
        termids_seen[m.termid] = path
      end

      if m.status.nil?
        errs << "#{path}: managed status is empty"
      end
      if m.sources.nil? || m.sources.empty?
        errs << "#{path}: managed sources[] is empty"
      end
      errs
    end

    def validate_localized(cf, path)
      errs = []
      loc = cf.find_localized(:eng)
      if loc.nil?
        errs << "#{path}: no eng localized concept"
        return errs
      end
      if loc.terms.nil? || loc.terms.empty?
        errs << "#{path}: terms[] is empty"
      else
        loc.terms.each_with_index do |t, i|
          if t.designation.nil? || t.designation.to_s.empty?
            errs << "#{path}: terms[#{i}].designation is empty"
          end
          if t.normative_status.nil?
            errs << "#{path}: terms[#{i}].normative_status is empty"
          end
        end
      end
      if loc.definition.nil? || loc.definition.empty? || loc.definition.all? { |d| d[:content].to_s.empty? }
        errs << "#{path}: definition has no content"
      end
      errs
    end

    # Every {17-XX-YYY, ...} cross-ref in definitions and notes must
    # resolve to a real concept file in the dataset.
    def validate_cross_refs(cf, path)
      errs = []
      loc = cf.find_localized(:eng)
      return errs if loc.nil?
      refs = extract_refs(loc)
      refs.each do |ref|
        target = File.join(CONCEPTS_DIR, "#{ref}.yaml")
        unless File.exist?(target)
          errs << "#{path}: cross-ref to #{ref} does not resolve (no #{ref}.yaml)"
        end
      end
      errs
    end

    def extract_refs(loc)
      refs = []
      inline_ref_re = /\{([0-9]{2}-[0-9]{2}-[0-9]{3})\b[^}]*\}/
      (loc.definition || []).each do |d|
        d[:content].to_s.scan(inline_ref_re) { |m| refs << m.first }
      end
      (loc.notes || []).each do |n|
        n[:content].to_s.scan(inline_ref_re) { |m| refs << m.first }
      end
      refs.uniq
    end

    def validate_dataset_invariants(termids_seen)
      errs = []
      index_path = "reference-docs/scraped/terms/index.json"
      if File.exist?(index_path)
        index = JSON.parse(File.read(index_path))
        index_termids = index.map { |e| e["termid"] }.to_set
        disk_termids = termids_seen.keys.to_set
        missing = index_termids - disk_termids
        missing.each do |t|
          errs << "index.json lists #{t} but no concept file exists"
        end
        extra = disk_termids - index_termids
        extra.each do |t|
          errs << "concept file #{t}.yaml exists but is not in index.json"
        end
      end
      errs
    end
  end
end
```

## File: `scripts/audit_terms.rb`

```ruby
#!/usr/bin/env ruby
require "cie_eilv"

exit CieEilv::Auditor.new.run!
```

### Validation rules

**Per-concept (managed):**
- `termid` present, matches `17-XX-YYY` regex.
- `termid` is unique across the dataset.
- `status` present (typically `:valid`).
- `sources[]` non-empty (authoritative source link to `cie.co.at/eilvterm/<id>`).

**Per-concept (localized eng):**
- An `eng` localized concept exists.
- `terms[]` non-empty; each term has `designation` and `normative_status`.
- `definition[]` has at least one entry with non-empty content.

**Cross-concept refs:**
- Every `{17-XX-YYY, ...}` inline ref resolves to a real `<termid>.yaml`
  file in the dataset.

**Dataset-level invariants:**
- The set of termids on disk matches the set in `reference-docs/scraped/terms/index.json`.
  Catches both missing transforms (term in index, no file) and orphaned
  concepts (file exists, not in index — usually a rename or deletion upstream).

### Non-zero exit code

`run!` returns 0 on success, 1 on errors. `scripts/audit_terms.rb` uses
`exit` with that code, so a CI step `bundle exec ruby scripts/audit_terms.rb`
will fail the build on audit errors.

### Why exit code, not exception

An audit "failure" is not a crash — it's data drift. The script should
print all errors (not halt on the first), then exit non-zero. The CI
runner translates exit code → pass/fail.

## Specs (`spec/auditor_spec.rb`)

Use `Dir.mktmpdir` and write minimal valid + invalid fixtures.

Cases:

1. Valid concept file (matches the 17-21-012 sample) → no errors.
2. Missing `termid` → 1 error matching `/termid is empty/`.
3. Malformed `termid` (`17-99-9`) → 1 error matching `/malformed termid/`.
4. Duplicate `termid` across two files → 2 errors (one per file), each
   mentioning the other file.
5. Localized concept with empty `definition` → 1 error matching
   `/definition has no content/`.
6. Concept file with a cross-ref to `17-99-999` (no target file) →
   1 error matching `/cross-ref.*does not resolve/`.
7. Disk has a concept file not in `index.json` → 1 error matching
   `/not in index.json/`.
8. Audit returns integer 0 on success, integer 1 on errors (not booleans).

## Verification

```bash
bundle exec rspec spec/auditor_spec.rb
bundle exec ruby scripts/audit_terms.rb
echo "exit code: $?"   # must be 0
```

CI workflow (step 12) wires this in as a build gate.

## Do not

- Do NOT halt on first error. The auditor's value is in showing all
   problems at once — fixing them iteratively.
- Do NOT auto-fix the errors it reports. The auditor is read-only.
   Fix the upstream script (transformer, linker, scraper) and re-run.
- Do NOT warn at non-zero exit. Errors block the build; warnings don't.
   If something is genuinely informational, log it to stderr at exit 0.
