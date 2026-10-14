// Gamepad support through the browser Gamepad API ("standard" mapping, which
// Xbox and PlayStation pads use in Chrome and Edge on Windows).
//
// Gameplay                         Menus (bags / character open)
//   Left stick   move                D-pad / left stick  move the highlight
//   Right stick  aim                 A   pick up / put down an item
//   X  (□)       Strike              X   use or equip
//   Y  (△)       Shield Break        Y   drop on the ground
//   RB (R1)      Lunge               B   cancel / close
//   B  (○)       Brace               LB/RB  switch between windows
//   LB (L1)      Healing draught
//   RT (R2)      Strike
//   R3           Lock on / release
//   A  (✕)       Interact / loot
//   Start        Bags     View/Select  Character     D-pad down  Save

export const BUTTONS = {
  A: 0, B: 1, X: 2, Y: 3, LB: 4, RB: 5, LT: 6, RT: 7,
  VIEW: 8, START: 9, LS: 10, RS: 11, UP: 12, DOWN: 13, LEFT: 14, RIGHT: 15,
};

const DEADZONE = 0.22;

function shape(x, y) {
  const m = Math.hypot(x, y);
  if (m < DEADZONE) return { x: 0, y: 0, m: 0 };
  const k = Math.min(1, (m - DEADZONE) / (1 - DEADZONE)) / m;
  return { x: x * k, y: y * k, m: Math.min(1, m) };
}

export class Gamepad {
  constructor() {
    this.index = null;
    this.prev = [];
    this.now = [];
    this.left = { x: 0, y: 0, m: 0 };
    this.right = { x: 0, y: 0, m: 0 };
    this.active = false; // true once the pad has been used, to switch prompts
    this.repeat = {}; // menu navigation auto-repeat timers
    window.addEventListener('gamepadconnected', (e) => {
      if (this.index === null) this.index = e.gamepad.index;
    });
    window.addEventListener('gamepaddisconnected', (e) => {
      if (this.index === e.gamepad.index) this.index = null;
    });
  }

  _pad() {
    const pads = (navigator.getGamepads && navigator.getGamepads()) || [];
    if (this.index !== null && pads[this.index]) return pads[this.index];
    for (const p of pads) {
      if (p && p.connected) {
        this.index = p.index;
        return p;
      }
    }
    return null;
  }

  poll() {
    this.prev = this.now;
    const pad = this._pad();
    if (!pad) {
      this.now = [];
      this.left = this.right = { x: 0, y: 0, m: 0 };
      return;
    }
    this.now = pad.buttons.map((b) => (typeof b === 'object' ? b.pressed || b.value > 0.5 : b > 0.5));
    this.left = shape(pad.axes[0] || 0, pad.axes[1] || 0);
    this.right = shape(pad.axes[2] || 0, pad.axes[3] || 0);
    if (this.now.some(Boolean) || this.left.m > 0 || this.right.m > 0) this.active = true;
  }

  held(b) {
    return !!this.now[b];
  }

  pressed(b) {
    return !!this.now[b] && !this.prev[b];
  }

  // Menu navigation: a direction from the d-pad or left stick, repeating
  // while held. Returns 'up' | 'down' | 'left' | 'right' | null.
  navDirection(dt) {
    const dirs = {
      up: this.held(BUTTONS.UP) || this.left.y < -0.6,
      down: this.held(BUTTONS.DOWN) || this.left.y > 0.6,
      left: this.held(BUTTONS.LEFT) || this.left.x < -0.6,
      right: this.held(BUTTONS.RIGHT) || this.left.x > 0.6,
    };
    for (const [d, on] of Object.entries(dirs)) {
      if (!on) {
        delete this.repeat[d];
        continue;
      }
      if (this.repeat[d] === undefined) {
        this.repeat[d] = 0.35;
        return d;
      }
      this.repeat[d] -= dt;
      if (this.repeat[d] <= 0) {
        this.repeat[d] = 0.12;
        return d;
      }
    }
    return null;
  }
}
