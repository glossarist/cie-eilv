# frozen_string_literal: true

require "yaml"
require "set"

module CieEilv
  # Fixes designation types: acronyms (UVR, LED, CCT, etc.) were
  # incorrectly typed as "symbol" instead of "abbreviation".
  #
  # Per concept-model:
  #   ExpressionDesignation — linguistic term (general concept name)
  #   AbbreviationDesignation — shortened form (acronym, initialism)
  #   SymbolDesignation — mathematical/graphical notation (Φ_e, λ, E_v)
  #   LetterSymbolDesignation — letter symbols (same as symbol but letters)
  #
  # All-caps Latin letter sequences like "UVR", "CCT", "LED" are
  # abbreviations, NOT symbols.
  class DesignationTypeFixer
    ABBR_RE = /\A[A-Z][A-Z0-9-]{1,}\z/.freeze

    attr_reader :stats

    def initialize(concepts_dirs:)
      @concepts_dirs = concepts_dirs
      @stats = { touched: 0, fixed: 0 }
    end

    def run!
      @concepts_dirs.each do |dir|
        Dir.glob(File.join(dir, "*.yaml")).sort.each do |path|
          process_file(path)
        end
      end
      warn "DesignationTypeFixer: touched=#{@stats[:touched]} fixed=#{@stats[:fixed]}"
    end

    private

    def process_file(path)
      raw = File.read(path)
      docs = YAML.load_stream(raw)
      changed = false

      docs.each do |doc|
        next unless doc.is_a?(Hash)
        data = doc["data"]
        next unless data.is_a?(Hash)

        terms = data["terms"]
        next unless terms.is_a?(Array)

        terms.each do |t|
          next unless t.is_a?(Hash)
          next unless t["type"] == "symbol"
          desig = t["designation"].to_s
          next unless ABBR_RE.match?(desig)
          # Skip if it looks like a math symbol (has subscripts/braces)
          next if desig.match?(/[_\^{}\[\]]/)
          t["type"] = "abbreviation"
          changed = true
          @stats[:fixed] += 1
        end
      end

      return unless changed

      File.write(path, yaml_stream(docs))
      @stats[:touched] += 1
    end

    def yaml_stream(docs)
      docs.map { |d| d.to_yaml }.join("---\n").gsub(/^---\n---\n/, "---\n")
    end
  end
end
