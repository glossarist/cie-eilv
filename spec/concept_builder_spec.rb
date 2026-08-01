# frozen_string_literal: true
require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe CieEilv::ConceptBuilder do
  def term_for(termid)
    CieEilv::TermParser.parse(fixture("terms/#{termid}.html"), termid: termid)
  end

  let(:builder) { described_class.new }

  describe "#build_managed" do
    it "produces a ManagedConcept with the termid as id and identifier" do
      mc = builder.build_managed(term_for("17-21-012"))
      expect(mc).to be_a(Glossarist::V3::ManagedConcept)
      expect(mc.data.id).to eq("17-21-012")
      expect(mc.id).to eq(CieEilv::Uuid.v5("17-21-012"))
    end

    it "produces a stable UUID across runs (deterministic)" do
      mc1 = builder.build_managed(term_for("17-21-012"))
      mc2 = builder.build_managed(term_for("17-21-012"))
      expect(mc1.id).to eq(mc2.id)
    end

    it "produces different UUIDs for different termids" do
      a = builder.build_managed(term_for("17-21-012")).id
      b = builder.build_managed(term_for("17-29-062")).id
      expect(a).not_to eq(b)
    end

    it "assigns the section-<n> domain via the dataset URN" do
      mc = builder.build_managed(term_for("17-21-012"))
      domains = mc.data.domains
      expect(domains.length).to eq(1)
      expect(domains.first.concept_id).to eq("section-21")
      expect(domains.first.source).to eq(CieEilv::Paths::URN)
      expect(domains.first.ref_type).to eq("section")
    end

    it "carries an authoritative source linking back to cie.co.at" do
      mc = builder.build_managed(term_for("17-21-012"))
      src = mc.sources.first
      expect(src.type).to eq("authoritative")
      expect(src.origin.ref.source).to eq("CIE S 017:2020")
      expect(src.origin.link).to eq("https://cie.co.at/eilvterm/17-21-012")
    end

    it "sets status to valid" do
      mc = builder.build_managed(term_for("17-21-012"))
      expect(mc.status).to eq("valid")
    end
  end

  describe "#build_localized" do
    it "produces a LocalizedConcept with language_code eng" do
      lc = builder.build_localized(term_for("17-21-012"))
      expect(lc).to be_a(Glossarist::V3::LocalizedConcept)
      expect(lc.data.language_code).to eq("eng")
      expect(lc.termid).to eq("17-21-012")
    end

    it "emits a single preferred expression term with designation, usage_info, and POS" do
      lc = builder.build_localized(term_for("17-21-012"))
      term = lc.data.terms.first
      expect(term).to be_a(Glossarist::Designation::Expression)
      expect(term.designation).to eq("light")
      expect(term.usage_info).to eq("psychophysical")
      expect(term.normative_status).to eq("preferred")
      expect(term.grammar_info.first.part_of_speech).to eq("noun")
    end

    it "emits a symbol term when the TermEntry has one (17-21-025)" do
      lc = builder.build_localized(term_for("17-21-025"))
      types = lc.data.terms.map(&:class)
      expect(types).to include(Glossarist::Designation::Expression, Glossarist::Designation::Symbol)
      sym = lc.data.terms.find { |t| t.is_a?(Glossarist::Designation::Symbol) }
      expect(sym.designation).to eq("λ")
      expect(sym.normative_status).to eq("preferred")
    end

    it "preserves the definition verbatim" do
      lc = builder.build_localized(term_for("17-21-012"))
      expect(lc.data.definition.first.content).to start_with("radiation that is considered")
    end

    it "preserves all notes verbatim (including prior-numbering)" do
      lc = builder.build_localized(term_for("17-21-012"))
      notes = lc.data.notes.map(&:content)
      expect(notes.length).to eq(3)
      expect(notes.any? { |n| n.include?("845-01-06") }).to be true
      expect(notes.any? { |n| n.include?("17-659") }).to be true
    end

    it "emits prior-numbering entries as structured sources" do
      lc = builder.build_localized(term_for("17-21-012"))
      prior_sources = lc.data.sources.select { |s| s.origin.ref.source != "CIE S 017:2020" }
      expect(prior_sources.length).to eq(2)
      standards = prior_sources.map { |s| s.origin.ref.source }
      expect(standards).to contain_exactly("IEC 60050-845:1987", "CIE S 017:2011")
      iec = prior_sources.find { |s| s.origin.ref.source == "IEC 60050-845:1987" }
      expect(iec.origin.ref.id).to eq("845-01-06")
    end

    it "always carries the CIE S 017:2020 authoritative source first" do
      lc = builder.build_localized(term_for("17-21-012"))
      expect(lc.data.sources.first.origin.ref.source).to eq("CIE S 017:2020")
      expect(lc.data.sources.first.type).to eq("authoritative")
    end
  end

  describe "#write_concept (integration with ConceptFile)" do
    let(:tmpdir) { Dir.mktmpdir("concept-builder-spec") }
    after { FileUtils.rm_rf(tmpdir) }

    it "writes a multi-doc YAML file readable by ConceptFile" do
      path = File.join(tmpdir, "17-21-012.yaml")
      builder.write_concept(term_for("17-21-012"), path: path)

      cf = CieEilv::ConceptFile.read(path)
      expect(cf.managed.data.id).to eq("17-21-012")
      eng = cf.find_localized("eng")
      expect(eng.data.terms.first.designation).to eq("light")
    end
  end
end
