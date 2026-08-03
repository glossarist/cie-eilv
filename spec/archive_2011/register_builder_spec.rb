# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe CieEilv::Archive2011::RegisterBuilder do
  let(:tmpdir) { Dir.mktmpdir }
  let(:out_path) { File.join(tmpdir, "register.yaml") }

  after { FileUtils.remove_entry(tmpdir) if File.exist?(tmpdir) }

  it "writes a YAML file at out_path" do
    described_class.new(out_path:).run!
    expect(File.exist?(out_path)).to be true
  end

  it "uses the cie-2011 dataset id, URN, and year" do
    register = described_class.new(out_path:).run!
    expect(register["id"]).to eq("cie-2011")
    expect(register["urn"]).to eq("urn:cie:ilv:cie-2011")
    expect(register["year"]).to eq(2011)
  end

  it "carries the CIE S 017:2011 ref and historical status" do
    register = described_class.new(out_path:).run!
    expect(register["ref"]).to include("CIE S 017:2011")
    expect(register["status"]).to eq("historical")
  end

  it "emits the 12 ILV sections plus an unknown bucket" do
    register = described_class.new(out_path:).run!
    sections = register["sections"]
    ids = sections.map { |s| s["id"] }
    expect(ids.length).to eq(13)
    ("21".."32").each { |n| expect(ids).to include(n) }
    expect(ids).to include("unknown")
    s21 = sections.find { |s| s["id"] == "21" }
    expect(s21["names"]["eng"]).to eq(CieEilv::Sections.title_for("21"))
  end
end
