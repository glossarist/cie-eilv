# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

# Build an in-memory cie-2011 mini-dataset, then run the linker against it.
RSpec.describe CieEilv::Archive2011::CrossRefLinker do
  let(:concepts_dir) { Dir.mktmpdir }
  let(:linker) { described_class.new(concepts_dir:) }

  def build_concept(archive_id, designation, definition = "", notes = [])
    builder = CieEilv::Archive2011::ConceptBuilder.new
    term = CieEilv::Archive2011::TermEntry.new(
      archive_id:, termid: "17-#{archive_id}",
      designation:, definition:, notes:
    )
    out = File.join(concepts_dir, "17-#{archive_id}.yaml")
    builder.write_concept(term, path: out, source_url: "https://example.org/x")
    out
  end

  it "rewrites a bare-numeric anchor into Glossarist inline-ref syntax" do
    build_concept("1014", "radiance dose", %(See also "<a href="100">related</a>"))
    build_concept("100", "blue light hazard")

    linker.run!

    cf = CieEilv::ConceptFile.read(File.join(concepts_dir, "17-1014.yaml"))
    definition = cf.find_localized("eng").data.definition.first.content
    expect(definition).to include("{{17-100, blue light hazard}}")
    expect(definition).not_to include("<a href=\"100\">")
  end

  it "rewrites a Wayback-rewritten anchor" do
    build_concept("1", "Abney phenomenon",
                  %(links to <a href="/web/20190101000000/http://eilv.cie.co.at/term/2">x</a>))
    build_concept("2", "Abney's law")

    linker.run!

    cf = CieEilv::ConceptFile.read(File.join(concepts_dir, "17-1.yaml"))
    definition = cf.find_localized("eng").data.definition.first.content
    expect(definition).to include("{{17-2, Abney's law}}")
  end

  it "uses the anchor text when the target concept is unknown" do
    build_concept("1", "Abney phenomenon", %(See "<a href="9999">missing</a>"))

    linker.run!

    cf = CieEilv::ConceptFile.read(File.join(concepts_dir, "17-1.yaml"))
    definition = cf.find_localized("eng").data.definition.first.content
    expect(definition).to include("{{17-9999, missing}}")
  end

  it "is idempotent — re-running touches zero files" do
    build_concept("1", "x", %(<a href="2">y</a>))
    build_concept("2", "y")

    linker.run!
    second_pass = described_class.new(concepts_dir:)
    expect(second_pass.run!).to eq(0)
  end

  it "rewrites anchors inside notes, not just definition" do
    build_concept("1", "x", "definition", ["NOTE refers to <a href=\"2\">y</a>"])
    build_concept("2", "y")

    linker.run!

    cf = CieEilv::ConceptFile.read(File.join(concepts_dir, "17-1.yaml"))
    note = cf.find_localized("eng").data.notes.first.content
    expect(note).to include("{{17-2, y}}")
  end
end
