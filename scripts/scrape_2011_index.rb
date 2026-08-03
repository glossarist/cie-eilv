#!/usr/bin/env ruby
# frozen_string_literal: true

require "cie_eilv"

records = CieEilv::Archive2011::Index.fetch_and_parse
CieEilv::Archive2011::Index.write_index(records, CieEilv::Archive2011::Paths::INDEX_PATH)

puts "Wrote #{records.length} terms to #{CieEilv::Archive2011::Paths::INDEX_PATH}"
puts "  first: #{records.first.inspect}"
puts "  last:  #{records.last.inspect}"
