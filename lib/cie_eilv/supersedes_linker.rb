# frozen_string_literal: true

module CieEilv
  # Adds structured "supersedes" relationships on ManagedConcept for
  # each 2020 concept that has a predecessor in CIE S 017:2011.
  #
  # The 2011 IDs are parsed from:
  #   1. Structured sources: {source: "CIE S 017:2011", id: "17-580 and 17-610"}
  #   2. Note text: "This entry was numbered 17-580 and 17-610 in CIE S 017:2011."
  #
  # Each parsed ID becomes a RelatedConcept entry:
  #   related:
  #   - type: supersedes
  #     ref:
  #       source: CIE S 017:2011
  #       id: 17-580
  class SupersedesLinker
    CIE_2011 = "CIE S 017:2011".freeze

    # Matches "17-NNN" IDs in 2011 note text
    ID_RE = /(17-\d{1,4})/.freeze
    # Splits "17-580 and 17-610" into individual IDs
    SPLIT_RE = / and |; |, /.freeze

    attr_reader :stats

    def initialize(concepts_dir: Paths::CONCEPTS_DIR)
      @concepts_dir = concepts_dir
      @stats = { linked: 0, skipped: 0 }
    end

    def run!
      Dir.glob(File.join(@concepts_dir, "*.yaml")).sort.each do |path|
        process_file(path)
      end
      warn "SupersedesLinker: linked=#{stats[:linked]} skipped=#{stats[:skipped]}"
    end

    private

    def process_file(path)
      cf = ConceptFile.read(path)
      managed = cf.managed
      return unless managed

      ids = collect_2011_ids(cf)
      return if ids.empty?

      # Skip if already has supersedes entries for all IDs
      existing = managed.related&.map { |r| r.respond_to?(:ref) ? r.ref&.id : nil }&.compact || []
      new_ids = ids - existing
      return if new_ids.empty?

      managed.related = (managed.related || []) if managed.related.nil?
      new_ids.each do |id|
        managed.related << Glossarist::V3::RelatedConcept.new(
          type: "supersedes",
          ref: Glossarist::V3::ConceptRef.new(source: CIE_2011, id: id),
        )
      end

      cf.save
      @stats[:linked] += 1
    rescue StandardError => e
      warn "  #{File.basename(path, '.yaml')}: #{e.message}"
      @stats[:skipped] += 1
    end

    def collect_2011_ids(cf)
      ids = []

      # From structured sources (localized concept)
      loc = cf.find_localized("eng")
      if loc
        loc.data.sources&.each do |s|
          ref = s.origin&.ref rescue nil
          next unless ref && ref.source.to_s.include?("2011")
          parse_ids(ref.id.to_s).each { |id| ids << id }
        end
      end

      # From managed concept sources
      cf.managed&.sources&.each do |s|
        ref = s.origin&.ref rescue nil
        next unless ref && ref.source.to_s.include?("2011")
        parse_ids(ref.id.to_s).each { |id| ids << id }
      end

      # From note text (fallback)
      if loc
        loc.data.notes&.each do |n|
          content = n.respond_to?(:content) ? n.content : nil
          next unless content&.include?("2011")
          parse_ids(content).each { |id| ids << id }
        end
      end

      ids.uniq
    end

    def parse_ids(text)
      text.scan(ID_RE).flatten.map(&:strip).uniq
    end
  end
end
