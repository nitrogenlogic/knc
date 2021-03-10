/* Depth Camera Server JavaScript initialization code - (C)2013 Mike Bourgeous */

var KNC = window.KNC || {};

// TODO: Move this into a namespace
var runZoneUpdates = false;
var runImageUpdates = false;
var zoneTimer;
var zoneInterval = 100;
var zoneErrorInterval = 500;
var imageErrorInterval = 1000;
var imageErrorCountLimit = 5;
var reloadInterval = 5*60*1000;
var activityTimer;
function queueZoneUpdates() {
	if(!runZoneUpdates) {
		runZoneUpdates = true;
		zoneTimer = setTimeout(function() { updateZones(zoneDataHandler); }, zoneInterval);
	}
}
function cancelZoneUpdates() {
	runZoneUpdates = false;
	clearTimeout(zoneTimer);

	// Don't reload the page if there's no background loading going on
	if(!runImageUpdates) {
		stopActivityTimer();
	}
}
function queueImageUpdates() {
	runImageUpdates = true;
	tabShowIndex($('#zonetabs').tabs('option', 'active'));
}
function cancelImageUpdates() {
	runImageUpdates = false;
	stopImage('perspective_image');
	stopImage('overhead_image');
	stopImage('side_image');
	stopImage('front_image');
	stopImage('video_image');

	// Don't reload the page if there's no background loading going on
	if(!runZoneUpdates) {
		stopActivityTimer();
	}
}

function resetActivityTimer() {
	if(activityTimer != null) {
		clearTimeout(activityTimer);
	} else {
		console.log("Starting activity timer.");
	}
	// At an estimated memory leak rate of 2MB/s
	// and a goal of running on 512MB systems, we need
	// to reload once per minute.  Newer versions of
	// Chrome do not have the leak.
	activityTimer = setTimeout(function(){ console.log("Activity timer reloading."); window.location.reload(); }, reloadInterval);
}
function stopActivityTimer() {
	if(activityTimer != null) {
		console.log("Stopping activity timer.");
		clearTimeout(activityTimer);
	}
	activityTimer = null;
}

function zoneDataHandler(data) {
	// Remove dead zones
	var zones = data.zones;
	$.each(KNC.zones, function(name, zone) {
		if(!zones.hasOwnProperty(name)) {
			zone.remove();
		}
	});

	// Add new zones to the list of zones/update existing zones
	$.each(zones, function(name, zone) {
		if(!KNC.zones.hasOwnProperty(name)) {
			new KNC.Zone(zone);
		} else {
			KNC.zones[name].update(zone);
		}
	});

	if(runZoneUpdates) {
		zoneTimer = setTimeout(function() { updateZones(zoneDataHandler); }, zoneInterval);
	}
}
function updateZones(handler) {
	var zh = handler || zoneDataHandler;

	var fail = function(jqXHR, textStatus, errorThrown) {
		clearTimeout(zoneTimer);
		zoneTimer = setTimeout(function() { updateZones(zh); }, zoneErrorInterval);
	};

	KNC.updateZones(zh, fail);
}

// Sets up image loading (imgId: img tag ID, filename: base image filename)
// Images are long-polled -- server should delay image loading until an image
// is ready (TODO: perhaps delay only if ?v= is specified?).
function setupImage(imgId, filename, tabIndex, interval)
{
	interval = interval || 0; // Default to no delay

	var img = document.getElementById(imgId);
	if(!img) {
		throw 'Image ' + imgId + ' not found.';
	}

	if(!$(img).data('baseName')) {
		$(img).data('baseName', filename);
	}

	tabIndex = tabIndex || $(img).data('tabIndex');
	$(img).data('tabIndex', tabIndex);

	$(img).data('update', false);

	$(img).data('errCount', 0);

	function getNewImage() {
		img.src = $(img).data('baseName') + "?v=" + new Date().getTime();
	}

	img.onload = img.onload || function() {
		clearTimeout($(img).data('timer'));
		$(img).data('timer', null);
		$(img).data('errCount', 0);

		// TODO: Limit update rate to interval instead of delaying by interval
		// (e.g. use setTimeout if it's been less than X ms since last update)
		if($(img).data('update')) {
			if(interval > 0) {
				var timer = setTimeout(getNewImage, interval);
				$(img).data('timer', timer);
			} else {
				getNewImage();
			}
		}
	}
	img.onerror = img.onerror || function() {
		var timer = setTimeout(img.onload, imageErrorInterval);
		$(img).data('timer', timer);

		var count = $(img).data('errCount');
		count++;
		if(count > imageErrorCountLimit) {
			KNC.updateFPSDisplay(false, 0);
		}
	}
	img.onmousedown = img.onmousedown || function(ev) {
		// This doesn't seem to be necessary with the pointer-events: none; CSS.
		ev.preventDefault();
	}
}

