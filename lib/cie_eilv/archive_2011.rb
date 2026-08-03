# frozen_string_literal: true

module CieEilv
  # CIE S 017:2011 ILV (1st edition), as archived on web.archive.org.
  # The original eilv.cie.co.at site was decommissioned after the 2020
  # edition launched; archive.org is the only source.
  module Archive2011
    autoload :Paths,           "cie_eilv/archive_2011/paths"
    autoload :Client,          "cie_eilv/archive_2011/client"
    autoload :Index,           "cie_eilv/archive_2011/index"
    autoload :TermEntry,       "cie_eilv/archive_2011/term_entry"
    autoload :TermParser,      "cie_eilv/archive_2011/term_parser"
    autoload :ConceptBuilder,  "cie_eilv/archive_2011/concept_builder"
    autoload :RegisterBuilder, "cie_eilv/archive_2011/register_builder"
    autoload :CrossRefLinker,  "cie_eilv/archive_2011/cross_ref_linker"
    autoload :Auditor,         "cie_eilv/archive_2011/auditor"
    autoload :IevMathImporter, "cie_eilv/archive_2011/iev_math_importer"
    autoload :IevSourceSyncer, "cie_eilv/archive_2011/iev_source_syncer"
    autoload :CrossEditionLinker, "cie_eilv/archive_2011/cross_edition_linker"
    autoload :SectionMapper, "cie_eilv/archive_2011/section_mapper"
  end
end
