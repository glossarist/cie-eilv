# frozen_string_literal: true

module CieEilv
  module Archive2011
    # Adds a "superseded_by" related entry to each cie-2011 concept that
    # has a cie-2020 sibling. Enables reverse navigation: the concept
    # browser can render "Superseded by 17-21-067 in the 2020 edition"
    # from cie-2011 concept pages.
    #
    # The cross-edition map is read from cie-2020's prior-numbering
    # sources[]. Forward direction (cie-2020 → cie-2011) was already
    # encoded by the 2020 transformer; this closes the reverse path.
    #
    # The relationship is stored in `related[]` (type: superseded_by),
    # NOT in `sources[]`. Putting it in sources[] would be anachronistic:
    # a 2011-edition concept cannot have a 2020-edition document as an
    # authoritative source — the 2020 standard didn't exist when the
    # 2011 concept was published.
    #
    # Idempotent. Re-running on already-processed concepts touches zero
    # files (the related entry is detected and skipped).
    class CrossEditionLinker
      LEGACY_ID_RE = /17-(\d+)/.freeze
      SUPSEREDED_BY = "superseded_by".freeze

      attr_reader :stats

      def initialize(concepts_dir: Paths::CONCEPTS_DIR,
                     cie_2020_concepts_dir: CieEilv::Paths::CONCEPTS_DIR)
        @concepts_dir = concepts_dir
        @cie_2020_concepts_dir = cie_2020_concepts_dir
        @stats = { linked: 0, skipped: 0, cleaned: 0 }
      end

      def run!
        @map_2011_to_2020 = build_cross_edition_map
        warn "Archive2011::CrossEditionLinker: #{@map_2011_to_2020.length} cie-2011 IDs map to cie-2020"

        each_concept_file do |path|
          process_file(path)
        end
        warn "Archive2011::CrossEditionLinker: linked=#{stats[:linked]} skipped=#{stats[:skipped]} cleaned=#{stats[:cleaned]}"
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

        cf = ConceptFile.read(path)
        managed = cf.managed
        return unless managed

        changed = false

        # 1. Clean anachronistic "CIE S 017:2020" entries from managed
        #    and localized sources[]. A 2011 concept's authoritative
        #    sources can only be 2011-or-earlier documents.
        if needs_anachronism_cleanup?(managed.sources)
          managed.sources = filter_anachronistic(managed.sources)
          changed = true
        end
        cf.localized.each do |lc|
          src = lc.data.sources
          next unless needs_anachronism_cleanup?(src)
          # Rebuild via the data object's setter.
          lc.data.sources = filter_anachronistic(src)
          changed = true
        end

        # 2. Add the superseded_by related entry.
        if termid_2020
          related_changed = add_superseded_by!(managed, termid_2020)
          changed |= related_changed
          @stats[:linked] += 1 if related_changed
        end

        @stats[:skipped] += 1 unless changed
        cf.save if changed
      rescue StandardError => e
        warn "  17-#{archive_id}: #{e.message}"
        @stats[:skipped] += 1
      end

      def needs_anachronism_cleanup?(sources)
        return false unless sources.respond_to?(:each)
        sources.any? do |s|
          s.respond_to?(:origin) && s.origin&.ref&.source == "CIE S 017:2020"
        end
      end

      def filter_anachronistic(sources)
        kept = sources.reject do |s|
          s.respond_to?(:origin) && s.origin&.ref&.source == "CIE S 017:2020"
        end
        dropped = sources.respond_to?(:size) ? sources.size - kept.length : sources.to_a.length - kept.length
        @stats[:cleaned] += dropped
        kept
      end

      def add_superseded_by!(managed, termid_2020)
        # managed.related is nil for concepts that didn't have any
        # related entries in their YAML. Initialize as empty array.
        related = managed.related || []

        # Skip if the entry already exists.
        existing = related.any? do |r|
          r.type == SUPSEREDED_BY &&
            r.ref&.source == "CIE S 017:2020" &&
            r.ref&.id == termid_2020
        end
        return false if existing

        new_rel = Glossarist::V3::RelatedConcept.new(
          type: SUPSEREDED_BY,
          ref: Glossarist::V3::ConceptRef.new(
            source: "CIE S 017:2020",
            id: termid_2020
          )
        )
        related << new_rel
        managed.related = related
        true
      rescue StandardError => e
        warn "    add_superseded_by! failed: #{e.message}"
        false
      end

      def each_concept_file
        Dir.glob(File.join(@concepts_dir, "*.yaml")).sort.each { |p| yield p }
      end
    end
  end
end
