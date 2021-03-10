/*
 * Automation Rules update code for Depth Camera Controller Rules page.
 * (C)2013 Mike Bourgeous
 */

var KNC = window.KNC || {};

KNC.Rules = KNC.Rules || {};

$(function() {
	function submitRow(ev) {
		ev.preventDefault();

		var cmd = document.createElement('input');
		cmd.type = 'hidden';
		cmd.name = 'command';
		cmd.value = 'Update';
		this.form.appendChild(cmd);

		this.form.submit();
	}

	// TODO: Row object model, dynamic updating/addition/removal.
	$('select').change(submitRow);

	KNC.keyPress($('input').not('[type="submit"]'), [ [ 13, submitRow ] ]);
});
