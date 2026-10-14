// All sound is synthesised with the Web Audio API, so there are no audio files
// to ship. If audio is unavailable the game simply plays silently.

import { DANGER_ZONES } from '../world/layout.js';

export class AudioSystem {
  constructor(game) {
    this.game = game;
    this.ctx = null;
    this.muted = false;
    this.nextCrow = 6;
    this.nextBell = 18;
    this.nextCreak = 10;
  }

  // Must be called from a user gesture (the title screen button).
  start() {
    if (this.ctx) return;
    try {
      const Ctx = window.AudioContext || window.webkitAudioContext;
      if (!Ctx) return;
      this.ctx = new Ctx();
      this.master = this.ctx.createGain();
      this.master.gain.value = 0.7;
      this.master.connect(this.ctx.destination);
      this.noise = this._noiseBuffer();
      this._startWind();
      this._startRumble();
      this._bind();
    } catch (err) {
      console.warn('Audio unavailable; continuing without sound.', err);
      this.ctx = null;
    }
  }

  toggleMute() {
    this.muted = !this.muted;
    if (this.master) this.master.gain.setTargetAtTime(this.muted ? 0 : 0.7, this.ctx.currentTime, 0.05);
    return this.muted;
  }

  _bind() {
    const ev = this.game.events;
    ev.on('playerSwing', () => this.whoosh(0.18, 900));
    ev.on('playerMiss', () => {});
    ev.on('enemyHit', ({ kind }) => (kind === 'strike' ? this.impact() : null));
    ev.on('shieldBreak', () => this.shieldBreak());
    ev.on('playerBrace', () => this.thud(180, 0.12));
    ev.on('braceBlock', () => {
      this.impact();
      this.bell(0.12, 660);
    });
    ev.on('corpseLooted', () => this.coins());
    ev.on('enemyWindup', ({ enemy }) => this.growl(enemy.type === 'brute' ? 70 : 120, enemy.type === 'brute' ? 0.5 : 0.35));
    ev.on('playerHurt', () => this.thud(110, 0.25));
    ev.on('enemyDefeated', ({ enemy }) => this.death(enemy.type === 'brute'));
    ev.on('lootCollected', () => this.chime([660, 990], 0.12));
    ev.on('coins', () => this.coins());
    ev.on('levelUp', () => this.chime([392, 523, 659], 0.25));
    ev.on('shrineRest', () => this.bell(0.25, 440));
    ev.on('draught', () => this.chime([330, 415], 0.15));
    ev.on('playerDied', () => this.growl(55, 1.4));
    ev.on('playerLunge', () => this.whoosh(0.3, 700));
    ev.on('graveSlam', () => {
      this.thud(60, 0.6);
      this.shieldBreak();
    });
    ev.on('itemDropped', () => this.thud(220, 0.12));
  }

