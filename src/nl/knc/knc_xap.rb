# xAP support for KNC (Kinematic Network Controller - front-end daemon for
# Nitrogen Logic Depth Camera Controllers)
# (C)2012 Mike Bourgeous

require 'json'

require 'xap_ruby'

module NL
  module KNC
    module KncXap
      include KNCLog
      extend KNCLog

      # An xAP Basic Status and Control model of the depth controller.
      class KncXapDevice < Xap::Schema::XapBscDevice
        include KNCLog

        attr_accessor :callback

        def initialize uid
          super Xap::XapAddress.new('n2l', 'depth', Socket.gethostname.gsub(/[^a-z0-9\.-_]+/, '-').gsub(/-+/, '.')),
            uid || Xap.random_uid,
            [ { :endpoint => '__Status', :uid => 254, :State => false, :Level => [0, 30] } ]

          @last_fps = Time.now
          @enable_fps = true
          @callback = proc { |type, param|
            begin
              case type
              when :add # Zone events
                log "Adding xAP endpoint for zone #{param['name']}"

                ep = { :endpoint => param['name'], :State => param['occupied'] }
                ep[:Level] = [ param['bright'] , 1000 ] if param.include? 'bright'
                add_endpoint ep
              when :del
                log "Removing xAP endpoint for zone #{param['name']}"
                remove_endpoint param['name']

                # Renumber endpoints to avoid UIDs changing after restarting
                @uids.clear
                @uids[254] = @endpoints['__status']
                @endpoints.each do |k, v|
                  if k != '__status'
                    v[:uid] = find_free_uid
                    @uids[v[:uid]] = v
                  end
                end
                announce_endpoints
              when :change
                # TODO: Other parameters: surface area, xc/yc/zc, etc.
                if param['occupied'] != get_state(param['name'])
                  set_state param['name'], param['occupied']
                end
                if param.include? 'bright'
                  if [ param['bright'] , 1000 ] != get_level(param['name'])
                    set_level param['name'], [ param['bright'] , 1000 ]
                  end
                elsif get_level(param['name'])
                  set_level param['name'], nil
                end

              when :online # Status events
                set_state '__Status', param

                # Delete all endpoints when going offline (they will be
                # re-added when coming back online)
                unless param
                  eps = @endpoints.clone
                  eps.delete '__status'

                  eps.each do |k, v|
                    remove_endpoint v
                  end
                end
              when :fps
                fps = get_level('__Status')[0]
                if fps != param && Time.now - @last_fps > 1 && @enable_fps
                  @last_fps = Time.now
                  set_level '__Status', param
                end
              end
            rescue Exception => e
              log "Error updating xAP for #{type.inspect} event: #{e}\n\t#{e.backtrace.join("\n\t")}"
            end
          }
        end

        # Sets the xAP handler that owns this device.  Starts/stops the
        # periodic announcement timer.
        def handler= handler
          super handler

          if handler
            @announce_timer = EM.add_periodic_timer(10) do
              announce_endpoints
            end
          else
            @announce_timer.cancel if @announce_timer
            @announce_timer = nil
          end
        end

        # Gets the uid for the given zone (either a Zone or a String).
        def get_uid zone
          zone = zone['name'] if zone.is_a? Zone
          super zone
        end

        # Returns a JSON representation of this device's endpoints.
        def to_json
          eps = @endpoints.clone
          eps.each do |k, v|
            ep = v.clone

            ep[:uid] = sprintf("%02X", ep[:uid])
            ep[:endpoint] = "#{self.address.to_s}:#{ep[:endpoint]}"

            case ep[:State]
            when true
              ep[:State] = 'ON'
            when false
              ep[:State] = 'OFF'
            end

            eps[k] = ep
          end
          eps.to_json
        end

        # Sets the device instance name in this virtual device's xAP address.
        # This is set from the host name in KNC.  All endpoints will be
        # reannounced at the new address.
        def set_instance hostname
          set_address Xap::XapAddress.new(
            'n2l',
            'depth',
            hostname.gsub(/[^a-z0-9\.-_]+/, '-').gsub(/-+/, '.'))
        end
      end

      @@device = nil
      @@hntimer = nil

      NL::KNC::CONFIG[:xap] ||= {}
      NL::KNC::CONFIG[:xap][:enabled] ||= false
      NL::KNC::CONFIG[:xap][:uid] ||= Xap.random_uid[2, 4]

      # Starts KNC support for the xAP protocol and starts the xAP event
      # manager.
      def self.start_kncxap
        log "Starting xAP"
        NL::KNC::EventLog.normal "Starting xAP.", 'xAP'
        NL::KNC::CONFIG[:xap][:enabled] = true
        begin
          start_xap_internal "FF#{NL::KNC::CONFIG[:xap][:uid]}00"
        rescue StandardError => e
          if e.message.include? 'uid'
            NL::KNC::CONFIG[:xap][:uid] = Xap.random_uid[2, 4]
            start_xap_internal "FF#{NL::KNC::CONFIG[:xap][:uid]}00"
          else
            raise
          end
        end
        NL::KndClient::EMKndClient.instance.add_cb(device.callback) if NL::KndClient::EMKndClient.instance
      end

      def self.stop_kncxap
        log "Stopping xAP"
        NL::KNC::EventLog.normal "Stopping xAP.", 'xAP'
        NL::KNC::CONFIG[:xap][:enabled] = false
        NL::KndClient::EMKndClient.instance.remove_cb(device.callback) if KncXap.device && NL::KndClient::EMKndClient.instance
        stop_xap_internal
      end

      def self.set_xapuid uid
        if uid.downcase == 'rand' || uid.downcase == 'random'
          uid = Xap.random_uid[2, 4]
        else
          uid = uid.upcase
        end

        log "Changing xAP UID to #{uid}"

        # FIXME: this returns 500 instead of 400
        if uid.length != 4 || uid =~ /(?:^(?:00|FF)|(?:00|FF)$)/i || !(uid =~ /[0-9A-Fa-f]{4}/)
          raise 'UID must be four hexadecimal digits, each pair in the range 01-FE.'
        end

        KncXap.device.uid = "FF#{uid}00" if KncXap.device

        NL::KNC::CONFIG[:xap] ||= {}
        NL::KNC::CONFIG[:xap][:uid] = uid

        NL::KNC::EventLog.normal "Changed xAP UID to #{uid}.", 'xAP'
      end


      def self.start_xap_internal uid
        Xap.start_xap
        unless @@device
          device = KncXapDevice.new uid
          Xap.add_device device
          @@device = device
          device = nil
        end

        unless @@hntimer
          hostname = Socket.gethostname
          timer = EM.add_periodic_timer(5) {
            newhost = Socket.gethostname
            if hostname != newhost && @@device
              log "Hostname changed from #{hostname} to #{newhost}"
              @@device.set_instance newhost
              hostname = newhost
            end
          }
        end
      end

      def self.stop_xap_internal
        Xap.remove_device @@device if @@device
        @@device = nil
        Xap.stop_xap if Xap.xap_running?

        @@hntimer.cancel if @@hntimer
        @@hntimer = nil
      end

      # Returns the KncXapDevice created by start_kncxap.
      def self.device
        @@device
      end
    end
  end
end
