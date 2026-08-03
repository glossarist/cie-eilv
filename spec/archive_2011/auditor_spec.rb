# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "json"

RSpec.describe CieEilv::Archive2011::Auditor do
  let(:concepts_dir) { Dir.mktmpdir }
  let(:index_path) { File.join(Dir.mktmpdir, "index.json") }
  let(:io) { StringIO.new }
  let(:auditor) { described_class.new(concepts_dir:, index_path:, io:) }

  def write_concept(archive_id, designation:, definition: "some definition", status: "valid")
    builder = CieEilv::Archive2011::ConceptBuilder.new
    term = CieEilv::Archive2011::TermEntry.new(
      archive_id:, termid: "17-#{archive_id}",
      designation:, definition:
    )
    out = File.join(concepts_dir, "17-#{archive_id}.yaml")
    builder.write_concept(term, path: out, source_url: "https://example.org/x")
    out
  end

  def write_index(archive_ids)
    File.write(index_path, JSON.generate(archive_ids.map { |id| { "archive_id" => id.to_s } }))
  end

  it "returns 0 and prints OK when the dataset is consistent" do
    write_concept("1", designation: "x")
    write_concept("2", designation: "y")
    write_index(%w[1 2])

    expect(auditor.run!).to eq(0)
    expect(io.string).to include("OK")
  end

  it "returns 1 when index.json lists an id missing from disk" do
    write_concept("1", designation: "x")
    write_index(%w[1 999])

    expect(auditor.run!).to eq(1)
    expect(io.string).to include("17-999")
  end

  it "returns 1 when a concept file isn't listed in index.json" do
    write_concept("1", designation: "x")
    write_concept("2", designation: "y")
    write_index(%w[1])

    expect(auditor.run!).to eq(1)
    expect(io.string).to include("17-2.yaml")
  end

  it "rejects malformed termids" do
    # Hand-craft a concept with a bad termid by post-processing the file.
    write_concept("1", designation: "x")
    path = File.join(concepts_dir, "17-1.yaml")
    text = File.read(path)
    text.sub!("17-1", "not-a-termid")
    File.write(path, text)
    write_index(%w[1])

    expect(auditor.run!).to eq(1)
    expect(io.string).to include("malformed termid")
  end

  it "flags duplicate termids as errors" do
    write_concept("1", designation: "x")
    FileUtils.cp(File.join(concepts_dir, "17-1.yaml"),
                 File.join(concepts_dir, "17-1-dup.yaml"))
    write_index(%w[1])

    expect(auditor.run!).to eq(1)
    expect(io.string).to include("duplicate termid")
  end

  it "warns (not errors) on empty definition — alias entries" do
    write_concept("1", designation: "x", definition: "")
    write_index(%w[1])

    expect(auditor.run!).to eq(0)
    expect(io.string).to include("WARN")
    expect(io.string).to include("definition has no content")
  end
end
