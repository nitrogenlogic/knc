/*
 * Hue settings code on the Depth Camera Controller settings page
 * (C)2013 Mike Bourgeous
 */

var KNC = window.KNC || {};

KNC.Hue = KNC.Hue || {};


// Use jQuery.extend(prototype, KNC.Hue.DataSync) to add methods for updating
// elements' contents when an associated property changes.
// TODO: Use an existing data binding library (Angular, React, etc.)
KNC.Hue.DataSync = {
	// Adds an HTML element whose contents should be changed when
	// notifyElements is called with the given property.
	addElement: function(property, element) {
		if(!(typeof(property) === 'string')) {
			throw 'property must be a String';
		}
		if(!(element instanceof Element || typeof(element) === 'function')) {
			throw 'element must be an Element or a function';
		}

		this.elements = this.elements || {};
		this.elements[property] = this.elements[property] || [];

		if($.inArray(element, this.elements[property]) === -1) {
			this.elements[property].push(element);
		}
	},

	// Unsubscribes the given element from the given property.
	removeElement: function(property, element) {
		if(!(property instanceof String)) {
			throw 'property must be a String';
		}
		if(!(element instanceof Element)) {
			throw 'element must be an Element';
		}

		this.elements = this.elements || {};
		this.elements[property] = this.elements[property] || [];

		var idx = $.inArray(element, this.elements[property]);
		if(idx !== -1) {
			delete this.elements[idx];
		}
	},

	// Sets all elements added with the given property to and notifies all
	// functions with the given value using KNC.setElements()
	notifyElements: function(property, value) {
		this.elements = this.elements || {};
		this.elements[property] = this.elements[property] || [];
		KNC.setElements(this.elements[property], value);
	}

	// TODO: support for event handlers on input elements to replace ad hoc
	// handlers in KNC.Hue.Light.html()
	// TODO: cleanElements() function that removes any event handlers
}


KNC.Hue.bridges = {}; // 'serial': Bridge

// Adds a bridge for the given serial number if one does not already exist.  If
// it's not present in the JSON from the server, it will be removed on the next
// update.  Info is optional.  Returns the new Bridge object.
KNC.Hue.addBridge = function(serial, info) {
	var br = KNC.Hue.bridges[serial]

	if(!br) {
		console.log('Adding new Hue bridge ' + serial + '.');

		br = new KNC.Hue.Bridge(serial);
		if(info) {
			br.handleJSON(info);
		}
		KNC.Hue.bridges[serial] = br;

		var el = $('tbody.hue_bridge[data-serial="' + serial + '"]')[0];
		if(el) {
			el.parentNode.replaceChild(br.html(), el);
		} else {
			document.getElementById('hue_bridges_table').appendChild(br.html());
		}
	}

	return br;
}

// Removes a bridge with the given serial number.
KNC.Hue.removeBridge = function(serial) {
	var br = KNC.Hue.bridges[serial];
	if(br) {
		console.log('Removing Hue bridge ' + serial + '.');

		var html = KNC.Hue.bridges[serial].html();
		if(html.parentNode) {
			html.parentNode.removeChild(html);
		}

		delete KNC.Hue.bridges[serial];
	}
}

// Call with the bridges array from /settings/hue
KNC.Hue.updateBridges = function(bridges) {
	var bridgeValid = {};

	// Add/update bridges
	for(var idx in bridges) {
		var info = bridges[idx];

		bridgeValid[info.serial] = true;

		var br = KNC.Hue.bridges[info.serial]
		if(br instanceof KNC.Hue.Bridge) {
			br.handleJSON(info);
		} else {
			KNC.Hue.addBridge(info.serial, info);
		}
	}

	// Remove old bridges
	for(var br in KNC.Hue.bridges) {
		if(!bridgeValid[br]) {
			KNC.Hue.removeBridge(br);
		}
	}
}

