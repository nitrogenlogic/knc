/* Event log live update. (C)2014 Mike Bourgeous */

var KNC = window.KNC || {};

$(function() {
	var log_body = $('#eventlog').find('tbody');
	var errdiv = $('#log_errors');
	var last_idx = $('#eventlog').attr('data-idx') || -1;
	var logTimer;

	function logErrorText(text) {
		return KNC.errorText(errdiv, text);
	}

	// Prepends a table row for the given log entry object.
	function insertLogEntry(row) {
		var jqRow = $(row.html);
		jqRow.fadeIn();
		log_body.prepend(jqRow);
	}

	// Prepends table rows for new entries from the list of log entries.
	function handleLogData(data) {
		if(data.idx != last_idx) {
			console.log("New log entries received.  New index: " + data.idx);

			// Prepend all log entries of the index moves backward
			if(data.idx < last_idx) {
				last_idx = data.idx - 1;
			}

			// Search upward from the bottom of the list for the first new entry
			var start = 0;
			for(var i = data.log.length - 1; i >= 0; i--) {
				if(data.log[i].idx <= last_idx) {
					start = i + 1;
					break;
				}
			}

			// Move downward to the end of the list, prepending entries to the table
			for(var i = start; i < data.log.length; i++) {
				insertLogEntry(data.log[i]);
			}

			last_idx = data.idx;
		} else {
			console.log("No new log entries received.");
		}
	}

	function updateLog() {
		console.log("Requesting log entries at index " + last_idx); // XXX
		var req = $.get('/log.json?idx=' + last_idx);

		req.done(function(data) {
			handleLogData(data);
			logErrorText('');

			clearTimeout(logTimer);
			logTimer = setTimeout(updateLog, 125);
		});

		req.fail(function(jqXHR) {
			console.log("Error getting event log entries.");

			if(logErrorText() == '') {
				logErrorText('Error getting the event log from the controller.  ' +
					(jqXHR.responseText || ''));
			}

			clearTimeout(logTimer);
			logTimer = setTimeout(updateLog, 2000);
		});
	}
	updateLog();
});
