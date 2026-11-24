shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha, diffuse_burley;

uniform float run_length = 28.0;

void fragment() {
	float run = UV.y - TIME * 3.2;
	float across = UV.x + sin(run * 0.81 + UV.x * 8.0) * 0.015;
	float ribbons = sin(across * 42.0 + sin(run * 0.57) * 1.1);
	ribbons += sin(across * 91.0 + run * 0.85) * 0.48;
	float white = smoothstep(-0.32, 0.95, ribbons + sin(run * 2.1 + across * 27.0) * 0.35);
	float edge = smoothstep(0.005, 0.19, across) * smoothstep(0.005, 0.19, 1.0 - across);
	float fall = smoothstep(5.5, 12.5, UV.y) * (1.0 - smoothstep(19.0, run_length - 2.0, UV.y));
	float finish = smoothstep(0.08, 2.5, UV.y) * (1.0 - smoothstep(run_length - 7.0, run_length - 0.15, UV.y));
	vec3 stream = vec3(0.055, 0.24, 0.27);
	vec3 foam = vec3(0.51, 0.72, 0.68);
	ALBEDO = mix(stream, foam, (0.15 + white * 0.8) * edge * (0.52 + 0.48 * fall));
	EMISSION = foam * white * edge * fall * 0.16;
	ALPHA = edge * finish * (0.86 + white * 0.14);
	ROUGHNESS = 0.55;
}
