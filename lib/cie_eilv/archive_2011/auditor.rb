# frozen_string_literal: true

require "json"

module CieEilv
  module Archive2011
    # Per-concept and per-dataset invariant validation for cie-2011.
    # Mirrors the 2020 Auditor's contract but with the 2011 termid shape
    # (17-XXXX, single 1+ digit suffix instead of 17-XX-YYY).
    class Auditor
      class << self
        def run!(...)
          new(...).run!
        end
      end

      CONCEPTS_DIR = Paths::CONCEPTS_DIR
      INDEX_PATH   = Paths::INDEX_PATH
      # 17- followed by 1-4 digits. The 2011 IDs go up to ~17-1448.
      TERMID_RE    = /\A17-\d{1,4}\z/.freeze

      def initialize(concepts_dir: CONCEPTS_DIR, index_path: INDEX_PATH, io: $stderr)
        @concepts_dir = concepts_dir
        @index_path = index_path
        @io = io
      end

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
          @io.puts "Archive2011 Audit: OK (#{termids_seen.length} concepts, #{warnings.length} warning(s))"
          0
        else
          @io.puts "Archive2011 Audit: #{errors.length} error(s) across #{termids_seen.length} concepts"
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
        file_name = File.basename(path)
        begin
          cf = CieEilv::ConceptFile.read(path)
        rescue StandardError => e
          errs << "#{file_name}: load failed: #{e.class}: #{e.message}"
          return [errs, warnings]
        end

        errs.concat(validate_managed(cf, file_name, termids_seen))
        loc_errs, loc_warns = validate_localized(cf, file_name)
        errs.concat(loc_errs)
        warnings.concat(loc_warns)
        [errs, warnings]
      end

      def validate_managed(cf, file_name, termids_seen)
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

      def validate_localized(cf, file_name)
        errs = []
        warnings = []
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
          warnings << "#{file_name}: definition has no content (alias entry or upstream quirk)"
        end

        [errs, warnings]
      end

      def validate_dataset_invariants(termids_seen)
        errs = []
        return errs unless File.exist?(@index_path)

        index = JSON.parse(File.read(@index_path))
        index_ids = index.map { |e| "17-#{e['archive_id']}" }.to_set
        disk_ids = termids_seen.keys.to_set

        (index_ids - disk_ids).each do |t|
          errs << "index.json lists #{t} but no concept file exists"
        end
        (disk_ids - index_ids).each do |t|
          errs << "#{t}.yaml exists on disk but is not in index.json"
        end
        errs
      end
    end
  end
end
