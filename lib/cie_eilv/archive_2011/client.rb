# frozen_string_literal: true

require "httparty"
require "digest"
require "fileutils"
require "json"
require "uri"

module CieEilv
  module Archive2011
    # HTTP client for the Wayback Machine (web.archive.org). Resolves each
    # original URL to its latest snapshot at or before Paths::TARGET_TIMESTAMP
    # via the availability API, then fetches and caches the body.
    #
    # Two layers of caching:
    # 1. snapshot_map (Paths::SNAPSHOTS_PATH): original_url -> wayback_url.
    #    Survives across runs so the availability API is hit once per URL.
    # 2. body cache (CieEilv::Paths::CACHE_DIR/archive-<md5>.html): the raw
    #    response body, keyed by MD5(wayback_url). Shared with the 2020
    #    pipeline's cache dir, distinguished by filename prefix.
    #
    # To force a re-resolve of one URL: delete its entry from snapshots.json
    # AND the corresponding archive-<md5>.html file.
    class Client
      class Error < StandardError; end
      class ClientError < Error; end
      class ServerError < Error; end
      class NotArchivedError < Error; end

      USER_AGENT = "Mozilla/5.0 (CieEilv archive.org scraper; +https://glossarist.org)".freeze
      RATE_LIMIT_DELAY = ENV.fetch("CIE_ARCHIVE_DELAY", "1.0").to_f
      MAX_RETRIES = 5

      TRANSIENT_ERRORS = [
        ServerError,
        Errno::ECONNRESET,
        Errno::ECONNREFUSED,
        Errno::EHOSTUNREACH,
        Errno::ETIMEDOUT,
        IOError,
        SocketError,
        Net::ReadTimeout,
        Net::OpenTimeout,
        Net::ProtocolError,
        HTTParty::Error
      ].freeze

      class << self
        # Fetch the body of the latest archived snapshot of +original_url+
        # at or before Paths::TARGET_TIMESTAMP. Returns the body String.
        # Raises NotArchivedError if no qualifying snapshot exists.
        def fetch(original_url)
          wayback_url = resolve_snapshot(original_url)
          fetch_raw(wayback_url)
        end

        # Convenience: fetch a single term page by archive_id (the Drupal
        # node id, e.g. 1319).
        def fetch_term(archive_id)
          fetch("#{Paths::ORIGINAL_BASE}/term/#{archive_id}")
        end

        # Query the CDX Server API for all archived snapshots matching the
        # URL +url_pattern+ (a wildcard pattern, e.g. "eilv.cie.co.at/term/*")
        # at or before Paths::TARGET_TIMESTAMP. Returns an Array of Hashes:
        #   { urlkey:, timestamp:, original:, mimetype:, statuscode:, digest:, length: }
        # Raw — no filtering or dedup. Caller picks the rows it wants.
        def cdx_query(url_pattern)
          response = HTTParty.get(
            "#{Paths::ARCHIVE_BASE}/cdx/search/cdx",
            query: {
              url: url_pattern,
              output: "json",
              from: "2000",
              to: Paths::TARGET_TIMESTAMP
            },
            headers: { "User-Agent" => USER_AGENT },
            timeout: 120
          )

          if response.code.between?(400, 499)
            raise ClientError, "CDX API returned #{response.code}"
          end
          if response.code.between?(500, 599)
            raise ServerError, "CDX API server error #{response.code}"
          end

          parse_cdx_json(response.body)
        end

        # Resolve +original_url+ to its Wayback URL via the availability
        # API. Caches the mapping on disk so subsequent runs skip the call.
        def resolve_snapshot(original_url)
          map = load_snapshot_map
          return map[original_url] if map[original_url]

          url = query_availability(original_url)
          map[original_url] = url
          write_snapshot_map(map)
          url
        end

        # Direct fetch of an absolute Wayback URL (already resolved).
        # Cached by MD5(url) under the shared api-cache dir.
        def fetch_raw(url)
          normalized = normalize_wayback_url(url)
          cache = body_cache_path(normalized)
          return File.read(cache) if File.exist?(cache) && File.size?(cache)

          body = http_get(normalized)
          FileUtils.mkdir_p(File.dirname(cache))
          File.write(cache, body)
          body
        end

        private

        # CDX JSON output: first row is the header (column names), remaining
        # rows are data. Map each row to a Hash keyed by symbol.
        def parse_cdx_json(body)
          rows = JSON.parse(body)
          return [] if rows.empty?

          header = rows.first.map(&:to_sym)
          rows.drop(1).map do |row|
            header.zip(row).to_h
          end
        end

        # Query the availability API for the closest snapshot at or before
        # TARGET_TIMESTAMP. Normalizes http:// -> https://.
        def query_availability(original_url)
          response = HTTParty.get(
            Paths::AVAILABILITY_API,
            query: { url: original_url, timestamp: Paths::TARGET_TIMESTAMP },
            headers: { "User-Agent" => USER_AGENT },
            timeout: 30
          )

          if response.code.between?(400, 499)
            raise ClientError,
                  "availability API returned #{response.code} for #{original_url}"
          end
          if response.code.between?(500, 599)
            raise ServerError,
                  "availability API server error #{response.code} for #{original_url}"
          end

          data = JSON.parse(response.body)
          closest = data.dig("archived_snapshots", "closest")
          unless closest && closest["available"]
            raise NotArchivedError,
                  "no Wayback snapshot for #{original_url} at or before #{Paths::TARGET_TIMESTAMP}"
          end

          # Guard against the API returning a snapshot AFTER our target date
          # (the "closest" semantic is bidirectional).
          if closest["timestamp"] > Paths::TARGET_TIMESTAMP
            raise NotArchivedError,
                  "closest snapshot for #{original_url} is #{closest['timestamp']} (after #{Paths::TARGET_TIMESTAMP})"
          end

          normalize_wayback_url(closest["url"])
        end

        # Force https, drop trailing slash. The availability API returns
        # http:// URLs; https:// is preferred and works for all Wayback URLs.
        def normalize_wayback_url(url)
          u = URI.parse(url.to_s)
          u.scheme = "https"
          u.to_s
        end

        def body_cache_path(url)
          hash = Digest::MD5.hexdigest(url)
          File.join(CieEilv::Paths::CACHE_DIR, "archive-#{hash}.html")
        end

        def load_snapshot_map
          return {} unless File.exist?(Paths::SNAPSHOTS_PATH)
          JSON.parse(File.read(Paths::SNAPSHOTS_PATH))
        rescue JSON::ParserError
          {}
        end

        def write_snapshot_map(map)
          FileUtils.mkdir_p(File.dirname(Paths::SNAPSHOTS_PATH))
          File.write(Paths::SNAPSHOTS_PATH, JSON.pretty_generate(map))
        end

        def http_get(url, attempt: 1)
          response = HTTParty.get(
            url,
            headers: { "User-Agent" => USER_AGENT, "Accept" => "text/html,*/*" },
            timeout: 60
          )

          if response.code == 429 || response.code.between?(500, 599)
            raise ServerError, "server error #{response.code} for #{url}"
          elsif response.code.between?(400, 499)
            raise ClientError, "client error #{response.code} for #{url}"
          end

          sleep RATE_LIMIT_DELAY
          response.body
        rescue *TRANSIENT_ERRORS => e
          if attempt < MAX_RETRIES
            backoff = 2**attempt
            warn "Archive2011::Client: #{e.class}: #{e.message}. Retrying in #{backoff}s (attempt #{attempt}/#{MAX_RETRIES})..."
            sleep backoff
            http_get(url, attempt: attempt + 1)
          else
            raise Error, "failed after #{MAX_RETRIES} retries: #{e.class}: #{e.message}"
          end
        end
      end
    end
  end
end
