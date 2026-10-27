// Pass one of the player's silhouette: marks the stencil wherever the player
// is in view, and draws nothing.
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_back, blend_mix;
stencil_mode write, compare_always, 1;

void fragment() {
	ALBEDO = vec3(0.0);
	ALPHA = 0.0;
}
