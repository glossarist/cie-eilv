# frozen_string_literal: true
require "spec_helper"

RSpec.describe CieEilv::Sections do
  describe ".title_for" do
    it "returns the title for a known section" do
      expect(described_class.title_for("21")).to eq("Electromagnetic radiation and optical radiation")
      expect(described_class.title_for("32")).to eq("Imaging technology")
    end

    it "falls back to a numeric label for an unknown section" do
      expect(described_class.title_for("99")).to eq("Section 99")
    end

    it "coerces integer-like input to string lookup" do
      expect(described_class.title_for(21)).to eq("Electromagnetic radiation and optical radiation")
    end
  end

  describe ".all" do
    it "returns all 12 section prefixes in numeric order" do
      expect(described_class.all).to eq(%w[21 22 23 24 25 26 27 28 29 30 31 32])
    end
  end

  describe "TABLE integrity" do
    it "every value is a non-empty String" do
      described_class::TABLE.each do |prefix, title|
        expect(prefix).to match(/\A\d{2}\z/)
        expect(title).to be_a(String)
        expect(title).to match(/\S/)
        expect(title).to eq(title.strip)  # no leading/trailing whitespace
      end
    end
  end
end
