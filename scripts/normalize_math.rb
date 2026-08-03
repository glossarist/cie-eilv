#!/usr/bin/env ruby
# frozen_string_literal: true

# Apply MathNormalizer to every concept YAML in a directory.
# Handles both Glossarist V3 multi-doc concept files (cie-2020, cie-2011)
# and plain single-doc YAML files (iev-data).
#
# Usage:
#   bundle exec ruby scripts/normalize_math.rb datasets/cie-2020/concepts
#   bundle exec ruby scripts/normalize_math.rb datasets/cie-2011/concepts
#   bundle exec ruby scripts/normalize_math.rb /path/to/iev-data/concepts

require "cie_eilv"
require "yaml"
require "fileutils"

STDOUT.sync = true

dir = ARGV[0] || abort("usage: #{$PROGRAM_NAME} <concepts-dir>")
abort "not a directory: #{dir}" unless File.directory?(dir)

# Detect format: cie-* has multi-doc YAML (multiple --- separators),
# iev-data has a single doc (one --- at the start as the YAML header).
def multi_doc?(path)
  doc_separators = 0
  File.foreach(path) do |line|
    doc_separators += 1 if line.start_with?("---")
    break if doc_separators >= 2
  end
  doc_separators >= 2
end

def normalize_glossarist_concept(path)
  cf = CieEilv::ConceptFile.read(path)
  changed = false

  # Only localized concepts carry the user-visible text (definition,
  # notes, examples, terms). Managed concept data is just metadata.
  cf.localized.each do |lc|
    data = lc.data
    next unless data
    changed |= normalize_collection(data.definition)
    changed |= normalize_collection(data.notes)
    changed |= normalize_collection(data.examples)
    changed |= normalize_terms(data.terms)
  end

  return false unless changed

  cf.save
  true
end

def normalize_collection(collection)
  return false unless collection.respond_to?(:each)

  changed = false
  collection.each do |entry|
    next unless entry.respond_to?(:content) && entry.content.is_a?(String)
    new = CieEilv::MathNormalizer.normalize_text(entry.content)
    next if new == entry.content

    entry.content = new
    changed = true
  end
  changed
end

def normalize_terms(terms)
  return false unless terms.respond_to?(:each)

  changed = false
  terms.each do |term|
    next unless term.respond_to?(:designation) && term.designation.is_a?(String)
    new = CieEilv::MathNormalizer.normalize_text(term.designation)
    next if new == term.designation

    term.designation = new
    changed = true
  end
  changed
end

def normalize_plain_yaml(path)
  docs = YAML.load_stream(File.read(path))
  changed = false

  docs.each do |doc|
    next unless doc.is_a?(Hash)
    changed |= CieEilv::MathNormalizer.normalize_hash!(doc)
  end

  return false unless changed

  # Re-emit preserving the stream. For single-doc iev-data files, this is
  # one doc; for multi-doc (rare), preserve all.
  output = docs.map { |d| d.nil? ? "---\n" : YAML.dump(d) }.join
  File.write(path, output)
  true
end

files = Dir.glob(File.join(dir, "*.yaml")).sort
total = files.length
touched = 0

files.each.with_index do |path, i|
  begin
    if multi_doc?(path)
      touched += 1 if normalize_glossarist_concept(path)
    else
      touched += 1 if normalize_plain_yaml(path)
    end
  rescue StandardError => e
    warn "\nFAILED #{File.basename(path)}: #{e.class}: #{e.message}"
  end
  print "\r[#{i + 1}/#{total}] touched=#{touched}    "
end

puts
puts "Done: #{touched}/#{total} files changed under #{dir}/"
