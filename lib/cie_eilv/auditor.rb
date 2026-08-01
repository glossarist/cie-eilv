# frozen_string_literal: true

require "json"

module CieEilv
  # Per-concept, per-dataset, and cross-reference invariant validation.
  # CI gate: scripts/audit_terms.rb exits non-zero on any error, blocking
  # the GH Pages deploy.
  #
  # Read-only: never mutates the dataset. Fix the upstream script (transformer,
  # linker, scraper) and re-run.
  class Auditor
    class << self
      def run!(...)
        new(...).run!
      end
    end

    CONCEPTS_DIR = Paths::CONCEPTS_DIR
    INDEX_PATH   = Paths::INDEX_PATH
    TERMID_RE    = /\A17-\d{2}-\d{3}\z/.freeze

    def initialize(concepts_dir: CONCEPTS_DIR, index_path: INDEX_PATH, io: $stderr)
      @concepts_dir = concepts_dir
      @index_path = index_path
      @io = io
    end

    # Validates the dataset. Returns 0 on success (or warnings-only),
    # 1 on any hard error. Warnings are printed to stderr but do not block.
    def run!
      errors = []
      warnings = []
      termids_seen = {}

      each_concept_file do |path|
        file_errs, file_warns = validate_file(path, termids_seen)
        errors.concat(file_errs)
        warnings.concat(file_warns)
      end

      errors.concat(validate_dataset_invariants(termids_seen))

      warnings.each { |w| @io.puts "  WARN: #{w}" }

      if errors.empty?
        @io.puts "Audit: OK (#{termids_seen.length} concepts, #{warnings.length} warning(s))"
        0
      else
        @io.puts "Audit: #{errors.length} error(s) across #{termids_seen.length} concepts"
        errors.each { |e| @io.puts "  - #{e}" }
        1
      end
    end

    private

    def each_concept_file
      Dir.glob("#{@concepts_dir}/*.yaml").each { |p| yield p }
    end

    def validate_file(path, termids_seen)
      errs = []
      warnings = []
      cf = ConceptFile.read(path)

      errs.concat(validate_managed(cf, path, termids_seen))
      loc_errs, loc_warns = validate_localized(cf, path)
      errs.concat(loc_errs)
      warnings.concat(loc_warns)
      [errs, warnings]
    rescue StandardError => e
      errs << "#{File.basename(path)}: load failed: #{e.class}: #{e.message}"
      [errs, warnings]
    end

    def validate_managed(cf, path, termids_seen)
      file_name = File.basename(path)
      errs = []
      m = cf.managed
      if m.nil?
        errs << "#{file_name}: missing managed concept (doc 1)"
        return errs
      end

      termid = m.data&.id
      if termid.nil? || termid.to_s.empty?
        errs << "#{file_name}: managed data.id is empty"
      elsif termid.to_s !~ TERMID_RE
        errs << "#{file_name}: malformed termid #{termid.inspect}"
      elsif termids_seen.key?(termid)
        errs << "#{file_name}: duplicate termid #{termid} (also in #{termids_seen[termid]})"
      else
        termids_seen[termid] = file_name
      end

      errs << "#{file_name}: status is empty" if m.status.nil? || m.status.to_s.empty?
      errs << "#{file_name}: sources[] is empty" if m.sources.nil? || m.sources.empty?
      errs
    end

    # Returns [errs, warnings]. Hard errors block the build; warnings don't.
    # An empty definition is a warning (upstream data quirk we cannot fix);
    # missing eng localized concept, empty terms[], or empty designation are
    # hard errors (the pipeline itself failed to produce valid output).
    def validate_localized(cf, path)
      errs = []
      warnings = []
      file_name = File.basename(path)
      eng = cf.find_localized("eng")
      if eng.nil?
        errs << "#{file_name}: no eng localized concept"
        return [errs, warnings]
      end

      terms = eng.data&.terms || []
      if terms.empty?
        errs << "#{file_name}: terms[] is empty"
      else
        terms.each_with_index do |term, i|
          if term.designation.nil? || term.designation.to_s.empty?
            errs << "#{file_name}: terms[#{i}].designation is empty"
          end
        end
      end

      definition = eng.data&.definition || []
      if definition.empty? || definition.all? { |d| d.content.to_s.strip.empty? }
        warnings << "#{file_name}: definition has no content (upstream data quirk)"
      end

      [errs, warnings]
    end

    def validate_dataset_invariants(termids_seen)
      errs = []
      return errs unless File.exist?(@index_path)

      index = JSON.parse(File.read(@index_path))
      index_termids = index.map { |e| e["termid"] }.to_set
      disk_termids = termids_seen.keys.to_set

      (index_termids - disk_termids).each do |t|
        errs << "index.json lists #{t} but no concept file exists"
      end
      (disk_termids - index_termids).each do |t|
        errs << "#{t}.yaml exists on disk but is not in index.json"
      end
      errs
    end
  end
end
