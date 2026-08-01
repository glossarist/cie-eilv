# frozen_string_literal: true
require "spec_helper"
require "tmpdir"
require "json"

RSpec.describe CieEilv::RegisterBuilder do
  let(:sample_index) do
    [
      { "termid" => "17-21-001", "listing_designation" => "electromagnetic radiation, <phenomenon>" },
      { "termid" => "17-21-012", "listing_designation" => "light, <psychophysical> noun" },
      { "termid" => "17-22-002", "listing_designation" => "cones, pl" },
      { "termid" => "17-29-062", "listing_designation" => "lumen method" },
      { "termid" => "17-32-068", "listing_designation" => "white balance" }
    ]
  end

  let(:tmpdir) { Dir.mktmpdir("register-builder-spec") }
  after { FileUtils.rm_rf(tmpdir) }

  before do
    index_path = File.join(tmpdir, "scraped", "terms", "index.json")
    FileUtils.mkdir_p(File.dirname(index_path))
    File.write(index_path, JSON.pretty_generate(sample_index))

    # Stub Paths::INDEX_PATH to point at our fixture index.
    stub_const("CieEilv::Paths::INDEX_PATH", File.join(tmpdir, "scraped", "terms", "index.json"))
  end

  describe "#run!" do
    it "writes register.yaml to the given path" do
      out = File.join(tmpdir, "register.yaml")
      described_class.new(out_path: out).run!
      expect(File.exist?(out)).to be(true)
    end

    it "produces the expected top-level fields" do
      out = File.join(tmpdir, "register.yaml")
      register = described_class.new(out_path: out).run!
      expect(register["schema_type"]).to eq("glossarist")
      expect(register["schema_version"]).to eq("3")
      expect(register["id"]).to eq("cie-2020")
      expect(register["ref"]).to include("CIE S 017:2020")
      expect(register["year"]).to eq(2020)
      expect(register["urn"]).to eq(CieEilv::Paths::URN)
      expect(register["status"]).to eq("current")
      expect(register["owner"]).to eq("CIE")
      expect(register["languages"]).to eq(["eng"])
      expect(register["language_order"]).to eq(["eng"])
      expect(register["ordering"]).to eq("systematic")
    end

    it "emits the full 12-section tree in numeric order" do
      out = File.join(tmpdir, "register.yaml")
      register = described_class.new(out_path: out).run!
      section_ids = register["sections"].map { |s| s["id"] }
      expect(section_ids).to eq(CieEilv::Sections.all)
    end

    it "every section has an English title from Sections::TABLE" do
      out = File.join(tmpdir, "register.yaml")
      register = described_class.new(out_path: out).run!
      register["sections"].each do |s|
        expect(s["names"]["eng"]).to eq(CieEilv::Sections.title_for(s["id"]))
        expect(s["children"]).to eq([])
      end
    end

    it "round-trips through YAML with section ids as quoted strings" do
      out = File.join(tmpdir, "register.yaml")
      described_class.new(out_path: out).run!
      yaml_text = File.read(out)
      expect(yaml_text).to match(/- id: '21'/)
      parsed = YAML.safe_load(yaml_text, aliases: true)
      expect(parsed["sections"].first["id"]).to eq("21")
    end
  end
end
