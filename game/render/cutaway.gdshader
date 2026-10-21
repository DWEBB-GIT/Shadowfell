// Woodland with a cutaway (src/world/world.js `_cutawayMaterial`): trees
// between the camera and the player dissolve in a dither pattern so the
// character is never hidden behind foliage. Flat shaded, vertex coloured.
shader_type spatial;
// (diffuse_lambert and specular_disabled render black in GL Compatibility)

uniform vec4 albedo : source_color = vec4(1.0);
uniform vec3 uCamPos;
uniform vec3 uFocus;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 seg = uFocus - uCamPos;
	float t = clamp(dot(v_world - uCamPos, seg) / max(dot(seg, seg), 1e-4), 0.0, 1.0);
	float d = length(v_world - (uCamPos + seg * t));
	float fade = smoothstep(2.2, 4.2, d) + step(0.93, t);
	float dither = fract(sin(dot(floor(FRAGCOORD.xy), vec2(12.9898, 78.233))) * 43758.5453);
	if (fade < dither) {
		discard;
	}
	NORMAL = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));
	ALBEDO = albedo.rgb * COLOR.rgb;
	ROUGHNESS = 1.0;
}
