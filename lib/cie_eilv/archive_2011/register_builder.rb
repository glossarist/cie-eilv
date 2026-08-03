# frozen_string_literal: true

require "json"
require "yaml"
require "fileutils"

module CieEilv
  module Archive2011
    # Builds the cie-2011 register.yaml: metadata + flat single-section tree.
    #
    # The 2011 ILV term IDs are flat (17-XXXX) without a section prefix.
    # Without per-term section information (which would require cross-
    # edition mapping via the 2020 prior-numbering notes), every concept
    # lives under a single "section-all" bucket. Real section structure
    # is a future enhancement.
    class RegisterBuilder
      DATASET_ID   = Paths::DATASET_ID
      URN          = Paths::URN
      OWNER        = "CIE".freeze
      YEAR         = 2011
      REF          = "CIE S 017:2011 ILV: International Lighting Vocabulary, 1st edition".freeze
      DESCRIPTION  = "The International Lighting Vocabulary (ILV), 1st edition " \
                     "(CIE S 017:2011). Archived snapshot of the defunct " \
                     "eilv.cie.co.at site, scraped from web.archive.org.".freeze
      TAGS         = %w[lighting illumination photometry colorimetry cie ilv archive].freeze

      attr_reader :out_path

      def initialize(out_path: Paths::REGISTER_PATH)
        @out_path = out_path
      end

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
          "status"         => "historical",
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
        # The 12 ILV sections are stable across editions (CIE S 017:2011
        # and 2020 share the same section structure even though 2011
        # uses flat 17-NNNN IDs). SectionMapper assigned each cie-2011
        # concept to its section via the cross-edition map; unmapped
        # concepts land in "unknown".
        sections = ("21".."32").to_a + ["unknown"]
        sections.map do |prefix|
          title = prefix == "unknown" ? "Unmapped (no 2020 sibling)" : CieEilv::Sections.title_for(prefix)
          {
            "id"       => prefix,
            "names"    => { "eng" => title },
            "children" => []
          }
        end
      end

      def render(register)
        YAML.dump(register)
      end
    end
  end
end
