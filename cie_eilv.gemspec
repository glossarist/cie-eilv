# frozen_string_literal: true

lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require_relative "lib/cie_eilv/version"

Gem::Specification.new do |spec|
  spec.name          = "cie_eilv"
  spec.version       = CieEilv::VERSION
  spec.summary       = "CIE e-ILV data pipeline — scrape, transform, audit, deploy"
  spec.description   = "Pipeline for building the CIE International Lighting Vocabulary (CIE S 017:2020) Glossarist Concept Browser dataset from the free e-ILV at https://cie.co.at/e-ilv."
  spec.authors       = ["Ribose Inc."]
  spec.email         = ["open.source@ribose.com"]
  spec.license       = "CC-BY-4.0"
  spec.homepage      = "https://github.com/glossarist/cie-eilv"

  spec.files         = Dir["lib/**/*.rb"]
  spec.bindir        = "exe"
  spec.executables   = Dir["exe/*"].map { |f| File.basename(f) }

  spec.required_ruby_version = ">= 3.0"

  spec.add_dependency "glossarist", ">= 2.8.18"
  spec.add_dependency "httparty", "~> 0.21"
  spec.add_dependency "nokogiri", "~> 1.15"

  spec.add_development_dependency "rspec", "~> 3.13"
  spec.add_development_dependency "rake", "~> 13.0"
end
