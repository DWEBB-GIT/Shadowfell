import * as THREE from 'three';
import { seededRandom } from '../world/terrain.js';

// Small procedurally painted textures. Low resolution on purpose: they give
// surfaces a hand-painted grain rather than a modern, sharp look.

function canvasTexture(size, paint) {
  const canvas = document.createElement('canvas');
  canvas.width = canvas.height = size;
  const ctx = canvas.getContext('2d');
  paint(ctx, size);
  const tex = new THREE.CanvasTexture(canvas);
  tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
  tex.magFilter = THREE.NearestFilter;
  tex.minFilter = THREE.LinearMipmapLinearFilter;
  tex.colorSpace = THREE.SRGBColorSpace;
  return tex;
}

export function createTextures() {
  const rand = seededRandom(7);
  const groundDetail = canvasTexture(64, (ctx, s) => {
    ctx.fillStyle = '#d8d8d8';
    ctx.fillRect(0, 0, s, s);
    for (let i = 0; i < 900; i++) {
      const v = Math.floor(170 + rand() * 85);
      ctx.fillStyle = `rgb(${v},${v},${v})`;
      const w = 1 + Math.floor(rand() * 2);
      ctx.fillRect(Math.floor(rand() * s), Math.floor(rand() * s), w, w + Math.floor(rand() * 2));
    }
  });

  const glint = canvasTexture(32, (ctx, s) => {
    const g = ctx.createRadialGradient(s / 2, s / 2, 0, s / 2, s / 2, s / 2);
    g.addColorStop(0, 'rgba(255,236,190,1)');
    g.addColorStop(0.25, 'rgba(255,214,150,0.5)');
    g.addColorStop(1, 'rgba(255,200,120,0)');
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, s, s);
  });
  glint.magFilter = THREE.LinearFilter;

  const ring = canvasTexture(64, (ctx, s) => {
    const g = ctx.createRadialGradient(s / 2, s / 2, s * 0.28, s / 2, s / 2, s / 2);
    g.addColorStop(0, 'rgba(255,255,255,0)');
    g.addColorStop(0.7, 'rgba(255,240,210,0.9)');
    g.addColorStop(1, 'rgba(255,240,210,0)');
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, s, s);
  });
  ring.magFilter = THREE.LinearFilter;

  const blob = canvasTexture(32, (ctx, s) => {
    const g = ctx.createRadialGradient(s / 2, s / 2, 0, s / 2, s / 2, s / 2);
    g.addColorStop(0, 'rgba(0,0,0,0.55)');
    g.addColorStop(1, 'rgba(0,0,0,0)');
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, s, s);
  });
  blob.magFilter = THREE.LinearFilter;

  // soft cloudy blotches for ground mist
  const mist = canvasTexture(128, (ctx, s) => {
    ctx.clearRect(0, 0, s, s);
    for (let i = 0; i < 26; i++) {
      // keep every blotch inside the canvas so the plane has no hard edge
      const x = s * (0.32 + rand() * 0.36);
      const y = s * (0.32 + rand() * 0.36);
      const r = s * (0.1 + rand() * 0.17);
      const g = ctx.createRadialGradient(x, y, 0, x, y, r);
      g.addColorStop(0, 'rgba(255,255,255,0.22)');
      g.addColorStop(1, 'rgba(255,255,255,0)');
      ctx.fillStyle = g;
      ctx.fillRect(0, 0, s, s);
    }
  });
  mist.magFilter = THREE.LinearFilter;
  mist.wrapS = mist.wrapT = THREE.ClampToEdgeWrapping;

  return { groundDetail, glint, ring, blob, mist };
}
