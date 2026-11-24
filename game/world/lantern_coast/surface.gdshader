shader_type spatial;

#include "res://game/render/cutaway.gdshaderinc"

uniform float cliff_normal_y = 0.788;

uniform sampler2D terrain_control : source_color, filter_linear, repeat_disable;
uniform sampler2D paving_control : filter_linear, repeat_disable;
uniform sampler2D road_control : filter_linear, repeat_disable;
uniform bool fine_roads = false;
uniform sampler2D path_edits : filter_linear, repeat_disable;
uniform bool has_path_edits = false;
uniform sampler2D cobble_detail : filter_linear_mipmap, repeat_enable;
uniform sampler2D terrain_accents : filter_linear_mipmap, repeat_enable;
uniform sampler2D biome_brushwork : filter_linear_mipmap, repeat_enable;
uniform sampler2D bank_detail : filter_linear_mipmap, repeat_enable;
uniform sampler2D ground_detail : filter_linear_mipmap, repeat_enable;
uniform sampler2D cliff_detail : filter_linear_mipmap, repeat_enable;

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	// Keep the hole local to the player's view. The minimap and shadow
	// cameras continue to draw the whole terrain.
	if (!IN_SHADOW_PASS && distance(CAMERA_POSITION_WORLD, sf_cut_cam) < 0.1) {
		vec3 offset = world_position - sf_cut_focus;
		vec3 toward_camera = INV_VIEW_MATRIX[2].xyz;
		float depth = dot(offset, toward_camera);
		float side = length(offset - toward_camera * depth);
		if (depth > 0.6 && offset.y > -0.68 && side < 1.34) {
			float keep = smoothstep(0.62, 1.34, side);
			const float bayer[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
			ivec2 pixel = ivec2(mod(FRAGCOORD.xy, 4.0));
			if (keep < (bayer[pixel.x + 4 * pixel.y] + 0.5) / 16.0) {
				discard;
			}
		}
	}
	vec4 control = texture(terrain_control, UV);
	vec2 road_uv = ((UV * 35.0 - 1.5) * 4.0 + 2.5) / 133.0;
	if (fine_roads) {
		float painted_road = texture(road_control, road_uv).r;
		float above_water = smoothstep(0.12, 1.0, world_position.y);
		control.a = mix(control.a, painted_road, above_water);
	}
	vec3 path_edit = vec3(0.0);
	if (has_path_edits) {
		path_edit = texture(path_edits, road_uv).rgb;
		control.a = control.a * (1.0 - path_edit.b) + path_edit.r;
	}
	vec3 n = normalize(world_normal);
	// Use the shared smooth normal at tile edges. Triangle normals make
	// the paint boundary step from one polygon to the next.
	float wall = 1.0 - smoothstep(cliff_normal_y - 0.06, cliff_normal_y + 0.045, n.y);
	float rock = max(1.0 - smoothstep(0.57, 0.91, n.y), wall * 0.96);
	float foot = smoothstep(0.65, 0.77, n.y) * (1.0 - smoothstep(0.81, 0.92, n.y));
	vec4 brush = texture(ground_detail, world_position.xz / 7.0);
	vec4 wash = texture(ground_detail, world_position.zx / 29.0);
	vec4 grain = texture(ground_detail, world_position.xz / 2.85);
	vec2 surface_uv = world_position.xz;
	vec4 accent = texture(terrain_accents, surface_uv / 6.8);
	vec4 accent_coarse = texture(terrain_accents, (surface_uv.yx + vec2(53.0, 16.0)) / 16.0);
	vec2 stroke = surface_uv + 1.6 * vec2(accent_coarse.r - .5, accent_coarse.b - .5);
	vec4 material_strokes = texture(biome_brushwork, stroke / 6.5);
	vec4 broad_strokes = texture(biome_brushwork, stroke / vec2(18.0, 14.0));
	// The two low-frequency fields break up repeated brush marks at world scale.
	vec4 banks = texture(bank_detail, (surface_uv + vec2(59.0, 19.0)) / 37.0);
	vec4 bank_marks = texture(bank_detail, stroke / 5.0);
	vec3 w = pow(abs(n), vec3(4.0));
	w /= w.x + w.y + w.z;
	vec3 rock_uv = world_position / vec3(12.0, 5.0, 12.0);
	float strata = texture(cliff_detail, rock_uv.zy).r * w.x
		+ texture(cliff_detail, rock_uv.xz).r * w.y
		+ texture(cliff_detail, rock_uv.xy).r * w.z;
	// The control image carries the slowly changing biome pigment. The
	// same compact tile supplies a different brush pattern for each soil.
	vec3 paint = control.rgb;
	if (!OUTPUT_IS_SRGB) {
		paint = pow(max(paint, vec3(0.0)), vec3(1.0 / 2.2));
	}
	float dry = smoothstep(0.07, 0.22, paint.r - paint.g + 0.055);
	float woodland = (1.0 - smoothstep(0.36, 0.55, paint.g))
		* (1.0 - smoothstep(0.07, 0.22, paint.r - paint.g + 0.04));
	float snow = smoothstep(0.62, 0.77, paint.b) * smoothstep(0.0, 0.035, paint.b - paint.r);
	float sand = max(dry, smoothstep(0.58, 0.75, paint.r) * smoothstep(0.10, 0.26, paint.r - paint.b));
	float beach = smoothstep(0.23, 0.43, paint.r - paint.b) * smoothstep(0.50, 0.68, paint.g);
	float ash = (1.0 - smoothstep(.42, .56, paint.g)) * smoothstep(.026, .095, paint.r - paint.g)
		* (1.0 - smoothstep(.07, .16, paint.r - paint.b));
	float gravel = (1.0 - smoothstep(0.16, 0.29, paint.g - paint.b))
		* (1.0 - max(sand, max(snow, woodland)));
	vec3 biome = control.rgb * vec3(0.65, 0.73, 0.61);
	float brushwork = mix(brush.r, brush.a, woodland);
	brushwork = mix(brushwork, brush.b, sand);
	float washwork = mix(wash.r, wash.a, woodland);
	washwork = mix(washwork, wash.b, sand);
	float edge = (wash.g - 0.60) * 0.47 + (brush.g - 0.60) * 0.33
		+ (grain.r - 0.60) * 0.31 + (accent.r - 0.60) * 0.42 + (material_strokes.r - .59) * .26;
	// Leave the wheel tread legible. In wider patches the surroundings creep
	// further onto the shoulders, with different texture in each biome.
	float drift = .5 + .5 * sin(dot(surface_uv, vec2(.116, .069)) + .8 * sin(surface_uv.y * .13))
		* cos(dot(surface_uv, vec2(-.077, .161)));
	float intrusion = smoothstep(.43, .76, drift * .74 + banks.r * .26);
	float fringe_stroke = mix(material_strokes.r, bank_marks.r, woodland * .62);
	fringe_stroke = mix(fringe_stroke, broad_strokes.g, sand * .85);
	fringe_stroke = mix(fringe_stroke, broad_strokes.b, snow * .91);
	float protected_tread = smoothstep(.68, .99, control.a);
	float cover_edge = intrusion * mix(.09, .30, smoothstep(.32, .70, fringe_stroke)) * (1.0 - protected_tread);
	float track = control.a + edge - cover_edge;
	float path = smoothstep(.40, .94, track);
	float shoulder = smoothstep(.10, .60, track) * (1.0 - path);
	float grass_intrusion = smoothstep(0.49, 0.72, brush.r * 0.25 + grain.r * 0.20 + accent.r * 0.25 + material_strokes.r * .30);
	path *= 1.0 - grass_intrusion * (1.0 - smoothstep(0.58, 0.98, control.a)) * (1.0 - sand);
	vec3 road_pigment = mix(vec3(0.27, 0.176, 0.090), vec3(0.39, 0.254, 0.139), sand);
	road_pigment = mix(road_pigment, vec3(0.205, 0.153, 0.094), woodland);
	road_pigment = mix(road_pigment, vec3(0.30, 0.274, 0.226), max(snow, gravel * 0.74));
	float tread = mix(brush.g, brush.a, woodland);
	tread = mix(tread, brush.b, sand);
	tread = mix(tread, strata, gravel * 0.78);
	vec3 dirt = road_pigment * mix(0.52, 1.42, tread) * mix(0.68, 1.26, wash.g);
	dirt *= mix(0.74, 1.21, grain.g);
	float worn_track = smoothstep(0.48, 0.77, wash.g + (accent_coarse.b - 0.53) * 0.34);
	dirt = mix(dirt, dirt * vec3(0.80, 0.88, 0.90), worn_track * 0.75);
	float grit = smoothstep(0.35, 0.64, accent.g);
	float stony_tread = mix(0.20, 0.71, max(gravel, worn_track * 0.72));
	vec3 pebbles = mix(vec3(0.14, 0.117, 0.084), vec3(0.43, 0.36, 0.25), accent.g);
	pebbles = mix(pebbles, vec3(0.31, 0.31, 0.27), gravel * 0.72);
	dirt = mix(dirt, pebbles, grit * stony_tread);
	// Damp earth and weathered stone reflect less light than dry road grit.
	// Use the painted biome so this transition follows the ground at borders.
	float damp_track = woodland * (1.0 - max(sand, snow));
	vec3 road_reflectance = mix(vec3(1.0), vec3(0.36, 0.47, 0.51), damp_track);
	dirt *= road_reflectance;
	vec3 soil = biome * mix(0.39, 1.34, washwork) * mix(0.48, 1.40, brushwork);
	soil *= mix(1.0, 0.70, woodland);
	float meadow = (1.0 - max(sand, snow)) * (1.0 - woodland * 0.65);
	// Break the open grass into worn earth, olive cover and shadowed thatch.
	// These marks stay in the material, so they have no collision or draw calls.
	float mottling = wash.r * 0.42 + accent_coarse.r * 0.32 + grain.r * 0.26;
	float thatch = 1.0 - smoothstep(0.35, 0.60, mottling);
	vec3 warm_soil = mix(soil * vec3(0.83, 0.66, 0.54), vec3(0.19, 0.149, 0.082), 0.20);
	soil = mix(soil, warm_soil, thatch * meadow * 0.62);
	float earth_luma = dot(soil, vec3(0.2126, 0.7152, 0.0722));
	soil = mix(soil, vec3(earth_luma) * vec3(0.97, 1.02, 0.76), meadow * 0.29);
	vec3 grass_brush = mix(vec3(0.68, 0.71, 0.72), vec3(1.27, 1.30, 1.03),
		smoothstep(0.37, 0.82, grain.r));
	soil *= mix(vec3(1.0), grass_brush, meadow * 0.76);
	float grass_density = smoothstep(0.30, 0.78, accent.r * 0.68 + accent_coarse.r * 0.32);
	soil *= mix(vec3(1.0), mix(vec3(0.67, 0.72, 0.60), vec3(1.10, 1.14, 0.90), grass_density), meadow * 0.58);
	float tuft = smoothstep(.35, .79, mix(material_strokes.r, broad_strokes.r, .32));
	soil *= mix(vec3(1.0), mix(vec3(.54, .66, .58), vec3(1.20, 1.14, .89), tuft), meadow * .68);
	float moss_stands = smoothstep(.40, .74, .64 * broad_strokes.r + .36 * material_strokes.r);
	vec3 moss_soil = mix(soil * vec3(.76, .87, .72), soil * vec3(1.13, 1.24, .91), moss_stands);
	soil = mix(soil, moss_soil, woodland * (1.0 - max(sand, snow)) * .82);
	vec3 beach_sand = vec3(0.48, 0.31, 0.14) * mix(0.56, 1.27, brush.b) * mix(0.73, 1.19, wash.b);
	beach_sand *= mix(0.55, 1.0, smoothstep(-0.15, 1.6, world_position.y));
	soil = mix(soil, beach_sand, beach);
	float ripple = smoothstep(.29, .79, .68 * material_strokes.g + .32 * broad_strokes.g);
	float drifts = smoothstep(.32, .71, banks.b * .64 + accent_coarse.r * .36);
	float hardpan = sand * (1.0 - drifts);
	vec3 packed_sand = soil * mix(vec3(.67, .68, .70), vec3(.99, .93, .84), broad_strokes.r);
	packed_sand = mix(packed_sand, pebbles * .67, smoothstep(.60, .88, bank_marks.g) * .55);
	soil = mix(soil, packed_sand, hardpan * .62);
	soil = mix(soil, soil * mix(vec3(.67, .63, .56), vec3(1.19, 1.12, 1.03), ripple), sand * drifts * .57);
	float clinker = smoothstep(.27, .82, material_strokes.a);
	vec3 ash_bed = mix(vec3(.044, .035, .034), vec3(.16, .092, .061), clinker);
	soil = mix(soil, ash_bed, ash * .89);
	vec3 disturbed_ground = mix(soil * .92, dirt, .24);
	disturbed_ground = mix(disturbed_ground, beach_sand * 0.82, beach * 0.72);
	disturbed_ground = mix(disturbed_ground, pebbles * road_reflectance, grit * (0.28 + sand * 0.24));
	float soft_tread = .27 + .20 * intrusion * (1.0 - protected_tread);
	vec3 shared_pigment = mix(dirt, soil * vec3(1.06, .96, .86), soft_tread);
	soil = mix(soil, disturbed_ground, shoulder * (1.0 - grass_intrusion * .65));
	soil = mix(soil, shared_pigment, path);
	vec3 stone_pigment = mix(vec3(0.217, 0.212, 0.203), vec3(0.32, 0.198, 0.112), sand);
	stone_pigment = mix(stone_pigment, vec3(0.155, 0.176, 0.178), woodland);
	vec3 stone = mix(stone_pigment, biome, 0.16) * mix(0.35, 1.58, strata);
	float chips = accent.b;
	if (rock > 0.15) {
		chips = texture(terrain_accents, world_position.zy / vec2(8.0, 4.8)).b * w.x
			+ accent.b * w.y
			+ texture(terrain_accents, world_position.xy / vec2(8.0, 4.8)).b * w.z;
	}
	float broken = smoothstep(0.41, 0.70, chips * 0.68 + accent_coarse.b * 0.32);
	stone *= mix(vec3(0.60, 0.68, 0.72), vec3(1.23, 1.19, 1.08), broken);
	float bedding = smoothstep(.24, .8, strata * .75 + chips * .25);
	stone *= mix(vec3(.54, .62, .68), vec3(1.04, 1.03, .99), bedding);
	stone = mix(stone, soil * vec3(0.81, 0.88, 0.73), foot * grass_density * (1.0 - sand) * 0.42);
	float moss_lip = moss_stands * smoothstep(.23, .67, n.y) * (1.0 - max(sand, snow));
	stone = mix(stone, soil * vec3(.72, .84, .68), moss_lip * mix(.24, .64, woodland));
	stone *= mix(1.05, 0.53, foot);
	vec3 pigment = mix(soil, stone, rock);
	float exposed_stone = smoothstep(.51, .77, banks.g * .57 + bank_marks.g * .43)
		* (max(hardpan * .65, foot * .84) + woodland * .13) * (1.0 - path);
	pigment = mix(pigment, stone * mix(.72, 1.2, bank_marks.g), exposed_stone);
	vec3 snowpack = mix(vec3(0.34, 0.43, 0.51), vec3(0.61, 0.69, 0.73),
		smoothstep(0.32, 0.76, brush.r * 0.52 + wash.r * 0.48));
	float scoured = smoothstep(0.47, 0.76, accent_coarse.b * 0.67 + grain.b * 0.33);
	float ice = smoothstep(.50, .76, material_strokes.b) * smoothstep(.34, .67, broad_strokes.b);
	snowpack = mix(snowpack * mix(.75, 1.06, broad_strokes.b), vec3(.25, .45, .57), ice * .70);
	float snow_drift = max(intrusion, smoothstep(.48, .70, broad_strokes.b));
	float shoveled = path * mix(.59, .34, snow_drift * (1.0 - protected_tread));
	pigment = mix(pigment, snowpack, snow * (1.0 - wall) * (1.0 - shoveled) * (1.0 - scoured * .30));
	float paving = texture(paving_control, UV).r * (1.0 - path_edit.b) + path_edit.g;
	float bank_height = world_position.y;
	// The spring uses a raised water surface over the existing terrain.
	float spring = 1.0 - smoothstep(.94, 1.34, length((surface_uv - vec2(-340.0, 38.0)) / vec2(8.0, 7.0)));
	bank_height -= spring * 10.0;
	float tideline = .45 + banks.r * 1.15 + bank_marks.r * .66;
	float bank_coverage = (1.0 - smoothstep(.19, tideline, bank_height)) * smoothstep(.40, .85, n.y);
	float wetness = (1.0 - smoothstep(-.12, .70, bank_height)) * smoothstep(.38, .88, n.y);
	if (paving > 0.02) {
		float stonework = texture(cobble_detail, world_position.xz / 4.25).r;
		float coverage = smoothstep(0.18, 0.82, paving + edge + (stonework - 0.55) * 0.27);
		vec3 paving_colour = mix(vec3(0.087, 0.080, 0.059), vec3(0.32, 0.285, 0.225), stonework);
		paving_colour *= road_reflectance;
		paving_colour = mix(paving_colour, soil * 0.9, smoothstep(0.57, 0.81, brush.r) * 0.38);
		pigment = mix(pigment, paving_colour, coverage * (1.0 - wall));
	}
	float sandy_bank = max(beach, sand * .76);
	vec3 wet_silt = mix(vec3(.087, .075, .051), vec3(.31, .197, .105), sandy_bank);
	wet_silt *= mix(.55, 1.30, brush.b * .34 + bank_marks.r * .66);
	float bank_stones = smoothstep(.52, .84, bank_marks.g * .8 + banks.g * .2);
	wet_silt = mix(wet_silt, pebbles * .73, bank_stones * (.65 - sandy_bank * .25));
	float rushes = smoothstep(.62, .83, bank_marks.a) * smoothstep(.35, .68, banks.a);
	wet_silt = mix(wet_silt, soil * vec3(.69, .73, .58), rushes * (1.0 - sandy_bank) * (1.0 - wetness));
	pigment = mix(pigment, wet_silt * mix(1.05, .73, wetness), bank_coverage * (1.0 - paving * .88));
	// Compatibility lights in sRGB. Keep its afternoon highlights from
	// driving the greens and clay into neon at the same grade settings.
	if (OUTPUT_IS_SRGB) {
		float luma = dot(pigment, vec3(0.2126, 0.7152, 0.0722));
		pigment = mix(vec3(luma), pigment, 0.78) * 0.82;
	}
	ALBEDO = pigment;
	EMISSION = vec3(.30, .075, .02) * ash * smoothstep(.82, .96, material_strokes.a) * (1.0 - max(path, rock));
	ROUGHNESS = mix(mix(1.0, 0.48, ice * snow), 0.73, wetness);
	SPECULAR = mix(0.06, 0.16, wetness);
}
