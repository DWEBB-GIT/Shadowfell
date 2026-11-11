// A paved town floor (Town._build_paving). UV is the paving's own metres on
// its turned grid: big flagstones in running bond, each a shade apart, with
// dark grout; streets (COLOR.r = 1) get smaller, darker setts so they still
// read at a glance from the iso camera. No textures: light for the web build.
shader_type spatial;
render_mode cull_disabled;

uniform vec4 stone : source_color = vec4(0.6, 0.57, 0.52, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	float street = COLOR.r;
	float size = mix(1.0, 0.6, street);
	vec2 p = UV / size;
	// running bond: every other row shifted half a stone
	p.x += step(1.0, mod(floor(p.y), 2.0)) * 0.5;
	vec2 id = floor(p);
	vec2 f = fract(p);
	float edge = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
	float grout = 1.0 - smoothstep(0.02, 0.06, edge);
	float shade = 0.86 + hash(id) * 0.22;
	vec3 base = stone.rgb * mix(1.0, 0.78, street);
	vec3 col = base * shade;
	// a little wear towards each stone's middle
	col *= 1.0 - 0.05 * (1.0 - smoothstep(0.0, 0.5, edge));
	col = mix(col, base * 0.45, grout);
	ALBEDO = col;
	ROUGHNESS = 0.95;
}
