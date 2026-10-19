// Keyboard and mouse state. Gameplay reads held keys each frame and consumes
// one-shot presses, so a press is never processed twice.

const GAME_KEYS = new Set([
  'KeyW', 'KeyA', 'KeyS', 'KeyD', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'Space', 'ShiftLeft', 'ShiftRight',
  'KeyQ', 'KeyE', 'KeyI', 'KeyK', 'KeyB', 'KeyC', 'KeyP', 'Tab', 'Escape', 'Enter',
  'Digit1', 'Digit2', 'Digit3', 'Digit4', 'Digit5', 'KeyL',
]);

export class Input {
  constructor(canvas) {
    this.held = new Set();
    this.pressed = new Set();
    this.mouse = { x: 0, y: 0, ndcX: 0, ndcY: 0, clicked: false, rightClicked: false };
    this.canvas = canvas;

    this.capture = null; // set while Settings waits for a key to bind
    this.isBound = () => false; // key bindings say which other keys the game uses
    window.addEventListener('keydown', (e) => {
      if (this.capture) {
        e.preventDefault();
        if (!e.repeat) this.capture(e);
        return;
      }
      // typing in a text field (the character name) is not a game key
      if (e.target instanceof HTMLInputElement) return;
      // with Shift held a key is its Shift binding if it has one (Shift-1:
      // utility slot 1), else the key itself (Shift+W still walks)
      const shifted = e.shiftKey && !e.code.startsWith('Shift') && this.isBound('Shift+' + e.code) ? 'Shift+' + e.code : null;
      if (GAME_KEYS.has(e.code) || shifted || this.isBound(e.code)) e.preventDefault();
      if (!e.repeat) this.pressed.add(shifted || e.code);
      this.held.add(e.code);
    });
    window.addEventListener('keyup', (e) => {
      this.held.delete(e.code);
    });
    window.addEventListener('blur', () => this.held.clear());
    window.addEventListener('mousemove', (e) => this._mouse(e));
    canvas.addEventListener('mousedown', (e) => {
      this._mouse(e);
      if (e.button === 0) this.mouse.clicked = true;
      if (e.button === 2) this.mouse.rightClicked = true;
    });
    canvas.addEventListener('contextmenu', (e) => e.preventDefault());
    // the wheel zooms the camera (notches, + is out)
    this.wheel = 0;
    canvas.addEventListener('wheel', (e) => {
      e.preventDefault();
      this.wheel += Math.sign(e.deltaY);
    }, { passive: false });
  }

  _mouse(e) {
    const r = this.canvas.getBoundingClientRect();
    this.mouse.x = e.clientX;
    this.mouse.y = e.clientY;
    this.mouse.onCanvas = e.target === this.canvas; // not over a window or button
    this.mouse.ndcX = ((e.clientX - r.left) / r.width) * 2 - 1;
    this.mouse.ndcY = -((e.clientY - r.top) / r.height) * 2 + 1;
  }

  isHeld(code) {
    return this.held.has(code);
  }

  consume(code) {
    if (this.pressed.has(code)) {
      this.pressed.delete(code);
      return true;
    }
    return false;
  }

  consumeWheel() {
    const w = this.wheel;
    this.wheel = 0;
    return w;
  }

  consumeClick() {
    const c = this.mouse.clicked;
    this.mouse.clicked = false;
    return c;
  }

  consumeRightClick() {
    const c = this.mouse.rightClicked;
    this.mouse.rightClicked = false;
    return c;
  }

  // Call at the end of every frame so stale presses don't fire later.
  endFrame() {
    this.pressed.clear();
    this.mouse.clicked = false;
    this.mouse.rightClicked = false;
  }

  // Movement axis in world space: W is north (-z), D is east (+x); the
  // arrow keys move too.
  moveAxis() {
    let x = 0;
    let z = 0;
    if (this.isHeld('KeyW') || this.isHeld('ArrowUp')) z -= 1;
    if (this.isHeld('KeyS') || this.isHeld('ArrowDown')) z += 1;
    if (this.isHeld('KeyA') || this.isHeld('ArrowLeft')) x -= 1;
    if (this.isHeld('KeyD') || this.isHeld('ArrowRight')) x += 1;
    const len = Math.hypot(x, z);
    if (len > 0) {
      x /= len; // diagonal input is normalised
      z /= len;
    }
    return { x, z };
  }
}
