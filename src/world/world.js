import * as THREE from 'three';
import { buildTerrain, heightAt, distanceToRoad, distanceToMainRoad, seededRandom, blackwoodness } from './terrain.js';
import { BOUNDS, regionById, PROPS, CLEARINGS, LIGHTS, WITCHLIGHTS, BUILDINGS, PADS } from './layout.js';
import { SIGNPOSTS, signpostLines } from './signposts.js';

const DEG = Math.PI / 180;

// Builds The Fallen Road: terrain, hand-placed props, scattered woodland,
// ground cover and warm light sources. Registers obstacles with collision and
// examine points with the interaction system.

export class World {
  constructor(game) {
    this.game = game;
    this.group = new THREE.Group();
    this.group.name = 'World';
    this.flickerLights = [];
    this.flames = [];
    this.mist = [];
    this.examinePoints = [];
  }

  build() {
    const { assets, collision, textures } = this.game;
    this.group.add(buildTerrain(textures));

    for (const p of PROPS) {
      const obj = assets.instance(p.model);
      const [x, z] = p.position;
      obj.position.set(x, heightAt(x, z), z);
      obj.rotation.y = (p.rotation || 0) * DEG;
      if (p.tilt) obj.rotation.z = -p.tilt * DEG;
      if (p.scale) obj.scale.setScalar(p.scale);
      this.group.add(obj);
      this._addCollider(p, x, z);
      if (p.examine) {
        const off = p.examineOffset || [0, 0];
        const r = (p.rotation || 0) * DEG;
        const ex = x + off[0] * Math.cos(r) + off[1] * Math.sin(r);
        const ez = z - off[0] * Math.sin(r) + off[1] * Math.cos(r);
        this.examinePoints.push({ id: p.examine, x: ex, z: ez });
      }
    }

    this._buildBuildings();
    this._buildSignposts();
    this._scatterWoodland();
    this._scatterGroundCover();
    this._addLights();
    this._addMist();
    return this;
  }

  _addCollider(p, x, z) {
    const { collision } = this.game;
    if (!p.collider) return;
    const s = p.scale || 1;
    if (typeof p.collider === 'number') {
      collision.add(x, z, p.collider * s);
      return;
    }
    if (p.collider.box) {
      // a closed box (a cottage): its four walls
      const [w, d] = p.collider.box.map((v) => v / 2);
      this._wallColliders(x, z, (p.rotation || 0) * DEG, [[-w, -d, w, -d], [w, -d, w, d], [-w, d, w, d], [-w, -d, -w, d]]);
      return;
    }
    // compound collider: offsets in the prop's local space
    const r = (p.rotation || 0) * DEG;
    const cos = Math.cos(r);
    const sin = Math.sin(r);
    for (const [ox, oz, cr] of p.collider) {
      collision.add(x + (ox * cos + oz * sin) * s, z + (-ox * sin + oz * cos) * s, cr * s);
    }
  }

  // walls as rows of small circles, from [x1, z1, x2, z2] segments in the
  // object's own space (rotated by `r` radians)
  _wallColliders(x, z, r, segments, radius = 0.28) {
    const cos = Math.cos(r);
    const sin = Math.sin(r);
    for (const [x1, z1, x2, z2] of segments) {
      const len = Math.hypot(x2 - x1, z2 - z1);
      const n = Math.max(1, Math.ceil(len / 0.35));
      for (let i = 0; i <= n; i++) {
        const ox = x1 + ((x2 - x1) * i) / n;
        const oz = z1 + ((z2 - z1) * i) / n;
        this.game.collision.add(x + ox * cos + oz * sin, z - ox * sin + oz * cos, radius);
      }
    }
  }

