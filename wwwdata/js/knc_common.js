/* Display functions common to all KNC pages - (C)2013 Mike Bourgeous */

var KNC = window.KNC || {};

// Updates the online/offline and FPS displays and shows/hides the offline dialog (if it exists)
KNC.updateFPSDisplay = function(connected, fps) {
	if(KNC.connected != connected) {
		KNC.connected = connected;
		$('.fps').css('display', connected ? 'inline' : 'none');
		$('.online').css('display', connected ? 'inline' : 'none');
		$('.offline').css('display', connected ? 'none' : 'inline');
		$('#offline-dialog').dialog(connected ? 'close' : 'open');
	}
	if(connected && KNC.fps != fps) {
		KNC.fps = fps;
		$('.fps').text(" at " + fps + "fps");
	}
}

// Updates the occupied zone count display
KNC.updateOccupiedDisplay = function(count) {
	if(KNC.occupiedCount != count) {
		KNC.occupiedCount = count;
		$('.occupied_count').text(count);
	}
}

// Connect FPS and occupied count displays to zone updates, if possible
$(function() {
	if(KNC.addZoneSuccessHandler) {
		KNC.addZoneSuccessHandler(function(data) {
			KNC.updateFPSDisplay(data.connected, data.fps);
			KNC.updateOccupiedDisplay(data.occupied);
		});
		KNC.addZoneErrorHandler(function(jqXHR, textStatus, errorThrown) {
			KNC.updateFPSDisplay(false, 0);
			KNC.updateOccupiedDisplay(0);
		});
	}
});


// Shows a "Please wait..." dialog with the given title.  If closeFunc is
// specified, it will be called when the dialog is closed.  Returns the jQuery
// object representing the dialog, with added methods preventClose(),
// allowCancel(), and allowClose().
KNC.showPleaseWaitDialog = function(title, closeFunc) {
	var html = '<div class="please_wait_dialog">' +
		'<img class="loading_icon" src="/images/loading_15x15.gif">' +
		'<span>Please wait...</span></div>';

	var dlg = $(html).dialog({
		modal: true,
		draggable: false,
		title: title,
		width: 480,
		buttons: [],
		close: function(ev, ui) {
			if(closeFunc) {
				closeFunc();
			}
			dlg.dialog('destroy');
			dlg.remove();
		}
	});

	dlg.preventClose = function() {
		dlg.dialog({ beforeClose: function() { return false; } });
	}

	dlg.allowCancel = function() {
		dlg.dialog({ beforeClose: null });

		if($('#please_wait_cancel').length == 0) {
			dlg.dialog('option', 'buttons', [ {
				id: 'please_wait_cancel',
				text: 'Cancel',
				click: function() {
					dlg.dialog('close');
				}
			} ]);
		}

		$('#please_wait_cancel').button('enable');
	}

	dlg.allowClose = function() {
		dlg.dialog({ beforeClose: null });

		dlg.dialog('option', 'buttons', [ {
			id: 'please_wait_close',
			text: 'Close',
			click: function() {
				dlg.dialog('close');
			}
		} ]);

		$('#please_wait_close').button('enable');
	}

	return dlg;
}

KNC.showErrorDialog = function(message, title) {
	var msg = message.toString().replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;");
	return $('<div>' + (title ? '' : 'An error occurred.<br>') + msg + '</div>').dialog({
		modal: true,
		title: title ? title : "Error",
		width: 360,
	});
}

// Shows an error dialog for an AJAX request.  Message is only used if there is
// no jqXHR responseText.  Returns the jQuery dialog object.
KNC.showRequestErrorDialog = function(title, message, jqXHR, status, error) {
	var msg;

	if(jqXHR.responseText) {
		msg = jqXHR.responseText;
	} else {
		msg = KNC.escape(message.toString()) + '<br>' + status + ' ' + error;
	}

	return $('<div>' + (title ? '' : 'An error occurred.<br>') + msg + '</div>').dialog({
		modal: true,
		title: title ? title : "Error",
		width: 400,
	});
}

