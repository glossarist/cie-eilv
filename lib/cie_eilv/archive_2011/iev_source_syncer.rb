# frozen_string_literal: true

require "set"

module CieEilv
  module Archive2011
    # Ensures every {{cite:IEV-ID, ...}} mention in a cie-2011 concept has
    # a matching ConceptSource entry in its sources[] (both managed and
    # localized). Without the backing source, concept-browser renders the
    # cite as an unresolved span.
    #
    # Mirrors the ensure_cite_sources! pattern from CieEilv::IevMathImporter.
    # The source carries an Electropedia link so citeResolver can render
    # it as a clickable external link.
    class IevSourceSyncer
      CITE_RE = /\{\{cite:([^},]+)/.freeze

      ELECTROPEDIA_LINK = "https://www.electropedia.org/iev/iev.nsf/display?openform&ievref=%<id>s".freeze
      IEV_SOURCE_NAME = "IEC 60050 (IEV)".freeze

      attr_reader :stats

      def initialize(concepts_dir: Paths::CONCEPTS_DIR)
        @concepts_dir = concepts_dir
        @stats = { touched: 0, sources_added: 0 }
      end

      def run!
        each_concept_file do |path|
          process_file(path)
        end
        warn "Archive2011::IevSourceSyncer: touched #{stats[:touched]} files, added #{stats[:sources_added]} sources"
      end

      private

      def process_file(path)
        cf = ConceptFile.read(path)
        eng = cf.find_localized("eng")
        return unless eng

        cited_ids = collect_cite_ids(cf)
        return if cited_ids.empty?

        existing_loc = source_ids(eng.data.sources)
        existing_mgr = source_ids(cf.managed&.sources)

        new_ids = cited_ids - existing_loc
        return if new_ids.empty?

        # Add to localized sources[]
        new_ids.each do |id|
          eng.data.sources << build_source(id)
        end

        # Add to managed sources[] too (mirrors cie-2020 structure)
        if cf.managed && cf.managed.respond_to?(:sources)
          (new_ids - existing_mgr).each do |id|
            cf.managed.sources << build_source(id)
          end
        end

        cf.save
        @stats[:touched] += 1
        @stats[:sources_added] += new_ids.length
      rescue StandardError => e
        warn "  #{File.basename(path)}: #{e.message}"
      end

      def collect_cite_ids(cf)
        ids = Set.new
        eng = cf.find_localized("eng")
        return ids unless eng

        walk_text(eng.data.definition, ids)
        walk_text(eng.data.notes, ids)
        walk_text(eng.data.examples, ids)
        (eng.data.terms || []).each do |t|
          next unless t.respond_to?(:designation)
          t.designation.to_s.scan(CITE_RE) { |m| ids << m[0].strip }
        end
        ids
      end

      def walk_text(collection, ids)
        return unless collection.respond_to?(:each)
        collection.each do |entry|
          next unless entry.respond_to?(:content)
          entry.content.to_s.scan(CITE_RE) { |m| ids << m[0].strip }
        end
      end

      def source_ids(sources)
        return Set.new unless sources.respond_to?(:each)

        ids = Set.new
        sources.each do |s|
          next unless s.respond_to?(:origin) && s.origin.respond_to?(:ref)
          ref = s.origin&.ref
          sid = ref&.id
          ids << sid if sid && !sid.empty?
        end
        ids
      end

      def build_source(iev_id)
        link = format(ELECTROPEDIA_LINK, id: iev_id)
        Glossarist::V3::ConceptSource.new(
          id: iev_id,
          type: "authoritative",
          origin: Glossarist::V3::Citation.new(
            ref: Glossarist::Citation::Ref.new(source: IEV_SOURCE_NAME, id: iev_id),
            link: link
          )
        )
      end

      def each_concept_file
        Dir.glob(File.join(@concepts_dir, "*.yaml")).sort.each { |p| yield p }
      end
    end
  end
end
