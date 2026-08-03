# frozen_string_literal: true

module CieEilv
  # Migrates inline mentions to the fully declarative grammar from
  # concept-model/docs/design/inline-mentions-implementation-guide.md.
  #
  #   {{17-XX-YYY, display}}        → {{concept:DATASET:17-XX-YYY, display}}
  #   {{cite:NNN-NN-NN, display}}   → {{cite:IEV:NNN-NN-NN, display}}
  #   {{cite:845-XX-YYY, display}}  → {{cite:IEV:845-XX-YYY, display}}
  #
  # Also fixes ConceptSource origin.ref.source:
  #   "IEC 60050 (IEV)" → "IEV"
  # so the citeResolver's dataset matching works.
  class MentionMigrator
    # {{17-XX-YYY, display}} — bare concept ref (no kind prefix)
    BARE_CONCEPT_RE = /\{\{(17-\d{2}-\d{3})(?:,\s*([^}]+))?\}\}/.freeze

    # {{cite:NNN-NN-NN, display}} — cite with bare ID (no DATASET: prefix)
    BARE_CITE_RE = /\{\{cite:(\d{2,3}-\d{2,3}-\d{2,4})(?:,\s*([^}]+))?\}\}/.freeze

    IEV_SOURCE_VALUES = [
      "IEC 60050 (IEV)",
      "IEC 60050-845:1987",
      "IEC 60050-845",
    ].freeze

    attr_reader :stats

    def initialize(dataset_id:, concepts_dir:)
      @dataset_id = dataset_id
      @concepts_dir = concepts_dir
      @stats = { touched: 0 }
    end

    def run!
      Dir.glob(File.join(@concepts_dir, "*.yaml")).sort.each do |path|
        process_file(path)
      end
      warn "MentionMigrator(#{@dataset_id}): touched #{@stats[:touched]} files"
    end

    private

    def process_file(path)
      cf = ConceptFile.read(path)
      loc = cf.find_localized("eng")
      return unless loc

      changed = false

      [loc.data.definition, loc.data.notes, loc.data.examples].each do |coll|
        next unless coll.respond_to?(:each)
        coll.each do |entry|
          next unless entry.respond_to?(:content)
          original = entry.content
          next unless original

          result = migrate_mentions(original)
          next if result == original

          entry.content = result
          changed = true
        end
      end

      # Fix ConceptSource origin.ref.source
      [cf.managed, loc].each do |concept|
        next unless concept
        sources = if concept.respond_to?(:sources) && concept.sources.is_a?(Array)
                    concept.sources
                  elsif concept.data.respond_to?(:sources)
                    concept.data.sources
                  end
        next unless sources
        sources.each do |s|
          ref = s.origin&.ref rescue nil
          next unless ref
          if IEV_SOURCE_VALUES.include?(ref.source.to_s)
            ref.source = "IEV"
            changed = true
          end
        end
      end

      return unless changed

      cf.save
      @stats[:touched] += 1
    end

    def migrate_mentions(text)
      result = text

      # {{17-XX-YYY, display}} → {{concept:DATASET:17-XX-YYY, display}}
      result = result.gsub(BARE_CONCEPT_RE) do
        id = Regexp.last_match(1)
        display = Regexp.last_match(2)
        if display
          "{{concept:#{@dataset_id}:#{id}, #{display.strip}}}"
        else
          "{{concept:#{@dataset_id}:#{id}}}"
        end
      end

      # {{cite:NNN-NN-NN, display}} → {{cite:IEV:NNN-NN-NN, display}}
      result = result.gsub(BARE_CITE_RE) do
        id = Regexp.last_match(1)
        display = Regexp.last_match(2)
        if display
          "{{cite:IEV:#{id}, #{display.strip}}}"
        else
          "{{cite:IEV:#{id}}}"
        end
      end

      result
    end
  end
end
