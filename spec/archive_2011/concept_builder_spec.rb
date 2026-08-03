# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe CieEilv::Archive2011::ConceptBuilder do
  let(:builder) { described_class.new }
  let(:source_url) { "https://web.archive.org/web/20190000000000/http://eilv.cie.co.at/term/5" }

  def term_for(archive_id)
    html = File.read(File.join(__dir__, "fixtures", "#{archive_id}.html"))
    CieEilv::Archive2011::TermParser.parse(html, archive_id: archive_id)
  end

  describe "#build_managed" do
    it "produces a ManagedConcept with the termid as identifier" do
      mc = builder.build_managed(term_for("1"), source_url: source_url)
      expect(mc).to be_a(Glossarist::V3::ManagedConcept)
      expect(mc.data.id).to eq("17-1")
      expect(mc.id).to eq(CieEilv::Uuid.v5("17-1"))
    end

    it "produces a stable UUID across runs" do
      a = builder.build_managed(term_for("1"), source_url: source_url).id
      b = builder.build_managed(term_for("1"), source_url: source_url).id
      expect(a).to eq(b)
    end

    it "produces different UUIDs for different archive_ids" do
      a = builder.build_managed(term_for("1"), source_url: source_url).id
      b = builder.build_managed(term_for("5"), source_url: source_url).id
      expect(a).not_to eq(b)
    end

    it "assigns the flat section-all domain via the dataset URN" do
      mc = builder.build_managed(term_for("5"), source_url: source_url)
      domain = mc.data.domains.first
      expect(domain.concept_id).to eq("section-all")
      expect(domain.source).to eq(CieEilv::Archive2011::Paths::URN)
      expect(domain.ref_type).to eq("section")
    end

    it "carries an authoritative CIE S 017:2011 source with the wayback link" do
      mc = builder.build_managed(term_for("5"), source_url: source_url)
      src = mc.sources.first
      expect(src.type).to eq("authoritative")
      expect(src.origin.ref.source).to eq("CIE S 017:2011")
      expect(src.origin.link).to eq(source_url)
    end

    it "sets status to valid" do
      mc = builder.build_managed(term_for("1"), source_url: source_url)
      expect(mc.status).to eq("valid")
    end
  end

  describe "#build_localized" do
    it "produces a LocalizedConcept with language_code eng" do
      lc = builder.build_localized(term_for("1"))
      expect(lc).to be_a(Glossarist::V3::LocalizedConcept)
      expect(lc.data.language_code).to eq("eng")
      expect(lc.termid).to eq("17-1")
    end

    it "emits a preferred expression term with the designation" do
      lc = builder.build_localized(term_for("1"))
      term = lc.data.terms.first
      expect(term).to be_a(Glossarist::Designation::Expression)
      expect(term.designation).to eq("Abney phenomenon")
      expect(term.normative_status).to eq("preferred")
    end

    it "emits a symbol term when the TermEntry has one (5)" do
      lc = builder.build_localized(term_for("5"))
      types = lc.data.terms.map(&:class)
      expect(types).to include(Glossarist::Designation::Expression, Glossarist::Designation::Symbol)
      sym = lc.data.terms.find { |t| t.is_a?(Glossarist::Designation::Symbol) }
      expect(sym.designation).to eq("<i>α</i>")
      expect(sym.normative_status).to eq("preferred")
    end

    it "emits admitted terms for equivalent_terms (103)" do
      lc = builder.build_localized(term_for("103"))
      admitted = lc.data.terms.select { |t| t.normative_status == "admitted" }
      expect(admitted.length).to eq(1)
      expect(admitted.first.designation).to eq("blue light hazard radiance dose")
    end

    it "puts notes in the notes collection, not the definition (103)" do
      lc = builder.build_localized(term_for("103"))
      expect(lc.data.notes.length).to eq(1)
      expect(lc.data.notes.first.content).to start_with("This definition implies")
    end

    it "carries an authoritative source with no link (localized)" do
      lc = builder.build_localized(term_for("1"))
      src = lc.data.sources.first
      expect(src.type).to eq("authoritative")
      expect(src.origin.ref.source).to eq("CIE S 017:2011")
    end
  end

  describe "#write_concept" do
    it "writes a two-doc YAML stream (managed + localized)" do
      Dir.mktmpdir do |dir|
        out = File.join(dir, "17-1.yaml")
        builder.write_concept(term_for("1"), path: out, source_url: source_url)
        cf = CieEilv::ConceptFile.read(out)
        expect(cf.managed).to be_a(Glossarist::V3::ManagedConcept)
        expect(cf.localized.first).to be_a(Glossarist::V3::LocalizedConcept)
      end
    end
  end
end
