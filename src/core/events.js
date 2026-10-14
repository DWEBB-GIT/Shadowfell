// Minimal publish/subscribe bus. Systems announce what happened; the HUD and
// audio listen. Nothing listening is ever required for gameplay to work.

export class Events {
  constructor() {
    this.handlers = new Map();
  }

  on(type, fn) {
    if (!this.handlers.has(type)) this.handlers.set(type, []);
    this.handlers.get(type).push(fn);
    return () => this.off(type, fn);
  }

  off(type, fn) {
    const list = this.handlers.get(type);
    if (list) this.handlers.set(type, list.filter((f) => f !== fn));
  }

  emit(type, payload) {
    const list = this.handlers.get(type);
    if (!list) return;
    for (const fn of list) {
      try {
        fn(payload);
      } catch (err) {
        console.error(`Handler for "${type}" failed`, err);
      }
    }
  }
}