  _noiseBuffer() {
    const len = this.ctx.sampleRate * 2;
    const buf = this.ctx.createBuffer(1, len, this.ctx.sampleRate);
    const d = buf.getChannelData(0);
    for (let i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;
    return buf;
  }

  _noiseSource(loop = false) {
    const src = this.ctx.createBufferSource();
    src.buffer = this.noise;
    src.loop = loop;
    return src;
  }

  _env(gainNode, t, attack, peak, decay) {
    gainNode.gain.setValueAtTime(0.0001, t);
    gainNode.gain.exponentialRampToValueAtTime(peak, t + attack);
    gainNode.gain.exponentialRampToValueAtTime(0.0001, t + attack + decay);
  }

  _startWind() {
    const src = this._noiseSource(true);
    const filter = this.ctx.createBiquadFilter();
    filter.type = 'bandpass';
    filter.frequency.value = 420;
    filter.Q.value = 0.6;
    const gain = this.ctx.createGain();
    gain.gain.value = 0.06;
    const lfo = this.ctx.createOscillator();
    lfo.frequency.value = 0.09;
    const lfoGain = this.ctx.createGain();
    lfoGain.gain.value = 220;
    lfo.connect(lfoGain).connect(filter.frequency);
    const lfo2 = this.ctx.createOscillator();
    lfo2.frequency.value = 0.13;
    const lfo2Gain = this.ctx.createGain();
    lfo2Gain.gain.value = 0.03;
    lfo2.connect(lfo2Gain).connect(gain.gain);
    src.connect(filter).connect(gain).connect(this.master);
    src.start();
    lfo.start();
    lfo2.start();
  }

  _startRumble() {
    const osc = this.ctx.createOscillator();
    osc.type = 'sawtooth';
    osc.frequency.value = 38;
    const filter = this.ctx.createBiquadFilter();
    filter.type = 'lowpass';
    filter.frequency.value = 90;
    this.rumbleGain = this.ctx.createGain();
    this.rumbleGain.gain.value = 0;
    osc.connect(filter).connect(this.rumbleGain).connect(this.master);
    osc.start();
  }

  whoosh(dur, freq) {
    if (!this.ctx) return;
    const t = this.ctx.currentTime;
    const src = this._noiseSource();
    const f = this.ctx.createBiquadFilter();
    f.type = 'bandpass';
    f.Q.value = 1.2;
    f.frequency.setValueAtTime(freq * 0.6, t);
    f.frequency.exponentialRampToValueAtTime(freq * 1.6, t + dur);
    const g = this.ctx.createGain();
    this._env(g, t, dur * 0.4, 0.18, dur * 0.6);
    src.connect(f).connect(g).connect(this.master);
    src.start(t, Math.random());
    src.stop(t + dur + 0.05);
  }

  impact() {
    if (!this.ctx) return;
    this.thud(160, 0.18);
    const t = this.ctx.currentTime;
    const o = this.ctx.createOscillator();
    o.type = 'square';
    o.frequency.setValueAtTime(1800 + Math.random() * 400, t);
    const f = this.ctx.createBiquadFilter();
    f.type = 'highpass';
    f.frequency.value = 1200;
    const g = this.ctx.createGain();
    this._env(g, t, 0.003, 0.05, 0.08);
    o.connect(f).connect(g).connect(this.master);
    o.start(t);
    o.stop(t + 0.1);
  }

  thud(freq, dur) {
    if (!this.ctx) return;
    const t = this.ctx.currentTime;
    const o = this.ctx.createOscillator();
    o.frequency.setValueAtTime(freq, t);
    o.frequency.exponentialRampToValueAtTime(freq * 0.4, t + dur);
    const g = this.ctx.createGain();
    this._env(g, t, 0.005, 0.35, dur);
    o.connect(g).connect(this.master);
    o.start(t);
    o.stop(t + dur + 0.05);
    const n = this._noiseSource();
    const f = this.ctx.createBiquadFilter();
    f.type = 'lowpass';
    f.frequency.value = 900;
    const ng = this.ctx.createGain();
    this._env(ng, t, 0.003, 0.25, dur * 0.6);
    n.connect(f).connect(ng).connect(this.master);
    n.start(t, Math.random());
    n.stop(t + dur);
  }

  shieldBreak() {
    if (!this.ctx) return;
    this.thud(70, 0.6);
    this.whoosh(0.35, 300);
    const t = this.ctx.currentTime;
    const n = this._noiseSource();
    const f = this.ctx.createBiquadFilter();
    f.type = 'bandpass';
    f.frequency.value = 2400;
    const g = this.ctx.createGain();
    this._env(g, t, 0.002, 0.2, 0.25);
    n.connect(f).connect(g).connect(this.master);
    n.start(t, Math.random());
    n.stop(t + 0.3);
  }

  growl(freq, dur) {
    if (!this.ctx) return;
    const t = this.ctx.currentTime;
    const o = this.ctx.createOscillator();
    o.type = 'sawtooth';
    o.frequency.setValueAtTime(freq * 1.3, t);
    o.frequency.exponentialRampToValueAtTime(freq * 0.8, t + dur);
    const f = this.ctx.createBiquadFilter();
    f.type = 'lowpass';
    f.frequency.value = freq * 5;
    const g = this.ctx.createGain();
    this._env(g, t, dur * 0.3, 0.12, dur * 0.7);
    o.connect(f).connect(g).connect(this.master);
    o.start(t);
    o.stop(t + dur + 0.05);
  }

  death(heavy) {
    this.growl(heavy ? 50 : 90, heavy ? 1.2 : 0.8);
    this.thud(heavy ? 50 : 80, 0.5);
  }

  chime(freqs, gap) {
    if (!this.ctx) return;
    const t0 = this.ctx.currentTime;
    freqs.forEach((fr, i) => {
      const t = t0 + i * gap;
      const o = this.ctx.createOscillator();
      o.type = 'triangle';
      o.frequency.value = fr;
      const g = this.ctx.createGain();
      this._env(g, t, 0.01, 0.07, 0.9);
      o.connect(g).connect(this.master);
      o.start(t);
      o.stop(t + 1);
    });
  }

  coins() {
    if (!this.ctx) return;
    for (let i = 0; i < 3; i++) {
      const t = this.ctx.currentTime + i * 0.06 + Math.random() * 0.02;
      const o = this.ctx.createOscillator();
      o.type = 'square';
      o.frequency.value = 2200 + Math.random() * 900;
      const g = this.ctx.createGain();
      this._env(g, t, 0.002, 0.025, 0.12);
      o.connect(g).connect(this.master);
      o.start(t);
      o.stop(t + 0.15);
    }
  }

  // a distant, slightly detuned bell
  bell(level = 0.06, base = 196) {
    if (!this.ctx) return;
    const t = this.ctx.currentTime;
    [1, 2.01, 2.76, 5.4].forEach((ratio, i) => {
      const o = this.ctx.createOscillator();
      o.frequency.value = base * ratio;
      const g = this.ctx.createGain();
      this._env(g, t, 0.01, level / (i + 1), 3.5 / (i * 0.5 + 1));
      o.connect(g).connect(this.master);
      o.start(t);
      o.stop(t + 4);
    });
  }

  crow() {
    if (!this.ctx) return;
    const caws = 2 + Math.floor(Math.random() * 2);
    for (let i = 0; i < caws; i++) {
      const t = this.ctx.currentTime + i * 0.32;
      const n = this._noiseSource();
      const f = this.ctx.createBiquadFilter();
      f.type = 'bandpass';
      f.Q.value = 6;
      f.frequency.setValueAtTime(1300, t);
      f.frequency.linearRampToValueAtTime(900, t + 0.18);
      const g = this.ctx.createGain();
      this._env(g, t, 0.02, 0.05, 0.18);
      n.connect(f).connect(g).connect(this.master);
      n.start(t, Math.random());
      n.stop(t + 0.25);
    }
  }

  creak() {
    if (!this.ctx) return;
    const t = this.ctx.currentTime;
    const o = this.ctx.createOscillator();
    o.type = 'sawtooth';
    o.frequency.setValueAtTime(140, t);
    o.frequency.linearRampToValueAtTime(110 + Math.random() * 60, t + 0.8);
    const f = this.ctx.createBiquadFilter();
    f.type = 'bandpass';
    f.frequency.value = 600;
    f.Q.value = 8;
    const g = this.ctx.createGain();
    this._env(g, t, 0.3, 0.025, 0.6);
    o.connect(f).connect(g).connect(this.master);
    o.start(t);
    o.stop(t + 1);
  }

  update(dt) {
    if (!this.ctx) return;
    this.nextCrow -= dt;
    this.nextBell -= dt;
    this.nextCreak -= dt;
    if (this.nextCrow <= 0) {
      this.crow();
      this.nextCrow = 14 + Math.random() * 20;
    }
    if (this.nextBell <= 0) {
      this.bell(0.035, 180 + Math.random() * 30);
      this.nextBell = 35 + Math.random() * 40;
    }
    if (this.nextCreak <= 0) {
      this.creak();
      this.nextCreak = 12 + Math.random() * 18;
    }
    // low rumble rises near the elite's ground
    const p = this.game.player.position;
    let danger = 0;
    for (const z of DANGER_ZONES) {
      const d = Math.hypot(p.x - z.position[0], p.z - z.position[1]);
      danger = Math.max(danger, 1 - d / z.radius);
    }
    if (this.game.worldState.isDefeated('brute_hallow')) danger *= 0.3;
    this.rumbleGain.gain.setTargetAtTime(Math.max(0, danger) * 0.12, this.ctx.currentTime, 0.5);
  }
}
