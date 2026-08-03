#!/usr/bin/env ruby
# frozen_string_literal: true

require "cie_eilv"

# Converts remaining HTML math tags (<i>, <sub>, <sup>) in concept
# definition/notes/examples content to proper notation:
#   <i>X</i>        → stem:[X]
#   <sub>e</sub>    → ~e~  (AsciiDoc subscript, adjacent to stem)
#   <sup>−1</sup>   → stem:[^(-1)]  where context allows
#
# Runs after IevMathImporter handles the bulk of conversions via iev-data.
# This catches residual tags in notes that iev-data doesn't cover.

module CieEilv
  class MathTagConverter
    I_TAG_RE = %r{<i>([^<]*)</i>}.freeze
    SUB_TAG_RE = %r{<sub>([^<]*)</sub>}.freeze
    SUP_TAG_RE = %r{<sup>([^<]*)</sup>}.freeze
    NESTED_I_SUB_RE = %r{<i><sub>([^<]*)</sub></i>}.freeze

    attr_reader :stats

    def initialize(concepts_dir: Paths::CONCEPTS_DIR)
      @concepts_dir = concepts_dir
      @stats = { touched: 0 }
    end

    def run!
      Dir.glob(File.join(@concepts_dir, "*.yaml")).sort.each do |path|
        cf = ConceptFile.read(path)
        loc = cf.find_localized("eng")
        next unless loc

        changed = false
        [loc.data.definition, loc.data.notes, loc.data.examples].each do |collection|
          next unless collection.respond_to?(:each)
          collection.each do |entry|
            original = entry.content
            next unless original
            converted = convert_tags(original)
            next if converted == original
            entry.content = converted
            changed = true
          end
        end

        # Also process term designations — symbols and admitted terms
        # often carry inline math (e.g. <i>H</i><sub>e,o</sub>).
        if loc.data.terms.respond_to?(:each)
          loc.data.terms.each do |term|
            next unless term.respond_to?(:designation) && term.designation.is_a?(String)
            original = term.designation
            converted = convert_tags(original)
            next if converted == original
            term.designation = converted
            changed = true
          end
        end

        next unless changed
        cf.save
        @stats[:touched] += 1
      end
      warn "MathTagConverter: touched #{@stats[:touched]} files"
    end

    private

    def convert_tags(text)
      result = text
      # Handle nested <i><sub>x</sub></i> → ~x~ first
      result = result.gsub(NESTED_I_SUB_RE) { "~#{Regexp.last_match(1)}~" }
      # <i>content</i> → stem:[content]
      result = result.gsub(I_TAG_RE) { "stem:[#{Regexp.last_match(1)}]" }
      # <sub>content</sub> → ~content~
      result = result.gsub(SUB_TAG_RE) { "~#{Regexp.last_match(1)}~" }
      # <sup>content</sup> → ^content^  (AsciiDoc superscript)
      result = result.gsub(SUP_TAG_RE) { "^#{Regexp.last_match(1)}^" }
      result
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  CieEilv::MathTagConverter.new.run!
end
