
// document ready
$(function() {
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
