# frozen_string_literal: true

require "digest"

module CieEilv
  # UUID v5 (name + namespace, SHA-1 based) for deterministic managed-concept IDs.
  # RFC 4122 §4.3. Same +name+ under the same namespace always produces the
  # same UUID — important for cross-edition linking stability.
  module Uuid
    class << self
      # Returns the canonical 8-4-4-4-12 hex UUID for +name+ under the
      # CIE e-ILV namespace.
      def v5(name)
        format_uuid(derive(NAMESPACE_BYTES, name.to_s))
      end

      # Returns 16 raw bytes of the UUID v5 of +name+ hashed under +namespace_bytes+.
      def derive(namespace_bytes, name)
        hash = Digest::SHA1.digest(namespace_bytes + name)
        bytes = hash.bytes.first(16)
        bytes[6] = (bytes[6] & 0x0f) | 0x50   # version 5
        bytes[8] = (bytes[8] & 0x3f) | 0x80   # variant RFC 4122
        bytes.pack("C*")
      end

      # Formats 16 raw bytes as the canonical UUID hex form.
      def format_uuid(raw_bytes)
        hex = raw_bytes.unpack1("H*")
        "#{hex[0, 8]}-#{hex[8, 4]}-#{hex[12, 4]}-#{hex[16, 4]}-#{hex[20, 12]}"
      end

      # Parses a canonical UUID string into 16 raw bytes.
      def parse(uuid_str)
        [uuid_str.delete("-")].pack("H*")
      end
    end

    # RFC 4122 §4.2.2 DNS namespace UUID, as 16 raw bytes.
    DNS_NAMESPACE_BYTES = parse("6ba7b810-9dad-11d1-80b4-00c04fd430c8").freeze

    # The CIE e-ILV namespace: v5("cie.co.at") under the DNS namespace.
    # Anchors this dataset's UUID space to the source domain.
    NAMESPACE_BYTES = derive(DNS_NAMESPACE_BYTES, "cie.co.at").freeze
  end
end
