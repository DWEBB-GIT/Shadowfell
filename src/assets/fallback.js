import * as THREE from 'three';

// Procedural stand-ins used only if an embedded Blender model fails to load.
// Characters keep the same part names so the animator still works.

const mat = (hex) => new THREE.MeshLambertMaterial({ color: hex, flatShading: true });

function box(w, h, d, hex, x = 0, y = 0, z = 0) {
  const m = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat(hex));
  m.position.set(x, y, z);
  m.castShadow = true;
  return m;
}

function humanoid(scale, body, limb) {
  const root = new THREE.Group();
  const torso = new THREE.Group();
  torso.name = 'Torso';
  torso.position.y = 0.92 * scale;
  torso.add(box(0.45 * scale, 0.6 * scale, 0.3 * scale, body, 0, 0.3 * scale, 0));
  root.add(torso);
  const head = new THREE.Group();
  head.name = 'Head';
  head.position.y = 0.66 * scale;
  head.add(box(0.24 * scale, 0.26 * scale, 0.24 * scale, limb, 0, 0.15 * scale, 0));
  torso.add(head);
  for (const [side, s] of [['L', 1], ['R', -1]]) {
    const arm = new THREE.Group();
    arm.name = 'Arm_' + side;
    arm.position.set(0.3 * s * scale, 0.56 * scale, 0);
    arm.add(box(0.12 * scale, 0.6 * scale, 0.12 * scale, limb, 0, -0.3 * scale, 0));
    torso.add(arm);
    const leg = new THREE.Group();
    leg.name = 'Leg_' + side;
    leg.position.set(0.12 * s * scale, 0.93 * scale, 0);
    leg.add(box(0.16 * scale, 0.9 * scale, 0.16 * scale, body, 0, -0.45 * scale, 0));
    root.add(leg);
  }
  return root;
}

export function fallbackModel(name) {
  switch (name) {
    case 'warden':
      return humanoid(1, 0x4a3a2a, 0x8a7060);
    case 'ghoul':
      return humanoid(0.95, 0x5a564e, 0x6a665e);
    case 'brute':
      return humanoid(1.3, 0x3a3836, 0x5a4a3a);
    case 'training_dummy': {
      // a straw man on a post, built in code; Torso so it rocks when hit
      const g = new THREE.Group();
      g.add(box(0.14, 1.0, 0.14, 0x4a3420, 0, 0.5, 0));
      const torso = new THREE.Group();
      torso.name = 'Torso';
      torso.position.y = 0.95;
      torso.add(box(0.5, 0.7, 0.32, 0xb59a5a, 0, 0.35, 0));
      torso.add(box(1.2, 0.1, 0.1, 0x4a3420, 0, 0.55, 0));
      torso.add(box(0.3, 0.3, 0.3, 0xc4a868, 0, 0.88, 0));
      torso.add(box(0.52, 0.08, 0.34, 0x6a2a20, 0, 0.2, 0));
      g.add(torso);
      return g;
    }
    case 'town_board': {
      // a notice board on two posts under a little roof, papers pinned on
      const g = new THREE.Group();
      g.add(box(0.12, 2.0, 0.12, 0x4a3420, -0.7, 1.0, 0));
      g.add(box(0.12, 2.0, 0.12, 0x4a3420, 0.7, 1.0, 0));
      g.add(box(1.5, 0.9, 0.08, 0x5a4028, 0, 1.35, 0));
      g.add(box(1.8, 0.08, 0.5, 0x3a2818, 0, 2.02, 0));
      for (const [x, y, w, h] of [[-0.45, 1.5, 0.3, 0.38], [0.05, 1.42, 0.34, 0.46], [0.48, 1.55, 0.28, 0.3], [-0.2, 1.08, 0.36, 0.26], [0.4, 1.12, 0.3, 0.3]]) g.add(box(w, h, 0.02, 0xd8c8a0, x, y, -0.06));
      return g;
    }
    case 'pine': {
      const g = new THREE.Group();
      const c = new THREE.Mesh(new THREE.ConeGeometry(1.6, 4.5, 7), mat(0x1c3020));
      c.position.y = 3;
      g.add(c);
      return g;
    }
    default: {
      const g = new THREE.Group();
      g.add(box(0.8, 0.8, 0.8, 0x6a6458, 0, 0.4, 0));
      return g;
    }
  }
}
