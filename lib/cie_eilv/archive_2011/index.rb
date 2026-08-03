# frozen_string_literal: true

require "json"
require "fileutils"

module CieEilv
  module Archive2011
    # Enumerates all archived term pages on the defunct eilv.cie.co.at site
    # via the Wayback CDX Server API. One CDX query returns every snapshot
    # of every `eilv.cie.co.at/term/*` URL; we filter to HTML 200s and
    # dedupe by URL keeping the latest snapshot at or before TARGET_TIMESTAMP.
    #
    # The Drupal listing pages (`/indexpage/term/all`, paginated) were only
    # partially archived — most `?page=N` URLs are missing. CDX enumeration
    # is the authoritative source of "what term pages exist in the archive".
    #
    # Records have no listing_designation — that field is parsed from each
    # term page itself during the transform phase.
    class Index
      CDX_PATTERN = "eilv.cie.co.at/term/*".freeze
      # `/term/<digits>` followed by end, slash, or `?`. Rejects look-alikes
      # like `/termlist` and accepts `/term/157/` or `/term/N?query=...`.
      ARCHIVE_ID_RE = %r{/term/(\d+)(?=[/?]|\z)}.freeze

      class << self
        # Query CDX + dedupe to one record per term URL (latest snapshot ≤
        # TARGET_TIMESTAMP). Returns an Array of records sorted by archive_id:
        #   { archive_id:, original_url:, wayback_url:, snapshot_timestamp: }
        def fetch_and_parse
          snapshots = Client.cdx_query(CDX_PATTERN)
          dedupe_latest_per_url(snapshots).filter_map { |s| record_from_snapshot(s) }
            .sort_by { |r| r[:archive_id].to_i }
        end

        # Write +records+ as pretty JSON to +path+.
        def write_index(records, path)
          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, JSON.pretty_generate(records))
        end

        private

        # From all CDX rows, keep only HTML 200s, then for each distinct
        # original URL keep the row with the maximum timestamp.
        def dedupe_latest_per_url(snapshots)
          valid = snapshots.select { |s| html_200?(s) }
          grouped = valid.group_by { |s| canonical_original(s[:original]) }
          grouped.map do |_url, rows|
            rows.max_by { |s| s[:timestamp] }
          end
        end

        def html_200?(snapshot)
          snapshot[:statuscode] == "200" && snapshot[:mimetype] == "text/html"
        end

        # Strip the optional :80 port, trailing slash, and any query
        # string so the same logical URL always maps to the same key.
        # CDX records variants like :80 vs no-port, trailing /, and
        # search-result clicks like ?sourceid=chrome&...
        def canonical_original(url)
          url.to_s
             .sub(":80/", "/")
             .sub(/[?#].*\z/, "")
             .sub(%r{/\z}, "")
        end

        def record_from_snapshot(snapshot)
          original = canonical_original(snapshot[:original])
          archive_id = extract_archive_id(original)
          return nil unless archive_id

          # Drop any query string / fragment and trailing slash so the
          # cache key is stable.
          original = original.sub(/[?#].*\z/, "").sub(%r{/\z}, "")
          timestamp = snapshot[:timestamp]
          {
            archive_id: archive_id,
            original_url: original,
            wayback_url: wayback_url_for(timestamp, original),
            snapshot_timestamp: timestamp
          }
        end

        def extract_archive_id(original_url)
          m = original_url.match(ARCHIVE_ID_RE)
          m ? m[1] : nil
        end

        def wayback_url_for(timestamp, original_url)
          "https://web.archive.org/web/#{timestamp}/#{original_url}"
        end
      end
    end
  end
end
