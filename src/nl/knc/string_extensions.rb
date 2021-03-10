require 'uri'

module NL
  module KNC
    module StringExtensions
      # Converts the string's list of URI-style key-value pairs into a Hash.
      # TODO: find a library function that does this (decode_www_form does
      # not handle [] the way we want)
      def urikvp
        h = nil
        Bench.bench 'urikvp' do
          h = {}
          self.split(/[&;]/).each do |pair|
            k, v = pair.split('=', 2).map!{ |s|
              s.gsub! '+', ' '
              URI.decode_www_form_component s
            }
            if k.end_with?('[]')
              h[k] ||= []
              h[k] << v
            else
              h[k] = v
            end
          end
        end
        h
      end

      def text_to_html
        s = EscapeUtils.escape_html self
        s.gsub(/\t/, '&nbsp;&nbsp;&nbsp;&nbsp;').gsub(/\n/,'<br>')
      end

      # Splits the string on camel-case boundaries
      def camel
        split(/(?<=[^[:upper:]])(?=[[:upper:]])/)
      end
    end

    String.include(StringExtensions)
  end
end
