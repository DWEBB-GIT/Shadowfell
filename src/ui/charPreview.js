import * as THREE from 'three';

// The character panel's figure: the player's own model, live, with whatever
// they wear and carry, as in WoW's paper doll. While the panel is open the
// model is lent to a small scene of its own once a frame, drawn from the
// front by a second renderer on the panel's canvas, and handed straight
// back, so it animates, swaps gear and fades as a ghost exactly as it does
// in the world. Drag on the figure to turn it.

export class CharPreview {
  constructor(game, canvas) {
    this.game = game;
    this.canvas = canvas;
    this.renderer = null; // made the first time the panel opens
    this.failed = false;
    this.turn = 0; // radians the viewer has turned the figure
    this.scene = new THREE.Scene();
    this.scene.add(new THREE.HemisphereLight(0xfff0dc, 0x2a2018, 2.2));
    const key = new THREE.DirectionalLight(0xffe2c0, 2.6);
    key.position.set(1.6, 2.6, 2.4);
    this.scene.add(key);
    const rim = new THREE.DirectionalLight(0x9ab0ff, 1.4);
    rim.position.set(-2, 1.8, -2.2);
    this.scene.add(rim);
    this.pivot = new THREE.Group(); // the model hangs from this while drawn
    this.scene.add(this.pivot);
    this.camera = new THREE.PerspectiveCamera(26, 1, 0.1, 30);

    let drag = null;
    canvas.addEventListener('pointerdown', (e) => {
      drag = e.clientX;
      canvas.setPointerCapture(e.pointerId);
    });
    canvas.addEventListener('pointermove', (e) => {
      if (drag === null) return;
      this.turn += (e.clientX - drag) * 0.012;
      drag = e.clientX;
    });
    const end = () => (drag = null);
    canvas.addEventListener('pointerup', end);
    canvas.addEventListener('pointercancel', end);
  }

  _init() {
    try {
      this.renderer = new THREE.WebGLRenderer({ canvas: this.canvas, alpha: true, antialias: true });
      this.renderer.outputColorSpace = THREE.SRGBColorSpace;
      this.renderer.setClearColor(0x000000, 0);
      this.renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
    } catch (e) {
      this.failed = true; // the flat silhouette stays in its place
      this.canvas.closest('.char-figure')?.classList.add('no-model');
    }
  }

  // Called after the world is drawn, every frame the panel is open.
  render() {
    if (this.failed) return;
    const w = this.canvas.clientWidth;
    const h = this.canvas.clientHeight;
    if (!w || !h) return;
    if (!this.renderer) this._init();
    if (!this.renderer) return;
    const size = this.renderer.getSize(new THREE.Vector2());
    if (size.x !== w || size.y !== h) {
      this.renderer.setSize(w, h, false);
      this.camera.aspect = w / h;
      this.camera.updateProjectionMatrix();
    }
    const model = this.game.player.model;
    const home = model.parent;
    if (!home) return;
    // from the front: undo the player's facing, then the viewer's turn
    this.pivot.rotation.y = this.turn;
    this.pivot.add(model);
    // frame the whole figure (it stands about 2 m with a helm)
    this.camera.position.set(0, 1.15, 5.1);
    this.camera.lookAt(0, 1.0, 0);
    try {
      this.renderer.render(this.scene, this.camera);
    } finally {
      home.add(model);
    }
  }
}
