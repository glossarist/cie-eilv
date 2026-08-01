# frozen_string_literal: true

require "json"
require "yaml"

module CieEilv
  # Builds the per-dataset register.yaml: metadata + section tree.
  #
  # The section tree is derived from the term-id section prefix; section
  # titles come from CieEilv::Sections. Term counts are NOT embedded —
  # the concept-browser derives them from the concept files on disk.
  class RegisterBuilder
    DATASET_ID   = Paths::DATASET_ID
    URN          = Paths::URN
    OWNER        = "CIE".freeze
    YEAR         = 2020
    REF          = "CIE S 017:2020 ILV: International Lighting Vocabulary, 2nd edition".freeze
    DESCRIPTION  = "The International Lighting Vocabulary (ILV), 2nd edition (CIE S 017:2020). " \
                   "Free electronic edition provided by the CIE at https://cie.co.at/e-ilv.".freeze
    TAGS         = %w[lighting illumination photometry colorimetry cie ilv].freeze

    attr_reader :out_path

    def initialize(out_path: Paths::REGISTER_PATH)
      @out_path = out_path
    end

    # Builds and writes the register. Returns the register Hash (string keys).
    def run!
      register = build_register
      FileUtils.mkdir_p(File.dirname(out_path))
      File.write(out_path, render(register))
      register
    end

    private

    def build_register
      {
        "schema_type"    => "glossarist",
        "schema_version" => "3",
        "id"             => DATASET_ID,
        "ref"            => REF,
        "year"           => YEAR,
        "urn"            => URN,
        "status"         => "current",
        "owner"          => OWNER,
        "source_repo"    => "https://github.com/glossarist/cie-eilv",
        "tags"           => TAGS,
        "languages"      => ["eng"],
        "language_order" => ["eng"],
        "ordering"       => "systematic",
        "description"    => { "eng" => DESCRIPTION },
        "sections"       => build_section_tree
      }
    end

    def build_section_tree
      Sections.all.map do |prefix|
        {
          "id"       => prefix,
          "names"    => { "eng" => Sections.title_for(prefix) },
          "children" => []
        }
      end
    end

    # YAML.dump quotes "21" naturally (because it could parse as Integer),
    # so no extra quoting pass needed. String keys render as bare keys.
    def render(register)
      YAML.dump(register)
    end
  end
end
