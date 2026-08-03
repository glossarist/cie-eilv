#!/usr/bin/env ruby
# frozen_string_literal: true

# Migrate deprecated <<target, label>> xref syntax to canonical
# {{cite:target, label}} form per concept-model/docs/design/inline-mentions.md.
#
# The <<...>> form is a deprecated AsciiDoc xref alias. The canonical
# form for citing external concepts (e.g. IEV concepts outside section
# 845) is {{cite:target, label}}, backed by a ConceptSource entry in
# the concept's sources[].
#
# This script only rewrites the inline syntax. It does NOT add the
# matching ConceptSource entries — run IevMathImporter afterward to
# populate sources[] via its ensure_cite_sources! path.

require "cie_eilv"
require "yaml"
require "fileutils"

STDOUT.sync = true

DEPRECATED_RE = /<<([^>]+)>>/.freeze

def migrate_text(text)
  return text unless text.is_a?(String)
  text.gsub(DEPRECATED_RE) do
    body = Regexp.last_match(1)
    "{{cite:#{body}}}"
  end
end

def migrate_collection(collection)
  return false unless collection.respond_to?(:each)
  changed = false
  collection.each do |entry|
    next unless entry.respond_to?(:content) && entry.content.is_a?(String)
    new = migrate_text(entry.content)
    next if new == entry.content
    entry.content = new
    changed = true
  end
  changed
end

def migrate_terms(terms)
  return false unless terms.respond_to?(:each)
  changed = false
  terms.each do |term|
    next unless term.respond_to?(:designation) && term.designation.is_a?(String)
    new = migrate_text(term.designation)
    next if new == term.designation
    term.designation = new
    changed = true
  end
  changed
end

def migrate_glossarist_concept(path)
  cf = CieEilv::ConceptFile.read(path)
  changed = false
  cf.localized.each do |lc|
    data = lc.data
    next unless data
    changed |= migrate_collection(data.definition)
    changed |= migrate_collection(data.notes)
    changed |= migrate_collection(data.examples)
    changed |= migrate_terms(data.terms)
  end
  return false unless changed
  cf.save
  true
end

dir = ARGV[0] || abort("usage: #{$PROGRAM_NAME} <concepts-dir>")
abort "not a directory: #{dir}" unless File.directory?(dir)

files = Dir.glob(File.join(dir, "*.yaml")).sort
total = files.length
touched = 0

files.each.with_index do |path, i|
  begin
    # Only Glossarist V3 multi-doc concept files. Skip iev-data (plain
    # single-doc YAML) — it doesn't use <<...>> xref syntax.
    first_lines = File.foreach(path).first(2).join
    next unless first_lines.start_with?("---")

    # Count doc separators to confirm multi-doc.
    separators = 0
    File.foreach(path) do |line|
      separators += 1 if line.start_with?("---")
      break if separators >= 2
    end
    next unless separators >= 2

    touched += 1 if migrate_glossarist_concept(path)
  rescue StandardError => e
    warn "\nFAILED #{File.basename(path)}: #{e.class}: #{e.message}"
  end
  print "\r[#{i + 1}/#{total}] migrated=#{touched}    "
end

puts
puts "Done: #{touched}/#{total} files migrated under #{dir}/"
