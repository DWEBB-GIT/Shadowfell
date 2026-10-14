// Hand-placed layout of The Fallen Road. Pure data: positions are [x, z] in
// metres, rotations in degrees around the vertical axis. North is -z, so the
// road climbs "up" the screen from the start towards the watch post.

export const BOUNDS = { minX: -36, maxX: 36, minZ: -49, maxZ: 47 };

export const ROAD = [
  [-9, 58], [-8, 44], [-6, 32], [-2, 22], [3, 14], [5, 6], [5, -2], [3, -10],
  [6, -18], [13, -26], [19, -33], [22, -40], [23, -52],
];
export const ROAD_HALF_WIDTH = 2.2;

export const PLAYER_START = { position: [-6, 33], facing: 180 };

export const SHRINE = { id: 'shrine_road', position: [9.6, 5.2], rotation: -90 };

export const CART = { position: [-6.3, -4.0], rotation: 25 };

export const ENEMIES = [
  { id: 'ghoul_cart', type: 'ghoul', position: [-3.2, -9.0] },
  { id: 'ghoul_graves', type: 'ghoul', position: [-21.5, 11.0] },
  { id: 'ghoul_road', type: 'ghoul', position: [9.0, -21.0] },
  { id: 'brute_hallow', type: 'brute', position: [22.5, -19.5] },
];

// Static props. `collider` is a circle radius (0 = walk-through).
export const PROPS = [
  // the cart site
  { model: 'cart', position: CART.position, rotation: CART.rotation, collider: [[0, 0, 1.3], [0.4, -1.2, 1.0], [-0.4, 1.2, 1.0]], examine: 'cart', examineOffset: [1.6, 1.6] },
  { model: 'crate', position: [-8.9, -5.4], rotation: 12, collider: 0.5 },
  { model: 'crate', position: [-3.6, -1.6], rotation: 50, collider: 0.5 },
  { model: 'crate_broken', position: [-8.4, -1.4], rotation: -30, collider: 0 },
  { model: 'wheel', position: [-10.8, -8.0], rotation: 70, tilt: 8, collider: 0 },
  { model: 'fence', position: [-1.2, 1.5], rotation: 80, collider: 0 },

  // start of the road
  { model: 'waymarker', position: [-3.2, 31.0], rotation: -70, collider: 0.4, examine: 'waymarker' },
  { model: 'dead_tree', position: [-10.5, 45.0], rotation: 0, tilt: 84, collider: [[0, 0, 0.6], [1.6, 0, 0.6], [3.2, 0, 0.6], [-1.6, 0, 0.6]] }, // fallen across the road
  { model: 'fence', position: [-1.0, 38.0], rotation: 100, collider: 0 },
  { model: 'fence', position: [0.0, 26.0], rotation: 70, collider: 0 },

  // the shrine area
  { model: 'shrine', position: SHRINE.position, rotation: SHRINE.rotation, collider: 0.85 },
  { model: 'rock0', position: [12.0, 2.5], rotation: 40, scale: 0.7, collider: 0.8 },
  { model: 'rock1', position: [12.4, 8.0], rotation: 10, scale: 0.8, collider: 0.7 },

  // old roadside graves to the west
  { model: 'grave0', position: [-23.5, 12.8], rotation: 10, collider: 0.3 },
  { model: 'grave0', position: [-25.2, 11.2], rotation: -15, collider: 0.3 },
  { model: 'grave0', position: [-22.0, 14.6], rotation: 25, collider: 0.3 },
  { model: 'grave0', position: [-26.6, 13.9], rotation: 5, collider: 0.3 },
  { model: 'grave0', position: [-20.8, 9.4], rotation: -30, collider: 0.3 },
  { model: 'ruin_wall', position: [-27.5, 9.0], rotation: 75, collider: [[0, 0, 0.9], [0, 1.2, 0.8], [0, -1.2, 0.8]] },
  { model: 'dead_tree', position: [-19.0, 15.5], rotation: 40, collider: 0.4 },
  { model: 'dead_tree', position: [-28.0, 16.0], rotation: 200, collider: 0.4 },

  // the hidden satchel among rocks to the east
  { model: 'rock0', position: [23.5, 11.0], rotation: 0, scale: 1.2, collider: 1.2 },
  { model: 'rock1', position: [26.8, 12.0], rotation: 60, scale: 1.1, collider: 1.0 },
  { model: 'rock0', position: [25.0, 15.6], rotation: 140, scale: 1.0, collider: 1.0 },

  // Hallow Cut: fresh timber markers with bells, the brute's ground
  { model: 'grave1', position: [19.8, -17.0], rotation: 10, collider: 0.25 },
  { model: 'grave1', position: [21.5, -15.8], rotation: -10, collider: 0.25 },
  { model: 'grave1', position: [24.5, -16.6], rotation: 30, collider: 0.25 },
  { model: 'grave1', position: [25.9, -19.8], rotation: 5, collider: 0.25 },
  { model: 'grave1', position: [25.0, -22.8], rotation: -25, collider: 0.25 },
  { model: 'grave1', position: [19.0, -22.0], rotation: 15, collider: 0.25, examine: 'hallow_cut' },
  { model: 'ruin_wall', position: [27.8, -24.5], rotation: 120, collider: [[0, 0, 0.9], [0.9, 0.6, 0.8], [-0.9, -0.6, 0.8]] },
  { model: 'dead_tree', position: [17.0, -14.0], rotation: 0, collider: 0.4 },
  { model: 'dead_tree', position: [28.5, -17.5], rotation: 90, collider: 0.4 },

  // the watch post and its approach
  { model: 'watch_post', position: [24.0, -46.0], rotation: 0, collider: [[0, 0, 2.7], [-4.8, -0.6, 1.4], [-2.6, -0.4, 1.4], [-7.2, -0.8, 1.4], [4.0, 1.4, 1.6], [6.5, 2.0, 1.0], [-0.5, 3.2, 1.0], [2, 3.4, 1.0]], examine: 'watch_post', examineOffset: [0, 2.6] },
  { model: 'ruin_wall', position: [10.5, -38.6], rotation: 15, collider: [[0, 0, 0.9], [1.2, 0.3, 0.8], [-1.2, -0.3, 0.8]] },
  { model: 'fence', position: [17.5, -35.0], rotation: 40, collider: 0 },
  { model: 'grave0', position: [12.6, -29.0], rotation: 30, collider: 0.3 },
  { model: 'rock1', position: [30.0, -36.0], rotation: 30, scale: 1.3, collider: 1.2 },

  // scattered boulders along the woodland edge
  { model: 'rock0', position: [-14.0, 24.0], rotation: 10, scale: 1.1, collider: 1.1 },
  { model: 'rock1', position: [-15.5, -14.0], rotation: 80, scale: 1.2, collider: 1.1 },
  { model: 'rock0', position: [15.5, 26.5], rotation: 200, scale: 0.9, collider: 0.9 },
  { model: 'rock0', position: [-10.0, -28.0], rotation: 120, scale: 1.4, collider: 1.4 },
  { model: 'ruin_wall', position: [-12.5, -31.5], rotation: -20, collider: [[0, 0, 0.9], [1.2, -0.4, 0.8], [-1.2, 0.4, 0.8]] },
  { model: 'dead_tree', position: [-4.0, -22.0], rotation: 30, collider: 0.4 },
  { model: 'dead_tree', position: [14.0, -6.0], rotation: 120, collider: 0.4 },
];

