// Flat shaded, vertex coloured, solid: a house while it hides nothing.
shader_type spatial;

uniform vec4 albedo : source_color = vec4(1.0);

void fragment() {
	NORMAL = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));
	ALBEDO = albedo.rgb * COLOR.rgb;
	ROUGHNESS = 1.0;
}
