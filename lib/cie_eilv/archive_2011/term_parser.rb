# frozen_string_literal: true

require "nokogiri"

module CieEilv
  module Archive2011
    # Parses a single archived 2011 e-ILV term page (HTML) into a TermEntry.
    #
    # Page contract (verified against ~1400 cached pages):
    #
    #   <div id="content">
    #     <div class="breadcrumb">…</div>
    #     <div class="content-middle">
    #       <div class="node">
    #         <div class="content">
    #           <h2 class="header_neu">17-<archive_id></h2>
    #           <p>designation [<em>symbol</em>]</p>
    #           <p>definition paragraph 1</p>
    #           <p>definition paragraph 2 (e.g. math <img src="…/images/N-M.png">)</p>
    #           <p>Unit: …</p>
    #           <p>Equivalent term: "…"</p>
    #           <p>NOTE 1 …</p>
    #           <p>NOTE 2 …</p>
    #         </div>
    #       </div>
    #     </div>
    #   </div>
    #
    # The upstream HTML nests the designation <p> INSIDE the <h2>, but
    # HTML5 forbids block elements in headings, so Nokogiri (and any
    # spec-compliant parser) hoists the <p> to be a sibling. We rely on
    # the hoisted shape: h2.text is just the termid, and the first <p>
    # sibling is the designation.
    #
    # Notes:
    # - The h2 heading has the archive_id (Drupal node id) prefixed as
    #   "17-<id>". This becomes the termid.
    # - The designation paragraph may have a trailing [<symbol>] where the
    #   symbol contains HTML markup (italics, subscripts).
    # - Notes are prefixed with "NOTE N " — but the markup is irregular;
    #   some pages emit "NOTE11" with no space. The regex is permissive.
    # - "Unit:" and "Equivalent term:" are inline paragraphs in the
    #   definition flow, not separate fields.
    # - Cross-concept links appear as <a href="NNN"> (bare numeric, relative)
    #   or as Wayback-rewritten <a href="/web/<ts>/http://eilv.cie.co.at/term/NNN">.
    class TermParser
      class ParseError < StandardError; end

      # Matches "NOTE N", "NOTE  N", "NOTEN", "NOTE11", or just "NOTE"
      # (unnumbered, used on single-note pages). Captures trailing text.
      NOTE_RE = /\A\s*NOTE\s*\d*\s+/i.freeze

      # "Equivalent term: …" — captures the term text inside the quotes
      # (or unquoted if upstream forgot them).
      EQUIV_TERM_RE = /\A\s*Equivalent\s+term\s*:\s*(.+?)\s*\z/i.freeze

      # "Unit: …"
      UNIT_RE = /\A\s*Unit\s*:\s*(.+?)\s*\z/i.freeze

      # "See "<target>"" — alias pointer. Captures nothing; the cross-ref
      # in the body becomes the link.
      SEE_RE = /\A\s*See\s+["“]/i.freeze

      # Cross-ref href patterns. Bare numeric (Drupal relative) OR
      # Wayback-rewritten full URL.
      BARE_HREF_RE = %r{\A(\d+)\z}.freeze
      WAYBACK_HREF_RE = %r{/web/\d{14}(?:[a-z]{2}_)?/http://eilv\.cie\.co\.at/term/(\d)+}i.freeze

      class << self
        # Parse +html+ for the given +archive_id+. Returns a TermEntry.
        # Raises ParseError on contract violations.
        def parse(html, archive_id:)
          doc = Nokogiri::HTML(html)
          node = doc.at_css("div.content-middle div.node div.content")
          raise ParseError, "no .content-middle .node .content for archive_id=#{archive_id}" if node.nil?

          h2 = node.at_css("h2.header_neu")
          raise ParseError, "no h2.header_neu for archive_id=#{archive_id}" if h2.nil?

          archive_id_parsed = parse_termid(h2, archive_id)

          # The upstream HTML nests the designation <p> inside the <h2>,
          # but HTML5 forbids that, so Nokogiri hoists it to be the h2's
          # next sibling. The first <p> sibling is the designation; any
          # further <p> siblings are body content.
          designation_p = h2.next_element
          if designation_p && designation_p.name == "p"
            designation_html = inner_html_normalized(designation_p)
            body_paragraphs = collect_p_siblings(designation_p)
          else
            designation_html = ""
            body_paragraphs = []
          end

          designation, symbol = split_symbol(designation_html)
          definition, notes, equivalent_terms = classify_paragraphs(body_paragraphs)
          cross_refs = extract_cross_refs(body_paragraphs)

          TermEntry.new(
            archive_id: archive_id_parsed,
            termid: "17-#{archive_id_parsed}",
            designation: designation,
            symbol: symbol,
            definition: definition,
            notes: notes,
            equivalent_terms: equivalent_terms,
            cross_refs: cross_refs,
            raw_html: node.inner_html
          )
        end

        private

        def parse_termid(h2, fallback_archive_id)
          text = h2.text.to_s.strip
          m = text.match(/\A17-(\d+)\b/)
          m ? m[1] : fallback_archive_id.to_s
        end

        # All <p> siblings that follow +start_node+, stopping at the first
        # non-<p> sibling (e.g. the trailing <div style="clear:both">).
        def collect_p_siblings(start_node)
          siblings = []
          n = start_node
          while n.respond_to?(:next_element) && (n = n.next_element)
            break unless n.name == "p"
            siblings << n
          end
          siblings
        end

        # Split a designation HTML string of the form
        #   "designation text [<symbol markup>]"
        # into [designation, symbol]. Both may contain HTML markup.
        # If no trailing [...] block is present, symbol is nil.
        def split_symbol(html)
          # Find the LAST [ in the string; everything from there to the
          # matching ] is the symbol. We work on the raw HTML string so
          # markup inside the symbol is preserved.
          last_open = html.rindex("[")
          return [html.strip, nil] unless last_open

          after = html[(last_open + 1)..]
          close = after.rindex("]")
          return [html.strip, nil] unless close

          designation = html[0...last_open].strip
          symbol = after[0...close].strip
          [designation, symbol]
        end

        # All <p> siblings that follow the h2 inside the same .content div.
        def paragraphs_after(content_node, h2)
          siblings = []
          n = h2
          while n.respond_to?(:next_element) && (n = n.next_element)
            break unless n.name == "p"
            siblings << n
          end
          siblings
        end

        # Walk the body paragraphs and classify each into definition
        # (a single concatenated string), notes[], or equivalent_terms[].
        #
        # Definition = all leading paragraphs up to (but not including)
        # the first NOTE paragraph. Notes = NOTE paragraphs. Equivalent
        # term lines stay in the definition (they're inline labels, not
        # separate concepts in this dataset's modeling).
        def classify_paragraphs(paragraphs)
          definition_parts = []
          notes = []
          equivalent_terms = []
          in_notes = false

          paragraphs.each do |p|
            text = inner_html_normalized(p)

            if (note_match = text.match(NOTE_RE))
              in_notes = true
              note_text = text.sub(NOTE_RE, "").strip
              notes << note_text
              next
            end

            if in_notes
              # Continuation of a multi-paragraph note (rare but seen on
              # pages where NOTE text wraps). Append to the last note.
              if notes.empty?
                notes << text.strip
              else
                notes[-1] = "#{notes[-1]}\n#{text.strip}"
              end
              next
            end

            if (equiv = text.match(EQUIV_TERM_RE))
              equivalent_terms << strip_quotes(equiv[1])
              # Keep the line in the definition too — the inline label is
              # part of the rendered page.
              definition_parts << text.strip
              next
            end

            definition_parts << text.strip
          end

          definition = definition_parts.reject(&:empty?).join("\n\n")
          [definition, notes, equivalent_terms]
        end

        def extract_cross_refs(paragraphs)
          refs = []
          paragraphs.each do |p|
            p.css("a[href]").each do |a|
              href = a["href"].to_s.strip
              archive_id = resolve_archive_id(href)
              refs << archive_id if archive_id
            end
          end
          refs.uniq
        end

        # Given an href attribute value from the archived HTML, return the
        # archive_id it points at, or nil. Handles both the bare numeric
        # form (Drupal relative URL, e.g. "1014") and the Wayback-rewritten
        # form (e.g. "/web/20190917165407/http://eilv.cie.co.at/term/1014").
        def resolve_archive_id(href)
          if (m = href.match(BARE_HREF_RE))
            return m[1]
          end
          if (m = href.match(WAYBACK_HREF_RE))
            return m[1]
          end
          nil
        end

        # Normalize an element's inner HTML: collapse whitespace, normalize
        # Times New Roman font spans (just keep their contents — the styling
        # is purely visual and adds noise), keep semantic markup
        # (i, em, sub, sup, a, img).
        def inner_html_normalized(node)
          return "" if node.nil?
          # Re-parse into a fresh fragment so clean_node can mutate freely
          # without touching the source document.
          fragment = Nokogiri::HTML::DocumentFragment.parse(node.inner_html)
          clean_node(fragment)
          fragment_to_html(fragment)
        end

        # Recursively clean a node: drop font-family spans (keep contents),
        # normalize <em> → <i>, collapse whitespace.
        def clean_node(node)
          # Remove style spans (font-family wrappers) — keep their children.
          node.css("span[style*='font-family']").each do |span|
            span.replace(span.children)
          end

          # Normalize <em> → <i> for consistency with the 2020 transformer.
          node.css("em").each { |em| em.name = "i" }

          # Drop empty spans entirely.
          node.css("span").each do |span|
            span.replace(span.children) if span.children.empty?
          end

          node
        end

        # Render a node's children as an HTML string, preserving only the
        # semantic subset (i, b, sub, sup, a, img, br). Strip everything else.
        def fragment_to_html(node)
          parts = node.children.map { |child| render_child(child) }
          result = parts.join
          collapse_whitespace(result).strip
        end

        def render_child(child)
          case child
          when Nokogiri::XML::Text
            child.content
          when Nokogiri::XML::Element
            inner = fragment_to_html(child)
            case child.name
            when "i", "em" then "<i>#{inner}</i>"
            when "b", "strong" then "<b>#{inner}</b>"
            when "sub" then "<sub>#{inner}</sub>"
            when "sup" then "<sup>#{inner}</sup>"
            when "br" then "\n"
            when "a"
              href = child["href"].to_s
              %(<a href="#{href}">#{inner}</a>)
            when "img"
              src = child["src"].to_s
              %(<img src="#{src}">)
            else
              inner
            end
          else
            ""
          end
        end

        # Collapse runs of ASCII whitespace and &nbsp; into single spaces.
        # Preserve newlines (used to separate definition paragraphs and
        # multi-line notes).
        def collapse_whitespace(text)
          text
            .gsub(" ", " ")
            .gsub(/[ \t]+/, " ")
            .gsub(/ *\n */, "\n")
            .strip
        end

        def strip_quotes(text)
          text.strip.sub(/\A["“]/, "").sub(/["”]\z/, "").strip
        end
      end
    end
  end
end
