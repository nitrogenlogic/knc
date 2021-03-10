/* Single-zone class. (C)2014 Mike Bourgeous */

var KNC = window.KNC || {};

KNC.zones = KNC.zones || {};
KNC.zoneCount = 0;

KNC.zoneAttrs = ['name', 'xmin', 'xmax', 'ymin', 'ymax', 'zmin', 'zmax',
	'px_xmin', 'px_xmax', 'px_ymin', 'px_ymax', 'px_zmin', 'px_zmax', 'xc',
	'yc', 'zc', 'sa', 'bright', 'pop', 'occupied', 'maxpop'];

KNC.zoneColors = [
	["#4060b0", "#1030ff"],
	["#60c070", "#10ff66"],
	["#c95", "#eb8"],
	["#80101c", "#c0101c"],
	];

KNC.XMAX = 3797
KNC.PX_XMAX = 639
KNC.YMAX = 2848
KNC.PX_YMAX = 479
KNC.ZMAX = 7000
KNC.PX_ZMAX = 1092

// Updates the style of the given zone div
KNC.setDivAttrs = function(domDiv, x, y, w, h, z, opacity)
{
	if(domDiv.style.left != x + 'px') {
		domDiv.style.left = x + 'px';
	}
	if(domDiv.style.top != y + 'px') {
		domDiv.style.top = y + 'px';
	}
	if(domDiv.style.width != w + 'px') {
		domDiv.style.width = w + 'px';
	}
	if(domDiv.style.height != h + 'px') {
		domDiv.style.height = h + 'px';
		domDiv.style.lineHeight = domDiv.style.height;
	}
	if(domDiv.style.zIndex != z) {
		domDiv.style.zIndex = z;
	}
	if(domDiv.style.opacity != opacity) {
		domDiv.style.opacity = opacity;
	}
};

// Toggles visibility overriding on the given div
KNC.setDivVisible = function(domDiv, visible)
{
	// TODO: Use a CSS style for zone raising
	if(visible) {
		domDiv.style.visibility = 'visible';
	} else {
		domDiv.style.visibility = 'inherit';
	}
}

// Toggles the occupied flag of the given jQuery-wrapped zone div
KNC.setZoneDivOccupied = function(jqDiv, occupied)
{
	// TODO: Determine whether hasClass() or data() is faster, or whether
	// addClass()/removeClass() can be called repeatedly
	if(occupied && !jqDiv.data('occupied')) {
		jqDiv.addClass('occupied');
		jqDiv.data('occupied', true);
	} else if(!occupied && jqDiv.data('occupied')) {
		jqDiv.removeClass('occupied');
		jqDiv.data('occupied', false);
	}
}

// pix* functions return an object containing x: and y: pixel coordinates
// relative to the view div.
KNC.pixPerspective = function(xw, yw, zw)
{
	return {
		// tan(28) ~= 0.53171
		x: 320 * (1 - xw / (zw * .53171)),
		y: 320 * (1 - yw / (zw * .53171)) - 80
	};
}

KNC.pixOverhead = function(xw, yw, zw)
{
	return {
		x: 250 + xw * 250 / KNC.XMAX,
		y: zw * 500 / KNC.ZMAX - 10
	};
}

KNC.pixSide = function(xw, yw, zw)
{
	return {
		x: zw * 500 / KNC.ZMAX,
		y: 240 - yw * 250 / KNC.YMAX
	};
}

KNC.pixFront = function(xw, yw, zw)
{
	return {
		x: 250 - xw * 250 / KNC.XMAX,
		y: 240 - yw * 250 / KNC.YMAX
	};
}

KNC.recolorZones = function()
{
	var i = 1;
	$.each(KNC.zones, function(name, zone) {
		$.each(zone.elements, function(k, div) {
			$(div).removeClass('c1')
				.removeClass('c2')
				.removeClass('c3')
				.removeClass('c4')
				.addClass('c' + i);
		});

		$(zone.titleDiv).removeClass('c1')
			.removeClass('c2')
			.removeClass('c3')
			.removeClass('c4')
			.addClass('c' + i);

		i = i + 1;
		if(i > KNC.zoneColors.length) {
			i = 1;
		}
	});
}

