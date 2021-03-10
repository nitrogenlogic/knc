require 'socket'
require 'eventmachine'
require 'evma_httpserver'

require 'nl/fast_png'
require 'nl/knd_client'

require_relative 'knc/version'
require_relative 'knc/knc_log'
require_relative 'knc/bench'
require_relative 'knc/string_extensions'
require_relative 'knc/hash_extensions'
require_relative 'knc/knc_conf'
require_relative 'knc/sudo'
require_relative 'knc/ring_buffer'
require_relative 'knc/event_log'
require_relative 'knc/html_escape'

module NL
  # Initially based on:
  # https://github.com/eventmachine/eventmachine/wiki/Code-Snippets
  # client_3
  module KNC
    include KNCLog
    extend KNCLog

    KNC_PORT = ENV['KNC_PORT']&.to_i.yield_self { |v| (v && v > 0) ? v : 8089 }

    CONFIG_DIR = ENV['KNC_SAVEDIR'].yield_self { |v| (v && File.directory?(v)) ? v : '/var/lib/knc' }
    CONFIG_FILENAME = ENV['KNC_CONFFILE'] || File.join(CONFIG_DIR, 'config.json')
    CONFIG = KncConf.new(CONFIG_FILENAME)

    LOG_FILENAME = ENV['KNC_LOGFILE'] || File.join(CONFIG_DIR, 'eventlog.json')
    EVENT_LOG = KncConf.new(LOG_FILENAME)

    RULES_FILENAME = ENV['KNC_RULESFILE'] || File.join(CONFIG_DIR, 'rules.json')
    RULES = KncConf.new(RULES_FILENAME)

    KND_DIR = ENV['KND_SAVEDIR'].yield_self { |v| (v && File.directory?(v)) ? v : '/var/lib/knd' }
    KND_ZONES = File.join(KND_DIR, 'zones.knd')

    BUILD = (File.readable?('/etc/knc/build') && File.file?('/etc/knc/build')) ? File.read('/etc/knc/build').strip : '[unknown build]'

    def self.start_knc hostname=nil
      log "Starting KNC"

      Signal.trap "EXIT" do
        NL::KNC::EventLog.normal "Stopping Depth Camera Controller web interface #{NL::KNC::BUILD}.", 'System'
        log "Saving configuration before exiting."
        NL::KNC::CONFIG.save

        log "Saving event log before exiting."
        NL::KNC::EVENT_LOG[:log] = NL::KNC::EventLog.store_log
        NL::KNC::EVENT_LOG.save

        log "Saving automation rules before exiting."
        NL::KNC::RULES[:rules] = KncAction.store_rules
        NL::KNC::RULES.save

        exit
      end

      begin
        log "Loading event log"
        NL::KNC::EventLog.init_log NL::KNC::EVENT_LOG[:log]
        log "Loaded #{NL::KNC::EventLog.current_index} event log events." if NL::KNC::EventLog.current_index > 0
      rescue => e
        log_e e, "Unable to load the saved event log."
      end

      begin
        if NL::KNC::RULES[:rules]
          log "Loading automation rules"
          KncAction.load_rules NL::KNC::RULES[:rules]
          log "Loaded #{KncAction.rules.count} automation rules."
        end
      rescue => e
        log_e e, "Unable to load the saved automation rules."
      end

      log_index = NL::KNC::EventLog.current_index
      NL::KNC::EventLog.normal "Starting Depth Camera Controller web interface #{NL::KNC::BUILD}.", 'System'

      # TODO: Move this into xAP and NL::KNC::EventLog modules
      NL::KndClient::EMKndClient.on_connect do |online|
        if NL::KndClient::EMKndClient.instance
          if online
            NL::KndClient::EMKndClient.instance.add_cb NL::KNC::EventLog.knc_handler
            NL::KndClient::EMKndClient.instance.add_cb NL::KNC::KncXap.device.callback if $xap_ok && KncXap.device
            NL::KndClient::EMKndClient.instance.add_cb NL::KNC::KncAction::KncZoneTriggers.trigger_proxy
          else
            NL::KndClient::EMKndClient.instance.remove_cb NL::KNC::EventLog.knc_handler
            NL::KndClient::EMKndClient.instance.remove_cb NL::KNC::KncXap.device.callback if $xap_ok && KncXap.device
            NL::KndClient::EMKndClient.instance.remove_cb NL::KNC::KncAction::KncZoneTriggers.trigger_proxy
          end
        end
      end

      EM.run {
        EM.error_handler do |e|
          log_e e, "Error in event loop"
        end

        NL::KndClient::EMKndClient.on_log do |msg|
          if msg.is_a?(Exception)
            log_e(msg)
          else
            log(msg)
          end
        end

        NL::KndClient::EMKndClient.on_bench do |name, block|
          NL::KNC::Bench.bench(name, &block)
        end

        NL::KndClient::EMKndClient.connect(hostname || '127.0.0.1')

        EM.start_server('0.0.0.0', NL::KNC::KNC_PORT, NL::KNC::ZoneWeb)

        NL::KNC::KncXap.start_kncxap if $xap_ok && NL::KNC::CONFIG[:xap] && NL::KNC::CONFIG[:xap][:enabled]
        NL::KNC::ZoneBright.start_bright
        KncHue.start_hue if $hue_ok && NL::KNC::CONFIG[:hue] && NL::KNC::CONFIG[:hue][:enabled]

        EM.add_periodic_timer(1) do
          if NL::KNC::CONFIG.modified?
            log "Saving configuration."
            NL::KNC::CONFIG.save
          end
        end

        EM.add_periodic_timer(10) do
          new_index = NL::KNC::EventLog.current_index
          if new_index != log_index
            log "Saving event log (#{new_index - log_index} new events)."
            NL::KNC::EVENT_LOG[:log] = NL::KNC::EventLog.store_log
            NL::KNC::EVENT_LOG.save
            log_index = new_index
          end

          rules = KncAction.store_rules
          if rules != NL::KNC::RULES[:rules]
            log "Saving automation rules."
            NL::KNC::RULES[:rules] = rules
            NL::KNC::RULES.save
          end
        end
      }
    end
  end
end

require_relative 'knc/zone_web'
require_relative 'knc/zone_bright'

require_relative 'knc/knc_rules'

begin
  require_relative 'knc/knc_xap'
  $xap_ok = true
rescue LoadError => e
  # Prevent total failure in case xAP fails to load due to missing gems...
  NL::KNC.log_e e, 'Error loading xAP module'
  $xap_ok = false
end

begin
  require_relative 'knc/knc_hue'
  $hue_ok = true
  $hue_error = nil
rescue Exception => e
  NL::KNC.log_e e, 'Error loading Hue support'
  $hue_ok = false
  $hue_error = e
end

require_relative 'knc/knc_zones'
require_relative 'knc/knc_rules'
