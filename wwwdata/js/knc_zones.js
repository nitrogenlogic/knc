/* Zones page scripts. (C)2013 Mike Bourgeous */

var KNC = window.KNC || {};

KNC.zoneRowInterval = 100;
KNC.zoneRowErrorInterval = 500;

KNC.zoneRows = KNC.zoneRows || {};
KNC.zoneRowCount = 0;
KNC.lastAddedZone = null; // Name of the last zone added by Add a Zone (set to null after zone is highlighted)

// Returns the number of zone rows that have extra details visible.
KNC.extraVisibleRows = function() {
	var openCount = 0;

	$.each(KNC.zoneRows, function(name, row) {
		if(row.extraVisible) {
			openCount++;
		}
	});

	return openCount;
}

// Represents a row in the list of zones.  Pass a zone data object parsed from JSON.
KNC.ZoneRow = function(zone) {
	var that = this;

	that.attr_elements = {};

	var name = zone['name'].replace(/[^A-Za-z0-9]+/g, '_');

	// Returns value for template strings
	function templateFunc(str) {
		var str = str.replace(/(^#|#$)/g, '');

		switch(str) {
			case 'ZONEID':
				str = name;
				break;

			case 'ZONENAME':
				str = zone['name'];
				break;

			case 'XMAX':
				str = KNC.XMAX;
				break;
			case 'PX_XMAX':
				str = KNC.PX_XMAX;
				break;

			case 'YMAX':
				str = KNC.YMAX;
				break;
			case 'PX_YMAX':
				str = KNC.PX_YMAX;
				break;

			case 'ZMAX':
				str = KNC.ZMAX;
				break;
			case 'PX_ZMAX':
				str = KNC.PX_ZMAX;
				break;

			default:
				str = '#' + str + '#';
				break;
		}

		return str;
	}

	// Build the row display from the template
	that.row = $(KNC.zoneRowTemplate.html().replace(/#[A-Z]+#/g, templateFunc));
	that.summary = that.row.find('.zone_summary');
	that.extra = that.row.find('tr.zone_extra');
	that.extraWrapper = that.extra.find('div.zone_extra').first();

	// Set up row detail toggle
	that.extraVisible = false;
	KNC.actionEvent(that.row.find('.row_toggle'), function(ev) {
		ev.preventDefault();
		that.showExtra(!that.extraVisible);
		return false;
	});

	// Set up row delete button
	KNC.actionEvent(
			that.row.find('.row_delete'),
			function(ev) {
				ev.preventDefault();
				that.delete();
				return false;
			},
			KNC.keyUp
			);

	// Set handlers on zone name field
	var nameInput = that.row.find('input[data-attr="name"]');
	KNC.keyDown(nameInput, [
			[ 9, function(ev) { if(!ev.shiftKey) { that.showExtra(true); } } ],
			[ 13, function(ev) { /* TODO: Commit change to name field (rename zone) */ } ],
			[ 27, function(ev) { ev.preventDefault(); $(this).val(this.getAttribute('data-value')); this.select(); } ]
			]);
	nameInput.focusout(function() {
		$(this).val(this.getAttribute('data-value'));
	});

	// Store attribute-specific elements for rapid reference during updates
	that.row.find('[data-attr]').each(function(idx, el) {
		var attr = el.getAttribute('data-attr');
		that.attr_elements[attr] = that.attr_elements[attr] || [];
		that.attr_elements[attr].push(el);
	});

	// Set up input events on extra details input fields
	var extraInputs = that.extra.find('input[data-attr], select[data-attr]');
	KNC.inputEvents(extraInputs, function(val) {
		that.setAttribute(this.getAttribute('data-attr'), val);
	});

	// Add zone attributes to this zone row object
	that.update(zone);

	KNC.zoneButtonRow.before(that.row);

	that.showExtra(false);

	KNC.zoneRows[zone['name']] = that;
	KNC.zoneRowCount++;
}
KNC.ZoneRow.prototype = {
	remove: function() {
		console.log('Removing zone row ' + this['name']);
		this.row.remove();
		delete KNC.zoneRows[this['name']];
		KNC.zoneRowCount--;
	},

	delete: function() {
		var that = this;
		var dlg = KNC.showDeleteZoneDialog(that.name, function() {
			console.log('Deleting zone ' + that.name);
			var req = KNC.rmZone(that.name);
			req.done(function() {
				that.remove();
			});
			req.fail(function(jqXHR, status, error) {
				KNC.showRequestErrorDialog(
					'Error deleting zone ' + that.name,
					'Error deleting zone ' + that.name,
					jqXHR.responseText,
					status,
					error
					);
			});
		});
	},

	update: function(zone) {
		var that = this;
		$.each(zone, function(attr, val) {
			var val = KNC.checkNum(val);
			if(that[attr] != val) {
				if(that.attr_elements[attr]) {
					if(!KNC.setElements(that.attr_elements[attr], val)) {
						that[attr] = val;
					}
				}
			}
		});
	},

	// Shows/hides the zone's extra details row.
	// visible - Whether to show (true) or hide (false) the row.
	// focus - If true, focuses the row's first input element when made visible.
	showExtra: function(visible, focus) {
		var that = this;

		that.extraVisible = visible;

		if(visible) {
			that.row.addClass('opened');
			that.extra.show();
			KNC.showHide(that.extraWrapper, true, function() {
				if(that.extraVisible) {
					that.extra.show();
					if(focus) {
						that.extra.find('input, select').first().focus();
					}
				}
			});
		} else {
			that.row.removeClass('opened');
			KNC.showHide(that.extraWrapper, false, function() {
				if(!that.extraVisible) {
					that.extra.hide();
				}
			});
		}
	},

	// Calls KNC.setZone() to set the given attribute to the given value.
	setAttribute: function(attribute, value) {
		var info = { name: this.name };
		info[attribute] = value;
		KNC.setZone(info);
	}
}

// Set up row templates
$(function() {
	var template = $('#zone_row_template');
	template.attr('id', null);
	template.css('display', 'table-row-group');
	KNC.zoneRowParent = template.parent();
	KNC.zoneButtonRow = $('#zone_button_row');
	template.remove();
	KNC.zoneRowTemplate = $('<table></table>').append(template);
});

// Set up help toggle
$(function() {
	var help = $('#zones_help');
	var helpLink = $('#zones_help_toggle');
	var visible = help.is(':visible');
	$('#zones_help_toggle').click(function(ev) {
		visible = !visible;
		helpLink.text(visible ? 'Hide Help' : 'Show Help');
		KNC.showHide(help, visible);
		ev.preventDefault();
		return false;
	});
});

// Set up Upload Zones and Remove All Zones links
$(function() {
	$('a.uploadzones').click(function(ev) {
		ev.preventDefault();
		KNC.showUploadZonesDialog();
		// TODO: Make upload asynchronous, or redirect back to /zones instead of /
	});

	$('a.clearzones').click(function(ev) {
		ev.preventDefault();
		KNC.showClearZonesDialog();
	});
});

// Set up add zone button
$(function() {
	$('#add_zone_button').click(function(ev) {
		KNC.showAddZoneDialog(
			'Zone ' + (KNC.zoneRowCount + 1),
			function(name) {
				// Arrange zones in a 3D grid, staggered by vertical layer
				var x = (KNC.zoneRowCount % 7) * 1000 - 3500;
				var z = (Math.floor(KNC.zoneRowCount / 7) % 5) * 1000 + 1000;
				var y = -Math.floor(KNC.zoneRowCount / 35) * 1000;
				var zone = {
					xmin: x + 50 - y/20, xmax: x + 950 - y/20,
					ymin: y + 50, ymax: y + 950,
					zmin: z + 50 - y/20, zmax: z + 950 - y/20,
					name: name
				};

				var dlg = KNC.showPleaseWaitDialog('Adding zone ' + name);
				dlg.dialog({beforeClose: function() { return false; }});

				// TODO: Merge with addZoneForProxy() from knc_main.js
				var req = KNC.addZone(zone);
				req.done(function(html) {
					KNC.lastAddedZone = name;
					dlg.allowClose();
					dlg.dialog('close');
				});
				req.fail(function(jqXHR, status, error) {
					console.error("Error adding zone: " + status + " - " + error);

					dlg.allowClose();
					dlg.dialog('option', 'title', 'Error adding zone');

					if(jqXHR.responseText) {
						dlg.html(jqXHR.responseText);
					} else {
						dlg.text('Error adding zone ' + name + ': ' + status + ' ' + error);
					}
				});
			}
			);
		ev.preventDefault();
		return false;
	});
});

// Set up zone row updates
$(function() {
	var zoneRowTimer;
	var runUpdates = true;
	var firstUpdate = true;

	function zoneUpdater() {
		if(runUpdates) {
			KNC.updateZones(zoneHandler, zoneFail);
		}
	}
	function zoneHandler(data) {
		// Remove dead zones
		var zones = data.zones;
		$.each(KNC.zoneRows, function(name, zone) {
			if(!zones[name]) {
				zone.remove();
			}
		});

		// Add new zones to the list of zones and update existing zones
		var newZones = [];
		$.each(data.zones, function(name, zone) {
			if(KNC.zoneRows[name]) {
				KNC.zoneRows[name].update(zone);
			} else {
				newZones.push(new KNC.ZoneRow(zone));
			}
		});

		// Highlight newly added zones
		if(!firstUpdate && newZones.length > 0) {
			console.log("NEW ZONES"); // XXX
			console.dir(newZones);

			$('.highlight').removeClass('highlight');
			for(var i = 0; i < newZones.length; i++) {
				var z = newZones[i];
				z.summary.addClass('highlight');

				// Open details and focus first input field if this zone
				// was added by the Add a Zone button
				if(z.name == KNC.lastAddedZone) {
					KNC.lastAddedZone = null;

					var active = document.activeElement;
					var inputActive = active instanceof HTMLInputElement ||
						active instanceof HTMLSelectElement;

					z.showExtra(true, !inputActive);
				}
			}
		}

		clearTimeout(zoneRowTimer);
		zoneRowTimer = setTimeout(zoneUpdater, KNC.zoneRowInterval);

		firstUpdate = false;
	}
	function zoneFail() {
		// TODO: Add offline dialog to zones.html
		clearTimeout(zoneRowTimer);
		zoneRowTimer = setTimeout(zoneUpdater, KNC.zoneRowErrorInterval);
	}

	KNC.stopZoneRowUpdates = function() {
		runUpdates = false;
		clearTimeout(KNC.zoneRowTimer);
	}

	KNC.startZoneRowUpdates = function() {
		KNC.stopZoneRowUpdates();
		setTimeout(function() { runUpdates = true; zoneUpdater(); }, 500);
	}

	zoneUpdater();
});
