require 'webrick' # for form parsing

module NL
  module KNC
    # This is the HTTP server that serves the KNC API and UI.  It's faster than
    # Sinatra, but the code design is quite poor.
    class ZoneWeb < EM::Connection
      include EM::HttpServer
      include KNCLog
      include HTMLEscape

      # Interacts with do_firmware and sends the result to the client.
      module FirmwareHandler
        # firmware_data should be a hash: { :filename => "client-side firmware file name", :tmpfile => Tempfile.new() }
        def initialize http_response, firmware_data
          @resp = http_response
          @tmpfile = firmware_data[:tmpfile]
          @filename = EscapeUtils.escape_html(firmware_data[:filename])

          NL::KNC::EventLog.warning "Attempting firmware update using #{@filename}.", 'Firmware'

          @resp.send_headers
          @resp.send_body
        end

        def post_init
          @resp.chunk <<-EOF
                        <script type="text/javascript">
                                window.onbeforeunload = function() {
                                        return "Please wait for the firmware update to finish.";
                                }
                        </script>
          EOF
          @resp.chunk '<pre>'
        end

        def receive_data data
          @resp.chunk EscapeUtils.escape_html(data)
          @resp.send_body
        end

        def unbind
          @resp.chunk '</pre>'
          @resp.chunk '<script type="text/javascript">window.onbeforeunload = null;</script>'
          if get_status.exitstatus != 0
            NL::KNC::EventLog.error "Firmware update using #{@filename} failed.", 'Firmware'
            @resp.chunk '<h4>Firmware update failed</h4>'
          else
            NL::KNC::EventLog.good "Firmware update using #{@filename} succeeded.", 'Firmware'
            @resp.chunk '<h4>Firmware update succeeded</h4>'
          end
          @resp.chunk '<div class="subtitle"><a href="/settings">Settings</a></div>'
          @resp.chunk html_footer
          @resp.send_body
          @resp.send_trailer
          @resp.close_connection_after_writing
          @tmpfile.unlink
          @@firmware_active = false
        end
      end

      @@routes = {}
      @@zonecolors = [
        ["#4060b0", "#1030ff"],
        ["#60c070", "#10ff66"],
        ["#c95", "#eb8"],
        ["#80101c", "#c0101c"],
      ];
      @@color_indexer = lambda { c = 0; lambda { |*args| args.length > 0 && c = args[0] - 1; b = c; c = (c + 1) % @@zonecolors.length; b }}.call
      @@firmware_active = false
      @@hostname_active = false

      # Adds a handler for the given exact path(s), which must be a String or
      # an Array of Strings.  Any existing route for the given path(s) will
      # be replaced.  Hard-coded routes cannot be replaced by this method.
      # The handler's first parameter is the HTTP response object (an
      # EM::DelegatedHttpResponse).  If the handler's return value is an
      # array, the first value indicates whether to send the response
      # immediately (true to send, false to defer), and the second value
      # indicates whether to log the response (true to log).  The handler may
      # also set @log_request and @send_response instead.  The handler will
      # be executed in the context of a ZoneWeb object, and can use 'next' to
      # abort its execution early.
      def self.add_route path, handler=nil, &block
        raise "Provide a Proc in handler or a block, but not both." if handler && block_given?
        raise "Pass a Proc in handler or provide a block." unless handler.is_a?(Proc) || block_given?
        raise "The given handler is not a Proc." if handler && !handler.is_a?(Proc)
        raise "The path must be a String or an Array." unless path.is_a?(String) || path.is_a?(Array)

        if path.is_a?(Array)
          path.each do |p|
            raise 'Each element in path Array must be a String.' unless p.is_a?(String)
            raise 'Each element in path Array must start with a slash.' unless p.start_with?('/')
            @@routes[p] = handler || block
          end
        else
          raise "The path must start with a slash." unless path.start_with?('/')
          @@routes[path] = handler || block
        end
      end

      def html_header(title, extrahead='')
        str = <<-HTML
          <html>
          <head>
          <link rel="stylesheet" type="text/css" href="/css/main.css">
          <title>#{title}</title>
          #{extrahead}
          </head>
          <body>
          <div id="content">
        HTML
      end

      def html_footer
        '<div class="copyright">&copy;2015 Nitrogen Logic</div></div></body></html>'
      end

      def parse_headers headers
        parsed = {}
        headers.split("\0").map do |s|
          k, v = s.split(': ', 2)
          parsed[k] = v
        end
        parsed
      end

      # Adds cache-disabling headers to the @response variable's headers.
      def no_cache
        @response.headers['Cache-Control'] = 'no-cache'
        @response.headers['Pragma'] = 'no-cache'
      end

      # Finds the filename of the given uploaded file, or nil if none
      def get_filename post_var
        filename = nil
        if @http_post_content
          @http_post_content.each_line do |line|
            if /^Content-Disposition.*#{post_var}.*filename=/ =~ line
                filename = line.strip.gsub(/.*filename="([^"]*)".*/, '\1')
              filename = URI.decode filename
              break
            end
          end
        end
        filename
      end

      # Sends the given type of image using the given response object (for
      # use by depth/ovh/etc. PNGs).  Returns whether the response should be
      # sent right away.
      def send_image type, response
        response.content_type 'image/png'
        response.headers['Cache-Control'] = 'no-cache'
        response.headers['Pragma'] = 'no-cache'
        response.headers['Refresh'] = (type == :video) ? '5' : '1'

        if NL::KndClient::EMKndClient.connected?
          NL::KndClient::EMKndClient.instance.get_image(type) do |png|
            response.content = png
            response.send_response
          end
          return false
        else
          response.content = NL::KndClient::EMKndClient.png_data type
          return true
        end
      end

      def process_http_request
        Bench.bench "HTTP #{@http_request_method} #{@http_request_uri}" do
          begin
            process_http_request_internal
          rescue => e
            log_e e, "Error processing #{@http_request_method} #{@http_request_uri}"
            @response.status = 500
            @response.content_type 'text/plain; charset=utf-8'
            @response.content = '500 - ' + e.to_s
            @response.send_response
          end
        end
      end

      # Sends a 400 response with the given content and content type
      # (defaults to plain UTF-8 text).
      def send400 content, content_type='text/plain; charset=utf-8'
        @response.status = 400
        @response.content_type content_type
        @response.content = content
      end

      # Sends a 400 response and a plain text error if the given parameter is
      # missing.  Must be called within the original handler given to
      # #add_route, and not in a deferred block.  Returns the value of the
      # given variable, or nil if it was not present in either the query
      # parameters or the POST parameters.
      def get_allvar name, description
        unless @allvars.include?(name)
          send400 "#{description} missing ('#{name}' parameter)."
        end
        @allvars[name]
      end

      # Sends a 400 response and a plain text error if the given parameter is
      # missing.  Must be called within the original handler given to
      # #add_route, and not in a deferred block.  Returns the value of the
      # given variable, or nil if it was not present in the query parameters.
      def get_queryvar name, description
        unless @queryvars.include?(name)
          send400 "#{description} missing ('#{name}' parameter)."
        end
        @queryvars[name]
      end

      # Sends a 400 response and a plain text error if the given parameter is
      # missing.  Must be called within the original handler given to
      # #add_route, and not in a deferred block.  Returns the value of the
      # given variable, or nil if it was not present the POST parameters.
      def get_postvar name, description
        unless @postvars.include?(name)
          send400 "#{description} missing ('#{name}' parameter)."
        end
        @postvars[name]
      end

      # Sends a 405 error and returns false if the current HTTP request
      # method is not included in http_methods.  Example usage in a callback
      # added with add_route:
      #   next unless accept_methods 'GET', 'POST'
      def accept_methods *http_methods
        unless http_methods.include?(@http_request_method)
          @response.status = 405
          @response.content_type 'text/plain; charset=utf-8'
          @response.content = "405 - Method #{@http_request_method} not allowed."
          return false
        end
        return true
      end

      def process_http_request_internal
        if @http_query_string != nil
          queryvars = @http_query_string.urikvp
        end
        if @http_post_content != nil
          if @http_content_type.start_with? 'application/x-www-form-urlencoded'
            postvars = @http_post_content.urikvp
          elsif @http_content_type.start_with? 'multipart/form-data'
            boundary = @http_content_type.sub(/^.*; boundary=(.+)$/, '\1')
            postvars = WEBrick::HTTPUtils::parse_form_data(@http_post_content, boundary)
          end
        end
        queryvars ||= {}
        postvars ||= {}
        allvars = queryvars.merge postvars
        @queryvars = queryvars
        @postvars = postvars
        @allvars = allvars

        @send_response = true
        @log_request = true

        response = EM::DelegatedHttpResponse.new(self)
        response.status = 200
        response.content_type 'text/html; charset=utf-8'
        @response = response

        # TODO: Use a single URI and REST for zone manipulation
        case @http_request_uri
        when '/', '/index.html'
          index_html = File.read('wwwdata/index.html')

          response.headers['Cache-Control'] = 'no-cache'
          response.headers['Pragma'] = 'no-cache'
          response.content = ''
          perspective_html = ''
          zonelist_html = ''
          overhead_html = ''
          side_html = ''
          front_html = ''
          video_html = ''

          # TODO: URL-escape characters for URLs in references below
          @@color_indexer.call 0
          NL::KndClient::EMKndClient.zones.each do |name, zone|
            cidx = @@color_indexer.call + 1
            h_name = h(name)

            zonelist_html << <<-ZONE
                                <div id="list_#{name}" data-zone="#{h_name}" class="list_zone c#{cidx}">
            <div class="zonetitle c#{cidx}">#{zone['name']}
            <a class="rmzone_button" rel="nofollow" href="/rmzone?name=#{h_name}"><span class="ui-icon ui-icon-close" href="/rmzone?name=#{h_name}"></span></a>
              </div>
              <table id="list_table_#{h_name}">
              ZONE

              [['xmin', 'xmax'], ['ymin', 'ymax'], ['zmin', 'zmax'], ['px_xmin', 'px_xmax'],
               ['px_ymin', 'px_ymax'], ['px_zmin', 'px_zmax'], ['xc', 'yc'],
               ['zc', 'sa'], ['bright', 'pop'], ['occupied', 'maxpop']].each do |row|
                 zonelist_html << "<tr>"
                 if(row[0] != nil)
                   zonelist_html << %Q{<th>#{row[0]}:</th><td><span class="#{row[0]}_#{h_name}">#{zone[row[0]]}</span></td>}
                 else
                   zonelist_html << "<th></th><td></td>"
                 end
                 if(row[1] != nil)
                   zonelist_html << %Q{<th>#{row[1]}:</th><td><span class="#{row[1]}_#{h_name}">#{zone[row[1]]}</span></td>}
                 else
                   zonelist_html << "<th></th><td></td>"
                 end
                 zonelist_html << "</tr>"
               end

               zonelist_html << <<-ZONE
                                </table>
                                </div>
               ZONE

               perspective_html << <<-ZONE
                                <div id="perspective_#{h_name}" data-zone="#{h_name}" class="zone perspective_zone
               #{zone['occupied'] ? 'occupied ' : ''}c#{cidx}" style="
               left: #{zone['px_xmin']}px;
                 top: #{zone['px_ymin']}px;
                 width: #{zone['px_xmax'].to_i - zone['px_xmin'].to_i}px;
                 height: #{height = zone['px_ymax'].to_i - zone['px_ymin'].to_i}px;
                 line-height: #{height}px;
                 z-index: #{[10, 1592 - zone['px_zmin'].to_i].max};
                 opacity: #{0.4 + [0.5, 2.0 * zone['pop'].to_f / zone['maxpop'].to_f].min};
                 ">
                                <span class="name_#{h_name}">#{zone['name']}</span>
               </div>
               ZONE

               # TODO: Fix roughly single-pixel shifts between these coordinates and those set by JavaScript
               overhead_html << <<-ZONE
                                <div id="overhead_#{h_name}" data-zone="#{h_name}" class="zone overhead_zone
               #{zone['occupied'] ? 'occupied ' : ''}c#{cidx}" style="
               left: #{(250 + zone['xmin'] * KNC_XPIX / KNC_XMAX).to_i}px;
                 top: #{(zone['zmin'] * KNC_ZPIX / KNC_ZMAX - 10).to_i}px;
                 width: #{((zone['xmax'] - zone['xmin']) * KNC_XPIX / KNC_XMAX + 0.5).to_i}px;
                 height: #{height = ((zone['zmax'] - zone['zmin']) * KNC_ZPIX / KNC_ZMAX + 0.5).to_i}px;
                 line-height: #{height}px;
                 z-index: #{[10, (5000 + zone['ymax']).to_i].max};
                 opacity: #{0.6 + [0.35, 2.0 * zone['pop'].to_f / zone['maxpop'].to_f].min};
                 ">
                                <span class="name_#{h_name}">#{zone['name']}</span>
               </div>
               ZONE

               side_html << <<-ZONE
                                <div id="side_#{h_name}" data-zone="#{h_name}" class="zone side_zone
               #{zone['occupied'] ? 'occupied ' : ''}c#{cidx}" style="
               left: #{(zone['zmin'] * KNC_ZPIX / KNC_ZMAX).to_i}px;
                 top: #{(240 - zone['ymax'] * KNC_YPIX / KNC_YMAX).to_i}px;
                 width: #{((zone['zmax'] - zone['zmin']) * KNC_ZPIX / KNC_ZMAX + 0.5).to_i}px;
                 height: #{height = ((zone['ymax'] - zone['ymin']) * KNC_YPIX / KNC_YMAX + 0.5).to_i}px;
                 line-height: #{height}px;
                 z-index: #{[10, (5000 - zone['xmin']).to_i].max};
                 opacity: #{0.6 + [0.35, 2.0 * zone['pop'].to_f / zone['maxpop'].to_f].min};
                 ">
                                <span class="name_#{h_name}">#{zone['name']}</span>
               </div>
               ZONE

               front_html << <<-ZONE
                                <div id="front_#{h_name}" data-zone="#{h_name}" class="zone front_zone
               #{zone['occupied'] ? 'occupied ' : ''}c#{cidx}" style="
               left: #{(250 - zone['xmax'] * KNC_XPIX / KNC_XMAX).to_i}px;
                 top: #{(240 - zone['ymax'] * KNC_YPIX / KNC_YMAX).to_i}px;
                 width: #{((zone['xmax'] - zone['xmin']) * KNC_XPIX / KNC_XMAX + 0.5).to_i}px;
                 height: #{height = ((zone['ymax'] - zone['ymin']) * KNC_YPIX / KNC_YMAX + 0.5).to_i}px;
                 line-height: #{height}px;
                 z-index: #{[10, 1592 - zone['px_zmin'].to_i].max};
                 opacity: #{0.6 + [0.35, 2.0 * zone['pop'].to_f / zone['maxpop'].to_f].min};
                 ">
                                <span class="name_#{h_name}">#{zone['name']}</span>
               </div>
               ZONE

               bright = zone['bright'] || 0
               video_html << <<-ZONE
                                <div id="video_#{h_name}" data-zone="#{h_name}" class="zone video_zone
               #{zone['occupied'] ? 'occupied ' : ''}c#{cidx}" style="
               left: #{zone['px_xmin']}px;
                 top: #{zone['px_ymin']}px;
                 width: #{zone['px_xmax'].to_i - zone['px_xmin'].to_i}px;
                 height: #{height = zone['px_ymax'].to_i - zone['px_ymin'].to_i}px;
                 line-height: #{height}px;
                 z-index: #{[10, 1592 - zone['px_zmin'].to_i].max};
                 opacity: #{0.4 + [0.5, 2.0 * bright.to_f / 1000.0].min};
                 ">
                                <span class="name_#{h_name}">#{zone['name']}</span>
               </div>
               ZONE
          end

          response.content = index_html.gsub('##ZONELIST##', zonelist_html).
            gsub('##ZONEDIVS##', perspective_html).
            gsub('##OVHDIVS##', overhead_html).
            gsub('##SIDEDIVS##', side_html).
            gsub('##FRONTDIVS##', front_html).
            gsub('##VIDEODIVS##', video_html). # FIXME: depth+video registration
            gsub('##HOSTNAME##', Socket.gethostname).
            gsub('##BUILDNO##', EscapeUtils.escape_html(NL::KNC::BUILD))

        when '/index_webgl.html'
          response.content = File.read('wwwdata/index_webgl.html').gsub('##ZONELIST##', '').
            gsub('##ZONEDIVS##', '').
            gsub('##OVHDIVS##', '').
            gsub('##SIDEDIVS##', '').
            gsub('##FRONTDIVS##', '').
            gsub('##VIDEODIVS##', ''). # FIXME: depth+video registration
            gsub('##HOSTNAME##', Socket.gethostname).
            gsub('##BUILDNO##', EscapeUtils.escape_html(NL::KNC::BUILD))

        when '/depth16.png'
          @log_request = false
          @send_response = send_image :depth, response

        when '/depth8.png'
          @log_request = false
          @send_response = send_image :linear, response

        when '/overhead.png'
          @log_request = false
          @send_response = send_image :ovh, response

        when '/side.png'
          @log_request = false
          @send_response = send_image :side, response

        when '/front.png'
          @log_request = false
          @send_response = send_image :front, response

        when '/video.png'
          @log_request = false
          @send_response = send_image :video, response

        when '/blank.png'
          @log_request = false
          response.content_type 'image/png'
          response.content = NL::KndClient::EMKndClient.blank_image

        when '/bench'
          Bench.toggle_bench
          response.content = html_header('Depth Controller Profiling')

          response.content << "<h3>Profiling is now #{Bench.enabled? ? 'enabled' : 'disabled'}.</h3>\n"
          if Bench.enabled?
            response.content << "<h4>Reload to see results.</h4>\n"
          else
            elapsed = Bench.elapsed
            response.content << "<h4>Results (#{NL::KNC::EventLog.sectostr(elapsed)} elapsed):</h4>\n"
            response.content << "<table id=\"benchresults\" class=\"knc_table\"><tr>\n"
            [ "Task", "Count", "Total Time", "Average Time", "Overall" ].each do |v|
              response.content << "<th>#{v}</th>"
            end
            response.content << "</tr>\n"

            results = Bench.get_benchresults
            results = results.sort_by { |label, result| -result[:time] }
            results.each do |k|
              response.content << "<tr><td>#{k[0]}</td><td>#{k[1][:count]}</td>"
              response.content << "<td>#{k[1][:time].round(7)}s</td>"
              response.content << "<td>#{(k[1][:time] * 1000 / k[1][:count]).round(4)}ms</td>"
              response.content << "<td>#{(k[1][:time] * 100 / elapsed).round(2)}%</td></tr>\n"
            end
            response.content << "</table>\n"
          end

          response.content << html_footer

        when '/build'
          response.content_type 'text/plain; charset=utf-8'
          response.content = NL::KNC::BUILD
          @log_request = @http_request_method != 'POST'

          # TODO: Separate templates from static files
        when '/settings.html', '/settings/'
          response.status = 301
          response.headers['Location'] = '/settings'

        when '/settings'
          response.content = File.read('wwwdata/settings.html').
            gsub('##HOSTNAME##', Socket.gethostname).
            gsub('##BRIGHT_RATE##', NL::KNC::CONFIG[:bright][:rate].to_s).
            gsub('##XAP_ENABLED##', NL::KNC::CONFIG[:xap][:enabled] ? 'checked' : '').
            gsub('##XAP_UID##', NL::KNC::CONFIG[:xap][:uid]).
            gsub('##HUE_ENABLED##', NL::KNC::CONFIG[:hue][:enabled] ? 'checked' : '').
            gsub('##HUE_DISCO##', $hue_ok ? NL::KNC::KncHue.disco_html : '<h1>Error loading Hue support</h1>').
            gsub('##HUE_BRIDGES##', $hue_ok ? NL::KNC::KncHue.bridges_html : '<h1>Error loading Hue bridges</h1>').
            gsub('##BUILDNO##', EscapeUtils.escape_html(NL::KNC::BUILD))

        when '/settings/brightness'
          begin
            allvars.each do |k, v|
              case k
              when 'rate'
                ZoneBright.set_rate v.to_i
              end
            end

            if allvars['submit'] =~ /Brightness/i
              unless allvars.include? 'noredir'
                response.status = 302
                response.headers['Location'] = '/settings'
              end
            else
              response.content_type 'application/json; charset=utf-8'
              response.headers['Cache-Control'] = 'no-cache'
              response.headers['Pragma'] = 'no-cache'
              response.content = NL::KNC::CONFIG[:bright] ? NL::KNC::CONFIG[:bright].merge({'vars' => allvars}).to_json : '{}'
              @log_request = false
            end
          rescue Exception => e
            response.status = 500
            log_e e, @http_request_uri
          end

        when '/settings/xap'
          begin
            raise 'xAP support unavailable -- contact technical support.' unless $xap_ok

            allvars.each do |k, v|
              case k
              when 'enabled'
                v =~ /^(?:true|on|1)$/ ? NL::KNC::KncXap.start_kncxap : NL::KNC::KncXap.stop_kncxap
              when 'uid'
                set_xapuid v
              end
            end

            if allvars['submit'] =~ /xAP/i
              allvars.include?('enabled') ? NL::KNC::KncXap.start_kncxap : NL::KNC::KncXap.stop_kncxap
              unless allvars.include? 'noredir'
                response.status = 302
                response.headers['Location'] = '/settings'
              end
            else
              response.content_type 'application/json; charset=utf-8'
              response.headers['Cache-Control'] = 'no-cache'
              response.headers['Pragma'] = 'no-cache'
              response.content = NL::KNC::CONFIG[:xap] ? NL::KNC::CONFIG[:xap].merge({'vars' => allvars}).to_json : '{}'
              @log_request = false
            end
          rescue Exception => e
            # TODO: Move this outside the big case/when
            response.status = 500
            response.content_type 'text/plain; charset=utf-8'
            response.content = "Error - #{e}"
            log_e e, @http_request_uri
          end

        when '/settings/xap/endpoints'
          begin
            raise 'xAP support unavailable -- contact technical support.' unless $xap_ok

            response.content_type 'application/json; charset=utf-8'
            response.headers['Cache-Control'] = 'no-cache'
            response.headers['Pragma'] = 'no-cache'

            dev = NL::KNC::KncXap.device
            if dev
              response.content = dev.to_json
            else
              response.content = "{}"
            end

            @log_request = false
          rescue Exception => e
            response.status = 500
            response.content_type 'text/plain; charset=utf-8'
            response.content = "Error - #{e}"
            log_e e, @http_request_uri
          end

        when '/hostname'
          if postvars.empty?
            response.status = 302
            response.headers['Location'] = '/settings'
          else
            resp_text = html_header('Set Hostname')
            resp_text << '<h3>Set Hostname</h3>'

            host = postvars['hostname'].strip.downcase
            if @@hostname_active
              response.status = 500
              resp_text << '<h4>Error setting hostname.  A hostname change is already in progress.</h4>'
              resp_text << html_footer
              response.content = resp_text
            elsif host =~ /[^[:alnum:]-]/
              response.status = 500
              resp_text << '<h4>Invalid Hostname</h4>'
              resp_text << "<p>&ldquo;#{EscapeUtils.escape_html(host)}&rdquo; is not a valid hostname.  "
              resp_text << "Only letters, numbers, and hyphens are permitted.</p>"
              resp_text << html_footer
              response.content = resp_text
            else
              @@hostname_active = true
              @send_response = false
              response.chunk resp_text
              Sudo.sudo("/opt/nitrogenlogic/util/set_hostname.sh #{host} 2>&1") do |text, status|
                if status.success?
                  NL::KNC::EventLog.normal "Set hostname to #{host}", 'System'
                  response.chunk '<h4>Hostname set successfully</h4>'
                  response.chunk "<p>Hostname set to #{host}.local: #{EscapeUtils.escape_html(text.strip)}</p>"
                  response.chunk %Q{<p><a href="//#{host}.local:#{NL::KNC::KNC_PORT}/settings">Click here to go to the new hostname.</a></p>}
                else
                  NL::KNC::EventLog.error "Error setting hostname to #{host}", 'System'
                  response.status = 500
                  response.chunk '<h4>Error setting hostname</h4>'
                  response.chunk "<p>#{EscapeUtils.escape_html(text)}</p>"
                end

                response.chunk html_footer
                response.send_body
                response.send_trailer
                response.close_connection_after_writing
                @@hostname_active = false
              end
            end
          end

        when '/shutdown.html'
          response.status = 301
          response.headers['Location'] = '/settings'

        when '/shutdown'
          if @http_request_method == 'GET' || postvars.empty?
            response.content = File.read('wwwdata/shutdown.html')
          else
            @send_response = false
            Sudo.sudo("/opt/nitrogenlogic/util/shutdown.sh 2>&1") do |text, status|
              if status.success?
                response.content = File.read('wwwdata/shutdown_done.html')
              else
                response.status = 500
                response.content = html_header('Error - Prepare for Transport')
                response.content << '<h3>Prepare for Transport</h3>'
                response.content << '<h4>Error shutting down</h4>'
                response.content << "<p>#{EscapeUtils.escape_html(text)}</p>"
                response.content << html_footer
              end
              response.send_response
            end
          end

        when '/firmware'
          bytes = allvars['firmware_file'] && allvars['firmware_file'].length || 0
          filename = ''
          if @http_post_content
            @http_post_content.each_line do |line|
              if /^Content-Disposition.*firmware_file.*filename=/ =~ line
                filename = line.strip.gsub(/.*filename="([^"]*)".*/, '\1')
                filename = URI.decode filename
                break
              end
            end
          end
          resp_text = html_header('Firmware Upload')
          resp_text << "<h3>Firmware Upload</h3>"
          resp_text << "<h4>Received \"#{EscapeUtils.escape_html(filename)}\": #{bytes} bytes</h4>"
          if allvars.has_key? 'debug'
            resp_text << '<pre><code>'
            resp_text << allvars.to_s
            resp_text << EscapeUtils.escape_html(%Q{\n\n#{@http_headers.split("\0").join("\n")}})
            if @http_post_content != nil
              resp_text << EscapeUtils.escape_html(%Q{\n\n#{@http_content_type}\n\n#{@http_post_content}})
            end
            resp_text << '</code></pre>'
          end
          if @@firmware_active
            resp_text << '<h4>A firmware update is already in progress.</h4>'
            resp_text << '<div class="subtitle"><a href="/settings">Settings</a></div>'
            resp_text << html_footer
            response.status = 500
            response.content = resp_text
          elsif bytes <= 0
            resp_text << '<h4>Firmware size must be greater than 0 bytes.</h4>'
            resp_text << '<div class="subtitle"><a href="/settings">Settings</a></div>'
            resp_text << html_footer
            response.status = 500
            response.content = resp_text
          else
            # TODO: Add a verification step with anti-CSRF nonce to ensure the
            # firmware update is intended
            # TODO: Limit length of filename?
            @@firmware_active = true
            @send_response = false
            response.chunk resp_text

            # It would be safer to ignore the client-specified filename here, but
            # it may be useful to preserve some of the filename for identifying
            # problems related to a specific firmware upload.
            fwfile = Tempfile.new(
              ["client_firmware_#{filename.gsub(/[^A-Za-z0-9]/, '')}", ".nlfw"])
            fwfile.write(allvars['firmware_file'])
            fwfile.seek(0)
            fwfile.close

            # TODO: Use Sudo
            EM.popen("bash -c 'do_firmware #{fwfile.path} 2>&1 | grep --line-buffered -iv \"cat: write error: Broken pipe\"; exit ${PIPESTATUS[0]}'", FirmwareHandler, response, { :tmpfile => fwfile, :filename => filename })
          end
        else
          if @@routes.include? @http_request_uri
            result = instance_exec(response, &@@routes[@http_request_uri])
            if result.is_a?(Array)
              @send_response, @log_request = *result
            end
          else
            response.headers['Cache-Control'] = 'max-age=60, must-revalidate'
            # TODO: Use an absolute or configurable path
            path = File.expand_path "./wwwdata/#{@http_request_uri}"
            datapath = File.expand_path './wwwdata/'
            if path.start_with?(datapath) and File.exists?(path) and not File.directory?(path)
              f = File.new(path, "rb")
              response.content = f.read
              f.close
              ext = File.extname(path)
              case ext
              when '.html'
                ctype = 'text/html; charset=utf-8'
              when '.css'
                ctype = 'text/css; charset=utf-8'
              when '.js'
                ctype = 'text/javascript; charset=utf-8'
              when '.png'
                ctype = 'image/png'
              when '.gif'
                ctype = 'image/gif'
              when '.jpg', '.jpeg'
                ctype = 'image/jpeg'
              when '.txt'
                ctype = 'text/plain; charset=utf-8'
              else
                ctype = 'application/octet-stream'
              end
              response.content_type ctype
            else
              response.status = 404
              response.content_type 'text/plain; charset=utf-8'
              response.content = "404 - Not found: #{@http_request_uri}"
            end
          end
        end

        response.send_response if @send_response

        if @log_request
          msg = "#{Socket.unpack_sockaddr_in(get_peername)} - #{response.status} #{@http_request_method} "
          msg += "#{@http_request_uri}#{@send_response ? '' : ' (deferred)'}\n"
          log msg
        end
      end
    end
  end
end
