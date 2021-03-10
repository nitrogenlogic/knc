# Parameter support for Automation Rule system on the Depth Camera Controller.
# (C)2013 Mike Bourgeous

module NL
  module KNC
    module KncAction
      # A parameter that can be set on an action, trigger, or condition.
      class Parameter
        attr_reader :name, :type, :range, :revrange, :default

        # name - The name of the parameter (e.g. "Light ID").  Leading/trailing whitespace will be removed.
        # type - The type of the parameter (Integer, Numeric, String, Symbol, :boolean).
        # range - The value range of the parameter:
        # 		nil for no limits,
        # 		Range with min/max (lengths if type is String),
        # 		Array with acceptable list,
        # 		Hash with acceptable list => user-friendly String.
        # 		Include nil in Array or Hash to allow any value.
        # 		Range required if type is Symbol.
        # default - The default value of the parameter (nil to use the first element in range,
        # 		true if :boolean and no range, 0 if Numeric and no range,
        # 		'' if String and no range).
        # percent_preferred - Whether the parameter's percentage value is more user-friendly.
        # optional - Whether the parameter must be specified for each ActionActivator.
        def initialize name, type, range = nil, default = nil, percent_preferred = false, optional = false
          raise 'name must be specified' unless name.is_a?(String) && name.strip.length > 0
          @name = name.strip

          unless type == :boolean || type == Integer || type == Numeric || type == String || type == Symbol
            raise 'type must be :boolean, Integer, Numeric, String, or Symbol'
          end
          @type = type

          self.range = range

          if !default.nil?
            raise 'default must have type specified in type' unless check_type(default)
            raise 'default must be within range' unless check_range(default)
            @default = default
          elsif @range.is_a?(Hash)
            @range.each do |k, v|
              unless k.nil?
                @default = k
                break
              end
            end
          elsif @range.is_a?(Array)
            @range.each do |v|
              unless v.nil?
                @default = v
                break
              end
            end
          elsif @range.is_a?(Range) && type != String
            @default = @range.min
          end

          unless @default
            if @type == :boolean
              @default = true
            elsif @type == Integer || @type == Numeric
              @default = 0
            elsif @type == String
              @default = ''
            elsif @type == Symbol
              raise "A non-empty range must be specified when a Parameter's type is Symbol"
            else
              raise "BUG: invalid type #{@type} when setting up default"
            end
          end

          unless percent_preferred == true || percent_preferred == false
            raise 'percent_preferred must be true or false'
          end
          unless percent_preferred == false || range.is_a?(Range)
            raise 'percent_preferred not permitted unless range is a Range'
          end
          @percent_preferred = percent_preferred

          raise 'optional must be true or false' unless optional == true || optional == false
          @optional = optional
        end

        # Indicates whether given value can be assigned to this parameter by type.
        # Does not verify range; use #check_range() for that.
        def check_type value
          if @type == :boolean
            return value == true || value == false
          end
          return value.is_a? @type
        end

        # Indicates whether the given value is within the range of this
        # parameter.  Any value is permitted if the range is an Array
        # or Hash and includes nil.  Does not verify type; use
        # #check_type() for that.
        def check_range value
          if @type == String && @range.is_a?(Range)
            return @range.nil? || @range.include?(value.length)
          end
          return @range.nil? || @range.include?(nil) || @range.include?(value)
        end

        # Raises an exception if the given value is the wrong type or
        # out of range for this parameter.  Returns the value.
        def check_value value
          unless check_type(value)
            raise "Invalid type #{value.class} for parameter #{@name}"
          end
          unless check_range(value)
            raise "Out-of-range value for parameter #{@name}" if @type == String || @type == Symbol
            raise "Out-of-range value #{value} for parameter #{@name}"
          end
          value
        end

        # Parses the given String using this parameter's type.  Returns
        # the value unmodified if it is already the correct type.  If
        # this parameter's range is a Hash, then Strings will be
        # checked against the range's user-friendly values before
        # attempting to parse the internal values.  Doesn't pass the
        # parsed value to #check_range.  Raises an error for :boolean
        # if str is not 'true' or 'false' (ignoring
        # case).
        def parse str
          if @range.is_a?(Hash) && @revrange.include?(str)
            return @revrange[str]
          end

          return str if check_type(str)

          if @type == :boolean
            str = str.downcase
            return true if str == 'true'
            return false if str == 'false'
            raise "Boolean values must be 'true' or 'false'."
          elsif @type == Integer
            return str.to_i
          elsif @type == Numeric
            return str.to_f if str =~ /[.eE]/
            return str.to_i
          elsif @type == Symbol
            return str.to_sym
          end

          return str
        end

        # TODO: clamp_range

        # Returns the name of this Parameter.
        def to_s
          @name
        end

        # Returns a Hash that describes this Parameter.
        def to_h
          {
            :name => @name,
            :type => @type.to_s,
            :range => @range.is_a?(Range) ? { :min => @range.min, :max => @range.max } : @range,
            :default => @default,
            :percent_preferred => @percent_preferred, # TODO: Get rid of percent preferred?
            :optional => @optional
          }
        end
        alias to_hash to_h

        # Converts the Hash describing this Parameter to JSON.
        def to_json *args
          to_h.to_json *args
        end

        # Changes the accepted range of this parameter (nil for no
        # limits, Range with min/max (lengths if type is String), Array
        # with acceptable list).  Clears this Parameter's
        # percent_preferred? flag if set to anything other than a
        # Range.  Resets this Parameter's default value to the first
        # non-nil element of the range if range is not nil and does not
        # include the default value.  A range Array or Hash must be
        # specified if type is Symbol.  Include nil in Array or Hash to
        # allow any value.
        def range= range
          unless range.nil?
            unless [Range, Array, Hash].include?(range.class)
              raise 'range must be a Range, Hash, or Array'
            end

            if range.is_a?(Range)
              unless (@type == String && range.first.is_a?(Integer) && range.last.is_a?(Integer)) ||
                  (check_type(range.first) && check_type(range.last))
                raise 'Range limits must have the specified type'
              end
              @range = range.clone.freeze
            elsif range.is_a?(Hash)
              range.each do |k, v|
                unless k.nil? || (check_type(k) && v.is_a?(String))
                  raise 'Hash range must map the specified type to String'
                end
              end
              range = range.clone.freeze
              revrange = range.invert.freeze
              if range.size != revrange.size
                raise 'Hash range must map one-to-one to Strings'
              end
              @range = range
              @revrange = revrange
            else
              range.each do |v|
                unless v.nil? || check_type(v)
                  raise 'Array range elements must have the specified type'
                end
              end
              @range = range.uniq.freeze
              @percent_preferred = false
            end
          else
            raise 'range must not be nil when type is Symbol' if @type == Symbol
            @range = nil
            @percent_preferred = false
          end

          if @range && instance_variable_defined?(:@default) && !range.include?(@default)
            if @range.is_a?(Range)
              @default = @range.first
            elsif @range.is_a?(Hash)
              @range.each do |k, v|
                unless k.nil?
                  @default = k
                  break
                end
              end
            else
              @range.each do |v|
                unless v.nil?
                  @default = v
                  break
                end
              end
            end
          end
        end

        # Indicates whether this parameter is more naturally controlled
        # by a percentage of its range.
        def percent_preferred?
          @percent_preferred
        end

        # Indicates whether this parameter can be omitted when firing
        # an action (Triggers and Conditions do not support optional
        # Parameters).
        def optional?
          @optional
        end
      end

      # Provides support to Action, Condition, and Trigger for parameters.
      # This module should be included in the target class.
      module ParameterSet
        # Whether to allow optional parameters.
        @@allow_optional = false

        # Returns the Set of this object's parameters.  Do not modify
        # this Set directly.
        def parameters
          @parameters ||= Set.new
          @parameters
        end

        # Returns an array containing this object's non-optional parameters.
        def mandatory_parameters
          @parameters ||= Set.new
          @parameters.select {|p| !p.optional?}
        end

        # Returns an array containing this object's optional parameters.
        def optional_parameters
          @parameters ||= Set.new
          @parameters.select {|p| p.optional?}
        end

        # Finds a parameter with the given name.  Raises an error if
        # the name isn't found.
        def find_parameter name
          @param_hash ||= {}
          raise "No parameter named '#{name}' on #{self}." unless @param_hash.include? name
          @param_hash[name]
        end

        # Sets a parameter on this object (e.g. Action, Trigger,
        # Condition).  Parameters control an object's behavior.
        # Subclasses of Action, Trigger, and Condition add available
        # parameters in their constructors.  Pass the name of the
        # parameter or a Parameter object as the first argument.
        def []= param, value
          @parameters ||= Set.new
          @paramvals ||= {}

          param = find_parameter(param) if param.is_a?(String)
          raise 'param is not a Parameter' unless param.is_a?(Parameter)
          raise "Parameter #{param.name} is not from this object." unless @parameters.include?(param)

          @paramvals[param] = param.check_value(value)
        end

        # Gets the value of the given parameter, or nil if the given
        # optional parameter isn't set.
        def [] param
          @parameters ||= Set.new
          @paramvals ||= {}

          param = find_parameter(param) if param.is_a?(String)
          raise 'param is not a Parameter' unless param.is_a?(Parameter)
          raise "Parameter #{param.name} is not from this object." unless @parameters.include?(param)

          @paramvals[param]
        end

        # Clears the given optional parameter's value.
        def clear_parameter param
          @parameters ||= Set.new
          @paramvals ||= {}
          raise 'param is not a Parameter' unless param.is_a?(Parameter)
          raise "Parameter #{param.name} is not from this object." unless @parameters.include?(param)
          raise 'Cannot clear a non-optional parameter.' unless param.optional?
          @paramvals.delete param
        end

        # Returns a hash containing the current parameter values.  If
        # include_info is true (the default), then information about
        # all available parameters is included as well.  The hash looks
        # like this:
        # {
        #   :parameters => { :name => [value] },
        #   :param_info => [parameters]
        # }
        def params_hash include_info=true
          @parameters ||= Set.new
          @paramvals ||= {}

          valhash = Hash[@paramvals.map{|k, v| [k.to_s.to_sym, v]}]
          if include_info
            return {
              :parameters => valhash,
              :param_info => @parameters.to_a
            }
          else
            return { :parameters => valhash }
          end
        end

        protected
        # Loads parameters from the given hash, printing a warning
        # using the "log" method for parameters that aren't part of
        # this parameter set.  The keys of the hash, when converted to
        # strings, should be the names of parameters.  The values will
        # be parsed using Parameter#parse.
        def params_from_hash h
          raise 'Can only load parameters from a Hash.' unless h.is_a?(Hash)

          # If these have to be created now, there shouldn't be
          # any parameters to deserialize.
          @parameters ||= Set.new
          @paramvals ||= {}
          @param_hash ||= {}

          h.each do |key, value|
            param = @param_hash[key.to_s]
            if param
              begin
                self[param] = param.parse(value)
              rescue => e
                log_e e, "Warning: Unable to set #{key} to #{value.inspect} when loading parameters"
              end
            else
              log "Warning: no such parameter #{key} on #{self} when loading parameters."
            end
          end
        end

        private
        # Adds a controllable parameter to this object, set to its
        # default value if the parameter is not optional.  The
        # parameter is stored in the @parameters Set.  Returns the
        # added parameter.
        def add_parameter param
          raise 'param must be a Parameter' unless param.is_a? Parameter
          if param.optional? && !@@allow_optional
            raise "Optional parameters not supported on #{self.class.name}"
          end

          @parameters ||= Set.new
          @paramvals ||= {}
          @param_hash ||= {}

          if @param_hash.include? param.name
            raise "A parameter named #{param.name} already exists."
          end

          @parameters << param
          @paramvals[param] = param.default unless param.optional?
          @param_hash[param.name] = param

          param
        end

        # Removes the given parameter from the list of parameters.
        def remove_parameter param
          @parameters ||= Set.new
          @paramvals ||= {}
          @param_hash ||= {}

          raise 'param must be a Parameter' unless param.is_a? Parameter
          raise "param #{param} is not from this object" unless @parameters.include? param

          @parameters.delete param
          @paramvals.delete param
          @param_hash.delete param.name
        end

        # Removes all parameters and their stored values.
        def clean_parameters
          @parameters.clear if @parameters
          @paramvals.clear if @paramvals
          @param_hash.clear if @param_hash
        end
      end
    end
  end
end
