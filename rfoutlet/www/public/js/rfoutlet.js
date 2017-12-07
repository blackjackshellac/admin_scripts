
// document ready
$(function() {

	$(document).keydown(function(e) {
		var tag = e.target.tagName.toLowerCase();
		switch(e.which) {
			case 13:
				if (tag === 'input') {
					defocus();
				} else {
					$(".check").click();
				}
				break;
			case 27:
				if (tag === 'input') {
					defocus();
				} else {
					$(".close").click();
				}
				break;
			default: // do nothing
				break;
		}
	});

	$( ".button_on" ).click(function() {
		var $this = $(this);
		var outlet=$this.data("outlet");
		light_switch(outlet, 1);
	});

	$( ".button_off" ).click(function() {
		var $this = $(this);
		var outlet=$this.data("outlet");
		light_switch(outlet, 0);
	});

	$( ".button_hamburger").click(function() {
		var $this = $(this);
		var outlet=$this.data("outlet");

		get_outlet_config(outlet);

	});

	$( ".close" ).click(function() {
		$('#myModal').hide();
	});

	$( ".check" ).click(function() {
		oc=save_outlet_config();

		post_outlet_config(oc);
	});

	$( "#show" ).click(function() {
		var secret=$("#secret");

		var label;
		var type = secret.attr('type');
		if (type === 'password') {
			type = 'text';
			label='Hide';
		} else {
			type= 'password';
			label='Show';
		}
		secret.attr('type', type);
		$(this).html(label);
	});

	$("#secret").val(getCookie("secret"));
});

function defocus() {
	window.focus();
	if (document.activeElement) {
   	document.activeElement.blur();
	}
}

function setCookie(key, value) {
	var expires = new Date();
	// cookie expires in about 365*10 years
	expires.setTime(expires.getTime() + (10 * 365 * 24 * 60 * 60 * 1000));
	document.cookie = key + '=' + value + ';expires=' + expires.toUTCString();
}

function getCookie(key) {
	var keyValue = document.cookie.match('(^|;) ?' + key + '=([^;]*)(;|$)');
	return keyValue ? keyValue[2] : null;
}

function secret_cookie() {
	var secret=$("#secret").val();
	setCookie('secret', secret);
}

function light_switch(outlet, state) {
	secret_cookie();

	$('#output').html("Waiting for response ...");

	var url = "/lights/"
	url += state ? "on" : "off"

	// this gets added to headers as HTML_OUTLET
	// accessible in sinatra as request.env['HTML_OUTLET']
	$.ajaxSetup({
		headers: {
			outlet: outlet
		}
	});

	$("body").css("cursor", "progress");

	var result = $.getJSON( url, function(data) {
		console.log( "success" );
	}).fail(function(data) {
		console.log( "error" );
	}).always(function(data) {
		if (data instanceof Array) {
			html="";
			for (var i = 0; i < data.length; i++) {
				html+=data[i]+"\n";
			}
			data=html;
		} else if (data instanceof Object) {
			data=data.responseText;
		}
		$('#output').html(data);
		$("body").css("cursor", "default");
		console.log(data);
	});

	return result;
}

function save_outlet_config() {
	oc={
		outlet: $('#outlet').val(),
		data: {}
	}
	data=oc.data;
	data.name=$('#name').val().trim();
	data.code=$('#code').val();
	data.on=$('#code_on').val();
	data.off=$('#code_off').val();
	data.sched={};

	if ($('#sunrise').prop('checked')) {
		data.sched.sunrise={
			enabled: true,
			before: $('#sunrise_range_before').val().trim(),
			after: $('#sunrise_range_after').val().trim()
		}
	}
	if ($('#sunset').prop('checked')) {
		data.sched.sunset={
			enabled: true,
			before: $('#sunset_range_before').val().trim(),
			after: $('#sunset_range_after').val().trim()
		}
	}
	if (jQuery.isEmptyObject(data.sched)) {
		delete data.sched;
	}
	return oc;
}

function show_config(outlet, data) {
	var modal = $('#myModal');

	/*
	data.name
	data.code
	data.on
	data.off
	data.sched
	data.sched.sunrise
	data.sched.sunset
	*/


	$('#modal-title-text').html(data.name);

	$('#outlet').val(outlet);
	$('#name').val(data.name);
	$('#code').val(data.code);
	$('#code_on').val(data.on);
	$('#code_off').val(data.off);

	if (undefined === data.sched) {
		data.sched = {};
	}
	if (undefined === data.sched.sunrise) {
		data.sched.sunrise={
			enabled: false,
			before: 1800,
			after: 1800
		};
	}
	if (undefined === data.sched.sunset) {
		data.sched.sunset = {
			enabled: false,
			before: 1800,
			after: 1800
		};
	}

	$('#sunrise').prop('checked', data.sched.sunrise.enabled);
	$('#sunrise_range_before').val(data.sched.sunrise.before);
	$('#sunrise_range_after').val(data.sched.sunrise.after);

	$('#sunset').prop('checked', data.sched.sunset.enabled);
	$('#sunset_range_before').val(data.sched.sunset.before);
	$('#sunset_range_after').val(data.sched.sunset.after);

	modal.show();
}

function post_outlet_config(oc) {
	secret_cookie();

	var outlet=oc.outlet;
	var data=oc.data;
	var json=JSON.stringify(oc);

	var url="/lights/outlet"
	$.ajaxSetup({
		headers: {
			outlet: outlet
		}
	});

	$("body").css("cursor", "progress");
	var result=$.post( url, json, function() {
		console.log( "success" );
		$("#"+outlet).html(data.name);
	}).fail(function() {
		var msg="Failed to save config for outlet "+data.name;
		console.log(msg);
		$('#output').html(msg);
	}).always(function() {
		console.log( "finished" );
		$("body").css("cursor", "default");
		$('#myModal').hide();
	});

}


function get_outlet_config(outlet) {
	secret_cookie();

	var url="/lights/outlet"
	$.ajaxSetup({
		headers: {
			outlet: outlet
		}
	});

	$("body").css("cursor", "progress");

	var result=$.getJSON( url, function(data) {
		console.log("success");
	}).fail(function(data) {
		console.log("error");
	}).always(function(data) {
		if (data instanceof Object) {
			show_config(outlet, data);
		}

		$('#output').html(data);
		$("body").css("cursor", "default");
	});

	return result;
}
