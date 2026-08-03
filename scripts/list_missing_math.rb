#!/usr/bin/env ruby
# frozen_string_literal: true

require "cie_eilv"
require "json"

missing = []
Dir.glob("datasets/cie-2011/concepts/*.yaml").sort.each do |path|
  cf = CieEilv::ConceptFile.read(path)
  eng = cf.find_localized("eng")
  next unless eng

  texts = []
  [eng.data.definition, eng.data.notes, eng.data.examples].each do |coll|
    next unless coll.respond_to?(:each)
    coll.each { |e| texts << e.content.to_s if e.respond_to?(:content) }
  end
  (eng.data.terms || []).each do |t|
    texts << t.designation.to_s if t.respond_to?(:designation)
  end

  full = texts.join("\n")
  next unless full =~ %r{<i>|<sub>|<sup>|<img}

  preferred = eng.data.terms&.find { |t| t.normative_status == "preferred" }
  designation = preferred ? preferred.designation : "?"

  missing << {
    termid: cf.managed.data.id,
    designation: designation,
    img_count: full.scan(%r{<img[^>]*>}).length,
    img_missing: full.scan(%r{<img[^>]*src="[^"]*im_/[^"]*\.png"}).length,
    i_count: full.scan(/<i>([^<]*)<\/i>/).length,
    sub_count: full.scan(/<sub>/).length,
    sup_count: full.scan(/<sup>/).length
  }
end

puts "TOTAL: #{missing.length} cie-2011 concepts with residual HTML/img math"
puts
puts "BREAKDOWN"
img_total     = missing.sum { |m| m[:img_count] }
img_missing_t = missing.sum { |m| m[:img_missing] }
puts "  Total <img> tags:              #{img_total}"
puts "  <img> for missing PNGs:        #{img_missing_t}"
puts "  <i>...</i> tags:               #{missing.sum { |m| m[:i_count] }}"
puts "  <sub> tags:                    #{missing.sum { |m| m[:sub_count] }}"
puts "  <sup> tags:                    #{missing.sum { |m| m[:sup_count] }}"
puts

with_imgs = missing.select { |m| m[:img_missing] > 0 }
puts "CONCEPTS WITH BROKEN IMAGE REFS (#{with_imgs.length} concepts)"
puts "(equations unrecoverable from archive.org — need LLM/manual transcription)"
puts
with_imgs.each do |m|
  puts "  #{m[:termid]}  imgs=#{m[:img_missing]}  #{m[:designation]}"
end
puts

html_only = missing.select { |m| m[:img_missing] == 0 }
puts "CONCEPTS WITH HTML-ONLY RESIDUAL (#{html_only.length} concepts)"
puts "(no broken images — fixable with another MathTagConverter pass)"
puts
html_only.each do |m|
  puts "  #{m[:termid]}  i=#{m[:i_count]} sub=#{m[:sub_count]} sup=#{m[:sup_count]}  #{m[:designation]}"
end
