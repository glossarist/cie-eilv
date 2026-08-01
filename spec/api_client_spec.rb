# frozen_string_literal: true
require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe CieEilv::ApiClient, :network do
  let(:real_term_html_marker) { %(<p class="TermEntry">light) }

  describe ".fetch_term" do
    around do |ex|
      Dir.mktmpdir("cie-api-client-spec") do |dir|
        # Run from a clean cwd so cache paths land in the tmpdir.
        Dir.chdir(dir, &ex)
      end
    end

    it "fetches a known term page over the network and returns HTML" do
      html = described_class.fetch_term("17-21-012")
      expect(html).to include(real_term_html_marker)
    end

    it "writes a cache file and a sibling .url file after a network fetch" do
      described_class.fetch_term("17-21-012")
      cache_files = Dir.glob("#{CieEilv::Paths::CACHE_DIR}/*")
      expect(cache_files.length).to eq(2) # .html + .url
      html_file = cache_files.find { |f| f.end_with?(".html") }
      url_file = cache_files.find { |f| f.end_with?(".url") }
      expect(File.size(html_file)).to be > 0
      expect(File.read(url_file)).to eq("https://cie.co.at/eilvterm/17-21-012")
    end

    it "serves the cached body on the second call without re-hitting the network" do
      first = described_class.fetch_term("17-21-012")
      # Break the network path: if .fetch hits the network with delay=999,
      # a cache miss would take 999s. A cache hit returns instantly.
      ENV["CIE_API_DELAY"] = "999"
      start = Time.now
      second = described_class.fetch_term("17-21-012")
      elapsed = Time.now - start
      ENV.delete("CIE_API_DELAY")
      expect(second).to eq(first)
      expect(elapsed).to be < 1.0
    end

    it "canonicalizes paths so /eilvterm/X and https://cie.co.at/eilvterm/X/ share cache" do
      described_class.fetch("/eilvterm/17-21-012")
      cache_files = Dir.glob("#{CieEilv::Paths::CACHE_DIR}/*.html")
      expect(cache_files.length).to eq(1)
      described_class.fetch("https://cie.co.at/eilvterm/17-21-012/")
      cache_files_after = Dir.glob("#{CieEilv::Paths::CACHE_DIR}/*.html")
      expect(cache_files_after.length).to eq(1)
    end
  end

  describe ".fetch_term on a non-existent term" do
    around do |ex|
      Dir.mktmpdir("cie-api-client-spec") do |dir|
        Dir.chdir(dir, &ex)
      end
    end

    it "raises with the URL and status in the message" do
      expect { described_class.fetch_term("00-00-000") }.to raise_error(/404|410|cie\.co\.at/)
    end
  end

  describe ".canonical (private, tested via behavior)" do
    it "strips fragments and lowercases the host" do
      canon = described_class.send(:canonical, "HTTPS://CIE.CO.AT/eilvterm/17-21-012#frag")
      expect(canon).to eq("https://cie.co.at/eilvterm/17-21-012")
    end
  end
end
