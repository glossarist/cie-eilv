#!/usr/bin/env ruby
# frozen_string_literal: true

require "cie_eilv"
require "json"

# Build cie-2011 → cie-2020 map
map_2011_to_2020 = {}
Dir.glob("datasets/cie-2020/concepts/*.yaml").each do |path|
  cf = CieEilv::ConceptFile.read(path)
  eng = cf.find_localized("eng")
  next unless eng
  termid_2020 = cf.managed&.data&.id
  next unless termid_2020
  eng.data.sources.each do |src|
    next unless src.origin&.ref&.source == "CIE S 017:2011"
    legacy = src.origin.ref.id.to_s
    legacy.scan(/17-(\d+)/) { |m| map_2011_to_2020[m[0]] = termid_2020 }
  end
end

# Walk cie-2011 concepts with broken image refs
results = []
Dir.glob("datasets/cie-2011/concepts/*.yaml").sort.each do |path|
  cf = CieEilv::ConceptFile.read(path)
  eng = cf.find_localized("eng")
  next unless eng

  archive_id = File.basename(path, ".yaml").sub(/\A17-/, "")
  texts = []
  [eng.data.definition, eng.data.notes, eng.data.examples].each do |coll|
    next unless coll.respond_to?(:each)
    coll.each { |e| texts << e.content.to_s if e.respond_to?(:content) }
  end
  full = texts.join("\n")
  next unless full =~ /<img[^>]*src="[^"]*im_\/[^"]*\.png/

  img_count = full.scan(%r{<img[^>]*src="[^"]*im_/[^"]*\.png"}).length
  termid_2020 = map_2011_to_2020[archive_id]

  result = {
    archive_id: archive_id,
    termid_2011: "17-#{archive_id}",
    termid_2020: termid_2020,
    img_count: img_count
  }

  if termid_2020
    path_2020 = "datasets/cie-2020/concepts/#{termid_2020}.yaml"
    if File.exist?(path_2020)
      cf2 = CieEilv::ConceptFile.read(path_2020)
      eng2 = cf2.find_localized("eng")
      if eng2
        notes_2020 = eng2.data.notes rescue []
        notes_text = ""
        notes_2020&.each { |n| notes_text += "\n" + n.content.to_s }
        def_text = (eng2.data.definition&.map(&:content) || []).join("\n")
        stem_in_def = def_text.scan(/stem:\[/).length
        stem_in_notes = notes_text.scan(/stem:\[/).length
        result[:stem_in_def] = stem_in_def
        result[:stem_in_notes] = stem_in_notes
        result[:notes_2020_count] = notes_2020.respond_to?(:size) ? notes_2020.size : 0
        result[:notes_2011_count] = eng.data.notes.respond_to?(:size) ? eng.data.notes.size : 0
      end
    end
  end

  results << result
end

puts "Investigation: 47 cie-2011 concepts with broken image refs vs cie-2020"
puts
puts "Concepts where cie-2020 HAS stem:[...] in notes (could potentially replace):"
could_replace = results.select { |r| r[:stem_in_notes].to_i > 0 }
puts "  Count: #{could_replace.length}"
could_replace.first(10).each do |r|
  puts "  #{r[:termid_2011]} → #{r[:termid_2020]}  (2020 notes have #{r[:stem_in_notes]} stem blocks; 2011 has #{r[:notes_2011_count]} notes, #{r[:img_count]} broken imgs)"
end
puts
puts "Concepts where cie-2020 has stem ONLY in definition (notes won't help):"
def_only = results.select { |r| r[:stem_in_notes].to_i == 0 && r[:stem_in_def].to_i > 0 }
puts "  Count: #{def_only.length}"
puts
puts "Concepts where cie-2020 has NO stem at all:"
no_stem = results.select { |r| r[:stem_in_notes].to_i == 0 && r[:stem_in_def].to_i == 0 }
puts "  Count: #{no_stem.length}"
no_stem.each do |r|
  puts "  #{r[:termid_2011]} → #{r[:termid_2020] or "UNMAPPED"}"
end
puts
puts "Concepts UNMAPPED to cie-2020:"
unmapped = results.select { |r| r[:termid_2020].nil? }
puts "  Count: #{unmapped.length}"
unmapped.each { |r| puts "  #{r[:termid_2011]}" }