// Finds an existing or creates a new zone div for the named zone on the given
// named view.  Does not set the zone div's style.
KNC.findCreateZoneDiv = function(view, name)
{
	var zDiv, jqDiv;

	jqDiv = $('#' + view + '_' + name);
	if(jqDiv.length > 0) {
		zDiv = jqDiv[0];
		jqDiv.removeClass('occupied');
	} else {
		zDiv = document.createElement('div');
		zDiv.id = view + '_' + name;
		$(zDiv).attr('data-zone', name)
			.addClass('zone ' + view + '_zone')
			.addClass('c' + (KNC.zoneCount % KNC.zoneColors.length + 1));

		zDiv.innerHTML = '<span class="name_' + name + '">' + name + '</span>';

		$('[data-view="' + view + '"] .zonewrap')[0].appendChild(zDiv);
	}

	// Create center-of-gravity visualization div
	var cogVis = document.createElement('div');
	cogVis.id = 'cog_' + name;
	$(cogVis).addClass('cog');
	zDiv.appendChild(cogVis);

	return zDiv;
};

// Adds a new zone to all views
KNC.Zone = function(attrs) {
	var that = this;

	// Store attributes
	$.each(attrs, function(k, v) {
		attrs[k] = KNC.checkNum(v);
		that[k] = attrs[k];
	});

	var name = attrs['name'];
	var xmin = parseFloat(attrs['xmin']);
	var xmax = parseFloat(attrs['xmax']);
	var ymin = parseFloat(attrs['ymin']);
	var ymax = parseFloat(attrs['ymax']);
	var zmin = parseFloat(attrs['zmin']);
	var zmax = parseFloat(attrs['zmax']);
	var px_xmin = parseInt(attrs['px_xmin'], 10);
	var px_xmax = parseInt(attrs['px_xmax'], 10);
	var px_ymin = parseInt(attrs['px_ymin'], 10);
	var px_ymax = parseInt(attrs['px_ymax'], 10);
	var px_zmin = parseInt(attrs['px_zmin'], 10);
	var px_zmax = parseInt(attrs['px_zmax'], 10);
	var xc = parseFloat(attrs['xc']);
	var yc = parseFloat(attrs['yc']);
	var zc = parseFloat(attrs['zc']);
	var sa = parseFloat(attrs['sa']);
	var pop = parseInt(attrs['pop'], 10);
	var maxpop = parseInt(attrs['maxpop'], 10);
	var occupied = attrs['occupied'] == 'true';
	var bright = parseInt(attrs['bright']);

	that.elements = [];

	// Generates a table row element for attributes named in attr1 and attr2
	function tableRow(attrs, attr1, attr2) {
		var tr = document.createElement('tr');
		var html = '';
		if(attr1 != null) {
			html += '<th>' + attr1 + ':</th>';
			html += '<td><span class="' + attr1 + '_' + name + '">' + attrs[attr1] + '</span></td>';
		} else {
			html += '<th></th><td></td>';
		}
		if(attr2 != null) {
			html += '<th>' + attr2 + ':</th>';
			html += '<td><span class="' + attr2 + '_' + name + '">' + attrs[attr2] + '</span></td>';
		} else {
			html += '<th></th><td></td>';
		}
		tr.innerHTML = html;

		return tr;
	}

	function findCreateListDiv(name) {
		var create = true;
		var listDiv, titleDiv, listTable;
		var jqDiv;

		// Create list entry container div
		jqDiv = $('.list_zone[data-zone="' + name + '"]');
		if(jqDiv.length > 0) {
			listDiv = jqDiv[0];
		} else {
			listDiv = document.createElement('div');
			listDiv.id = 'list_' + name;
			$(listDiv).attr("data-zone", name)
				.addClass('list_zone')
				.addClass('c' + (KNC.zoneCount % KNC.zoneColors.length + 1));
		}

		// Create title div
		jqDiv = $(listDiv).find('div.zonetitle');
		if(jqDiv.length > 0) {
			titleDiv = jqDiv[0];
		} else {
			titleDiv = document.createElement('div');
			$(titleDiv).addClass('zonetitle')
				.addClass('c' + (KNC.zoneCount % KNC.zoneColors.length + 1));
			var titleHTML = name + '<a class="rmzone_button" rel="nofollow" href="/rmzone?name=' + name + '">';
			titleHTML += '  <span class="ui-icon ui-icon-close"></span>';
			titleHTML += '</a>';
			titleDiv.innerHTML = titleHTML;
			listDiv.appendChild(titleDiv);
		}
		$(titleDiv).find('.rmzone_button').click(function(ev) {
			ev.preventDefault();
			deleteZone(name);
			return false;
		});

		// Create table
		jqDiv = $(listDiv).find('table');
		if(jqDiv.length > 0) {
			listTable = jqDiv[0];
		} else {
			listTable = document.createElement('table');
			listTable.id = 'list_table_' + name;

			for(var i = 1; i < KNC.zoneAttrs.length; i += 2) {
				listTable.appendChild(tableRow(attrs, KNC.zoneAttrs[i], KNC.zoneAttrs[i + 1]));
			}

			listDiv.appendChild(listTable);
		}
		$(listTable).hide();
		that.tableHidden = true;

		that.titleDiv = titleDiv;
		that.listDiv = listDiv;
		that.listTable = listTable;
		that.elements.push(listDiv);

		if(create) {
			document.getElementById('zonelist')
				.insertBefore(listDiv, document.getElementById('zonelist_help'));
		}

		$(titleDiv).click(function() {
			resetActivityTimer();
			that.tableHidden = !that.tableHidden;
			if(that.tableHidden) {
				$(that.listTable).hide();
			} else {
				$(that.listTable).show();
			}
			that.update({});
		});
	}

	// Create zone list entry
	findCreateListDiv(name);

	// Create perspective view zone box
	var perspDiv = KNC.findCreateZoneDiv('perspective', name);
	KNC.setDivAttrs(
			perspDiv,
			px_xmin, px_ymin,
			px_xmax - px_xmin,
			px_ymax - px_ymin,
			Math.max(10, 1100 - px_zmin),
			0.4 + Math.min(0.35, 2.0 * pop / maxpop)
			);
	that.perspDiv = perspDiv;
	that.elements.push(perspDiv);

	// Create overhead view zone box
	var ovhDiv = KNC.findCreateZoneDiv('overhead', name);
	KNC.setDivAttrs(
			ovhDiv,
			Math.round(250 + xmin * 250 / KNC.XMAX),
			Math.round(zmin * 500 / KNC.ZMAX - 10),
			Math.round((xmax - xmin) * 250 / KNC.XMAX),
			Math.round((zmax - zmin) * 500 / KNC.ZMAX),
			Math.round(Math.max(10, 5000 + ymax * 1000)),
			0.6 + Math.min(0.35, 2.0 * pop / maxpop)
			);
	that.ovhDiv = ovhDiv;
	that.elements.push(ovhDiv);

	// Create side view zone box
	var sideDiv = KNC.findCreateZoneDiv('side', name);
	KNC.setDivAttrs(
			sideDiv,
			Math.round(zmin * 500 / KNC.ZMAX),
			Math.round(240 - ymax * 250 / KNC.YMAX),
			Math.round((zmax - zmin) * 500 / KNC.ZMAX),
			Math.round((ymax - ymin) * 250 / KNC.YMAX),
			Math.round(Math.max(10, 5000 - xmin * 1000)),
			0.6 + Math.min(0.35, 2.0 * pop / maxpop)
			);
	that.sideDiv = sideDiv;
	that.elements.push(sideDiv);

	// Create front view zone box
	var frontDiv = KNC.findCreateZoneDiv('front', name);
	KNC.setDivAttrs(
			frontDiv,
			Math.round(250 - xmax * 250 / KNC.XMAX),
			Math.round(240 - ymax * 250 / KNC.YMAX),
			Math.round((xmax - xmin) * 250 / KNC.XMAX),
			Math.round((ymax - ymin) * 250 / KNC.YMAX),
			Math.max(10, 1100 - px_zmin),
			0.6 + Math.min(0.35, 2.0 * pop / maxpop)
			);
	that.frontDiv = frontDiv;
	that.elements.push(frontDiv);

	// Create video view zone box
	// FIXME: depth+video registration
	var videoDiv = KNC.findCreateZoneDiv('video', name);
	KNC.setDivAttrs(
			videoDiv,
			px_xmin, px_ymin,
			px_xmax - px_xmin,
			px_ymax - px_ymin,
			Math.max(10, 1100 - px_zmin),
			0.4 + Math.min(2.0 * bright / 1000, 0.5)
			);
	that.videoDiv = videoDiv;
	that.elements.push(videoDiv);

	$.each({persp: 'perspective', ovh: 'overhead', side: 'side', front: 'front', video: 'video'}, function(sView, lView) {
		var jqd = $(that[sView + 'Div']);
		// TODO: Use reference count instead of true/false for dragging/resizing, clear old timeout
		jqd.draggable({
			containment: 'parent',
			start: function(ev, ui) { jqd.data('dragging', true); ev.stopPropagation(); },
			drag: function(ev, ui) { that.updateFromDiv(lView); },
			stop: function(ev, ui) {
				that.updateFromDiv(lView);
				setTimeout(function(){ jqd.data('dragging', false); }, 350);
			}
		})
		.resizable({
			containment: 'parent',
			handles: 'all',
			minWidth: 16,
			minHeight: 16,
			start: function(ev, ui) { jqd.data('resizing', true); ev.stopPropagation(); },
			resize: function(ev, ui) {
				that.updateFromDiv(lView);
				this.style.lineHeight = this.style.height;
			},
			stop: function(ev, ui) {
				that.updateFromDiv(lView);
				setTimeout(function(){ jqd.data('resizing', false); }, 350);
			      }
		});
	});

	// Store attribute elements (i.e. px_zmax: [xyz])
	// TODO: Use HTML5 data- attributes instead of CSS classes/IDs
	that.attr_elements = {};
	$.each(KNC.zoneAttrs, function(k, v) {
		that.attr_elements[v] = $('.' + v + '_' + name);
	});

	KNC.zones[name] = that;
	KNC.zoneCount++;
}

