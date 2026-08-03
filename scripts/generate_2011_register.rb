#!/usr/bin/env ruby
# frozen_string_literal: true

require "cie_eilv"

CieEilv::Archive2011::RegisterBuilder.new.run!
puts "Wrote #{CieEilv::Archive2011::Paths::REGISTER_PATH}"
