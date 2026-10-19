import { DB } from '../data/db.js';
import { SIGNPOSTS } from './layout.js';

// Road signposts (data/world.json `signposts`): each arm points at a
// location. Hovering over a post shows where its arms point, and reading it
// (E) puts the same on screen.

const DIRS = [
  ['north', '↑'], ['north-east', '↗'], ['east', '→'], ['south-east', '↘'],
  ['south', '↓'], ['south-west', '↙'], ['west', '←'], ['north-west', '↖'],
];

// [{ label, dir, arrow, metres, angle }] for one signpost; north is -z
export function signpostLines(sp) {
  const [x, z] = sp.position;
  return sp.points.map((p) => {
    const loc = DB.locations[p.to];
    const dx = loc.position[0] - x;
    const dz = loc.position[1] - z;
    const bearing = ((Math.atan2(dx, -dz) * 180) / Math.PI + 360) % 360;
    const [dir, arrow] = DIRS[Math.round(bearing / 45) % 8];
    return { label: p.label || loc.name, dir, arrow, metres: Math.max(10, Math.round(Math.hypot(dx, dz) / 10) * 10), angle: Math.atan2(dx, dz) };
  });
}

export { SIGNPOSTS };
