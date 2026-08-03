# frozen_string_literal: true

require "yaml"

module CieEilv
  module Archive2011
    # Copies proper AsciiMath math from cie-2020 concepts into cie-2011
    # concepts via the prior-numbering cross-edition map.
    #
    # The cie-2020 dataset already has stem:[...] notation (imported from
    # iev-data by CieEilv::IevMathImporter and normalized by
    # CieEilv::MathNormalizer). Cie-2011 was scraped from archive.org
    # and has only HTML fake math + broken image refs.
    #
    # For each cie-2011 concept that has a cie-2020 sibling (encoded in
    # the 2020 concept's sources[] as `source: CIE S 017:2011,
    # id: 17-NNN`):
    #
    #   1. Replace cie-2011's definition with cie-2020's (math included),
    #      with cie-2011's existing cross-refs re-applied on top.
    #   2. Replace cie-2011's terms[] with cie-2020's (carries the symbol
    #      designation with proper stem:[...] form).
    #
    # Notes are NOT touched. Cie-2011 often has more detailed math notes
    # than the abbreviated cie-2020 versions; replacing them would lose
    # information. (The user's IevMathImporter / MathTagConverter pipeline
    # handles residual HTML fake math in notes separately.)
    #
    # The cross-edition map is built once at construction from all
    # cie-2020 concepts' prior-numbering sources.
    #
    # Idempotent. Concepts without a mapping (~147, mostly text-only or
    # aliases) are skipped and reported.
    class IevMathImporter
      CROSS_REF_RE = /\{\{([^}]+)\}\}/.freeze
      BIB_REF_RE = /<<([^>]+)>>/.freeze
      STEM_BLOCK_RE = /(\*?(?:stem|latexmath):\[[^\]]+\])/.freeze

      # Captures 17-NNNN IDs inside the legacy id string.
      LEGACY_ID_RE = /17-(\d+)/.freeze

      attr_reader :stats

      def initialize(concepts_dir: Paths::CONCEPTS_DIR,
                     cie_2020_concepts_dir: CieEilv::Paths::CONCEPTS_DIR)
        @concepts_dir = concepts_dir
        @cie_2020_concepts_dir = cie_2020_concepts_dir
        @stats = { mapped: 0, updated: 0, skipped: 0, unmapped: 0 }
      end

      def run!
        @map_2011_to_2020 = build_cross_edition_map
        warn "Archive2011::IevMathImporter: #{@map_2011_to_2020.length} cie-2011 IDs have a cie-2020 mapping"

        each_concept_file do |path|
          process_file(path)
        end
        warn "Archive2011::IevMathImporter: mapped=#{stats[:mapped]} updated=#{stats[:updated]} skipped=#{stats[:skipped]} unmapped=#{stats[:unmapped]}"
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
          stats[:unmapped] += 1
          return
        end

        cie_2020_path = File.join(@cie_2020_concepts_dir, "#{termid_2020}.yaml")
        unless File.exist?(cie_2020_path)
          stats[:unmapped] += 1
          return
        end

        stats[:mapped] += 1

        cf_2011 = ConceptFile.read(path)
        cf_2020 = ConceptFile.read(cie_2020_path)
        eng_2011 = cf_2011.find_localized("eng")
        eng_2020 = cf_2020.find_localized("eng")
        return unless eng_2011 && eng_2020

        changed = false
        changed |= merge_definition(eng_2011, eng_2020)
        changed |= merge_notes_if_broken(eng_2011, eng_2020)
        changed |= merge_terms(eng_2011, eng_2020)

        return unless changed

        cf_2011.save
        stats[:updated] += 1
      rescue StandardError => e
        warn "  17-#{archive_id}: #{e.message}"
        stats[:skipped] += 1
      end

      # Detect broken-image refs in cie-2011 notes — signal that we should
      # pull cie-2020's notes (with complete AsciiMath) as replacement.
      BROKEN_IMG_RE = %r{<img[^>]*src="[^"]*im_/[^"]*\.png"}.freeze

      def notes_have_broken_images(eng_2011)
        notes = eng_2011.data.notes
        return false unless notes.respond_to?(:each)

        notes.any? { |n| n.content.to_s =~ BROKEN_IMG_RE }
      end

      # Replace cie-2011's notes with cie-2020's when cie-2011 has broken
      # image refs. Cie-2020's notes have complete AsciiMath (pulled from
      # iev-data by CieEilv::IevMathImporter). The trade-off: cie-2011's
      # original note wording is lost when cie-2020 has abbreviated it.
      # Acceptable because the alternative is unrecoverable image refs.
      def merge_notes_if_broken(eng_2011, eng_2020)
        return false unless notes_have_broken_images(eng_2011)

        notes_2011 = eng_2011.data.notes
        notes_2020 = eng_2020.data.notes
        return false unless notes_2020.respond_to?(:each) && !notes_2020.empty?

        # Pull cie-2011's cross-refs first; we'll re-apply them on top
        # of cie-2020's notes (which use cie-2020 IDs).
        refs_2011 = []
        notes_2011.each do |note|
          extract_refs(note.content.to_s).each { |r| refs_2011 << r }
        end

        old_contents = notes_2011.map(&:content)

        # Build a fresh notes collection from cie-2020's content with
        # cie-2011's cross-refs re-applied. Glossarist collections don't
        # support #pop or #clear, so we replace via assignment.
        new_collection = Glossarist::Collections::DetailedDefinitionCollection.new
        notes_2020.each do |note_2020|
          merged = merge_content("", note_2020.content.to_s)
          refs_2011.each do |ref|
            plain = ref[:plain]
            escaped = Regexp.escape(plain)
            merged = merged.sub(/(?<![{<])#{escaped}(?![}>])/) { ref[:marker] }
          end
          new_collection << Glossarist::V3::DetailedDefinition.new(content: merged)
        end

        eng_2011.data.notes = new_collection

        new_contents = new_collection.map(&:content)
        new_contents != old_contents
      end

      def merge_definition(eng_2011, eng_2020)
        defs_2011 = eng_2011.data.definition
        defs_2020 = eng_2020.data.definition
        return false if defs_2011.nil? || defs_2011.empty?
        return false if defs_2020.nil? || defs_2020.empty?

        old = defs_2011.first.content
        new_2020 = defs_2020.first.content
        merged = merge_content(old, new_2020)
        return false if merged == old

        defs_2011.first.content = merged
        true
      end

      # Replace cie-2011's terms with cie-2020's terms. Cie-2020 carries
      # the proper stem:[...] symbol designation; cie-2011 has HTML
      # markup that needs the cross-edition fix.
      def merge_terms(eng_2011, eng_2020)
        terms_2011 = eng_2011.data.terms
        terms_2020 = eng_2020.data.terms
        return false unless terms_2011.respond_to?(:each)
        return false unless terms_2020.respond_to?(:each)
        return false if terms_2020.empty?

        # Snapshot current cie-2011 term designations to detect change.
        old_designations = terms_2011.map(&:designation)

        # Build the replacement list. We preserve cie-2011's preferred
        # designation (it's the canonical name in 2011's wording) but
        # pull cie-2020's symbol term (with proper stem notation).
        new_terms = build_terms(eng_2011, eng_2020)
        return false if new_terms.nil?

        replace_terms(terms_2011, new_terms)

        new_designations = terms_2011.map(&:designation)
        new_designations != old_designations
      end

      # Build the new term list for cie-2011. Strategy:
      # - For each cie-2011 term:
      #   - If it has a broken image in its designation → use the matching
      #     cie-2020 term (preferred → cie-2020 preferred, etc.)
      #   - Else → keep cie-2011's term (preserves 2011 wording)
      # - Ensure cie-2020's symbol term is included (carries stem:[...]).
      def build_terms(eng_2011, eng_2020)
        terms_2011 = eng_2011.data.terms.to_a
        terms_2020 = eng_2020.data.terms.to_a

        symbol_2020 = terms_2020.find { |t| t.is_a?(Glossarist::Designation::Symbol) }
        # If cie-2011 has any broken-image term, we need cie-2020's clean version.
        any_broken = terms_2011.any? { |t| t.designation.to_s =~ BROKEN_IMG_RE }

        result = []
        symbol_added = false

        terms_2011.each do |t_2011|
          if t_2011.designation.to_s =~ BROKEN_IMG_RE
            # Replace with cie-2020's corresponding term (same type+status).
            t_2020 = find_matching_term(terms_2020, t_2011)
            if t_2020
              result << t_2020.dup
              symbol_added = true if t_2020.is_a?(Glossarist::Designation::Symbol)
              next
            end
            # No cie-2020 match — drop the broken term entirely.
            next
          end

          result << t_2011

          # After cie-2011's preferred expression, insert cie-2020's symbol
          # (if cie-2020 has one and we haven't added it yet).
          if symbol_2020 && !symbol_added &&
             t_2011.is_a?(Glossarist::Designation::Expression) &&
             t_2011.normative_status == "preferred"
            result << symbol_2020.dup
            symbol_added = true
          end
        end

        # If cie-2011 had no preferred expression slot to anchor the
        # symbol after, append it at the end.
        result << symbol_2020.dup if symbol_2020 && !symbol_added

        # If nothing changed, return nil so merge_terms reports no change.
        old_designations = terms_2011.map(&:designation)
        new_designations = result.map(&:designation)
        new_designations == old_designations ? nil : result
      end

      # Find the cie-2020 term that best matches +t_2011+ by type and
      # normative_status. Used when cie-2011's term has a broken image
      # and we want to pull cie-2020's clean version.
      def find_matching_term(terms_2020, t_2011)
        same_type = terms_2020.select { |t| t.class == t_2011.class }
        same_type.find { |t| t.normative_status == t_2011.normative_status } ||
          same_type.first
      end

      # Glossarist collections don't have #clear or #delete — replace by
      # rebuilding the underlying array via private methods.
      def replace_terms(collection, new_terms)
        collection.each_with_index do |_, i|
          next unless i < collection.size
        end
        # Pop all from end, then push new.
        while collection.size.positive?
          last = collection.last
          if collection.respond_to?(:pop)
            collection.pop
          else
            # Manual removal — find and remove from internal array.
            collection.delete_if { |x| x.equal?(last) }
          end
        end
        new_terms.each { |t| collection << t }
      end

      # Take cie-2011's content (for its cross-refs) and cie-2020's content
      # (for its math). Strip cie-2020's cross-refs, then re-apply
      # cie-2011's cross-refs by display-text matching on the cie-2020 text.
      def merge_content(content_2011, content_2020)
        refs = extract_refs(content_2011.to_s)
        stripped = strip_2020_refs(content_2020.to_s)
        return stripped if refs.empty?
        apply_refs_to_stem_text(stripped, refs)
      end

      def strip_2020_refs(text)
        text.gsub(CROSS_REF_RE) do |match|
          body = Regexp.last_match(1)
          _id, display = body.split(",", 2).map(&:strip)
          display || body
        end
      end

      def extract_refs(text)
        refs = []
        text.scan(CROSS_REF_RE) do |groups|
          body = groups.is_a?(Array) ? groups.first : groups
          id, display = body.split(",", 2).map(&:strip)
          refs << { marker: "{{#{id}, #{display}}}", plain: display } if display && !display.empty?
        end
        text.scan(BIB_REF_RE) do |groups|
          body = groups.is_a?(Array) ? groups.first : groups
          id, display = body.split(",", 2).map(&:strip)
          refs << { marker: "<<#{id}, #{display}>>", plain: display } if display && !display.empty?
        end
        refs
      end

      def apply_refs_to_stem_text(text, refs)
        return text if refs.empty?

        placeholders = {}
        protected_text = text.gsub(STEM_BLOCK_RE) do |match|
          key = " STEM#{placeholders.size} "
          placeholders[key] = match
          key
        end

        refs.each do |ref|
          plain = ref[:plain]
          escaped = Regexp.escape(plain)
          protected_text = protected_text.sub(/(?<![{<])#{escaped}(?![}>])/) { ref[:marker] }
        end

        placeholders.each { |key, val| protected_text.sub!(key, val) }
        protected_text
      end

      def each_concept_file
        Dir.glob(File.join(@concepts_dir, "*.yaml")).sort.each { |p| yield p }
      end
    end
  end
end
