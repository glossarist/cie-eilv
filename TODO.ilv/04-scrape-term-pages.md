# 04 — Scrape every term page

## Goal

Download the HTML for every termid in `terms/index.json`, caching each page
under `reference-docs/scraped/terms/pages/<termid>.html`. This is the most
network-intensive step (~1,300 requests) and the one the cache most pays off
for on re-runs.

## File: `scripts/scrape_term_pages.rb`

```ruby
#!/usr/bin/env ruby
require "cie_eilv"
require "json"
require "fileutils"

INDEX = "reference-docs/scraped/terms/index.json"
OUT_DIR = "reference-docs/scraped/terms/pages"
FileUtils.mkdir_p(OUT_DIR)

index = JSON.parse(File.read(INDEX))
total = index.length

index.each.with_index do |entry, i|
  termid = entry["termid"]
  out = File.join(OUT_DIR, "#{termid}.html")
  if File.exist?(out) && File.size(out) > 0
    print "\r[#{i+1}/#{total}] cached #{termid}    "
    next
  end
  html = CieEilv::ApiClient.fetch_term(termid)
  File.write(out, html)
  print "\r[#{i+1}/#{total}] fetched #{termid}    "
end

puts
puts "Done: #{index.length} term pages under #{OUT_DIR}/"
```

### Behavior

- **Incremental**: existing non-empty files are skipped. Re-running the
  script picks up only newly-added termids (or those whose cache you deleted).
- **Rate-limited**: `CieEilv::ApiClient` already sleeps `CIE_API_DELAY`
  between network requests. Don't add a second sleep here.
- **No retry-on-page-error**: if `fetch_term` raises (4xx/5xx after retries),
  the script halts with the termid in the message. The on-disk index of
  what-succeeded is "files present in `pages/`" — resuming is just re-running
  the script.

### Expected runtime

At `CIE_API_DELAY=0.2`, ~1,300 pages × (network + 0.2s) ≈ 5–8 minutes on a
typical home connection. The cache means you only pay this once.

### Failure modes to watch

1. **Transient 5xx**: handled by `ApiClient`'s exponential backoff. If a
   particular page persistently 5xx's after 3 attempts, the script halts —
   investigate manually (the termid may have been retired or the URL pattern
   may have changed).
2. **404 for a valid termid**: should not happen given the listing is the
   authoritative source. If it does, log the termid and continue rather than
   halting — better to ship a 1,299-term dataset than none. Add a `--skip-missing`
   flag if you need this behavior; default is to halt (loud failure).
3. **Drupal cache invalidation**: occasionally `cie.co.at` regenerates a page
   and the HTML changes (e.g., a Note is added). The local cache will not
   reflect this. Solution: delete the affected `<termid>.html` and re-run.

## No specs for this script

This is a thin orchestration wrapper over `ApiClient` (which is already
spec'd in step 02). Adding a spec would mean mocking the network, which
gives no value. Verification is the post-run audit:

```bash
ls reference-docs/scraped/terms/pages/ | wc -l   # should equal jq length of index.json
```

## Verification

```bash
bundle exec ruby scripts/scrape_term_pages.rb
TOTAL=$(jq 'length' reference-docs/scraped/terms/index.json)
CACHED=$(ls reference-docs/scraped/terms/pages/ | wc -l)
echo "index=$TOTAL cached=$CACHED"
test "$TOTAL" -eq "$CACHED" && echo OK || echo MISMATCH
```

`OK` is required before proceeding. If `MISMATCH`, look at which termids
are missing:

```bash
jq -r '.[].termid' reference-docs/scraped/terms/index.json | sort > /tmp/index.txt
ls reference-docs/scraped/terms/pages/ | sed 's/\.html$//' | sort > /tmp/cached.txt
comm -23 /tmp/index.txt /tmp/cached.txt   # missing termids
```

Re-run `scrape_term_pages.rb` to fill gaps.

## Do not

- Do NOT pre-validate the HTML in this step. Validation belongs in step 05
  (TermParser). This step just downloads bytes.
- Do NOT delete and re-fetch all pages on every run. The cache is the
  whole point — respect `File.exist?` short-circuit.
- Do NOT parallelize with threads by default. The site is Drupal-on-CGI;
  be a polite citizen. If you must parallelize, cap at 4 concurrent and
  set `CIE_API_DELAY` to compensate.
