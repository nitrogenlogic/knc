# Philips Hue support for KNC
# (C)2013-2021 Mike Bourgeous

require 'nlhue'

module NL
  module KNC
    module KncHue
      include NL::KNC::KNCLog
      extend NL::KNC::KNCLog

      extend NL::KNC::HTMLEscape

      DEVICE_TYPE = 'Nitrogen Logic Depth Camera Controller'

      # Version of key-value pair API
      HUE_VERSION = 2

      NL::KNC::CONFIG[:hue] ||= {}
      NL::KNC::CONFIG[:hue][:enabled] ||= false

      # TODO: show registered but missing bridges in the bridge list in the web UI
      NL::KNC::CONFIG[:hue][:usernames] ||= {}

      @@update_cbs = {} # serial => cb_proc

      @@disco_cb = nil

      # Enables Hue support in the configuration and calls start_hue.
      def self.enable_hue
        NL::KNC::CONFIG[:hue][:enabled] = true
        start_hue unless NLHue::Disco.disco_started?
      end

      # Disables Hue support in the configuration and calls stop_hue.
      def self.disable_hue
        NL::KNC::CONFIG[:hue][:enabled] = false
        stop_hue
      end

      # Tries to find a username in the saved configuration for the given
      # bridge +serial+ (Symbol or String).
      def self.find_user(serial)
        if NL::KNC::CONFIG[:hue][:usernames].is_a?(Hash)
          user = NL::KNC::CONFIG[:hue][:usernames][serial.to_s]
          user ||= NL::KNC::CONFIG[:hue][:usernames][serial.to_sym]
        end
        user ||= NL::KNC::CONFIG[:hue][:username] # For legacy config compatibility
        user
      end

      # Stores the given +username+ for the given bridge +serial+ in the
      # saved configuration.
      def self.set_user(serial, username)
        NL::KNC::CONFIG[:hue][:usernames] ||= {}
        NL::KNC::CONFIG[:hue][:usernames][serial.to_sym] = username
      end

      # Initializes Hue support and starts periodic discovery of Hue bridges.
      def self.start_hue
        log "Starting Hue support"
        NL::KNC::EventLog.normal 'Starting Hue support.', 'Hue'

        if NL::KNC::CONFIG[:hue][:usernames] && !NL::KNC::CONFIG[:hue][:usernames].empty?
          disco_user = NL::KNC::CONFIG[:hue][:usernames]
        else
          disco_user = NL::KNC::CONFIG[:hue][:username]
        end
        NLHue::Disco.start_discovery(disco_user)

        @@disco_cb = NLHue::Disco.add_disco_callback do |event, param, msg|
          case event
          when :start
            log 'Hue discovery starting'

          when :add
            br = param
            log "Added Hue bridge #{br} with original username #{br.username}."
            NL::KNC::EventLog.normal "Bridge #{br.serial} added.", 'Hue'

            br.username ||= find_user(br.serial)

            @@update_cbs[br.serial] = br.add_update_callback do |status, result|
              if status
                set_user(br.serial, br.username)
              elsif !result.is_a?(NLHue::NotRegisteredError)
                log "Update failed on Hue bridge '#{br}': #{result}"
              end
            end

            br.subscribe(2)

          when :del
            br = param
            log "Removed Hue bridge #{br}."
            NL::KNC::EventLog.normal "Bridge #{br.serial} removed: #{msg}", 'Hue'

            br.remove_update_callback @@update_cbs.delete(br.serial)

          when :end
            log "Hue discovery completed (#{NLHue::Disco.bridges.size} bridges, #{param ? "" : "un"}changed)"
            NLHue::Disco.bridges.each do |br|
              errcount = NLHue::Disco.get_error_count(br.serial)
              misscount = NLHue::Disco.get_missing_count(br.serial);

              if errcount > 0
                log "Bridge #{br.serial} has #{errcount} update errors."
              end
              if misscount > 0
                log "Bridge #{br.serial} missing from #{misscount} discovery rounds."
              end
              if misscount > 0 || errcount > 0
                log "Bridge #{br.serial} is#{br.subscribed? ? '' : ' not'} subscribed."
              end
            end
          end
        end
      end

      # Cleans up Hue support and stops periodic discovery of Hue bridges.
      # All discovery callbacks will be removed.
      def self.stop_hue
        log "Stopping Hue support"
        NL::KNC::EventLog.normal 'Stopping Hue support.', 'Hue'
        NLHue::Disco.stop_discovery
        NLHue::Disco.remove_disco_callback @@disco_cb
      end

      # Returns an array of the bridges known to the NLHue discovery process.
      def self.bridges
        NLHue::Disco.bridges
      end

      # Returns the given bridge, if it exists.
      def self.get_bridge serial
        NLHue::Disco.get_bridge serial
      end

      # Raises an exception if the given serial number is not in the correct
      # format for a Hue bridge serial number.
      def self.check_serial serial
        raise 'Serial number not specified.' unless serial.is_a?(String)
        raise "Serial number #{serial} invalid." unless serial =~ /^[0-9a-f]{12}$/i
        serial.downcase
      end

      # Finds a bridge with the given serial, or the first bridge if the serial number is blank.
      def self.find_bridge(serial)
        if (serial.nil? || serial.empty?) && KncHue.bridges.count > 0
          bridges.first
        else
          get_bridge(check_serial(serial))
        end
      end

      def self.register bridge, &block
        raise 'A block must be given to register().' unless block_given?

        if bridge.registered?
          yield true, 'Already registered'
          return
        end

        bridge.register DEVICE_TYPE do |status, result|
          if status
            bridge.update do |upstat, upres|
              unless upstat
                log "Error updating after registering: #{upres}"
              else
                NL::KNC::EventLog.normal "Registered with bridge #{bridge.serial}", 'Hue'
                set_user(bridge.serial, bridge.username)
              end
              yield status, result
            end
          else
            yield status, result
          end
        end
      end

      def self.unregister bridge, &block
        raise 'A block must be given to register().' unless block_given?

        bridge.unregister do |status, result|
          NL::KNC::EventLog.normal "Unregistered from bridge #{bridge.serial}", 'Hue' if status
          yield status, result
        end
      end



      ############### HTML #######################

      # TODO: Use a templating language that compiles to Ruby (like ERB or Slim)

      def self.disco_html
        scanning = NLHue::Disco.disco_running?

        return <<-HTML
          <span class="hue_disco_running"
            #{scanning ? '' : 'style="display: none'}">
            <img class="loading_icon" src="/images/loading_15x15.gif">
            Scanning...
          </span>
          <span class="hue_disco_idle"
            #{scanning ? 'style="display: none' : ''}">
            <a href="/settings/hue/disco" class="hue_disco_link">Scan for bridges</a>
          </span>
        HTML
      end

      def self.bridges_html
        unless $hue_ok
          return <<-HTML
            <tbody>
              <tr><td colspan="5" class="error_message">
                 Error activating Hue support: #{$hue_error}.<br>
                 Check for firmware updates, contact Nitrogen Logic.
              </td></tr>
            </tbody>
          HTML
        end

        html = ''
        NLHue::Disco.bridges.each do |br|
          # All values are escaped, even if they wouldn't normally contain
          # dangerous characters, to protect against the extremely
          # unlikely case of a malicious device mimicking a bridge.
          name = h(br.name) || '&mdash;'
          addr = h(br.addr) || '&mdash;'
          serial = h(br.serial) || '&mdash;'
          lights = br.registered? ? br.num_lights : '&mdash;'

          uperror = NLHue::Disco.get_error_count(br.serial) > 0
          dtimeout = NLHue::Disco.get_missing_count(br.serial) > (br.subscribed? ? 4 : 1)

          html << <<-HTML
            <tbody class="hue_bridge" data-serial="#{serial}">
            <tr class="hue_bridge_row #{br.registered? ? 'detail_visible' : ''}"
              data-serial="#{serial}" data-registered="#{br.registered?}"
              data-disco-timeout="#{dtimeout}" data-update-error="#{uperror}"
              data-scan-active=#{br.scan_active?}>
            <td class="hue_bridge_name">
            <div>#{name}<div class="hue_bridge_name_icons">
            <img class="warning_icon" src="/images/warning_15x15.png"
              title="Error updating bridge information."
              alt="(error)">
            <img class="timeout_icon" src="/images/timeout_15x15.png"
              title="Bridge stopped responding to discovery scans."
              alt="(timeout)">
            </div></div>
            </td>
            <td class="hue_bridge_addr">#{addr}</td>
            <td class="hue_bridge_serial">#{serial}</td>
            <td class="hue_bridge_lights">#{lights}</td>
            <td class="hue_bridge_action">
              <a href="javascript:" class="hue_unregister_link" data-serial="#{serial}">Unregister</a>
              <a href="javascript:" class="hue_register_link" data-serial="#{serial}">Register</a>
            </td>
          HTML

          html << "</tr>"

          html << <<-HTML
            <tr #{br.registered? ? '' : 'style="display: none"'}
                class="hue_bridge_detail" data-serial="#{serial}">
            <td colspan="5">
            <div>
            <h5>Lights</h5>

            <div class="hue_scan_active">
              <img class="loading_icon" src="/images/loading_15x15.gif">
              Scanning for new lights...
              <a href="javascript:" class="hue_scan_link">Restart scan</a>
            </div>
            <div class="hue_scan_inactive">
              <a href="javascript:" class="hue_scan_link">Scan for new lights</a>
            </div>

            #{lights_html br}
            <h5>Scenes</h5>
            #{scenes_html br}
            <h5>Groups</h5>
            #{groups_html br}
            </div>
            </td>
            </tr>
            </tbody>
          HTML
        end

        return html
      end

      def self.lights_html bridge
        html = <<-HTML
          <table class="hue hue_lights subsection_table knc_table">
          <thead>
          <tr>
          <th class="hue_light_id">ID</th>
          <th class="hue_light_name">Name</th>
          <th class="hue_light_on">On</th>
          <th class="hue_light_bri" title="0-255">Bright</th>
          <th class="hue_light_ct" title="154-500 mireds">Temp</th>
          <th class="hue_light_x" title="0.0-1.0">X</th>
          <th class="hue_light_y" title="0.0-1.0">Y</th>
          <th class="hue_light_hue" title="0.0-360.0">Hue</th>
          <th class="hue_light_sat" title="0-255">Sat</th>
          <th class="hue_light_preset">Preset</th>
          </tr>
          </thead>
          <tbody>
        HTML

        bridge.lights.each_value do |light|
          ct = light.ct
          temp = 1000000 / (ct == 0 ? 369 : ct)
          serial = h(bridge.serial) || '&mdash;'
          name = h(light.name) || light.id
          type = h(light.type) || '&mdash;'

          # TODO: Show light color, use a color selector

          html << <<-HTML
            <form class="hue_light_form" data-id="#{light.id}" method="POST"
                  action="/settings/hue/light" novalidate>

            <input type="hidden" name="serial" value="#{serial}"></input>
            <input type="hidden" name="id" value="#{light.id}"></input>
            <input type="hidden" name="redir" value="1"></input>
            <tr class="hue_light_row" data-id="#{light.id}" data-colormode="#{light.colormode}">
            <td class="hue_light_id" title="#{type}">#{light.id}</td>
            <td class="hue_light_name">#{name}</td>
            <td class="hue_light_on" data-on="#{light.on?}"><select name="on"><option>true</option><option>false</option></select></td>
            <td class="hue_light_bri" data-bri="#{light.bri}"><input name="bri" type="number" min="0" max="255" step="1" value="#{light.bri}"></input></td>
            <td class="hue_light_ct" data-ct="#{ct}" title="#{temp.to_i}K"><input name="ct" type="number" min="153" max="500" step="1" value="#{ct}"></input></td>
            <td class="hue_light_x" data-x="#{light.xy[0]}"><input name="x" type="number" min="0.0" max="1.0" step="any" value="#{light.xy[0].round(4)}"></input></td>
            <td class="hue_light_y" data-y="#{light.xy[1]}"><input name="y" type="number" min="0.0" max="1.0" step="any" value="#{light.xy[1].round(4)}"></input></td>
            <td class="hue_light_hue" data-hue="#{light.hue}"><input name="hue" type="number" min="0" max="359.9" step="0.1" value="#{"%.1f" % light.hue.round(1)}"></input></td>
            <td class="hue_light_sat" data-sat="#{light.sat}"><input name="sat" type="number" min="0" max="255" step="1" value="#{light.sat}"></input></td>
            <td class="hue_light_preset">
            <!-- Presets only available when JavaScript is enabled -->
            <input type="submit" tabindex="-1"></input>
            </td>
            </tr>
            </form>
          HTML
        end

        html << "</tbody></table>"

        html
      end

      def self.groups_html bridge
        html = <<-HTML
          <table class="hue hue_groups subsection_table knc_table">
          <thead>
          <tr>
          <th class="hue_group_id">ID</th>
          <th class="hue_group_name">Name</th>
          <th class="hue_group_lights">Lights</th>
          </tr>
          </thead>
          <tbody>
        HTML

        bridge.groups.each_value do |group|
          name = h(group.name) || group.id

          html << <<-HTML
            <tr class="hue_group_row" data-id="#{group.id}">
            <td class="hue_group_id">#{group.id}</td>
            <td class="hue_group_name">#{name}</td>
            <td class="hue_group_lights">#{group.light_ids.join(', ')}</td>
            #{group.id == 0 ? '<td></td>' : '<td class="hue_group_delete">Delete</td>'}
            </tr>
          HTML
        end

        html << "</tbody></table>"

        html
      end

      def self.scenes_html bridge
        html = <<-HTML
          <table class="hue hue_scenes subsection_table knc_table">
          <thead>
          <tr>
          <th class="hue_scene_id">ID</th>
          <th class="hue_scene_name">Name</th>
          <th class="hue_scene_lights">Lights</th>
          </tr>
          </thead>
          <tbody>
        HTML

        bridge.scenes.each_value do |scene|
          id = h(scene.id)
          name = h(scene.name) || id

          html << <<-HTML
            <tr class="hue_scene_row" data-id="#{h scene.id}">
            <td class="hue_scene_id">#{h scene.id}</td>
            <td class="hue_scene_name">#{name}</td>
            <td class="hue_scene_lights">#{scene.light_ids.join(', ')}</td>
            <td class="hue_scene_delete">Delete</td>
            </tr>
          HTML
        end

        html << "</tbody></table>"

        html
      end
    end

    module KncHue
      # Base class for all Hue actions.  Handles bridge parameter.
      class HueAction < KncAction::Action
        # Returns a list of available bridges suitable for use in a
        # Parameter's range.
        def self.available_bridges
          bridges = {nil=>nil, '0'=>'[No Bridge]'}
          bridges.merge! Hash[KncHue.bridges.select{|br|
            br.registered?
          }.map{|br|
            [br.serial, br.name]
          }]
        end

        @@bridge = KncAction::Parameter.new(
          "Bridge",
          String,
          available_bridges,
          '[No Bridge]'
        )

        NLHue::Disco.add_disco_callback do |event, param, msg|
          if (event == :end || event == :add || event == :del) && param
            @@bridge.range = available_bridges
          end
        end

        NLHue::Bridge.add_bridge_callback do |bridge, status|
          @@bridge.range = available_bridges
        end

        def initialize
          add_parameter @@bridge

          @dsc_cb = NLHue::Disco.add_disco_callback do |event, param, msg|
            if param && (event == :add || event == :del || event == :end)
              disco_cb(event, param, msg)
            end
          end

          @br_cb = NLHue::Bridge.add_bridge_callback do |bridge, param|
            bridge_cb(bridge, param) if param
          end
        end

        def clean
          NLHue::Disco.remove_disco_callback @dsc_cb
          NLHue::Bridge.remove_bridge_callback @br_cb
          super
        end

        private
        # Tries to find a Hue bridge matching the current value of the
        # Bridge parameter.  Returns nil if there is no match.
        def get_bridge
          KncHue.get_bridge self[@@bridge]
        end

        # Called when a bridge discovery event occurs.  Subclasses
        # should override and call super.
        def disco_cb(event, param, msg)
        end

        # Called when a bridge update event occurs.  Subclasses should
        # override and call super.
        def bridge_cb(bridge, status)
        end
      end

      # Base class for HueSetLightAction and HueSetGroupAction.
      class HueSetTargetAction < HueAction
        @@on = KncAction::Parameter.new(
          "On",
          :boolean,
          nil,
          true,
          false,
          true
        )
        @@bri = KncAction::Parameter.new(
          "Brightness",
          Integer,
          0..255,
          255,
          true,
          true
        )
        @@ct = KncAction::Parameter.new(
          "Temp. (mireds)",
          Integer,
          154..500,
          350,
          true,
          true
        )
        @@x = KncAction::Parameter.new(
          "x (CIE 1931)",
          Numeric,
          0..1,
          0.447460,
          false,
          true
        )
        @@y = KncAction::Parameter.new(
          "y (CIE 1931)",
          Numeric,
          0..1,
          0.407407,
          false,
          true
        )
        @@hue = KncAction::Parameter.new(
          "Hue",
          Numeric,
          0..360,
          nil,
          false,
          true
        )
        @@sat = KncAction::Parameter.new(
          "Saturation",
          Numeric,
          0..255,
          255,
          false,
          true
        )
        @@transitiontime = KncAction::Parameter.new(
          "Transition Time",
          Numeric,
          0..6553.5,
          0.4,
          false,
          true
        )
        @@alert = KncAction::Parameter.new(
          "Alert",
          String,
          {'none' => 'None', 'select' => 'Flash Once', 'lselect' => 'Flash for 30s'},
          nil,
          false,
          true
        )
        @@effect = KncAction::Parameter.new(
          "Effect",
          String,
          {'none' => 'None', 'colorloop' => 'Color Loop'},
          nil,
          false,
          true
        )

        # Adds common parameters to the action.  Subclasses must call
        # this before doing their own initialization.
        # target_type - Word used to describe targets (e.g. 'Light' or 'Group')
        def initialize target_type
          raise 'target_type must be a String.' unless target_type.is_a?(String)
          @type = target_type

          super()

          add_parameter @@on
          add_parameter @@bri
          add_parameter @@ct
          add_parameter @@x
          add_parameter @@y
          add_parameter @@hue
          add_parameter @@sat
          add_parameter @@transitiontime
          add_parameter @@alert
          add_parameter @@effect

          @targets = [] # Parameters for Light IDs or Group IDs
          @targets[0] = add_parameter KncAction::Parameter.new(
            @type,
            Integer,
            available_targets,
            0
          )

          update_params
        end

        def disco_cb(event, param, msg)
          update_range
          super
        end

        def bridge_cb(bridge, status)
          update_range
          super
        end

        def []= param, value
          super param, value
          if param == @@bridge
            update_range
          elsif param == @targets.last
            update_params
          end
        end

        def clear_parameter param
          super param
          if @targets.include?(param)
            update_params
          end
        end

        # Returns a list of available targets (e.g. lights or groups)
        # on the current bridge.  Subclasses must override without
        # calling the superclass method.
        def available_targets
          raise NotImplementedError.new 'Subclasses must override available_targets.'
        end

        # Updates the ranges of target parameters when the bridge is
        # changed.
        def update_range
          targets = available_targets
          @targets.each do |param|
            param.range = targets
          end
        end

        # Adds/removes/shifts parameters in response to parameters
        # being added or cleared, ensuring there is exactly one target
        # at the end of the list of parameters with no value set.
        def update_params
          # Shift parameters and count nils
          nil_count = 0
          read = 0
          write = 0
          while read < @targets.size
            unless @paramvals[@targets[read]].nil?
              @paramvals[@targets[write]] = @paramvals[@targets[read]] if write != read
              write += 1
            else
              nil_count += 1
            end
            read += 1
          end
          while write < @targets.size
            @paramvals.delete @targets[write]
            write += 1
          end

          # Add an empty target parameter if necessary
          if nil_count == 0
            @targets[@targets.size] = add_parameter KncAction::Parameter.new(
              "#{@type} #{@targets.size + 1}",
              Integer,
              available_targets,
              0,
              false,
              true
            )
          end

          # Delete excess empty slots
          while nil_count > 1
            remove_parameter @targets.pop
            nil_count -= 1
          end
        end

        # Fires an event to all targets set on this object.
        def fire data
          log "Firing hue set #{@type} event" # XXX
          bridge = get_bridge
          if bridge
            log "Bridge found, firing #{@type}s" # XXX
            @targets.each do |param|
              id = self[param]
              fire_target bridge, id unless id.nil?
            end
          end
        end

        # Fires an event for the given bridge and target ID.  Uses
        # #get_target to retrieve the target (e.g. Light or Group) from
        # the bridge.
        def fire_target bridge, id
          log "Firing #{@type} #{id}" # XXX
          target = get_target bridge, id
          if target
            log "#{@type} found" # XXX

            target.defer

            # TODO: Some kind of map to simplify this
            if @paramvals.include?(@@on)
              target.on = self[@@on]
            end
            if @paramvals.include?(@@bri)
              target.bri = self[@@bri]
            end
            if @paramvals.include?(@@ct)
              target.ct = self[@@ct]
            end
            if @paramvals.include?(@@x)
              target.x = self[@@x]
            end
            if @paramvals.include?(@@y)
              target.y = self[@@y]
            end
            if @paramvals.include?(@@hue)
              target.hue = self[@@hue]
            end
            if @paramvals.include?(@@sat)
              target.sat = self[@@sat]
            end
            if @paramvals.include?(@@transitiontime)
              target.transitiontime = (self[@@transitiontime] * 10).to_i
            end
            if @paramvals.include?(@@alert)
              target.alert = self[@@alert]
            end
            if @paramvals.include?(@@effect)
              target.effect = self[@@effect]
            end

            log "Sending to #{@type}" # XXX
            target.submit do |status, result|
              log "#{@type} set result: #{status}, #{result}" # XXX
              if result.is_a?(Exception) && !result.message.include?('Device is set to off')
                log_e result, "Error setting #{@type} #{id} in a Set #{@type} action"
              end
            end
          end
        end

        private
        # Returns the target on the given bridge having the given ID.
        # Subclasses must override without calling the superclass
        # method.
        def get_target bridge, id
          raise NotImplementedError.new 'Subclasses must override get_target.'
        end
      end

      # An Action that changes one or more lights on a Hue bridge.
      class HueSetLightAction < HueSetTargetAction
        register

        def initialize
          super 'Light'
        end

        # Returns a Hash of lights available for control by this
        # HueSetLightAction, suitable for use as a Parameter's range.
        def available_targets
          lights = {nil=>nil, 0 => '0 - [No Light]'}
          bridge = get_bridge
          if bridge
            lights.merge! Hash[bridge.lights.values.map{|light|
              [light.id, "#{light.id} - #{light.name}"]
            }]
          end
          lights
        end

        private
        def get_target bridge, id
          bridge.lights[id]
        end
      end

      # An Action that changes one or more groups on a Hue bridge.
      class HueSetGroupAction < HueSetTargetAction
        register

        def initialize
          super 'Group'
        end

        # Returns a Hash of groups available for control by this
        # HueSetGroupAction, suitable for use as a Parameter's range.
        def available_targets
          groups = {nil=>nil, 0 => 'Lightset 0'}
          bridge = get_bridge
          if bridge
            groups.merge! Hash[bridge.groups.map{|id, group|
              [group.id, "#{group.id} - #{group.name} (#{group.lights.size} lights)"]
            }]
          end
          groups
        end

        private
        def get_target bridge, id
          bridge.groups[id]
        end
      end

      # An Action that recalls a scene on a Hue bridge.
      class HueRecallSceneAction < HueAction
        register

        def initialize
          super

          @scene = KncAction::Parameter.new(
            'Scene',
            String,
            available_scenes
          )
          add_parameter(@scene)
        end

        def disco_cb(event, param, msg)
          update_range
          super
        end

        def bridge_cb(bridge, status)
          update_range
          super
        end

        def update_range
          @scene.range = available_scenes
        end

        # TODO: Merge identical copies of this method in other classes
        def []= param, value
          super param, value
          if param == @@bridge
            update_range
          end
        end

        def available_scenes
          scenes = {nil => nil}

          bridge = get_bridge
          if bridge
            scenes.merge! Hash[bridge.scenes.map{|id, scene|
              [id, "#{scene.name} (#{id})"]
            }]
          end

          scenes
        end

        def fire data
          log "Firing hue recall scene event" # XXX
          bridge = get_bridge
          if bridge
            log "Bridge found, recalling scene " # XXX

            id = self[@scene]
            scene = bridge.scenes[id]
            if scene
              @warning_sent = false
              scene.recall
            elsif !@warning_sent && id && id.length > 0
              @warning_sent = true
              NL::KNC::EventLog.warning "Scene #{id.inspect} not found on bridge #{bridge.serial}", 'Hue'
            end
          end
        end

      end


      # An Action that increments or decrements one or more parameters on one
      # or more lights on a Hue bridge.
      # TODO: This class shares a lot of code with HueSetTargetAction.  Find
      # a way to reduce the duplication.
      class HueIncrementLightAction < HueAction
        register

        @@sync = KncAction::Parameter.new(
          "Synchronize",
          :boolean
        )

        # TODO: Optional wraparound

        @@on = KncAction::Parameter.new(
          "On (toggle)",
          :boolean,
          nil,
          true,
          false,
          true
        )
        @@bri = KncAction::Parameter.new(
          "Brightness",
          Integer,
          -255..255,
          25,
          true,
          true
        )
        @@ct = KncAction::Parameter.new(
          "Temp. (mireds)",
          Integer,
          -350..350,
          25,
          true,
          true
        )
        @@x = KncAction::Parameter.new(
          "x (CIE 1931)",
          Numeric,
          -1..1,
          0.1,
          false,
          true
        )
        @@y = KncAction::Parameter.new(
          "y (CIE 1931)",
          Numeric,
          -1..1,
          0.1,
          false,
          true
        )
        @@hue = KncAction::Parameter.new(
          "Hue",
          Numeric,
          -360..360,
          30,
          false,
          true
        )
        @@sat = KncAction::Parameter.new(
          "Saturation",
          Numeric,
          -255..255,
          25,
          false,
          true
        )
        @@transitiontime = KncAction::Parameter.new(
          "Transition Time",
          Numeric,
          0..6553.5,
          0.4,
          false,
          true
        )

        def initialize
          super

          add_parameter @@sync

          add_parameter @@on
          add_parameter @@bri
          add_parameter @@ct
          add_parameter @@x
          add_parameter @@y
          add_parameter @@hue
          add_parameter @@sat
          add_parameter @@transitiontime

          @targets = [] # Parameters for Light IDs
          @targets[0] = add_parameter KncAction::Parameter.new(
            'Light',
            Integer,
            available_targets,
            0
          )

          @sync_state = {} # Values for synchronization

          update_params
        end

        def disco_cb(event, param, msg)
          update_range
        end

        def bridge_cb(event, status)
          update_range
        end

        def []= param, value
          super param, value
          if param == @@bridge
            update_range
          elsif param == @targets.last
            update_params
          end
        end

        def clear_parameter param
          super param
          if @targets.include?(param)
            update_params
          end
        end

        # Updates the ranges of target parameters when the bridge is
        # changed.
        def update_range
          targets = available_targets
          @targets.each do |param|
            param.range = targets
          end
        end

        # Adds/removes/shifts parameters in response to parameters
        # being added or cleared, ensuring there is exactly one target
        # at the end of the list of parameters with no value set.
        def update_params
          # Shift parameters and count nils
          nil_count = 0
          read = 0
          write = 0
          while read < @targets.size
            unless @paramvals[@targets[read]].nil?
              @paramvals[@targets[write]] = @paramvals[@targets[read]] if write != read
              write += 1
            else
              nil_count += 1
            end
            read += 1
          end
          while write < @targets.size
            @paramvals.delete @targets[write]
            write += 1
          end

          # Add an empty target parameter if necessary
          if nil_count == 0
            @targets[@targets.size] = add_parameter KncAction::Parameter.new(
              "Light #{@targets.size + 1}",
              Integer,
              available_targets,
              0,
              false,
              true
            )
          end

          # Delete excess empty slots
          while nil_count > 1
            remove_parameter @targets.pop
            nil_count -= 1
          end
        end

        # Fires an event to all targets set on this object.
        def fire data
          log "Firing hue increment light event" # XXX

          bridge = get_bridge
          if bridge
            log "Bridge found, firing incremented lights" # XXX

            if self[@@sync]
              # Synchronize all targets' state with the first extant target
              target = nil
              @targets.each do |param|
                target = get_target bridge, self[param]
                break if target
              end

              if target
                @@sync_state = target.state

                @@sync_state[:on] = !@@sync_state[:on] if self[@@on]
                @@sync_state[:bri] += self[@@bri] if self[@@bri]
                @@sync_state[:ct] += self[@@ct] if self[@@ct]
                @@sync_state[:x] += self[@@x] if self[@@x]
                @@sync_state[:y] += self[@@y] if self[@@y]
                @@sync_state[:hue] += self[@@hue] if self[@@hue]
                @@sync_state[:sat] += self[@@sat] if self[@@sat]
              end
            end

            @targets.each do |param|
              id = self[param]
              fire_target bridge, id unless id.nil?
            end
          end
        end

        # Fires an event for the given bridge and target ID.  Uses
        # #get_target to retrieve the target (e.g. Light or Group) from
        # the bridge.
        def fire_target bridge, id
          log "Firing incremented light #{id}" # XXX
          target = get_target bridge, id
          if target
            log "Light #{id} found for incrementing" # XXX

            target.defer

            # TODO: Some kind of map to simplify this
            if self[@@sync]
              if @paramvals.include?(@@on) && self[@@on]
                target.on = @@sync_state[:on]
              end
              if @paramvals.include?(@@bri)
                target.bri = @@sync_state[:bri]
              end
              if @paramvals.include?(@@ct)
                target.ct = @@sync_state[:ct]
              end
              if @paramvals.include?(@@x)
                target.x = @@sync_state[:x]
              end
              if @paramvals.include?(@@y)
                target.y = @@sync_state[:y]
              end
              if @paramvals.include?(@@hue)
                target.hue = @@sync_state[:hue]
              end
              if @paramvals.include?(@@sat)
                target.sat = @@sync_state[:sat]
              end
            else
              if @paramvals.include?(@@on) && self[@@on]
                target.on = !target.on?
              end
              if @paramvals.include?(@@bri)
                target.bri = target.bri + self[@@bri]
              end
              if @paramvals.include?(@@ct)
                target.ct = target.ct + self[@@ct]
              end
              if @paramvals.include?(@@x)
                target.x = target.x + self[@@x]
              end
              if @paramvals.include?(@@y)
                target.y = target.y + self[@@y]
              end
              if @paramvals.include?(@@hue)
                target.hue = target.hue + self[@@hue]
              end
              if @paramvals.include?(@@sat)
                target.sat = target.sat + self[@@sat]
              end
            end

            if @paramvals.include?(@@transitiontime)
              target.transitiontime = (self[@@transitiontime] * 10).to_i
            end

            log "Sending to incremented light #{id}" # XXX
            target.submit do |status, result|
              log "Light #{id} increment result: #{status}, #{result}" # XXX
              if result.is_a?(Exception) && !result.message.include?('Device is set to off')
                log_e result, "Error setting light #{id} in an increment light action"
              end
            end
          end
        end

        # Returns a Hash of lights available for control by this
        # HueIncrementLightAction, suitable for use as a Parameter's range.
        def available_targets
          lights = {nil=>nil, 0 => '0 - [No Light]'}
          bridge = get_bridge
          if bridge
            lights.merge! Hash[bridge.lights.map{|id, light|
              [light.id, "#{light.id} - #{light.name}"]
            }]
          end
          lights
        end

        private
        def get_target bridge, id
          bridge.lights[id]
        end
      end

    end

    EM.next_tick do
      NL::KNC::ZoneWeb.add_route '/settings/hue' do |response|
        begin
          if @allvars.include? 'enabled'
            @allvars['enabled'] == 'true' ? KncHue.enable_hue : KncHue.disable_hue
          end
          if @allvars.include? 'redir'
            response.status = 302
            response.headers['Location'] = '/settings'
          else
            response.content_type 'application/json; charset=utf-8'
            response.headers['Cache-Control'] = 'no-cache'
            response.headers['Pragma'] = 'no-cache'
            response.content = "{\"enabled\":#{NL::KNC::CONFIG[:hue][:enabled]},"
            response.content << "\"discovery\":#{NLHue::Disco.disco_running?},"
            response.content << "\"bridges\":[#{KncHue.bridges.map(){|br|
              h = br.to_h
              h[:update_error] = NLHue::Disco.get_error_count(br.serial) > 0
              h[:disco_timeout] =
                NLHue::Disco.get_missing_count(br.serial) > (br.subscribed? ? 4 : 1)
              h.to_json
            }.join(',')}]}"
            @log_request = false
          end
        rescue Exception => e
          response.status = 500
          log_e e, @http_request_uri
        end
      end

      # Sends a summary key-value pair line followed by a key-value pair line for each bridge
      NL::KNC::ZoneWeb.add_route '/settings/hue/status.kvp' do |response|
        begin
          response.content_type 'text/plain; charset=utf-8'
          response.content = {
            version: KncHue::HUE_VERSION,
            enabled: NL::KNC::CONFIG[:hue][:enabled],
            discovery: NLHue::Disco.disco_running?,
            bridges: KncHue.bridges.count
          }.to_kvp

          bridges = KncHue.bridges.sort_by(&:serial).map{|br|
            {
              addr: br.addr,
              serial: br.serial,
              name: br.name || '',
              verified: br.verified?,
              online: br.updated?,
              registered: br.registered?,
              scan_active: br.scan_active?,
              subscribed: br.subscribed?,
              update_error: NLHue::Disco.get_error_count(br.serial) > 0,
              disco_timeout: NLHue::Disco.get_missing_count(br.serial) > (br.subscribed? ? 4 : 1),
              lights: br.num_lights,
              groups: br.num_groups,
              scenes: br.num_scenes,
            }.to_kvp
          }.join("\n\t")

          unless bridges.length == 0
            response.content << "\n\t"
            response.content << bridges
          end

          @log_request = false
        rescue Exception => e
          response.status = 500
          log_e e, @http_request_uri
        end
      end

      NL::KNC::ZoneWeb.add_route ['/settings/hue/lights.kvp', '/settings/hue/groups.kvp'] do |response|
        begin
          response.content_type 'text/plain; charset=utf-8'

          # Defaults to bridge with lowest serial number if no serial number is specified
          serial = @allvars['serial']
          bridge = KncHue.find_bridge serial
          raise "No matching bridge found for #{serial.inspect}." unless bridge

          ids = @allvars['id[]'] || Array(@allvars['id'])
          ids = ids.map{|id| id.to_i}

          if @http_request_uri.end_with?('/groups.kvp')
            target = :groups
          else
            target = :lights
          end

          results = bridge.send(target)
          results.select!{|id, v| ids.include?(id)} unless ids.empty?
          response.content = results.map{|k, t|
            h = t.to_h
            h.merge!(h['state'] || h['action'] || {})
            h['x'], h['y'] = h['xy']
            h['hue'] &&= [359, (h['hue'] * 360.0 / 65535.0).round].min
            h['id'] = k.to_i
            h.delete('lights')
            h.delete('action')
            h.delete('state')
            h.delete('pointsymbol')
            h.delete('xy')
            h.to_kvp
          }.join("\n")
        rescue Exception => e
          response.status = 500
          response.content = e.message
          log_e e, @http_request_uri
          @send_response = true
        end
      end

      NL::KNC::ZoneWeb.add_route '/settings/hue/debug' do |response|
        begin
          response.content_type 'text/plain; charset=utf-8'

          requests = {} # Request times
          cb = NLHue::RequestQueue.add_debug_callback do |id, type, category, host, verb, path, content_type, data, cb_resp|
            requests[id] ||= Time.now

            response.chunk "Request #{id} #{type} (#{category}): #{verb} #{path} #{data} "
            response.chunk "(#{"%.02f" % (1000 * (Time.now - requests[id]))}ms)\n"
            if cb_resp.is_a?(Hash)
              # TODO: Content type (need to scan headers)
              response.chunk "\tResponse #{id}: "
              response.chunk "#{cb_resp[:content]}\n\n"
            end

            response.send_body

            requests.delete(id) if type == :success || type == :error
          end

          timeout = (@allvars['timeout'] || 300).to_i
          EM.add_timer(timeout) do
            NLHue::RequestQueue.remove_debug_callback(cb)

            response.chunk "CLOSING CONNECTION AFTER #{timeout}s".center(72, '-')
            response.chunk "\n"

            response.send_body
            response.send_trailer
            response.close_connection_after_writing

            requests.clear
            requests = nil
          end

          response.chunk "Hue Bridge Requests".center(72)
          response.chunk "\n"
          response.chunk '-' * 72
          response.chunk "\nLogging requests for #{timeout} seconds.\n\n"
          response.send_headers
          response.send_body

          @send_response = false
        rescue Exception => e
          response.status = 500
          log_e e, @http_request_uri
        end
      end

      # Deletes a scene.  Pass the scene name/ID in the scene parameter.
      NL::KNC::ZoneWeb.add_route ['/settings/hue/scene'] do |response|
        begin
          if @http_request_method != 'DELETE'
            response.status = 302
            response.headers['Location'] = '/settings'
          else
            # TODO: Move common serial/bridge processing into a shared preamble/helper
            serial = @allvars['serial']
            bridge = KncHue.find_bridge serial
            raise "No matching bridge found for #{serial}." unless bridge

            scene = @allvars['scene']
            scene = bridge.find_scene(@allvars['scene'])
            raise "Scene #{scene} not found" unless scene

            log "Deleting scene #{scene.id} on bridge #{bridge.serial}"

            bridge.delete_scene(scene) do |status, result|
              response.status = status ? 200 : 500 # Is there a better error code available?

              # TODO: Find some way to consolidate and clarify this
              # deferred response handling
              if result.is_a? Exception
                log_e result, 'Error deleting scene'
                response.content_type 'text/plain; charset=utf-8'
                response.content = result
                response.send_response
              else
                log "Deleted scene #{scene.id}"
                response.content_type 'application/json; charset=utf-8'
                response.content = scene.to_json
                response.send_response
              end
            end

            @send_response = false
          end

        rescue Exception => e
          # TODO: Move this common exception handling into NL::KNC::ZoneWeb
          response.status = 500
          response.content_type 'text/plain; charset=utf-8'
          response.content = e
          log_e e, @http_request_uri
        end
      end


      # Recalls a scene by full ID or by scene name prefix.  Pass the scene
      # name/ID in the scene parameter.  Recall a random scene (excluding
      # those which appear to turn off lights) by passing "_random".
      # Optionally pass a group ID in the group parameter.
      NL::KNC::ZoneWeb.add_route ['/settings/hue/recall_scene'] do |response|
        begin
          if @http_request_method != 'POST'
            response.status = 302
            response.headers['Location'] = '/settings'
          else
            # TODO: Move common serial/bridge processing into a shared preamble/helper
            serial = @allvars['serial']
            bridge = KncHue.find_bridge serial
            raise "No matching bridge found for #{serial}." unless bridge

            scene = @allvars['scene']
            if scene == '_random'
              scene = bridge.scenes.values.reject{|s| s.id.include?('-off-')}.sample
            else
              scene = bridge.find_scene(@allvars['scene'])
            end
            raise "Scene #{@allvars['scene']} not found" unless scene

            group = bridge.groups[@allvars['group'].to_i]
            raise "Invalid group #{@allvars['group']}" unless group

            cb = proc do |status, result|
              response.status = status ? 200 : 500 # Is there a better error code available?

              # TODO: Find some way to consolidate and clarify this
              # deferred response handling
              if result.is_a? Exception
                log_e result, 'Error while recalling scene'
                response.content_type 'text/plain; charset=utf-8'
                response.content = result
                response.send_response
              else
                response.content_type 'application/json; charset=utf-8'
                response.content = scene.to_json
                response.send_response
              end
            end

            if group.id > 0
              group.defer
              group.recall_scene scene, &cb
              group.submit &cb
            else
              scene.recall &cb
            end

            @send_response = false
          end

        rescue Exception => e
          # TODO: Move this common exception handling into NL::KNC::ZoneWeb
          response.status = 500
          response.content_type 'text/plain; charset=utf-8'
          response.content = e
          log_e e, @http_request_uri
        end
      end

      NL::KNC::ZoneWeb.add_route ['/settings/hue/light', '/settings/hue/group'] do |response|
        begin
          if @http_request_method == 'DELETE'
            raise 'Can only delete groups' unless @http_request_uri.end_with? '/group'

            serial = @allvars['serial']
            bridge = KncHue.find_bridge serial
            raise "No matching bridge found for #{serial}." unless bridge

            id = @allvars['id'].to_i
            target = bridge.groups[id]
            raise "Group #{id} not found." unless target

            bridge.delete_group(target) do |status, result|
              response.status = status ? 200 : 500 # Is there a better error code available?

              if result.is_a? Exception
                log_e result, 'Error while setting light or group'
                response.content_type 'text/plain; charset=utf-8'
                response.content = result
                response.send_response
              else
                if @allvars.include? 'redir'
                  response.status = 302
                  response.headers['Location'] = '/settings'
                  EM.add_timer(0.2) do
                    response.send_response
                  end
                else
                  response.content_type 'application/json; charset=utf-8'
                  response.content = target.to_json
                  response.send_response
                end
              end
            end

            @send_response = false
          elsif @http_request_method != 'POST' || @postvars.empty?
            response.status = 302
            response.headers['Location'] = '/settings'
          else
            serial = @allvars['serial']
            bridge = KncHue.find_bridge serial
            raise "No matching bridge found for #{serial}." unless bridge

            id = @allvars['id'].to_i

            if @http_request_uri.end_with? '/group'
              raise "Invalid group ID #{id}." unless id >= 0
              target = bridge.groups[id]
              raise "Group #{id} not found." unless target
            else
              raise "Invalid light ID #{id}." unless id >= 1
              target = bridge.lights[id]
              raise "Light #{id} not found." unless target
            end

            target.defer
            ct_set = @postvars.include?('ct') && @postvars['ct'].to_i != target.ct
            xy_set = (@postvars.include?('x') && @postvars['x'].to_f.round(4) != target.x.round(4)) ||
              (@postvars.include?('y') && @postvars['y'].to_f.round(4) != target.y.round(4))
            @postvars.each do |k, v|
              case k
              when 'all_on'
                # Special parameter to set light/group for max brightness
                target.on = true
                target.bri = 255
                target.hue = 231
                target.sat = 1

              when 'on'
                case v
                when 'true', 'on', '1'
                  on = true
                when 'toggle'
                  on = !target.on?
                else
                  on = false
                end

                # Try to work around Hue brightness bug
                # http://www.everyhue.com/vanilla/discussion/204
                if !on && target.on?
                  log "\n\nNot sending transition time for switch off\n\n" # XXX
                  @postvars.delete 'transitiontime'
                  target.transitiontime = nil
                end

                target.on = on

              when 'alert'
                target.alert = v

              when 'bri'
                target.bri = v.to_i if target.bri != v.to_i

              when 'ct'
                target.ct = v.to_i if target.ct != v.to_i

              when 'x'
                if !ct_set && target.x.round(4) != v.to_f.round(4)
                  target.x = v.to_f
                end

              when 'y'
                if !ct_set && target.y.round(4) != v.to_f.round(4)
                  target.y = v.to_f
                end

              when 'hue'
                if !ct_set && !xy_set && target.hue.round(1) != v.to_f.round(1)
                  target.hue = v.to_f.round(1)
                end

              when 'sat'
                if !ct_set && !xy_set && target.sat != v.to_i
                  target.sat = v.to_i
                end

              when 'colormode'
                case v
                when 'ct'
                  target.ct = target.ct
                when 'xy'
                  target.x = target.x
                  target.y = target.y
                when 'hs'
                  target.hue = target.hue
                  target.sat = target.sat
                end

              when 'transitiontime'
                target.transitiontime = v.to_i

              when 'effect'
                target.effect = v

              when 'scene'
                scene = bridge.find_scene(v)
                target.recall_scene(scene || v) if target.is_a?(NLHue::Group)
              end
            end

            target.submit do |status, result|
              response.status = status ? 200 : 500 # Is there a better error code available?

              if result.is_a? Exception
                log_e result, 'Error while setting light or group'
                response.content_type 'text/plain; charset=utf-8'
                response.content = result
                response.send_response
              else
                if @allvars.include? 'redir'
                  response.status = 302
                  response.headers['Location'] = '/settings'
                  EM.add_timer(0.2) do
                    response.send_response
                  end
                else
                  response.content_type 'application/json; charset=utf-8'
                  response.content = target.to_json
                  response.send_response
                end
              end

            end

            @send_response = false
          end
        rescue Exception => e
          response.status = 500
          response.content_type 'text/plain; charset=utf-8'
          response.content = e
          log_e e, @http_request_uri
        end
      end

      NL::KNC::ZoneWeb.add_route ['/settings/hue/newlights'] do |response|
        next unless accept_methods 'GET', 'POST'

        serial = @allvars['serial']
        bridge = KncHue.get_bridge serial
        raise 'No matching bridge found.' unless bridge || serial.nil?

        if @http_request_method == 'GET'
          response.content_type 'application/json; charset=utf-8'

          if bridge
            response.content = bridge.scan_status.to_json
          else
            h = {}
            KncHue.bridges.each do |br|
              h[br.serial] = br.scan_status
            end
            response.content = h.to_json
          end

          @log_request = false
        else
          response.content_type 'text/plain; charset=utf-8'

          unless bridge
            response.status = 400
            response.content = 'Bridge serial number missing ("serial" parameter).'
            next
          end

          scan_active = bridge.scan_active?

          bridge.scan_lights do |result|
            if result.is_a? Exception
              response.status = 500
              response.content = 'Error starting scan for new lights: ' + result
            else
              response.content = scan_active ?
                'Light scan restarted.' :
                'Light scan started.'
            end

            response.send_response
          end

          @send_response = false
        end
      end

      NL::KNC::ZoneWeb.add_route ['/settings/hue/disco'] do |response|
        running = NLHue::Disco.disco_running?
        EM.next_tick do
          NLHue::Disco.do_disco unless running
        end

        if @http_request_method == 'POST' || @allvars.include?('noredir')
          response.status = 200
          response.content_type 'text/plain; charset=utf-8'
          response.content = running ? 'Disco in progress' : 'Disco started'
        else
          response.status = 302
          response.headers['Location'] = '/settings'
        end
      end

      NL::KNC::ZoneWeb.add_route ['/settings/hue/register', '/settings/hue/unregister'] do |response|
        begin
          if @http_request_method != 'POST' || @postvars.empty?
            response.status = 302
            response.headers['Location'] = '/settings'
          else
            response.content_type 'application/json; charset=utf-8'

            # Don't default to first bridge here; only for use by web UI
            serial = KncHue.check_serial(@allvars['serial'])
            bridge = KncHue.get_bridge serial
            raise 'No matching bridge found.' unless bridge

            cback = proc { |status, result|
              # Is there a better error code available than
              # network authentication required?
              response.status = status ? 200 : 511

              if result.is_a? Exception
                response.content_type 'text/plain; charset=utf-8'

                if result.is_a? NLHue::LinkButtonError
                  response.content = result.message
                elsif result.is_a? NLHue::NotRegisteredError
                  response.content = 'The given bridge is not registered.'
                else
                  log_e result, 'Error while (un)registering'
                  response.content = result
                end
              else
                response.content = result.to_json
              end

              response.send_response
            }

            if @http_request_uri.end_with? '/register'
              KncHue.register bridge, &cback
            else
              KncHue.unregister bridge, &cback
            end

            @send_response = false
          end
        rescue Exception => e
          response.status = 500
          response.content_type 'text/plain; charset=utf-8'
          response.content = e.to_s
          @send_response = true
          log_e e, @http_request_uri
        end
      end
    end
  end
end
