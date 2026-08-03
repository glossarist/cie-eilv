#!/usr/bin/env ruby
# frozen_string_literal: true

# One-shot script that runs all four cie-2011 data-quality fixers
# in the right order:
#   1. IevSourceSyncer      — backs {{cite:...}} with ConceptSource entries
#   2. CrossEditionLinker   — adds CIE S 017:2020 source for reverse navigation
#   3. SectionMapper        — replaces section-all with real section from cross-edition map
# After running, regenerate the register to pick up the new section tree.

require "cie_eilv"

puts "== 1. IevSourceSyncer =="
CieEilv::Archive2011::IevSourceSyncer.new.run!

puts
puts "== 2. CrossEditionLinker =="
CieEilv::Archive2011::CrossEditionLinker.new.run!

puts
puts "== 3. SectionMapper =="
mapper = CieEilv::Archive2011::SectionMapper.new
mapper.run!
puts "Sections used: #{mapper.sections_used.inspect}"

puts
puts "== 4. Audit =="
exit CieEilv::Archive2011::Auditor.run!
