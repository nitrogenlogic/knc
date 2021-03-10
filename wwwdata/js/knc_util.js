/*
 * Depth Camera Server JavaScript utility functions
 * (C)2013 Mike Bourgeous
 */

var KNC = window.KNC || {};

var console = console || {
	log: function(){},
	error: function(){},
	dir: function(){},
	dirxml: function(){}
};

// Rounds to the nearest multiple of mult
KNC.roundMult = function(flt, mult) {
	return Math.round(flt / mult) * mult;
}

// Rounds to the nearest multiple of .001
KNC.roundk = function(flt) {
	return Math.round(flt * 1000) / 1000;
}

// Rounds numbers to multiple of .001, leaves other types unaltered
KNC.checkNum = function(num) {
	if(num instanceof Number || !isNaN(parseFloat(num))) {
		return KNC.roundk(parseFloat(num));
	}
	return num;
};

KNC.escape = function(str) {
	return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}


// Internal use function.  Called when a keyDown, keyUp, or keyPress event
// occurs in a handler added by the utility methods below.
KNC.keyEventHandler = function(that, event, eventMap) {
	var keyCode = event.keyCode || event.charCode;
	var ret = undefined;

	$.each(eventMap, function(idx, map) {
		var code = map[0];
		var handler = map[1];

		if(code == keyCode || (Array.isArray(code) && code.indexOf(keyCode) !== -1)) {
			ret = handler.apply(that, [event]);
		}
	});

	return ret;
}

// Bind handlers to specific key down/press/up events on specific elements.
// jqElements - A jQuery list of elements on which to bind key down events.
// eventMap - An array with pairs containing key codes and functions:
//     [
//         // Functions are applied with this set to the triggering element
//         // and the event object as the first parameter.
//         [ 9, function(event) { console.log("Tab pressed."); } ],
//         [ 27, function(event) { console.log("Escape pressed."); } ],
//         [ [13, 32], function(event) { console.log("Enter or space pressed."); } ]
//     ]
KNC.keyDown = function(jqElements, eventMap) {
	jqElements.keydown(function(ev) { return KNC.keyEventHandler(this, ev, eventMap); });
}
KNC.keyPress = function(jqElements, eventMap) {
	jqElements.keypress(function(ev) { return KNC.keyEventHandler(this, ev, eventMap); });
}
KNC.keyUp = function(jqElements, eventMap) {
	jqElements.keyup(function(ev) { return KNC.keyEventHandler(this, ev, eventMap); });
}


// Binds the given handler to left click, space bar, and enter on the given
// elements.  If keyFunc (one of the KNC.keyUp/Press/Down functions) is not
// specified then keypress events are used, so keys may repeat if held down.
KNC.actionEvent = function(jqElements, handler, keyFunc) {
	var keyFunc = keyFunc || KNC.keyPress;
	jqElements.click(function(ev) {
		if(ev.button == 0) {
			handler(ev);
		}
	});
	keyFunc(jqElements, [ [ [13, 32], handler ] ]);
}

// Adds handlers for value change, enter pressed, and escape pressed to an
// input element.  On change and enter, the handler is called with the element
// as this and the new value as the first parameter.  On escape, the value is
// set to the value stored in storedValueAttribute ("data-value" by default).
KNC.inputEvents = function(jqElements, handler, storedValueAttribute) {
	var attr = storedValueAttribute || 'data-value';

	function revert(ev) {
		ev.preventDefault();

		var jqThis = $(this);
		var val = jqThis.attr(attr);
		console.log("Resetting " + this.id + " from " + jqThis.text() + " to " + val); // XXX
		KNC.setElements(jqThis, val, true);
	}
	function dispatch(ev) {
		ev.preventDefault();

		var val = KNC.getElement($(this));
		console.log("Applying " + val + " to " + this.id); // XXX
		handler.apply(this, [ val ]);
	}
	jqElements.change(dispatch);
	KNC.keyPress(jqElements, [ [ 13, dispatch ] ]);
	KNC.keyDown(jqElements, [ [ 27, revert ] ]);
}


// Sets the contents of one or more elements (text contents for most elements,
// value= attribute for input elements), calls functions with the value.  Pass
// elements/functions as an array or jQuery object.  Returns true if any
// elements were skipped due to being focused, false if no elements were
// skipped.  Doesn't skip focused elements if setFocused is true.
KNC.setElements = function(elements, value, setFocused) {
	var skippedElements = false;

	$.each(elements, function(idx, elem) {
		if(typeof(elem) === 'function') {
			elem(value);
		} else {
			var trueval = elem.getAttribute('data-trueval');
			var falseval = elem.getAttribute('data-falseval');
			var jqElem = $(elem);

			if(trueval || falseval) {
				value = value ? trueval : falseval;
			}

			elem.setAttribute('data-value', value);

			if(!setFocused && jqElem.is(':focus') && elem.type != 'checkbox' && ('' + KNC.getElement(jqElem)) != ('' + value)) {
				$(elem).addClass('skipped_input');
				skippedElements = true;
				return;
			} else {
				$(elem).removeClass('skipped_input');
			}

			switch(elem.nodeName.toLowerCase()) {
				case 'input':
					if(elem.getAttribute('type') === 'checkbox') {
						elem.checked = !!value;
					} else {
						elem.value = value;
						if(jqElem.is(':focus')) {
							elem.select();
						}
					}
					break;

				case 'select':
					$(elem).val(value);
					break;

				default:
					$(elem).text(value);
					break;
			}
		}
	});

	return skippedElements;
}

