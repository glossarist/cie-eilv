#!/usr/bin/env ruby
# frozen_string_literal: true

require "cie_eilv"
require "nokogiri"
require "json"
require "fileutils"

STDOUT.sync = true

module ImageFetch
  IMAGE_PATH_RE = %r{/sites/default/files/images/([^"?]+)}.freeze
  WAYBACK_RE = %r{\Ahttps?://web\.archive\.org/web/\d{14}(?:[a-z]{2}_)?/(.*)\z}m.freeze

  module_function

  # Extract the original image URL from the Wayback URL in the HTML.
  # Returns nil if not a Wayback eilv image URL.
  def original_image_url(wayback_url)
    return nil unless wayback_url.include?("eilv.cie.co.at/sites/default/files/")
    m = wayback_url.match(WAYBACK_RE)
    m ? m[1] : nil
  end

  def filename_from_url(url)
    m = url.match(IMAGE_PATH_RE)
    return nil unless m
    m[1]
  end
end

images_dir = CieEilv::Archive2011::Paths::IMAGES_DIR
pages_dir = CieEilv::Archive2011::Paths::PAGES_DIR
FileUtils.mkdir_p(images_dir)

# Walk all cached term pages, collect unique ORIGINAL image URLs.
image_urls = {}
Dir.glob("#{pages_dir}/*.html").sort.each do |path|
  doc = Nokogiri::HTML(File.read(path))
  doc.css("img[src]").each do |img|
    src = img["src"].to_s.strip
    original = ImageFetch.original_image_url(src)
    next unless original

    filename = ImageFetch.filename_from_url(original)
    next unless filename

    # Track the original URL — we'll resolve via availability API at fetch time.
    image_urls[original] = filename
  end
end

# Optional slicing for parallel runs (same scheme as scrape_2011_pages.rb).
slice_spec = ENV.fetch("CIE_SCRAPE_SLICE", nil)
entries = image_urls.to_a
if slice_spec && slice_spec =~ %r{\A(\d+)/(\d+)\z}
  slice_idx = Regexp.last_match(1).to_i
  slice_count = Regexp.last_match(2).to_i
  entries = entries.each_slice(slice_count).map { |chunk| chunk[slice_idx] }.compact
end

total = entries.length
fetched = 0
cached = 0
failed = []

puts "Discovered #{image_urls.length} unique image URL(s) across cached pages; processing #{total}."

entries.each.with_index do |(original_url, filename), i|
  out = File.join(images_dir, filename)
  if File.exist?(out) && File.size(out) > 0
    cached += 1
  else
    begin
      # The URL embedded in the HTML has the HTML page's snapshot timestamp,
      # which usually doesn't match the image's archived snapshot. Resolve
      # the image's own latest snapshot via the availability API.
      body = CieEilv::Archive2011::Client.fetch_raw(
        CieEilv::Archive2011::Client.resolve_snapshot(original_url)
      )
      FileUtils.mkdir_p(File.dirname(out))
      File.binwrite(out, body)
      fetched += 1
    rescue CieEilv::Archive2011::Client::NotArchivedError => e
      failed << { url: original_url, error: "not_archived" }
    rescue StandardError => e
      warn "\nFAILED #{original_url}: #{e.class}: #{e.message}"
      failed << { url: original_url, error: "#{e.class}: #{e.message}" }
    end
  end

  print "\r[#{i + 1}/#{total}] fetched=#{fetched} cached=#{cached} failed=#{failed.length}    "
end

puts
puts "Done: #{total} images (#{fetched} fetched, #{cached} cached, #{failed.length} failed) under #{images_dir}/"

unless failed.empty?
  report_path = File.join(CieEilv::Archive2011::Paths::REFERENCE_DIR, "image-fetch-failures.json")
  FileUtils.mkdir_p(File.dirname(report_path))
  File.write(report_path, JSON.pretty_generate(failed))
  warn "Failures written to #{report_path}"
  warn "#{failed.length} images were not archived (no snapshot exists)."
end
