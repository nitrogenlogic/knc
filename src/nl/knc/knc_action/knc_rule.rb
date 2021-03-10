# Containing class for triggers and actions.  A Rule brings a Trigger,
# Filter/Condition, and Action together.
# (C)2013 Mike Bourgeous

require 'thread'
require_relative 'knc_action'
require_relative 'knc_trigger'
require_relative 'knc_condition'

module NL
  module KNC
    module KncAction
      # Indicates errors that occurred while loading a Rule.  If the Rule was
      # loaded anyway, it will be included in the error.
      class RuleLoadError < StandardError
        attr_reader :rule

        def initialize rule, msg
          super msg
          @rule = rule
        end
      end

      # A Rule combines a Trigger, Filter, Condition, and Action to form a
      # complete automation task.
      class Rule
        attr_reader :id, :trigger, :filter, :true_action, :false_action

        # Converts a Hash (e.g. parsed from JSON using symbolize_names)
        # into a Rule.  The hash should previously have been serialized
        # using Rule#to_h.  The Rule's trigger, condition, and actions
        # will be created from the Hash as well.  The block, if given,
        # will be called with the ID deserialized from the Hash.  The
        # block should return an available unique ID, which should be
        # the same as the ID it is passed, if it is available.
        def self.from_hash h, &block
          raise 'Rule.from_hash requires a Hash.' unless h.is_a?(Hash)
          id = h[:id]
          raise 'No unique Rule ID was found in the given Hash.' unless id

          errors = []

          id = yield id

          r = Rule.new id
          begin
            r.trigger = h[:trigger] && Trigger.from_hash(h[:trigger])
          rescue => e
            log_e e, "Error restoring automation rule #{id} trigger"
            NL::KNC::EventLog.error "Error restoring automation rule #{id} trigger: #{e}", 'Rules'

            errors << "Error restoring automation rule #{id} trigger: #{e}"
          end
          begin
            r.send :filter=, Filter.from_hash(h[:filter])
          rescue => e
            log_e e, "Error restoring automation rule #{id} filter"
            NL::KNC::EventLog.error "Error restoring automation rule #{id} filter: #{e}", 'Rules'

            errors << "Error restoring automation rule #{id} filter: #{e}"
          end
          begin
            r.true_action = h[:true_action] && Action.from_hash(h[:true_action])
          rescue => e
            log_e e, "Error restoring automation rule #{id} true action"
            NL::KNC::EventLog.error "Error restoring automation rule #{id} true action: #{e}", 'Rules'

            errors << "Error restoring automation rule #{id} true action: #{e}"
          end
          begin
            r.false_action = h[:false_action] && Action.from_hash(h[:false_action])
          rescue => e
            log_e e, "Error restoring automation rule #{id} false action"
            NL::KNC::EventLog.error "Error restoring automation rule #{id} false action: #{e}", 'Rules'

            errors << "Error restoring automation rule #{id} false action: #{e}"
          end

          raise RuleLoadError.new(r, errors.join("\n")) unless errors.empty?

          r
        end

        # Initializes a Rule with the given unique ID.
        def initialize id
          raise "A Rule's unique ID must be an integer." unless id.is_a?(Integer)
          @id = id

          @trigger = nil

          self.filter = Filter.new

          @true_action = nil
          @false_action = nil
        end

        # Sets the Trigger that will provide events for this Rule.  Be
        # sure to call .clean on the old Trigger.
        def trigger= trig
          raise "A Rule's trigger must be a Trigger or nil." unless trig.nil? || trig.is_a?(Trigger)
          return if trig == @trigger
          @filter.trigger = trig
          @trigger = trig
        end

        # Returns the condition used by the internal Filter.
        def condition
          @filter.condition
        end

        # Sets the condition used by the internal Filter to distribute
        # events to the true_action and false_action.  Be sure to call
        # .clean on the old Condition.
        def condition= c
          @filter.condition = c
        end

        # Sets the Action fired when the condition accepts an event.
        # Be sure to call .clean on the old Action.
        def true_action= act
          unless act.nil? || act.is_a?(Action)
            raise 'True action must be an Action or nil.'
          end
          @true_action = act
        end

        # Sets the Action fired when the condition rejects an event.
        # Be sure to call .clean on the old Action.
        def false_action= act
          unless act.nil? || act.is_a?(Action)
            raise 'False action must be an Action or nil.'
          end
          @false_action = act
        end

        # Generates a Hash that can later be passed to Rule.from_hash.
        # The include_info parameter is passed to the to_h methods of
        # Trigger, Filter, and Action.
        def to_h include_info=true
          {
            :id => @id,
            :trigger => @trigger && @trigger.to_h(include_info),
            :filter => @filter.to_h(include_info),
            :true_action => @true_action && @true_action.to_h(include_info),
            :false_action => @false_action && @false_action.to_h(include_info)
          }
        end
        alias to_hash to_h

        # Generates JSON from the return value of #to_h.  If the first
        # argument is a hash containing the key :noinfo with a trueish
        # value, then parameter information will not be included.
        def to_json *args
          to_h(!(args[0].is_a?(Hash) && args[0][:noinfo])).to_json *args
        end

        # Tells this Rule's Trigger, Filter, and Actions to clean
        # themselves, then sets them all to nil.  Call this when a Rule
        # is being removed (e.g. called by KncAction.delete_rule).
        def clean
          @trigger.clean if @trigger
          @trigger = nil
          @filter.clean if @filter
          @filter = nil
          @true_action.clean if @true_action
          @true_action = nil
          @false_action.clean if @false_action
          @false_action = nil
        end

        protected
        # Sets this Rule's Filter, moving listeners from the old Filter
        # to the new Filter.  The old Filter will be discarded.
        def filter= filt
          raise "A Rule's filter must be a Filter." unless filt.is_a?(Filter)

          if @filter
            @filter.clean
          end

          @filter = filt
          @filter.trigger = @trigger
          @filter.add_listener true do |trigger, pass, value, range|
            if @true_action
              @true_action.fire({
                :trigger => trigger,
                :pass => pass,
                :value => value,
                :range => range})
            end
          end
          @filter.add_listener false do |trigger, pass, value, range|
            if @false_action
              @false_action.fire({
                :trigger => trigger,
                :pass => pass,
                :value => value,
                :range => range})
            end
          end
        end
      end

      @@rules = {}
      @@next_id = 0
      @@id_lock = Mutex.new

      # Finds an unused unique index for a Rule.
      def self.next_id try_id=nil
        @@id_lock.synchronize {
          while try_id.nil? || @@rules.include?(try_id)
            try_id = @@next_id
            @@next_id += 1
          end
          @@next_id = try_id + 1 if try_id > @@next_id
        }
        try_id
      end

      # Adds a new, empty Rule to the list of rules.  Returns the new Rule.
      def self.add_rule
        r = Rule.new next_id
        @@rules[r.id] = r
        r
      end

      # Creates a new copy of the given rule.  Returns the new Rule.
      def self.copy_rule id
        raise "A Rule with the given ID #{id} was not found." unless @@rules.include? id

        # TODO: Something more elegant than serializing/deserializing a
        # rule to copy it?

        rule_from_hash @@rules[id].to_hash
      end

      # Adds a new Rule (and its associated Trigger, Condition, and Actions)
      # from the given Hash, preserving the Rule's saved ID if possible.  If
      # an error occurs while loading the rule, a RuleLoadError will be
      # passed to the caller.
      def self.rule_from_hash h
        error = nil

        r = begin
              Rule.from_hash h do |id| next_id(id) end
            rescue => e
              error = e
              error.is_a?(RuleLoadError) ? error.rule : nil
            end
        @@rules[r.id] = r if r

        raise error if error

        r
      end

      # Loads each rule from the given Array of Hashes.
      def self.load_rules arr
        raise 'Can only load Rules from an array of Hashes.' unless arr.is_a?(Array)

        errors = []

        arr.each do |h|
          begin
            rule_from_hash h
          rescue => e
            log_e e, "Error restoring automation rule #{h[:id]}"
            NL::KNC::EventLog.error "Error restoring autmation rule #{h[:id]}: #{e}.", 'Rules'

            errors << "Error restoring automation rule #{h[:id]}: #{e}"

            log h.inspect # XXX
          end
        end

        raise errors.join("\n") unless errors.empty?
      end

      # Removes all rules.
      def self.clear_rules
        rules = @@rules.clone
        @@rules.clear

        @@id_lock.synchronize {
          @@next_id = 0
        }

        rules.each do |id, r|
          r.clean
        end
      end

      def self.delete_rule id
        raise "A Rule with the given ID #{id} was not found." unless @@rules.include? id
        r = @@rules.delete id
        r.clean

        @@id_lock.synchronize {
          @@next_id = 0 if @@rules.empty?
        }
      end

      # TODO: User-categorized rules?

      # Returns a Hash mapping unique IDs to automation Rules.  Do not modify
      # the returned Hash.
      def self.rules
        @@rules
      end

      # Returns an array containing all rules converted to hashes.
      def self.store_rules
        @@rules.map{|k, v| v.to_hash(false)}
      end

      # Returns the nearest ID that is not equal to the given ID, or nil if
      # the given ID wasn't found or there are no other rules.  This method
      # may be slow if there are a lot of rules.
      def self.nearest_id id
        keys = @@rules.keys
        idx = keys.index(id)

        if idx == 0
          return keys[idx + 1]
        elsif idx > 0
          return keys[idx - 1]
        end

        return nil
      end
    end
  end
end
