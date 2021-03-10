# Zone-related definitions and web handlers for the Depth Camera Controller.
# (C)2014 Mike Bourgeous

require 'eventmachine'

module NL
  module KNC
    module KncZones
      extend KNCLog

      EM.next_tick do
        log "Setting up zone-related route handlers"

        NL::KNC::ZoneWeb.add_route '/zones.knd' do |response|
          response.content_type 'text/plain; charset=utf-8'
          if File.file?(NL::KNC::KND_ZONES) && File.readable?(NL::KNC::KND_ZONES)
            response.content = File.read($knd_zones)
            response.headers['Content-Disposition'] = 'attachment; filename=zones.knd'
          else
            response.status = 404
            response.content = "404 - No zone file was found.  Please connect a depth camera."
          end
        end

        NL::KNC::ZoneWeb.add_route '/zones.json' do |response|
          resp = {
            'version' => NL::KndClient::Zone::ZONE_VERSION,
            'connected' => NL::KndClient::EMKndClient.connected?,
            'fps' => NL::KndClient::EMKndClient.fps,
            'occupied' => NL::KndClient::EMKndClient.occupied,
            'zones' => NL::KndClient::EMKndClient.zones
          }
          response.content_type 'application/json; charset=utf-8'
          response.content = resp.to_json
          response.headers['Cache-Control'] = 'no-cache'
          response.headers['Pragma'] = 'no-cache'
          response.headers['Refresh'] = '1'

          req_headers = parse_headers @http_headers
          host = req_headers['Host']
          referrer = req_headers['Referer'] || ''
          if @queryvars['dl'] && referrer.include?(host) && (referrer.end_with?("#{host}/") || referrer.end_with?("#{host}/index.html"))
            response.headers['Content-Disposition'] = 'attachment; filename=zones.json'
          else
            @log_request = false
          end
        end

        NL::KNC::ZoneWeb.add_route '/uploadzones' do |response|
          bytes = @allvars['zone_file'] && @allvars['zone_file'].length || 0
          filename = get_filename('zone_file') || ''
          data = @allvars['zone_file']
          resp_text = html_header('Zone Upload')
          resp_text << '<h3>Zone Upload</h3>'
          resp_text << "<h4>Received \"#{h(filename)}\": #{bytes} bytes</h4>"
          debug = @allvars.has_key? 'debug'

          unless bytes > 0
            resp_text << '<h4>Zone file size must be greater than 0 bytes.</h4>'
            resp_text << html_footer
            response.content = resp_text
          else
            json = begin
                     JSON.parse data
                   rescue
                     nil
                   end

            if !json || !json['zones'] || !json['zones'].is_a?(Hash)
              resp_text << '<h4>This does not appear to be a valid zone file.</h4>'
              resp_text << html_footer
              response.content = resp_text
            elsif !NL::KndClient::EMKndClient.connected?
              resp_text << "<h3>The depth camera is not connected.</h3>"
              resp_text << html_footer
              response.content = resp_text
            else
              @send_response = false
              final_result = true
              final_message = '<dl>'
              error_messages = []

              zones = []
              json['zones'].each_pair do |k, v|
                v['version'] = json['version'] unless json['version'].nil?
                zones << NL::KndClient::Zone.new(v)
              end

              # Proc called for each entry in the zone list
              add_proc = proc { |str, res, msg|
                final_result &&= res
                final_message << "<dt>#{h str}</dt><dd>#{h msg}</dd>\n"
                if !res
                  error_messages << "#{str}: #{msg}"
                end
                if zones.length > 0
                  z = zones.shift
                  NL::KndClient::EMKndClient.instance.add_zone z do |zres, zmsg|
                    add_proc.call "Add zone #{h z['name']}", zres, zmsg
                  end
                else
                  final_message << '</dl>'
                  if final_result
                    resp_text << '<h4>Success</h4>'
                  else
                    resp_text << '<h4>Failure</h4>'
                    resp_text << "<p>#{error_messages.join('</p><p>')}</p>"
                  end
                  resp_text << final_message if debug
                  resp_text << html_footer
                  response.headers['Refresh'] = '1; url=/'
                  response.content = resp_text
                  response.send_response
                end
              }

              NL::KndClient::EMKndClient.instance.clear_zones do |result, message|
                add_proc.call "Clear zones", result, message
              end
            end
          end
        end

        NL::KNC::ZoneWeb.add_route '/clearzones' do |response|
          response.content = html_header('Remove all zones')
          response.headers['Refresh'] = '3; url=/'
          if NL::KndClient::EMKndClient.connected?
            NL::KndClient::EMKndClient.instance.clear_zones do |result, message|
              response.headers['Refresh'] = '1; url=/' if result
              response.status = 400 unless result
              response.content << (result ? "<h3>Success</h3>" : "<h3>Error</h3>")
              response.content << "<h4>#{EscapeUtils.escape_html message}</h4></body></html>"
              response.send_response
            end
            @send_response = false
          else
            response.content << "<h3>Depth camera is not connected.</h3></body></html>"
            response.status = 503
          end
        end

        NL::KNC::ZoneWeb.add_route '/addzone' do |response|
          # TODO: Anti-CSRF (could Accept: header be used to prevent <img> use?)
          # TODO: Make calls to these asynchronous so no HTML is
          # needed (return JSON maybe)
          response.content = html_header('Add new zone');
          response.headers['Refresh'] = '3; url=/'
          if NL::KndClient::EMKndClient.connected?
            zone = NL::KndClient::Zone.new(@allvars)
            NL::KndClient::EMKndClient.instance.add_zone zone do |result, message|
              response.headers['Refresh'] = '1; url=/' if result
              response.status = 400 unless result
              response.content << (result ? "<h3>Success</h3>" : "<h3>Error</h3>")
              response.content << "<h4>#{EscapeUtils.escape_html message}</h4></body></html>"
              response.send_response
            end
            @send_response = false
          else
            response.content << "<h3>Depth camera is not connected.</h3></body></html>"
            response.status = 503
          end
        end

        NL::KNC::ZoneWeb.add_route '/setzone' do |response|
          # TODO: Anti-CSRF
          response.content = html_header('Set zone parameters')
          if NL::KndClient::EMKndClient.connected?
            zone = NL::KndClient::Zone.new(@allvars)
            NL::KndClient::EMKndClient.instance.set_zone zone do |result, message|
              response.status = 400 unless result
              response.content << (result ? "<h3>Success</h3>" : "<h3>Error</h3>\n")
              response.content << "<h4>#{EscapeUtils.escape_html message}</h4></body></html>"
              response.send_response
            end
            @send_response = false
          else
            response.content << "<h3>Depth camera is not connected.</h3></body></html>"
            response.status = 503
          end
        end

        NL::KNC::ZoneWeb.add_route '/rmzone' do |response|
          # TODO: Anti-CSRF
          response.content = html_header('Remove zone')
          response.headers['Refresh'] = '3; url=/'
          if NL::KndClient::EMKndClient.connected?
            NL::KndClient::EMKndClient.instance.remove_zone @allvars['name'] do |result, message|
              response.headers['Refresh'] = '1; url=/' if result
              response.status = 400 unless result
              response.content << (result ? "<h3>Success</h3>" : "<h3>Error</h3>")
              response.content << "<h4>#{EscapeUtils.escape_html message}</h4></body></html>"
              response.send_response
            end
            @send_response = false
          else
            response.content << "<h3>Depth camera is not connected.</h3></body></html>"
            response.status = 503
          end
        end

        NL::KNC::ZoneWeb.add_route ['/zones.html', '/zones/'] do |response|
          response.status = 301
          response.headers['Location'] = '/zones'
        end

        # TODO: Separate templates from static files
        NL::KNC::ZoneWeb.add_route '/zones' do |response|
          zone_html = ''
          response.content = File.read('wwwdata/zones.html').
            gsub('##HOSTNAME##', Socket.gethostname)
        end
      end
    end
  end
end
