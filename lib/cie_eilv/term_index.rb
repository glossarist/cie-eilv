# frozen_string_literal: true

require "nokogiri"

module CieEilv
  # Parses the single-page e-ILV listing at https://cie.co.at/e-ilv into a
  # flat list of {termid:, listing_designation:} records.
  #
  # The listing has no pagination (all ~1,300 terms in one HTML page) and
  # no explicit section headers — sections are implied by the term-id
  # prefix (17-21 through 17-32).
  class TermIndex
    SELECTOR = ".views-row a[href^='/eilvterm/']".freeze

    class << self
      # Parse +listing_html+ and return an Array of
      # {termid:, listing_designation:} records sorted by termid.
      def parse(listing_html)
        doc = Nokogiri::HTML(listing_html)
        doc.css(SELECTOR).map { |a| row_from_anchor(a) }
           .reject { |r| r.nil? }
           .sort_by { |r| r[:termid] }
      end

      # Fetch the live listing (via ApiClient) and parse it.
      def fetch_and_parse
        parse(ApiClient.fetch_listing)
      end

      # Write +records+ (as returned by .parse) as pretty JSON to +path+.
      def write_index(records, path)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, JSON.pretty_generate(records))
      end

      private

      def row_from_anchor(anchor)
        termid = anchor.text.strip
        return nil unless termid =~ /\A17-\d{2}-\d{3}\z/

        span = anchor.ancestors("span").first || anchor.parent
        designation = strip_leading_termid(span.text, termid)
        { termid: termid, listing_designation: designation }
      end

      def strip_leading_termid(text, termid)
        # &nbsp; decodes to   in Nokogiri text output; collapse both
        #   and ASCII spaces after the leading termid.
        text.strip
            .sub(/\A#{Regexp.escape(termid)}[\s ]*/, "")
            .gsub(/[ ]/, " ")
            .strip
      end
    end
  end
end
