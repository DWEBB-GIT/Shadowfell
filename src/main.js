import * as THREE from 'three';
import { CONFIG } from './config.js';
import { Events } from './core/events.js';
import { Input } from './core/input.js';
import { Gamepad, BUTTONS } from './core/gamepad.js';
import { Assets } from './assets/assets.js';
import { createTextures } from './render/textures.js';
import { Collision } from './world/collision.js';
import { World } from './world/world.js';
import { PLAYER_START, SHRINE } from './world/layout.js';
import { Player } from './entities/player.js';
import { Combat } from './systems/combat.js';
import { EnemyManager } from './systems/enemies.js';
import { LootSystem } from './systems/loot.js';
import { Interaction } from './systems/interaction.js';
import { Inventory } from './systems/inventory.js';
import { Stats } from './systems/stats.js';
import { Progression } from './systems/progression.js';
import { WorldState } from './systems/worldState.js';
import { SaveManager } from './systems/save.js';
import { Effects } from './systems/fx.js';
import { AudioSystem } from './systems/audio.js';
import { Telegraphs } from './systems/telegraphs.js';
import { ActionBar, ABILITIES } from './systems/actionBar.js';
import { heightAt } from './world/terrain.js';
import { Targeting } from './systems/targeting.js';
import { Hud } from './ui/hud.js';
import { renderItemIcons } from './ui/icons.js';
import { EXAMINE } from './data/text.js';

// Game initialisation and the main loop. Each system owns its own state; this
// file wires them together and routes input.

class Game {
  constructor() {
    this.config = CONFIG;
    this.started = false;
    this.time = 0;
    this.events = new Events();
    this.pendingDeath = null;
  }

  async init() {
    this._initRenderer();
    this.input = new Input(this.renderer.domElement);
    this.pad = new Gamepad();
    this.textures = createTextures();
    this.assets = await new Assets().load();
    this.collision = new Collision();
    this.world = new World(this).build();
    this.scene.add(this.world.group);

    this.worldState = new WorldState(this);
    this.progression = new Progression(this);
    this.stats = new Stats(this);
    this.random = Math.random; // every combat roll goes through this (tests pin it)
    this.player = new Player(this);
    this.scene.add(this.player.group);
    this.inventory = new Inventory(this);
    this.combat = new Combat(this);
    this.telegraphs = new Telegraphs(this);
    this.enemies = new EnemyManager(this);
    this.targeting = new Targeting(this);
    this.loot = new LootSystem(this);
    this.interaction = new Interaction(this);
    this.actionBar = new ActionBar(this);
    this.hud = new Hud(this);
    this.hud.setItemIcons(renderItemIcons(this.assets));
    this.fx = new Effects(this);
    this.audio = new AudioSystem(this);
    this.save = new SaveManager(this);

    this._bindLifecycle();
    this._snapCamera();
    this._showTitle();
    document.getElementById('loading').hidden = true;
    if (this.assets.usedFallback.length) console.warn('Fallback geometry used for:', this.assets.usedFallback);

    this.clock = new THREE.Clock();
    this.renderer.setAnimationLoop(() => this._frame());
  }

