# frozen_string_literal: true

module CieEilv
  module Archive2011
    # Immutable value object representing the structured fields parsed from
    # a single archived 2011 e-ILV term page. TermParser produces these;
    # ConceptBuilder consumes them.
    #
    # Unlike the 2020 TermEntry, the 2011 markup has no structured
    # usage_info or part_of_speech — those are 2020-edition additions.
    # The 2011 designation is freeform text, optionally with a trailing
    # [<symbol>] (with HTML markup for italics/sub/sup).
    class TermEntry
      attr_reader :archive_id, :termid, :designation, :symbol,
                  :definition, :notes, :equivalent_terms,
                  :cross_refs, :raw_html

      def initialize(archive_id:, termid:, designation:, definition:,
                     symbol: nil, notes: [], equivalent_terms: [],
                     cross_refs: [], raw_html: nil)
        @archive_id = archive_id
        @termid = termid
        @designation = designation
        @symbol = symbol
        @definition = definition
        @notes = notes
        @equivalent_terms = equivalent_terms
        @cross_refs = cross_refs
        @raw_html = raw_html
      end

      def symbol?
        !symbol.nil? && !symbol.empty?
      end

      # True if the page's body is just a "See X" pointer with no real
      # definition. These are alias entries — the upstream site lists
      # the term but defers to a canonical entry for the definition.
      def alias?
        definition.to_s.match?(/\A\s*See\s+"/i) && notes.empty?
      end
    end
  end
end
