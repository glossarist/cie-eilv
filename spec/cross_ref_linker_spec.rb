# frozen_string_literal: true
require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe CieEilv::CrossRefLinker do
  let(:tmpdir) { Dir.mktmpdir("linker-spec") }
  after { FileUtils.rm_rf(tmpdir) }

  # Build a tiny 2-concept dataset where A's definition references B.
  let(:concepts_dir) { File.join(tmpdir, "concepts") }

  before do
    FileUtils.mkdir_p(concepts_dir)
    stub_const("CieEilv::CrossRefLinker::CONCEPTS_DIR", concepts_dir)

    builder = CieEilv::ConceptBuilder.new

    # A: 17-99-001 with definition referencing B (17-99-002)
    term_a = CieEilv::TermEntry.new(
      termid: "17-99-001",
      designation: "alpha",
      definition: %(A thing related to <a href="/eilvterm/17-99-002">beta</a>.),
      notes: [],
      cross_refs: ["17-99-002"]
    )
    builder.write_concept(term_a, path: File.join(concepts_dir, "17-99-001.yaml"))

    # B: 17-99-002 (no refs)
    term_b = CieEilv::TermEntry.new(
      termid: "17-99-002",
      designation: "beta",
      definition: "Another thing.",
      notes: [],
      cross_refs: []
    )
    builder.write_concept(term_b, path: File.join(concepts_dir, "17-99-002.yaml"))
  end

  describe "#run!" do
    it "rewrites /eilvterm/<id> anchors into {id, designation} inline-ref syntax" do
      described_class.new.run!
      cf = CieEilv::ConceptFile.read(File.join(concepts_dir, "17-99-001.yaml"))
      definition = cf.find_localized("eng").data.definition.first.content
      expect(definition).to include("{17-99-002, beta}")
      expect(definition).not_to include('href="/eilvterm/')
    end

    it "is idempotent (second run touches zero files)" do
      linker = described_class.new
      linker.run!
      first_count = linker.last_touched_count
      linker.run!
      second_count = linker.last_touched_count
      expect(first_count).to be > 0
      expect(second_count).to eq(0)
    end

    it "preserves other HTML (italics, etc.) in the definition" do
      FileUtils.rm_rf(concepts_dir)
      FileUtils.mkdir_p(concepts_dir)
      builder = CieEilv::ConceptBuilder.new
      term = CieEilv::TermEntry.new(
        termid: "17-99-003",
        designation: "gamma",
        definition: %(An <i>italicized</i> thing with <a href="/eilvterm/17-99-004">delta</a> ref.),
        notes: [],
        cross_refs: ["17-99-004"]
      )
      builder.write_concept(term, path: File.join(concepts_dir, "17-99-003.yaml"))
      term_d = CieEilv::TermEntry.new(
        termid: "17-99-004",
        designation: "delta",
        definition: "Another.",
        notes: [],
        cross_refs: []
      )
      builder.write_concept(term_d, path: File.join(concepts_dir, "17-99-004.yaml"))

      described_class.new.run!
      cf = CieEilv::ConceptFile.read(File.join(concepts_dir, "17-99-003.yaml"))
      definition = cf.find_localized("eng").data.definition.first.content
      expect(definition).to include("<i>italicized</i>")
      expect(definition).to include("{17-99-004, delta}")
    end

    it "also rewrites anchors inside notes" do
      FileUtils.rm_rf(concepts_dir)
      FileUtils.mkdir_p(concepts_dir)
      builder = CieEilv::ConceptBuilder.new
      term = CieEilv::TermEntry.new(
        termid: "17-99-005",
        designation: "epsilon",
        definition: "Def.",
        notes: [%(See also <a href="/eilvterm/17-99-006">zeta</a>.)],
        cross_refs: ["17-99-006"]
      )
      builder.write_concept(term, path: File.join(concepts_dir, "17-99-005.yaml"))
      term_f = CieEilv::TermEntry.new(
        termid: "17-99-006",
        designation: "zeta",
        definition: "Def.",
        notes: [],
        cross_refs: []
      )
      builder.write_concept(term_f, path: File.join(concepts_dir, "17-99-006.yaml"))

      described_class.new.run!
      cf = CieEilv::ConceptFile.read(File.join(concepts_dir, "17-99-005.yaml"))
      note = cf.find_localized("eng").data.notes.first.content
      expect(note).to include("{17-99-006, zeta}")
    end
  end
end
