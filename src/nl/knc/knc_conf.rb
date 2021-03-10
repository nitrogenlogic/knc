# JSON configuration file storage for depth camera controller web daemon
# (C)2013 Mike Bourgeous

require 'json'

module NL
  module KNC
    # A wrapper for Hash that is easy to save to and load from a file as JSON.
    # Intended for storing configuration settings.  Don't add recursive hashes
    # (i.e. hashes that reference a parent or sibling that is also referenced
    # elsewhere in the tree of hashes).
    class KncConf < Hash
      include KNCLog

      # Initializes a KncConf object with JSON stored in the given file.
      def initialize(filename)
        raise 'Filename must be a string.' unless filename.is_a? String
        @filename = filename
        @saved = {}
        self.load
      end

      # Saves the configuration to the file specified at initialization.
      def save
        File.open(@filename + '.tmp', "w") do |f|
          f.write to_json
          f.fsync
        end

        File.rename(@filename + '.tmp', @filename)

        @saved = self.deep_clone
        self
      end

      # Loads the configuration from the file specified at initialization.
      # Any settings loaded from the file will be merged into this
      # configuration (call clear first if necessary).
      def load
        begin
          @saved = JSON.parse(File.read(@filename), :symbolize_names => true)
          deep_merge! @saved
        rescue Errno::ENOENT => e
        rescue => e
          log_e e, "Error loading #{@filename}."
        end
      end

      # Whether this configuration differs from what is stored in the file.
      def modified?
        !self.deep_equals(@saved)
      end

      # A human-readable string representation of this configuration hash.
      def to_s
        "'#{@filename}': #{modified? ? '' : 'un'}modified - #{super}"
      end
      alias_method :inspect, :to_s
    end
  end
end
