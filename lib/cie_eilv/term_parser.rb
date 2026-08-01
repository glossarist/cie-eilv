# frozen_string_literal: true

require "nokogiri"

module CieEilv
  # Parses a single e-ILV term page (HTML) into a TermEntry value object.
  #
  # The page markup inside <article class="node node--type-eilvterm ...">
  # uses a small fixed set of CSS classes — see CLAUDE.md "e-ILV HTML
  # structure" for the contract. This parser knows about that contract
  # and nothing else; the TermEntry it returns is plain data.
  class TermParser
    class ParseError < StandardError; end

    # "Note N to entry: " — Drupal emits <span class="NoteLabel">; we strip
    # both the wrapper and any leading text matching this pattern (defensive).
    NOTE_LABEL_RE = /\ANote \s*\d+ \s* to \s* entry:\s*/x.freeze

    # "This entry was numbered <legacy_id> in <standard>." — dual-purpose note.
    # legacy_id is a free-form token up to the literal " in " separator.
    PRIOR_NUMBER_RE =
      /\AThis \s+ entry \s+ was \s+ numbered \s+
       (?<legacy_id>.+?) \s+ in \s+
       (?<standard>IEC \s 60050-845:1987 | CIE \s S \s 017:2011)
       \s*\.\s*\z/x.freeze

    class << self
      # Parse +html+ (a full term page body) for the given +termid+.
      # Returns a CieEilv::TermEntry. Raises ParseError on contract violations.
      def parse(html, termid:)
        doc = Nokogiri::HTML(html)
        body = doc.at_css("article.node--type-eilvterm .field--name-body")
        raise ParseError, "no .field--name-body in term page #{termid}" if body.nil?

        term_entries = body.css("p.TermEntry").to_a
        raise ParseError, "no <p class='TermEntry'> in #{termid}" if term_entries.empty?

        designation, usage_info, part_of_speech = split_designation(term_entries.first)
        symbol = symbol_entry(term_entries[1..])

        definition = body.at_css("p.Definition")&.then { |n| clean_html(n) } || ""

        note_texts = body.css("p.Note")
                          .map { |n| extract_note_text(n) }
                          .compact
                          .reject { |t| t.empty? }

        cross_refs = body.css("a[href^='/eilvterm/']")
                         .map { |a| a["href"].sub(%r{\A/eilvterm/}, "") }
                         .uniq

        prior_numberings, real_notes = classify_notes(note_texts)

        TermEntry.new(
          termid: termid,
          designation: designation,
          usage_info: usage_info,
          part_of_speech: part_of_speech,
          symbol: symbol,
          definition: definition,
          notes: real_notes,
          cross_refs: cross_refs,
          prior_numberings: prior_numberings,
          raw_html: body.inner_html
        )
      end

      private

      # Split a <p class="TermEntry"> into (designation, usage_info, part_of_speech).
      #
      # The TermEntry paragraph's full text is `designation + ", " + suffix`
      # where the suffix is `<usage_info> part_of_speech` (or just POS, or
      # just usage_info). The upstream HTML may split the suffix across
      # multiple <span class="TermDesc"> elements when the usage_info
      # contains an inline cross-concept link (e.g. 17-21-032
      # "source, <of optical radiation>" — "optical radiation" is hyperlinked).
      # Rather than parse the spans individually, we take the full text and
      # split on the first ", ".
      def split_designation(term_entry_node)
        full_text = clean_text(term_entry_node.text)

        if full_text =~ /\A(.*?),\s+(.*)\z/m
          designation = $1.strip
          suffix = $2.strip
        else
          return [full_text, nil, nil]
        end

        usage_info = nil
        part_of_speech = nil

        if suffix =~ /<([^>]+)>/
          usage_info = $1.strip
          suffix = suffix.sub(/<[^>]+>\s*/, "")
        end

        part_of_speech = suffix.strip.empty? ? nil : suffix.strip
        [designation, usage_info, part_of_speech]
      end

      # If there are multiple <p class="TermEntry"> paragraphs, the second
      # (and beyond) are symbol entries. Returns the first non-empty symbol
      # text, or nil.
      def symbol_entry(nodes)
        return nil if nodes.nil? || nodes.empty?

        nodes.each do |n|
          text = clean_text(n.text)
          return text unless text.empty?
        end
        nil
      end

      # Strip the NoteLabel span and clean whitespace from a Note <p>.
      # Returns nil for empty Notes (the separator artifact).
      def extract_note_text(note_node)
        # Work on a copy so the original doc is untouched.
        node = note_node.dup
        node.css("span.NoteLabel").remove
        text = clean_html(node)
        # Belt-and-suspenders: strip any leading "Note N to entry: " the
        # NoteLabel removal missed (e.g. malformed pages where the label
        # is plain text, not wrapped).
        text = text.sub(NOTE_LABEL_RE, "")
        text.strip!
        text.empty? ? nil : text
      end

      # Partition note texts into prior-numbering records vs. substantive notes.
      # Prior-numbering notes are ALSO kept verbatim in the substantive list
      # (they carry user-visible provenance); the records are an additional
      # structured form for the builder to emit as sources[].
      def classify_notes(note_texts)
        prior = []
        note_texts.each do |text|
          if (m = text.match(PRIOR_NUMBER_RE))
            prior << TermEntry::PriorNumbering.new(
              standard: m[:standard].gsub(/\s+/, " "),
              legacy_id: m[:legacy_id].strip
            )
          end
        end
        [prior, note_texts]
      end

      # Convert an HTML fragment (Nokogiri node) to text-with-minimal-markup.
      # Drupal uses <italic> instead of <i>; we normalize. <a href="/eilvterm/...">
      # anchors are preserved verbatim — the CrossRefLinker rewrites them later.
      def clean_html(node)
        return "" if node.nil?

        # Normalize <italic> → <i>. The fragment re-parse catches nested cases.
        normalized = node.inner_html.gsub(/<(\/?)italic>/, '<\1i>')
        fragment = Nokogiri::HTML::DocumentFragment.parse(normalized)
        collapse_whitespace(fragment_to_text(fragment))
      end

      # Walk the fragment emitting text with minimal inline markup preserved.
      def fragment_to_text(node)
        result = +""
        node.children.each do |child|
          case child
          when Nokogiri::XML::Text
            result << child.content
          when Nokogiri::XML::Element
            inner = fragment_to_text(child)
            case child.name
            when "a"
              href = child["href"].to_s
              result << %(<a href="#{href}">#{inner}</a>)
            when "i", "em"
              result << "<i>#{inner}</i>"
            when "b", "strong"
              result << "<b>#{inner}</b>"
            when "sub"
              result << "<sub>#{inner}</sub>"
            when "sup"
              result << "<sup>#{inner}</sup>"
            when "br"
              result << "\n"
            else
              result << inner
            end
          end
        end
        result
      end

      # Collapse runs of whitespace (incl. &nbsp;) into single spaces.
      # Preserve newlines (multi-line formula notes use them).
      def collapse_whitespace(text)
        text
          .gsub(" ", " ")
          .gsub(/[ \t]+/, " ")
          .gsub(/ *\n */, "\n")
          .strip
      end

      def clean_text(text)
        collapse_whitespace(text.to_s.gsub(" ", " "))
      end
    end
  end
end
