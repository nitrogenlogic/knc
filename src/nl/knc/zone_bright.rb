# (C)2012 Mike Bourgeous
module NL
  module KNC
    # Periodic video brightness for each zone.
    # TODO: Merge relevant parts into EMKndClient
    module ZoneBright
      include KNCLog
      extend KNCLog

      @@timer = nil

      NL::KNC::CONFIG[:bright] ||= {}
      NL::KNC::CONFIG[:bright][:rate] ||= 1000

      def self.start_bright
        log "Starting Brightness"
        start_timer
      end

      def self.stop_bright
        log "Stopping Brightness"

        stop_timer

        EM::KndClient::EMKndClient.zones.each do |z|
          z.delete 'bright'
        end
      end

      def self.set_rate interval
        NL::KNC::CONFIG[:bright][:rate] = [ 1000, interval ].max
        self.stop_timer
        self.start_timer
      end

      private

      def self.start_timer
        @@timer = EM.add_periodic_timer(NL::KNC::CONFIG[:bright][:rate] / 1000.0) do
          begin
            if NL::KndClient::EMKndClient.connected? && NL::KndClient::EMKndClient.instance
              NL::KndClient::EMKndClient.instance.request_brightness do |result, message|
                log "Error requesting brightness: #{message}" unless result
              end
            end
          rescue => e
            log_e e, "Error requesting brightness"
          end
        end
      end

      def self.stop_timer
        if @@timer
          @@timer.cancel
          @@timer = nil
        end
      end
    end
  end
end
