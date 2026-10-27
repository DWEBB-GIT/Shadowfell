// The player's silhouette through whatever hides them (Diablo 3/4). Pass two
// of the overlay (silhouette_mark.gdshader is pass one): it draws only where
// something nearer covers the player (inverted depth test) and not where the
// player's own body is in view (the stencil the first pass wrote).
shader_type spatial;
render_mode unshaded, depth_draw_never, depth_test_inverted, cull_back, blend_mix;
stencil_mode read, compare_not_equal, 1;

uniform vec4 tint : source_color = vec4(1.0, 0.82, 0.45, 0.5);

void fragment() {
	float rim = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
	ALBEDO = tint.rgb;
	ALPHA = tint.a * (0.4 + 0.6 * rim);
}
