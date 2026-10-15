import * as THREE from 'three';
import { ITEMS } from '../data/items.js';

// Inventory icons are rendered from the same Blender models used in the
// world, once at start-up, so an item always looks like what you dropped.
// Ability icons are small painted glyphs.

export function renderItemIcons(assets, size = 64) {
  const icons = {};
  let renderer;
  try {
    const canvas = document.createElement('canvas');
    renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true, preserveDrawingBuffer: true });
  } catch {
    return icons; // the HUD falls back to lettered tiles
  }
  renderer.setSize(size, size, false);
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  const scene = new THREE.Scene();
  scene.add(new THREE.HemisphereLight(0xf0e8d8, 0x504030, 3.4));
  const key = new THREE.DirectionalLight(0xfff0d8, 3.0);
  key.position.set(2, 3, 4);
  scene.add(key);
  const camera = new THREE.PerspectiveCamera(30, 1, 0.01, 50);

  const models = new Set(Object.values(ITEMS).map((i) => i.model));
  for (const name of models) {
    const obj = assets.instance(name);
    // long items (swords) are shown diagonally, the classic RPG way
    if (['worn_sword', 'watchmans_edge', 'rusted_falchion', 'blackwood_cleaver', 'witchbane'].includes(name)) obj.rotation.set(0, 0, -Math.PI / 4);
    else if (name === 'kite_shield' || name === 'iron_shield') obj.rotation.set(0.15, 0.35, 0);
    else obj.rotation.set(0.5, -0.6, 0);
    scene.add(obj);
    const box = new THREE.Box3().setFromObject(obj);
    const centre = box.getCenter(new THREE.Vector3());
    // frame the model's largest side, so flat and long items both fill the tile
    const size = box.getSize(new THREE.Vector3());
    const radius = Math.max(size.x, size.y, size.z) / 2;
    const dist = (radius / Math.tan((camera.fov * Math.PI) / 360)) * 0.78 + size.z / 2;
    camera.position.set(centre.x, centre.y, centre.z + dist);
    camera.lookAt(centre);
    renderer.render(scene, camera);
    icons[name] = renderer.domElement.toDataURL();
    scene.remove(obj);
  }
  renderer.dispose();
  return icons;
}

function glyph(draw, size = 64) {
  const c = document.createElement('canvas');
  c.width = c.height = size;
  const g = c.getContext('2d');
  const grad = g.createRadialGradient(size / 2, size / 2, 4, size / 2, size / 2, size * 0.7);
  grad.addColorStop(0, '#3a2f22');
  grad.addColorStop(1, '#100c09');
  g.fillStyle = grad;
  g.fillRect(0, 0, size, size);
  g.lineCap = 'round';
  g.lineJoin = 'round';
  draw(g, size);
  return c.toDataURL();
}

