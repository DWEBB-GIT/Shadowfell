// Sun shafts: a soft additive ribbon of light falling along the sun's
// direction into a clearing. The quad (1 x 1) is stretched along uAxis from
// the node's origin and turned to face the camera around that axis, so it
// reads as a column of light from any angle. Fades with distance in place of
// the fog (fog would tint an additive shaft grey). UV.y is 0 at the canopy.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, skip_vertex_transform, fog_disabled;

uniform vec3 uAxis = vec3(0.46, -0.86, -0.2);
uniform float uLength = 18.0;
uniform float uWidth = 2.4;
uniform vec4 uColor : source_color = vec4(1.0, 0.82, 0.55, 0.22);
uniform float uSeed = 0.0;
uniform float uFadeNear = 20.0;
uniform float uFadeFar = 34.0;

varying float vDist;

void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 a = normalize(uAxis);
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 side = normalize(cross(a, cam - origin));
	float down = 0.5 - VERTEX.y; // 0 at the top edge, 1 at the bottom
	// a little wider where it lands, as light spreads
	vec3 w = origin + a * down * uLength + side * VERTEX.x * uWidth * (0.7 + 0.5 * down);
	vDist = distance(cam, w);
	VERTEX = (VIEW_MATRIX * vec4(w, 1.0)).xyz;
}

void fragment() {
	float across = abs(UV.x * 2.0 - 1.0);
	float edge = 1.0 - smoothstep(0.1, 1.0, across);
	float t = TIME * 0.25 + uSeed;
	// dust streaks drifting through the beam
	float streak = 0.55 + 0.25 * sin(UV.x * 21.0 + t * 1.3) + 0.2 * sin(UV.x * 7.0 - t * 0.7 + UV.y * 2.0);
	float along = smoothstep(0.0, 0.3, UV.y) * (1.0 - smoothstep(0.82, 1.0, UV.y));
	float pulse = 0.8 + 0.2 * sin(t * 0.9);
	float far = 1.0 - smoothstep(uFadeNear, uFadeFar, vDist);
	ALBEDO = uColor.rgb;
	ALPHA = clamp(uColor.a * edge * streak * along * pulse * far, 0.0, 1.0);
}
