# Event log for the Depth Camera Controller web UI.
# (C)2014 Mike Bourgeous

module NL
  module KNC
    module EventLog
      include KNCLog
      extend KNCLog

      # Version 2 introduced separate buffers for each log source
      KNC_EVENTLOG_VERSION = 2

      ERROR = 4
      WARNING = 3
      NORMAL = 2
      DEBUG = 1
      GOOD = 0

      LEVELS = [ 'good', 'debug', 'normal', 'warning', 'error' ]

      # "source" => RingBuffer
      @@logs = {}
      @@idx = 0

      @@watchers = []

      @@occupied = {}

      @@logger = proc { |type, param, param2=nil|
        Bench.bench 'Zone update log handler' do
          begin
            case type
            when :add
              normal "#{param['name']} added.", 'Zone'
              @@occupied[param['name']] = false

            when :del
              normal "#{param['name']} removed.", 'Zone'
              @@occupied.delete param['name']

            when :change
              if @@occupied[param['name']] != param['occupied']
                msg = "#{param['name']} #{param['occupied'] ? 'entered' : 'exited'} at "
                msg << "(#{param['xc']}, #{param['yc']}, #{param['zc']})."
                normal msg, 'Zone'
                @@occupied[param['name']] = param['occupied']
              end

            when :online
              add_log (param ? GOOD : ERROR), "#{param ? 'Online' : 'Offline'} after #{sectostr param2}.", 'Camera'
              @@occupied.clear unless param

            when :fps
              # Ignored

            end
          rescue Exception => e
            log_e e, "Error logging #{type.inspect} event"
          end
        end
      }

      # Returns a string of the form "DD days HH:MM:SS.s" for the given number
      # of seconds (which should be a Float).
      def self.sectostr(seconds)
        seconds = seconds.round(2)
        sec = seconds.to_i
        frac = 100 * (seconds - sec)
        sec = sec.to_i
        min = sec / 60
        hr = min / 60
        day = hr / 24
        hr = hr % 24
        min = min % 60
        sec = sec % 60

        showday = day > 0
        showhr = showday || hr > 0
        showmin = showhr || min > 0

        str = ""
        str << "#{day} days " if showday
        str << "#{hr}:" if showhr
        str << (showhr ? "%02d:" % min : "#{min}:") if showmin
        str << (showmin ? "%02d" % sec : sec.to_s)
        str << ".%02ds" % frac.to_i
        str
      end

      # Returns the callback used for logging events from Knc.
      def self.knc_handler
        @@logger
      end

      # Initializes the log with the given RingBuffer hash returned by old
      # versions of EventLog.store_log(), or the hash of RingBuffer hashes
      # returned by current versions of EventLog.store_log().
      def self.init_log(rbuf_hash)
        return unless rbuf_hash.is_a? Hash

        if rbuf_hash.include?(:version) && rbuf_hash[:version] >= 2
          rbuf_hash.each do |k, v|
            if v.is_a? Hash
              k = k.to_s
              @@logs[k] ||= RingBuffer.new(100)
              @@logs[k].load v
              log "Loaded #{v[:size]} entries (#{@@logs[k].length}) for source #{k.inspect}" # XXX
            end
          end
          @@idx = rbuf_hash[:idx]

          log "Stored index: #{@@idx}" # XXX
        else
          a = RingBuffer.new(100)
          a.load rbuf_hash
          a.each do |v|
            next unless v.is_a? Array
            log "Importing old entry #{v.inspect} of source #{v[4]}" # XXX
            @@logs[v[4]] ||= RingBuffer.new(100)
            @@logs[v[4]].push v
          end

          @@idx = [rbuf_hash[:idx] || rbuf_hash[:size] || rbuf_hash.size, @@idx].max
          log "New index after import: #{@@idx}" # XXX
          log "Candidates: :idx: #{rbuf_hash[:idx].inspect}, :size: #{rbuf_hash[:size].inspect}, .size: #{rbuf_hash.size.inspect}, @@idx: #{@@idx.inspect}" # XXX
        end
      end

      # Returns a RingBuffer hash that can later be given to
      # EventLog.init_log().
      def self.store_log
        # XXX
        log "Store log:\n\t#{caller.join("\n\t")}"
        log "Storing these sources: #{@@logs.keys}"

        h = {}
        @@logs.each do |k, v|
          log "Storing #{v.length} log entries for source #{k}"
          h[k] = v.store
        end
        h[:idx] = @@idx
        h[:version] = KNC_EVENTLOG_VERSION
        h
      end

      # Adds a new message to the log at the given level.  If source is a
      # string, the string will be recorded as the event source.  Otherwise,
      # the class name of the source will be recorded.
      def self.add_log(level, msg, source=nil)
        raise "Invalid log level #{level}" if level < GOOD || level > ERROR
        @@idx += 1

        source = source.class.name unless source.nil? || source.is_a?(String)
        entry = [ @@idx, Time.now.strftime('%Y-%m-%d %H:%M:%S.%3N %z'), level, msg, source ]

        @@logs[source] ||= RingBuffer.new(100)
        @@logs[source].push entry

        notify_watchers entry

        nil
      end

      # Adds an error message to the log.
      def self.error(msg, source=nil)
        add_log ERROR, msg, source
      end

      # Adds a warning message to the log.
      def self.warning(msg, source=nil)
        add_log WARNING, msg, source
      end

      # Adds a normal message to the log.
      def self.normal(msg, source=nil)
        add_log NORMAL, msg, source
      end

      # Adds a debug message to the log.
      def self.debug(msg, source=nil)
        add_log DEBUG, msg, source
      end

      # Adds a good message to the log.
      def self.good(msg, source=nil)
        add_log GOOD, msg, source
      end

      # Returns an array of arrays, each array describing a log event, sorted
      # by index.
      # TODO: Return an array of hashes?
      def self.to_a(source=nil)
        unless source.nil?
          return @@logs[source].to_a
        end

        a = []
        @@logs.each do |source, log|
          a.concat log.to_a
        end
        return a.sort_by!{|v| v[0] || 0}
      end

      # Returns an object with log info and an array of log entry hashes
      # converted to JSON, with the following structure:
      # {
      #     :idx => (current log index),
      #     :log => [
      #         {
      #             :idx => (index),
      #             :date => (date),
      #             :level => (severity),
      #             :msg => (message),
      #             :source => (source),
      #             :html => (html row) // If include_html is true
      #         },
      #         {
      #             ...
      #         }
      #     ]
      # }
      def self.to_json(include_html)
        items = EventLog.to_a.map! do |idx, date, level, msg, source|
          entry = { :idx => idx, :date => date, :level => level, :msg => msg, :source => source }
          entry[:html] = EventLog.entry_html(idx, date, level, msg, source) if include_html
          entry
        end
        { :idx => @@idx, :log => items }.to_json
      end

      # Adds a block to be notified with an event exactly once when the next
      # event occurs, or with nil after the given timeout if no events occur.
      def self.notify(timeout=60, &block)
        raise 'A block must be given to notify' unless block_given?
        info = nil
        timer = EM::Timer.new(timeout) do
          log "Timed out info is #{info.inspect}" # XXX
          @@watchers.delete info
          info[0].call nil
        end
        info = [ block, timer ]
        log "Added info is #{info.inspect}" # XXX
        @@watchers << info
      end

      # Notifies event watchers that an event occurred, then removes them.
      # Watchers will not be notified if the event loop is not running.
      def self.notify_watchers(entry)
        return unless EM.reactor_running?

        # Copy and clear the list in case any watchers add a new watcher.
        watchers = @@watchers.clone
        @@watchers.clear
        watchers.each do |info|
          log "Calling info #{info.inspect}" # XXX
          info[1].cancel
          info[0].call entry
        end

        nil
      end

      # Returns the index that was given to the last entry added to the log.
      # This may be used for determining if the log has been modified.
      def self.current_index
        @@idx
      end

      # Generates an HTML table row for a single log entry.
      def self.entry_html(idx, date, level, msg, source)
        s = "<tr id=\"entry_#{idx}\" data-idx=\"#{idx}\"><td class=\"log_index\">#{idx}</td>"
        s << "<td class=\"log_date\">#{date}</td>"
        if source.nil?
          s << "<td class=\"event_src\"></td>"
        else
          s << "<td class=\"event_src event_src_#{source}\">#{source}</td>"
        end

        msg &&= msg.text_to_html
        # FIXME: This seems fragile
        if source == 'Zone'
          # TODO: Link to /zones#zone_[processed zone name]
          msg = msg.gsub(/^(.*) added/, "<b>\\1</b> <span class=\"log_good\">added</span>")
          msg = msg.gsub(/^(.*) removed/, "<b>\\1</b> <span class=\"log_error\">removed</span>")
          msg = msg.gsub(/^(.*) entered/, "<b>\\1</b> <span class=\"log_debug\">entered</span>")
          msg = msg.gsub(/^(.*) exited/, "<b>\\1</b> <span class=\"log_warning\">exited</span>")
        elsif source == 'Hue'
          msg = msg.gsub(' added', " <span class=\"log_good\">added</span>")
          msg = msg.gsub(' removed', " <span class=\"log_error\">removed</span>")
        end
        s << "<td class=\"log_msg log_#{EventLog::LEVELS[level || 0]}\">#{msg}</td></tr>\n"

        s
      end

      # TODO: design a better way of adding new routes to the HTTP server,
      # separate controllers from models
      EM.next_tick do
        # TODO: Separate templates from static files
        NL::KNC::ZoneWeb.add_route [ '/log.html', '/log/' ] do |response|
          response.status = 301
          response.headers['Location'] = '/log'
        end

        NL::KNC::ZoneWeb.add_route '/log' do |response|
          lines = EventLog.to_a.map! do |idx, date, level, msg, source|
            EventLog.entry_html(idx, date, level, msg, source)
          end
          event_rows = lines.reverse!.join

          response.content = File.read('wwwdata/log.html').
            gsub('##HOSTNAME##', Socket.gethostname).
            gsub('##LOG_INDEX##', EventLog.current_index.to_s).
            gsub('##EVENT_ROWS##', event_rows)
        end

        # Parameters:
        #     idx=nn - Sends a response immediately if the current log index is
        #              > idx, otherwise waits for up to 10 seconds for a single new
        #              event before sending the response.
        #     html=1 - Includes HTML for a table row in each log entry if html is 1
        #              or if html is unspecified.
        NL::KNC::ZoneWeb.add_route '/log.json' do |response|
          response.content_type 'application/json; charset=utf-8'
          response.headers['Cache-Control'] = 'no-cache'
          response.headers['Pragma'] = 'no-cache'

          # TODO: Add a way to send only new events

          # Include html if html is unspecified or if html is 1
          include_html = !@allvars.include?('html') || @allvars['html'] == '1'

          if @allvars.include?('idx') && @allvars['idx'].to_i >= EventLog.current_index
            log "Waiting to send a log JSON response." # XXX

            EventLog.notify(10) do |entry|
              log "Notified for a delayed log JSON response: #{entry.inspect}" # XXX
              response.content = EventLog.to_json(include_html)
              response.send_response
            end

            [ false, false ] # Don't send the response right away, don't log the request
          else
            log "Not waiting to send a log JSON response." # XXX
            response.content = EventLog.to_json(include_html)

            [ true, false ] # Send the response, but don't log the request
          end
        end
      end
    end
  end
end
