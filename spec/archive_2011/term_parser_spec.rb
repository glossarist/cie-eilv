# frozen_string_literal: true

require "spec_helper"

def fixture_archive_page(archive_id)
  File.read(File.join(__dir__, "fixtures", "#{archive_id}.html"))
end

RSpec.describe CieEilv::Archive2011::TermParser do
  describe ".parse — heading extraction" do
    it "extracts archive_id and termid from the h2" do
      term = described_class.parse(fixture_archive_page("1"), archive_id: "1")
      expect(term.archive_id).to eq("1")
      expect(term.termid).to eq("17-1")
    end

    it "extracts a simple designation (no symbol, no POS)" do
      term = described_class.parse(fixture_archive_page("1"), archive_id: "1")
      expect(term.designation).to eq("Abney phenomenon")
    end

    it "extracts a designation with trailing [<symbol>] markup" do
      term = described_class.parse(fixture_archive_page("5"), archive_id: "5")
      expect(term.designation).to eq("absorptance")
      expect(term.symbol).to eq("<i>α</i>")
      expect(term.symbol?).to be true
    end

    it "extracts a designation with complex subscripted symbol (103)" do
      term = described_class.parse(fixture_archive_page("103"), archive_id: "103")
      expect(term.designation).to eq("blue light hazard (time) integrated radiance")
      expect(term.symbol).to eq("<i>L</i><sub>b,t</sub>")
    end
  end

  describe ".parse — body classification" do
    it "puts a single definition paragraph in definition, no notes (1)" do
      term = described_class.parse(fixture_archive_page("1"), archive_id: "1")
      expect(term.definition).to start_with("change of hue produced by decreasing the purity")
      expect(term.notes).to be_empty
    end

    it "classifies 'NOTE This definition…' (unnumbered) as a note (103)" do
      term = described_class.parse(fixture_archive_page("103"), archive_id: "103")
      expect(term.notes.length).to eq(1)
      expect(term.notes.first).to start_with("This definition implies that an action spectrum")
    end

    it "preserves the 'Equivalent term:' line inline AND extracts the term" do
      term = described_class.parse(fixture_archive_page("103"), archive_id: "103")
      expect(term.equivalent_terms).to eq(["blue light hazard radiance dose"])
      expect(term.definition).to include('Equivalent term: "blue light hazard radiance dose"')
    end

    it "extracts bare-numeric cross-refs from definition and notes (103)" do
      term = described_class.parse(fixture_archive_page("103"), archive_id: "103")
      expect(term.cross_refs).to include("1014")
    end
  end

  describe ".parse — alias entries" do
    it "detects a 'See \"X\"' page as an alias (100)" do
      term = described_class.parse(fixture_archive_page("100"), archive_id: "100")
      expect(term.alias?).to be true
      expect(term.designation).to eq("blue light hazard radiance dose")
      expect(term.definition).to include('See "<a href="103">')
    end
  end

  describe ".parse — NOTE regex edge cases" do
    it "matches 'NOTE 1', 'NOTE11', and bare 'NOTE'" do
      re = CieEilv::Archive2011::TermParser::NOTE_RE

      expect("NOTE 1 The first.".match?(re)).to be true
      expect("NOTE11 The eleventh.".match?(re)).to be true
      expect("NOTE Only one.".match?(re)).to be true
      expect("NOTA BENE".match?(re)).to be false
    end
  end

  describe ".parse — contract violations" do
    let(:no_content_middle) { "<html><body>nope</body></html>" }

    it "raises ParseError when the content wrapper is missing" do
      expect do
        described_class.parse(no_content_middle, archive_id: "999")
      end.to raise_error(CieEilv::Archive2011::TermParser::ParseError, /no .content-middle/)
    end
  end
end
