// Flat shaded, vertex coloured, with the see-through circle around the
// player (cutaway.gdshaderinc): woodland trees, town walls and houses.
shader_type spatial;
// (diffuse_lambert and specular_disabled render black in GL Compatibility)

#include "res://game/render/cutaway.gdshaderinc"

uniform vec4 albedo : source_color = vec4(1.0);

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (sf_cut_keep(v_world, FRAGCOORD.xy) < 0.5) {
		discard;
	}
	NORMAL = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));
	ALBEDO = albedo.rgb * COLOR.rgb;
	ROUGHNESS = 1.0;
}
