#!/usr/bin/env ruby
# frozen_string_literal: true

require "cie_eilv"
require "json"
require "fileutils"

STDOUT.sync = true

index_path = CieEilv::Archive2011::Paths::INDEX_PATH
index = JSON.parse(File.read(index_path))
pages_dir = CieEilv::Archive2011::Paths::PAGES_DIR
FileUtils.mkdir_p(pages_dir)

# Optional slicing for parallel runs. CIE_SCRAPE_SLICE="0/3" means
# "slice 0 of 3" — take every 3rd entry starting at index 0.
slice_spec = ENV.fetch("CIE_SCRAPE_SLICE", nil)
if slice_spec && slice_spec =~ %r{\A(\d+)/(\d+)\z}
  slice_idx = Regexp.last_match(1).to_i
  slice_count = Regexp.last_match(2).to_i
  index = index.each_slice(slice_count).map { |chunk| chunk[slice_idx] }.compact
end

total = index.length
fetched = 0
cached = 0
failed = []

index.each.with_index do |entry, i|
  archive_id = entry["archive_id"]
  wayback_url = entry["wayback_url"]
  out = File.join(pages_dir, "#{archive_id}.html")

  if File.exist?(out) && File.size(out) > 0
    cached += 1
  else
    begin
      # The index already resolved the snapshot URL via CDX; go straight
      # to fetch_raw and skip the availability API.
      body = CieEilv::Archive2011::Client.fetch_raw(wayback_url)
      File.write(out, body)
      fetched += 1
    rescue CieEilv::Archive2011::Client::Error => e
      warn "\nFAILED #{archive_id}: #{e.class}: #{e.message}"
      failed << { archive_id: archive_id, wayback_url: wayback_url,
                  error: "#{e.class}: #{e.message}" }
      File.delete(out) if File.exist?(out)
    end
  end

  print "\r[#{i + 1}/#{total}] fetched=#{fetched} cached=#{cached} failed=#{failed.length}    "
end

puts
puts "Done: #{total} term pages (#{fetched} fetched, #{cached} cached, #{failed.length} failed) under #{pages_dir}/"

unless failed.empty?
  report_path = File.join(CieEilv::Archive2011::Paths::REFERENCE_DIR, "fetch-failures.json")
  FileUtils.mkdir_p(File.dirname(report_path))
  File.write(report_path, JSON.pretty_generate(failed))
  warn "Failures written to #{report_path}"
end