// Represents a Hue bridge discovered by the Depth Camera Controller
KNC.Hue.Bridge = function(serial) {
	var that = this;

	serial = serial.toLowerCase();

	if(!(serial.match(/^[0-9a-f]{12}$/))) {
		throw 'Serial number ' + serial + ' is invalid.';
	}

	this.serial = serial;

	this.lights = {};
	this.numLights = 0;

	this.groups = {};
	this.numGroups = 0;

	this.scenes = {};
	this.numScenes = 0;

	var jqInfoRow = $('tr.hue_bridge_row[data-serial="' + serial + '"]').first();
	var jqDetailRow = $('tr.hue_bridge_detail[data-serial="' + serial + '"]').first();
	if(jqInfoRow.length > 0) {
		this.registered = jqInfoRow.attr('data-registered') == 'true';
		this.discoTimeout = jqInfoRow.attr('data-disco-timeout') == 'true';
		this.updateError = jqInfoRow.attr('data-update-error') == 'true';
		this.scanActive = jqInfoRow.attr('data-scan-active') == 'true';
		this.name = jqInfoRow.find('td.hue_bridge_name').text().trim();
		this.addr = jqInfoRow.find('td.hue_bridge_addr').text().trim();

		if(jqDetailRow.length > 0) {
			jqDetailRow.find('.hue_light_row, .hue_group_row, .hue_scene_row').each(function(idx, el) {
				var id = el.getAttribute('data-id');
				var intid = parseInt(id);

				if(el.className.indexOf('hue_light_row') !== -1) {
					if(!(that.lights[intid] instanceof KNC.Hue.Light)) {
						that.lights[intid] = new KNC.Hue.Light(that, {id: id});
						that.numLights++;
					}
				} else if(el.className.indexOf('hue_scene_row') !== -1) {
					if(!(that.scenes[id] instanceof KNC.Hue.Scene)) {
						that.scenes[id] = new KNC.Hue.Scene(that, {id: id});
						that.numScenes++;
					}
				} else {
					if(!(that.groups[intid] instanceof KNC.Hue.Group)) {
						that.groups[intid] = new KNC.Hue.Group(that, {id: id});
						that.numGroups++;
					}
				}
			});
		}
	} else {
		this.registered = false;
	}
}
KNC.Hue.Bridge.prototype = {
	// Updates this bridge's state (lights, groups, scenes, name, etc.).  Pass a
	// JavaScript object parsed from Bridge-describing JSON returned by the
	// Depth Camera Controller API.
	handleJSON: function(info) {
		var that = this;

		if(info.serial != this.serial) {
			throw 'Cannot update bridge ' + this.serial +
				' with info from different bridge ' + info.serial + '.';
		}

		this.info = info;

		if(info.addr != this.addr) {
			this.addr = info.addr;
			this.notifyElements('addr', this.addr);
		}

		if(info.name != this.name) {
			this.name = info.name;
			this.notifyElements('name', this.name || "\u2014");
		}

		if(info.registered != this.registered) {
			this.registered = info.registered;
			this.notifyElements('registered', this.registered);
		}

		if(info.disco_timeout != this.discoTimeout) {
			this.discoTimeout = info.disco_timeout;
			this.notifyElements('discoTimeout', this.discoTimeout);
		}

		if(info.update_error != this.updateError) {
			this.updateError = info.update_error;
			this.notifyElements('updateError', this.updateError);
		}

		var scan = info.scan.lastscan === 'active';
		if(scan != this.scanActive) {
			this.scanActive = scan;
			this.notifyElements('scanActive', this.scanActive);
		}

		// Add new lights
		var lightsAdded = false;
		$.each(info.lights, function(idx, light) {
			if(!(that.lights[light.id] instanceof KNC.Hue.Light)) {
				console.log('Adding light ' + idx + ' to bridge ' + that.serial + '.');
				that.lights[light.id] = new KNC.Hue.Light(that, light);
				that.numLights++;
				that.notifyElements('numLights', that.numLights);
				lightsAdded = true;

				if(that.lightsBody) {
					that.lightsBody.appendChild(that.lights[light.id].html());
				}
			} else {
				that.lights[light.id].handleJSON(light);
			}
		});

		// Remove old lights
		$.each(this.lights, function(idx, light) {
			if(!(info.lights[idx])) {
				console.log('Removing light ' + idx + ' from bridge ' + that.serial + '.');

				var lightHTML = that.lights[idx].html();
				if(lightHTML.parentNode) {
					lightHTML.parentNode.removeChild(lightHTML);
				}

				delete that.lights[idx];
				that.numLights--;
				that.notifyElements('numLights', that.numLights);
			}
		});

		// Sort light rows by ID
		if(lightsAdded && this.lightsBody) {
			var lights = Object.keys(this.lights).sort();
			for(var i = 0; i < lights.length; i++) {
				this.lightsBody.appendChild(this.lights[lights[i]].html());
			}
		}

		// Add new groups
		var groupsAdded = false;
		$.each(info.groups, function(idx, group) {
			if(!(that.groups[group.id] instanceof KNC.Hue.Group)) {
				console.log('Adding group ' + idx + ' to bridge ' + that.serial + '.');
				that.groups[group.id] = new KNC.Hue.Group(that, group);
				that.numGroups++;
				that.notifyElements('numGroups', that.numGroups);

				if(that.groupsBody) {
					that.groupsBody.appendChild(that.groups[group.id].html());
				}
			} else {
				that.groups[group.id].handleJSON(group);
			}
		});

		// Remove old groups
		$.each(this.groups, function(idx, group) {
			if(!(info.groups[group.id])) {
				console.log('Removing group ' + idx + ' from bridge ' + that.serial + '.');

				var groupHTML = that.groups[idx].html();
				if(groupHTML.parentNode) {
					groupHTML.parentNode.removeChild(groupHTML);
				}

				delete that.groups[idx];
				that.numGroups--;
				that.notifyElements('numGroups', that.numGroups);
			}
		});

		// Sort group rows by ID
		if(groupsAdded && this.groupsBody) {
			var groups = Object.keys(this.groups).sort();
			for(var i = 0; i < groups.length; i++) {
				this.groupsBody.appendChild(this.groups[groups[i]].html());
			}
		}

		// Add new scenes
		var scenesAdded = false;
		$.each(info.scenes, function(idx, scene) {
			if(!(that.scenes[scene.id] instanceof KNC.Hue.Scene)) {
				console.log('Adding scene ' + idx + '/' + scene.name + ' to bridge ' + that.serial + '.');
				that.scenes[scene.id] = new KNC.Hue.Scene(that, scene);
				that.numScenes++;
				that.notifyElements('numScenes', that.numScenes);

				if(that.scenesBody) {
					that.scenesBody.appendChild(that.scenes[scene.id].html());
				}
			} else {
				that.scenes[scene.id].handleJSON(scene);
			}
		});

		// Remove old scenes
		$.each(this.scenes, function(idx, scene) {
			if(!(info.scenes[scene.id])) {
				var scene = that.scenes[idx];
				console.log('Removing scene ' + idx + '/' + scene.name + ' from bridge ' + that.serial + '.');

				scene.removeHTML();

				delete that.scenes[idx];
				that.numScenes--;
				that.notifyElements('numScenes', that.numScenes);
			}
		});

		// Sort scene rows by name
		if(scenesAdded && this.scenesBody) {
			this.scenes.sort(function(a, b) { a['name'].localeCompare(b['name']) });
			for(var i = 0; i < scenes.length; i++) {
				this.scenesBody.appendChild(this.scenes[scenes[i]].html());
			}
		}

		// TODO: deduplicate light/group/scene row management
	},

	// Registers with or unregisters from this bridge.  Shows a dialog
	// while registration is in progress.
	// register - true: register, false: unregister
	register: function(register) {
		var uppercase = register ? 'Register' : 'Unregister';
		var lowercase = register ? 'register' : 'unregister';
		var api = '/settings/hue/' + lowercase;
		var retryTimer;
		var serial = this.serial;
		var that = this;

		if(this.registered == register) {
			console.log('Bridge ' + serial + ' is already ' + lowercase + 'ed.');
			return;
		}

		// Open dialog
		var dialog = KNC.showPleaseWaitDialog(
				uppercase + 'ing with bridge ' + serial,
				function() {
					if(retryTimer) {
						clearTimeout(retryTimer);
					}
				}
				);

		// Send request
		function sendRequest() {
			dialog.preventClose();
			retryTimer = null;

			$.post(api, { 'serial': serial }).done(function(data) {
				// If response is affirmative, show success dialog
				console.log(uppercase + 'ed with Hue bridge ' + serial);
				dialog.text('Successfully ' + lowercase + 'ed.');
				dialog.allowClose();

				that.registered = register;
				that.infoRow.setAttribute('data-registered', register);
				that.notifyElements('registered', that.registered);
			}).fail(function(jqXHR, status, error) {
				// If response is negative, show error message
				var text = jqXHR.responseText || error || '';

				console.log('Error ' + lowercase + 'ing with Hue bridge ' + serial + ': ' + text);

				// If the error	message requires pressing the link button, keep
				// the dialog open with a spinner indicating activity, add a
				// cancel button, and retry every few seconds.
				if(register && text.indexOf('link button') >= 0) {
					retryTimer = setTimeout(sendRequest, 2000);
					dialog.find('span').text(jqXHR.responseText);
					dialog.allowCancel();
				} else {
					dialog.dialog('option', 'title', 'Error ' + lowercase + 'ing with bridge ' + serial);
					dialog.text(text);
					dialog.allowClose();
				}
			});
		}

		sendRequest();
	},

	// Asks for confirmation using a dialog before unregistering from the
	// given bridge.
	unregister: function() {
		var that = this;
		var dialog = $('<div>Are you sure you want to unregister from this bridge?</div>').dialog({
			modal: true,
			draggable: false,
			title: 'Unregister from bridge ' + this.name + ' (' + this.serial + ')',
			close: function() { dialog.dialog('destroy'); dialog.remove(); },
			width: 500,
			buttons: {
				'Unregister': function() { dialog.dialog('close'); that.register(false); },
				'Cancel': function() { dialog.dialog('close'); },
			}
		});
	},

	// Makes a POST request to /settings/hue/newlights, starting (or
	// restarting) a scan for new lights.  Returns a jqXHR object, to which
	// success and failure callbacks may be added.
	scanLights: function() {
		var that = this;
		return this.set('newlights', {serial: this.serial}).done(function(data) {
			console.log('Started light scan on bridge ' + that.serial);
			that.scanActive = true;
			that.notifyElements('scanActive', true);
		});
	},

	xhrDone: function(type, params, data) {
	},

	xhrFail: function(type, params, jqXHR, status, error) {
		if(('' + jqXHR.responseText).indexOf('Device is set to off') == -1) {
			KNC.Hue.hueErrorText('Error setting ' + type + ' ' + params.id + ': ' +
				(jqXHR.responseText || error || ''));
		}
		console.error('Error setting ' + type + ' ' + params.id + ' on bridge ' + this.serial + ': ');
		console.error(jqXHR.responseText);
	},

	// Makes a POST request to /settings/hue/[type] with the given
	// parameters.  Returns a jqXHR object, to which success and failure
	// callbacks may be added.
	set: function(type, params, method) {
		if(method === undefined) {
			method = 'POST';
		}

		var that = this;
		return $.ajax('/settings/hue/' + type, {data: params, method: method}).done(function(data) {
			if(KNC.Hue.hueErrorText().indexOf('Error setting') === 0) {
				KNC.Hue.hueErrorText('');
			}

			if(params.hasOwnProperty('id') && type == 'light' || type == 'group') {
				that[type + 's'][params.id].handleJSON(data);
			}
		}).fail(function(jqXHR, status, error) {
			if(('' + jqXHR.responseText).indexOf('Device is set to off') == -1) {
				KNC.Hue.hueErrorText('Error setting ' + type + ' ' + params.id + ': ' +
					(jqXHR.responseText || error || ''));
			}
			console.error('Error ' + method + '-ing ' + type + ' ' + params.id + ' on bridge ' + that.serial + ': ');
			console.error(jqXHR.responseText);
		});
	},

	// Sends the given parameters to the given light.  Returns a jqXHR
	// object, to which success and failure callbacks may be added.
	setLight: function(id, params) {
		params = $.extend({id: id, serial: this.serial}, params);
		return this.set('light', params);
	},

	// Recalls a scene by exact ID or by name prefix.  Returns a jqXHR
	// object, to which success and failure callbacks may be added.
	recallScene: function(scene_id) {
		return this.set('recall_scene', {serial: this.serial, scene: scene_id});
	},

	// Deletes the given scene.
	deleteScene: function(scene_id) {
		return this.set('scene', {serial: this.serial, scene: scene_id}, 'DELETE');
	},

	// Deletes the given group.
	deleteGroup: function(id) {
		return this.set('group', {serial: this.serial, id: id}, 'DELETE');
	},

	// Sends the given parameters to the given group.  Returns a jqXHR
	// object, to which success and failure callbacks may be added.
	setGroup: function(id, params) {
		params = $.extend({id: id, serial: this.serial}, params);
		return this.set('group', params);
	},

	// Shows or hides the detail row.
	showDetails: function(visible, time) {
		if(this.infoRow) {
			if(visible) {
				this.infoRow.classList.add('detail_visible');
			} else {
				this.infoRow.classList.remove('detail_visible');
			}
		}
		if(this.detailRow) {
			KNC.showHide($(this.detailRow), visible, time);
			KNC.showHide($(this.detailContents), visible, time);
		}
	},

	// Returns a <tbody> element containing the infoHTML() and detailHTML()
	// rows.  Creates the HTML tree if it does not exist.  The detail row
	// will be shown/hidden automatically as the bridge is registered or
	// unregistered.
	html: function() {
		if(this.tbody instanceof Element) {
			return this.tbody;
		}

		this.tbody = document.createElement('tbody');
		this.tbody.className = 'hue_bridge';
		this.tbody.setAttribute('data-serial', this.serial);
		this.tbody.appendChild(this.infoHTML());
		this.tbody.appendChild(this.detailHTML());
		if(!this.registered) {
			this.infoRow.classList.remove('detail_visible');
			this.detailRow.style.display = 'none';
			this.detailContents.style.display = 'none';
		}

		return this.tbody;
	},

	// Returns a <tr> element containing the HTML for this bridge's info
	// row (name, serial, address, etc.).  Creates the HTML tree if it does
	// not exist.
	infoHTML: function() {
		var that = this;

		if(this.infoRow instanceof Element) {
			return this.infoRow;
		}

		this.infoRow = document.createElement('tr');
		this.infoRow.className = 'hue_bridge_row detail_visible';
		this.infoRow.setAttribute('data-serial', this.serial);
		this.infoRow.setAttribute('data-registered', this.registered);
		this.infoRow.setAttribute('data-disco-timeout', this.discoTimeout);
		this.infoRow.setAttribute('data-update-error', this.updateError);
		this.infoRow.setAttribute('data-scan-active', this.scanActive);
		this.addElement('registered', function(value) {
			that.infoRow.setAttribute('data-registered', value);
			that.showDetails(value);
		});
		this.addElement('discoTimeout', function(value) {
			that.infoRow.setAttribute('data-disco-timeout', value);
		});
		this.addElement('updateError', function(value) {
			that.infoRow.setAttribute('data-update-error', value);
		});
		this.addElement('scanActive', function(value) {
			that.infoRow.setAttribute('data-scan-active', value);
		});

		var nameElem = document.createElement('td');
		nameElem.className = 'hue_bridge_name';
		this.infoRow.appendChild(nameElem);

		var nameDiv = document.createElement('div');
		nameDiv.appendChild(document.createTextNode(this.name || "\u2014"));
		nameElem.appendChild(nameDiv);
		this.addElement('name', nameDiv);

		var iconDiv = document.createElement('div');
		iconDiv.className = 'hue_bridge_name_icons';
		nameDiv.appendChild(iconDiv);

		var warnIcon = document.createElement('img');
		warnIcon.className = 'warning_icon';
		warnIcon.src = '/images/warning_15x15.png';
		warnIcon.title = 'Error updating bridge information.';
		warnIcon.alt = '(error)';
		iconDiv.appendChild(warnIcon);

		var timeoutIcon = document.createElement('img');
		timeoutIcon.className = 'timeout_icon';
		timeoutIcon.src = '/images/timeout_15x15.png';
		timeoutIcon.title = 'Bridge stopped responding to discovery scans.';
		timeoutIcon.alt = '(timeout)';
		iconDiv.appendChild(timeoutIcon);

		var addrElem = document.createElement('td');
		addrElem.className = 'hue_bridge_addr';
		addrElem.appendChild(document.createTextNode(this.addr));
		this.infoRow.appendChild(addrElem);
		this.addElement('addr', addrElem);

		var serialElem = document.createElement('td');
		serialElem.className = 'hue_bridge_serial';
		serialElem.appendChild(document.createTextNode(this.serial));
		this.infoRow.appendChild(serialElem);

		var lightsElem = document.createElement('td');
		lightsElem.className = 'hue_bridge_lights';
		if(this.registered || this.numLights > 0) {
			lightsElem.appendChild(document.createTextNode(this.numLights));
		} else {
			lightsElem.appendChild(document.createTextNode("\u2014"));
		}
		lightsElem.title = "Click to identify this bridge's lights (if registered).";
		lightsElem.onclick = function() {
			that.setGroup(0, {alert: 'select'});
		}
		this.infoRow.appendChild(lightsElem);
		this.addElement('numLights', function(value) {
			if(value > 0 || that.registered) {
				lightsElem.textContent = value;
			} else {
				lightsElem.textContent = "\u2014";
			}
		});

		var actionElem = document.createElement('td');
		actionElem.className = 'hue_bridge_action';
		this.infoRow.appendChild(actionElem);

		this.registerLink = document.createElement('a');
		this.registerLink.href = 'javascript:';
		this.registerLink.className = 'hue_register_link';
		this.registerLink.setAttribute('data-serial', this.serial);
		this.registerLink.appendChild(document.createTextNode('Register'));
		this.registerLink.onclick = function() {
			that.register(true);
		}

		this.unregisterLink = document.createElement('a');
		this.unregisterLink.href = 'javascript:';
		this.unregisterLink.className = 'hue_unregister_link';
		this.unregisterLink.setAttribute('data-serial', this.serial);
		this.unregisterLink.appendChild(document.createTextNode('Unregister'));
		this.unregisterLink.onclick = function() {
			that.unregister();
		}

		actionElem.appendChild(this.unregisterLink);
		actionElem.appendChild(this.registerLink);

		return this.infoRow;
	},

	// Returns a <tr> element containing the HTML for this bridge's detail
	// row (lights, groups).  Creates the HTML tree if it does not exist.
	detailHTML: function() {
		var that = this;

		if(this.detailRow instanceof Element) {
			return this.detailRow;
		}

		this.detailRow = document.createElement('tr');
		this.detailRow.className = 'hue_bridge_detail';
		this.detailRow.setAttribute('data-serial', this.serial);

		var col = document.createElement('td');
		col.setAttribute('colspan', 5);
		this.detailRow.appendChild(col);

		this.detailContents = document.createElement('div');
		col.appendChild(this.detailContents);

		var lightHeader = document.createElement('h5');
		lightHeader.appendChild(document.createTextNode('Lights'));
		this.detailContents.appendChild(lightHeader);

		var scanActive = document.createElement('div');
		scanActive.className = 'hue_scan_active';
		scanActive.innerHTML = '<img class="loading_icon" src="/images/loading_15x15.gif">' +
			'Scanning for new lights...' +
			'<a href="javascript:" class="hue_scan_link">Restart scan</a>';
		this.detailContents.appendChild(scanActive);

		var activeLink = scanActive.firstElementChild.nextElementSibling;
		activeLink.onclick = function() {
			var wasActive = that.scanActive;
			that.scanLights().fail(function() {
				that.scanActive = wasActive;
				that.notifyElements('scanActive', wasActive);
			});
			that.notifyElements('scanActive', true);
		}

		var scanInactive = document.createElement('div');
		scanInactive.className = 'hue_scan_inactive';
		scanInactive.innerHTML = '<a href="javascript:" class="hue_scan_link">Scan for new lights</a>';
		this.detailContents.appendChild(scanInactive);

		var inactiveLink = scanInactive.firstElementChild;
		inactiveLink.title = 'Start a scan for up to 15 new Hue lights.';
		inactiveLink.onclick = activeLink.onclick;

		this.detailContents.appendChild(this.lightsHTML());

		var sceneHeader = document.createElement('h5');
		sceneHeader.appendChild(document.createTextNode('Scenes'));
		this.detailContents.appendChild(sceneHeader);
		this.detailContents.appendChild(this.scenesHTML());

		var groupHeader = document.createElement('h5');
		groupHeader.appendChild(document.createTextNode('Groups'));
		this.detailContents.appendChild(groupHeader);
		this.detailContents.appendChild(this.groupsHTML());

		return this.detailRow;
	},

	lightsHTML: function() {
		if(this.lightsTable instanceof Element) {
			return this.lightsTable;
		}

		this.lightsTable = document.createElement('table');
		this.lightsTable.className = 'hue hue_lights subsection_table knc_table';

		var header = document.createElement('thead');
		header.innerHTML =
			'<tr>' +
			'<th class="hue_light_id">ID</th>' +
			'<th class="hue_light_name">Name</th>' +
			'<th class="hue_light_on">On</th>' +
			'<th class="hue_light_bri" title="0-255">Bright</th>' +
			'<th class="hue_light_ct" title="154-500 mireds">Temp</th>' +
			'<th class="hue_light_x" title="0.0-1.0">X</th>' +
			'<th class="hue_light_y" title="0.0-1.0">Y</th>' +
			'<th class="hue_light_hue" title="0.0-360.0">Hue</th>' +
			'<th class="hue_light_sat" title="0-255">Sat</th>' +
			'<th class="hue_light_preset">Preset</th>' +
			'</tr>';
		this.lightsTable.appendChild(header);

		this.lightsBody = document.createElement('tbody');
		this.lightsTable.appendChild(this.lightsBody);

		for(var id in this.lights) {
			this.lightsBody.appendChild(this.lights[id].html());
		}

		return this.lightsTable;
	},

	scenesHTML: function() {
		if(this.scenesTable instanceof Element) {
			return this.scenesTable;
		}

		this.scenesTable = document.createElement('table');
		this.scenesTable.className = 'hue hue_scenes subsection_table knc_table';

		var header = document.createElement('thead');
		header.innerHTML =
			'<tr>' +
			'<th class="hue_scene_id">ID</th>' +
			'<th class="hue_scene_name">Name</th>' +
			'<th class="hue_scene_lights">Lights</th>' +
			'</tr>';
		this.scenesTable.appendChild(header);

		this.scenesBody = document.createElement('tbody');
		this.scenesTable.appendChild(this.scenesBody);

		for(var id in this.scenes) {
			this.scenesBody.appendChild(this.scenes[id].html());
		}

		return this.scenesTable;
	},

	groupsHTML: function() {
		if(this.groupsTable instanceof Element) {
			return this.groupsTable;
		}

		this.groupsTable = document.createElement('table');
		this.groupsTable.className = 'hue hue_groups subsection_table knc_table';

		var header = document.createElement('thead');
		header.innerHTML =
			'<tr>' +
			'<th class="hue_group_id">ID</th>' +
			'<th class="hue_group_name">Name</th>' +
			'<th class="hue_group_lights">Lights</th>' +
			'</tr>';
		this.groupsTable.appendChild(header);

		this.groupsBody = document.createElement('tbody');
		this.groupsTable.appendChild(this.groupsBody);

		for(var id in this.groups) {
			this.groupsBody.appendChild(this.groups[id].html());
		}

		return this.groupsTable;
	},
}
$.extend(KNC.Hue.Bridge.prototype, KNC.Hue.DataSync);

