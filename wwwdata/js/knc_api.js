/* API-related functions - (C)2013 Mike Bourgeous */

var KNC = window.KNC || {};

KNC.setZoneInterval = 200;

KNC.setZoneHandler = function(attrs) {
	// TODO: Error handling
	$.post('/setzone', attrs, 'json');
}

// attrs should include the id-formatted name of the
// zone (though at this point there is no id formatting)
KNC.setZone = function(attrs) {
	KNC.rateLimit('setZone: ' + attrs.name, KNC.setZoneInterval, KNC.setZoneHandler, attrs, 'merge');
}

// Returns the jQuery AJAX request object.
KNC.addZone = function(attrs) {
	if(attrs.name == null || attrs.xmin == null || attrs.xmax == null ||
			attrs.ymin == null || attrs.ymax == null ||
			attrs.zmin == null || attrs.zmax == null) {
		throw 'Invalid zone parameter.';
	}
	return $.post('/addzone', attrs, 'html');
}

// Returns the jQuery AJAX request object.
KNC.rmZone = function(name) {
	// TODO: Request JSON instead?  Use Accept header in knc_zones.rb?
	return $.post('/rmzone', { name: name }, 'html');
}

// Returns the jQuery AJAX request object.
KNC.clearZones = function() {
	// TODO: Request JSON instead?  Use Accept header in knc_zones.rb?
	return $.post('/clearzones', null, 'html');
}

// Functions called with (data) by updateZones() on successful JSON response
KNC.zoneSuccessHandlers = [];

// Functions called with (jqXHR, textStatus, errorThrown) by updateZones() on JSON failure
KNC.zoneErrorHandlers = [];

// Makes a JSON call to /zones.json, calling success (if given )with the
// resulting object on success, or fail (if given) with error information.
// Also calls registered zone success or error handlers.
KNC.updateZones = function(success, fail) {
	var req = $.getJSON('/zones.json');

	req.done(function(data) {
		$.each(KNC.zoneSuccessHandlers, function(idx, handler) {
			handler(data);
		});

		if(success) {
			success(data);
		}
	});

	req.fail(function(jqXHR, textStatus, errorThrown) {
		console.error("Error getting zones: " + textStatus + ", " + errorThrown);
		console.dir(errorThrown);
		console.dir(jqXHR);

		$.each(KNC.zoneErrorHandlers, function(idx, handler) {
			handler(jqXHR, textStatus, errorThrown);
		});

		if(fail) {
			fail(jqXHR, textStatus, errorThrown);
		}
	});

	return req;
}

// Adds a function to be called with (data) when updateZones() succeeds
KNC.addZoneSuccessHandler = function(success) {
	KNC.zoneSuccessHandlers.push(success);
}

// Adds a function to be called with (jqXHR, textStatus, errorThrown) when updateZones() fails
KNC.addZoneErrorHandler = function(failure) {
	KNC.zoneErrorHandlers.push(failure);
}
