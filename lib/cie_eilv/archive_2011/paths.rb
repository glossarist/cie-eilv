# frozen_string_literal: true

module CieEilv
  module Archive2011
    # Path constants for the 2011 archive scrape + dataset.
    #
    # Scraped HTML and the snapshot-resolution map live under
    # `reference-docs/scraped/editions/cie-2011/` so the 2020 and 2011
    # pipelines don't collide. MD5-keyed HTTP bodies go to the shared
    # `reference-docs/api-cache/` with an `archive-` filename prefix.
    module Paths
      DATASET_ID     = "cie-2011".freeze
      URN            = "urn:cie:ilv:cie-2011".freeze
      DATASET_DIR    = "datasets/cie-2011".freeze
      CONCEPTS_DIR   = "#{DATASET_DIR}/concepts".freeze
      REGISTER_PATH  = "#{DATASET_DIR}/register.yaml".freeze

      REFERENCE_DIR  = "reference-docs/scraped/editions/cie-2011".freeze
      INDEX_PATH     = "#{REFERENCE_DIR}/index.json".freeze
      PAGES_DIR      = "#{REFERENCE_DIR}/pages".freeze
      IMAGES_DIR     = "#{REFERENCE_DIR}/images".freeze
      SNAPSHOTS_PATH = "#{REFERENCE_DIR}/snapshots.json".freeze

      ORIGINAL_BASE    = "http://eilv.cie.co.at".freeze

      ARCHIVE_BASE     = "https://web.archive.org".freeze
      AVAILABILITY_API = "https://archive.org/wayback/available".freeze

      # "Latest snapshot before 2020" — pin every fetch to the most recent
      # Wayback snapshot at or before this timestamp. Makes the scrape
      # reproducible: re-runs hit the same snapshot even if archive.org
      # adds new ones later.
      TARGET_TIMESTAMP = "20191231235959".freeze
    end
  end
end
