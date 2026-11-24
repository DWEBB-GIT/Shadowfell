shader_type spatial;

uniform sampler2D stone_detail : repeat_enable, filter_linear_mipmap;
varying vec3 stone_point;
varying vec3 stone_normal;

void vertex() {
	stone_point = VERTEX;
	stone_normal = NORMAL;
}

void fragment() {
	vec3 axis = pow(abs(stone_normal), vec3(3.0));
	axis /= max(dot(axis, vec3(1.0)), .01);
	vec3 p = stone_point + vec3(.37, .15, .71);
	float detail = texture(stone_detail, p.zy * vec2(.24, .48)).r * axis.x
		+ texture(stone_detail, p.xz * .27).r * axis.y
		+ texture(stone_detail, p.xy * vec2(.24, .48)).r * axis.z;
	float fissure = sin(p.x * 4.4 + p.z * 4.7 + sin(p.y * 2.2) * .48) * .12;
	float bedding = smoothstep(.20, .79, detail + sin(p.y * 7.5 + p.x * .85) * .07 + fissure);
	vec3 tint = COLOR.rgb;
	if (!OUTPUT_IS_SRGB) {
		tint = pow(tint, vec3(2.0));
	}
	vec3 stone = tint * mix(.38, .96, bedding);
	vec3 moss = stone * vec3(.87, 1.09, .61);
	float growth = (1.0 - smoothstep(.04, 1.15, p.y)) * smoothstep(.40, .70, detail);
	ALBEDO = mix(stone, moss, growth);
	ROUGHNESS = .98;
	SPECULAR = .07;
}
