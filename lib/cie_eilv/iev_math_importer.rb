# frozen_string_literal: true

require "yaml"

module CieEilv
  # Merges proper stem:[] math notation from the iev-data termbase
  # (../iev-data) into the CIE e-ILV concept files.
  #
  # iev-data cross-references are converted to Glossarist syntax:
  #   <a href="IEV845-21-025">wavelength</a>  →  {{17-21-025, wavelength}}
  #   {{frequency, IEV:103-06-02}}            →  {{cite:103-06-02, frequency}}
  #
  # For external IEV references (non-845 chapters), a ConceptSource entry
  # is added to the concept's sources[] with the Electropedia link, so the
  # concept-browser's citeResolver can render it as a clickable citation.
  class IevMathImporter
    IEV_DATA_DIR = File.expand_path("../iev-data/concepts", Dir.pwd).freeze
    BIBLIOGRAPHY_PATH = File.join(Paths::DATASET_DIR, "bibliography.yaml").freeze

    IEV_ANCHOR_RE = %r{<a\s+href="IEV(\d{2,3})-(\d{2,3})-(\d{2,4})"[^>]*>(.*?)</a>}m.freeze
    IEV_MENTION_RE = /\{\{([^,{}]+),\s*IEV:(\d{2,3})-(\d{2,3})-(\d{2,4})\}\}/.freeze
    CITE_RE = /\{\{cite:([\d-]+)(?:,\s*([^}]+))?\}\}/.freeze

    attr_reader :stats

    def initialize(concepts_dir: Paths::CONCEPTS_DIR, iev_data_dir: IEV_DATA_DIR)
      @concepts_dir = concepts_dir
      @iev_data_dir = iev_data_dir
      @bib_links = load_bibliography_links
      @stats = { matched: 0, updated: 0, skipped: 0 }
    end

    def run!
      each_concept_file do |path|
        process_file(path)
      end
      warn "IevMathImporter: matched=#{stats[:matched]} updated=#{stats[:updated]} skipped=#{stats[:skipped]}"
    end

    private

    def process_file(path)
      termid = File.basename(path, ".yaml")
      iev_id = map_to_iev_id(termid)
      return unless iev_id

      iev_path = File.join(@iev_data_dir, "concept-#{iev_id}.yaml")
      return unless File.exist?(iev_path)

      stats[:matched] += 1
      iev_doc = YAML.load_file(iev_path)
      eng = iev_doc && iev_doc["eng"]
      return unless eng

      cf = ConceptFile.read(path)
      loc = cf.find_localized("eng")
      return unless loc

      changed = false
      changed |= merge_definition(loc, eng)
      changed |= merge_collection(loc.data.notes, eng["notes"])
      changed |= merge_collection(loc.data.examples, eng["examples"])

      # Cite sources go on the managed concept (where citeResolver looks)
      managed = cf.managed
      ensure_cite_sources!(managed) if managed
      ensure_cite_sources!(loc)

      return unless changed

      cf.save
      stats[:updated] += 1
    rescue StandardError => e
      warn "  #{termid}: #{e.message}"
      stats[:skipped] += 1
    end

    def merge_definition(localized, eng)
      defs = localized.data.definition
      return false if defs.nil? || defs.empty?

      iev_def = eng["definition"]
      return false unless iev_def.is_a?(String)

      new = convert_iev_refs(iev_def)
      return false if new == defs.first.content

      defs.first.content = new
      true
    end

    def merge_collection(collection, iev_entries)
      return false unless collection.respond_to?(:each) && iev_entries.is_a?(Array)

      changed = false
      collection.each_with_index do |entry, i|
        break if i >= iev_entries.length

        iev_text = iev_entries[i]
        iev_text = iev_text["content"] if iev_text.is_a?(Hash)
        next unless iev_text.is_a?(String)

        new = convert_iev_refs(iev_text)
        next if new == entry.content

        entry.content = new
        changed = true
      end
      changed
    end

    # Convert iev-data cross-reference syntax to Glossarist inline-ref syntax.
    def convert_iev_refs(text)
      result = text.gsub(IEV_ANCHOR_RE) do |_|
        build_ref(Regexp.last_match(1), Regexp.last_match(2),
                  Regexp.last_match(3), Regexp.last_match(4).strip)
      end

      result = result.gsub(IEV_MENTION_RE) do
        build_ref(Regexp.last_match(2), Regexp.last_match(3),
                  Regexp.last_match(4), Regexp.last_match(1).strip)
      end

      result
    end

    def build_ref(chapter, section, number, display)
      iev_id = "#{chapter}-#{section}-#{number}"
      if chapter == "845"
        "{{17-#{section}-#{number}, #{display}}}"
      else
        "{{cite:#{iev_id}, #{display}}}"
      end
    end

    # Scan all content for {{cite:id}} mentions and ensure a matching
    # ConceptSource exists on the localized concept. Each source carries
    # the Electropedia link so citeResolver renders it as a clickable link.
    def ensure_cite_sources!(localized)
      cited_ids = collect_cite_ids(localized)
      return if cited_ids.empty?

      sources = localized.data.sources
      existing_ids = sources.map { |s| s.respond_to?(:id) ? s.id : s[:id] }.compact

      cited_ids.each do |iev_id|
        next if existing_ids.include?(iev_id)
        link = @bib_links[iev_id]
        sources << build_cite_source(iev_id, link)
      end
    end

    def collect_cite_ids(localized)
      ids = Set.new
      [localized.data.definition, localized.data.notes, localized.data.examples].each do |coll|
        next unless coll.respond_to?(:each)
        coll.each do |entry|
          next unless entry.respond_to?(:content)
          entry.content.to_s.scan(CITE_RE) { |m| ids << m[0] }
        end
      end
      ids
    end

    def build_cite_source(iev_id, link)
      link ||= "https://www.electropedia.org/iev/iev.nsf/display?openform&ievref=#{iev_id}"
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

    def load_bibliography_links
      return {} unless File.exist?(BIBLIOGRAPHY_PATH)
      raw = YAML.load_file(BIBLIOGRAPHY_PATH)
      entries = raw.is_a?(Hash) ? (raw["bibliography"] || []) : (raw || [])
      entries.each_with_object({}) do |e, h|
        h[e["id"]] = e["link"] if e["id"] && e["link"]
      end
    rescue StandardError
      {}
    end

    def map_to_iev_id(termid)
      parts = termid.split("-")
      "845-#{parts[1]}-#{parts[2]}" if parts.length == 3
    end

    def each_concept_file
      Dir.glob(File.join(@concepts_dir, "*.yaml")).sort.each { |p| yield p }
    end
  end
end
