import * as THREE from 'three';

// Procedural animation for the Blender characters. Each part's origin sits at
// its joint, so rotating a part swings it naturally. All timing is in seconds.

const PART_NAMES = ['Torso', 'Head', 'Arm_L', 'Arm_R', 'Leg_L', 'Leg_R', 'Weapon'];
const ease = (t) => t * t * (3 - 2 * t);

export class Rig {
  constructor(model, style = 'warden') {
    this.model = model;
    model.rotation.order = 'YXZ'; // yaw outermost, so falls happen in the character's own frame
    this.style = style; // 'warden' | 'ghoul' | 'brute' | 'hound' | 'archer' | 'seer'
    this.parts = {};
    this.base = {};
    for (const name of PART_NAMES) {
      const obj = model.getObjectByName(name);
      if (obj) {
        this.parts[name] = obj;
        this.base[name] = { rot: obj.rotation.clone(), pos: obj.position.clone() };
      }
    }
    this.phase = 0;
    this.move = 0; // 0 idle .. 1 full walk
    this.time = Math.random() * 10;
    this.action = null; // { type, t, duration, impact }
    this.flinch = 0;
    this.death = -1; // -1 alive, otherwise seconds since death
    this.lean = 0;
    this.pose = null; // a held pose ('fish') when no action plays
    this.frozen = 0; // hit-stop: the pose holds for a moment when a blow lands
  }

  // hold the current pose for `seconds` (the weight of a landed blow)
  freeze(seconds) {
    this.frozen = Math.max(this.frozen, seconds);
  }

  play(type, duration, impact = 0.5) {
    this.action = { type, t: 0, duration, impact };
  }

  hit() {
    this.flinch = 1;
  }

  die() {
    this.death = 0;
    this.action = null;
  }

  revive() {
    this.death = -1;
    this.model.rotation.x = 0;
    this.model.position.y = 0;
  }

  reset() {
    for (const [name, obj] of Object.entries(this.parts)) {
      obj.rotation.copy(this.base[name].rot);
      obj.position.copy(this.base[name].pos);
    }
  }

  update(dt, speed01) {
    if (this.frozen > 0 && this.death < 0) {
      this.frozen -= dt;
      return;
    }
    this.time += dt;
    this.move += (speed01 - this.move) * Math.min(1, dt * 10);
    const stride = this.style === 'brute' ? 6 : this.style === 'ghoul' ? 7 : this.style === 'hound' ? 13 : 9;
    this.phase += dt * stride * Math.max(0.2, this.move);
    this.flinch = Math.max(0, this.flinch - dt * 4);
    this.reset();

    const p = this.parts;
    const s = Math.sin(this.phase);
    const m = this.move;
    const breathe = Math.sin(this.time * 1.8) * 0.03;

    if (p.Leg_L) p.Leg_L.rotation.x += s * 0.65 * m;
    if (p.Leg_R) p.Leg_R.rotation.x -= s * 0.65 * m;
    if (p.Arm_L) p.Arm_L.rotation.x -= s * 0.45 * m;
    if (p.Arm_R) p.Arm_R.rotation.x += s * 0.45 * m;
    if (p.Torso) {
      p.Torso.position.y += Math.abs(Math.cos(this.phase)) * 0.04 * m;
      p.Torso.rotation.x += breathe - this.flinch * 0.35;
      p.Torso.rotation.z += Math.sin(this.phase) * 0.05 * m;
    }

    if (this.style === 'ghoul') {
      // arms reach forward as it shambles; head lolls
      if (p.Arm_L) p.Arm_L.rotation.x -= 0.9 + Math.sin(this.time * 2.1) * 0.1;
      if (p.Arm_R) p.Arm_R.rotation.x -= 0.8 + Math.sin(this.time * 2.4) * 0.1;
      if (p.Head) p.Head.rotation.z += Math.sin(this.time * 1.3) * 0.15;
    }
    if (this.style === 'brute' && p.Torso) {
      p.Torso.rotation.x -= 0.08;
    }

    // a held pose under any action: the rod out over the water
    if (this.pose === 'fish' && !this.action) {
      if (p.Arm_R) p.Arm_R.rotation.x += -1.0;
      if (p.Arm_L) p.Arm_L.rotation.x += -0.35;
    }
    if (this.action) this._applyAction(dt);
    if (this.death >= 0) this._applyDeath(dt);
  }

