#!/usr/bin/env ruby
# frozen_string_literal: true

require "cie_eilv"
require "json"
require "fileutils"

STDOUT.sync = true

index_path = CieEilv::Archive2011::Paths::INDEX_PATH
index = JSON.parse(File.read(index_path))
concepts_dir = CieEilv::Archive2011::Paths::CONCEPTS_DIR
pages_dir = CieEilv::Archive2011::Paths::PAGES_DIR
FileUtils.mkdir_p(concepts_dir)

builder = CieEilv::Archive2011::ConceptBuilder.new
total = index.length
errors = []

index.each.with_index do |entry, i|
  archive_id = entry["archive_id"]
  wayback_url = entry["wayback_url"]
  html_path = File.join(pages_dir, "#{archive_id}.html")
  out_path = File.join(concepts_dir, "17-#{archive_id}.yaml")

  unless File.exist?(html_path)
    errors << "#{archive_id}: no cached page at #{html_path}"
    next
  end

  begin
    term = CieEilv::Archive2011::TermParser.parse(File.read(html_path), archive_id: archive_id)
    builder.write_concept(term, path: out_path, source_url: wayback_url)
  rescue CieEilv::Archive2011::TermParser::ParseError => e
    errors << "17-#{archive_id}: #{e.message}"
  end

  print "\r[#{i + 1}/#{total}] transformed    "
end

puts
puts "Wrote #{total - errors.length}/#{total} concept files to #{concepts_dir}/"
return if errors.empty?

warn "#{errors.length} error(s):"
errors.first(20).each { |e| warn "  - #{e}" }
warn "..." if errors.length > 20
exit 1
