#!/usr/bin/env ruby
# frozen_string_literal: true

# Convert residual HTML math tags to Asciidoc subscripts/superscripts +
# stem blocks. Run after import_2011_math.rb to handle notes the
# cross-edition importer left untouched.

require "cie_eilv"

concepts_dir = ARGV[0] || CieEilv::Archive2011::Paths::CONCEPTS_DIR
abort "not a directory: #{concepts_dir}" unless File.directory?(concepts_dir)

converter = CieEilv::MathTagConverter.new(concepts_dir:)
converter.run!
puts "Done. Stats: #{converter.stats.inspect}"