  // Buildings you can walk into: the shell (floor, back walls, fittings), the
  // wall facing the camera and the roof, which fade away while you are inside
  // so the fixed camera can see in (see updateIndoors).
  // a post, and an arm turned towards each place it names
  _buildSignposts() {
    const { assets, collision } = this.game;
    for (const sp of SIGNPOSTS) {
      const [x, z] = sp.position;
      const y = heightAt(x, z);
      const post = assets.instance('signpost');
      post.position.set(x, y, z);
      this.group.add(post);
      signpostLines(sp).forEach((l, i) => {
        const arm = assets.instance('sign_arm');
        arm.position.set(x, y + 2.05 - i * 0.27, z);
        arm.rotation.y = l.angle;
        this.group.add(arm);
      });
      collision.add(x, z, 0.3);
    }
  }

  _buildBuildings() {
    const { assets } = this.game;
    this.buildings = [];
    for (const b of BUILDINGS) {
      const [x, z] = b.position;
      const group = new THREE.Group();
      group.name = b.id;
      group.position.set(x, heightAt(x, z) - 0.1, z);
      group.add(assets.instance(b.shell));
      const fade = [b.front, b.roof].map((m) => {
        const obj = assets.instance(m);
        const mats = [];
        obj.traverse((o) => {
          if (!o.isMesh) return;
          o.material = o.material.clone();
          o.material.transparent = true;
          mats.push(o.material);
        });
        group.add(obj);
        return { obj, mats };
      });
      if (b.light) {
        const light = new THREE.PointLight(0xffa050, 4, 10, 1.4);
        light.position.set(b.light[0], 1.1, b.light[1]);
        group.add(light);
        this.flickerLights.push({ light, base: 4, seed: x });
      }
      this.group.add(group);
      this._wallColliders(x, z, 0, b.walls);
      for (const [ox, oz, r] of b.furniture || []) this.game.collision.add(x + ox, z + oz, r);
      const [w, d] = b.size;
      this.buildings.push({ def: b, fade, inside: 0, minX: x - w / 2, maxX: x + w / 2, minZ: z - d / 2, maxZ: z + d / 2 });
    }
    this.indoors = null;
  }

  // Which building (if any) the Warrior stands in; fade its front wall and
  // roof towards hidden while inside, back again outside.
  updateIndoors(dt, pos) {
    this.indoors = null;
    for (const b of this.buildings || []) {
      const inside = pos.x > b.minX + 0.1 && pos.x < b.maxX - 0.1 && pos.z > b.minZ + 0.1 && pos.z < b.maxZ - 0.1;
      if (inside) this.indoors = b;
      const k = 1 - Math.exp(-8 * dt);
      b.inside += ((inside ? 1 : 0) - b.inside) * (dt > 0 ? k : 1);
      for (const f of b.fade) {
        const o = 1 - b.inside * (f === b.fade[1] ? 1 : 0.85);
        for (const m of f.mats) {
          m.opacity = o;
          m.depthWrite = o > 0.95;
        }
        f.obj.visible = o > 0.02;
      }
    }
    return this.indoors;
  }

  // 0 outside, rising to 1 inside a building (the camera closes in)
  get indoorBlend() {
    return Math.max(0, ...(this.buildings || []).map((b) => b.inside));
  }

  // Not on a building (with room to walk round it), a levelled pad, or a
  // prop that has a box collider (the cottages).
  _clearOfTown(x, z) {
    for (const b of BUILDINGS) {
      const [w, d] = b.size;
      if (Math.abs(x - b.position[0]) < w / 2 + 3 && Math.abs(z - b.position[1]) < d / 2 + 3) return false;
    }
    for (const [px, pz, r] of PADS) if (Math.hypot(x - px, z - pz) < r + 2) return false;
    for (const p of PROPS) {
      const box = p.collider?.box;
      if (box && Math.abs(x - p.position[0]) < box[0] / 2 + 3 && Math.abs(z - p.position[1]) < box[1] / 2 + 3) return false;
    }
    return true;
  }

  _clear(x, z, margin = 0) {
    for (const [cx, cz, r] of CLEARINGS) {
      if (Math.hypot(x - cx, z - cz) < r + margin) return false;
    }
    return true;
  }