function setupImages()
{
	// TODO: Make an array that stores this information (or use data-* attributes)
	setupImage('perspective_image', 'depth8.png', 0);
	setupImage('overhead_image', 'overhead.png', 1);
	setupImage('side_image', 'side.png', 2);
	setupImage('front_image', 'front.png', 3);
	setupImage('video_image', 'video.png', 4, 250);

	var videoImage = document.getElementById('video_image');
	var videoParent = videoImage.parentNode;
	try {
		KNC.initDemosaic(videoImage);
	} catch(e) {
		KNC.showErrorDialog("" + e, 'Error initializing video demosaic.');
		videoImage.parentNode.appendChild(document.createTextNode('' + e));
	}
}

// Sets whether the given image should be updated
function updateImage(imgId, update)
{
	var img = document.getElementById(imgId);
	if(!img) {
		throw 'Image ' + imgId + ' not found.';
	}

	$(img).data('update', update);
	if(img.onload) {
		img.onload();
	}
}

// Resumes image loading for the given img tag (by ID)
function startImage(imgId)
{
	updateImage(imgId, true);
}

// Stops image reloading for the given img tag (by ID)
function stopImage(imgId)
{
	updateImage(imgId, false);
}

function tabShowIndex(index)
{
	resetActivityTimer();

	stopImage('perspective_image');
	stopImage('overhead_image');
	stopImage('side_image');
	stopImage('front_image');
	stopImage('video_image');

	switch(index) {
		case 0:
			updateImage('perspective_image', runImageUpdates);
			break;
		case 1:
			updateImage('overhead_image', runImageUpdates);
			break;
		case 2:
			updateImage('side_image', runImageUpdates);
			break;
		case 3:
			updateImage('front_image', runImageUpdates);
			break;
		case 4:
			updateImage('video_image', runImageUpdates);
			break;
	}
}

$(function() {
	setupImages();
	setTimeout(function() {
		queueZoneUpdates();
		queueImageUpdates();
		resetActivityTimer();
	}, 250);

	$('a.startzone').click(function() { queueZoneUpdates(); resetActivityTimer(); });
	$('a.stopzone').click(cancelZoneUpdates);
	$('a.startimage').click(function() { queueImageUpdates(); resetActivityTimer(); });
	$('a.stopimage').click(cancelImageUpdates);
	$('a.uploadzones').click(function(ev) {
		ev.preventDefault();
		stopActivityTimer();
		KNC.showUploadZonesDialog(
			function() { cancelZoneUpdates(); },
			function() { resetActivityTimer(); }
			);
	});
	$('a.clearzones').click(function(ev) {
		ev.preventDefault();
		stopActivityTimer();
		KNC.showClearZonesDialog(
			function() { resetActivityTimer(); },
			function() { resetActivityTimer(); }
			);
	});

	$("#zonetabs").tabs({
		activate: function(ev, ui) {
			var index = ui.newTab.index();
			tabShowIndex(index);
			$.cookie('ui-tabs-1', index, { expires: 1 });
		}
	});
	$("#zonetabs").tabs('option', 'active', parseInt($.cookie('ui-tabs-1')));

	$("#zonelisttabs").tabs();

	$('#offline-dialog').dialog({
		autoOpen: false,
		beforeClose: function() { return KNC.connected; },
		modal: true,
		title: 'Camera Offline',
		minWidth: 340,
		minHeight: 110,
		});

	setTimeout(function() { $('#offline-dialog').dialog(KNC.connected ? 'close' : 'open') }, 250);
});

