# frozen_string_literal: true

require "fileutils"

module CieEilv
  # Pure mapper from a parsed TermEntry into Glossarist v3 ManagedConcept and
  # LocalizedConcept model instances.
  #
  # MECE boundary:
  # - TermParser knows the e-ILV HTML contract.
  # - ConceptBuilder knows the Glossarist v3 schema mapping.
  # Neither knows about the other's internals.
  #
  # No hand-rolled serialization here — all to_yaml / from_yaml goes through
  # Glossarist::V3::*.
  class ConceptBuilder
    AUTHORITATIVE_SOURCE = "CIE S 017:2020".freeze
    DATASET_URN = Paths::URN

    # Build the managed (top-level) concept for +term+.
    def build_managed(term)
      Glossarist::V3::ManagedConcept.new(
        status: "valid",
        data: managed_data(term),
        sources: [managed_source(term)]
      ).tap { |mc| mc.id = Uuid.v5(term.termid) }
    end

    # Build the English localized concept for +term+.
    def build_localized(term)
      Glossarist::V3::LocalizedConcept.new(
        termid: term.termid,
        data: localized_data(term)
      ).tap { |lc| lc.id = "#{term.termid}-eng" }
    end

    # Build both docs and write a multi-doc YAML file at +path+.
    # Returns the path.
    def write_concept(term, path:)
      managed = build_managed(term)
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
            concept_id: "section-#{term.section_prefix}",
            source: DATASET_URN,
            ref_type: "section"
          }
        ]
      }
    end

    def managed_source(term)
      Glossarist::V3::ConceptSource.new(
        type: "authoritative",
        origin: Glossarist::V3::Citation.new(
          ref: Glossarist::Citation::Ref.new(source: AUTHORITATIVE_SOURCE),
          link: "#{Paths::BASE_URL}/eilvterm/#{term.termid}"
        )
      )
    end

    def localized_data(term)
      {
        language_code: "eng",
        terms: build_terms(term),
        definition: [Glossarist::V3::DetailedDefinition.new(content: term.definition)],
        notes: term.notes.map { |n| Glossarist::V3::DetailedDefinition.new(content: n) },
        examples: [],
        sources: localized_sources(term)
      }
    end

    def build_terms(term)
      terms = [build_expression_term(term)]
      terms << Glossarist::Designation::Symbol.new(
        designation: term.symbol,
        normative_status: "preferred"
      ) if term.symbol?
      terms
    end

    def build_expression_term(term)
      expr = Glossarist::Designation::Expression.new(
        designation: term.designation,
        normative_status: "preferred"
      )
      expr.usage_info = term.usage_info if term.usage_info
      expr.grammar_info = [build_grammar_info(term.part_of_speech)] if term.part_of_speech
      expr
    end

    # Maps an ILV part-of-speech token to a Glossarist::Designation::GrammarInfo.
    # Recognized POS: noun, adj, verb, adverb. "pl" (plural-only) is encoded
    # as number=plural, since it's not a part of speech but a number marker.
    def build_grammar_info(part_of_speech)
      case part_of_speech
      when "noun", "adj", "verb", "adverb", "participle", "preposition"
        Glossarist::Designation::GrammarInfo.new(part_of_speech: part_of_speech.to_sym)
      when "pl"
        Glossarist::Designation::GrammarInfo.new(number: [:plural])
      else
        Glossarist::Designation::GrammarInfo.new(part_of_speech: part_of_speech.to_sym)
      end
    end

    def localized_sources(term)
      sources = [primary_source]
      term.prior_numberings.each { |prior| sources << prior_source(prior) }
      sources
    end

    private

    def primary_source
      Glossarist::V3::ConceptSource.new(
        type: "authoritative",
        origin: Glossarist::V3::Citation.new(
          ref: Glossarist::Citation::Ref.new(source: AUTHORITATIVE_SOURCE)
        )
      )
    end

    def prior_source(prior)
      Glossarist::V3::ConceptSource.new(
        type: "authoritative",
        origin: Glossarist::V3::Citation.new(
          ref: Glossarist::Citation::Ref.new(source: prior.standard, id: prior.legacy_id)
        )
      )
    end
  end
end
