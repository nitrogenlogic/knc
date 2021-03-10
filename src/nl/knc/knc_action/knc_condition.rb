# Conditions for filtering events from a Trigger before sending to an Action.
# (C)2013 Mike Bourgeous

require 'set'
require_relative 'knc_action'
require_relative 'knc_trigger'

module NL
  module KNC
    module KncAction
      # Converts the given value into a boolean value.
      #
      # If the value is false, nil, or 0, false is returned.
      #
      # If the value is true or nonzero, true is returned.
      def self.boolean_value value
        return (value && value != 0) ? true : false
      end

      # Converts the given boolean or numeric value into a numeric value.
      #
      # If the value is false, 0 is returned.
      #
      # If the value is true, 1 is returned.
      #
      # Otherwise, the value is returned unchanged.
      def self.numeric_value value
        return value == false ? 0 :
          value == true ? 1 :
          value
      end

      # Converts the given value into a percentage value, using the
      # given range.
      #
      # If the value is false or nil, 0 is returned.
      #
      # If the value is true, 100 is returned.
      #
      # If the range is a Range, the value will be scaled with
      # range.min as 0 and range.max as 100.
      #
      # If the range is an Array, the index of the value within the
      # array will be scaled with range.length as 100.  If the value does not
      # occur within the array, the raw value will be returned, clamped to
      # 0-100..
      #
      # Otherwise, the raw value will be returned, clamped to 0-100.
      def self.percent_value value, range
        return 0 unless value
        return 100 if value == true

        if range.is_a? Range
          return (value - range.min) * 100.0 / (range.max - range.min)
        end

        if range.is_a? Array
          idx = range.index(value)
          return idx * 100.0 / range.length if idx
        end

        return [100, [0, value].max].min
      end

      # A Filter sits between a Trigger and a pair of Actions, using a
      # Condition to determine which Action should receive events.
      class Filter
        attr_reader :condition, :trigger, :edge

        # Creates a new Filter and Condition based on the given Hash
        # previously returned by Filter#to_h (or parsed from JSON
        # returned by Filter#to_json using JSON.parse(...,
        # :symbolize_names => true)).
        def self.from_hash h
          raise 'Filter.from_hash requires a Hash.' unless h.is_a?(Hash)

          filt = Filter.new
          filt.edge = h[:edge]
          filt.condition = Condition.from_hash h[:condition]

          filt
        end

        def initialize
          @condition = AlwaysCondition.new
          @edge = true
          @trigger = nil

          @last_pass = nil
          @handler = proc { |trigger, value, range|
            pass = @condition.pass value, range
            if !@edge || pass != @last_pass || @condition.is_a?(AlwaysCondition)
              fire pass, value, range
              @last_pass = pass
            end
          }

          @true_listeners = Set.new
          @false_listeners = Set.new
        end

        def condition= condition
          raise "A Filter's condition must be a Condition." unless condition.is_a? Condition
          @condition = condition
        end

        # Sets the trigger whose events should be received and
        # processed by this Filter.  Adds this Filter as an event
        # listener to the given trigger (if not nil), and removes the
        # event listener from the existing Trigger, if any.
        def trigger= trigger
          unless trigger.nil? || trigger.is_a?(Trigger)
            raise "A Filter's trigger must be a Trigger or nil."
          end

          @trigger.remove_listener @handler if @trigger
          trigger.add_listener @handler if trigger

          @trigger = trigger
        end

        # Sets whether this Filter is edge-triggered (true: only the
        # first event that results in a Condition changing from true to
        # false or false to true is delivered) or level-triggered
        # (false: every event is delivered to its corresponding
        # listener).  This setting is ignored if the condition is an
        # AlwaysCondition.
        def edge= edge
          raise 'edge must be true or false.' unless edge == true || edge == false
          @edge = edge
        end

        # Adds a listener to be notified when events pass (if pass is
        # true), fail (if pass is false), or either (if pass is nil).
        # The listener must accept four parameters: the source trigger,
        # whether the event passed the condition, the value of the
        # event, and the range of the event.  Either pass a Proc object
        # in listener or provide a block, but not both.  Returns the
        # Proc object that may be passed to remove_listener.
        def add_listener pass, listener=nil, &block
          raise 'pass must be true, false, or nil' unless pass.nil? || pass == true || pass == false
          if block_given?
            raise 'Specify only a listener or a block, not both' unless listener.nil?
            listener = block
          elsif !listener.is_a?(Proc)
            raise "No block given and listener #{listener.inspect} is not a Proc"
          end

          case pass
          when true
            @true_listeners << listener
          when false
            @false_listeners << listener
          when nil
            @true_listeners << listener
            @false_listeners << listener
          end
        end

        # Removes the given listener (A Proc object either passed to or
        # returned by add_listener).
        # pass - true: remove the listener from the listeners notified with passing events
        # 	false: remove the listener from the listeners notified with failing events
        # 	  nil: remove the listener from all events
        def remove_listener pass, listener
          raise "listener #{listener.inspect} is not a Proc" unless listener.is_a? Proc

          case pass
          when true
            @true_listeners.delete listener
          when false
            @false_listeners.delete listener
          when nil
            @true_listeners.delete listener
            @false_listeners.delete listener
          end
        end

        # Generates a Hash that can later be passed to
        # Filter.from_hash.  The include_info parameter is passed to
        # Condition#to_h.
        def to_h include_info=true
          { :edge => @edge, :condition => @condition.to_h(include_info) }
        end
        alias to_hash to_h

        # Generates JSON from the return value of #to_h.  If the first
        # argument is a hash containing the key :noinfo with a trueish
        # value, then parameter information will not be included.
        def to_json *args
          to_h(!(args[0].is_a?(Hash) && args[0][:noinfo])).to_json *args
        end

        # Tells the contained Condition to clean itself, then gets rid
        # of any resources used by the Filter.  Call this method when
        # the Filter will no longer be used.
        def clean
          self.trigger = nil
          @condition.clean
          @condition = nil
          @true_listeners.clear
          @false_listeners.clear
        end

        private
        # pass - Whether this event was passed by the condition.
        # value - The value of the event from the Trigger.
        # range - The range of the event from the Trigger.
        def fire pass, value, range
          if pass
            @true_listeners.each do |l|
              l.call @trigger, pass, value, range
            end
          else
            @false_listeners.each do |l|
              l.call @trigger, pass, value, range
            end
          end
        end
      end

      # A condition that determines whether to pass events from a Trigger to
      # an Action.  Conditions may have a memory of previous values.
      # Subclasses must call .register() somewhere in their class body and
      # override the #pass() method.
      class Condition
        include ParameterSet
        include NL::KNC::KNCLog
        extend NL::KNC::KNCLog

        @@conditions = Set.new
        @@condition_hash = {}

        # The Set of registered Conditions.
        def self.conditions
          @@conditions
        end

        # Returns the condition having the given user-friendly name, or
        # nil if there is no such condition.
        def self.find_condition name
          @@condition_hash[name]
        end

        # Converts a JSON-parsed Hash into a Condition.  The specific
        # type of condition must be in @@conditions for deserialization
        # to succeed.
        def self.from_hash h
          raise 'Condition.from_hash requires a Hash.' unless h.is_a? Hash
          raise 'No Condition type specified.' unless h.include? :type

          type = find_condition h[:type]
          raise "No Condition named #{h[:type]} was found." unless type

          cond = type.new
          cond.send :params_from_hash, h[:parameters]
          cond
        end

        # Indicates whether the given value in the given range passes this condition.
        def pass value, range
          raise NotImplementedError.new 'Condition subclasses must override the value method.'
        end

        # Returns the human-friendly name of this comparison.
        def to_s
          self.class.instance_variable_get :@name
        end

        # Returns the human-friendly name of this comparison class.
        def self.to_s
          self.instance_variable_get :@name
        end

        # Returns a Hash that can later be deserialized by passing to
        # Condition.from_hash.  The include_info parameter is passed to
        # ParameterSet#params_hash.
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

        # Discards references to resources used by this Condition.
        # Subclasses should override this method and call this
        # superclass implementation if they allocate any
        # memory-intensive resources, timer tasks, etc.
        def clean
          clean_parameters
        end

        private
        # Adds a condition subclass to the list of registered
        # conditions.  The class name is converted from camel case to
        # produce the name displayed to the user.  "Condition" is
        # removed from the end.  So, subclass names should look like
        # this: ConditionNameCondition.
        def self.register
          name = self.name.split(':').last.gsub(/Condition$/, '').camel.join(' ')
          self.instance_variable_set :@name, name

          raise "A Condition named '#{name}' is already registered." if @@condition_hash.include? name

          @@conditions << self
          @@condition_hash[name] = self
          log "Added condition #{self}" # XXX
        end
      end

      # A condition that passes all events.
      class AlwaysCondition < Condition
        register

        def pass value, range
          true
        end
      end

      # A condition that passes events with a given boolean value.
      # Numeric events will be passed if their value is non zero.
      class BooleanCondition < Condition
        register

        def initialize
          @val = add_parameter Parameter.new("Value", :boolean)
        end

        def pass value, range
          KncAction.boolean_value(value) == self[@val]
        end
      end

      # A condition that passes events whose absolute value matches a
      # comparison with a reference value.  Boolean values will be treated as
      # having a numeric value of 0 for false and 1 for true.
      class ComparisonCondition < Condition
        register

        def initialize
          @comp = add_parameter Parameter.new("Comparison", Symbol,
                                              [:'<', :'<=', :'!=', :'=', :'>=', :'>'], :'=')
          @val = add_parameter Parameter.new("Value", Numeric)
        end

        def pass value, range
          value = 1 if value == true
          value = 0 if value == false

          # There's probably some clever Rubyish way to do this
          # using metaprogramming...
          case self[@comp]
          when :'<'
            return value < self[@val]

          when :'<='
            return value <= self[@val]

          when :'!='
            return value != self[@val]

          when :'='
            return value == self[@val]

          when :'>='
            return value >= self[@val]

          when :'>'
            return value > self[@val]
          end
        end
      end

      # A condition that passes events whose value as a percentage of their
      # range matches a comparison with a reference value between 0 and 100.
      # Boolean values will be treated as having a percentage value of 0 for
      # false and 100 for true.  For values without a range, the absolute
      # value will be used.
      class PercentComparisonCondition < Condition
        register

        def initialize
          @comp = add_parameter Parameter.new("Comparison", Symbol,
                                              [:'<', :'<=', :'!=', :'=', :'>=', :'>'], :'>=')
          @val = add_parameter Parameter.new("Value", Numeric, 0..100, 50)
        end

        def pass value, range
          value = KncAction.percent_value value, range

          case self[@comp]
          when :'<'
            return value < self[@val]

          when :'<='
            return value <= self[@val]

          when :'!='
            return value != self[@val]

          when :'='
            return value == self[@val]

          when :'>='
            return value >= self[@val]

          when :'>'
            return value > self[@val]
          end
        end
      end

      # A condition that passes events whose value has risen >= a rising
      # threshold, but not yet fallen <= a falling threshold.  Used to
      # implement hysteresis.
      class ThresholdCondition < Condition
        register

        def initialize
          @rising = add_parameter Parameter.new("Rising Threshold", Numeric, nil, 250)
          @falling = add_parameter Parameter.new("Falling Threshold", Numeric, nil, 150)
          @state = false
        end

        def pass value, range
          value = KncAction.numeric_value(value)

          if !@state && value >= self[@rising]
            @state = true
          elsif @state && value <= self[@falling]
            @state = false
          end

          @state
        end

        # Make sure rising >= falling
        def []= param, value
          super param, value

          if param == @rising
            if self[@falling] > value
              self[@falling] = value
            end
          elsif param == @falling
            if self[@rising] < value
              self[@rising] = value
            end
          end
        end
      end

      # A condition that passes events whose value as a percentage of their
      # range has risen >= a rising threshold, but not yet fallen <= a
      # falling threshold.  Used to implement hysteresis.
      class PercentThresholdCondition < Condition
        register

        def initialize
          @rising = add_parameter Parameter.new("Rising Threshold", Numeric, 0..100, 51)
          @falling = add_parameter Parameter.new("Falling Threshold", Numeric, 0..100, 49)
          @state = false
        end

        def pass value, range
          value = KncAction.percent_value(value, range)

          if !@state && value >= self[@rising]
            @state = true
          elsif @state && value <= self[@falling]
            @state = false
          end

          @state
        end

        # Make sure rising >= falling
        def []= param, value
          super param, value

          if param == @rising
            if self[@falling] > value
              self[@falling] = value
            end
          elsif param == @falling
            if self[@rising] < value
              self[@rising] = value
            end
          end
        end
      end

      # A condition that passes events whose value is within a specified
      # inclusive range.
      class RangeCondition < Condition
        register

        def initialize
          @min = add_parameter Parameter.new("Minimum", Numeric, nil, 100)
          @max = add_parameter Parameter.new("Maximum", Numeric, nil, 200)
        end

        def pass value, range
          value = KncAction.numeric_value(value)
          value >= self[@min] && value <= self[@max]
        end

        # Make sure max >= min
        def []= param, value
          super param, value

          if param == @max
            if self[@min] > value
              self[@min] = value
            end
          elsif param == @min
            if self[@max] < value
              self[@max] = value
            end
          end
        end
      end

      # A condition that passes events whose value as a percentage of their
      # range is within a specified inclusive range.
      class PercentRangeCondition < Condition
        register

        def initialize
          @min = add_parameter Parameter.new("Minimum", Numeric, nil, 25)
          @max = add_parameter Parameter.new("Maximum", Numeric, nil, 75)
        end

        def pass value, range
          value = KncAction.percent_value(value, range)
          value >= self[@min] && value <= self[@max]
        end

        # Make sure max >= min
        def []= param, value
          super param, value

          if param == @max
            if self[@min] > value
              self[@min] = value
            end
          elsif param == @min
            if self[@max] < value
              self[@max] = value
            end
          end
        end
      end

      # XXX
      Condition.log "Registered conditions:\n\t#{Condition.conditions.to_a.join("\n\t")}"
    end
  end
end
