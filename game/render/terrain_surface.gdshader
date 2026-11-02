// Surface paint is sampled in world space, independently of terrain triangles.
shader_type spatial;

uniform sampler2D surface_control : source_color, filter_linear, repeat_disable;
uniform sampler2D ground_detail : source_color, filter_linear_mipmap, repeat_enable;
uniform vec2 control_origin;
uniform vec2 control_world_size;
uniform float control_step = 2.0;
uniform float blend_radius = 1.4;
uniform vec4 road_colour : source_color = vec4(0.416, 0.361, 0.282, 1.0);
uniform vec4 stone_colour : source_color = vec4(0.353, 0.337, 0.314, 1.0);

varying vec3 world_position;
varying vec3 world_normal;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float soft_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), f.x),
		mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

void fragment() {
	vec2 uv = (world_position.xz - control_origin + vec2(control_step * 0.5)) / control_world_size;
	vec2 d = vec2(blend_radius) / control_world_size;
	// A compact Gaussian kernel softens painted boundaries without borrowing
	// triangle barycentric colours. Chunk borders have matching padded samples.
	vec3 colour = texture(surface_control, uv).rgb * 0.25;
	colour += texture(surface_control, uv + vec2(d.x, 0.0)).rgb * 0.125;
	colour += texture(surface_control, uv - vec2(d.x, 0.0)).rgb * 0.125;
	colour += texture(surface_control, uv + vec2(0.0, d.y)).rgb * 0.125;
	colour += texture(surface_control, uv - vec2(0.0, d.y)).rgb * 0.125;
	colour += texture(surface_control, uv + d).rgb * 0.0625;
	colour += texture(surface_control, uv - d).rgb * 0.0625;
	colour += texture(surface_control, uv + vec2(d.x, -d.y)).rgb * 0.0625;
	colour += texture(surface_control, uv + vec2(-d.x, d.y)).rgb * 0.0625;

	vec3 n = normalize(world_normal);
	// Gentle slope exposure, retaining the authored biome colour on the tops.
	float rock = smoothstep(0.20, 0.72, 1.0 - abs(n.y));
	colour = mix(colour, stone_colour.rgb, rock * 0.55);

	float road = texture(surface_control, uv).a;
	float grain = soft_noise(world_position.xz * 0.6);
	// Noise affects only the verge, leaving the road centre and its width clear.
	road = clamp(road + (grain - 0.5) * 0.12 * 4.0 * road * (1.0 - road), 0.0, 1.0);
	road = smoothstep(0.0, 1.0, road);
	colour = mix(colour, road_colour.rgb, road * 0.92);

	// World-space triplanar detail avoids stretched texture stripes on cliffs.
	vec3 weights = pow(abs(n), vec3(4.0));
	weights /= max(weights.x + weights.y + weights.z, 0.0001);
	vec3 detail = texture(ground_detail, world_position.zy / 6.0).rgb * weights.x;
	detail += texture(ground_detail, world_position.xz / 6.0).rgb * weights.y;
	detail += texture(ground_detail, world_position.xy / 6.0).rgb * weights.z;
	ALBEDO = colour * detail * mix(0.98, 1.02, soft_noise(world_position.xz * 0.12));
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.12;
}
