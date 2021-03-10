module NL
  module KNC
    # Include and extend in modules or classes to provide a logging method.
    module KNCLog
      # Prints the given message, prefixed by the current time and the
      # class/module name.
      def log(msg)
        origin = (self.is_a?(Module) ? self : self.class).name
        color = (origin.hash ^ (origin.hash >> 15)) % 6 + 31
        bold = (origin.hash >> 10) & 1
	puts "\e[38;5;240m#{Time.now.strftime('%Y-%m-%d %H:%M:%S.%6N %z')} - \e[#{bold};#{color}m#{origin}\e[0;38;5;240m - \e[0m#{msg}"
      end

      # Logs an exception
      def log_e(e, msg = nil)
	msg = "\e[1;31m#{msg ? (msg + ' - ') : ''}#{e.inspect}\n\t\e[22m#{e.backtrace.join("\n\t")}\e[0m"
	msg.gsub!(/^(\s*)#{Regexp.escape(File.dirname(__FILE__))}/, '\\1')
	log msg

        if defined?(EventLog)
          EventLog.error "Internal error; contact support:\n#{msg}", 'System'
	end
      end
    end
  end
end
