/* Depth Camera Server JavaScript initialization code - (C)2011 Mike Bourgeous */

var KNC = window.KNC || {};

// TODO: Move this into a namespace
// TODO: Consider the camera server offline if there are no
// updates for 5s when updates should be running (timeout
// counter incremented in fix*Updates()?).
var runZoneUpdates = false;
var runImageUpdates = false;
var zoneTimer;
var perspTimer;
var ovhTimer;
var sideTimer;
var frontTimer;
var zoneInterval = 125;
var imageInterval = 250;
var reloadInterval = 1*60*1000;
var fixInterval = 3000;
var connected;
var fps;
var occupied;
var activityTimer;
function queueZoneUpdates() {
	if(!runZoneUpdates) {
		runZoneUpdates = true;
		zoneTimer = setTimeout(updateZones, zoneInterval);
	}
}
function queueImageUpdates() {
	if(!runImageUpdates) {
		runImageUpdates = true;
		perspTimer = setTimeout(updatePersp, imageInterval);
		ovhTimer = setTimeout(updateOvh, imageInterval);
		sideTimer = setTimeout(updateSide, imageInterval);
		frontTimer = setTimeout(updateFront, imageInterval);

		updatePersp(true);
		updateOvh(true);
		updateSide(true);
		updateFront(true);
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
function cancelImageUpdates() {
	runImageUpdates = false;
	clearTimeout(perspTimer);
	clearTimeout(ovhTimer);
	clearTimeout(sideTimer);
	clearTimeout(frontTimer);

	// Don't reload the page if there's no background loading going on
	if(!runZoneUpdates) {
		stopActivityTimer();
	}
}
function fixZoneUpdates() {
	var updates = runZoneUpdates;
	clearTimeout(zoneTimer);
	if(updates) {
		runZoneUpdates = false;
		queueZoneUpdates();
	}
}
function fixImageUpdates() {
	var updates = runImageUpdates;
	clearTimeout(perspTimer);
	clearTimeout(ovhTimer);
	clearTimeout(sideTimer);
	clearTimeout(frontTimer);
	if(updates) {
		runImageUpdates = false;
		queueImageUpdates();
	}
}

function resetActivityTimer() {
	console.log("Resetting activity timer.");
	if(activityTimer != null) {
		clearTimeout(activityTimer);
	}
	// At an estimated memory leak rate of 2MB/s
	// and a goal of running on 512MB systems, we need
	// to reload once per minute.  FIXME: fix leak
	//activityTimer = setTimeout(function(){ console.log("Activity timer reloading."); window.location.reload(); }, reloadInterval);
}
function stopActivityTimer() {
	console.log("Stopping activity timer.");
	if(activityTimer != null) {
		clearTimeout(activityTimer);
	}
}

function errorMessage(message) {
	var msg = message.toString().replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;");
	$('<div>An error occurred.<br>' + msg + '</div>').dialog({modal: true, title: "Error"});
}

function zoneDataHandler(data) {
	var last_connected = connected;
	if(connected != data.connected) {
		connected = data.connected;
		$('.fps').css('display', connected ? 'inline' : 'none');
		$('.online').css('display', connected ? 'inline' : 'none');
		$('.offline').css('display', connected ? 'none' : 'inline');
		$('#offline-dialog').dialog(connected ? 'close' : 'open');
	}
	if(connected && fps != data.fps) {
		fps = data.fps;
		$('.fps').text(" at " + fps + "fps");
	}
	if(occupied != data.occupied) {
		occupied = data.occupied;
		$('.occupied_count').text(occupied);
	}

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

	/*
	$.each(zones, function(key, zone) {
			$('.zone[data-zone="' + key + '"]').css({
				color: zone.occupied ? '#2f3' : 'white' // TODO: use an occupied class
				});
			});
			*/
	if(runZoneUpdates) {
		zoneTimer = setTimeout(updateZones, zoneInterval);
	}
}
function updateZones() {
	// TODO: Add a setTimeout call for failure that tries again on a slower interval.
	$.getJSON('/zones.json', zoneDataHandler);
}
function updatePersp(force) {
	// TODO: Add a setTimeout call for failure that tries again on a slower interval.

	// TODO: Use tab select events to load images
	if($('#zonetabs').tabs('option', 'active') == 0 || force == true) {
		$('.vis_perspective_loader').attr("src", "/depth8.png?v=" + new Date().getTime());
	}
}
function updateOvh(force) {
	if($('#zonetabs').tabs('option', 'active') == 1 || force == true) {
		$('.vis_overhead_loader').attr("src", "/overhead.png?v=" + new Date().getTime());
	}
}
function updateSide(force) {
	if($('#zonetabs').tabs('option', 'active') == 2 || force == true) {
		$('.vis_side_loader').attr("src", "/side.png?v=" + new Date().getTime());
	}
}
function updateFront(force) {
	if($('#zonetabs').tabs('option', 'active') == 3 || force == true) {
		$('.vis_front_loader').attr("src", "/front.png?v=" + new Date().getTime());
	}
}
$(function() {
	$("#zonetabs").tabs({ activate: function(){resetActivityTimer();} });
	$("#zonelisttabs").tabs();

	resetActivityTimer();
	queueZoneUpdates();
	queueImageUpdates();
	$('a.startzone').click(function() { queueZoneUpdates(); resetActivityTimer(); });
	$('a.stopzone').click(cancelZoneUpdates);
	$('a.startimage').click(function() { queueImageUpdates(); resetActivityTimer(); });
	$('a.stopimage').click(cancelImageUpdates);
	$('a.uploadzones').click(function(ev) { $('#zoneupload-dialog').dialog('open'); ev.preventDefault(); });

	// TODO: Reduce code duplication here, use z-index or visibility
	// instead of changing both background URI and img src
	$('.vis_perspective_loader').load(function() {
		updateTexture(this);
		if(runImageUpdates) {
			perspTimer = setTimeout(updatePersp, imageInterval);
		}
		});
	$('.vis_overhead_loader').load(function() {
		//updateTexture(this);
		if(runImageUpdates) {
			ovhTimer = setTimeout(updateOvh, imageInterval);
		}
		});
	$('.vis_side_loader').load(function() {
		//updateTexture(this);
		if(runImageUpdates) {
			sideTimer = setTimeout(updateSide, imageInterval);
		}
		});
	$('.vis_front_loader').load(function() {
		//updateTexture(this);
		if(runImageUpdates) {
			frontTimer = setTimeout(updateFront, imageInterval);
		}
		});

	$('#addzone-dialog').dialog({
		autoOpen: false,
		beforeClose: function() { $('.zone_proxy').remove(); },
		buttons: {
			"Add Zone": function() {
				var name = document.getElementById('addzone_name').value;
				var ret = addZoneForProxy(name, $('.zone_proxy'));
				// TODO: Use exceptions for detailed error messages
				if(ret == false) {
					errorMessage("The zone could not be added.");
				}
				$('#addzone-dialog').dialog("close");
				resetActivityTimer();
				},
			"Cancel": function() {
				$('#addzone-dialog').dialog("close");
				resetActivityTimer();
				}
			},
		modal: true,
		open: function() { stopActivityTimer(); $('#addzone-dialog input#addzone_name')[0].select(); },
		title: "Enter Zone Name",
		width: 320,
		zIndex: 36000
		// Setting a large zIndex (>=100000) caused input forms to quit working in Firefox 5
		});

	$('#zoneupload-dialog').dialog({
		autoOpen: false,
		buttons: {
			// Cancel zone updates so the new zones don't become visible behind the dialog
			"Upload Zones": function() { cancelZoneUpdates(); $('#zoneupload-submit').click(); },
			"Cancel": function() { $('#zoneupload-dialog').dialog('close'); resetActivityTimer(); }
		},
		modal: true,
		open: function() { stopActivityTimer(); $('#zoneupload-dialog input#zone_file')[0].select(); },
		title: "Upload Zones",
		width: 460,
		zIndex: 36000
	});

	$('#addzone-form').submit(function() {
		$("#addzone-dialog").parent().find("button:first").trigger("click");
		return false;
		});

	$('#offline-dialog').dialog({
		autoOpen: false,
		beforeClose: function() { return connected; },
		modal: true,
		title: 'Camera Offline',
		minWidth: 340,
		minHeight: 110,
		zIndex: 38000
		});

	setTimeout(function() { $('#offline-dialog').dialog(connected ? 'close' : 'open') }, 250);
});

function setZonePerspective(jqd) {
	// TODO: Use coordinates from the event to avoid lag/overwritten updates
	// TODO: Limit update rate while resizing/dragging
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

function addZoneForProxy(name, jqd) {
	var zone = {
		xmin: -0.5, xmax: 0.5,
		ymin: -0.5, ymax: 0.5,
		zmin: 3.0, zmax: 4.0,
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
			// TODO: Support perspective
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

	KNC.addZone(zone);
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
	$('.vis').not('[data-view="perspective"]').drag("start", function(ev, drag) {
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
			// FIXME: Work around image updates stopping when dragging
			fixImageUpdates();
			if(!dragging) { return; }
			dragging = false;
			document.getElementById('addzone_name').value = 'New Zone';
			stopActivityTimer();
			$('#addzone-dialog').dialog('open');
		});

	// Prevent zone creation on perspective view
	$('.vis[data-view="perspective"]').mousedown(function(ev) { ev.preventDefault(); });
}

function updateTexture(img) {
	var tex = $(img).data('tex');
	var gl = $(img).data('gl');
	if(!tex || !gl) {
		console.log("No texture or gl bound to image!  tex: " + tex + " gl: " + gl);
		console.dir(img);
		return;
	}
	gl.bindTexture(gl.TEXTURE_2D, tex);
	gl.texImage2D(gl.TEXTURE_2D, 0, gl.LUMINANCE, gl.LUMINANCE, gl.UNSIGNED_BYTE, img);
	gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
	gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
	gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
	gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
	gl.bindTexture(gl.TEXTURE_2D, null);
}

$(function() {
	$('a#showhide').click(function(ev) { toggleZoneDivs(); ev.stopPropagation(); ev.preventDefault(); });
	hideZoneDivs(String($.cookie('zones_hidden')) == "true");
	set_rectable();
	setInterval(function() { fixZoneUpdates(); fixImageUpdates(); }, fixInterval);
});

function getShader(gl, domId) {
	var shaderElem = document.getElementById(domId);

	if(!shaderElem) {
		throw "Shader '" + domId + "' not found in DOM.";
	}

	var shaderText = "";
	var currentChild = shaderElem.firstChild;
	while(currentChild) {
		if(currentChild.nodeType == currentChild.TEXT_NODE) {
			shaderText += currentChild.textContent;
		}
		currentChild = currentChild.nextSibling;
	}

	var shaderId;
	if(shaderElem.type == "x-shader/x-fragment") {
		console.log("Loading fragment shader from " + domId);
		shaderId = gl.createShader(gl.FRAGMENT_SHADER);
	} else if(shaderElem.type == "x-shader/x-vertex") {
		console.log("Loading vertex shader from " + domId);
		shaderId = gl.createShader(gl.VERTEX_SHADER);
	} else {
		alert("Invalid shader type " + shaderElem.type);
		return null;
	}

	gl.shaderSource(shaderId, shaderText);
	gl.compileShader(shaderId);
	if(!gl.getShaderParameter(shaderId, gl.COMPILE_STATUS)) {
		alert("An error occurred while compiling shader '" + domId + "': " +
				gl.getShaderInfoLog(shaderId));
		return null;
	}

	return shaderId;
}

var shaderProgram;
var aVertexPositionAttr;
var aVertexNormalAttr;
var vtxColorAttr;
var texCoordAttr;
function initShaders() {
	var vertexShader = getShader(gl, "shader-vs01");
	var fragmentShader = getShader(gl, "shader-fs01");

	shaderProgram = gl.createProgram();
	gl.attachShader(shaderProgram, vertexShader);
	gl.attachShader(shaderProgram, fragmentShader);
	gl.linkProgram(shaderProgram);

	if(!gl.getProgramParameter(shaderProgram, gl.LINK_STATUS)) {
		alert("Unable to initialize the shader program.");
	}

	gl.useProgram(shaderProgram);

	aVertexPositionAttr = gl.getAttribLocation(shaderProgram, "aVertexPosition");
	gl.enableVertexAttribArray(aVertexPositionAttr);

	aVertexNormalAttr = gl.getAttribLocation(shaderProgram, "aVertexNormal");
	gl.enableVertexAttribArray(aVertexNormalAttr);

	vtxColorAttr = gl.getAttribLocation(shaderProgram, "aVertexColor");
	gl.enableVertexAttribArray(vtxColorAttr);

	texCoordAttr = gl.getAttribLocation(shaderProgram, "aTexCoord");
	gl.enableVertexAttribArray(texCoordAttr);
}

function initTextures(gl) {
	var img = $(".vis_perspective_loader")[0];
	var tex = gl.createTexture();
	$(img).data('tex', tex);
	$(img).data('gl', gl);
}

function texLoaded(img, tex) {
	gl.bindTexture(gl.TEXTURE_2D, tex);
	gl.texImage2D(gl.TEXTURE_2D, 0, gl.LUMINANCE, gl.LUMINANCE, gl.UNSIGNED_BYTE, img);
	gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
	gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
	gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
	gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
	gl.bindTexture(gl.TEXTURE_2D, null);
}

// Returns vertices for the faces in a cube in the following
// order: front, right, top, left, bottom, back
function rect3d(x1, y1, z1, x2, y2, z2) {
	return [
		// front
		x1, y1, z2, // 0 - bottom left front
	x1, y2, z2, // 1 - top left front
	x2, y2, z2, // 2 - top right front
	x2, y1, z2, // 3 - bottom right front

	// right
	x2, y1, z2, // 3 - bottom right front
	x2, y2, z2, // 2 - top right front
	x2, y2, z1, // 6 - top right back
	x2, y1, z1,  // 7 - bottom right back

	// top
	x1, y2, z2, // 1 - top left front
	x1, y2, z1, // 5 - top left back
	x2, y2, z1, // 6 - top right back
	x2, y2, z2, // 2 - top right front

	// left
	x1, y1, z1, // 4 - bottom left back
	x1, y2, z1, // 5 - top left back
	x1, y2, z2, // 1 - top left front
	x1, y1, z2, // 0 - bottom left front

	// bottom
	x1, y1, z1, // 4 - bottom left back
	x1, y1, z2, // 0 - bottom left front
	x2, y1, z2, // 3 - bottom right front
	x2, y1, z1,  // 7 - bottom right back

	// back
	x2, y1, z1, // 7 - bottom right back
	x2, y2, z1, // 6 - top right back
	x1, y2, z1, // 5 - top left back
	x1, y1, z1  // 4 - bottom left back
		];
}

// Returns vertex indices for two triangles on each
// face of a cube.  x1/y1/z2 < x2/y2/z1.
function rect3dIdx() {
	// Two triangles: bl, tl, tr; bl, tr, br
	function faceVertices(face) {
		return [0 + face * 4, 1 + face * 4, 2 + face * 4,
		       0 + face * 4, 2 + face * 4, 3 + face * 4];
	}

	var idx = [];
	for(var i = 0; i < 6; i++) {
		idx = idx.concat(faceVertices(i));
	}

	return idx;
}

var vtxBuf;
var idxBuf;
var colorBuf;
var texCoordBuf;
var normBuf;
function initBuffers() {
	// Create/fill vertex buffer
	vtxBuf = gl.createBuffer();
	gl.bindBuffer(gl.ARRAY_BUFFER, vtxBuf);
	var vtx = rect3d(-1.33333, -1.0, -0.25, 1.33333, 1.0, 0.25);
	gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(vtx), gl.STATIC_DRAW);

	// Create/fill element buffer
	var idx = rect3dIdx();
	idxBuf = gl.createBuffer();
	gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, idxBuf);
	gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, new Uint16Array(idx), gl.STATIC_DRAW);

	// Create/fill vertex color buffer
	var vtxColors = [
		// front
		0.6, 0.6, 0.6, 1.0,
		0.6, 0.6, 0.6, 1.0,
		0.6, 0.6, 0.6, 1.0,
		0.6, 0.6, 0.6, 1.0,

		// right
		1.0, 1.0, 0.3, 1.0,
		1.0, 1.0, 0.3, 1.0,
		1.0, 1.0, 0.3, 1.0,
		1.0, 1.0, 0.3, 1.0,

		// top
		0.3, 0.8, 0.4, 1.0,
		0.3, 0.8, 0.4, 1.0,
		0.3, 0.8, 0.4, 1.0,
		0.3, 0.8, 0.4, 1.0,

		// left
		0.3, 0.7, 1.0, 1.0,
		0.3, 0.7, 1.0, 1.0,
		0.3, 0.7, 1.0, 1.0,
		0.3, 0.7, 1.0, 1.0,

		// bottom
		0.8, 0.2, 0.15, 1.0,
		0.8, 0.2, 0.15, 1.0,
		0.8, 0.2, 0.15, 1.0,
		0.8, 0.2, 0.15, 1.0,

		// back
		0.4, 0.4, 0.4, 1.0,
		0.4, 0.4, 0.4, 1.0,
		0.4, 0.4, 0.4, 1.0,
		0.4, 0.4, 0.4, 1.0,
		];

	colorBuf = gl.createBuffer();
	gl.bindBuffer(gl.ARRAY_BUFFER, colorBuf);
	gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(vtxColors), gl.STATIC_DRAW);

	// Assign texture coordinates (same for each face)
	var texCoords = [
		0.0, 1.0,
		0.0, 0.0,
		1.0, 0.0,
		1.0, 1.0,
		0.0, 1.0,
		0.0, 0.0,
		1.0, 0.0,
		1.0, 1.0,
		0.0, 1.0,
		0.0, 0.0,
		1.0, 0.0,
		1.0, 1.0,
		0.0, 1.0,
		0.0, 0.0,
		1.0, 0.0,
		1.0, 1.0,
		0.0, 1.0,
		0.0, 0.0,
		1.0, 0.0,
		1.0, 1.0,
		0.0, 1.0,
		0.0, 0.0,
		1.0, 0.0,
		1.0, 1.0,
		];

	texCoordBuf = gl.createBuffer();
	gl.bindBuffer(gl.ARRAY_BUFFER, texCoordBuf);
	gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(texCoords), gl.STATIC_DRAW);

	var normals = [
		// front
		0.0, 0.0, 1.0,
		0.0, 0.0, 1.0,
		0.0, 0.0, 1.0,
		0.0, 0.0, 1.0,

		// right
		1.0, 0.0, 0.0,
		1.0, 0.0, 0.0,
		1.0, 0.0, 0.0,
		1.0, 0.0, 0.0,

		// top
		0.0, 1.0, 0.0,
		0.0, 1.0, 0.0,
		0.0, 1.0, 0.0,
		0.0, 1.0, 0.0,

		// left
		-1.0, 0.0, 0.0,
		-1.0, 0.0, 0.0,
		-1.0, 0.0, 0.0,
		-1.0, 0.0, 0.0,

		// bottom
		0.0, -1.0, 0.0,
		0.0, -1.0, 0.0,
		0.0, -1.0, 0.0,
		0.0, -1.0, 0.0,

		// back
		0.0, 0.0, -1.0,
		0.0, 0.0, -1.0,
		0.0, 0.0, -1.0,
		0.0, 0.0, -1.0,
		];

	normBuf = gl.createBuffer();
	gl.bindBuffer(gl.ARRAY_BUFFER, normBuf);
	gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(normals), gl.STATIC_DRAW);
}