// Pass {id: [light id]} as info for lights created from HTML.
KNC.Hue.Light = function(bridge, info) {
	this.bridge = bridge;
	this.handleJSON(info);

	var jqLightRow = $('tr.hue_bridge_detail[data-serial="' + bridge.serial +
			'"] .hue_light_row[data-id="' + info.id + '"]').first();
	if(jqLightRow.length > 0) {
		this.colormode = jqLightRow.attr('data-colormode');
		this.type = jqLightRow.find('td.hue_light_id').attr('title').trim();
		this.name = jqLightRow.find('td.hue_light_name').text().trim();
		this.on = jqLightRow.find('td.hue_light_on').attr('data-on') == 'true';
		this.bri = parseInt(jqLightRow.find('td.hue_light_bri').attr('data-bri'));
		this.ct = parseInt(jqLightRow.find('td.hue_light_ct').attr('data-ct'));
		this.x = KNC.roundk(parseFloat(jqLightRow.find('td.hue_light_x').attr('data-x')));
		this.y = KNC.roundk(parseFloat(jqLightRow.find('td.hue_light_y').attr('data-y')));
		this.hue = KNC.roundMult(parseFloat(jqLightRow.find('td.hue_light_hue').attr('data-hue')), 0.1);
		this.sat = parseInt(jqLightRow.find('td.hue_light_sat').attr('data-sat'));
	}
}
KNC.Hue.Light.prototype = {
	handleJSON: function(info) {
		if(info.hue) {
			info.hue = KNC.roundMult(info.hue, 0.1);
		}
		if(info.x) {
			info.x = KNC.roundk(info.x);
		}
		if(info.y) {
			info.y = KNC.roundk(info.y);
		}

		for(var param in info) {
			if(this[param] != info[param]) {
				this[param] = info[param];
				this.notifyElements(param, info[param]);
			}
		}
		this.info = info;

		if(this.lightRow) {
			this.lightRow.setAttribute('data-colormode', this.colormode);
		}
	},

	// Sends the given set of parameters to this light.
	set: function(params) {
		for(var param in params) {
			if(param !== 'on') {
				this[param] = params[param];
				this.notifyElements(param, this[param]);
			}
		}
		return this.bridge.setLight(this.id, params);
	},

	// Flashes this light.  Also flashes the light's table row.
	flash: function() {
		var that = this;
		if(that.lightRow) {
			that.lightRow.style.opacity = 0.65;
		}
		this.set({alert: 'select'}).always(function(data) {
			if(data.hasOwnProperty('responseText') && (
					'' + data.responseText).indexOf('Device is set to off') == -1) {
				that.lightRow.style.opacity = null;
				return;
			}

			console.log("Flashed light " + that.id + " on bridge " + that.bridge.serial);

			if(that.lightRow) {
				that.lightRow.style.opacity = 0.25;
				setTimeout(function() { that.lightRow.style.opacity = null; }, 500);
			}
		})
	},

	// Returns an element containing the table row for this light, creating
	// it if necessary.
	html: function() {
		var that = this;

		if(this.lightRow instanceof Element) {
			return this.lightRow;
		}

		var formId = 'bridge_' + this.bridge.serial + '_light_' + this.id;

		this.form = document.createElement('form');
		this.form.setAttribute('id', formId);
		this.form.autocomplete = 'off';
		this.form.className = 'hue_light_form';
		this.form.method = 'POST';
		this.form.action = '/settings/hue/light';
		this.form.setAttribute('novalidate', '');
		this.form.setAttribute('data-id', this.id);
		$(this.form).submit(function(ev) { ev.preventDefault(); return false; });

		var serialInput = document.createElement('input');
		serialInput.type = 'hidden';
		serialInput.name = 'serial';
		serialInput.value = this.bridge.serial;
		this.form.appendChild(serialInput);

		var idInput = document.createElement('input');
		idInput.type = 'hidden';
		idInput.name = 'id';
		idInput.value = this.id;
		this.form.appendChild(idInput);

		var redirInput = document.createElement('input');
		redirInput.type = 'hidden';
		redirInput.name = 'redir';
		redirInput.value = 1;
		this.form.appendChild(redirInput);

		this.lightRow = document.createElement('tr');
		this.lightRow.className = 'hue_light_row';
		this.lightRow.setAttribute('data-id', this.id);
		this.lightRow.setAttribute('data-colormode', this.colormode);

		var idCol = document.createElement('td');
		idCol.className = 'hue_light_id';
		idCol.title = this.type;
		idCol.appendChild(document.createTextNode(this.id));
		idCol.appendChild(this.form);
		idCol.onclick = function() {
			that.flash();
		}
		this.lightRow.appendChild(idCol);

		var nameCol = document.createElement('td');
		nameCol.className = 'hue_light_name';
		nameCol.title = 'Click to identify this light.';
		nameCol.appendChild(document.createTextNode(this.name));
		nameCol.onclick = function() {
			that.flash();
		}
		this.lightRow.appendChild(nameCol);
		this.addElement('name', nameCol);

		var onCol = document.createElement('td');
		onCol.className = 'hue_light_on';
		onCol.setAttribute('data-on', this.on);
		this.lightRow.appendChild(onCol);

		var onLink = document.createElement('a');
		onLink.appendChild(document.createTextNode(this.on ? "On" : "Off"));
		onLink.href = 'javascript:';
		onLink.onclick = function() {
			that.set({ on: 'toggle' }).done(function(data) {
				var on = data.on ? 'On' : 'Off';

				console.log("Light " + that.id + " on " + that.bridge.serial + " is now " + on);

				onCol.setAttribute('data-on', data.on);
				onLink.textContent = on;
				that.on = data.on;
			});
		};
		onCol.appendChild(onLink);
		this.addElement('on', function(value) {
			onCol.setAttribute('data-on', value);
			onLink.textContent = value ? 'On' : 'Off';
		});

		// TODO: Consolidate update/change handlers
		var brightCol = document.createElement('td');
		brightCol.className = 'hue_light_bri';
		brightCol.setAttribute('data-bri', this.bri);
		brightCol.innerHTML = '<input form="' + formId + '" name="bri" type="number" ' +
			'min="0" max="255" step="1" value="' + this.bri + '">';
		this.lightRow.appendChild(brightCol);

		var brightInput = brightCol.firstElementChild;
		$(brightInput).blur(function() {
			brightInput.value = that.bri;
		}).keyup(function(ev) {
			if(ev.keyCode == 27) {
				brightInput.value = that.bri;
				brightInput.select();
			}
		}).change(function() {
			brightInput.value = parseInt(brightInput.value);
			brightCol.setAttribute('data-bri', brightInput.value);
			brightInput.select();

			that.set({ bri: parseInt(brightInput.value) }).done(function(data) {
				if(brightInput === document.activeElement) {
					brightInput.value = data.bri;
					brightInput.select();
				}
			});
		});
		this.addElement('bri', function(value) {
			if(brightInput !== document.activeElement || brightInput.value === brightCol.getAttribute('data-bri')) {
				brightInput.value = value;
				brightCol.setAttribute('data-bri', brightInput.value);
				if(brightInput === document.activeElement) {
					brightInput.select();
				}
			}
		});

		var tempCol = document.createElement('td');
		tempCol.className = 'hue_light_ct';
		tempCol.setAttribute('data-ct', this.ct);
		tempCol.title = '' + (1000000 / (this.ct == 0 ? 369 : this.ct) | 0) + 'K';
		tempCol.innerHTML = '<input form="' + formId + '" name="ct" type="number" ' +
			'min="153" max="500" step="1" value="' + this.ct + '">';
		this.lightRow.appendChild(tempCol);

		var tempInput = tempCol.firstElementChild;
		$(tempInput).blur(function() {
			tempInput.value = that.ct;
		}).keyup(function(ev) {
			if(ev.keyCode == 27) {
				tempInput.value = that.ct;
				tempInput.select();
			}
		}).change(function() {
			tempInput.value = parseInt(tempInput.value);
			tempCol.setAttribute('data-ct', tempInput.value);
			tempInput.select();

			that.set({
				colormode: 'ct',
				ct: parseInt(tempInput.value)
			}).done(function(data) {
				if(tempInput === document.activeElement) {
					tempInput.value = data.ct;
					tempInput.select();
				}
			});
		});
		this.addElement('ct', function(value) {
			if(tempInput !== document.activeElement || tempInput.value === tempCol.getAttribute('data-ct')) {
				tempInput.value = value;
				tempCol.setAttribute('data-ct', tempInput.value);
				if(tempInput === document.activeElement) {
					tempInput.select();
				}
			}
		});
		this.addElement('ct', function(value) {
			tempCol.title = '' + (1000000 / (value == 0 ? 369 : value) | 0) + 'K';
		});

		var xCol = document.createElement('td');
		xCol.className = 'hue_light_x';
		xCol.setAttribute('data-x', this.x.toFixed(3));
		xCol.innerHTML = '<input form="' + formId + '" name="x" type="number" ' +
			'min="0.0" max="1.0" step="any" value="' + this.x.toFixed(3) + '">';
		this.lightRow.appendChild(xCol);

		var xInput = xCol.firstElementChild;
		$(xInput).blur(function() {
			xInput.value = that.x.toFixed(3);
		}).keyup(function(ev) {
			if(ev.keyCode == 27) {
				xInput.value = that.x.toFixed(3);
				xInput.select();
			}
		}).change(function() {
			xInput.value = parseFloat(xInput.value).toFixed(3);
			xCol.setAttribute('data-x', xInput.value);
			xInput.select();

			that.set({
				colormode: 'xy',
				x: parseFloat(xInput.value),
				y: that.y
			}).done(function(data) {
				if(xInput === document.activeElement) {
					xInput.value = data.x.toFixed(3);
					xInput.select();
				}
			});
		});
		this.addElement('x', function(value) {
			if(xInput !== document.activeElement || xInput.value === xCol.getAttribute('data-x')) {
				xInput.value = value.toFixed(3);
				xCol.setAttribute('data-x', xInput.value);
				if(xInput === document.activeElement) {
					xInput.select();
				}
			}
		});

		var yCol = document.createElement('td');
		yCol.className = 'hue_light_y';
		yCol.setAttribute('data-y', this.y.toFixed(3));
		yCol.innerHTML = '<input form="' + formId + '" name="y" type="number" ' +
			'min="0.0" may="1.0" step="any" value="' + this.y.toFixed(3) + '">';
		this.lightRow.appendChild(yCol);

		var yInput = yCol.firstElementChild;
		$(yInput).blur(function() {
			yInput.value = that.y.toFixed(3);
		}).keyup(function(ev) {
			if(ev.keyCode == 27) {
				yInput.value = that.y.toFixed(3);
				yInput.select();
			}
		}).change(function() {
			yInput.value = parseFloat(yInput.value).toFixed(3);
			yCol.setAttribute('data-y', yInput.value);
			yInput.select();

			that.set({
				colormode: 'xy',
				y: parseFloat(yInput.value),
				x: that.x
			}).done(function(data) {
				if(yInput === document.activeElement) {
					yInput.value = data.y.toFixed(3);
					yInput.select();
				}
			});
		});
		this.addElement('y', function(value) {
			if(yInput !== document.activeElement || yInput.value === yCol.getAttribute('data-y')) {
				yInput.value = value.toFixed(3);
				yCol.setAttribute('data-y', yInput.value);
				if(yInput === document.activeElement) {
					yInput.select();
				}
			}
		});

		var hueCol = document.createElement('td');
		hueCol.className = 'hue_light_hue';
		hueCol.setAttribute('data-hue', this.hue.toFixed(1));
		hueCol.innerHTML = '<input form="' + formId + '" name="hue" type="number" ' +
			'min="0" max="359.9" step="0.1" value="' + this.hue.toFixed(1) + '">';
		this.lightRow.appendChild(hueCol);

		var hueInput = hueCol.firstElementChild;
		$(hueInput).blur(function() {
			hueInput.value = that.hue.toFixed(1);
		}).keyup(function(ev) {
			if(ev.keyCode == 27) {
				hueInput.value = that.hue.toFixed(1);
				hueInput.select();
			}
		}).change(function() {
			hueInput.value = parseFloat(hueInput.value).toFixed(1);
			hueCol.setAttribute('data-hue', hueInput.value);
			hueInput.select();

			that.set({
				colormode: 'hs',
				hue: parseFloat(hueInput.value),
				sat: that.sat
			}).done(function(data) {
				if(hueInput === document.activeElement) {
					hueInput.value = data.hue.toFixed(1);
					hueInput.select();
				}
			});
		});
		this.addElement('hue', function(value) {
			if(hueInput !== document.activeElement || hueInput.value === hueCol.getAttribute('data-hue')) {
				hueInput.value = value.toFixed(1);
				hueCol.setAttribute('data-hue', hueInput.value);
				if(hueInput === document.activeElement) {
					hueInput.select();
				}
			}
		});

		var satCol = document.createElement('td');
		satCol.className = 'hue_light_sat';
		satCol.setAttribute('data-sat', this.sat);
		satCol.innerHTML = '<input form="' + formId + '" name="sat" type="number" ' +
			'min="0" max="255" step="1" value="' + this.sat + '">';
		this.lightRow.appendChild(satCol);

		var satInput = satCol.firstElementChild;
		$(satInput).blur(function() {
			satInput.value = that.sat;
		}).keyup(function(ev) {
			if(ev.keyCode == 27) {
				satInput.value = that.sat;
				satInput.select();
			}
		}).change(function() {
			satInput.value = parseInt(satInput.value);
			satCol.setAttribute('data-sat', satInput.value);
			satInput.select();

			that.set({
				colormode: 'hs',
				sat: parseInt(satInput.value),
				hue: that.hue
			}).done(function(data) {
				if(satInput === document.activeElement) {
					satInput.value = data.sat;
					satInput.select();
				}
			});
		});
		this.addElement('sat', function(value) {
			if(satInput !== document.activeElement || satInput.value === satCol.getAttribute('data-sat')) {
				satInput.value = value;
				satCol.setAttribute('data-sat', satInput.value);
				if(satInput === document.activeElement) {
					satInput.select();
				}
			}
		});

		var presetCol = document.createElement('td');
		presetCol.className = 'hue_light_preset';
		presetCol.innerHTML = '<select form="' + formId + '" name="preset">' +
			'<!-- TODO: use HTML popup instead of select -->' +
			'<option>&mdash;&mdash;&mdash;&mdash;</option>' +
			'<option data-colormode="ct" data-ct="369">2710K</option>' +
			'<option data-colormode="ct" data-ct="200">5000K</option>' +
			'<option data-colormode="ct" data-ct="154">6500K</option>' +
			'<option data-colormode="hs" data-hue="0" data-sat="255">Red</option>' +
			'<option data-colormode="hs" data-hue="30" data-sat="255">Orange</option>' +
			'<option data-colormode="hs" data-hue="90" data-sat="255">Yellow</option>' +
			'<option data-colormode="hs" data-hue="138" data-sat="255">Green</option>' +
			'<option data-colormode="hs" data-hue="231" data-sat="236">Sky Blue</option>' +
			'<option data-colormode="hs" data-hue="258" data-sat="255">Blue</option>' +
			'<option data-colormode="hs" data-hue="271" data-sat="255">Purple</option>' +
			'<option data-colormode="hs" data-hue="310" data-sat="190">Pink</option>' +
			'<option data-colormode="hs" data-hue="320" data-sat="255">Magenta</option>' +
			'</select>';
		this.lightRow.appendChild(presetCol);

		var preset = presetCol.firstElementChild;
		var presetTimer = null;
		$(preset).change(function() {
			var option = preset.options[preset.selectedIndex];
			var colormode = option.getAttribute('data-colormode');

			var params;

			switch(colormode) {
				case 'ct':
					params = {
						colormode: 'ct',
						ct: parseInt(option.getAttribute('data-ct'))
					};
					break;

				case 'xy':
					params = {
						colormode: 'xy',
						x: parseFloat(option.getAttribute('data-x')),
						y: parseFloat(option.getAttribute('data-y')),
					};
					break;

				case 'hs':
					params = {
						colormode: 'hs',
						hue: parseFloat(option.getAttribute('data-hue')),
						sat: parseInt(option.getAttribute('data-sat')),
					};
					break;
			}

			that.set(params).always(function() {
				if(presetTimer) {
					clearTimeout(presetTimer);
				}
				presetTimer = setTimeout(function() {
					preset.selectedIndex = 0;
					presetTimer = null;
				}, 400);
			});
		});

		return this.lightRow;
	},
}
$.extend(KNC.Hue.Light.prototype, KNC.Hue.DataSync);

