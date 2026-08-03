# frozen_string_literal: true

require "yaml"

module CieEilv
  # Converts deprecated <<id, display>> bib-ref syntax to the canonical
  # {{cite:id, display}} form, and ensures each cited ID has a matching
  # ConceptSource entry on the localized concept.
  #
  # Also converts bare IEV IDs (NNN-NN-NN where first segment ≠ 17) found
  # in note/definition text to {{cite:NNN-NN-NN, NNN-NN-NN}}.
  class BibRefMigrator
    BIB_REF_RE = /<<([^,>]+),\s*([^>]+)>>/.freeze
    BIB_MENTION_RE = /\{\{bib:([^,}]+)(?:,\s*([^}]+))?\}\}/.freeze
    IEV_ID_RE = /(?<![\w{-])((?!17-)\d{2,3}-\d{2,3}-\d{2,4})(?![\w}])/m.freeze
    EXISTING_LINK_RE = /(\{\{[^}]+\}\})/.freeze

    ELECTROPEDIA_URL = "https://www.electropedia.org/iev/iev.nsf/display?openform&ievref=%s".freeze

    attr_reader :stats

    def initialize(concepts_dir: Paths::CONCEPTS_DIR)
      @concepts_dir = concepts_dir
      @stats = { touched: 0 }
    end

    def run!
      Dir.glob(File.join(@concepts_dir, "*.yaml")).sort.each do |path|
        process_file(path)
      end
      warn "BibRefMigrator: touched #{@stats[:touched]} files"
    end

    private

    def process_file(path)
      cf = ConceptFile.read(path)
      loc = cf.find_localized("eng")
      return unless loc

      cite_ids = Set.new
      changed = false

      [loc.data.definition, loc.data.notes, loc.data.examples].each do |coll|
        next unless coll.respond_to?(:each)
        coll.each do |entry|
          next unless entry.respond_to?(:content)
          original = entry.content
          next unless original

          result = original
          # Convert <<id, display>> → {{cite:id, display}}
          result = result.gsub(BIB_REF_RE) do
            id = Regexp.last_match(1).strip
            display = Regexp.last_match(2).strip
            cite_ids << id
            "{{cite:#{id}, #{display}}}"
          end

          # Convert {{bib:id, display}} → {{cite:id, display}}
          # IEV entries are concepts, not bibliography records
          result = result.gsub(BIB_MENTION_RE) do
            id = Regexp.last_match(1).strip
            display = Regexp.last_match(2)&.strip || id
            cite_ids << id
            "{{cite:#{id}, #{display}}}"
          end

          # Convert bare IEV IDs → {{cite:id, id}} (only outside existing {{...}})
          result = result.split(EXISTING_LINK_RE).map do |seg|
            next seg if seg.start_with?("{{")
            seg.gsub(IEV_ID_RE) do |match|
              cite_ids << match
              "{{cite:#{match}, #{match}}}"
            end
          end.join

          # Collect IDs from existing {{cite:id}} for source creation
          result.scan(/\{\{cite:([^,}]+)/) { |m| cite_ids << m[0] }

          next if result == original
          entry.content = result
          changed = true
        end
      end

      return unless changed || cite_ids.any?

      managed = cf.managed
      ensure_sources!(managed, cite_ids) if managed
      ensure_sources!(loc, cite_ids)
      cf.save
      @stats[:touched] += 1
    end

    def ensure_sources!(concept, cite_ids)
      sources = if concept.respond_to?(:sources) && concept.sources.is_a?(Array)
                  concept.sources
                elsif concept.data.respond_to?(:sources)
                  concept.data.sources
                else
                  nil
                end
      return if sources.nil?

      existing = sources.map { |s| s.respond_to?(:id) ? s.id : nil }.compact

      cite_ids.each do |id|
        next if existing.include?(id)
        sources << build_source(id)
      end
    end

    def build_source(iev_id)
      link = format(ELECTROPEDIA_URL, iev_id)
      citation = Glossarist::V3::Citation.new(
        ref: Glossarist::Citation::Ref.new(source: "IEC 60050 (IEV)", id: iev_id),
      )
      citation.link = link
      Glossarist::V3::ConceptSource.new(
        type: "authoritative",
        id: iev_id,
        origin: citation,
      )
    end
  end
end
