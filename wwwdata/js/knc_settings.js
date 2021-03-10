/*
 * JavaScript code for Depth Camera Controller settings page
 * (C)2013 Mike Bourgeous
 */

var KNC = window.KNC || {};

// xAP Settings
$(function() {
	var tbody = $('#xap_endpoints_table tbody');
	var enabled = $('#xap_enabled');
	var uid = $('#xap_uid');
	var epdiv = $('#xap_endpoints');
	var err = $('#xap_errors');

	function xapErrorText(text) {
		return KNC.errorText(err, text);
	}

	function handleXapSettings(obj) {
		// Set enabled checkbox
		if(enabled[0] && enabled[0].checked != obj.enabled) {
			enabled[0].checked = obj.enabled;
			setEndpointsVisible(enabled[0].checked);
		}

		// Set UID field
		if(!uid.is(':focus')) {
			uid.val(obj.uid);
		}

		// Enable/disable endpoint updating
		if(obj.enabled) {
			startEndpoints();
		} else {
			stopEndpoints();
		}
	}

	function handleEndpoints(eps) {
		function makeRow(ep) {
			var row = '<tr><td>' +
				KNC.escape(ep.endpoint).replace(/^(.+:)/, '<span class="xap_addr_prefix">$1</span>') +
				'</td>' +
				'<td>' + ep.uid + '</td>' +
				'<td>' + ep.State + '</td>';

			if(typeof ep.Level === 'object' && ep.Level[0] && ep.Level[1]) {
				row += '<td>' + ep.Level[0] + '/' + ep.Level[1] + '</td>';
			} else {
				row += '<td>&nbsp;</td>';
			}

			return row + '</tr>';
		}

		html = "";
		for(var epName in eps) {
			if(epName == "__status" || !eps.hasOwnProperty(epName)) {
				continue;
			}
			html += makeRow(eps[epName]);
		}
		if(eps.hasOwnProperty("__status")) {
			html += makeRow(eps["__status"]);
		}

		// TODO: Only update cells that have changed
		if(html != tbody.html()) {
			tbody.html(html);
		}
	}

	function enableXap(enabled) {
		console.log("Enable xap: " + enabled);
		$.post('/settings/xap', { 'enabled': enabled }).done(
			function(data) {
				handleXapSettings(data);
				xapErrorText('');
			})
		.fail(
			function(data) {
				console.log('Xap enable error ' + data.responseText);
				xapErrorText("Error " + (enabled ? "enabling" : "disabling") +
					" xAP: " + (data.responseText || ''));
			});
	}

	function setUid(val) {
		console.log("Set UID: " + val);

		// Allow the value to be updated when randomized
		var blur = val.toLowerCase() == 'rand' && uid.is(':focus');

		$.post('/settings/xap', { 'uid': val }).done(
			function(data) {
				if(blur) {
					enabled.focus();
				}
				handleXapSettings(data);
				if(blur) {
					uid.focus();
				}
				xapErrorText('');
			})
		.fail(
			function(data) {
				console.log('Xap set UID error ' + data.responseText);
				xapErrorText("Error setting UID: " + (data.responseText || ''));
			});
	}

	function setEndpointsVisible(visible, time) {
		KNC.showHide(epdiv, visible, time);
	}

	function handleXapEnabled(ev) {
		if(enabled[0] && enabled[0].checked) {
			// Show endpoints list
			setEndpointsVisible(true);

			// Send change to the server
			enableXap(true);
		} else {
			// Hide endpoints list
			setEndpointsVisible(false);

			// Send change to the server
			enableXap(false);
		}
	}

	function handleUid(ev) {
		// Send change to the server
		setUid(uid.val());
		uid.attr('data-orig', uid.val());
	}

	// Disable form submission
	$('#xap_form').submit(function(ev) { ev.preventDefault(); return false; });

	// Hide/show elements as appropriate
	$('#xap_submit').hide().attr('disabled', 'disabled');
	$('#xap_aside').css('display', 'inline');

	enabled.change(handleXapEnabled);
	setEndpointsVisible(enabled[0] && enabled[0].checked, 0);

	uid.change(handleUid);

	// xAP settings update timer (TODO: Set up long polling on the server side)
	var xapUpdateTimer;
	function updateXapSettings() {
		$.get('/settings/xap').done(function(data) {
			if(xapErrorText().match(/^Error getting current settings/)) {
				xapErrorText('');
			}
			handleXapSettings(data);
			clearTimeout(xapUpdateTimer);
			xapUpdateTimer = setTimeout(updateXapSettings, 500);
		}).fail(function(data) {
			xapErrorText("Error getting current settings from the controller.  " +
				"Make sure the controller is on.  " + (data.responseText || ''));
			clearTimeout(xapUpdateTimer);
			xapUpdateTimer = setTimeout(updateXapSettings, 2000);
		});
	}
	updateXapSettings();

	// Endpoint update timer (TODO: Set up long polling on the server side)
	var epTimer = null;
	function updateEndpoints() {
		$.get('/settings/xap/endpoints').done(function(data) {
			if(xapErrorText().match(/^Error getting xAP endpoints/)) {
				xapErrorText('');
			}
			handleEndpoints(data);
			clearTimeout(epTimer);
			epTimer = setTimeout(updateEndpoints, 500);
		}).fail(function(data) {
			if(xapErrorText() == "") {
				xapErrorText("Error getting xAP endpoints from the controller.");
			}
			clearTimeout(epTimer);
			epTimer = setTimeout(updateEndpoints, 2000);
		});
	}

	// Starts the endpoint update timer
	function startEndpoints() {
		if(epTimer == null) {
			updateEndpoints();
		}
	}

	// Stops the endpoint update timer
	function stopEndpoints() {
		if(epTimer != null) {
			clearTimeout(epTimer);
			epTimer = null;
		}
	}
});