function setZonePerspective(jqd) {
	// TODO: Use coordinates from the event to avoid lag/overwritten updates
	// TODO: Use data-zone attribute for px_xmin_ etc.
	var name = jqd.attr("data-zone");
	var xmin = jqd.position().left;
	var ymin = jqd.position().top;
	var xmax = Math.min(639, xmin + jqd.outerWidth());
	var ymax = Math.min(479, ymin + jqd.outerHeight());
	$('.px_xmin_' + name).text(xmin);
	$('.px_ymin_' + name).text(ymin);
	$('.px_xmax_' + name).text(xmax);
	$('.px_ymax_' + name).text(ymax);
	KNC.setZone({
		name: name,
		px_xmin: xmin,
		px_ymin: ymin,
		px_xmax: xmax,
		px_ymax: ymax
		});
}

function overheadCoords(px_x, px_y) {
	var x = (px_x - 320) * KNC.XMAX / 250;
	var z = (px_y + 10) * KNC.ZMAX / 500;
	return {x: x, z: z};
}

function setZoneOverhead(jqd) {
	// TODO: Only update text if the value has changed (do this
	// after creating a Zone class to manage these things)
	var name = jqd.attr("data-zone");
	var xmin = (jqd.position().left - 250) * KNC.XMAX / 250;
	var zmin = (jqd.position().top + 10) * KNC.ZMAX / 500;
	var xmax = xmin + jqd.outerWidth() * KNC.XMAX / 250;
	var zmax = zmin + jqd.outerHeight() * KNC.ZMAX / 500;
	if(zmin <= 0) {
		zmin = 0.001;
	}
	if(zmax <= 0.001) {
		zmax = 0.002;
	}
	$('.xmin_' + name).text(KNC.roundk(xmin));
	$('.zmin_' + name).text(KNC.roundk(zmin));
	$('.xmax_' + name).text(KNC.roundk(xmax));
	$('.zmax_' + name).text(KNC.roundk(zmax));
	KNC.setZone({
		name: name,
		xmin: xmin,
		zmin: zmin,
		xmax: xmax,
		zmax: zmax
		});
}

function sideCoords(px_x, px_y) {
	var y = (240 - px_y) * KNC.YMAX / 250;
	var z = (px_x - 70) * KNC.ZMAX / 500;
	return {y: y, z: z};
}

function setZoneSide(jqd) {
	var name = jqd.attr("data-zone");
	var zmin = jqd.position().left * KNC.ZMAX / 500;
	var ymax = (240 - jqd.position().top) * KNC.YMAX / 250;
	var zmax = zmin + jqd.outerWidth() * KNC.ZMAX / 500;
	var ymin = ymax - jqd.outerHeight() * KNC.YMAX / 250;
	if(zmin <= 0) {
		zmin = 0.001;
	}
	if(zmax <= 0.001) {
		zmax = 0.002;
	}
	$('.ymin_' + name).text(KNC.roundk(ymin));
	$('.ymax_' + name).text(KNC.roundk(ymax));
	$('.zmin_' + name).text(KNC.roundk(zmin));
	$('.zmax_' + name).text(KNC.roundk(zmax));
	KNC.setZone({
		name: name,
		ymin: ymin,
		ymax: ymax,
		zmin: zmin,
		zmax: zmax
		});
}

function frontCoords(px_x, px_y) {
	var x = (320 - px_x) * KNC.XMAX / 250;
	var y = (240 - px_y) * KNC.YMAX / 250;
	return {x: x, y: y};
}

function setZoneFront(jqd) {
	var name = jqd.attr("data-zone");
	var xmax = (250 - jqd.position().left) * KNC.XMAX / 250;
	var xmin = xmax - jqd.outerWidth() * KNC.XMAX / 250;
	var ymax = (240 - jqd.position().top) * KNC.YMAX / 250;
	var ymin = ymax - jqd.outerHeight() * KNC.YMAX / 250;
	$('.xmin_' + name).text(KNC.roundk(xmin));
	$('.xmax_' + name).text(KNC.roundk(xmax));
	$('.ymin_' + name).text(KNC.roundk(ymin));
	$('.ymax_' + name).text(KNC.roundk(ymax));
	KNC.setZone({
		name: name,
		xmin: xmin,
		xmax: xmax,
		ymin: ymin,
		ymax: ymax
		});
}

