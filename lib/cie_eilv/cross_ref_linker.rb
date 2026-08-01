# frozen_string_literal: true

module CieEilv
  # Second-pass rewriter: converts `<a href="/eilvterm/<id>">text</a>` anchors
  # in definitions and notes into Glossarist inline-ref syntax
  # `{<id>, <designation>}`, so the concept-browser renders them as
  # hyperlinks to the target concept.
  #
  # Idempotent: re-running on already-linked data touches zero files.
  # Must run after all concept files exist (the linker needs the full
  # dataset to resolve references).
  class CrossRefLinker
    ANCHOR_RE = %r{<a\s+href="/eilvterm/(17-\d{2}-\d{3})"[^>]*>(.*?)</a>}m.freeze

    CONCEPTS_DIR = Paths::CONCEPTS_DIR

    attr_reader :last_touched_count

    def initialize(concepts_dir: CONCEPTS_DIR)
      @concepts_dir = concepts_dir
      @last_touched_count = 0
    end

    def run!
      designations = load_designation_index
      touched = 0

      each_concept_file do |path|
        cf = ConceptFile.read(path)
        eng = cf.find_localized("eng")
        next unless eng

        changed = false
        changed |= rewrite_definition(eng, designations)
        changed |= rewrite_notes(eng, designations)

        next unless changed

        cf.save
        touched += 1
      end

      @last_touched_count = touched
      warn "CrossRefLinker: touched #{touched} files" if touched.positive?
      touched
    end

    private

    def load_designation_index
      index = {}
      each_concept_file do |path|
        cf = ConceptFile.read(path)
        termid = cf.managed&.data&.id
        eng = cf.find_localized("eng")
        designation = eng&.data&.terms&.first&.designation
        next unless termid && designation

        index[termid] = designation
      end
      index
    end

    def each_concept_file
      Dir.glob("#{@concepts_dir}/*.yaml").each { |p| yield p }
    end

    def rewrite_definition(localized, designations)
      localized.data.definition ||= []
      apply_to_collection(localized.data.definition, designations)
    end

    def rewrite_notes(localized, designations)
      localized.data.notes ||= []
      apply_to_collection(localized.data.notes, designations)
    end

    # Returns true if any element of +collection+ was rewritten.
    def apply_to_collection(collection, designations)
      changed = false
      collection.each do |entry|
        original = entry.content
        rewritten = rewrite_anchors(original, designations)
        next if rewritten == original

        entry.content = rewritten
        changed = true
      end
      changed
    end

    def rewrite_anchors(text, designations)
      return text if text.nil?

      text.gsub(ANCHOR_RE) do |_match|
        termid = Regexp.last_match(1)
        anchor_text = Regexp.last_match(2).strip
        designation = designations[termid] || anchor_text
        "{#{termid}, #{designation}}"
      end
    end
  end
end
