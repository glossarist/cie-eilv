#!/usr/bin/env ruby
# frozen_string_literal: true

require "cie_eilv"

linker = CieEilv::Archive2011::CrossRefLinker.new
touched = linker.run!
puts "CrossRefLinker: touched #{touched} files under #{CieEilv::Archive2011::Paths::CONCEPTS_DIR}/"
