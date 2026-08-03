# frozen_string_literal: true

require "set"

module CieEilv
  module Archive2011
    # Second-pass rewriter for the cie-2011 dataset: converts
    # `<a href="NNNN">text</a>` and Wayback-rewritten
    # `<a href="/web/<ts>/http://eilv.cie.co.at/term/NNNN">text</a>` anchors
    # in definitions and notes into Glossarist inline-ref syntax
    # `{{17-NNNN, designation}}`, so the concept-browser renders them as
    # hyperlinks to the target concept.
    #
    # Idempotent: re-running on already-linked data touches zero files.
    # Must run after all concept files exist.
    class CrossRefLinker
      # Bare numeric href (Drupal relative): "1014", "7", etc.
      BARE_ANCHOR_RE = %r{<a\s+href="(\d+)"[^>]*>(.*?)</a>}m.freeze

      # Wayback-rewritten href to a term page.
      WAYBACK_ANCHOR_RE =
        %r{<a\s+href="/web/\d{14}(?:[a-z]{2}_)?/http://eilv\.cie\.co\.at/term/(\d+)"[^>]*>(.*?)</a>}m.freeze

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
          cf = CieEilv::ConceptFile.read(path)
          eng = cf.find_localized("eng")
          next unless eng

          changed = false
          changed |= apply_to_collection(eng.data.definition, designations)
          changed |= apply_to_collection(eng.data.notes, designations)
          changed |= apply_to_terms(eng.data.terms, designations)

          next unless changed

          cf.save
          touched += 1
        end

        @last_touched_count = touched
        warn "Archive2011::CrossRefLinker: touched #{touched} files" if touched.positive?
        touched
      end

      private

      # Map of archive_id (string) → designation, for resolving anchor text.
      def load_designation_index
        index = {}
        each_concept_file do |path|
          cf = CieEilv::ConceptFile.read(path)
          identifier = cf.managed&.data&.id.to_s
          archive_id = identifier.sub(/\A17-/, "")
          eng = cf.find_localized("eng")
          designation = eng&.data&.terms&.find { |t| t.is_a?(Glossarist::Designation::Expression) }&.designation
          next unless !archive_id.empty? && designation

          index[archive_id] = designation
        end
        index
      end

      def each_concept_file
        Dir.glob("#{@concepts_dir}/*.yaml").each { |p| yield p }
      end

      def apply_to_collection(collection, designations)
        return false unless collection

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

        text
          .gsub(WAYBACK_ANCHOR_RE) { rewrite_ref(Regexp.last_match(1), Regexp.last_match(2), designations) }
          .gsub(BARE_ANCHOR_RE) { rewrite_ref(Regexp.last_match(1), Regexp.last_match(2), designations) }
      end

      def apply_to_terms(terms, designations)
        return false unless terms.respond_to?(:each)

        changed = false
        terms.each do |term|
          next unless term.respond_to?(:designation) && term.designation.is_a?(String)
          new = rewrite_anchors(term.designation, designations)
          next if new == term.designation
          term.designation = new
          changed = true
        end
        changed
      end

      def rewrite_ref(archive_id, anchor_text, designations)
        designation = designations[archive_id] || anchor_text.strip
        "{{17-#{archive_id}, #{designation}}}"
      end
    end
  end
end
