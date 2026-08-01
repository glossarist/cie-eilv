#!/usr/bin/env ruby
# frozen_string_literal: true

require "cie_eilv"

touched = CieEilv::CrossRefLinker.new.run!
puts "Done. #{touched} files updated."