  _scatterWoodland() {
    const { collision } = this.game;
    // The Fallen Road's woodland, laid out exactly as it always has been
    // (same seed, same bounds), less whatever now stands on the forest
    // track or beyond the old northern edge, where the Blackwood begins.
    const road = regionById('fallen_road').bounds;
    const rand = seededRandom(1999);
    const pines = [];
    const dead = [];
    const pad = 22;
    for (let i = 0; i < 2600 && pines.length < 520; i++) {
      const x = road.minX - pad + rand() * (road.maxX - road.minX + pad * 2);
      const z = road.minZ - pad + rand() * (road.maxZ - road.minZ + pad * 2);
      const inside = x >= road.minX && x <= road.maxX && z >= road.minZ && z <= road.maxZ;
      const edge = Math.min(x - road.minX, road.maxX - x, z - road.minZ, road.maxZ - z);
      const toRoad = distanceToMainRoad(x, z);
      if (toRoad < 4.2) continue;
      if (!this._clear(x, z)) continue;
      // sparse inside the play space, dense at and beyond its edge
      const density = !inside ? 0.85 : edge < 5 ? 0.6 : toRoad < 9 ? 0.08 : 0.2;
      if (rand() > density) continue;
      if (pines.some((p) => Math.hypot(p.x - x, p.z - z) < (inside ? 3.2 : 2.1))) continue;
      const s = 0.8 + rand() * 0.7;
      const entry = { x, z, s, r: rand() * Math.PI * 2, collide: inside || edge > -3 };
      if (inside && rand() < 0.12) dead.push(entry);
      else pines.push(entry);
    }
    // (south of z 49 is Brackenford now, which plants its own)
    const keep = (t) => t.z > -47 && t.z < 49 && distanceToRoad(t.x, t.z) >= 3.4;
    const roadPines = pines.filter(keep);
    const roadDead = dead.filter(keep);
    for (const t of [...roadPines, ...roadDead]) if (t.collide) collision.add(t.x, t.z, 0.45 * t.s);

    // The Blackwood: black pines, close-set, with the track the only clear way.
    const bw = regionById('blackwood').bounds;
    const rb = seededRandom(2024);
    const black = [];
    const bwDead = [];
    const all = () => black.concat(bwDead);
    for (let i = 0; i < 6000 && black.length < 900; i++) {
      const x = bw.minX - pad + rb() * (bw.maxX - bw.minX + pad * 2);
      const z = bw.minZ - pad + rb() * (-47 - bw.minZ + pad);
      const inside = x >= bw.minX && x <= bw.maxX && z >= bw.minZ;
      const edge = Math.min(x - bw.minX, bw.maxX - x, z - bw.minZ);
      const toPath = distanceToRoad(x, z);
      if (toPath < 3.4 || !this._clear(x, z)) continue;
      const density = !inside ? 0.85 : edge < 5 ? 0.7 : toPath < 7 ? 0.3 : 0.5;
      if (rb() > density) continue;
      if (all().some((p) => Math.hypot(p.x - x, p.z - z) < (inside ? 2.5 : 2.0))) continue;
      const s = 0.85 + rb() * 0.6;
      const entry = { x, z, s, r: rb() * Math.PI * 2 };
      if (inside && rb() < 0.1) bwDead.push(entry);
      else black.push(entry);
      if (inside || edge > -3) collision.add(x, z, 0.45 * s);
    }
    // Brackenford: a few pines about the town and a wood at its edges, never
    // on the road, a pad (the ground levelled for a building) or a building
    const town = regionById('brackenford').bounds;
    const rt = seededRandom(1213);
    const townPines = [];
    for (let i = 0; i < 2400 && townPines.length < 160; i++) {
      const x = town.minX - pad + rt() * (town.maxX - town.minX + pad * 2);
      const z = town.minZ + rt() * (town.maxZ - town.minZ + pad);
      const inside = x >= town.minX && x <= town.maxX && z <= town.maxZ;
      const edge = Math.min(x - town.minX, town.maxX - x, town.maxZ - z);
      if (distanceToMainRoad(x, z) < 4.2 || !this._clear(x, z) || !this._clearOfTown(x, z)) continue;
      const density = !inside ? 0.85 : edge < 5 ? 0.6 : 0.06;
      if (rt() > density) continue;
      if (townPines.some((p) => Math.hypot(p.x - x, p.z - z) < (inside ? 3.2 : 2.1))) continue;
      const s = 0.8 + rt() * 0.7;
      townPines.push({ x, z, s, r: rt() * Math.PI * 2 });
      if (inside || edge > -3) collision.add(x, z, 0.45 * s);
    }
    // for the minimap
    this.mapTrees = [...roadPines, ...townPines, ...roadDead, ...bwDead, ...black].map((t) => [t.x, t.z]);
    this._instanced('pine', roadPines.concat(townPines));
    this._instanced('dead_tree', roadDead.concat(bwDead));
    this._instanced('black_pine', black);
  }

