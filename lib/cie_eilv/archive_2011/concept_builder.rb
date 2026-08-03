# frozen_string_literal: true

require "fileutils"

module CieEilv
  module Archive2011
    # Pure mapper from a parsed 2011 TermEntry into Glossarist v3
    # ManagedConcept + LocalizedConcept model instances for the cie-2011
    # dataset.
    #
    # Differences from the 2020 ConceptBuilder:
    # - Source is "CIE S 017:2011" (1st edition).
    # - Source link is the archive.org Wayback URL (live site is gone).
    # - No usage_info / part_of_speech — those fields don't exist in the
    #   2011 markup.
    # - Equivalent terms become admitted expressions on the same concept.
    # - Sections: 2011 IDs are flat (17-XXXX), so every concept lives in
    #   a single "section-all" domain. Real section structure would
    #   require cross-edition mapping via the 2020 prior-numbering notes.
    class ConceptBuilder
      AUTHORITATIVE_SOURCE = "CIE S 017:2011".freeze
      DATASET_URN = Paths::URN

      # Build the managed (top-level) concept for +term+.
      # +source_url+ is the Wayback URL the page was scraped from —
      # preserved as the source link for provenance.
      def build_managed(term, source_url:)
        Glossarist::V3::ManagedConcept.new(
          status: term.alias? ? "valid" : "valid",
          data: managed_data(term),
          sources: [managed_source(term, source_url)]
        ).tap { |mc| mc.id = CieEilv::Uuid.v5(term.termid) }
      end

      # Build the English localized concept for +term+.
      def build_localized(term)
        Glossarist::V3::LocalizedConcept.new(
          termid: term.termid,
          data: localized_data(term)
        ).tap { |lc| lc.id = "#{term.termid}-eng" }
      end

      # Build both docs and write a multi-doc YAML file at +path+.
      def write_concept(term, path:, source_url:)
        managed = build_managed(term, source_url: source_url)
        localized = build_localized(term)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, [managed.to_yaml, localized.to_yaml].join)
        path
      end

      private

      def managed_data(term)
        {
          id: term.termid,
          domains: [
            {
              concept_id: "section-all",
              source: DATASET_URN,
              ref_type: "section"
            }
          ]
        }
      end

      def managed_source(term, source_url)
        Glossarist::V3::ConceptSource.new(
          type: "authoritative",
          origin: Glossarist::V3::Citation.new(
            ref: Glossarist::Citation::Ref.new(source: AUTHORITATIVE_SOURCE),
            link: source_url
          )
        )
      end

      def localized_data(term)
        {
          language_code: "eng",
          terms: build_terms(term),
          definition: build_definition(term),
          notes: term.notes.map { |n| Glossarist::V3::DetailedDefinition.new(content: n) },
          examples: [],
          sources: [primary_source]
        }
      end

      def build_terms(term)
        terms = [build_expression_term(term)]
        terms << build_symbol_term(term) if term.symbol?
        term.equivalent_terms.each { |et| terms << build_admitted_term(et) }
        terms
      end

      def build_expression_term(term)
        Glossarist::Designation::Expression.new(
          designation: term.designation,
          normative_status: "preferred"
        )
      end

      def build_symbol_term(term)
        Glossarist::Designation::Symbol.new(
          designation: term.symbol,
          normative_status: "preferred"
        )
      end

      def build_admitted_term(designation)
        Glossarist::Designation::Expression.new(
          designation: designation,
          normative_status: "admitted"
        )
      end

      def build_definition(term)
        return [Glossarist::V3::DetailedDefinition.new(content: term.definition)] unless term.definition.empty?

        # Alias entries with only a "See X" pointer have non-empty
        # definition; this branch is a defensive fallback for pages
        # where the body is genuinely empty.
        []
      end

      def primary_source
        Glossarist::V3::ConceptSource.new(
          type: "authoritative",
          origin: Glossarist::V3::Citation.new(
            ref: Glossarist::Citation::Ref.new(source: AUTHORITATIVE_SOURCE)
          )
        )
      end
    end
  end
end
