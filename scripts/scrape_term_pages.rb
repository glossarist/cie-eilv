#!/usr/bin/env ruby
# frozen_string_literal: true

require "cie_eilv"
require "json"
require "fileutils"

STDOUT.sync = true  # flush progress lines so \r doesn't hide stderr

index = JSON.parse(File.read(CieEilv::Paths::INDEX_PATH))
FileUtils.mkdir_p(CieEilv::Paths::PAGES_DIR)

total = index.length
fetched = 0
cached = 0

index.each.with_index do |entry, i|
  termid = entry["termid"]
  out = File.join(CieEilv::Paths::PAGES_DIR, "#{termid}.html")

  if File.exist?(out) && File.size(out) > 0
    cached += 1
  else
    begin
      File.write(out, CieEilv::ApiClient.fetch_term(termid))
      fetched += 1
    rescue CieEilv::ApiClient::Error => e
      warn "\nFAILED #{termid}: #{e.class}: #{e.message}"
      # Leave a marker so a later run can retry, but don't halt — ship partial.
      File.delete(out) if File.exist?(out)
    end
  end

  print "\r[#{i + 1}/#{total}] fetched=#{fetched} cached=#{cached}    "
end

puts
puts "Done: #{total} term pages (#{fetched} fetched, #{cached} cached) under #{CieEilv::Paths::PAGES_DIR}/"

