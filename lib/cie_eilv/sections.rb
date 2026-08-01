# frozen_string_literal: true

module CieEilv
  # Single source of truth for the 12 ILV section names (term-id prefix
  # 17-21 through 17-32). Sections are derived from the term-id prefix;
  # this module supplies the human-readable titles.
  module Sections
    # Term-id section prefix → section title.
    # Sourced from CIE S 017:2020 ILV table of contents, cross-checked
    # against the e-ILV term listing topic clustering.
    TABLE = {
      "21" => "Electromagnetic radiation and optical radiation",
      "22" => "Visual perception",
      "23" => "Colorimetry",
      "24" => "Optical properties of materials and media",
      "25" => "Radiometric and photometric measurement",
      "26" => "Actinic effects of optical radiation",
      "27" => "Optical radiation sources and lighting equipment",
      "28" => "Lamp components and ancillaries",
      "29" => "Lighting and daylighting",
      "30" => "Luminaires and lighting equipment",
      "31" => "Visual signalling",
      "32" => "Imaging technology"
    }.freeze

    # Returns the title for a section prefix, or "Section <n>" fallback.
    def self.title_for(section_prefix)
      TABLE[section_prefix.to_s] || "Section #{section_prefix}"
    end

    # All known section prefixes in canonical (numeric) order.
    def self.all
      TABLE.keys.sort
    end
  end
end
