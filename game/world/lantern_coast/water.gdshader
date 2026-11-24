shader_type spatial;
render_mode cull_disabled;

uniform vec2 sandy_bay = vec2(9999.0);
uniform sampler2D water_field : filter_linear, repeat_disable;
uniform sampler2D ripple_detail : filter_linear_mipmap, repeat_enable;
uniform vec4 field_bounds = vec4(0.0, 0.0, 1.0, 1.0);
uniform bool raised_pool = false;

varying vec2 water_position;

void vertex() {
	water_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 p = water_position;
	vec2 field_uv = (p - field_bounds.xy) / field_bounds.zw;
	vec4 field = texture(water_field, field_uv);
	float signed_depth = field.r * 7.0 - 2.0;
	float depth = max(signed_depth, 0.0) / 5.0;
	float shore = field.a;
	if (raised_pool || any(lessThan(field_uv, vec2(0.0))) || any(greaterThan(field_uv, vec2(1.0)))) {
		depth = 0.7;
		shore = 1.0;
		signed_depth = 3.5;
	}
	vec2 drift = vec2(TIME * 0.018, TIME * -0.013);
	float swell = texture(ripple_detail, p / vec2(17.0, 13.0) + drift).a;
	float crosswave = texture(ripple_detail, (p.yx + vec2(8.0, 19.0)) / vec2(11.0, 8.0) - drift * 1.33).a;
	float ripple = swell * 0.64 + crosswave * 0.36;
	float glint = smoothstep(0.73, 0.94, ripple) * 0.34;
	float cove = 1.0 - smoothstep(19.0, 53.0, distance(water_position, sandy_bay));
	vec3 deep = mix(vec3(0.026, 0.113, 0.151), vec3(0.024, 0.17, 0.18), cove);
	vec3 shallows = mix(vec3(0.12, 0.225, 0.18), vec3(0.18, 0.34, 0.24), cove);
	float shallow = 1.0 - smoothstep(0.025, 0.38, depth * 0.76 + shore * 0.24);
	vec3 pigment = mix(deep, shallows, shallow);
	pigment *= 0.84 + ripple * 0.32;
	vec3 glints = mix(vec3(0.15, 0.32, 0.32), vec3(0.35, 0.53, 0.37), cove);
	pigment = mix(pigment, glints, glint);
	// A continuous contact band, with the animated wash entirely on the wet side.
	float contact_depth = max(signed_depth + .11, 0.0);
	float shore_band = 1.0 - smoothstep(.04, .38, contact_depth);
	float tide = .5 + .5 * sin(TIME * .85 + shore * 2.2 + swell * .45);
	float wash = shore_band * mix(.28, .52, cove) * mix(.80, 1.0, tide);
	ALBEDO = mix(pigment, vec3(0.36, 0.52, 0.44), wash);
	vec3 normal = normalize(vec3((crosswave - 0.5) * 0.095, 1.0, (swell - 0.5) * 0.095));
	NORMAL = normalize((VIEW_MATRIX * vec4(normal, 0.0)).xyz);
	ROUGHNESS = mix(0.49, 0.37, shallow);
	SPECULAR = 0.25;
	float opacity = mix(0.37, 0.99, smoothstep(0.02, 0.70, depth));
	float waterline = smoothstep(-.26, .02, signed_depth);
	ALPHA = max(opacity * waterline, shore_band * waterline * mix(.26, .43, cove));
}