export function abilityIcons() {
  return {
    strike: glyph((g) => {
      // a sword slash
      g.strokeStyle = '#c8c4b8';
      g.lineWidth = 5;
      g.beginPath();
      g.moveTo(14, 50);
      g.lineTo(48, 16);
      g.stroke();
      g.strokeStyle = '#8a6a3a';
      g.lineWidth = 6;
      g.beginPath();
      g.moveTo(10, 42);
      g.lineTo(22, 54);
      g.stroke();
      g.strokeStyle = 'rgba(230,200,140,0.6)';
      g.lineWidth = 2;
      g.beginPath();
      g.arc(30, 34, 24, -1.9, -0.3);
      g.stroke();
    }),
    shieldBreak: glyph((g) => {
      // a burst cracking the ground
      g.strokeStyle = '#e0b060';
      g.lineWidth = 3;
      for (let i = 0; i < 8; i++) {
        const a = (i / 8) * Math.PI * 2;
        g.beginPath();
        g.moveTo(32 + Math.cos(a) * 9, 34 + Math.sin(a) * 9);
        g.lineTo(32 + Math.cos(a) * 24, 34 + Math.sin(a) * 24);
        g.stroke();
      }
      g.fillStyle = '#f2d9a0';
      g.beginPath();
      g.arc(32, 34, 7, 0, Math.PI * 2);
      g.fill();
    }),
    lunge: glyph((g) => {
      // a forward charge
      g.strokeStyle = '#c8c4b8';
      g.lineWidth = 4;
      g.beginPath();
      g.moveTo(12, 32);
      g.lineTo(50, 32);
      g.lineTo(40, 22);
      g.moveTo(50, 32);
      g.lineTo(40, 42);
      g.stroke();
      g.strokeStyle = 'rgba(200,170,110,0.6)';
      g.lineWidth = 2;
      for (const y of [22, 42]) {
        g.beginPath();
        g.moveTo(10, y);
        g.lineTo(28, y);
        g.stroke();
      }
    }),
    brace: glyph((g) => {
      // a kite shield
      g.fillStyle = '#4f6a8a';
      g.strokeStyle = '#c8d4e0';
      g.lineWidth = 3;
      g.beginPath();
      g.moveTo(32, 10);
      g.lineTo(50, 18);
      g.quadraticCurveTo(50, 42, 32, 56);
      g.quadraticCurveTo(14, 42, 14, 18);
      g.closePath();
      g.fill();
      g.stroke();
      g.strokeStyle = '#e0c070';
      g.beginPath();
      g.moveTo(32, 16);
      g.lineTo(32, 48);
      g.moveTo(20, 28);
      g.lineTo(44, 28);
      g.stroke();
    }),
    hallowedBolt: glyph((g) => {
      // a mote of gold fire with its trail
      g.strokeStyle = 'rgba(255,210,120,0.55)';
      g.lineWidth = 6;
      g.beginPath();
      g.moveTo(10, 54);
      g.lineTo(36, 28);
      g.stroke();
      const r = g.createRadialGradient(40, 24, 2, 40, 24, 16);
      r.addColorStop(0, '#fff6d0');
      r.addColorStop(0.5, '#ffc850');
      r.addColorStop(1, 'rgba(255,160,40,0)');
      g.fillStyle = r;
      g.beginPath();
      g.arc(40, 24, 16, 0, Math.PI * 2);
      g.fill();
    }),
    rend: glyph((g) => {
      // three claw tears and drops of blood
      g.strokeStyle = '#c03a2a';
      g.lineWidth = 4;
      for (const x of [18, 30, 42]) {
        g.beginPath();
        g.moveTo(x, 12);
        g.quadraticCurveTo(x - 6, 30, x - 2, 46);
        g.stroke();
      }
      g.fillStyle = '#8a1a14';
      for (const [x, y] of [[16, 54], [28, 56], [40, 53]]) {
        g.beginPath();
        g.arc(x, y, 3, 0, Math.PI * 2);
        g.fill();
      }
    }),
    smite: glyph((g) => {
      // a star of light
      g.fillStyle = '#ffe9a8';
      g.beginPath();
      for (let i = 0; i < 16; i++) {
        const a = (i / 16) * Math.PI * 2 - Math.PI / 2;
        const r = i % 2 ? 7 : i % 4 ? 18 : 26;
        g.lineTo(32 + Math.cos(a) * r, 32 + Math.sin(a) * r);
      }
      g.closePath();
      g.fill();
    }),
    hallowedGround: glyph((g) => {
      // a glowing ring on the ground with a rune inside
      g.strokeStyle = '#ffd070';
      g.lineWidth = 4;
      g.beginPath();
      g.ellipse(32, 38, 24, 12, 0, 0, Math.PI * 2);
      g.stroke();
      g.strokeStyle = 'rgba(255,220,140,0.7)';
      g.lineWidth = 2;
      for (const x of [20, 32, 44]) {
        g.beginPath();
        g.moveTo(x, 36);
        g.lineTo(x, 14 + Math.abs(x - 32) * 0.5);
        g.stroke();
      }
    }),
    cleave: glyph((g) => {
      // a broad arc of a swing
      g.strokeStyle = '#d8d0c0';
      g.lineWidth = 6;
      g.beginPath();
      g.arc(32, 46, 26, -2.6, -0.55);
      g.stroke();
      g.strokeStyle = 'rgba(230,180,110,0.6)';
      g.lineWidth = 2;
      g.beginPath();
      g.arc(32, 46, 18, -2.4, -0.75);
      g.stroke();
      g.fillStyle = '#8a6a3a';
      g.fillRect(28, 44, 8, 14);
    }),
    battleCry: glyph((g) => {
      // sound waves from a shout
      g.strokeStyle = '#ff9a5a';
      g.lineWidth = 3;
      for (const r of [8, 16, 24]) {
        g.beginPath();
        g.arc(14, 32, r, -0.8, 0.8);
        g.stroke();
      }
      g.fillStyle = '#e0c070';
      g.beginPath();
      g.moveTo(8, 26);
      g.lineTo(16, 32);
      g.lineTo(8, 38);
      g.fill();
    }),
  };
}
