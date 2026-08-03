# frozen_string_literal: true

require "spec_helper"

RSpec.describe CieEilv::Archive2011::Index do
  describe ".parse (via #parse internals) — record_from_snapshot shape" do
    # The CDX query is live-network; spec the dedup/filter logic via a
    # synthetic snapshot set.
    let(:snapshots) do
      [
        # Two snapshots of the same URL — different timestamps.
        { urlkey: "k1", timestamp: "20150101000000", original: "http://eilv.cie.co.at/term/1",
          mimetype: "text/html", statuscode: "200", digest: "a", length: 100 },
        { urlkey: "k1", timestamp: "20190101000000", original: "http://eilv.cie.co.at/term/1",
          mimetype: "text/html", statuscode: "200", digest: "b", length: 200 },
        # Different URL with :80 port variant — must dedupe with the no-port version.
        { urlkey: "k2", timestamp: "20190101000000", original: "http://eilv.cie.co.at:80/term/2",
          mimetype: "text/html", statuscode: "200", digest: "c", length: 100 },
        { urlkey: "k2", timestamp: "20190201000000", original: "http://eilv.cie.co.at/term/2",
          mimetype: "text/html", statuscode: "200", digest: "d", length: 100 },
        # Non-200 status — must be filtered out.
        { urlkey: "k3", timestamp: "20190101000000", original: "http://eilv.cie.co.at/term/3",
          mimetype: "text/html", statuscode: "404", digest: "e", length: 50 },
        # Non-HTML mimetype — must be filtered out.
        { urlkey: "k4", timestamp: "20190101000000", original: "http://eilv.cie.co.at/term/4",
          mimetype: "application/pdf", statuscode: "200", digest: "f", length: 1000 },
        # Non-term URL — must be dropped by the archive_id regex.
        { urlkey: "k5", timestamp: "20190101000000", original: "http://eilv.cie.co.at/termlist",
          mimetype: "text/html", statuscode: "200", digest: "g", length: 100 },
        # Trailing slash + query string — must be normalized.
        { urlkey: "k6", timestamp: "20190101000000", original: "http://eilv.cie.co.at/term/157/?x=1",
          mimetype: "text/html", statuscode: "200", digest: "h", length: 100 }
      ]
    end

    it "dedupes by URL, keeping the latest snapshot per URL" do
      records = described_class.send(:dedupe_latest_per_url, snapshots)
      originals = records.map { |r| r[:original] }.sort
      # Two URLs (1 and 2) survive, plus the trailing-slash variant (6).
      expect(originals).to include(
        "http://eilv.cie.co.at/term/1",
        "http://eilv.cie.co.at/term/2",
        "http://eilv.cie.co.at/term/157/?x=1"
      )
      # The latest snapshot of term/1 is 2019, not 2015.
      term1 = records.find { |r| r[:original] == "http://eilv.cie.co.at/term/1" }
      expect(term1[:timestamp]).to eq("20190101000000")
    end

    it "drops non-200 and non-HTML rows" do
      records = described_class.send(:dedupe_latest_per_url, snapshots)
      originals = records.map { |r| r[:original] }
      expect(originals).not_to include("http://eilv.cie.co.at/term/3")  # 404
      expect(originals).not_to include("http://eilv.cie.co.at/term/4")  # PDF
    end

    it "drops URLs that don't match the /term/<digits> shape" do
      records = described_class.send(:dedupe_latest_per_url, snapshots)
      records = records.map { |s| described_class.send(:record_from_snapshot, s) }.compact
      ids = records.map { |r| r[:archive_id] }
      expect(ids).not_to include(nil)
      expect(ids).not_to include("list") # from /termlist
    end

    it "extracts the archive_id from URLs with trailing slash or query" do
      record = described_class.send(:record_from_snapshot,
                                    original: "http://eilv.cie.co.at/term/157/?x=1",
                                    timestamp: "20190101000000",
                                    mimetype: "text/html",
                                    statuscode: "200")
      expect(record[:archive_id]).to eq("157")
      expect(record[:original_url]).to eq("http://eilv.cie.co.at/term/157")
      expect(record[:snapshot_timestamp]).to eq("20190101000000")
      expect(record[:wayback_url]).to eq(
        "https://web.archive.org/web/20190101000000/http://eilv.cie.co.at/term/157"
      )
    end
  end
end