KNC.Zone.prototype = {
	// Returns the absolute CoG of the zone as array of [x, y, z] (in millimeters)
	getCog: function() {
		var that = this;
		var xp = that.xc * (that.xmax - that.xmin) / 1000 + that.xmin;
		var yp = that.yc * (that.ymax - that.ymin) / 1000 + that.ymin;
		var zp = that.zc * (that.zmax - that.zmin) / 1000 + that.zmin;
		return [xp, yp, zp];
	},
	remove: function() {
		console.log('Deleting zone ' + this['name']);
		$.each(this.elements, function(key, elem) {
			elem.parentNode.removeChild(elem);
		});
		delete KNC.zones[this['name']];
		KNC.zoneCount--;
		KNC.recolorZones();
	},
	updateFromDiv: function(view) { // Called when the user changes a zone rect
		var that = this;
		resetActivityTimer();
		switch(view) {
			case 'perspective':
				setZonePerspective($(that.perspDiv));
				break;
			case 'overhead':
				setZoneOverhead($(that.ovhDiv));
				break;
			case 'front':
				setZoneFront($(that.frontDiv));
				break;
			case 'side':
				setZoneSide($(that.sideDiv));
				break;
			case 'video':
				setZonePerspective($(that.videoDiv));
				break;
		}
	},
	update: function(attrs) {
		var that = this;
		$.each(attrs, function(k, v) {
			var val = KNC.checkNum(v);
			if(that[k] != val) {
				that[k] = val;
				if(that.attr_elements.hasOwnProperty(k)) {
					that.attr_elements[k].text(val);
				}
			}
		});

		KNC.setZoneDivOccupied($(that.listDiv), that.occupied);

		that.updatePerspective();
		that.updateOverhead();
		that.updateSide();
		that.updateFront();
		that.updateVideo(); // FIXME: depth+video registration
	},
	updatePerspective: function() {
		var that = this;
		var div = that.perspDiv;
		var jqDiv = $(div);
		if(jqDiv.data('resizing') == true || jqDiv.data('dragging') == true) {
			return;
		}
		KNC.setZoneDivOccupied(jqDiv, that.occupied);
		KNC.setDivAttrs(
				div,
				that.px_xmin, that.px_ymin,
				that.px_xmax - that.px_xmin,
				that.px_ymax - that.px_ymin,
				Math.max(10, (that.tableHidden ? 1100 : 2200) - that.px_zmin),
				(that.tableHidden ? 0.4 : 0.6) + Math.min(0.35, 2.0 * that.pop / that.maxpop) + (jqDiv.is(':hover') ? 0.15 : 0.0)
				);
		KNC.setDivVisible(div, !that.tableHidden);

		// TODO: Simplify CoG indicator updating (add abstraction)
		if(that.occupied) {
			var cogVis = jqDiv.find('.cog')[0];
			var cog = that.getCog();
			var c = KNC.pixPerspective(cog[0], cog[1], cog[2]);
			c.x -= that.px_xmin + 4; // + 4 for border/size of CoG indicator
			c.y -= that.px_ymin + 4;
			cogVis.style.left = Math.round(c.x) + 'px';
			cogVis.style.top = Math.round(c.y) + 'px';
		}
	},
	updateOverhead: function() {
		var that = this;
		var div = that.ovhDiv;
		var jqDiv = $(div);
		if(jqDiv.data('resizing') == true || jqDiv.data('dragging') == true) {
			return;
		}
		KNC.setZoneDivOccupied(jqDiv, that.occupied);
		KNC.setDivAttrs(
				div,
				Math.round(250 + that.xmin * 250 / KNC.XMAX),
				Math.round(that.zmin * 500 / KNC.ZMAX - 10),
				Math.round((that.xmax - that.xmin) * 250 / KNC.XMAX),
				Math.round((that.zmax - that.zmin) * 500 / KNC.ZMAX),
				Math.round(Math.max(10, (that.tableHidden ? 5000 : 15000) + that.ymax * 1000)),
				(that.tableHidden ? 0.4 : 0.6) + Math.min(0.35, 2.0 * that.pop / that.maxpop) + (jqDiv.is(':hover') ? 0.2 : 0.0)
				);
		KNC.setDivVisible(div, !that.tableHidden);

		// TODO: Simplify CoG indicator updating (add abstraction)
		if(that.occupied) {
			var cogDiv = jqDiv.find('.cog')[0];
			var cog = that.getCog();
			var c = KNC.pixOverhead(cog[0], cog[1], cog[2]);
			var m = KNC.pixOverhead(that.xmin, that.ymin, that.zmin);
			c.x -= m.x + 4; // + 4 for border/size of CoG indicator
			c.y -= m.y + 4;
			cogDiv.style.left = Math.round(c.x) + 'px';
			cogDiv.style.top = Math.round(c.y) + 'px';
		}
	},
	updateSide: function() {
		var that = this;
		var div = that.sideDiv;
		var jqDiv = $(div);
		if(jqDiv.data('resizing') == true || jqDiv.data('dragging') == true) {
			return;
		}
		KNC.setZoneDivOccupied(jqDiv, that.occupied);
		KNC.setDivAttrs(
				div,
				Math.round(that.zmin * 500 / KNC.ZMAX),
				Math.round(240 - that.ymax * 250 / KNC.YMAX),
				Math.round((that.zmax - that.zmin) * 500 / KNC.ZMAX),
				Math.round((that.ymax - that.ymin) * 250 / KNC.YMAX),
				Math.round(Math.max(10, (that.tableHidden ? 5000 : 15000) - that.xmin * 1000)),
				(that.tableHidden ? 0.4 : 0.6) + Math.min(0.35, 2.0 * that.pop / that.maxpop) + (jqDiv.is(':hover') ? 0.2 : 0.0)
				);
		KNC.setDivVisible(div, !that.tableHidden);

		// TODO: Simplify CoG indicator updating (add abstraction)
		if(that.occupied) {
			var cogDiv = jqDiv.find('.cog')[0];
			var cog = that.getCog();
			var c = KNC.pixSide(cog[0], cog[1], cog[2]);
			var m = KNC.pixSide(that.xmin, that.ymax, that.zmin);
			c.x -= m.x + 4; // + 4 for border/size of CoG indicator
			c.y -= m.y + 4;
			cogDiv.style.left = Math.round(c.x) + 'px';
			cogDiv.style.top = Math.round(c.y) + 'px';
		}
	},
	updateFront: function() {
		var that = this;
		var div = that.frontDiv;
		var jqDiv = $(div);
		if(jqDiv.data('resizing') == true || jqDiv.data('dragging') == true) {
			return;
		}
		KNC.setZoneDivOccupied(jqDiv, that.occupied);
		KNC.setDivAttrs(
				div,
				Math.round(250 - that.xmax * 250 / KNC.XMAX),
				Math.round(240 - that.ymax * 250 / KNC.YMAX),
				Math.round((that.xmax - that.xmin) * 250 / KNC.XMAX),
				Math.round((that.ymax - that.ymin) * 250 / KNC.YMAX),
				Math.max(10, (that.tableHidden ? 1100 : 2200) - that.px_zmin),
				(that.tableHidden ? 0.2 : 0.5) + Math.min(0.35, 2.0 * that.pop / that.maxpop) + (jqDiv.is(':hover') ? (that.tableHidden ? 0.4 : 0.3) : 0.0)
				);
		KNC.setDivVisible(div, !that.tableHidden);

		// TODO: Simplify CoG indicator updating (add abstraction)
		if(that.occupied) {
			var cogDiv = jqDiv.find('.cog')[0];
			var cog = that.getCog();
			var c = KNC.pixFront(cog[0], cog[1], cog[2]);
			var m = KNC.pixFront(that.xmax, that.ymax, that.zmin);
			c.x -= m.x + 4; // + 4 for border/size of CoG indicator
			c.y -= m.y + 4;
			cogDiv.style.left = Math.round(c.x) + 'px';
			cogDiv.style.top = Math.round(c.y) + 'px';
		}
	},
	updateVideo: function() {
		var that = this;
		var div = that.videoDiv;
		var jqDiv = $(div);
		if(jqDiv.data('resizing') == true || jqDiv.data('dragging') == true) {
			return;
		}
		KNC.setZoneDivOccupied(jqDiv, that.occupied);
		KNC.setDivAttrs(
				div,
				that.px_xmin, that.px_ymin,
				that.px_xmax - that.px_xmin,
				that.px_ymax - that.px_ymin,
				Math.max(10, (that.tableHidden ? 1100 : 2200) - that.px_zmin),
				0.4 + Math.min(2.0 * that.bright / 1000, 0.5) + (jqDiv.is(':hover') ? 0.15 : 0.0)
				);
		KNC.setDivVisible(div, !that.tableHidden);

		// TODO: Simplify CoG indicator updating (add abstraction)
		if(that.occupied) {
			var cogDiv = jqDiv.find('.cog')[0];
			var cog = that.getCog();
			var c = KNC.pixPerspective(cog[0], cog[1], cog[2]);
			c.x -= that.px_xmin + 4; // + 4 for border/size of CoG indicator
			c.y -= that.px_ymin + 4;
			cogDiv.style.left = Math.round(c.x) + 'px';
			cogDiv.style.top = Math.round(c.y) + 'px';
		}
	},
};

