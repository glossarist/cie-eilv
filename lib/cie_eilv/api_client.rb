# frozen_string_literal: true

require "httparty"
require "digest"
require "fileutils"
require "uri"
require "socket"
require "net/protocol"

module CieEilv
  # The only network surface in the pipeline. Plain HTTPS GETs against
  # cie.co.at (no API; the e-ILV is plain Drupal-rendered HTML). All
  # responses are cached by MD5(canonical_url) under Paths::CACHE_DIR.
  #
  # To force a re-fetch, delete the relevant cache file (or all of
  # Paths::CACHE_DIR). Once cached, the cache is the source of truth —
  # upstream changes will not be picked up until the cache is invalidated.
  class ApiClient
    class Error < StandardError; end
    class ClientError < Error; end
    class ServerError < Error; end

    USER_AGENT = "Mozilla/5.0 (CieEilv scraper; +https://glossarist.org)".freeze
    RATE_LIMIT_DELAY = ENV.fetch("CIE_API_DELAY", "0.2").to_f
    MAX_RETRIES = 3

    # Network-level errors that should trigger the retry path. Ruby's
    # Net::HTTP and HTTParty raise a variety of socket/stream errors;
    # all of them are transient and worth retrying.
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
      # Fetch the term listing page (https://cie.co.at/e-ilv). Returns HTML.
      def fetch_listing
        fetch("/e-ilv")
      end

      # Fetch a single term page (https://cie.co.at/eilvterm/<termid>). Returns HTML.
      def fetch_term(termid)
        fetch("/eilvterm/#{termid}")
      end

      # Fetch +url+ (absolute, or relative to Paths::BASE_URL). Returns the
      # response body as a String. Cached by MD5(canonical_url).
      def fetch(url)
        canonical_url = canonical(url)
        cached = read_cache(canonical_url)
        return cached if cached

        body = http_get(canonical_url)
        write_cache(canonical_url, body)
        body
      end

      # Canonical form of +url+: absolute, lowercase host, no fragment,
      # single trailing-slash policy (paths under /eilvterm/<id> only).
      # The same logical URL must produce the same cache key.
      def canonical(url)
        u = URI.parse(url.to_s)
        u.host ||= Paths::BASE_URL.sub(%r{\Ahttps?://}, "")
        u.host = u.host.downcase
        u.scheme = "https"
        u.path = "/" if u.path.empty?
        u.path = u.path.sub(%r{/+\z}, "") unless u.path == "/"
        u.fragment = nil
        u.query = nil
        u.to_s
      end

      private

      def cache_files_for(canonical_url)
        hash = Digest::MD5.hexdigest(canonical_url)
        base = File.join(Paths::CACHE_DIR, hash)
        { body: "#{base}.html", url: "#{base}.url" }
      end

      def read_cache(canonical_url)
        files = cache_files_for(canonical_url)
        return nil unless File.exist?(files[:body]) && File.size?(files[:body])

        File.read(files[:body])
      end

      def write_cache(canonical_url, body)
        files = cache_files_for(canonical_url)
        FileUtils.mkdir_p(Paths::CACHE_DIR)
        File.write(files[:body], body)
        File.write(files[:url], canonical_url)
      end

      def http_get(url, attempt: 1)
        response = HTTParty.get(
          url,
          headers: { "User-Agent" => USER_AGENT, "Accept" => "text/html" },
          timeout: 30
        )

        if response.code >= 500 && response.code < 600
          raise ServerError, "server error #{response.code} for #{url}"
        elsif response.code >= 400 && response.code < 500
          raise ClientError, "client error #{response.code} for #{url}"
        end

        sleep RATE_LIMIT_DELAY
        response.body
      rescue *TRANSIENT_ERRORS => e
        if attempt < MAX_RETRIES
          backoff = 2**(attempt - 1)
          warn "ApiClient: #{e.class}: #{e.message}. Retrying in #{backoff}s (attempt #{attempt}/#{MAX_RETRIES})..."
          sleep backoff
          http_get(url, attempt: attempt + 1)
        else
          raise Error, "failed after #{MAX_RETRIES} retries: #{e.class}: #{e.message}"
        end
      end
    end
  end
end
