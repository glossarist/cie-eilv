#!/usr/bin/env ruby
# frozen_string_literal: true

require "cie_eilv"
require "json"
require "fileutils"

STDOUT.sync = true

index = JSON.parse(File.read(CieEilv::Paths::INDEX_PATH))
FileUtils.mkdir_p(CieEilv::Paths::CONCEPTS_DIR)

builder = CieEilv::ConceptBuilder.new
total = index.length
errors = []

index.each.with_index do |entry, i|
  termid = entry["termid"]
  html_path = File.join(CieEilv::Paths::PAGES_DIR, "#{termid}.html")
  out_path = File.join(CieEilv::Paths::CONCEPTS_DIR, "#{termid}.yaml")

  unless File.exist?(html_path)
    errors << "#{termid}: no cached page at #{html_path}"
    next
  end

  begin
    term = CieEilv::TermParser.parse(File.read(html_path), termid: termid)
    builder.write_concept(term, path: out_path)
  rescue CieEilv::TermParser::ParseError => e
    errors << "#{termid}: #{e.message}"
  end

  print "\r[#{i + 1}/#{total}] transformed    "
end

puts
puts "Wrote #{total - errors.length}/#{total} concept files to #{CieEilv::Paths::CONCEPTS_DIR}/"
if errors.any?
  warn "#{errors.length} error(s):"
  errors.first(20).each { |e| warn "  - #{e}" }
  warn "..." if errors.length > 20
  exit 1
end
