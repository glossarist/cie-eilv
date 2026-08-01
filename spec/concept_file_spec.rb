# frozen_string_literal: true
require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe CieEilv::ConceptFile do
  let(:tmpdir) { Dir.mktmpdir("concept-file-spec") }
  after { FileUtils.rm_rf(tmpdir) }

  let(:managed_yaml) do
    <<~YAML
      ---
      id: 17-21-012
      data:
        identifier: 17-21-012
        domains:
        - concept_id: section-21
          source: urn:cie:ilv:cie-2020
          ref_type: section
      status: valid
      sources:
      - type: authoritative
        origin:
          ref: { source: CIE S 017:2020 }
          link: https://cie.co.at/eilvterm/17-21-012
    YAML
  end

  let(:localized_yaml) do
    <<~YAML
      ---
      id: 17-21-012-eng
      termid: 17-21-012
      data:
        language_code: eng
        terms:
        - type: expression
          normative_status: preferred
          designation: light
        definition:
        - content: radiation that is considered from the point of view
        notes: []
        examples: []
      sources:
      - type: authoritative
        origin:
          ref: { source: CIE S 017:2020 }
    YAML
  end

  let(:path) { File.join(tmpdir, "17-21-012.yaml") }

  before do
    File.write(path, managed_yaml + localized_yaml)
  end

  describe ".read" do
    it "loads a multi-doc YAML stream into managed + localized concept models" do
      cf = described_class.read(path)
      expect(cf.managed).to be_a(Glossarist::V3::ManagedConcept)
      expect(cf.localized.length).to eq(1)
      expect(cf.localized.first).to be_a(Glossarist::V3::LocalizedConcept)
    end

    it "exposes the path" do
      cf = described_class.read(path)
      expect(cf.path).to eq(path)
    end

    it "starts not dirty" do
      cf = described_class.read(path)
      expect(cf).not_to be_dirty
    end
  end

  describe "#find_localized" do
    it "returns the localized doc matching the given language_code" do
      cf = described_class.read(path)
      eng = cf.find_localized("eng")
      expect(eng).not_to be_nil
      expect(eng.data.language_code).to eq("eng")
    end

    it "returns nil when no matching language_code exists" do
      cf = described_class.read(path)
      expect(cf.find_localized("deu")).to be_nil
    end
  end

  describe "#add_localized" do
    let(:deu) do
      Glossarist::V3::LocalizedConcept.new(
        data: { language_code: "deu", terms: [], definition: [], notes: [], examples: [] }
      )
    end

    it "appends a localized concept and marks the file dirty" do
      cf = described_class.read(path)
      expect { cf.add_localized(deu) }.to change { cf.dirty? }.from(false).to(true)
      expect(cf.localized.length).to eq(2)
    end

    it "upserts when a localized doc with the same language_code exists" do
      cf = described_class.read(path)
      original_eng = cf.find_localized("eng")
      cf.add_localized(original_eng)  # idempotent re-add
      expect(cf.localized.length).to eq(1)
    end
  end

  describe "#save (dirty-gated)" do
    it "writes when dirty" do
      cf = described_class.read(path)
      cf.managed.status = "draft"   # actually change the value
      mtime_before = File.mtime(path)
      sleep 0.05  # ensure mtime differs if written
      written = cf.save
      expect(written).to be(true)
      expect(File.mtime(path)).to be > mtime_before
    end

    it "skips write when not dirty" do
      cf = described_class.read(path)
      mtime_before = File.mtime(path)
      sleep 0.05
      written = cf.save
      expect(written).to be(false)
      expect(File.mtime(path)).to eq(mtime_before)
    end
  end

  describe "round-trip" do
    it "preserves all data across save and reload" do
      cf1 = described_class.read(path)
      cf1.managed.status = "draft"
      cf1.save

      cf2 = described_class.read(path)
      expect(cf2.managed.status).to eq("draft")
      expect(cf2.find_localized("eng").data.terms.first.designation).to eq("light")
    end
  end

  describe ".open (block form)" do
    it "auto-saves on block exit if dirty" do
      mtime_before = File.mtime(path)
      sleep 0.05
      described_class.open(path) do |cf|
        cf.managed.status = "draft"
      end
      expect(File.mtime(path)).to be > mtime_before
    end

    it "skips save on block exit if not dirty" do
      mtime_before = File.mtime(path)
      sleep 0.05
      described_class.open(path) { |_cf| }  # no mutation
      expect(File.mtime(path)).to eq(mtime_before)
    end
  end
end
