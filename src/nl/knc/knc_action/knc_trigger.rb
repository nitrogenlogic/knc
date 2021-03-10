# Generic trigger support.  A trigger is an event that is filtered by a
# condition, then fires an action if the condition passes.  A trigger might be
# a zone's occupied parameter.  A condition might be a boolean value the
# parameter must equal.  An action might be turning a light on or off.
# (C)2013 Mike Bourgeous

require 'set'
require_relative 'knc_action'

module NL
  module KNC
    # The module which contains KNC's generic action and trigger support.
    module KncAction
      # A trigger can deliver events that cause an action to be fired.  This
      # class should be subclassed, and the subclass should call #fire() when
      # an event occurs.  Subclasses must call .register somewhere in their
      # class body, and should override the #clean() method.
      class Trigger
        include ParameterSet
        include NL::KNC::KNCLog
        extend NL::KNC::KNCLog

        @@triggers = Set.new
        @@trigger_hash = {}

        # The Set of registered triggers.
        def self.triggers
          @@triggers
        end

        # Returns the registered Trigger having the given name, or nil
        # if there is no such Trigger.
        def self.find_trigger name
          @@trigger_hash[name]
        end

        # Converts a JSON-parsed Hash into a Trigger.  The specific
        # type of Trigger must be in @@triggers for deserialization to
        # succeed.
        def self.from_hash h
          raise 'Trigger.from_hash requires a Hash.' unless h.is_a?(Hash)
          raise 'No Trigger type specified.' unless h.include? :type

          type = find_trigger h[:type]
          raise "No Trigger named #{h[:type]} was found." unless type

          trig = type.new
          trig.send :params_from_hash, h[:parameters]
          trig
        end

        # Adds a block or Proc to be called when this trigger fires an
        # event.  The listener must accept three parameters: the
        # originating trigger, the value of the event, and the range of
        # the event.  Returns a Proc object that may be passed to
        # remove_listener.  A listener will only be called once, and
        # may only be removed once, even if it is added multiple times.
        def add_listener listener=nil, &block
          @listeners ||= Set.new
          if block_given?
            raise 'Specify only a listener or a block, not both' unless listener.nil?
            @listeners << block
          elsif listener.is_a? Proc
            @listeners << listener
          else
            raise "No block given and listener #{listener.inspect} is not a Proc"
          end
        end

        # Removes the given listener (which should be a Proc returned
        # by add_listener) from event notifications.
        def remove_listener listener
          raise "listener #{listener} is not a Proc" unless listener.is_a? Proc
          @listeners ||= Set.new
          @listeners.delete listener
        end

        # Tells this Trigger to stop timers, disconnect from events,
        # and discard allocated resources.  Subclass implementations
        # should call this superclass method.
        def clean
          @listeners.clear
        end

        # Returns the human-friendly name of this trigger's class.
        def to_s
          self.class.instance_variable_get :@name
        end

        # Returns the human-friendly name of this trigger class.
        def self.to_s
          self.instance_variable_get :@name
        end

        # Returns a Hash that can later be passed to Trigger.from_hash.
        # include_info is passed to ParameterSet#params_hash.
        def to_h include_info=true
          { :type => to_s }.merge!(params_hash(include_info))
        end
        alias to_hash to_h

        # Generates JSON from the return value of #to_h.  If the first
        # argument is a hash containing the key :noinfo with a trueish
        # value, then parameter information will not be included.
        def to_json *args
          to_h(!(args[0].is_a?(Hash) && args[0][:noinfo])).to_json(*args)
        end

        private
        # Subclasses should call this method when an event
        # corresponding to this trigger occurs.  For example, a zone
        # parameter change trigger would call this method whenever the
        # specified zone's specified parameter changes.  The value
        # should be a boolean or a Numeric.
        def fire value, range
          @listeners ||= Set.new
          @listeners.each do |l|
            EM.next_tick do
              begin
                l.call self, value, range
              rescue => e
                log_e e, "Error calling listener #{l} from #{self} (#{self.object_id})"
              end
            end
          end
        end

        # Adds a trigger subclass to the list of registered
        # triggers.  The class name is converted from camel case to
        # produce the name displayed to the user.  "Trigger" is removed
        # from the end.  So, subclass names should look like this:
        # TriggerNameTrigger.
        def self.register
          name = self.name.split(':').last.gsub(/Trigger$/, '').camel.join(' ')
          self.instance_variable_set :@name, name

          raise "A Trigger named '#{name}' is already registered." if @@trigger_hash.include? name

          @@triggers << self
          @@trigger_hash[name] = self
          log "Added trigger #{self}" # XXX
        end
      end

      # A Trigger that fires an event every given number of seconds.
      class TimerTrigger < Trigger
        register

        def initialize
          @interval = add_parameter Parameter.new("Interval (seconds)", Numeric, 1..86400)
          @state = false
          @timer = nil
          @timertask = proc {
            @state = !@state
            fire @state, nil
          }
          update_timer
        end

        def clean
          @timer.cancel if @timer
          @timer = nil
          super
        end

        def []= param, value
          super param, value

          if param == @interval
            update_timer
          end
        end

        private
        def update_timer
          EM.next_tick do
            @timer.cancel if @timer
            @timer = EM::add_periodic_timer(self[@interval], @timertask)
          end
        end
      end

      # A Trigger that fires a random integer every given number of seconds.
      class RandomTrigger < TimerTrigger
        register

        def initialize
          super
          @min = add_parameter Parameter.new("Minimum", Integer, nil, 0)
          @max = add_parameter Parameter.new("Maximum", Integer, nil, 100)
          @range = self[@min]..self[@max]
          @timertask = proc {
            fire rand(@range), @range
          }
        end

        def []= param, value
          super param, value

          if param == @min
            self[@max] = value if self[@max] < value
          elsif param == @max
            self[@min] = value if self[@min] > value
          end

          @range = self[@min]..self[@max]
        end
      end

      # TODO: Clock/calendar trigger (would require fixing hardware clock issues)

      # XXX
      Trigger.log "Registered triggers:\n\t#{Trigger.triggers.to_a.join("\n\t")}"
    end
  end
end