var mvMatrix;
var mvStack = [];
var perspMatrix;

// Clears the model view matrix
function mvIdentity() {
	mvMatrix = Matrix.I(4);
}

function mvMult(m) {
	mvMatrix = mvMatrix.x(m);
}

function mvTranslate(v) {
	mvMult(Matrix.Translation($V([v[0], v[1], v[2]])).ensure4x4());
}

// TODO: A function that rotates the up vector to point along the given vector
function mvRotate(r, v) {
	mvMult(Matrix.Rotation(r * Math.PI / 180.0, $V(v)).ensure4x4());
}

function uploadMatrices() {
	var pUniform = gl.getUniformLocation(shaderProgram, "uPMatrix");
	gl.uniformMatrix4fv(pUniform, false, new Float32Array(perspMatrix.flatten()));

	var mvUniform = gl.getUniformLocation(shaderProgram, "uMVMatrix");
	gl.uniformMatrix4fv(mvUniform, false, new Float32Array(mvMatrix.flatten()));

	var nMatrix = mvMatrix.inverse().transpose();
	var normUniform = gl.getUniformLocation(shaderProgram, "uNormalMatrix");
	gl.uniformMatrix4fv(normUniform, false, new Float32Array(nMatrix.flatten()));
}

function mvPush(m) {
	if(m) {
		mvStack.push(m.dup());
		mvMatrix = m.dup();
	} else {
		mvStack.push(mvMatrix.dup());
	}
}

