// The see-through circle (Dan, 2026-11-02, after Lost Ark / Diablo 4 / Path of
// Exile): anything between the camera and the player is cut away in an
// ordered dither inside a round hole around the player, soft at its edge,
// whatever it is: a house, a tree, a rock. Things beside or behind the player
// stay solid, so a building never vanishes as a whole.
// The camera and the player's chest are global shader values, set once a
// frame by World.set_cutaway, so every material shares them.

global uniform vec3 sf_cut_cam;
global uniform vec3 sf_cut_focus;

const float SF_CUT_INNER = 1.5; // fully open this close to the line (m)
const float SF_CUT_OUTER = 2.8; // solid again from here
const float SF_CUT_BEHIND = 0.6; // this close in front of the player stays solid

// 0 cuts the pixel, 1 keeps it. `world` is the pixel's world position.
float sf_cut_keep(vec3 world, vec2 frag) {
	vec3 seg = sf_cut_focus - sf_cut_cam;
	float len = length(seg);
	if (len < 0.01) {
		return 1.0;
	}
	vec3 dir = seg / len;
	float along = dot(world - sf_cut_cam, dir);
	if (along > len - SF_CUT_BEHIND || along < 0.0) {
		return 1.0;
	}
	float d = length(world - (sf_cut_cam + dir * along));
	float solid = smoothstep(SF_CUT_INNER, SF_CUT_OUTER, d);
	// 4x4 Bayer threshold: an even retro screen-door, not noise
	ivec2 p = ivec2(mod(frag, 4.0));
	int i = p.x + p.y * 4;
	const float bayer[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	float threshold = (bayer[i] + 0.5) / 16.0;
	return solid < threshold ? 0.0 : 1.0;
}
