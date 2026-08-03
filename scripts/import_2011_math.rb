#!/usr/bin/env ruby
# frozen_string_literal: true

require "cie_eilv"

importer = CieEilv::Archive2011::IevMathImporter.new
importer.run!
puts
puts "Stats: #{importer.stats.inspect}"
