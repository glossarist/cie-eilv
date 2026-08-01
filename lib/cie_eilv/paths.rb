# frozen_string_literal: true

module CieEilv
  module Paths
    BASE_URL       = "https://cie.co.at".freeze
    DATASET_ID     = "cie-2020".freeze
    URN            = "urn:cie:ilv:cie-2020".freeze

    DATASET_DIR    = "datasets/cie-2020".freeze
    CONCEPTS_DIR   = "#{DATASET_DIR}/concepts".freeze
    REGISTER_PATH  = "#{DATASET_DIR}/register.yaml".freeze

    REFERENCE_DOCS = "reference-docs".freeze
    CACHE_DIR      = "#{REFERENCE_DOCS}/api-cache".freeze
    INDEX_PATH     = "#{REFERENCE_DOCS}/scraped/terms/index.json".freeze
    PAGES_DIR      = "#{REFERENCE_DOCS}/scraped/terms/pages".freeze
    REPORTS_DIR    = "#{REFERENCE_DOCS}/reports".freeze
  end
end
