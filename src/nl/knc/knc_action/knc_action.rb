# Action support for the Automation Rule system.
# (C)2013 Mike Bourgeous

require 'set'
require_relative 'knc_param'

module NL
  module KNC
    # The module which contains KNC's generic action and trigger support.
    module KncAction
      # Information about an action that can be performed in response to a
      # Trigger.  Subclasses must call the register method somewhere in their
      # class body and override the fire method.  See the documentation for
      # KncAction::ParameterSet for information on adding parameters to
      # subclassed Actions.
      class Action
        include ParameterSet
        include NL::KNC::KNCLog
        extend NL::KNC::KNCLog

        @@allow_optional = true

        @@actions = Set.new
        @@action_hash = {}

        # The Set of registered actions.
        def self.actions
          @@actions
        end

        # The registered Action having the specified human-friendly
        # name, or nil if there is no such Action.
        def self.find_action name
          @@action_hash[name]
        end

        # Converts a JSON-parsed Hash into an Action.  The specific
        # type of Action must be in @@actions for deserialization to
        # succeed.
        def self.from_hash h
          raise 'Action.from_hash requires a Hash.' unless h.is_a?(Hash)
          raise 'No Action type specified.' unless h.include? :type

          type = find_action h[:type]
          raise "No Action named #{h[:type]} was found." unless type

          act = type.new
          act.send :params_from_hash, h[:parameters]
          act
        end

        # Triggers this action.  Subclasses must override this method.
        # data - A Hash containing information about the event, with at
        # least the following elements: :trigger, :pass, :value, and
        # :range.
        def fire data
          raise NotImplementedError.new 'Action subclasses must override the fire method.'
        end

        # Returns the human-friendly name of this action's action class.
        def to_s
          self.class.instance_variable_get :@name
        end

        # Returns the human-friendly name of this action class.
        def self.to_s
          self.instance_variable_get :@name
        end

        # Returns a Hash that can later be passed to Action.from_hash.
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

        # Tells this Action to discard references to system resources,
        # stop timers (if any), etc.  Call when the Action will no
        # longer be used.  Subclasses that override this method should
        # call this superclass implementation.
        def clean
          @parameters.clear
          @paramvals.clear
        end

        private
        # Adds a action subclass to the list of registered actions.
        # The class name is converted from camel case to produce the
        # name displayed to the user.  The first camel word is used as
        # a category for the name, and "Action" is removed from the
        # end.  So, subclass names should look like this:
        # CategoryActionNameAction.
        def self.register
          words = self.name.split(':').last.gsub(/Action$/, '').camel
          group = words.shift
          name = "#{group}: #{words.join(' ')}"
          self.instance_variable_set :@name, name

          raise "An Action named '#{name}' is already registered." if @@action_hash.include? name

          @@actions << self
          @@action_hash[name] = self
          log "Added action #{self}" # XXX
        end
      end

      # An action that adds an event to the event log.
      class LogAddEventAction < Action
        register

        def initialize
          @detail = add_parameter Parameter.new("Event Details", :boolean, nil, true)
          @msg = add_parameter Parameter.new("Message", String, 0..100, nil, false, true)
        end

        def fire data
          msg = self[@msg] || 'Event triggered'
          msg += ": #{data.inspect}" if self[@detail]

          log "User log: #{msg}"

          if defined?(NL::KNC::EventLog)
            NL::KNC::EventLog.normal msg, 'User'
          end
        end
      end

      # XXX
      Action.log "Registered actions:\n\t#{Action.actions.to_a.join("\n\t")}"
    end
  end
end