  _applyAction(dt) {
    const a = this.action;
    a.t += dt;
    const k = Math.min(1, a.t / a.duration);
    const p = this.parts;
    const impact = a.impact;
    // windup towards impact, then follow through and recover
    const raise = k < impact ? ease(k / impact) : 1 - ease((k - impact) / (1 - impact));
    const swing = k < impact ? 0 : ease(Math.min(1, (k - impact) / 0.35));

    switch (a.type) {
      case 'strike': // warden: overhand diagonal cut
        if (p.Arm_R) {
          p.Arm_R.rotation.x += -2.6 * raise - 0.9 * swing * (1 - k);
          p.Arm_R.rotation.y += 0.5 * raise;
        }
        if (p.Torso) p.Torso.rotation.y += 0.4 * raise - 0.5 * swing * (1 - k);
        break;
      case 'slam': // Shield Break: both hands overhead, then down hard
        if (p.Arm_R) p.Arm_R.rotation.x += -2.9 * raise - 0.8 * swing * (1 - k);
        if (p.Arm_L) p.Arm_L.rotation.x += -2.7 * raise - 0.8 * swing * (1 - k);
        if (p.Torso) p.Torso.rotation.x += -0.25 * raise + 0.45 * swing * (1 - k);
        break;
      case 'dodge':
        if (p.Torso) p.Torso.rotation.x += 0.55 * Math.sin(k * Math.PI);
        if (p.Leg_L) p.Leg_L.rotation.x += 0.8 * Math.sin(k * Math.PI);
        if (p.Leg_R) p.Leg_R.rotation.x -= 0.5 * Math.sin(k * Math.PI);
        this.model.position.y = -0.25 * Math.sin(k * Math.PI);
        break;
      case 'brace': // shield arm up and forward, weight back
        if (p.Arm_L) {
          p.Arm_L.rotation.x += -1.5 * Math.min(1, k * 4);
          p.Arm_L.rotation.y += 0.5 * Math.min(1, k * 4);
        }
        if (p.Torso) p.Torso.rotation.x += 0.12 * Math.min(1, k * 4);
        break;
      case 'drink':
        if (p.Arm_L) p.Arm_L.rotation.x += -2.2 * Math.sin(k * Math.PI);
        if (p.Head) p.Head.rotation.x += -0.4 * Math.sin(k * Math.PI);
        break;
      case 'claw': // ghoul: both arms rake down
        if (p.Arm_L) p.Arm_L.rotation.x += -1.6 * raise + 0.6 * swing * (1 - k);
        if (p.Arm_R) p.Arm_R.rotation.x += -1.8 * raise + 0.6 * swing * (1 - k);
        if (p.Torso) p.Torso.rotation.x += -0.3 * raise + 0.4 * swing * (1 - k);
        break;
      case 'bite': // hound: a lunge with the head low
        if (p.Torso) p.Torso.rotation.x += 0.25 * raise - 0.15 * swing * (1 - k);
        if (p.Head) p.Head.rotation.x += -0.5 * raise + 0.7 * swing * (1 - k);
        if (p.Arm_L) p.Arm_L.rotation.x += -0.6 * raise;
        if (p.Arm_R) p.Arm_R.rotation.x += -0.6 * raise;
        this.model.position.z = 0.25 * swing * (1 - k);
        break;
      case 'shoot': // archer: bow arm up and out, the other draws to the ear
        if (p.Arm_L) p.Arm_L.rotation.x += -1.55 * Math.min(1, k / Math.max(0.01, impact) * 1.6) * (k < impact ? 1 : 1 - ease((k - impact) / (1 - impact)));
        if (p.Arm_R) {
          p.Arm_R.rotation.x += -1.4 * raise;
          p.Arm_R.rotation.z += 0.5 * raise;
        }
        if (p.Torso) p.Torso.rotation.y += 0.35 * raise;
        break;
      case 'castLine': // fishing: rod back over the shoulder, then flicked out
        if (p.Arm_R) p.Arm_R.rotation.x += -1.0 - 1.7 * raise;
        if (p.Arm_L) p.Arm_L.rotation.x += -0.35;
        if (p.Torso) p.Torso.rotation.x += -0.12 * raise + 0.1 * swing * (1 - k);
        break;
      case 'cast': // seer: staff and free hand raised, then thrust down
        if (p.Arm_R) p.Arm_R.rotation.x += -2.2 * raise + 0.6 * swing * (1 - k);
        if (p.Arm_L) p.Arm_L.rotation.x += -1.8 * raise;
        if (p.Head) p.Head.rotation.x += -0.3 * raise;
        break;
      case 'cleave': // brute: wide overhead chop
        if (p.Arm_R) p.Arm_R.rotation.x += -2.8 * raise;
        if (p.Arm_L) p.Arm_L.rotation.x += -1.2 * raise;
        if (p.Torso) p.Torso.rotation.x += -0.3 * raise + 0.5 * swing * (1 - k);
        break;
      default:
        break;
    }
    if (k >= 1) {
      this.action = null;
      if (a.type === 'dodge') this.model.position.y = 0;
      if (a.type === 'bite') this.model.position.z = 0;
    }
  }

  _applyDeath(dt) {
    this.death += dt;
    const k = Math.min(1, this.death / 0.7);
    // hounds roll onto their side; everything else topples backwards
    if (this.style === 'hound') this.model.rotation.z = ease(k) * (Math.PI / 2) * 0.9;
    else this.model.rotation.x = -ease(k) * (Math.PI / 2) * 0.95;
    if (this.death > 2.5) this.model.position.y = -Math.min(1.2, (this.death - 2.5) * 0.4);
    const p = this.parts;
    if (p.Arm_L) p.Arm_L.rotation.x += -1.2 * k;
    if (p.Arm_R) p.Arm_R.rotation.x += -1.0 * k;
  }

  // Tint every mesh briefly (hit feedback). Requires per-instance materials.
  static isolateMaterials(model) {
    const cache = new Map();
    model.traverse((o) => {
      if (o.isMesh && o.material && o.material.isMeshLambertMaterial) {
        if (!cache.has(o.material)) cache.set(o.material, o.material.clone());
        o.material = cache.get(o.material);
      }
    });
    return [...cache.values()];
  }
}

export function setEmissive(materials, color, amount) {
  for (const m of materials) {
    m.emissive.setRGB(color.r * amount, color.g * amount, color.b * amount);
  }
}

export const FLASH_RED = new THREE.Color(0.9, 0.25, 0.15);
export const FLASH_WHITE = new THREE.Color(1, 0.9, 0.75);
