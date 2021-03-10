# Zone- and status-based Triggers for Automation Rules.
# (C)2013 Mike Bourgeous

require_relative 'knc_trigger'

module NL
  module KNC
    module KncAction
      module KncZoneTriggers
        @@trigger_proxy = proc { |type, *params|
          if @@listeners[type]
            @@listeners[type].each do |l|
              begin
                l.call type, *params
              rescue => e
                log_e e, "Error notifying Trigger listener #{l} with a #{type} event: #{params}"
              end
            end
          end
        }

        @@listeners = {}

        # Returns the event handler that should be added using
        # NL::KndClient::EMKndClient.instance.add_cb every time the backend
        # server comes online.
        def self.trigger_proxy
          @@trigger_proxy
        end

        # Calls the given block or callable object whenever @@trigger_proxy
        # receives an event of the given type.  The block will be called with
        # the event type and the event parameter (as received by
        # @@trigger_proxy).  Returns an object that may be passed to
        # remove_listener.
        def self.add_listener type, listener=nil, &block
          raise 'A block or callable object must be given.' unless listener || block_given?
          raise 'Pass either a block or a callable object, not both.' if listener && block_given?
          raise 'The listener must respond to the :call method.' unless block_given? || listener.respond_to?(:call)

          listener = block if block_given?
          @@listeners[type] ||= []
          @@listeners[type] << listener
          listener
        end

        # Removes the given listener from the list of listeners for the given
        # event type.
        def self.remove_listener type, listener
          @@listeners[type].delete(listener) if @@listeners[type]
        end

        # A trigger that sends true when the camera comes online, false when
        # the camera goes offline.
        class OnlineTrigger < KncAction::Trigger
          register

          def initialize
            @listener = KncZoneTriggers.add_listener :online do |type, state, elapsed|
              fire state, nil
            end
          end

          def clean
            super
            KncZoneTriggers.remove_listener :online, @listener
            @listener = nil
          end
        end

        # A trigger that sends the current frame rate.
        class FPSTrigger < KncAction::Trigger
          register

          def initialize
            @fps = -1
            @listener = KncZoneTriggers.add_listener :fps do |type, fps|
              if fps != @fps
                @fps = fps
                fire [fps, 30].min, 0..30
              end
            end
          end

          def clean
            super
            KncZoneTriggers.remove_listener :fps, @listener
            @listener = nil
          end
        end

        # A trigger that sends zone parameters.
        class ZoneTrigger < KncAction::Trigger
          register

          @@zone = KncAction::Parameter.new(
            'Zone',
            String,
            NL::KndClient::EMKndClient.zones ? [nil, '[No Zone]', *NL::KndClient::EMKndClient.zones.keys] : [nil, '[No Zone]']
          )

          @@update_proc = proc {
            @@zone.range = [nil, '[No Zone]', *NL::KndClient::EMKndClient.zones.keys]
          }

          KncZoneTriggers.add_listener(:add, &@@update_proc)
          KncZoneTriggers.add_listener(:del, &@@update_proc)
          KncZoneTriggers.add_listener(:online, &@@update_proc)

          def initialize
            @@key ||= KncAction::Parameter.new('Parameter', String, NL::KndClient::Zone.params)

            add_parameter @@zone
            add_parameter @@key

            @last_value = nil

            @listener = KncZoneTriggers.add_listener :add do |type, zone|
              key = self[@@key]
              if zone['name'] == self[@@zone] && zone.include?(key)
                value = zone[key]
                if value != @last_value
                  fire zone[key], zone.range(key)
                  @last_value = value
                end
              end
            end

            KncZoneTriggers.add_listener :change, @listener
          end

          def clean
            super
            KncZoneTriggers.remove_listener :add, @listener
            KncZoneTriggers.remove_listener :change, @listener
            @listener = nil
          end

          def []= param, value
            super param, value
            @last_value = nil
          end
        end
      end
    end
  end
end