function deleteZone(name) {
	resetActivityTimer();
	KNC.showDeleteZoneDialog(name, function() {
		var req = KNC.rmZone(name);
		req.done(function() {
			var zone = KNC.zones[name];
			if(zone) {
				zone.remove();
			}
		});
	});
}

function addZoneForProxy(name, jqd) {
	var zone = {
		xmin: -500, xmax: 500,
		ymin: -500, ymax: 500,
		zmin: 3000, zmax: 4000,
		name: name
	}
	var view = jqd.attr("data-view");
	var outer = $('.vis[data-view="' + view + '"]');
	var inner = outer.find('.zonewrap');
	var pos = jqd.position();

	pos.left -= inner.position().left;
	pos.top -= inner.position().top;

	console.log("Adding zone " + name + " on view " + view + " for element:");
	console.dir(jqd);
	console.dir(pos);

	switch(view) {
		default:
		case "perspective":
		case "video":
			// TODO: Support perspective and video
			return false;
		case "overhead":
			zone.xmin = (pos.left - 250) * KNC.XMAX / 250;
			zone.xmax = zone.xmin + jqd.outerWidth() * KNC.XMAX / 250;
			zone.zmin = (pos.top + 10) * KNC.ZMAX / 500;
			zone.zmax = zone.zmin + jqd.outerHeight() * KNC.ZMAX / 500;
			break;
		case "side":
			zone.zmin = pos.left * KNC.ZMAX / 500;
			zone.zmax = zone.zmin + jqd.outerWidth() * KNC.ZMAX / 500;
			zone.ymax = (240 - pos.top) * KNC.YMAX / 250;
			zone.ymin = zone.ymax - jqd.outerHeight() * KNC.YMAX / 250;
			break;
		case "front":
			zone.xmax = (250 - pos.left) * KNC.XMAX / 250;
			zone.xmin = zone.xmax - jqd.outerWidth() * KNC.XMAX / 250;
			zone.ymax = (240 - pos.top) * KNC.YMAX / 250;
			zone.ymin = zone.ymax - jqd.outerHeight() * KNC.YMAX / 250;
			break;
	}

	console.dir(zone);

	var req = KNC.addZone(zone);
	req.done(function(html) {
		// TODO: Respond to addzone with JSON containing the new zone (use Accept header?)
		$('.zone_proxy').remove();
	});
	req.fail(function(jqXHR, status, error) {
		$('.zone_proxy').remove();
		var dlg = KNC.showErrorDialog('Error adding zone: ' + error + ' ' + status, 'Error adding zone ' + name);
		if(jqXHR.responseText) {
			dlg.html(jqXHR.responseText);
		}
	});
}

var hideZones = false;
function hideZoneDivs(hide) {
	hideZones = hide;
	$('.zonewrap').css('visibility', hideZones ? 'hidden' : 'visible');
	$('a#showhide').text(hideZones ? 'Show Zones' : 'Hide Zones');
}

function toggleZoneDivs() {
	resetActivityTimer();
	hideZoneDivs(!hideZones);
	$.cookie('zones_hidden', hideZones);
}

