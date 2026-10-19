import * as THREE from 'three';

// Target-frame portraits, WoW style: a head-and-shoulders picture of each
// model, rendered once with the game's own renderer into an offscreen
// target and kept as an image.

const SIZE = 96;

export class Portraits {
  constructor(game) {
    this.game = game;
    this.cache = new Map();
    this.scene = new THREE.Scene();
    this.scene.add(new THREE.AmbientLight(0xffffff, 2.4));
    const key = new THREE.DirectionalLight(0xffe0c0, 3.2);
    key.position.set(1.5, 2, 3);
    this.scene.add(key);
    this.camera = new THREE.PerspectiveCamera(30, 1, 0.05, 50);
    this.target = new THREE.WebGLRenderTarget(SIZE, SIZE, { colorSpace: THREE.SRGBColorSpace });
    this.pixels = new Uint8Array(SIZE * SIZE * 4);
  }

  // an image URL for the model's portrait (cached), or '' if it cannot be made
  get(modelId) {
    if (this.cache.has(modelId)) return this.cache.get(modelId);
    let url = '';
    try {
      url = this._render(modelId);
    } catch (e) {
      url = '';
    }
    this.cache.set(modelId, url);
    return url;
  }

  _render(modelId) {
    const { renderer, assets } = this.game;
    const model = assets.instance(modelId);
    this.scene.add(model);
    model.updateMatrixWorld(true);
    // frame the head: the Head part if the model has one, else its top
    const box = new THREE.Box3().setFromObject(model);
    const head = model.getObjectByName('Head');
    const at = new THREE.Vector3();
    let span;
    if (head) {
      const hb = new THREE.Box3().setFromObject(head);
      hb.getCenter(at);
      span = Math.max(0.3, (hb.max.y - hb.min.y) * 1.25);
    } else {
      box.getCenter(at);
      at.y = box.max.y - (box.max.y - box.min.y) * 0.3;
      span = Math.max(box.max.x - box.min.x, box.max.z - box.min.z, 0.6) * 0.8;
    }
    const dist = span / Math.tan((this.camera.fov * Math.PI) / 360);
    this.camera.position.set(at.x + dist * 0.3, at.y + span * 0.05, at.z + dist);
    this.camera.lookAt(at.x, at.y - span * 0.2, at.z);

    const before = renderer.getRenderTarget();
    const clear = renderer.getClearAlpha();
    renderer.setClearAlpha(0);
    renderer.setRenderTarget(this.target);
    renderer.clear();
    renderer.render(this.scene, this.camera);
    renderer.readRenderTargetPixels(this.target, 0, 0, SIZE, SIZE, this.pixels);
    renderer.setRenderTarget(before);
    renderer.setClearAlpha(clear);
    this.scene.remove(model);

    // the target's rows run bottom up; a 2D canvas runs top down
    const canvas = document.createElement('canvas');
    canvas.width = canvas.height = SIZE;
    const ctx = canvas.getContext('2d');
    const img = ctx.createImageData(SIZE, SIZE);
    for (let y = 0; y < SIZE; y++) img.data.set(this.pixels.subarray((SIZE - 1 - y) * SIZE * 4, (SIZE - y) * SIZE * 4), y * SIZE * 4);
    ctx.putImageData(img, 0, 0);
    return canvas.toDataURL();
  }
}
