module NL
  module KNC
    module HashExtensions
      # Only works with simple keys and values (e.g. numbers, strings).
      def to_kvp
        self.map{|k, v| "#{k.to_s.inspect}=#{v.inspect}"}.join(" ")
      end

      # Performs a deep comparison (nested objects that respond to deep_equals
      # will be compared using deep_equals).
      def deep_equals(other)
        return false unless other.is_a?(Hash) && other == self

        self.each do |k, v|
          if v.respond_to?(:deep_equals)
            result = v.deep_equals(other[k])
          else
            result = v == other[k]
          end

          return false unless result
        end

        true
      end

      # Clones this hash, also cloning children that respond to deep_clone.
      def deep_clone
        h = self.clone

        h.each do |k, v|
          if v.respond_to?(:deep_clone)
            h[k] = v.deep_clone
          end
        end

        h
      end

      # Merges the other hash, making sure that nested objects that respond to
      # deep_clone are distinct objects.
      def deep_merge!(other)
        other.each do |k, v|
          if v.equal?(self[k]) && v.respond_to?(:deep_clone)
            self[k] = v.deep_clone
          elsif v.is_a?(Hash) && self[k].is_a?(Hash)
            self[k].deep_merge! v
          elsif v.respond_to?(:deep_clone)
            self[k] = v.deep_clone
          else
            self[k] = v
          end
        end

        self
      end
    end

    Hash.include(HashExtensions)
  end
end
