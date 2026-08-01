#!/usr/bin/env ruby
# frozen_string_literal: true

require "cie_eilv"

register = CieEilv::RegisterBuilder.new.run!
puts "Wrote #{CieEilv::Paths::REGISTER_PATH}"
puts "Sections: #{register['sections'].length}"