// Areas kept clear of procedurally scattered trees: [x, z, radius].
export const CLEARINGS = [
  [PLAYER_START.position[0], PLAYER_START.position[1], 5],
  [SHRINE.position[0], SHRINE.position[1], 5],
  [CART.position[0] - 1.5, CART.position[1] - 1, 8],
  [-23.5, 11.5, 6.5],
  [23, -19.5, 8.5],
  [24, -42, 10],
  [24.5, 13, 4.5],
  [10.5, -38, 4],
];

// Warm light sources: [x, z, height, intensity, distance].
export const LIGHTS = [
  { position: [SHRINE.position[0] - 0.4, SHRINE.position[1]], height: 0.9, intensity: 6, distance: 9, flicker: true },
  { position: [-5.0, -2.2], height: 0.4, intensity: 2.0, distance: 5, flicker: true, lantern: true }, // guttering lantern at the cart
  // braziers either side of the watch post approach, visible through the fog;
  // they share one light between them to keep the light count down
  { position: [24.1, -40.6], height: 1.8, intensity: 14, distance: 15, flicker: true },
  { position: [19.6, -41.4], brazier: true, noLight: true },
  { position: [28.6, -41.2], brazier: true, noLight: true },
];

// A rumble plays near here (the elite's territory).
export const DANGER_ZONES = [{ position: [22.5, -19.5], radius: 14 }];