function mvPop() {
	if(!mvStack.length) {
		throw "Model view stack is empty.";
	}

	mvMatrix = mvStack.pop();
	return mvMatrix;
}

var r = 0.0;
var xt = 0.0, yt = 0.0, zt = -2.0;
var lastTime = new Date().getTime();
function updateScene() {
	var now = new Date().getTime();
	var inc = now - lastTime;
	lastTime = now;

	/*
	xt -= 0.001 * inc;
	if(xt < -6) {
		xt = 6;
	}
	*/

	r += 0.08 * inc;
	if(r >= 360) {
		r -= 360;
	}
}

function drawScene() {
	gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);

	perspMatrix = makePerspective(
			60,
			canvas.offsetWidth / canvas.offsetHeight,
			0.1,
			100
			);

	mvIdentity();
	mvPush();
	mvTranslate([xt, yt, zt]);
	mvRotate(r, [0, 1, 0]);
	uploadMatrices();

	gl.bindBuffer(gl.ARRAY_BUFFER, vtxBuf);
	gl.vertexAttribPointer(aVertexPositionAttr, 3, gl.FLOAT, false, 0, 0);

	gl.bindBuffer(gl.ARRAY_BUFFER, normBuf);
	gl.vertexAttribPointer(aVertexNormalAttr, 3, gl.FLOAT, false, 0, 0);

	gl.bindBuffer(gl.ARRAY_BUFFER, colorBuf);
	gl.vertexAttribPointer(vtxColorAttr, 4, gl.FLOAT, false, 0, 0);

	var tex = $('.vis_perspective_loader').data('tex');
	gl.bindBuffer(gl.ARRAY_BUFFER, texCoordBuf);
	gl.vertexAttribPointer(texCoordAttr, 2, gl.FLOAT, false, 0, 0);
	gl.activeTexture(gl.TEXTURE0);
	gl.bindTexture(gl.TEXTURE_2D, tex);
	gl.uniform1i(gl.getUniformLocation(shaderProgram, "uSampler"), 0);

	gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, idxBuf);
	gl.drawElements(gl.TRIANGLES, 36, gl.UNSIGNED_SHORT, 0);

	mvPop();
}

