#!/usr/bin/env ruby
# frozen_string_literal: true

require "cie_eilv"

records = CieEilv::TermIndex.fetch_and_parse
CieEilv::TermIndex.write_index(records, CieEilv::Paths::INDEX_PATH)

puts "Wrote #{records.length} terms to #{CieEilv::Paths::INDEX_PATH}"
puts "  first: #{records.first.inspect}"
puts "  last:  #{records.last.inspect}"
