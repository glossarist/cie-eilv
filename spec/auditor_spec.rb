# frozen_string_literal: true
require "spec_helper"
require "tmpdir"
require "fileutils"
require "json"
require "stringio"

RSpec.describe CieEilv::Auditor do
  let(:tmpdir) { Dir.mktmpdir("auditor-spec") }
  let(:concepts_dir) { File.join(tmpdir, "concepts") }
  let(:index_path) { File.join(tmpdir, "index.json") }
  after { FileUtils.rm_rf(tmpdir) }

  before do
    FileUtils.mkdir_p(concepts_dir)
    stub_const("CieEilv::Auditor::CONCEPTS_DIR", concepts_dir)
    stub_const("CieEilv::Auditor::INDEX_PATH", index_path)
  end

  def write_valid_concept(termid, cross_refs: [])
    builder = CieEilv::ConceptBuilder.new
    definition = cross_refs.empty? ? "A definition." : "Refs {#{cross_refs.first}, x}."
    term = CieEilv::TermEntry.new(
      termid: termid,
      designation: "designation-#{termid}",
      definition: definition,
      notes: [],
      cross_refs: cross_refs
    )
    builder.write_concept(term, path: File.join(concepts_dir, "#{termid}.yaml"))
  end

  def write_index(termids)
    records = termids.map { |id| { "termid" => id, "listing_designation" => "" } }
    File.write(index_path, JSON.generate(records))
  end

  describe "#run! — valid dataset" do
    it "returns 0 when all invariants hold" do
      write_valid_concept("17-99-001")
      write_valid_concept("17-99-002")
      write_index(%w[17-99-001 17-99-002])
      expect(described_class.new.run!).to eq(0)
    end
  end

  describe "#run! — missing termid" do
    it "reports an error for a concept with empty managed id" do
      path = File.join(concepts_dir, "broken.yaml")
      # Build a concept then blank out the id
      write_valid_concept("17-99-001")
      cf_path = File.join(concepts_dir, "17-99-001.yaml")
      cf = CieEilv::ConceptFile.read(cf_path)
      cf.managed.data.id = nil
      cf.save

      write_index(%w[17-99-001])
      result = described_class.new.run!
      expect(result).to eq(1)
    end
  end

  describe "#run! — duplicate termid" do
    it "reports 2 errors (one per duplicate)" do
      # Hand-craft two files with the same termid by writing one then copying
      write_valid_concept("17-99-001")
      FileUtils.cp(File.join(concepts_dir, "17-99-001.yaml"),
                   File.join(concepts_dir, "17-99-001-dup.yaml"))
      write_index(%w[17-99-001])
      expect(described_class.new.run!).to eq(1)
    end
  end

  describe "#run! — empty definition (upstream quirk)" do
    it "warns but does NOT fail (exit 0) — upstream data, not pipeline bug" do
      builder = CieEilv::ConceptBuilder.new
      term = CieEilv::TermEntry.new(
        termid: "17-99-001",
        designation: "x",
        definition: "",
        notes: [],
        cross_refs: []
      )
      builder.write_concept(term, path: File.join(concepts_dir, "17-99-001.yaml"))
      write_index(%w[17-99-001])
      stderr_io = StringIO.new
      result = described_class.new(io: stderr_io).run!
      expect(result).to eq(0)
      expect(stderr_io.string).to match(/WARN.*definition has no content/)
    end
  end

  describe "#run! — disk/index mismatch" do
    it "reports errors when disk has files not in index" do
      write_valid_concept("17-99-001")
      write_valid_concept("17-99-002")
      write_index(%w[17-99-001])  # 17-99-002 on disk but not in index
      expect(described_class.new.run!).to eq(1)
    end

    it "reports errors when index lists termids with no file" do
      write_valid_concept("17-99-001")
      write_index(%w[17-99-001 17-99-002])  # 17-99-002 missing from disk
      expect(described_class.new.run!).to eq(1)
    end
  end

  describe "#run! — invariant details in stderr" do
    it "prints all errors to stderr before exiting non-zero" do
      write_valid_concept("17-99-001")
      write_valid_concept("17-99-002")
      write_index(%w[17-99-001])
      stderr_io = StringIO.new
      result = described_class.new(io: stderr_io).run!
      expect(result).to eq(1)
      expect(stderr_io.string).to match(/17-99-002/i)
    end
  end
end
