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