  _instanced(model, list) {
    const src = this.game.assets.geometryOf(model);
    if (!src || list.length === 0) return;
    const mesh = new THREE.InstancedMesh(src.geometry, this._cutawayMaterial(), list.length);
    const m = new THREE.Matrix4();
    const q = new THREE.Quaternion();
    const up = new THREE.Vector3(0, 1, 0);
    list.forEach((t, i) => {
      q.setFromAxisAngle(up, t.r);
      m.compose(new THREE.Vector3(t.x, heightAt(t.x, t.z) - 0.1, t.z), q, new THREE.Vector3(t.s, t.s, t.s));
      mesh.setMatrixAt(i, m);
    });
    mesh.castShadow = true;
    mesh.receiveShadow = true;
    mesh.name = 'Woodland_' + model;
    this.group.add(mesh);
  }

  // Trees between the camera and the player are dissolved with a dither
  // pattern so the character is never hidden behind foliage.
  _cutawayMaterial() {
    if (this.cutaway) return this.cutaway;
    const mat = new THREE.MeshLambertMaterial({ vertexColors: true, flatShading: true });
    this.cutawayUniforms = {
      uCamPos: { value: new THREE.Vector3() },
      uFocus: { value: new THREE.Vector3() },
    };
    mat.onBeforeCompile = (shader) => {
      Object.assign(shader.uniforms, this.cutawayUniforms);
      shader.vertexShader = shader.vertexShader
        .replace('#include <common>', '#include <common>\nvarying vec3 vCutWorld;')
        .replace('#include <worldpos_vertex>', '#include <worldpos_vertex>\nvCutWorld = (modelMatrix * instanceMatrix * vec4(transformed, 1.0)).xyz;');
      shader.fragmentShader = shader.fragmentShader
        .replace(
          '#include <common>',
          `#include <common>
          varying vec3 vCutWorld;
          uniform vec3 uCamPos;
          uniform vec3 uFocus;`,
        )
        .replace(
          '#include <clipping_planes_fragment>',
          `#include <clipping_planes_fragment>
          {
            vec3 seg = uFocus - uCamPos;
            float t = clamp(dot(vCutWorld - uCamPos, seg) / dot(seg, seg), 0.0, 1.0);
            float d = length(vCutWorld - (uCamPos + seg * t));
            float fade = smoothstep(2.2, 4.2, d) + step(0.93, t);
            float dither = fract(sin(dot(floor(gl_FragCoord.xy), vec2(12.9898, 78.233))) * 43758.5453);
            if (fade < dither) discard;
          }`,
        );
    };
    mat.customProgramCacheKey = () => 'cutaway';
    this.cutaway = mat;
    return mat;
  }

  setCutaway(cameraPos, focus) {
    if (!this.cutawayUniforms) return;
    this.cutawayUniforms.uCamPos.value.copy(cameraPos);
    this.cutawayUniforms.uFocus.value.copy(focus);
  }

