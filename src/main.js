import { CURSORS } from './ui/cursors.js';
import * as THREE from 'three';
import { CONFIG } from './config.js';
import { Events } from './core/events.js';
import { Input } from './core/input.js';
import { Gamepad, BUTTONS } from './core/gamepad.js';
import { Assets } from './assets/assets.js';
import { createTextures } from './render/textures.js';
import { Collision } from './world/collision.js';
import { World } from './world/world.js';
import { PLAYER_START, SHRINE, SHRINES, REGIONS, regionAt } from './world/layout.js';
import { blackwoodness } from './world/terrain.js';
import { Player } from './entities/player.js';
import { Combat } from './systems/combat.js';
import { Spells } from './systems/spells.js';
import { Afterlife } from './systems/afterlife.js';
import { Skills } from './systems/skills.js';
import { Settings } from './systems/settings.js';
import { Chests } from './systems/chests.js';
import { Reputation } from './systems/reputation.js';
import { Sparkles } from './render/sparkles.js';
import { Camp } from './systems/camp.js';
import { WaterAndDark } from './world/waterAndDark.js';
import { Fishing } from './systems/fishing.js';
import { EnemyManager } from './systems/enemies.js';
import { LootSystem } from './systems/loot.js';
import { Interaction } from './systems/interaction.js';
import { Inventory } from './systems/inventory.js';
import { Stats } from './systems/stats.js';
import { Progression } from './systems/progression.js';
import { WorldState } from './systems/worldState.js';
import { SaveManager, validateSave } from './systems/save.js';
import { Effects } from './systems/fx.js';
import { AudioSystem } from './systems/audio.js';
import { Telegraphs } from './systems/telegraphs.js';
import { ActionBar, ABILITIES } from './systems/actionBar.js';
import { heightAt } from './world/terrain.js';
import { Targeting } from './systems/targeting.js';
import { NpcManager } from './systems/npcs.js';
import { Merchant } from './systems/merchant.js';
import { QuestLog } from './systems/quests.js';
import { Dialogue } from './systems/dialogue.js';
import { Hud } from './ui/hud.js';
import { renderItemIcons } from './ui/icons.js';
import { EXAMINE } from './data/text.js';
import { ITEMS, validateItems, rollItem, itemView, rollLoot } from './data/items.js';
import { DB } from './data/db.js';
import { DATA_ERRORS } from './data/db.js';

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
    this.waterAndDark = new WaterAndDark(this).build();
    this.scene.add(this.world.group);

    this.worldState = new WorldState(this);
    // every data file is checked on load (src/data/schema.js); npm test
    // also checks them before the game is opened
    this.dataErrors = DATA_ERRORS;
    this.itemErrors = DATA_ERRORS; // (the name the item database tests use)
    for (const e of this.dataErrors) console.error('Game data: ' + e);
    this.items = ITEMS;
    this.validateItems = validateItems; // for tests and tools
    this.rollItem = rollItem;
    this.itemView = itemView;
    this.rollLoot = rollLoot;
    this.db = DB;
    this.validateSave = validateSave;
    this.progression = new Progression(this);
    this.stats = new Stats(this);
    this.random = Math.random; // every combat roll goes through this (tests pin it)
    this.player = new Player(this);
    this.scene.add(this.player.group);
    this.inventory = new Inventory(this);
    this.quests = new QuestLog(this);
    this.combat = new Combat(this);
    this.spells = new Spells(this);
    this.afterlife = new Afterlife(this);
    this.skills = new Skills(this);
    this.settings = new Settings(this);
    this.reputation = new Reputation(this);
    this.camp = new Camp(this);
    this.fishing = new Fishing(this);
    this.telegraphs = new Telegraphs(this);
    this.enemies = new EnemyManager(this);
    this.targeting = new Targeting(this);
    this.npcs = new NpcManager(this);
    this.merchant = new Merchant(this);
    this.dialogue = new Dialogue(this);
    this.loot = new LootSystem(this);
    this.chests = new Chests(this);
    this.sparkles = new Sparkles(this);
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
    this.dialogue.close();
    this.merchant.close();
    this.merchant.buyback = [];
    this.quests.startNew();
    this.region = null; // named again, quietly, from wherever the Warden stands
    this.afterlife.reset();
    this.skills.reset();
    this.reputation.reset();
    this.pendingDeath = null;
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
    this.camp.show();
    this.enemies.spawnAll();
    this.loot.spawnAll();
    this.chests.spawnAll();
    this.hud.hideTitle();
    this.hud.refreshObjective();
    this.started = true;
    this._snapCamera();
    if (resumed) this.hud.log('You take up the road again.', 'lore');
    else this.hud.log('The Fallen Road. Somewhere ahead lies the old watch post.', 'lore');
  }

  // ----------------------------------------------------------- game events
  onPlayerDeath(killer = null) {
    const coins = this.inventory.coins;
    const loss = Math.min(CONFIG.death.coinLossCap, Math.floor(coins * CONFIG.death.coinLossFraction));
    this.pendingDeath = { loss, timer: CONFIG.death.screenDelay };
    this.afterlife.onDeath(killer, loss);
    this.events.emit('playerDied', {});
    this.hud.closeModal(true);
    this.hud.log('You fall.', 'hurt');
  }

  // Leave the body and walk as a spirit (systems/afterlife.js).
  releaseSpirit() {
    if (!this.player.dead || !this.pendingDeath) return false;
    this.pendingDeath = null;
    this.hud.hideDeath();
    this.afterlife.release();
    this._snapCamera();
    return true;
  }

  // Release and return to life at once at the rest point, coins lost.
  respawn() {
    if (!this.releaseSpirit()) return;
    this.afterlife.reviveHere();
  }

  // What is under the cursor: a body or drop to loot, a living enemy, or a
  // townsperson. A living enemy wins a close call: fighting comes first.
  _pickUnderCursor() {
    const { input, camera, renderer, enemies, loot, npcs } = this;
    const r = renderer.domElement.getBoundingClientRect();
    const mx = input.mouse.x - r.left;
    const my = input.mouse.y - r.top;
    const screen = (x, y, z) => {
      const v = new THREE.Vector3(x, y, z).project(camera);
      return v.z < 1 ? Math.hypot(((v.x + 1) / 2) * r.width - mx, ((1 - v.y) / 2) * r.height - my) : Infinity;
    };
    let best = null;
    let bestD = CONFIG.targeting.clickRadius;
    const consider = (kind, obj, d) => {
      if (d < bestD) {
        bestD = d;
        best = { kind, obj };
      }
    };
    for (const e of enemies.list) {
      // the body and the feet both count, so tall and short foes are easy to click
      if (e.alive) consider('enemy', e, Math.min(screen(e.position.x, e.position.y + 1, e.position.z), screen(e.position.x, e.position.y + 0.3, e.position.z)) - 6);
    }
    for (const n of npcs.list) consider('npc', n, screen(n.position.x, n.position.y + 1, n.position.z));
    for (const c of this.chests.list) if (!this.chests.opened(c)) consider('chest', c, screen(c.x, heightAt(c.x, c.z) + 0.4, c.z));
    for (const l of loot.lootables()) {
      const d = screen(l.x, heightAt(l.x, l.z) + 0.3, l.z);
      if (d < CONFIG.loot.clickRadius) consider('loot', l, d);
    }
    return best;
  }

  // The mouse cursor says what a click would do (WoW): a sword over an
  // enemy, a speech bubble over a townsperson (grey until you are close
  // enough to talk), a hand over loot.
  _cursorFor(pick) {
    let c = '';
    if (pick) {
      const p = this.player.position;
      const o = pick.obj;
      if (pick.kind === 'enemy') c = CURSORS.attack;
      else if (pick.kind === 'npc') c = Math.hypot(o.position.x - p.x, o.position.z - p.z) <= CONFIG.shop.talkRange + 0.5 ? CURSORS.talk : CURSORS.talkFar;
      else if (pick.kind === 'loot' || pick.kind === 'chest') c = Math.hypot(o.x - p.x, o.z - p.z) <= (pick.kind === 'chest' ? 2.4 : CONFIG.loot.reach) ? CURSORS.loot : CURSORS.lootFar;
    }
    if (c !== this.cursor) this.renderer.domElement.style.cursor = this.cursor = c;
  }

  // Left click selects, right click acts (WoW): right on an enemy starts
  // auto attack, on a townsperson talks, and either button loots.
  _click(button) {
    // a click on (or near) the fishing bob strikes
    const bob = this.fishing.bobPosition;
    if (bob) {
      const r = this.renderer.domElement.getBoundingClientRect();
      const v = bob.clone().project(this.camera);
      const d = Math.hypot(((v.x + 1) / 2) * r.width - (this.input.mouse.x - r.left), ((1 - v.y) / 2) * r.height - (this.input.mouse.y - r.top));
      if (d < CONFIG.fishing.clickRadius) return this.fishing.strike();
    }
    const pick = this._pickUnderCursor();
    // a left click on the ground lets go of the target; a right click does not
    if (!pick) {
      if (button === 'left') this.targeting.clear();
      return false;
    }
    const { player, events, targeting, loot } = this;
    const far = (x, z, reach) => Math.hypot(x - player.position.x, z - player.position.z) > reach;
    if (pick.kind === 'chest') {
      if (far(pick.obj.x, pick.obj.z, 2.4)) this.hud.error('You need to be closer to interact with that target.');
      else this.chests.open(pick.obj);
    } else if (pick.kind === 'loot') {
      const l = pick.obj;
      if (far(l.x, l.z, CONFIG.loot.reach)) events.emit('log', { text: 'Too far away to loot that.', kind: 'muted', throttle: 'loot-far' });
      else loot.lootArea(l);
    } else if (pick.kind === 'enemy') {
      if (button === 'right') {
        targeting.engage(pick.obj);
        if (!targeting.targetInReach) this.hud.error('Out of range');
      } else targeting.select(pick.obj);
    } else if (pick.kind === 'npc') {
      // either button selects a townsperson and talks to them, if close enough
      const n = pick.obj;
      targeting.selectFriendly(n);
      if (far(n.position.x, n.position.z, CONFIG.shop.talkRange + 0.5)) this.hud.error('You need to be closer to interact with that target.');
      else this.npcs.talk(n);
    }
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
    return this.afterlife.restPoint();
  }

  restAtShrine(shrine = SHRINE) {
    const { player, worldState, events, hud } = this;
    const first = !worldState.examined.has('shrine');
    worldState.examined.add('shrine');
    player.health = player.maxHealth;
    // respawn just in front of the shrine, on the road side
    worldState.respawn = { x: shrine.position[0] - 1.8, z: shrine.position[1] };
    worldState.shrineActivated = shrine.id;
    worldState.restPoint = 'shrine';
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
      if (input.consume('Enter') || input.consume('KeyE') || pad.pressed(BUTTONS.A)) this.releaseSpirit();
      return null;
    }
    if (hud.modal === 'document') {
      if (pad.pressed(BUTTONS.B) || pad.pressed(BUTTONS.A)) hud.closeModal();
      return null;
    }
    if (input.consume('KeyB') || input.consume('KeyI') || pad.pressed(BUTTONS.START)) hud.togglePanel('bags');
    if (input.consume('KeyC') || pad.pressed(BUTTONS.VIEW)) hud.togglePanel('character');
    if (input.consume('KeyP')) hud.togglePanel('spellbook');
    if (input.consume('KeyU')) hud.togglePanel('skills');
    if (input.consume('KeyO')) hud.togglePanel('settings');
    // D-pad right opens and closes the log (it moves the highlight in the bags)
    if (input.consume('KeyL') || (!hud.items.anyOpen && !this.dialogue.isOpen && pad.pressed(BUTTONS.RIGHT))) hud.togglePanel('quests');
    // With a window open the pad drives the window; the world keeps running
    // and the keyboard and mouse still play, as in WoW. Conversations and the
    // quest log come first.
    const padMenu = hud.quests.anyOpen || hud.items.anyOpen;
    if (hud.quests.anyOpen) hud.quests.gamepad(pad, dt);
    else if (padMenu) hud.items.gamepad(pad, dt);
    else if (pad.pressed(BUTTONS.UP)) hud.togglePanel('spellbook');
    if (input.consume('KeyK') || (!padMenu && pad.pressed(BUTTONS.DOWN))) this.manualSave();
    if (hud.blocksGameplay) return null;
    if (input.consume('KeyE') || (!padMenu && pad.pressed(BUTTONS.A))) {
      if (this.fishing.active) this.fishing.strike();
      else this.interaction.interact();
    }
    const padOn = !padMenu;
    // a spirit only walks
    if (this.player.ghost) {
      input.consumeClick();
      input.consumeRightClick();
      return { move: padOn && pad.left.m > 0 ? { x: pad.left.x, z: pad.left.y } : input.moveAxis(), aim: null, actions: {} };
    }
    if (this.player.dead) return null;

    const move = padOn && pad.left.m > 0 ? { x: pad.left.x, z: pad.left.y } : input.moveAxis();
    const usingPad = padOn && (pad.left.m > 0 || pad.right.m > 0 || hud.padMode);
    const p = (b) => padOn && pad.pressed(b);
    const rawAim = usingPad ? this._padAim() : this._aimPoint();
    this.rawAim = rawAim;
    const tg = this.targeting;
    // Tab / R3 cycle targets; RT engages whoever is selected or ahead
    if (input.consume('Tab') || p(BUTTONS.RS)) tg.cycle(rawAim);
    if (p(BUTTONS.RT) && tg.engage(tg.current || tg.softTarget(rawAim, CONFIG.targeting.range)) && !tg.targetInReach) this.hud.error('Out of range');
    // hovering over anyone in the world shows who they are (bottom right)
    if (!usingPad) {
      const hover = input.mouse.onCanvas ? this._pickUnderCursor() : null;
      this.hud.items.worldTip(hover);
      this._cursorFor(hover);
    }
    // left click selects, right click attacks, talks or loots
    if (input.consumeClick()) this._click('left');
    if (input.consumeRightClick()) this._click('right');
    // each spell-bar slot has a fixed key; whatever ability sits there fires
    const slots = [
      input.consume('Digit1') || p(BUTTONS.X),
      input.consume('Digit2') || p(BUTTONS.Y),
      input.consume('Digit3') || input.consume('KeyQ') || p(BUTTONS.RB),
      input.consume('Digit4') || p(BUTTONS.LB),
      input.consume('Digit5') || p(BUTTONS.LT),
      input.consume('Space') || p(BUTTONS.B),
    ];
    const actions = this.actionBar.actions(slots);
    // Auto attack (WoW): once engaged (right-click, RT, or any ability used
    // on an enemy) the Warden swings whenever the target is in reach, in
    // front of him, and his weapon is ready. It is not on the bar.
    actions.strike = tg.attacking && tg.targetInReach;
    return {
      move,
      aim: actions.strike ? tg.current.position.clone() : tg.aimFor(rawAim, ABILITIES.strike.range),
      rawAim,
      actions,
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
      this.spells.update(dt);
      this.camp.update(dt, this.time);
      this.fishing.update(dt);
      this.waterAndDark.update(dt, this.time);
      this.enemies.update(dt);
      this.npcs.update(dt);
      this.merchant.update();
      this.dialogue.update();
      this.telegraphs.update(dt);
      this.targeting.update(dt, this.rawAim, ABILITIES.strike.range + 1);
      this.interaction.update();
      this.loot.update(dt, this.time);
      this.sparkles.update(dt);
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
    this._updateRegion();
    this._updateCamera(dt);
    if (this.started) this.hud.update(dt);
  }

  // Which region the Warden is in, and the air there: the fog and light
  // shade smoothly from the Fallen Road's dusk into the Blackwood's gloom.
  _updateRegion() {
    const z = this.player.position.z;
    const k = blackwoodness(z);
    if (k !== this._bwk) {
      this._bwk = k;
      const bw = CONFIG.blackwood;
      this.scene.fog.near = THREE.MathUtils.lerp(CONFIG.fog.near, bw.fogNear, k);
      this.scene.fog.far = THREE.MathUtils.lerp(CONFIG.fog.far, bw.fogFar, k);
      this.scene.fog.color.set(CONFIG.fog.color).lerp(new THREE.Color(bw.fogColor), k);
      this.scene.background.copy(this.scene.fog.color);
      const light = THREE.MathUtils.lerp(1, bw.light, k);
      this.hemi.intensity = 2.1 * light;
      this.sun.intensity = 2.3 * light;
    }
    // a little hysteresis so walking along the border does not flicker the name
    let r = regionAt(z);
    if (this.region && r !== this.region) {
      const ahead = REGIONS.indexOf(r) > REGIONS.indexOf(this.region) ? 1.5 : -1.5;
      if (regionAt(z + ahead) !== r) r = this.region;
    }
    if (r !== this.region) {
      const first = !!this.region;
      this.region = r;
      this.events.emit('regionChanged', { region: r, announce: first && this.started });
    }
  }

  _snapCamera() {
    this.cameraTarget.copy(this.player.position);
    this._placeCamera();
  }

  _updateCamera(dt) {
    // exponential smoothing: the same feel at any frame rate
    const k = 1 - Math.exp(-CONFIG.camera.followSharpness * dt);
    this.cameraTarget.lerp(this.player.position, k);
    this._placeCamera(dt);
  }

  // a kick of the camera when a blow lands (see CONFIG.impact)
  shakeCamera(amount) {
    this.shake = Math.max(this.shake || 0, amount);
  }

  _placeCamera(dt = 0) {
    // a fixed isometric view: the scenes are composed for this one angle
    const [ox, oy, oz] = CONFIG.camera.offset;
    const t = this.cameraTarget;
    let sx = 0;
    let sy = 0;
    if (this.shake > 0.001) {
      sx = Math.sin(this.time * 71) * this.shake;
      sy = Math.cos(this.time * 53) * this.shake;
      this.shake *= Math.exp(-CONFIG.impact.shakeDecay * dt);
    } else this.shake = 0;
    this.camera.position.set(t.x + ox + sx, t.y + oy + sy, t.z + oz);
    this.camera.lookAt(t.x + sx, t.y + 1.0 + sy, t.z - 2.4); // look a little ahead, up the road
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