// Pass {id: [scene id]} as info for scenes created from HTML.
KNC.Hue.Scene = function(bridge, info) {
	this.bridge = bridge;
	this.lights = [];
	this.handleJSON(info);

	var jqSceneRow = $('tr.hue_bridge_detail[data-serial="' + bridge.serial +
			'"] .hue_scene_row[data-id="' + info.id + '"]').first();
	if(jqSceneRow.length > 0) {
		this.name = jqSceneRow.find('td.hue_scene_name').text().trim();
		this.lights = jqSceneRow.find('td.hue_scene_lights').text().trim()
			.split(', ').map(function(el) { return parseInt(el); });
	}
}
KNC.Hue.Scene.prototype = {
	handleJSON: function(info) {
		if(info.name != this.name) {
			this.notifyElements('name', info.name);
		}

		for(var i in this.lights) {
			if(!info.lights || info.lights[i] !== this.lights[i]) {
				this.notifyElements('lights', info.lights.join(', '));
				break;
			}
		}

		this.info = info;
		$.extend(this, info);
	},

	// Recalls this scene.  Also flashes the scene's table row.
	recall: function() {
		if(this.sceneRow.classList.contains("disabled")) {
			return;
		}

		var that = this;
		this.bridge.recallScene(this.id).done(function(data) {
			console.log("Recalled scene " + that.id + " on bridge " + that.bridge.serial);
			if(that.sceneRow) {
				that.sceneRow.style.opacity = 0.25;
				setTimeout(function() { that.sceneRow.style.opacity = null; }, 500);
			}
		});
	},

	// Removes this scene's HTML (called by delete and when a scene disappears from the bridge)
	removeHTML: function() {
		var sceneHTML = this.html();
		if(sceneHTML.parentNode) {
			sceneHTML.parentNode.removeChild(sceneHTML);
		}
	},

	// Deletes this scene.
	delete: function() {
		if(this.sceneRow.classList.contains("disabled")) {
			return;
		}

		var that = this;
		this.sceneRow.className = 'hue_scene_row disabled'
		this.bridge.deleteScene(this.id).done(function(data) {
			console.log("Deleted scene" + that.id + " on bridge " + that.bridge.serial);
			that.removeHTML();
		}).fail(function() {
			that.sceneRow.className = 'hue_scene_row';
		});
	},

	// Returns an element containing the table row for this scene, creating
	// it if necessary.
	html: function() {
		var that = this;

		if(this.sceneRow instanceof Element) {
			return this.sceneRow;
		}

		this.sceneRow = document.createElement('tr');
		this.sceneRow.className = 'hue_scene_row';
		this.sceneRow.title = 'Click to activate this scene.';
		this.sceneRow.setAttribute('data-id', this.id);
		this.sceneRow.onclick = function() {
			that.recall();
		}

		var idCol = document.createElement('td');
		idCol.className = 'hue_scene_id';
		idCol.appendChild(document.createTextNode(this.id));
		this.sceneRow.appendChild(idCol);

		var nameCol = document.createElement('td');
		nameCol.className = 'hue_scene_name';
		nameCol.appendChild(document.createTextNode(this.name));
		this.sceneRow.appendChild(nameCol);
		this.addElement('name', nameCol);

		var lightsCol = document.createElement('td');
		lightsCol.className = 'hue_scene_lights';
		lightsCol.appendChild(document.createTextNode(this.lights.join(', ')));
		this.sceneRow.appendChild(lightsCol);
		this.addElement('lights', lightsCol);

		var deleteCol = document.createElement('td');
		deleteCol.title = 'Click to delete this scene.';
		deleteCol.className = 'hue_scene_delete';
		deleteCol.appendChild(document.createTextNode('Delete'));
		deleteCol.onclick = function(ev) {
			ev.preventDefault();
			ev.stopPropagation();
			that.delete();
			return false;
		}
		this.sceneRow.appendChild(deleteCol);
		this.addElement('delete', deleteCol);

		return this.sceneRow;
	},
}
$.extend(KNC.Hue.Scene.prototype, KNC.Hue.DataSync);

