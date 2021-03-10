require 'escape_utils'

module NL
  module KNC
    # Include in a module or class to get the h() method for escaping HTML.
    module HTMLEscape
      # Returns nil for nil, HTML-escaped string for String or object that responds
      # to :to_s, HTML-escaped inspected object for anything else.
      def h(str)
        str.nil? ? nil : EscapeUtils.escape_html(
          (str.is_a?(String) || str.respond_to?(:to_s)) ?
          str.to_s :
          str.inspect
        )
      end
    end
  end
end
