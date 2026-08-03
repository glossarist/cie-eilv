# frozen_string_literal: true

module CieEilv
  module Archive2011
    # Adds a "superseded by" ConceptSource to each cie-2011 concept that
    # has a cie-2020 sibling. Enables reverse navigation: the concept
    # browser can render "Superseded by 17-21-067 in the 2020 edition"
    # from cie-2011 concept pages.
    #
    # The cross-edition map is read from cie-2020's prior-numbering
    # sources[]. Forward direction (cie-2020 → cie-2011) was already
    # encoded by the 2020 transformer; this closes the reverse path.
    #
    # Idempotent.
    class CrossEditionLinker
      LEGACY_ID_RE = /17-(\d+)/.freeze

      attr_reader :stats

      def initialize(concepts_dir: Paths::CONCEPTS_DIR,
                     cie_2020_concepts_dir: CieEilv::Paths::CONCEPTS_DIR)
        @concepts_dir = concepts_dir
        @cie_2020_concepts_dir = cie_2020_concepts_dir
        @stats = { linked: 0, skipped: 0 }
      end

      def run!
        @map_2011_to_2020 = build_cross_edition_map
        warn "Archive2011::CrossEditionLinker: #{@map_2011_to_2020.length} cie-2011 IDs map to cie-2020"

        each_concept_file do |path|
          process_file(path)
        end
        warn "Archive2011::CrossEditionLinker: linked=#{stats[:linked]} skipped=#{stats[:skipped]}"
      end

      private

      def build_cross_edition_map
        map = {}
        Dir.glob(File.join(@cie_2020_concepts_dir, "*.yaml")).sort.each do |path|
          cf = ConceptFile.read(path)
          eng = cf.find_localized("eng")
          next unless eng

          termid_2020 = cf.managed&.data&.id
          next unless termid_2020

          eng.data.sources.each do |src|
            next unless src.origin&.ref&.source == "CIE S 017:2011"
            legacy = src.origin.ref.id.to_s
            legacy.scan(LEGACY_ID_RE) { |m| map[m[0]] = termid_2020 }
          end
        end
        map
      end

      def process_file(path)
        archive_id = File.basename(path, ".yaml").sub(/\A17-/, "")
        termid_2020 = @map_2011_to_2020[archive_id]

        if termid_2020.nil?
          @stats[:skipped] += 1
          return
        end

        cf = ConceptFile.read(path)
        eng = cf.find_localized("eng")
        return unless eng

        # Skip if the source already exists (idempotent).
        existing = source_ids_for(eng, termid_2020)
        unless existing.empty?
          @stats[:skipped] += 1
          return
        end

        source = build_supersession_source(termid_2020)
        eng.data.sources << source
        cf.managed&.sources&.<<(source)

        cf.save
        @stats[:linked] += 1
      rescue StandardError => e
        warn "  17-#{archive_id}: #{e.message}"
        @stats[:skipped] += 1
      end

      def source_ids_for(eng, termid_2020)
        ids = Set.new
        [eng.data.sources, eng.data.respond_to?(:managed) ? nil : nil].compact.each do |coll|
          next unless coll.respond_to?(:each)
          coll.each { |s| ids << s.origin&.ref&.id if s.origin&.ref&.source == "CIE S 017:2020" }
        end
        ids
      end

      def build_supersession_source(termid_2020)
        Glossarist::V3::ConceptSource.new(
          type: "authoritative",
          origin: Glossarist::V3::Citation.new(
            ref: Glossarist::Citation::Ref.new(source: "CIE S 017:2020", id: termid_2020)
          )
        )
      end

      def each_concept_file
        Dir.glob(File.join(@concepts_dir, "*.yaml")).sort.each { |p| yield p }
      end
    end
  end
end
