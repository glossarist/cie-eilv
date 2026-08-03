# frozen_string_literal: true

require "set"

module CieEilv
  module Archive2011
    # Derives a real section mapping for cie-2011 concepts via the
    # cross-edition map: cie-2011 archive_id → cie-2020 termid →
    # cie-2020 section prefix (the middle two digits of 17-XX-YYY).
    #
    # For cie-2011 concepts without a cie-2020 sibling (~147 unmapped),
    # assigns section "unknown".
    #
    # Replaces the flat "section-all" placeholder that the original
    # ConceptBuilder used before the cross-edition map was available.
    #
    # Idempotent.
    class SectionMapper
      LEGACY_ID_RE = /17-(\d+)/.freeze

      attr_reader :stats

      def initialize(concepts_dir: Paths::CONCEPTS_DIR,
                     cie_2020_concepts_dir: CieEilv::Paths::CONCEPTS_DIR)
        @concepts_dir = concepts_dir
        @cie_2020_concepts_dir = cie_2020_concepts_dir
        @stats = { mapped: 0, unmapped: 0 }
      end

      def run!
        @map_2011_to_section = build_section_map
        warn "Archive2011::SectionMapper: #{@map_2011_to_section.length} cie-2011 IDs have a real section"

        each_concept_file do |path|
          process_file(path)
        end
        warn "Archive2011::SectionMapper: mapped=#{stats[:mapped]} unmapped=#{stats[:unmapped]}"
      end

      # Public: the section prefixes actually used, sorted numerically.
      # Used by RegisterBuilder to emit the section tree.
      def sections_used
        @sections_used ||= begin
          run! if @map_2011_to_section.nil?
          Set.new(@map_2011_to_section.values).to_a.sort
        end
      end

      private

      def build_section_map
        map = {}
        Dir.glob(File.join(@cie_2020_concepts_dir, "*.yaml")).sort.each do |path|
          cf = ConceptFile.read(path)
          eng = cf.find_localized("eng")
          next unless eng

          termid_2020 = cf.managed&.data&.id
          next unless termid_2020

          section = section_from_termid(termid_2020)
          next unless section

          eng.data.sources.each do |src|
            next unless src.origin&.ref&.source == "CIE S 017:2011"
            legacy = src.origin.ref.id.to_s
            legacy.scan(LEGACY_ID_RE) { |m| map[m[0]] = section }
          end
        end
        map
      end

      def section_from_termid(termid)
        m = termid.to_s.match(/\A17-(\d{2})-\d{3}\z/)
        m ? m[1] : nil
      end

      def process_file(path)
        archive_id = File.basename(path, ".yaml").sub(/\A17-/, "")
        section = @map_2011_to_section[archive_id] || "unknown"

        cf = ConceptFile.read(path)
        m = cf.managed
        return unless m&.respond_to?(:data)

        domains = m.data.domains
        return unless domains.respond_to?(:each)

        changed = false
        domains.each do |d|
          next unless d.respond_to?(:concept_id)
          target = "section-#{section}"
          if d.concept_id != target
            d.concept_id = target
            changed = true
          end
        end

        return unless changed

        cf.save
        section == "unknown" ? (@stats[:unmapped] += 1) : (@stats[:mapped] += 1)
      rescue StandardError => e
        warn "  17-#{archive_id}: #{e.message}"
      end

      def each_concept_file
        Dir.glob(File.join(@concepts_dir, "*.yaml")).sort.each { |p| yield p }
      end
    end
  end
end
