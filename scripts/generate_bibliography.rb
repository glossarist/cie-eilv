#!/usr/bin/env ruby
# frozen_string_literal: true

require "cie_eilv"
require "yaml"

# Scan cached term-page HTML for IEV (Electropedia) references — any
# nnn-mm-pp pattern (2-3 digit chapter prefix) except 17-* (those are
# ILV-internal cross-refs handled by CrossRefLinker). Emit one
# bibliography entry per unique IEV id, with a link to the corresponding
# Electropedia page.
#
# Why we scan HTML, not the generated YAML: TermParser currently drops
# some content (notably `<p class="Definition">[SOURCE: ...]</p>` blocks
# when they're the second Definition paragraph on a page). Scanning the
# source-of-truth HTML catches every IEV ref regardless of transform
# gaps.
#
# concept-browser renders bibliography entries on the per-dataset Sources
# page; the link field makes each IEV id clickable through to Electropedia.

OUT_PATH = File.join(CieEilv::Paths::DATASET_DIR, "bibliography.yaml")
ELECTROPEDIA_URL = "https://www.electropedia.org/iev/iev.nsf/display?openform&ievref=%s".freeze
IEV_RE = /\b(\d{2,3}-\d{2}-\d{2,3})\b/.freeze

refs = Hash.new { |h, k| h[k] = 0 }
Dir.glob("#{CieEilv::Paths::PAGES_DIR}/*.html").each do |path|
  File.read(path).scan(IEV_RE).each do |match|
    iev_id = match[0]
    next if iev_id.start_with?("17-") # ILV-internal, not IEV
    refs[iev_id] += 1
  end
end

bib = refs.keys.sort.each_with_object({}) do |iev_id, h|
  h[iev_id] = {
    "reference" => "IEC 60050 (IEV) #{iev_id}",
    "link" => format(ELECTROPEDIA_URL, iev_id),
  }
end

File.write(OUT_PATH, YAML.dump(bib))
puts "Wrote #{bib.length} IEV references to #{OUT_PATH}"
puts "  by prefix:"
refs.keys.group_by { |k| k.split("-").first }.sort.each do |prefix, ids|
  puts "    #{prefix}-*: #{ids.length}"
end
