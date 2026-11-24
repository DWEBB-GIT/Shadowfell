// The nature pack's textured trees, rocks and plants (alpha cut leaves,
// normal mapped bark) with the see-through circle around the player
// (cutaway.gdshaderinc). Assets.use_cutaway builds one of these per source
// material, so thousands of props still share a handful of materials.
shader_type spatial;
render_mode cull_disabled;

#include "res://game/render/cutaway.gdshaderinc"

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_albedo_tex = false;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool use_normal_tex = false;
uniform float normal_scale = 1.0;
uniform float alpha_scissor = 0.0;
uniform float roughness = 1.0;
uniform float snow_cover = 0.0;

varying vec3 v_world;
varying vec3 v_local;
varying vec3 v_up;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_local = VERTEX;
	v_up = MODEL_NORMAL_MATRIX * NORMAL;
}

void fragment() {
	vec4 c = albedo;
	if (use_albedo_tex) {
		c *= texture(albedo_tex, UV);
	}
	if (c.a < alpha_scissor || sf_cut_keep(v_world, FRAGCOORD.xy) < 0.5) {
		discard;
	}
	ALBEDO = c.rgb;
	if (snow_cover > 0.0) {
		float upward = abs(normalize(v_up).y);
		float height = smoothstep(1.0, 5.0, v_local.y);
		float broken = sin(dot(v_local, vec3(3.7, 1.3, 2.1)) + sin(v_local.z * 4.4));
		float needles = smoothstep(.45, .83, upward * .70 + height * .26 + broken * .13);
		float snow = needles * snow_cover;
		ALBEDO = mix(ALBEDO, vec3(.66, .75, .79) * mix(.80, 1.04, height), snow);
	}
	if (use_normal_tex) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
	ROUGHNESS = roughness;
}
