# frozen_string_literal: true

require "fileutils"
require "yaml"

module CieEilv
  # File handle for a multi-doc Glossarist v3 concept YAML file: one
  # +Glossarist::V3::ManagedConcept+ document followed by zero or more
  # +Glossarist::V3::LocalizedConcept+ documents.
  #
  # Read/write lifecycle with snapshot-based dirty tracking: dirty? compares
  # the current serialization against the initial serialization captured at
  # load time. This is robust to any mutation path on the underlying models
  # — no need for mutation-intercepting helpers.
  class ConceptFile
    class << self
      # Reads +path+ and returns a new ConceptFile with dirty? == false.
      def read(path)
        docs = YAML.load_stream(File.read(path))
        new(
          path: path,
          managed: load_managed(docs),
          localized: load_localized(docs)
        )
      end
      alias :load :read

      # Yields the concept file; auto-saves on block exit iff dirty.
      def open(path)
        cf = read(path)
        yield cf
        cf.save
        cf
      end

      private

      def load_managed(docs)
        return nil if docs.empty? || docs[0].nil?

        Glossarist::V3::ManagedConcept.from_yaml(docs[0].to_yaml)
      end

      def load_localized(docs)
        docs.drop(1).compact.map do |doc|
          Glossarist::V3::LocalizedConcept.from_yaml(doc.to_yaml)
        end
      end
    end

    attr_reader :path, :managed, :localized

    def initialize(path:, managed:, localized: [])
      @path = path
      @managed = managed
      @localized = localized
      @initial_serialization = current_serialization
    end

    def dirty?
      current_serialization != @initial_serialization
    end

    # Returns the localized concept for +language_code+, or nil.
    def find_localized(language_code)
      localized.find { |lc| lc.data&.language_code == language_code }
    end

    # Upserts +localized_concept+ by +language_code+. Marks dirty.
    def add_localized(localized_concept)
      lang = localized_concept.data&.language_code
      raise ArgumentError, "localized concept has no language_code" unless lang

      idx = localized.index { |existing| existing.data&.language_code == lang }
      idx ? localized[idx] = localized_concept : localized.push(localized_concept)
      self
    end

    # Writes to disk iff dirty. Returns true on write, false on skip.
    def save
      return false unless dirty?

      save!
    end

    # Writes to disk unconditionally. Returns true.
    def save!
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, current_serialization)
      @initial_serialization = current_serialization
      true
    end

    private

    def current_serialization
      parts = [managed.to_yaml]
      parts.concat(localized.map(&:to_yaml))
      parts.join
    end
  end
end