var canvas;
var gl;
function startGL() {
	canvas = document.getElementById('persp_canvas');
	canvas.width = Math.max(640, canvas.offsetWidth);
	canvas.height = Math.max(480, canvas.offsetHeight);

	gl = canvas.getContext('webgl');
	if(gl == null) {
		console.log('No webgl context');
		gl = canvas.getContext('experimental-webgl');
	} else {
		console.log('Got webgl context');
	}
	if(gl == null) {
		document.body.innerHTML = 
			'<p class="glerror">It appears your browser does not support WebGL.</p>';
		return;
	} else {
		console.log('Got experimental-webgl context');
	}

	initTextures(gl);
	initShaders();
	initBuffers();

	gl.clearColor(0.0, 0.0, 0.0, 0.5);
	gl.clearDepth(1.0);
	gl.enable(gl.BLEND);
	gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
	gl.depthFunc(gl.LEQUAL);
	gl.enable(gl.DEPTH_TEST);
	gl.depthFunc(gl.LEQUAL);
	gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);

	var frameFunc;
	if(window.mozRequestAnimationFrame) {
		console.log("Using Mozilla requestAnimationFrame for timing.");
		frameFunc = window.mozRequestAnimationFrame;
	} else if(window.webkitRequestAnimationFrame) {
		console.log("Using WebKit requestAnimationFrame for timing.");
		frameFunc = window.webkitRequestAnimationFrame;
	} else if(window.msRequestAnimationFrame) {
		console.log("Using Microsoft requestAnimationFrame for timing.");
		frameFunc = window.msRequestAnimationFrame;
	} else if(window.requestAnimationFrame) {
		console.log("Cool, using standard requestAnimationFrame for timing.");
		frameFunc = window.requestAnimationFrame;
	} else {
		console.log("Using setTimeout for timing.");
		frameFunc = function(func) {
			setTimeout(func, 16);
		}
	}

	function updateAndDraw() {
		updateScene();
		drawScene();
		frameFunc(updateAndDraw);
	}
	frameFunc(updateAndDraw);

	console.log("Vertex texture limit: " + gl.getParameter(gl.MAX_VERTEX_TEXTURE_IMAGE_UNITS));
}

$(function() { startGL(); });
