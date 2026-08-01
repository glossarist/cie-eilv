# frozen_string_literal: true

require "glossarist"
require "json"
require "fileutils"
require "yaml"
require "nokogiri"
require "uri"
require "digest"
require "securerandom"

module CieEilv
  autoload :Version,          "cie_eilv/version"
  autoload :Paths,            "cie_eilv/paths"
  autoload :Uuid,             "cie_eilv/uuid"
  autoload :ApiClient,        "cie_eilv/api_client"
  autoload :TermIndex,        "cie_eilv/term_index"
  autoload :TermEntry,        "cie_eilv/term_entry"
  autoload :TermParser,       "cie_eilv/term_parser"
  autoload :ConceptFile,      "cie_eilv/concept_file"
  autoload :ConceptBuilder,   "cie_eilv/concept_builder"
  autoload :Sections,         "cie_eilv/sections"
  autoload :RegisterBuilder,  "cie_eilv/register_builder"
  autoload :CrossRefLinker,   "cie_eilv/cross_ref_linker"
  autoload :Auditor,          "cie_eilv/auditor"
end
