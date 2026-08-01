# frozen_string_literal: true
require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe CieEilv::TermIndex do
  let(:listing_html) { fixture("e-ilv-listing.html") }

  describe ".parse" do
    it "returns an Array of {termid, listing_designation} hashes" do
      records = described_class.parse(listing_html)
      expect(records).to all(include(:termid, :listing_designation))
      expect(records.length).to be > 1000  # full listing has ~1300
    end

    it "returns records sorted by termid" do
      records = described_class.parse(listing_html)
      termids = records.map { |r| r[:termid] }
      expect(termids).to eq(termids.sort)
    end

    it "extracts the first record as 17-21-001 with its designation" do
      records = described_class.parse(listing_html)
      first = records.first
      expect(first[:termid]).to eq("17-21-001")
      expect(first[:listing_designation]).to eq("electromagnetic radiation, <phenomenon>")
    end

    it "preserves the full <usage> POS suffix on the listing designation" do
      records = described_class.parse(listing_html)
      entry = records.find { |r| r[:termid] == "17-21-012" }
      expect(entry[:listing_designation]).to eq("light, <psychophysical> noun")
    end

    it "preserves a 'pl' part-of-speech with no angle brackets" do
      records = described_class.parse(listing_html)
      entry = records.find { |r| r[:termid] == "17-22-002" }
      expect(entry[:listing_designation]).to eq("cones, pl")
    end

    it "produces only termids matching the 17-XX-YYY pattern" do
      records = described_class.parse(listing_html)
      invalid = records.reject { |r| r[:termid] =~ /\A17-\d{2}-\d{3}\z/ }
      expect(invalid).to be_empty
    end

    it "produces no duplicate termids" do
      records = described_class.parse(listing_html)
      termids = records.map { |r| r[:termid] }
      expect(termids.uniq.length).to eq(termids.length)
    end

    it "returns an empty Array for HTML with no term rows" do
      expect(described_class.parse("<html><body></body></html>")).to eq([])
    end
  end

  describe ".write_index" do
    let(:tmpdir) { Dir.mktmpdir("term-index-spec") }

    after { FileUtils.rm_rf(tmpdir) }

    it "writes a pretty JSON array of records to the given path" do
      records = described_class.parse(listing_html)
      out = File.join(tmpdir, "index.json")
      described_class.write_index(records, out)
      parsed = JSON.parse(File.read(out))
      expect(parsed.length).to eq(records.length)
      expect(parsed.first).to eq("termid" => "17-21-001",
                                 "listing_designation" => "electromagnetic radiation, <phenomenon>")
    end
  end
end