  _initRenderer() {
    const canvas = document.getElementById('game');
    this.renderer = new THREE.WebGLRenderer({ canvas, antialias: false, powerPreference: 'high-performance' });
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 1) * CONFIG.camera.renderScale);
    this.renderer.setSize(window.innerWidth, window.innerHeight, false);
    this.renderer.shadowMap.enabled = true;
    this.renderer.shadowMap.type = THREE.PCFShadowMap;
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;

    this.scene = new THREE.Scene();
    // View-distance fog: clear around the player, swallowing the road ahead.
    // Things past `far` are not drawn at all.
    const fogColor = new THREE.Color(CONFIG.fog.color);
    this.scene.background = fogColor;
    this.scene.fog = new THREE.Fog(fogColor, CONFIG.fog.near, CONFIG.fog.far);

    this.camera = new THREE.PerspectiveCamera(CONFIG.camera.fov, window.innerWidth / window.innerHeight, 0.5, CONFIG.fog.far + 6);
    this.cameraTarget = new THREE.Vector3();

    // dusk: a cool sky fill, a low amber sun and a warm glow around the Warden
    this.hemi = new THREE.HemisphereLight(0x8a9aa8, 0x2c2418, 2.1);
    this.scene.add(this.hemi);
    this.sun = new THREE.DirectionalLight(0xf0c890, 2.3);
    this.sun.castShadow = true;
    this.sun.shadow.mapSize.set(1024, 1024);
    const sc = this.sun.shadow.camera;
    sc.left = sc.bottom = -20;
    sc.right = sc.top = 20;
    sc.near = 1;
    sc.far = 80;
    this.sun.shadow.bias = -0.0015;
    this.sun.shadow.normalBias = 0.03;
    this.scene.add(this.sun, this.sun.target);
    this.playerLight = new THREE.PointLight(0xffb070, 5, 9, 1.6);
    this.scene.add(this.playerLight);

    window.addEventListener('resize', () => {
      this.camera.aspect = window.innerWidth / window.innerHeight;
      this.camera.updateProjectionMatrix();
      this.renderer.setSize(window.innerWidth, window.innerHeight, false);
    });
  }

  _bindLifecycle() {
    // autosave when the page is closed or hidden, where the browser allows it
    window.addEventListener('pagehide', () => this.save.autosave());
    window.addEventListener('beforeunload', () => this.save.autosave());
    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState === 'hidden') this.save.autosave();
    });
    document.getElementById('continue-btn').addEventListener('click', () => this.startGame(true));
    document.getElementById('new-btn').addEventListener('click', () => this.startGame(false));
  }

  _showTitle() {
    const result = this.save.read();
    this.bootSave = result;
    let note = '';
    if (result.status === 'invalid') {
      this.save.quarantine(result.raw);
      note = 'Your previous save could not be read. It has been kept aside and will not be overwritten unless you save manually (K).';
      console.warn('Save rejected:', result.errors);
    }
    this.hud.showTitle({ hasSave: result.status === 'ok', note });
  }

  startGame(resume) {
    this.audio.start();
    this.worldState.reset();
    this.progression.apply({ level: 1, xp: 0 });
    this.inventory.apply(new Inventory(this).serialize());
    this.telegraphs.clear();
    this.hud.numbers.clear();
    this.hud.items.closeAll();
    this.actionBar.reset();
    this.targeting.clear();
    this.recomputeMaxHealth();
    this.player.health = this.player.maxHealth;
    this.player.revive(PLAYER_START.position[0], PLAYER_START.position[1]);
    this.player.facing = Math.PI;

    let resumed = false;
    if (resume && this.bootSave.status === 'ok') {
      try {
        this.save.apply(this.bootSave.data);
        resumed = true;
      } catch (err) {
        console.error('Applying save failed', err);
        this.save.quarantine(JSON.stringify(this.bootSave.data));
        this.worldState.reset();
      }
    }
    this.recomputeMaxHealth();
    this.enemies.spawnAll();
    this.loot.spawnAll();
    this.hud.hideTitle();
    this.hud.refreshObjective();
    this.started = true;
    this._snapCamera();
    if (resumed) this.hud.log('You take up the road again.', 'lore');
    else this.hud.log('The Fallen Road. Somewhere ahead lies the old watch post.', 'lore');
  }

  // ----------------------------------------------------------- game events
  onPlayerDeath() {
    const coins = this.inventory.coins;
    const loss = Math.min(CONFIG.death.coinLossCap, Math.floor(coins * CONFIG.death.coinLossFraction));
    this.pendingDeath = { loss, timer: CONFIG.death.screenDelay };
    this.events.emit('playerDied', {});
    this.hud.closeModal(true);
    this.hud.log('You fall.', 'hurt');
  }

  respawn() {
    if (!this.player.dead || !this.pendingDeath) return;
    const lost = this.inventory.loseCoins(this.pendingDeath.loss);
    this.pendingDeath = null;
    const dest = this.respawnPoint();
    this.telegraphs.clear();
    this.hud.numbers.clear();
    this.targeting.clear();
    this.player.revive(dest.x, dest.z);
    this.enemies.resetSurvivors();
    this.hud.hideDeath();
    this._snapCamera();
    this.hud.log(`You wake ${dest.label}.${lost ? ` ${lost} coin${lost === 1 ? '' : 's'} gone.` : ''}`, 'lore');
  }

  // A left click over a body or a drop loots it (and everything close by)
  // instead of swinging. Returns true if the click was used for looting.
  _clickLoot() {
    const { input, camera, renderer, enemies, loot, player, events } = this;
    const r = renderer.domElement.getBoundingClientRect();
    const mx = input.mouse.x - r.left;
    const my = input.mouse.y - r.top;
    const screen = (x, y, z) => {
      const v = new THREE.Vector3(x, y, z).project(camera);
      return v.z < 1 ? Math.hypot(((v.x + 1) / 2) * r.width - mx, ((1 - v.y) / 2) * r.height - my) : Infinity;
    };
    let best = null;
    let bestD = CONFIG.loot.clickRadius;
    for (const l of loot.lootables()) {
      const d = screen(l.x, heightAt(l.x, l.z) + 0.3, l.z);
      if (d < bestD) {
        bestD = d;
        best = l;
      }
    }
    if (!best) return false;
    // a living enemy under the cursor wins: fighting comes first
    for (const e of enemies.list) {
      if (e.alive && screen(e.position.x, e.position.y + 1, e.position.z) < bestD) return false;
    }
    if (Math.hypot(best.x - player.position.x, best.z - player.position.z) > CONFIG.loot.reach) {
      events.emit('log', { text: 'Too far away to loot that.', kind: 'muted', throttle: 'loot-far' });
      return true;
    }
    loot.lootArea(best);
    return true;
  }

  // Maximum health comes from level plus worn gear (the helm).
  recomputeMaxHealth() {
    const p = this.player;
    const before = p.maxHealth;
    p.maxHealth = this.stats.maxHealth;
    if (p.maxHealth > before && !p.dead) p.health += p.maxHealth - before;
    p.health = Math.min(p.health, p.maxHealth);
    this.events.emit('statsChanged', {});
  }

  respawnPoint() {
    const r = this.worldState.respawn;
    if (r) return { x: r.x, z: r.z, label: 'at the roadside shrine', kind: 'shrine' };
    return { x: PLAYER_START.position[0], z: PLAYER_START.position[1], label: "at the road's end", kind: 'start' };
  }

  restAtShrine() {
    const { player, worldState, events, hud } = this;
    const first = !worldState.examined.has('shrine');
    worldState.examined.add('shrine');
    player.health = player.maxHealth;
    // respawn just in front of the shrine, on the road side
    worldState.respawn = { x: SHRINE.position[0] - 1.8, z: SHRINE.position[1] };
    worldState.shrineActivated = SHRINE.id;
    events.emit('shrineRest', {});
    if (first) hud.log(EXAMINE.shrine_first, 'lore');
    hud.log('You rest a while. Your wounds close, and you will return here if you fall.', 'heal');
    hud.toast('Rested at the shrine');
  }

  manualSave() {
    const result = this.save.save({ manual: true });
    if (result.ok) {
      this.hud.toast('Game saved');
      this.hud.log('Game saved.', 'muted');
    } else {
      this.hud.toast(result.reason, 'bad');
      this.hud.log(result.reason, 'hurt');
    }
    return result;
  }

  // -------------------------------------------------------------- the loop
  _aimPoint() {
    const ray = new THREE.Raycaster();
    ray.setFromCamera(new THREE.Vector2(this.input.mouse.ndcX, this.input.mouse.ndcY), this.camera);
    const plane = new THREE.Plane(new THREE.Vector3(0, 1, 0), -this.player.position.y - 0.5);
    const hit = new THREE.Vector3();
    return ray.ray.intersectPlane(plane, hit) ? hit : null;
  }

  // Aim for pad play: the right stick if pushed, otherwise straight ahead
  // (or the way the left stick points), a few metres out.
  _padAim() {
    const p = this.player.position;
    const r = this.pad.right;
    const l = this.pad.left;
    let dir = null;
    if (r.m > 0.3) dir = { x: r.x, z: r.y };
    else if (l.m > 0.3) dir = { x: l.x, z: l.y };
    else dir = { x: Math.sin(this.player.facing), z: Math.cos(this.player.facing) };
    const len = Math.hypot(dir.x, dir.z) || 1;
    return new THREE.Vector3(p.x + (dir.x / len) * 4, p.y, p.z + (dir.z / len) * 4);
  }

  _handleInput(dt) {
    const { input, hud, pad } = this;
    pad.poll();
    // switch prompts to whichever device was touched last
    if (pad.active && pad.now.some(Boolean)) hud.setPadMode(true);
    if (input.pressed.size || input.mouse.clicked) hud.setPadMode(false);

    if (input.consume('KeyM')) hud.setMuted(this.audio.toggleMute());
    if (input.consume('Escape') && !hud.closeModal()) this.targeting.clear();
    if (hud.modal === 'title') {
      if (pad.pressed(BUTTONS.A)) this.startGame(this.bootSave.status === 'ok');
      return null;
    }
    if (hud.modal === 'death') {
      if (input.consume('Enter') || input.consume('KeyE') || pad.pressed(BUTTONS.A)) this.respawn();
      return null;
    }
    if (hud.modal === 'document') {
      if (pad.pressed(BUTTONS.B) || pad.pressed(BUTTONS.A)) hud.closeModal();
      return null;
    }
    if (input.consume('KeyB') || input.consume('KeyI') || pad.pressed(BUTTONS.START)) hud.togglePanel('bags');
    if (input.consume('KeyC') || pad.pressed(BUTTONS.VIEW)) hud.togglePanel('character');
    if (input.consume('KeyP')) hud.togglePanel('spellbook');
    // With a window open the pad drives the window; the world keeps running
    // and the keyboard and mouse still play, as in WoW.
    const padMenu = hud.items.anyOpen;
    if (padMenu) hud.items.gamepad(pad, dt);
    else if (pad.pressed(BUTTONS.UP)) hud.togglePanel('spellbook');
    if (input.consume('KeyK') || (!padMenu && pad.pressed(BUTTONS.DOWN))) this.manualSave();
    if (hud.blocksGameplay) return null;
    if (input.consume('KeyE') || (!padMenu && pad.pressed(BUTTONS.A))) this.interaction.interact();
    if (this.player.dead) return null;

    const padOn = !padMenu;
    const move = padOn && pad.left.m > 0 ? { x: pad.left.x, z: pad.left.y } : input.moveAxis();
    const usingPad = padOn && (pad.left.m > 0 || pad.right.m > 0 || hud.padMode);
    const p = (b) => padOn && pad.pressed(b);
    const h = (b) => padOn && pad.held(b);
    const rawAim = usingPad ? this._padAim() : this._aimPoint();
    this.rawAim = rawAim;
    if (input.consume('Tab') || p(BUTTONS.RS)) this.targeting.toggleLock(rawAim);
    // a click on a body or a drop loots instead of striking
    const click = input.consumeClick() && !this._clickLoot();
    // each spell-bar slot has a fixed key; whatever ability sits there fires
    const slots = [
      input.consume('Digit1') || p(BUTTONS.RB),
      input.consume('Digit2') || input.consume('KeyQ') || p(BUTTONS.LB),
      input.consume('Digit3') || p(BUTTONS.LT),
      input.consume('Digit4') || p(BUTTONS.LEFT),
      click || h(BUTTONS.X) || h(BUTTONS.RT),
      input.consumeRightClick() || p(BUTTONS.Y),
      input.consume('Space') || p(BUTTONS.B),
    ];
    const lock = this.targeting.current;
    return {
      move,
      aim: this.targeting.aimFor(rawAim, ABILITIES.strike.range),
      lungeAim: this.targeting.aimFor(rawAim, ABILITIES.lunge.range),
      lockOn: lock ? lock.position : null,
      actions: this.actionBar.actions(slots),
    };
  }

  _frame() {
    const dt = Math.min(this.clock.getDelta(), 0.1); // clamp long stalls
    this.step(dt);
    this.renderer.render(this.scene, this.camera);
  }

  // One simulation step. Exposed so tests can advance time deterministically.
  step(dt) {
    const controls = this._handleInput(dt); // also runs on the title screen, for the pad
    this.input.endFrame();
    const paused = !this.started || this.hud.blocksGameplay;
    if (!paused) {
      this.time += dt;
      this.player.update(dt, controls);
      this.enemies.update(dt);
      this.telegraphs.update(dt);
      this.targeting.update(dt, this.rawAim, ABILITIES.strike.range + 1);
      this.interaction.update();
      this.loot.update(dt, this.time);
      this.fx.update(dt);
      this.audio.update(dt);
      if (this.pendingDeath && this.hud.modal !== 'death') {
        this.pendingDeath.timer -= dt;
        if (this.pendingDeath.timer <= 0) {
          this.hud.showDeath({ coinsLost: this.pendingDeath.loss, destination: this.respawnPoint().kind });
        }
      }
    }
    this.world.update(dt, performance.now() / 1000);
    this._updateCamera(dt);
    if (this.started) this.hud.update(dt);
  }

  _snapCamera() {
    this.cameraTarget.copy(this.player.position);
    this._placeCamera();
  }

  _updateCamera(dt) {
    // exponential smoothing: the same feel at any frame rate
    const k = 1 - Math.exp(-CONFIG.camera.followSharpness * dt);
    this.cameraTarget.lerp(this.player.position, k);
    this._placeCamera();
  }

  _placeCamera() {
    // a fixed isometric view: the scenes are composed for this one angle
    const [ox, oy, oz] = CONFIG.camera.offset;
    const t = this.cameraTarget;
    this.camera.position.set(t.x + ox, t.y + oy, t.z + oz);
    this.camera.lookAt(t.x, t.y + 1.0, t.z - 2.4); // look a little ahead, up the road
    this.sun.position.set(t.x - 14, t.y + 26, t.z + 6);
    this.sun.target.position.set(t.x, t.y, t.z);
    const p = this.player.position;
    this.playerLight.position.set(p.x, p.y + 2.4, p.z + 0.6);
    this.world.setCutaway(this.camera.position, this.player.position.clone().setY(this.player.position.y + 1.2));
  }
}

const game = new Game();
window.__shadowfall = game; // handle for automated tests and debugging
game.init().catch((err) => {
  console.error(err);
  const l = document.getElementById('loading');
  l.hidden = false;
  l.textContent = 'Shadowfall could not start: ' + err.message;
});