KNC.showAddZoneDialog = function(initialName, addFunc, cancelFunc) {
	var html = '<div id="addzone-dialog">' +
		'<p>Enter a name for the new zone.  Names must be unique.</p>' +
		'<p>Only letters (A-Z), numbers (0-9), and underscores (_) are allowed.  ' +
		'Spaces will become underscores.</p>' +
		'<form id="addzone-form">' +
		'<input type="text" name="name" id="addzone_name" class="ui-widget-content ui-corner-all"></input>' +
		'</form>' +
		'</div>';
	var dlg = $(html);
	var input = dlg.find('#addzone_name');

	var canceled = true; // Set to false if the action button is clicked

	input.val(initialName);

	dlg.dialog({
		autoOpen: false,
		beforeClose: function() { if(canceled && cancelFunc) { cancelFunc(); } },
		buttons: [
			{
				text: "Add Zone",
				id: "addzone_add_button",
				click: function() {
					canceled = false;

					var name = input.val();
					name = name.replace(/ +/g, '_').replace(/[^A-Za-z0-9_]+/g, '');
					if(addFunc) {
						addFunc(name);
					}
					dlg.dialog("close");
				}
			},
			{
				text: "Cancel",
				id: "addzone_cancel_button",
				click: function() {
					dlg.dialog("close");
				}
			}
		],
		modal: true,
		open: function() { input[0].select(); },
		close: function() { dlg.dialog('destroy'); dlg.remove(); },
		title: "Enter Zone Name",
		width: 320,
		});

	dlg.find('#addzone-form').submit(function() {
		dlg.parent().find("#addzone_add_button").trigger("click");
		return false;
	});

	dlg.dialog('open');
}

// Shows a zone deletion confirmation dialog with the given zone name, then
// calls deleteFunc if Delete is clicked.  If deleteFunc is not given, then
// KNC.rmZone(zoneName) will be called.
KNC.showDeleteZoneDialog = function(zoneName, deleteFunc) {
	var deleteFunc = deleteFunc || function() { KNC.rmZone(zoneName); };
	var html = '<div id="rmzone-dialog"><p>Are you sure you want to delete zone ' +
		KNC.escape(zoneName) + '?</p></div>';
	var dlg = $(html).dialog({
		title: "Delete " + zoneName + "?",
		autoOpen: false,
		modal: true,
		width: 376,
		buttons: {
			"Delete": function() { dlg.dialog('close'); deleteFunc() },
			"Cancel": function() { dlg.dialog('close'); },
		},
		close: function() { dlg.dialog('destroy'); dlg.remove(); },
	});
	dlg.dialog('open');
}

// preUploadFunc - Called before uploading zones, if given
// cancelFunc - Called if the dialog is closed, if given
KNC.showUploadZonesDialog = function(preUploadFunc, cancelFunc) {
	var html = '<div id="zoneupload-dialog">' +
		'<p>Select a previously-downloaded zone file.</p><p><em>Existing ' +
		'zones will be removed before the new zones are added.</em></p>' +
		'<form id="zoneupload-form" method="POST" action="/uploadzones"' +
		'    charset="utf-8" enctype="multipart/form-data">' +
		'<input type="file" name="zone_file" id="zone_file"></input>' +
		'<input id="zoneupload-submit" type="submit" name="submit" value="Upload Zones"></input>' +
		'</form>' +
		'</div>';
	var dlg = $(html);

	var canceled = true; // Set to false if the action button is clicked.

	dlg.dialog({
		beforeClose: function() { if(canceled && cancelFunc) { cancelFunc(); } },
		autoOpen: false,
		buttons: {
			"Upload Zones": function() {
				canceled = false;
				if(preUploadFunc) {
					preUploadFunc();
				}
				$('#zoneupload-submit').click();
				dlg.dialog('close');
			},
			"Cancel": function() {
				dlg.dialog('close');
			}
		},
		modal: true,
		open: function() { dlg.find('#zone_file')[0].select(); },
		title: "Upload Zones",
		width: 460,
		close: function() { dlg.dialog('destroy'); dlg.remove(); },
	});

	dlg.dialog('open');

	return dlg;
}

KNC.showClearZonesDialog = function(preClearFunc, cancelFunc) {
	var html = '<div id="rmzone-dialog"><p>Are you sure you want to remove all zones?  ' +
		'This cannot be undone.</p></div>'
	var dlg = $(html);

	var canceled = true; // Set to false if the action button is clicked.

	dlg.dialog({
		beforeClose: function() { if(canceled && cancelFunc) { cancelFunc(); } },
		autoOpen: false,
		modal: true,
		title: "Remove All Zones",
		width: 390,
		buttons: {
			"Clear Zones": function() {
				if(preClearFunc) {
					preClearFunc();
				}

				var req = KNC.clearZones();
				req.done(function() {
					canceled = false;
					dlg.dialog('close');
				});
				req.fail(function(jqXHR, status, error) {
					dlg.dialog('close');
					KNC.showRequestErrorDialog(
						'Error clearing zones',
						'Error clearing zones',
						jqXHR,
						status,
						error
						);
				});
			},
			"Cancel": function() {
				dlg.dialog('close');
			},
		},
		close: function() { dlg.dialog('destroy'); dlg.remove(); },
	});

	dlg.dialog('open');

	return dlg;
}