  _scatterGroundCover() {
    // low-poly grass tufts: three crossed blades per tuft
    const blade = new THREE.BufferGeometry();
    const v = [];
    for (let k = 0; k < 3; k++) {
      const a = (k / 3) * Math.PI;
      const cx = Math.cos(a) * 0.18;
      const cz = Math.sin(a) * 0.18;
      v.push(-cx, 0, -cz, cx, 0, cz, cx * 0.2 + 0.05, 0.45, cz * 0.2);
    }
    blade.setAttribute('position', new THREE.Float32BufferAttribute(v, 3));
    blade.computeVertexNormals();
    const mat = new THREE.MeshLambertMaterial({ color: 0x4a5a32, side: THREE.DoubleSide });
    const rand = seededRandom(77);
    const count = Math.round(3600 * ((BOUNDS.maxZ - BOUNDS.minZ + 12) / 184)); // the same density as the first map
    const mesh = new THREE.InstancedMesh(blade, mat, count);
    const m = new THREE.Matrix4();
    const q = new THREE.Quaternion();
    const col = new THREE.Color();
    let n = 0;
    for (let i = 0; i < count * 3 && n < count; i++) {
      const x = BOUNDS.minX - 6 + rand() * (BOUNDS.maxX - BOUNDS.minX + 12);
      const z = BOUNDS.minZ - 6 + rand() * (BOUNDS.maxZ - BOUNDS.minZ + 12);
      const road = distanceToRoad(x, z);
      if (road < 1.6 && rand() > 0.15) continue; // a few tufts break through the road
      if ((this.buildings || []).some((b) => x > b.minX - 0.3 && x < b.maxX + 0.3 && z > b.minZ - 0.3 && z < b.maxZ + 0.3)) continue; // not through a floor
      q.setFromAxisAngle(new THREE.Vector3(0, 1, 0), rand() * Math.PI);
      const s = 0.6 + rand() * 0.9;
      m.compose(new THREE.Vector3(x, heightAt(x, z) - 0.02, z), q, new THREE.Vector3(s, s * (0.7 + rand() * 0.8), s));
      mesh.setMatrixAt(n, m);
      col.setHSL(0.2 + rand() * 0.06, 0.25 + rand() * 0.15, (0.17 + rand() * 0.1) * (1 - 0.45 * blackwoodness(z)));
      mesh.setColorAt(n, col);
      n++;
    }
    mesh.count = n;
    mesh.receiveShadow = true;
    mesh.name = 'GroundCover';
    this.group.add(mesh);
  }

