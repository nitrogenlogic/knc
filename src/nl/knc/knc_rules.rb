# Required files and web handlers for automation rule support in the Depth
# Camera Controller web interface.
# (C)2013 Mike Bourgeous

require 'eventmachine'
require 'escape_utils'

module NL
  module KNC
    module KncRules
      extend NL::KNC::KNCLog
      extend NL::KNC::HTMLEscape

      # Generates an HTML select input for triggers with the given Trigger selected.
      def self.triggers_html trig
        # FIXME: Firefox is not selecting the new dropdown value when
        # the page is reloaded with a different selected item.
        html = <<-HTML
          <select name="trigger">
            <option value=""#{trig.nil? ? ' selected' : ''}>[No Trigger]</option>
            #{KncAction::Trigger.triggers.map{|t|
              "<option value=\"#{t}\"#{trig.class == t ? ' selected' : ''}>#{t}</option>"
            }.join("\n")}
          </select>
        HTML
      end

      # Generates an HTML select input for Conditions with the given Condition selected.
      def self.conditions_html cond
        html = <<-HTML
          <select name="condition">
            #{KncAction::Condition.conditions.map{|t| "<option#{cond.class == t ? ' selected' : ''}>#{t}</option>"}.join("\n")}
          </select>
        HTML
      end

      # Generates an HTML select input for Actions with the given Action selected.
      def self.actions_html pass, act
        html = <<-HTML
          <select name="#{pass}_action">
            <option value=""#{act.nil? ? ' selected' : ''}>[No Action]</option>
            #{KncAction::Action.actions.map{|t|
              "<option value=\"#{t}\"#{act.class == t ? ' selected' : ''}>#{t}</option>"
            }.join("\n")}
          </select>
        HTML
      end

      # Generates an HTML form input for the given parameter, using its type
      # and range to decide what kind of input to create.
      # html_id - The ID used by the label corresponding to this input
      # name - The form field name submitted to the controller
      # param - The Parameter object for which to generate HTML
      # value - The value of the parameter, converted to String
      def self.param_html html_id, name, param, value
        value = param.default if value.nil?
        range = param.range
        type = param.type
        html = []

        if range.is_a?(Array) || range.is_a?(Hash)
          # TODO: Use a datalist for parameters that allow values
          # outside their Array range (i.e. range.include?(nil)
          # == true)

          html << %Q{<select id="#{html_id}" name="#{name}">\n}

          if range.is_a? Array
            range.each do |entry|
              next if entry.nil?
              html << %Q{\t<option value="#{h(entry)}"}
              html << ' selected' if value == entry
              html << ">#{h(entry)}</option>\n"
            end
          else
            range.each do |entry, desc|
              next if entry.nil?
              html << %Q{\t<option value="#{h(entry)}"}
              html << ' selected' if value == entry
              html << ">#{h(desc)}</option>\n"
            end
          end
          unless range.include?(value)
            html << %Q{\t<option value="#{h(value)}" selected>#{h(value)}</option>\n}
          end
          html << %Q{</select>\n}
        else
          if type == :boolean
            html << %Q{<input type="hidden" name="#{name}" value="false">}
            html << %Q{<input type="checkbox" id="#{html_id}" name="#{name}" value="true"}
            html << ' checked' if value == true
            html << '>'
          elsif type == Integer
            html << %Q{<input type="number" id="#{html_id}" name="#{name}" value="#{value}"}
            if range.is_a? Range
              html << %Q{ min="#{range.min}" max="#{range.max}"}
            end
            html << '>'
          elsif type == Numeric
            html << %Q{<input type="number" id="#{html_id}" name="#{name}" value="#{value}" step="any"}
            if range.is_a? Range
              html << %Q{ min="#{range.min}" max="#{range.max}"}
            end
            html << '>'
          else
            html << %Q{<input type="text" id="#{html_id}" name="#{name}" value="#{h(value)}"}
            if range.is_a? Range
              html << %Q{ maxlength="#{range.max}"}
            end
            html << '>'
          end
        end

        html.join
      end

      # Generates a parameters table for the given ParameterSet object, rule
      # ID, and parameter set type (e.g. 'trigger', 'true_action', etc.).
      def self.parameters_html pset, id, target
        return '' unless pset

        html = %Q{<table class="parameters">\n}

        pset.mandatory_parameters.each do |param|
          html_id = "#{target}_#{id}_#{param.name.downcase.gsub(/[^a-z0-9]+/, '_')}"
          name = "param_#{target}_#{h(param.name)}"

          html << %Q{<tr data-param="#{h(param.name)}"><td><label for="#{html_id}">}
          html << %Q{#{h(param.name)}</label></td>\n}
          html << "<td></td>\n"
          html << "<td>#{param_html(html_id, name, param, pset[param])}"
          html << "</td></tr>\n"
        end

        opt_hidden = []
        pset.optional_parameters.each do |param|
          html_id = "#{target}_#{id}_#{param.name.downcase.gsub(/[^a-z0-9]+/, '_')}"
          name = "param_#{target}_#{h(param.name)}"

          if pset[param].nil?
            opt_hidden << %Q{<tr data-param="#{h(param.name)}"><td><label for="#{html_id}">}
            opt_hidden << %Q{#{h(param.name)}</label></td>\n}
            opt_hidden << %Q{<td class="param_link"><a id="add_#{html_id}" class="add_parameter" }
            opt_hidden << %Q{rel="nofollow" href=}
            opt_hidden << %Q{"/rules/add_parameter?redir=1&id=#{id}&target=#{target}&name=#{h(param.name)}">+</a>}
            opt_hidden << "</td><td></td></tr>\n"
          else
            html << %Q{<tr data-param="#{h(param.name)}"><td><label for="#{html_id}">}
            html << %Q{#{h(param.name)}</label></td>\n}
            html << %Q{<td class="param_link"><a id="remove_#{html_id}" }
            html << %Q{class="remove_parameter" rel="nofollow" href=}
            html << %Q{"/rules/clear_parameter?redir=1&id=#{id}&target=#{target}&#{h(param.name)}">-</a>}
            html << '</td>'
            html << "<td>#{param_html(html_id, name, param, pset[param])}"
            html << "</td></tr>\n"
          end
        end

        html << "</table>\n"

        unless opt_hidden.empty?
          html << "<hr>\n"
          html << "<div class=\"optional_parameters\" tabindex=\"0\"><table class=\"parameters\">\n"
          html << opt_hidden.join
          html << "</table></div>\n"
        end

        html
      end

      # Generates a table row for each Rule for the Automation Rules page.
      def self.rules_html
        # TODO: Move this into a templating system (e.g. erb)
        html = ''
        KncAction.rules.each do |id, rule|
          html << <<-HTML
            <tr data-rule="#{id}" id="rule_row_#{id}">
              <!-- FIXME: Forms within tables are not HTML compliant -->
              <!-- IE doesn't support form= attribute -->
              <form method="POST" action="/rules/set_rule" id="rule_form_#{id}" autocomplete="off">
              <input type="hidden" name="id" value="#{id}">
              <td class="id">
                #{id}
              </td>
              <td class="trigger">
                <div class="insetbox trigger">
                #{triggers_html rule.trigger}
                <hr>
                #{parameters_html rule.trigger, id, 'trigger'}
              </td>
              <td class="filter">
                <div class="insetbox condition">
                  #{conditions_html rule.condition}
                  <table class="parameters">
                    <tr>
                      <td><label for="edge_#{id}">Edge Triggered</label></td>
                      <td><input type="checkbox" id="edge_#{id}" name="param_filter_edge" value="true" #{rule.filter.edge ? 'checked' : ''}></td>
                    </tr>
                  </table>
                  <hr>
                  #{parameters_html rule.condition, id, 'condition'}
                </div>
              </td>
              <td class="action">
                <div class="insetbox true_action">
                  #{actions_html true, rule.true_action}
                  <hr>
                  #{parameters_html rule.true_action, id, 'true_action'}
                </div>
                <div class="insetbox false_action">
                  #{actions_html false, rule.false_action}
                  <hr>
                  #{parameters_html rule.false_action, id, 'false_action'}
                </div>
              </td>
              <td class="rule_buttons">
                <input type="submit" name="command" value="Copy">
                <input type="submit" name="command" value="Update">
                <input type="submit" name="command" value="Delete">
              </td>
            </form>
          </tr>
          HTML
        end

        html
      end
    end

    # TODO: Anti-CSRF, etc.
    EM.next_tick do
      KncRules.log "Initializing Automation Rule support"

      NL::KNC::ZoneWeb.add_route '/rules.html' do |response|
        response.status = 301
        response.headers['Location'] = '/rules'
      end

      NL::KNC::ZoneWeb.add_route '/rules/' do |response|
        response.status = 301
        response.headers['Location'] = '/rules'
      end

      NL::KNC::ZoneWeb.add_route '/rules' do |response|
        rules_html = File.read 'wwwdata/rules.html'
        response.content = rules_html.
          gsub('##HOSTNAME##', Socket.gethostname).
          gsub('##RULES##', KncRules.rules_html)
      end

      # List available triggers
      NL::KNC::ZoneWeb.add_route '/rules/triggers' do |response|
        response.content_type 'application/json; charset=utf-8'
        response.content = KncAction::Trigger.triggers.to_a.to_json
      end

      # List available conditions
      NL::KNC::ZoneWeb.add_route '/rules/conditions' do |response|
        response.content_type 'application/json; charset=utf-8'
        response.content = KncAction::Condition.conditions.to_a.to_json
      end

      # List available actions
      NL::KNC::ZoneWeb.add_route '/rules/actions' do |response|
        response.content_type 'application/json; charset=utf-8'
        response.content = KncAction::Action.actions.to_a.to_json
      end

      # List rules that have been created
      NL::KNC::ZoneWeb.add_route '/rules/rules' do |response|
        next unless accept_methods 'GET'

        response.content_type 'application/json; charset=utf-8'

        if @allvars.include? 'id'
          id = @allvars['id'].to_i
          rule = KncAction.rules[id]
          unless rule
            send400 "No Rule found for ID #{id}."
          else
            response.content = rule.to_json
          end
        else
          response.content = {:rules => KncAction.rules.values}.to_json
        end

        if response.status == 200 && @allvars['dl']
          response.headers['Content-Disposition'] = 'attachment; filename=rules.json'
        else
          @log_request = false
        end
      end

      # Replace or merge with new rules.
      NL::KNC::ZoneWeb.add_route '/rules/upload_rules' do |response|
        next unless accept_methods 'POST'

        bytes = @postvars['rules_file'] ? @postvars['rules_file'].length : 0
        filename = get_filename('rules_file') || ''
        data = @postvars['rules_file']

        response.content = html_header('Upload Automation Rules')
        response.content << '<h3>Upload Automation Rules</h3>'
        response.content << "<h4>Received \"#{h(filename)}\": #{bytes} bytes</h4>"

        unless bytes > 0
          response.content << '<h4>Rules file size must be greater than 0 bytes.</h4>'
          response.content = response.content
        else
          json = begin
                   JSON.parse data, {:symbolize_names => true}
                 rescue
                   nil
                 end

          unless json.is_a?(Hash) && json[:rules].is_a?(Array)
            response.content << '<h4>This does not appear to be a valid rules file.</h4>'
            response.status = 400
          else
            old_rules = KncAction.rules.values
            begin
              unless @allvars['merge']
                KncAction.clear_rules
              end
              KncAction.load_rules json[:rules]

              response.content << '<h4>Rules loaded successfully</h4>'
              response.headers['Refresh'] = '1; url=/rules'

            rescue => e
              if KncAction.rules.empty? && !old_rules.empty?
                KncAction.load_rules old_rules.map{|r|r.to_hash}
              end

              response.content << '<h4>Error loading automation rules</h4>'
              response.content << "<p>#{e.to_s.text_to_html}</p>"
              response.status = 400
            end
          end
        end

        response.content << html_footer
      end

      # Delete all rules
      NL::KNC::ZoneWeb.add_route '/rules/clear_rules' do |response|
        # TODO: User confirmation
        response.headers['Refresh'] = '1; url=/rules'
        response.content = html_header('Remove all automation rules')
        KncAction.clear_rules
        response.content << "<h3>All rules were removed.</h3>"
        response.content << html_footer
      end

      # Add a new empty rule.
      NL::KNC::ZoneWeb.add_route '/rules/add_rule' do |response|
        # TODO: POST only
        rule = KncAction.add_rule
        if @postvars['redir'] == '1'
          response.status = 302
          response.headers['Location'] = "/rules#rule_row_#{rule.id}"
        else
          response.content_type 'application/json; charset=utf-8'
          response.content = rule.to_json
        end
      end

      # Copy the rule with the given unique numeric ID.
      NL::KNC::ZoneWeb.add_route '/rules/copy_rule' do |response|
        # TODO: POST only
        id = get_allvar 'id', 'Rule ID'
        next unless id
        id = id.to_i

        rule = KncAction.copy_rule id
        response.content_type 'application/json; charset=utf-8'
        response.content = rule.to_json
      end

      # Delete a rule by its unique numeric ID.
      NL::KNC::ZoneWeb.add_route '/rules/del_rule' do |response|
        # TODO: POST only (or DELETE only?)
        response.content_type 'application/json; charset=utf-8'

        id = get_allvar 'id', 'Rule ID'
        next unless id
        id = id.to_i

        begin
          KncAction.delete_rule id
          response.content = { :deleted => id }.to_json
        rescue => e
          send400 e.to_s
        end
      end

      # Set the trigger type used by a rule.  An empty type removes the trigger.
      NL::KNC::ZoneWeb.add_route '/rules/set_trigger' do |response|
        # TODO: POST only
        id = get_allvar 'id', 'Rule ID'
        next unless id
        id = id.to_i

        type = get_allvar 'type', 'Trigger type'
        next unless type

        rule = KncAction.rules[id]
        unless rule
          send400 "No Rule found for ID #{id}."
          next
        end

        oldtrig = rule.trigger

        if type.length > 0
          trig = KncAction::Trigger.find_trigger type
          unless trig
            send400 "No Trigger found of the given type (#{type})."
            next
          end

          unless oldtrig && oldtrig.instance_of?(trig)
            rule.trigger = trig.new
            oldtrig.clean if oldtrig
          end
        elsif oldtrig
          rule.trigger = nil
          oldtrig.clean
        end

        response.content_type 'application/json; charset=utf-8'
        response.content = rule.to_json
      end

      # Set the condition type used by a rule's filter.
      NL::KNC::ZoneWeb.add_route '/rules/set_condition' do |response|
        # TODO: POST only
        id = get_allvar 'id', 'Rule ID'
        next unless id
        id = id.to_i

        type = get_allvar 'type', 'Trigger type'
        next unless type

        rule = KncAction.rules[id]
        unless rule
          send400 "No Rule found for ID #{id}."
          next
        end

        oldcond = rule.condition

        cond = KncAction::Condition.find_condition type
        unless cond
          send400 "No Condition found of the given type (#{type})."
          next
        end

        unless oldcond && oldcond.instance_of?(cond)
          rule.condition = cond.new
          oldcond.clean if oldcond
        end

        response.content_type 'application/json; charset=utf-8'
        response.content = rule.to_json
      end

      # Sets the action type used by a rule.  An empty type clears the
      # action.
      NL::KNC::ZoneWeb.add_route '/rules/set_action' do |response|
        # TODO: POST only
        id = get_allvar 'id', 'Rule ID'
        next unless id
        id = id.to_i

        type = get_allvar 'type', 'Trigger type'
        next unless type

        pass = get_allvar 'pass', 'Condition result (true or false)'
        next unless pass

        case pass
        when 'true'
          pass = true
        when 'false'
          pass = false
        else
          send400 'Condition result must be "true" or "false".'
          next
        end

        rule = KncAction.rules[id]
        unless rule
          send400 "No Rule found for ID #{id}."
          next
        end

        oldact = pass ? rule.true_action : rule.false_action

        type = @allvars['type']
        if type.length > 0
          act = KncAction::Action.find_action type
          unless act
            send400 "No Action found of the given type (#{type})."
            next
          end

          unless oldact && oldact.instance_of?(act)
            pass ? rule.true_action = act.new : rule.false_action = act.new
            oldact.clean if oldact
          end
        elsif oldact
          pass ? rule.true_action = nil : rule.false_action = nil
          oldact.clean
        end

        response.content_type 'application/json; charset=utf-8'
        response.content = rule.to_json
      end

      # Sets parameters on an Action, a Trigger, or a Condition.
      NL::KNC::ZoneWeb.add_route '/rules/set_parameter' do |response|
        # TODO: POST only
        id = get_allvar 'id', 'Rule ID'
        next unless id
        id = id.to_i

        target = get_allvar 'target', 'Parameter target'
        next unless target
        target = target.to_sym

        unless [:trigger, :filter, :condition, :true_action, :false_action].include? target
          send400 "Target must be one of 'trigger', 'filter', 'condition', 'true_action', or 'false_action'."
          next
        end

        rule = KncAction.rules[id]
        unless rule
          send400 "No Rule found for ID #{id}."
          next
        end

        if target == :filter
          edge = @allvars['edge'].to_s.downcase
          rule.filter.edge = true if edge == 'true'
          rule.filter.edge = false if edge == 'false'
          response.content_type 'application/json; charset=utf-8'
          response.content = rule.filter.to_json
          next
        end

        # The target strings are the same as the getter names on
        # KncAction::Rule, and each target (other than Filter) responds
        # to []=.
        obj = rule.send target
        unless obj
          send400 "The specified target (#{target}) is empty."
          next
        end

        errors = []
        @allvars.each do |key, value|
          next if key == 'id' || key == 'target'

          begin
            param = obj.find_parameter(key)
          rescue => e
            errors << "No such parameter #{key} on #{obj}."
            next
          end

          begin
            obj[param] = param.parse(value)
          rescue => e
            errors << "Unable to set #{key} on #{obj}: #{e}"
          end
        end

        if errors.empty?
          response.content_type 'application/json; charset=utf-8'
          response.content = obj.to_json
        else
          send400 errors.join("\n")
        end
      end

      # Sets the given optional parameter to its default value.
      NL::KNC::ZoneWeb.add_route '/rules/add_parameter' do |response|
        # TODO: POST form to set_rule instead to avoid data loss when HTML only?
        id = get_allvar 'id', 'Rule ID'
        next unless id
        id = id.to_i

        target = get_allvar 'target', 'Parameter target'
        next unless target
        target = target.to_sym

        key = get_allvar 'name', 'Parameter name'
        next unless key

        unless [:true_action, :false_action].include? target
          send400 "Parameter target must be one of 'true_action' or 'false_action'."
          next
        end

        rule = KncAction.rules[id]
        unless rule
          send400 "No Rule found for ID #{id}."
          next
        end

        obj = rule.send target
        unless obj
          send400 "The specified target (#{target}) is empty."
          next
        end

        begin
          param = obj.find_parameter(key)
        rescue => e
          send400 "No such parameter #{key} on #{obj}: #{e}"
          next
        end

        unless param.optional?
          send400 "Parameter #{key} is not optional.  Can only add optional parameters."
          next
        end

        obj[param] = param.default if obj[param].nil?

        if @allvars['redir'] == '1'
          response.status = 302
          response.headers['Location'] = "/rules#rule_row_#{rule.id}"
        else
          response.content_type 'application/json; charset=utf-8'
          response.content = obj.to_json
        end
      end

      # Clears a parameter on an Action, a Condition, or a Trigger.  Removes
      # optional parameters' values, sets non-optional parameters to their
      # default values.
      NL::KNC::ZoneWeb.add_route '/rules/clear_parameter' do |response|
        id = get_allvar 'id', 'Rule ID'
        next unless id
        id = id.to_i

        target = get_allvar 'target', 'Parameter target'
        next unless target
        target = target.to_sym

        unless [:trigger, :filter, :condition, :true_action, :false_action].include? target
          send400 "Parameter target must be one of 'trigger', 'filter', 'condition', 'true_action', or 'false_action'."
          next
        end

        rule = KncAction.rules[id]
        unless rule
          send400 "No Rule found for ID #{id}."
          next
        end

        if target == :filter
          if @allvars.include? 'edge'
            rule.filter.edge = true
          end
          response.content_type 'application/json; charset=utf-8'
          response.content = rule.filter.to_json
          next
        end

        # The target strings are the same as the getter names on
        # KncAction::Rule, and each target (other than Filter) responds
        # to []= and clear_parameter.
        obj = rule.send target
        unless obj
          send400 "The specified target (#{target}) is empty."
          next
        end

        errors = []
        @allvars.each do |key, value|
          next if key == 'id' || key == 'target' || key == 'redir'

          begin
            param = obj.find_parameter(key)
          rescue => e
            errors << "No such parameter #{key} on #{obj}."
            next
          end

          begin
            if param.optional?
              obj.clear_parameter param
            else
              obj[param] = param.default
            end
          rescue => e
            errors << "Unable to clear or reset #{key} on #{obj}: #{e}"
          end
        end

        if errors.empty?
          if @allvars['redir'] == '1'
            response.status = 302
            response.headers['Location'] = "/rules#rule_row_#{rule.id}"
          else
            response.content_type 'application/json; charset=utf-8'
            response.content = obj.to_json
          end
        else
          send400 errors.join("\n")
        end
      end

      # Fallback API for setting an entire rule at once without JavaScript.
      NL::KNC::ZoneWeb.add_route '/rules/set_rule' do |response|
        next unless accept_methods 'POST'

        id = get_postvar 'id', 'Rule ID'
        next unless id
        id = id.to_i

        action = get_postvar 'command', 'Action'
        next unless action

        rule = KncAction.rules[id]
        unless rule
          send400 "No Rule found for ID #{id}."
          next
        end

        if action != 'Update' && action != 'Delete' && action != 'Copy'
          send400 "Unsupported action #{h(action)}."
          next
        end

        if action == 'Delete'
          begin
            near_id = KncAction.nearest_id(id)
            KncAction.delete_rule id
            text = html_header('Delete Rule')
            text << '<h3>Delete Rule</h3>'
            text << "<h4>Rule #{id} deleted.</h3>"
            text << html_footer

            response.status = 302
            if near_id
              response.headers['Location'] = "/rules#rule_row_#{near_id}"
            else
              response.headers['Location'] = "/rules"
            end
            response.content = text
          rescue => e
            send400 e.to_s
          end
          next
        end

        if action == 'Copy'
          rule = KncAction.copy_rule id
          text = html_header 'Copy Rule'
          text << '<h3>Copy Rule</h3>'
          text << "<h4>Rule #{id} copied as #{rule.id}.</h4>"
          text << html_footer

          response.status = 302
          response.headers['Location'] = "/rules#rule_row_#{rule.id}"
          response.content = text
          next
        end

        # Sort variables to process param_* first so that there are no
        # invalid parameter errors generated by a change to a Trigger,
        # Condition, or Action type.
        vars = @postvars.sort_by {|k, v|
          k.start_with?('param_') ? "0#{k}" : "1#{k}"
        }
        rule.filter.edge = @postvars.include?('param_filter_edge')
        errors = []
        vars.each do |key, value|
          next if key == 'id' || key == 'command'

          if key.start_with?("param_")
            _, target, param = key.split('_', 3)
            if (target == 'true' || target == 'false' && param.start_with?('action'))
              target = "#{target}_action"
              param = param.split('_', 2)[1]
            end
            target = target.to_sym

            if target != :filter
              # TODO: Extract a method shared with /rules/set_parameter
              begin
                obj = rule.send target
                unless obj
                  errors << "The specified target (#{target}) is empty."
                  next
                end
                param = obj.find_parameter(param)

                val = param.parse(value)
                obj[param] = val if val != obj[param]
              rescue => e
                errors << "Error setting #{param} on #{target}: #{e}"
              end
            end
          elsif ['trigger', 'condition', 'true_action', 'false_action'].include?(key)
            # TODO: Extract methods to be shared by set_trigger, set_condition, and set_action
            case key
            when 'trigger'
              oldtrig = rule.trigger

              if value.empty?
                rule.trigger = nil
              else
                trig = KncAction::Trigger.find_trigger value
                if trig
                  rule.trigger = trig.new unless rule.trigger.instance_of?(trig)
                else
                  errors << "Unknown trigger type: #{value}"
                end
              end

              if oldtrig && oldtrig != rule.trigger
                oldtrig.clean
              end

            when 'condition'
              oldcond = rule.condition

              cond = KncAction::Condition.find_condition value
              if cond
                rule.condition = cond.new unless rule.condition.instance_of?(cond)
              else
                errors << "Unknown condition type: #{value}"
              end

              if oldcond && oldcond != rule.condition
                oldcond.clean
              end

            when 'true_action'
              oldact = rule.true_action

              if value.empty?
                rule.true_action = nil
              else
                act = KncAction::Action.find_action value
                if act
                  rule.true_action = act.new unless rule.true_action.instance_of?(act)
                else
                  errors << "Unknown action type: #{value}"
                end
              end

              if oldact && oldact != rule.true_action
                oldact.clean
              end

            when 'false_action'
              oldact = rule.false_action

              if value.empty?
                rule.false_action = nil
              else
                act = KncAction::Action.find_action value
                if act
                  rule.false_action = act.new unless rule.false_action.instance_of?(act)
                else
                  errors << "Unknown action type: #{value}"
                end
              end

              if oldact && oldact != rule.false_action
                oldact.clean
              end
            end
          else
            errors << "Unknown parameter: #{key}"
          end
        end

        if errors.empty?
          response.status = 302
          response.headers['Location'] = "/rules#rule_row_#{id}"
        else
          send400 errors.join("\n")
        end
      end
    end
  end
end

require_relative 'knc_action/knc_action'
require_relative 'knc_action/knc_trigger'
require_relative 'knc_action/knc_condition'
require_relative 'knc_action/knc_rule'
require_relative 'knc_action/knc_triggers'