// Makes it possible to click and drag to create a zone
function set_rectable() {
	var dragging = false;
	$('.vis').not('[data-view="perspective"]').not('[data-view="video"]').drag("start", function(ev, drag) {
			if(dragging) { console.log('Dragging while dragging?!'); }
			if(!$(ev.target).hasClass("zonewrap")) { return null; }

			var container = $(this).find('.zonewrap');
			var x1 = container.offset().left;
			var y1 = container.offset().top;
			var x2 = container.offset().left + container.outerWidth();
			var y2 = container.offset().top + container.outerHeight();
			if(drag.startX < x1 || drag.startY < y1 ||
				drag.startX > x2 || drag.startY > y2) {
				return null;
			}
			drag.limit = {
				left: x1 - drag.originalX,
				top: y1 - drag.originalY,
				right: x2 - drag.originalX,
				bottom: y2 - drag.originalY
				};

			var tx = drag.startX - drag.originalX;
			var ty = drag.startY - drag.originalY;
			var sx = Math.min(tx, tx + drag.deltaX);
			var sy = Math.min(ty, ty + drag.deltaY);
			var dx = drag.deltaX;
			var dy = drag.deltaY;
			if(dx < 0) {
				// For some reason Math.abs() leaves these negative
				dx = -dx;
			}
			if(dy < 0) {
				dy = -dy;
			}
			var proxy = $('<div class="zone_proxy c' + ((KNC.zoneCount) % KNC.zoneColors.length + 1) + '">New Zone</div>');
			proxy.css({
				left: sx,
				top: sy,
				width: dx,
				height: dy,
				lineHeight: '' + dy + 'px'
				});
			proxy.attr("data-view", $(this).attr("data-view"));
			$(this).append(proxy);
			dragging = true;
			return proxy;
		}, { distance: 24, handle: ".zonewrap, .vis", not: ".zone, .zone *"})
		.drag(function(ev, drag) {
			if(!dragging) { return; }
			resetActivityTimer();
			var tx = drag.startX - drag.originalX;
			var ty = drag.startY - drag.originalY;
			var sx = Math.min(tx, tx + drag.deltaX); // Start x/y
			var sy = Math.min(ty, ty + drag.deltaY);
			var dx = drag.deltaX < 0 ? -drag.deltaX : drag.deltaX; // Delta x/y
			var dy = drag.deltaY < 0 ? -drag.deltaY : drag.deltaY;
			var ex = sx + dx; // End x/y
			var ey = sy + dy;

			if(drag.limit == null) {
				if(drag.proxy != this) {
					$(drag.proxy).remove();
				}
				return false;
			}
			if(sx < drag.limit.left) {
				sx = drag.limit.left;
			}
			if(sy < drag.limit.top) {
				sy = drag.limit.top;
			}
			if(ex > drag.limit.right) {
				ex = drag.limit.right;
			}
			if(ey > drag.limit.bottom) {
				ey = drag.limit.bottom;
			}

			$(drag.proxy).css({
				left: sx,
				top: sy,
				width: ex - sx,
				height: ey - sy,
				lineHeight: '' + (ey - sy) + 'px'
				});
		})
		.drag("end", function(ev, drag) {
			if(!dragging) { return; }
			dragging = false;
			stopActivityTimer();
			KNC.showAddZoneDialog(
				'Zone ' + (KNC.zoneCount + 1),
				function(name) {
					// Zone added
					var ret = addZoneForProxy(name, $('.zone_proxy'));
					// TODO: Use exceptions for detailed error messages
					if(ret == false) {
						KNC.showErrorDialog("The zone could not be added.");
					}
					resetActivityTimer();
				},
				function() {
					// Zone canceled
					$('.zone_proxy').remove();
					resetActivityTimer();
				}
				);
		});

	// Prevent text selection on perspective and video views
	$('.vis[data-view="perspective"]').mousedown(function(ev) { ev.preventDefault(); });
	$('.vis[data-view="video"]').mousedown(function(ev) { ev.preventDefault(); });
}

function setupCoordinateOverlay() {
	// Returns a function that handles mouse events generated by sourceDiv,
	// with coordinates calculated by coordFunc and printed into coordDiv.
	// coords is an array containing the names of the coordinates (e.g. ['x', 'y']).
	// sourceDiv and coordDiv should be jQuery objects.
	function makeMouseHandler(sourceDiv, coordDiv, coordFunc, coords) {
		return function(ev) {
			var offset = sourceDiv.offset();
			var loc = coordFunc(ev.pageX - offset.left - 1, ev.pageY - offset.top - 1);

			var str = [];
			for(s in coords) {
				str.push(coords[s] + ": " + Math.round(loc[coords[s]]));
			}

			coordDiv.html(str.join(' &nbsp; '));
			return true;
		}
	}

	$('#zonetabs-2').mousemove(makeMouseHandler(
				$('#zonetabs-2'), $('#overhead_coord'), overheadCoords, ['x', 'z']
				));

	$('#zonetabs-3').mousemove(makeMouseHandler(
				$('#zonetabs-3'), $('#side_coord'), sideCoords, ['y', 'z']
				));

	$('#zonetabs-4').mousemove(makeMouseHandler(
				$('#zonetabs-4'), $('#front_coord'), frontCoords, ['x', 'y']
				));
}

$(function() {
	$('a#showhide').click(function(ev) { toggleZoneDivs(); ev.stopPropagation(); ev.preventDefault(); });
	hideZoneDivs(String($.cookie('zones_hidden')) == "true");
	set_rectable();
	setupCoordinateOverlay();
});