// Pass {id: [group id]} as info for groups created from HTML.
KNC.Hue.Group = function(bridge, info) {
	this.bridge = bridge;
	this.lights = [];
	this.handleJSON(info);

	var jqGroupRow = $('tr.hue_bridge_detail[data-serial="' + bridge.serial +
			'"] .hue_group_row[data-id="' + info.id + '"]').first();
	if(jqGroupRow.length > 0) {
		this.name = jqGroupRow.find('td.hue_group_name').text().trim();
		this.lights = jqGroupRow.find('td.hue_group_lights').text().trim()
			.split(', ').map(function(el) { return parseInt(el); });
	}
}
KNC.Hue.Group.prototype = {
	handleJSON: function(info) {
		if(info.name != this.name) {
			this.notifyElements('name', info.name);
		}

		for(var i in this.lights) {
			if(!info.lights || info.lights[i] !== this.lights[i]) {
				this.notifyElements('lights', info.lights.join(', '));
				break;
			}
		}

		this.info = info;
		$.extend(this, info);
	},

	// Sends the given set of parameters to this group.
	set: function(params) {
		return this.bridge.setGroup(this.id, params);
	},

	// Flashes this group.  Also flashes the group's table row.
	flash: function() {
		if(this.groupRow.classList.contains("disabled")) {
			return;
		}

		var that = this;
		this.set({alert: 'select'}).done(function(data) {
			console.log("Flashed group " + that.id + " on bridge " + that.bridge.serial);
			if(that.groupRow) {
				that.groupRow.style.opacity = 0.25;
				setTimeout(function() { that.groupRow.style.opacity = null; }, 500);
			}
		});
	},

	// Removes this group's HTML (called by delete and when a group disappears from the bridge)
	removeHTML: function() {
		var groupHTML = this.html();
		if(groupHTML.parentNode) {
			groupHTML.parentNode.removeChild(groupHTML);
		}
	},

	// Deletes this group.
	delete: function() {
		if(this.groupRow.classList.contains("disabled")) {
			return;
		}

		var that = this;
		this.groupRow.className = 'hue_group_row disabled';
		this.bridge.deleteGroup(this.id).done(function(data) {
			console.log("Deleted group" + that.id + " on bridge " + that.bridge.serial);
			that.removeHTML();
		}).fail(function() {
			that.groupRow.className = 'hue_group_row';
		});
	},

	// Returns an element containing the table row for this group, creating
	// it if necessary.
	html: function() {
		var that = this;

		if(this.groupRow instanceof Element) {
			return this.groupRow;
		}

		this.groupRow = document.createElement('tr');
		this.groupRow.className = 'hue_group_row';
		this.groupRow.title = 'Click to identify this group.';
		this.groupRow.setAttribute('data-id', this.id);
		this.groupRow.onclick = function() {
			that.flash();
		}

		var idCol = document.createElement('td');
		idCol.className = 'hue_group_id';
		idCol.appendChild(document.createTextNode(this.id));
		this.groupRow.appendChild(idCol);

		var nameCol = document.createElement('td');
		nameCol.className = 'hue_group_name';
		nameCol.appendChild(document.createTextNode(this.name));
		this.groupRow.appendChild(nameCol);
		this.addElement('name', nameCol);

		var lightsCol = document.createElement('td');
		lightsCol.className = 'hue_group_lights';
		lightsCol.appendChild(document.createTextNode(this.lights.join(', ')));
		this.groupRow.appendChild(lightsCol);
		this.addElement('lights', lightsCol);

		var deleteCol = document.createElement('td');
		if(this.id != 0) {
			deleteCol.title = 'Click to delete this group.';
			deleteCol.className = 'hue_group_delete';
			deleteCol.appendChild(document.createTextNode('Delete'));
			deleteCol.onclick = function(ev) {
				ev.preventDefault();
				ev.stopPropagation();
				that.delete();
				return false;
			}
		}
		this.groupRow.appendChild(deleteCol);
		this.addElement('delete', deleteCol);

		return this.groupRow;
	},
}
$.extend(KNC.Hue.Group.prototype, KNC.Hue.DataSync);


