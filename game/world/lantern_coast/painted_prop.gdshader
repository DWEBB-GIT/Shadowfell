shader_type spatial;

#include "res://game/render/cutaway.gdshaderinc"

uniform vec4 pigment : source_color = vec4(1.0);
uniform float glow = 0.0;
uniform vec3 grain_direction = vec3(1.0);
varying vec3 world_point;
varying vec3 paint_point;

void vertex() {
	paint_point = VERTEX;
	world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (!IN_SHADOW_PASS && distance(CAMERA_POSITION_WORLD, sf_cut_cam) < 0.1
			&& sf_cut_keep(world_point, FRAGCOORD.xy) < 0.5) {
		discard;
	}
	vec3 p = paint_point * grain_direction;
	float wash = sin(p.x * 3.9 + p.z * 5.4 + sin(p.y * 2.6)) * 0.06;
	float flecks = sin(p.x * 28.3 + p.z * 17.1) * sin(p.y * 24.2 + p.x) * 0.035;
	float low = 0.84 + 0.14 * smoothstep(-0.45, 1.1, paint_point.y);
	ALBEDO = pigment.rgb * (low + wash + flecks);
	EMISSION = pigment.rgb * glow;
	ROUGHNESS = 0.94;
	SPECULAR = 0.08;
}
