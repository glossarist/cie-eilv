# 02 — Build the HTTP client

## Goal

Single network surface for the whole pipeline. MD5-keyed on-disk cache,
rate-limited, retry-on-5xx, with the Drupal-UA workaround.

The e-ILV site is plain HTTPS GET — there is **no API**. Unlike
`iala-vocab`'s MediaWiki client, we don't dispatch on `action` params;
every request is just "fetch this URL and return the body".

## File: `lib/cie_eilv/api_client.rb`

Public API:

```ruby
module CieEilv
  class ApiClient
    BASE = "https://cie.co.at".freeze
    RATE_LIMIT_DELAY = ENV.fetch("CIE_API_DELAY", "0.2").to_f
    USER_AGENT = "Mozilla/5.0 (CieEilv scraper; +https://glossarist.org)".freeze

    # Fetch +url+ (absolute or relative to BASE). Returns the response body as
    # a String. Cached by MD5(canonical_url) under reference-docs/api-cache/.
    # To force a re-fetch, delete the cache file.
    def self.fetch(url)
      ...
    end

    # Fetch /eilvterm/<termid>. Returns HTML String.
    def self.fetch_term(termid)
      fetch("/eilvterm/#{termid}")
    end

    # Fetch the term listing page. Returns HTML String.
    def self.fetch_listing
      fetch("/e-ilv")
    end

    private

    def self.cache_path_for(url)
      hash = Digest::MD5.hexdigest(canonical(url))
      File.join("reference-docs", "api-cache", "#{hash}.html")
    end

    def self.canonical(url)
      # Strip fragment, normalize trailing slash, absolutize against BASE.
      ...
    end

    def self.http_get(url)
      # HTTParty.get with headers, retries, rate limit. Raises on 4xx.
      ...
    end
  end
end
```

### Behavior contract

1. **Cache hit**: if `reference-docs/api-cache/<md5>.html` exists and is
   non-empty, return its contents without hitting the network. This is the
   source of truth for re-runs.
2. **Cache miss**: send `HTTParty.get` with `headers: { "User-Agent" => USER_AGENT }`.
   - On 5xx: retry up to 3 times with exponential backoff (1s, 2s, 4s).
   - On 4xx: raise immediately with the URL and status in the message.
   - On 2xx: write the body to the cache file (creating parent dirs), then
     sleep `RATE_LIMIT_DELAY` seconds, then return the body.
3. **Canonicalization**: same URL must hash to the same cache file. Strip
   `#fragment`, ensure a single `/` between BASE and path, lowercase the host.
   `/eilvterm/17-21-012` and `https://cie.co.at/eilvterm/17-21-012/` must
   both resolve to the same cache entry.

### Why MD5(url) as the cache key

Same pattern as `iala-vocab/scripts/iala_api.rb`. Filenames stay short,
no path-escaping issues, and the cache is opaque (the URL → hash mapping
is reproducible from anywhere). Trade-off: you can't tell what a cache
file contains by its name. Mitigation: keep a sibling
`reference-docs/api-cache/<md5>.url` text file alongside each `.html`
holding the canonical URL — written at cache time, used for debugging
"which URL produced this file?"

## Specs (`spec/api_client_spec.rb`)

Use the **real** HTTP layer against `cie.co.at` for a happy-path test (the
site is stable, public, and rate-limited). Mock-free is fine for one test.
Wrap in a `before(:all)` that ensures the cache dir is wiped, so the test
exercises the real network path.

Cases:

1. `fetch_term("17-21-012")` returns a String containing
   `<p class="TermEntry">light`.
2. Second call to `fetch_term("17-21-012")` returns the SAME String and does
   not hit the network (verify by setting `CIE_API_DELAY=999` env and
   confirming the call is still instant — the cache short-circuits).
3. `fetch("https://cie.co.at/eilvterm/17-21-012")` and
   `fetch("/eilvterm/17-21-012/")` produce the same cache file.
4. A 404 URL raises with the URL in the message. (Test against
   `/eilvterm/00-00-000` which does not exist.)
5. After a successful fetch, the cache file exists and the sibling `.url`
   file contains the canonical URL.

## Verification

```bash
bundle exec rspec spec/api_client_spec.rb
bundle exec ruby -e 'require "cie_eilv"; puts CieEilv::ApiClient.fetch_listing[0..50]'
```

Both must pass. The one-liner should print the first 50 chars of the
`/e-ilv` listing page (starts with `<!DOCTYPE html>` or similar).

## Do not

- Do NOT add a `parse` method or HTML parsing here. The client is
  byte-oriented; parsing belongs in `TermParser` (step 05).
- Do NOT silently swallow 4xx and return cached data. 4xx means the URL is
  wrong — fail loudly.
- Do NOT cache the rate-limit sleep across cache hits. Cache hits return
  immediately; only network responses pay the rate-limit cost.