$(function() {
	var enabled = $('#hue_enabled');
	var bridges = $('#hue_bridges');
	var err = $('#hue_errors');

	KNC.Hue.hueErrorText = function(text) {
		return KNC.errorText(err, text);
	}

	// Starts a bridge discovery process (if one is not already running).
	// Returns the request generated by $.post().
	function startDisco() {
		return $.post('/settings/hue/disco').fail(function(data) {
			var text = data.responseText || '';
			console.log('Error starting Hue bridge discovery: ' + text);
			KNC.Hue.hueErrorText('Error starting Hue bridge discovery: ' + text);
		});
	}

	function enableHue(enabled) {
		console.log("Enable hue: " + enabled);
		$.post('/settings/hue', { 'enabled': enabled }).done(
			function(data) {
				handleHueSettings(data);
				KNC.Hue.hueErrorText('');
			})
		.fail(
			function(jqXHR, status, error) {
				console.log('Hue enable error ' + jqXHR.responseText);
				KNC.Hue.hueErrorText("Error " + (enabled ? "enabling" : "disabling") +
					" Hue support: " + (jqXHR.responseText || error || ''));
			});
	}

	function setBridgesVisible(visible, time) {
		KNC.showHide(bridges, visible, time);
	}

	// Sets up bridge disco link
	function setupLinks(elem) {
		$(elem).find('a.hue_disco_link').each(function(idx, elem) {
			var idle_span = $(elem).parents('.hue_disco_idle');
			var running_span = idle_span.parent().find('.hue_disco_running');
			elem.title = 'Bridges are scanned periodically.  Click to scan for Hue bridges now.';
			elem.href = 'javascript:';
			elem.onclick = function() {
				startDisco();
				idle_span.hide();
				running_span.show();
				return false;
			}
		});
	}

	function handleHueEnabled(ev) {
		console.log("Enabled changed: " + enabled[0].checked);
		if(enabled[0].checked) {
			// Show bridges list
			setBridgesVisible(true);

			// Send change to the server
			enableHue(true);
		} else {
			// Hide bridges list
			setBridgesVisible(false);

			// Send change to the server
			enableHue(false);
		}
	}

	function handleHueSettings(data) {
		// Set enabled checkbox
		if(enabled[0].checked != data.enabled) {
			enabled[0].checked = data.enabled;
			setBridgesVisible(enabled[0].checked);
		}

		// Show/hide disco link and indicator
		if(data.discovery) {
			$('.hue_disco_idle').hide();
			$('.hue_disco_running').show();
		} else {
			$('.hue_disco_running').hide();
			$('.hue_disco_idle').show();
		}

		// Update bridges
		KNC.Hue.updateBridges(data.bridges);
	}

	// Hue settings update timer (TODO: Set up long polling on the server side)
	var hueUpdateTimer;
	function updateHueSettings() {
		$.get('/settings/hue').done(function(data) {
			if(KNC.Hue.hueErrorText().match(/^Error getting current settings/)) {
				KNC.Hue.hueErrorText('');
			}
			handleHueSettings(data);
			clearTimeout(hueUpdateTimer);
			hueUpdateTimer = setTimeout(updateHueSettings, 1000);
		}).fail(function(jqXHR, status, error) {
			KNC.Hue.hueErrorText("Error getting current settings from the controller.  " +
				"Make sure the controller is on.  " + (jqXHR.responseText || error || ''));
			clearTimeout(hueUpdateTimer);
			hueUpdateTimer = setTimeout(updateHueSettings, 2000);
		});
	}

	// Add bridges from HTML
	$('tbody.hue_bridge[data-serial]').each(function(idx, el) {
		var serial = el.getAttribute('data-serial');

		try {
			console.log('Adding Hue bridge ' + serial + ' from HTML.');
			KNC.Hue.addBridge(serial);
		} catch(err) {
			console.error('Error adding bridge for serial ' + serial + ': ' + err);
		}
	});

	// Set up click handlers and periodic updates
	setupLinks(document.getElementById('hue_bridges_table'));
	updateHueSettings();

	// Disable form submission, set up dynamic form handlers
	$('#hue_form').submit(function(ev) { ev.preventDefault(); return false; });
	$('#hue_submit').hide().attr('disabled', 'disabled');
	$('#hue_aside').css('display', 'inline');
	enabled.change(handleHueEnabled);
	setBridgesVisible(enabled[0].checked, 0);
});