  _addLights() {
    for (const l of LIGHTS) {
      const [x, z] = l.position;
      let light = null;
      if (!l.noLight) {
        light = new THREE.PointLight(l.color || 0xffa860, l.intensity, l.distance, 1.6);
        light.position.set(x, heightAt(x, z) + l.height, z);
        this.group.add(light);
      }
      if (l.lantern) {
        // a fallen lantern, still guttering
        const lantern = new THREE.Group();
        const frame = new THREE.Mesh(new THREE.BoxGeometry(0.16, 0.22, 0.16), new THREE.MeshLambertMaterial({ color: 0x1c1a18 }));
        const flame = new THREE.Mesh(new THREE.SphereGeometry(0.04, 5, 4), new THREE.MeshBasicMaterial({ color: 0xffb060 }));
        lantern.add(frame, flame);
        lantern.position.set(x, heightAt(x, z) + 0.1, z);
        lantern.rotation.z = 1.2;
        this.group.add(lantern);
      }
      if (l.brazier) {
        // an iron bowl on a post, with a flame that ignores the fog a little
        const brazier = new THREE.Group();
        const iron = new THREE.MeshLambertMaterial({ color: 0x24201c });
        const post = new THREE.Mesh(new THREE.CylinderGeometry(0.07, 0.1, 1.0, 6), iron);
        post.position.y = 0.5;
        const bowl = new THREE.Mesh(new THREE.CylinderGeometry(0.34, 0.18, 0.22, 8), iron);
        bowl.position.y = 1.08;
        const flame = new THREE.Mesh(new THREE.ConeGeometry(0.22, 0.5, 6), new THREE.MeshBasicMaterial({ color: 0xffa040, fog: false }));
        flame.position.y = 1.42;
        const glow = new THREE.Sprite(new THREE.SpriteMaterial({ map: this.game.textures.glint, color: 0xffa050, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, opacity: 0.8, fog: false }));
        glow.scale.setScalar(2.2);
        glow.position.y = 1.45;
        brazier.add(post, bowl, flame, glow);
        brazier.position.set(x, heightAt(x, z), z);
        brazier.name = 'Brazier';
        this.group.add(brazier);
        this.flames.push({ flame, glow, seed: Math.random() * 10 });
        this.game.collision.add(x, z, 0.35);
      }
      if (light && l.flicker) this.flickerLights.push({ light, base: l.intensity, seed: Math.random() * 10 });
    }
    // witchlight runes on the Blackwood's standing stones glow through the fog
    for (const [x, z, rot] of WITCHLIGHTS) {
      const r = (rot * Math.PI) / 180; // the rune is on the stone's front face
      const glow = new THREE.Sprite(new THREE.SpriteMaterial({ map: this.game.textures.glint, color: 0x80f0c0, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, opacity: 0.7, fog: false }));
      glow.scale.setScalar(1.3);
      glow.position.set(x + Math.sin(r) * 0.32, heightAt(x, z) + 1.2, z + Math.cos(r) * 0.32);
      glow.name = 'Witchlight';
      this.group.add(glow);
      this.flames.push({ flame: null, glow, seed: x * 3.1 });
    }
  }

  // Low drifting mist: a few large soft layers just above the ground. The
  // scene fog thickens them with distance, which sells the depth.
  _addMist() {
    const tex = this.game.textures.mist;
    for (let i = 0; i < 14; i++) {
      const x = -30 + ((i * 37) % 60);
      const z = 40 - i * 11.5;
      const deep = z < -52; // the Blackwood's mist lies thicker and greener
      const mat = new THREE.MeshBasicMaterial({ map: tex, color: deep ? 0x9cb8a8 : 0xb8c4c0, transparent: true, opacity: deep ? 0.28 : 0.22, depthWrite: false });
      const m = new THREE.Mesh(new THREE.PlaneGeometry(30, 30), mat);
      m.rotation.x = -Math.PI / 2;
      m.rotation.z = i * 1.3;
      m.position.set(x, heightAt(x, z) + 0.5 + (i % 3) * 0.25, z);
      m.renderOrder = 1;
      m.name = 'Mist';
      this.group.add(m);
      this.mist.push({ mesh: m, x, z, seed: i * 2.1 });
    }
  }

  update(dt, time) {
    for (const m of this.mist) {
      m.mesh.position.x = m.x + Math.sin(time * 0.05 + m.seed) * 3;
      m.mesh.position.z = m.z + Math.cos(time * 0.04 + m.seed) * 2;
      m.mesh.rotation.z += dt * 0.01;
    }
    for (const f of this.flames) {
      const t = time * 9 + f.seed;
      const k = 1 + Math.sin(t) * 0.12 + Math.sin(t * 2.3) * 0.08;
      if (f.flame) f.flame.scale.set(1, k, 1);
      f.glow.material.opacity = 0.65 + Math.sin(t * 1.7) * 0.15;
    }
    for (const f of this.flickerLights) {
      const t = time * 7 + f.seed;
      f.light.intensity = f.base * (0.82 + Math.sin(t) * 0.06 + Math.sin(t * 2.7) * 0.05 + Math.sin(t * 5.3) * 0.04);
    }
  }
}
