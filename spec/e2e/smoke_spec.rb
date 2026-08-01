# frozen_string_literal: true
require "spec_helper"
require "tmpdir"
require "fileutils"
require "json"

RSpec.describe "end-to-end pipeline", :e2e do
  let(:sample_termids) do
    %w[17-21-012 17-21-025 17-21-027 17-22-002 17-29-062]
  end

  it "scrapes (from cache), transforms, links, audits a 5-term sample" do
    Dir.mktmpdir("cie-eilv-e2e") do |tmp|
      Dir.chdir(tmp) do
        # Stage a tiny reference-docs from fixtures.
        FileUtils.mkdir_p("reference-docs/scraped/terms/pages")
        index = sample_termids.map do |id|
          FileUtils.cp(fixture_path("terms/#{id}.html"),
                       "reference-docs/scraped/terms/pages/#{id}.html")
          { "termid" => id, "listing_designation" => "" }
        end
        File.write("reference-docs/scraped/terms/index.json", JSON.generate(index))

        # Stub Paths to point at our sandbox.
        stub_const("CieEilv::Paths::INDEX_PATH", "reference-docs/scraped/terms/index.json")
        stub_const("CieEilv::Paths::PAGES_DIR", "reference-docs/scraped/terms/pages")
        stub_const("CieEilv::Paths::CONCEPTS_DIR", "datasets/cie-2020/concepts")
        stub_const("CieEilv::Paths::DATASET_DIR", "datasets/cie-2020")
        stub_const("CieEilv::Paths::REGISTER_PATH", "datasets/cie-2020/register.yaml")
        stub_const("CieEilv::RegisterBuilder::DATASET_ID", "cie-2020")
        stub_const("CieEilv::CrossRefLinker::CONCEPTS_DIR", "datasets/cie-2020/concepts")
        stub_const("CieEilv::Auditor::CONCEPTS_DIR", "datasets/cie-2020/concepts")
        stub_const("CieEilv::Auditor::INDEX_PATH", "reference-docs/scraped/terms/index.json")

        # Run pipeline pieces (lib calls, not script shellouts).
        CieEilv::RegisterBuilder.new.run!
        builder = CieEilv::ConceptBuilder.new
        sample_termids.each do |id|
          html = File.read("reference-docs/scraped/terms/pages/#{id}.html")
          term = CieEilv::TermParser.parse(html, termid: id)
          builder.write_concept(term, path: "datasets/cie-2020/concepts/#{id}.yaml")
        end
        CieEilv::CrossRefLinker.new.run!

        # Audit must pass.
        expect(CieEilv::Auditor.new.run!).to eq(0)

        # Output files exist and have the right shape.
        sample_termids.each do |id|
          path = "datasets/cie-2020/concepts/#{id}.yaml"
          expect(File.exist?(path)).to be(true)
          cf = CieEilv::ConceptFile.read(path)
          expect(cf.managed.data.id).to eq(id)
          expect(cf.find_localized("eng")).not_to be_nil
        end

        # Cross-ref in 17-21-012 is rewritten.
        cf = CieEilv::ConceptFile.read("datasets/cie-2020/concepts/17-21-012.yaml")
        note_text = cf.find_localized("eng").data.notes.map(&:content).join
        expect(note_text).to include("{{17-21-002,")
        expect(note_text).not_to include('href="/eilvterm/')

        # Register has all 12 sections.
        register = YAML.safe_load(File.read("datasets/cie-2020/register.yaml"), aliases: true)
        expect(register["sections"].length).to eq(12)
        expect(register["sections"].first["id"]).to eq("21")
      end
    end
  end
end
