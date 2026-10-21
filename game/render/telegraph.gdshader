// Ground telegraphs: a faint area, a fill that grows with the wind-up, a bright
// front edge and a rim (src/systems/telegraphs.js). UV.x is the distance from
// the caster (0..1), UV.y is 1 on a side edge.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform float uProgress = 0.0;
uniform vec3 uColor : source_color = vec3(1.0, 0.4, 0.1);
uniform float uOpacity = 1.0;

void fragment() {
	float vRad = UV.x;
	float vEdge = UV.y;
	float base = 0.16;
	float fill = step(vRad, uProgress) * 0.34;
	float front = smoothstep(0.035, 0.0, abs(vRad - uProgress)) * 0.5;
	float rim = smoothstep(0.93, 1.0, max(vRad, vEdge)) * 0.6;
	ALBEDO = uColor;
	ALPHA = clamp((base + fill + front + rim) * uOpacity, 0.0, 1.0);
}