// Zone Brightness Settings
$(function() {
	var enabled = $('#bright_enabled');
	var rate = $('#bright_rate');
	var err = $('#bright_errors');

	function brightErrorText(text) {
		return KNC.errorText(err, text);
	}

	function handleBrightSettings(obj, forceUpdate) {
		// Set rate field
		if(!rate.is(':focus') || forceUpdate) {
			rate.val(obj.rate);
			rate.attr('data-orig', rate.val());
		}
	}

	function setRate(val) {
		var intVal = parseInt(val, 10);
		if(isNaN(intVal)) {
			brightErrorText("Invalid rate.  Rate must be an integer.");
			rate.val(rate.attr('data-orig'));
			rate.select();
			return;
		}

		if(intVal < 1000) {
			intVal = 1000;
		}

		console.log("Set zonebright rate: " + intVal);

		if("" + intVal != val) {
			rate.val(intVal);
		}

		$.post('/settings/brightness', { 'rate': intVal }).done(
			function(data) {
				handleBrightSettings(data, true);
				rate.select();
				brightErrorText('');
			})
		.fail(
			function(data) {
				console.log('Bright set rate error ' + data.responseText);
				brightErrorText("Error setting rate: " + (data.responseText || ''));
			});
	}

	function handleRate(ev) {
		// Send change to the server
		setRate(rate.val());
		rate.attr('data-orig', rate.val());
	}

	rate.change(handleRate);

	// Disable form submission
	$('#bright_form').submit(function(ev) { ev.preventDefault(); return false; });

	// Hide/show elements as appropriate
	$('#bright_submit').hide().attr('disabled', 'disabled');

	// Bright settings update timer (TODO: long polling)
	// TODO: Generalize/merge xAP and brightness updating code - use angular js?
	var brightUpdateTimer;
	function updateBrightSettings() {
		$.get('/settings/brightness').done(function(data) {
			if(brightErrorText().match(/^Error getting current settings/)) {
				brightErrorText('');
			}
			handleBrightSettings(data);
			clearTimeout(brightUpdateTimer);
			brightUpdateTimer = setTimeout(updateBrightSettings, 500);
		}).fail(function(data) {
			brightErrorText("Error getting current settings from the controller.  " +
				"Make sure the controller is on.  " + (data.responseText || ''));
			clearTimeout(brightUpdateTimer);
			brightUpdateTimer = setTimeout(updateBrightSettings, 2000);
		});
	}
	updateBrightSettings();
});
