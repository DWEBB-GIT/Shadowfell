// The world's layout, read from data/world.json and data/scenery.json and
// exposed under the names the world code uses. Pure data: positions are
// [x, z] in metres, rotations in degrees around the vertical axis. North is
// -z, so the road climbs "up" the screen from the start towards the watch
// post, and a track carries on north past Mara's forge into the Blackwood.

import { DB } from '../data/db.js';

const W = DB.world;
const S = DB.scenery;

// The whole walkable world, and the regions within it. Regions are bands
// along the road (each holds from its minZ northwards to the previous one);
// the HUD names the one the Warden stands in.
export const BOUNDS = W.bounds;
export const REGIONS = W.regions.map((r) => ({ ...r, minZ: r.minZ === null ? -Infinity : r.minZ }));
export const regionById = (id) => REGIONS.find((r) => r.id === id);
export const regionAt = (z) => REGIONS.find((r) => z >= r.minZ) || REGIONS[REGIONS.length - 1];

const road = (id) => W.roads.find((r) => r.id === id);
export const ROAD = road('fallen_road').points;
export const ROAD_HALF_WIDTH = road('fallen_road').halfWidth;
export const TRACK = road('forest_track').points;

export const PLAYER_START = W.playerStart;
export const SHRINES = W.shrines;
export const SHRINE = SHRINES[0];

// Townsfolk where they stand, merged with who they are (data/npcs.json).
export const NPCS = W.npcSpawns.map((s) => {
  const n = DB.npcs[s.npc];
  return { ...n, ...s, id: n.id };
});

// Enemy spawns: { id, type, position }.
export const ENEMIES = W.enemySpawns.map((s) => ({ id: s.id, type: s.enemy, position: s.position }));

// Static props. `collider` is a circle radius (0 = walk-through) or a list of
// [x, z, radius] circles in the prop's own space.
export const PROPS = S.props;
// Areas kept clear of procedurally scattered trees: [x, z, radius].
export const CLEARINGS = S.clearings;
// Warm light sources (and the seer's witchlight).
export const LIGHTS = S.lights;
// Witchlight glows on standing stones: [x, z, rotation of the stone].
export const WITCHLIGHTS = S.witchlights;

// A rumble plays near these (an elite's ground), quieter once it is dead.
// ponds to fish (`fishTable` names a loot table) and places too dark to enter without a torch
export const WATER = DB.water;
export const OBSCURED = DB.obscured;

// Buildings you can walk into (the Ford Inn): footprint, models, walls.
export const BUILDINGS = W.buildings || [];
// Places that count as a cooking fire (the inn's hearth); a pitched camp counts too.
export const STATIONS = W.stations || [];
// road signposts: each arm points to a location (data/world.json `signposts`)
export const SIGNPOSTS = W.signposts || [];
// Ground flattened for a building: [x, z, radius].
export const PADS = W.pads || [];

export const DANGER_ZONES = W.dangerZones.map((z) => ({ position: z.position, radius: z.radius, enemy: z.enemySpawn }));
