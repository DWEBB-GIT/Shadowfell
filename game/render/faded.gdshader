// A house that stands between the camera and the player fades evenly as a
// whole (Diablo 3, Lost Ark), instead of a hole with a soft edge. Only its
// nearest faces draw (depth written, backs culled), so it reads as one
// see-through shape rather than a tangle of walls. Flat shaded.
shader_type spatial;
render_mode cull_back, depth_draw_always, blend_mix;

uniform vec4 albedo : source_color = vec4(1.0);
uniform float uFade = 1.0; // 1 solid, 0 gone

void fragment() {
	NORMAL = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));
	ALBEDO = albedo.rgb * COLOR.rgb;
	ROUGHNESS = 1.0;
	ALPHA = uFade;
}