// Returns true/false for checkboxes, the result of jQuery.val() for other elements.
KNC.getElement = function(jqElem) {
	if(jqElem[0] instanceof HTMLInputElement && ('' + jqElem.attr('type')).toLowerCase() == 'checkbox') {
		return jqElem[0].checked;
	} else {
		return jqElem.val();
	}
}

// Sets an error message in the given jQuery-wrapped error div.
// Returns the contents of the current error message if text is null.
// Hides the div if the text is an empty string.
KNC.errorText = function(jqErr, text) {
	if(text == null) {
		return jqErr.text();
	}

	text = text.toString();
	if(text.length > 0) {
		console.log('Error text: ' + text);
		jqErr.text(text);
		jqErr.stop(true, true);
		if(jqErr.is(':hidden')) {
			jqErr.slideToggle(200);
		}
	} else {
		jqErr.stop(true, true);
		if(jqErr.is(':visible')) {
			jqErr.slideToggle(200, function(){jqErr.text('');});
		}
	}
};

// Shows/hides the given element, animating in the given number of
// milliseconds.  The doneFunc function, if given, will be called when the
// animation completes
KNC.showHide = function(jqElem, visible, time, doneFunc) {
	time = (time == null) ? 400 : time;
	if(visible) {
		jqElem.stop(true, true);
		if(jqElem.is(":hidden")) {
			jqElem.slideToggle(time, doneFunc);
		}
	} else {
		jqElem.stop(true, true);
		if(jqElem.is(":visible")) {
			jqElem.slideToggle(time, doneFunc);
		}
	}
};


// Map of rate limiting instances (id => info).
KNC.rateLimitInfo = {};

// Internal-use callback for rate limiting.  Called whenever a rate limiting
// timer expires.  Schedules the next interval if more data remains.
KNC.rateLimitCallback = function(id) {
	var limitInfo = KNC.rateLimitInfo[id];
	if(!limitInfo) {
		var msg = 'Missing rate limit information for ' + id + ' in callback.';
		console.error(msg);
		throw msg;
	}

	if(limitInfo.data.length == 0) {
		console.log('Cleaning up rate limiting for ' + id); // XXX

		delete KNC.rateLimitInfo[id];
	} else {
		console.log('Releasing rate limiting data for ' + id); // XXX

		var data = limitInfo.data.shift();
		limitInfo.timer = setTimeout(limitInfo.callback, limitInfo.interval);
		limitInfo.handler(data);
	}
}

// Schedules the given data to be called with the given callback.  If more than
// one call is made with the same ID within interval milliseconds, the callback
// will be called with each new data entry approximately every interval ms.  If
// no data has yet been queued, the callback will be called immediately.  If
// replace is true, then new data will replace the last data added, instead of
// being appended to the list of data.  If replace is "merge", then data must
// be an object, and new objects will be merged into existing objects, instead
// of replacing them.  Returns the number of queued elements.
KNC.rateLimit = function(id, interval, callback, data, replace) {
	if(!id || !interval || !callback) {
		throw 'ID, interval, and callback must be specified.';
	}

	var limitInfo = KNC.rateLimitInfo[id];
	if(!limitInfo) {
		console.log('Initializing rate limiting for ' + id + ' with ' + data); // XXX

		callback(data);

		function cb() { KNC.rateLimitCallback(id); };

		limitInfo = {
			id: id,
			interval: interval,
			timer: setTimeout(cb, interval),
			handler: callback,
			callback: cb,
			data: []
		};

		KNC.rateLimitInfo[id] = limitInfo;
	} else {
		limitInfo.interval = interval;

		if(replace && limitInfo.data.length > 0) {
			var idx = limitInfo.data.length - 1;

			if(replace == 'merge') {
				console.log('Merging rate limiting ' + idx + ' data on ' + id); // XXX
				limitInfo.data[idx] = $.extend({}, limitInfo.data[idx], data);
			} else {
				console.log('Replacing rate limiting data ' + idx + ' with ' + data + ' on ' + id); // XXX
				limitInfo.data[idx] = data;
			}
		} else {
			console.log('Adding rate limiting data ' + data + ' to ' + id); // XXX
			limitInfo.data.push(data);
		}
	}

	return limitInfo.data.length;
}
