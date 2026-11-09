shader_type canvas_item;
// Mythkeep wordmark: the white fill pass becomes cast gold (bright top,
// a hot band across the middle, deep bronze below) with a little grain and
// pitting; the outline and the extruded shadow pass keep their own colours.

uniform float text_top = 0.0;
uniform float text_height = 60.0;
uniform float grain = 0.12;

varying vec2 local;

void vertex() {
	local = VERTEX;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec4 c = COLOR;
	if (c.r > 0.85 && c.g > 0.85) {
		float t = clamp((local.y - text_top) / text_height, 0.0, 1.0);
		vec3 top = vec3(1.0, 0.93, 0.66);
		vec3 mid = vec3(0.96, 0.72, 0.28);
		vec3 low = vec3(0.55, 0.30, 0.09);
		vec3 gold = t < 0.5 ? mix(top, mid, t / 0.5) : mix(mid, low, (t - 0.5) / 0.5);
		// a bright horizon line just under the middle, like polished metal
		gold += vec3(0.35, 0.25, 0.1) * smoothstep(0.05, 0.0, abs(t - 0.53));
		float n = noise(local * 0.35) * 0.6 + noise(local * 1.3) * 0.4;
		gold *= 1.0 - grain + grain * 2.0 * n;
		// small dark pits
		gold *= mix(0.78, 1.0, step(0.035, hash(floor(local * 0.7))));
		c.rgb = gold;
	}
	COLOR = c;
}
