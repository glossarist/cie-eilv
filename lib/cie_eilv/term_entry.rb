# frozen_string_literal: true

module CieEilv
  # Immutable value object representing the structured fields parsed from
  # a single e-ILV term page. The +TermParser+ produces these; the
  # +ConceptBuilder+ consumes them to build Glossarist v3 models.
  #
  # This is a pure data class — no behavior, no serialization. The builder
  # layer is responsible for mapping to Glossarist::V3::*.
  class TermEntry
    PRIOR_STANDARDS = %w[
      IEC\ 60050-845:1987
      CIE\ S\ 017:2011
    ].freeze

    PriorNumbering = Struct.new(:standard, :legacy_id, keyword_init: true) do
      def to_s
        "#{legacy_id} (#{standard})"
      end
    end

    attr_reader :termid, :designation, :usage_info, :part_of_speech,
                :symbol, :definition, :notes, :cross_refs,
                :prior_numberings, :raw_html

    def initialize(termid:, designation:, definition:, usage_info: nil,
                   part_of_speech: nil, symbol: nil, notes: [],
                   cross_refs: [], prior_numberings: [], raw_html: nil)
      @termid = termid
      @designation = designation
      @usage_info = usage_info
      @part_of_speech = part_of_speech
      @symbol = symbol
      @definition = definition
      @notes = notes
      @cross_refs = cross_refs
      @prior_numberings = prior_numberings
      @raw_html = raw_html
    end

    # Section prefix extracted from the termid (e.g. "21" for "17-21-012").
    def section_prefix
      termid.split("-")[1]
    end

    # True if a 2nd TermEntry paragraph yielded a symbol entry.
    def symbol?
      !symbol.nil? && !symbol.empty?
    end
  end
end
