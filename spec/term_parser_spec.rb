# frozen_string_literal: true
require "spec_helper"

RSpec.describe CieEilv::TermParser do
  def parse(termid)
    described_class.parse(fixture("terms/#{termid}.html"), termid: termid)
  end

  describe ".parse — designation / usage / part_of_speech extraction" do
    it "extracts designation, usage_info, and part_of_speech (17-21-012)" do
      e = parse("17-21-012")
      expect(e.designation).to eq("light")
      expect(e.usage_info).to eq("psychophysical")
      expect(e.part_of_speech).to eq("noun")
    end

    it "extracts adj POS (17-21-027)" do
      e = parse("17-21-027")
      expect(e.designation).to eq("spectral")
      expect(e.usage_info).to eq("of a quantity")
      expect(e.part_of_speech).to eq("adj")
    end

    it "extracts usage_info only, no POS (17-21-032)" do
      e = parse("17-21-032")
      expect(e.usage_info).to eq("of optical radiation")
      expect(e.part_of_speech).to be_nil
    end

    it "extracts 'pl' part-of-speech with no usage_info (17-22-002)" do
      e = parse("17-22-002")
      expect(e.designation).to eq("cones")
      expect(e.usage_info).to be_nil
      expect(e.part_of_speech).to eq("pl")
    end

    it "extracts a designation with no TermDesc span at all (17-25-014)" do
      e = parse("17-25-014")
      expect(e.designation).to eq("colorimetry")
      expect(e.usage_info).to be_nil
      expect(e.part_of_speech).to be_nil
    end

    it "extracts the symbol entry (17-21-025: λ)" do
      e = parse("17-21-025")
      expect(e.designation).to eq("wavelength")
      expect(e.symbol).to eq("λ")
      expect(e.symbol?).to be true
    end

    it "does not report a symbol when there is only one TermEntry (17-25-014)" do
      e = parse("17-25-014")
      expect(e.symbol?).to be false
      expect(e.symbol).to be_nil
    end
  end

  describe ".parse — definition and notes" do
    it "extracts the definition verbatim (17-21-012)" do
      e = parse("17-21-012")
      expect(e.definition).to start_with("radiation that is considered from the point of view")
    end

    it "preserves the leading 'Note N to entry' label-stripped note bodies (17-21-012)" do
      e = parse("17-21-012")
      expect(e.notes.length).to eq(3)
      expect(e.notes[0]).to start_with(%(The term "light" is sometimes used))
      expect(e.notes[0]).not_to match(/\ANote \d/)
    end

    it "drops the empty <p class='Note'></p> separator paragraph" do
      e = parse("17-21-012")
      expect(e.notes).to all(match(/\S/))  # no empty or whitespace-only entries
    end

    it "preserves a multi-line formula note intact (17-21-025 Note 3)" do
      e = parse("17-21-025")
      formula_note = e.notes.find { |n| n.include?("ν") && n.include?("phase velocity") }
      expect(formula_note).not_to be_nil
      expect(formula_note).to include("<i>λ</i>")
    end

    it "extracts 7 notes for 17-21-025 (wavelength)" do
      e = parse("17-21-025")
      expect(e.notes.length).to eq(7)
    end
  end

  describe ".parse — cross-concept references" do
    it "collects unique termids from /eilvterm/<id> anchors (17-21-012)" do
      e = parse("17-21-012")
      expect(e.cross_refs).to include("17-21-002")
      expect(e.cross_refs).to eq(e.cross_refs.uniq)
    end

    it "collects multiple cross-refs (17-29-062)" do
      e = parse("17-29-062")
      %w[17-27-001 17-30-001 17-29-155 17-29-068].each do |ref|
        expect(e.cross_refs).to include(ref)
      end
    end
  end

  describe ".parse — prior-numbering classification" do
    it "classifies IEC 60050-845:1987 and CIE S 017:2011 prior-numbering notes (17-21-012)" do
      e = parse("17-21-012")
      expect(e.prior_numberings.length).to eq(2)
      standards = e.prior_numberings.map(&:standard)
      expect(standards).to contain_exactly("IEC 60050-845:1987", "CIE S 017:2011")
      iec = e.prior_numberings.find { |p| p.standard == "IEC 60050-845:1987" }
      expect(iec.legacy_id).to eq("845-01-06")
      cie2011 = e.prior_numberings.find { |p| p.standard == "CIE S 017:2011" }
      expect(cie2011.legacy_id).to eq("17-659 (2.)")
    end

    it "keeps the prior-numbering notes verbatim in notes[] too" do
      e = parse("17-21-012")
      expect(e.notes.any? { |n| n.include?("numbered 845-01-06") }).to be true
      expect(e.notes.any? { |n| n.include?("numbered 17-659") }).to be true
    end
  end

  describe ".parse — section prefix" do
    it "derives section prefix from termid" do
      expect(parse("17-21-012").section_prefix).to eq("21")
      expect(parse("17-29-062").section_prefix).to eq("29")
    end
  end

  describe ".parse — error cases" do
    it "raises ParseError when the body field is missing" do
      expect {
        described_class.parse("<html><body></body></html>", termid: "17-21-012")
      }.to raise_error(CieEilv::TermParser::ParseError, /17-21-012/)
    end

    it "raises ParseError when TermEntry is missing" do
      html = '<article class="node node--type-eilvterm"><div class="field--name-body"></div></article>'
      expect {
        described_class.parse(html, termid: "17-21-012")
      }.to raise_error(CieEilv::TermParser::ParseError, /TermEntry/)
    end
  end
end
