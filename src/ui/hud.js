import * as THREE from 'three';
import { CONFIG } from '../config.js';
import { DOCUMENTS, INTRO } from '../data/text.js';
import { ItemUI } from './itemUI.js';
import { abilityIcons } from './icons.js';
import { ABILITIES, BAR_SLOTS } from '../systems/actionBar.js';
import { DamageNumbers } from './damageNumbers.js';

// The HUD reads game state and forwards requests (equip, respawn, close).
// It never decides gameplay outcomes itself.
//
// Bottom of the screen, Diablo/WoW style: the experience bar across the top
// of a spell bar, then the micro menu, coins and the bag slots.

const $ = (id) => document.getElementById(id);

export class Hud {
  constructor(game) {
    this.game = game;
    // 'title' | 'document' | 'death'. Bags, character panel and spellbook are
    // not modal: the world keeps running while they are open, as in WoW.
    this.modal = null;
    this.padMode = false; // show gamepad button names instead of keys
    this.logThrottle = new Map();
    this.enemyBars = new Map();
    this.tmp = new THREE.Vector3();
    this.el = {
      level: $('stat-level'),
      hpFill: $('hp-fill'),
      hpText: $('hp-text'),
      xpFill: $('xp-fill'),
      xpText: $('xp-text'),
      coins: $('stat-coins'),
      objective: $('objective-text'),
      objectiveState: $('objective-state'),
      objectiveTitle: $('objective-title'),
      prompt: $('prompt'),
      log: $('log'),
      bars: $('enemy-bars'),
      toast: $('toast'),
      vignette: $('vignette'),
      actionBar: $('action-bar'),
      documentPanel: $('document'),
      docTitle: $('document-title'),
      docBody: $('document-body'),
      death: $('death'),
      deathText: $('death-text'),
      target: $('target-frame'),
      targetName: $('target-name'),
      targetFill: $('target-fill'),
      targetText: $('target-text'),
      targetLabel: $('target-label'),
      targetManaBar: $('target-mana-bar'),
      targetMana: $('target-mana'),
      targetManaText: $('target-mana-text'),

      respawnBtn: $('respawn-btn'),
      title: $('title-screen'),
      continueBtn: $('continue-btn'),
      newBtn: $('new-btn'),
      titleNote: $('title-note'),
      intro: $('intro-text'),
      mute: $('mute-indicator'),
    };
    this.el.intro.textContent = INTRO;
    const P = () => game.player.cooldowns;
    this.cooldowns = {
      strike: () => [P().attack, game.stats.attackCooldown, false],
      shieldBreak: () => [P().shieldBreak, CONFIG.shieldBreak.cooldown, true],
      lunge: () => [P().lunge, CONFIG.lunge.cooldown, true],
      brace: () => [P().brace, CONFIG.brace.cooldown, false],
      draught: () => [P().draught, CONFIG.draught.cooldown, false],
    };
    this.abilityIcons = abilityIcons();
    this._buildBar();
    this.items = new ItemUI(game, this);
    this.numbers = new DamageNumbers(game, $('damage-numbers'));
    // the last enemy you fought, shown in the target frame for a while
    this.recentFoe = null;
    this.recentFoeTime = 0;
    const fought = (e) => {
      this.recentFoe = e.enemy;
      this.recentFoeTime = 6;
    };

    const ev = game.events;
    ev.on('log', (e) => this.log(e.text, e.kind, e.throttle));
    ev.on('objectiveChanged', () => this.refreshObjective());
    ev.on('regionChanged', ({ region, announce }) => {
      document.querySelector('#title-area .region').textContent = region.name;
      if (announce) {
        this.toast(region.name);
        if (region.id === 'blackwood') this.log('The pines close overhead and the road light fails. The Blackwood.', 'lore', 'enter-blackwood');
      }
    });
    ev.on('equipmentChanged', () => this.refreshStats());
    ev.on('statsChanged', () => this.refreshStats());
    ev.on('levelUp', (e) => this.showLevelUp(e));
    ev.on('barChanged', () => this.renderBar());
    ev.on('enemyHit', fought);
    ev.on('playerHurt', fought);

    document.querySelectorAll('[data-close]').forEach((b) => b.addEventListener('click', () => this.closeModal()));
    this.el.respawnBtn.addEventListener('click', () => game.respawn());

  }

  setItemIcons(icons) {
    if (icons.draught) this.abilityIcons.draught = icons.draught;
    this.items.setIcons(icons);
    this.renderBar();
  }

  // Only the title screen and documents pause the world; the death screen
  // and the item windows do not.
  get blocksGameplay() {
    return this.modal === 'title' || this.modal === 'document';
  }

  // ------------------------------------------------------------ spell bar
  _buildBar() {
    let html = '';
    BAR_SLOTS.forEach((b, i) => {
      if (i === 4) html += '<div class="sep"></div>';
       html += `<div class="aslot${b.mouse ? ' mouse' : ''}${b.defensive ? ' defensive' : ''}" id="aslot-${i}" data-loc="a:${i}"><img alt=""><span class="key" data-kbm="${b.kbm}" data-pad="${b.pad}"></span><span class="count"></span><span class="cd"></span><span class="gcd"></span><span class="aname"></span></div>`;
    });
    this.el.actionBar.innerHTML = html;
    this.barSlots = BAR_SLOTS.map((_, i) => $('aslot-' + i));
  }

  renderBar() {
    const bar = this.game.actionBar;
    if (!bar || !this.barSlots) return;
    this.barSlots.forEach((el, i) => {
      const a = bar.slots[i];
      el.dataset.ability = a || '';
      el.classList.toggle('empty', !a);
      const img = el.querySelector('img');
      if (a) img.src = this.abilityIcons[a] || '';
      else img.removeAttribute('src');
      el.querySelector('.aname').textContent = a ? ABILITIES[a].name : '';
    });
    this._applyKeyLabels();
  }

  // Swap every key label between keyboard and gamepad names.
  setPadMode(on) {
    if (this.padMode === on) return;
    this.padMode = on;
    document.body.classList.toggle('pad', on);
    this._applyKeyLabels();
    this.el.prompt.dataset.text = ''; // redraw the prompt with the right key
    this.items.render();
  }

  _applyKeyLabels() {
    document.querySelectorAll('.key[data-kbm]').forEach((k) => {
      k.textContent = this.padMode ? k.dataset.pad : k.dataset.kbm;
    });
  }

  // ---------------------------------------------------------------- modals
  showTitle({ hasSave, note }) {
    this.modal = 'title';
    this.el.title.hidden = false;
    $('hud').hidden = true;
    this.el.continueBtn.hidden = !hasSave;
    this.el.newBtn.textContent = hasSave ? 'Begin a new journey' : 'Begin';
    this.el.titleNote.textContent = note || '';
    this.el.titleNote.hidden = !note;
    (hasSave ? this.el.continueBtn : this.el.newBtn).focus();
  }

  hideTitle() {
    this.el.title.hidden = true;
    $('hud').hidden = false;
    this.modal = null;
    this.items.render();
  }

  // Bags, character panel and spellbook; toggles for B / C / P and the pad.
  togglePanel(which) {
    if (this.modal) return;
    this.items.toggle(which);
  }

  openDocument(id) {
    const doc = DOCUMENTS[id];
    if (!doc) return;
    this.modal = 'document';
    this.el.docTitle.textContent = doc.title;
    this.el.docBody.innerHTML = doc.body;
    this.el.documentPanel.hidden = false;
  }

  showDeath({ coinsLost, destination }) {
    this.closeModal(true);
    this.modal = 'death';
    this.el.deathText.textContent =
      `The road takes what it can. ${coinsLost > 0 ? `You will wake ${coinsLost} coin${coinsLost === 1 ? '' : 's'} lighter.` : 'You have nothing left for it to take.'}`;
    this.el.respawnBtn.textContent = destination === 'shrine' ? 'Return to the last shrine' : "Return to the road's end";
    this.el.death.hidden = false;
    this.el.respawnBtn.focus();
  }

  hideDeath() {
    this.el.death.hidden = true;
    this.modal = null;
  }

  // Escape / B closes whatever is open. The death screen only closes by respawning.
  closeModal(force = false) {
    if (this.modal === 'title' || (this.modal === 'death' && !force)) return false;
    if (this.modal === 'document') {
      // the windows underneath stay open
      this.el.documentPanel.hidden = true;
      this.modal = null;
      if (force) this.items.closeAll();
      return true;
    }
    if (force) this.items.closeAll();
    return this.items.closeAll();
  }

  // ------------------------------------------------------------- feedback
  log(text, kind = '', throttle = null) {
    if (!text) return;
    const now = performance.now();
    if (throttle) {
      if (now - (this.logThrottle.get(throttle) || -1e9) < 1500) return;
      this.logThrottle.set(throttle, now);
    }
    const li = document.createElement('li');
    li.className = kind;
    li.textContent = text;
    this.el.log.appendChild(li);
    while (this.el.log.children.length > 7) this.el.log.firstChild.remove();
    setTimeout(() => li.classList.add('old'), 9000);
  }

  // Level-up card: each stat that rose, old value to new.
  showLevelUp({ level, gains }) {
    $('levelup-title').textContent = `Level ${level}`;
    $('levelup-list').innerHTML = gains
      .map((g) => `<div class="lu-row"><span>${g.label}</span><span class="dim">${g.from}</span><span class="lu-arrow">→</span><b>${g.to}</b><span class="up">+${g.diff}</span></div>`)
      .join('');
    this.levelUpTime = 6;
    $('levelup').hidden = false;
    $('levelup').style.opacity = 1;
  }

  toast(text, kind = '') {
    const t = this.el.toast;
    t.textContent = text;
    t.className = 'show ' + kind;
    clearTimeout(this.toastTimer);
    this.toastTimer = setTimeout(() => (t.className = ''), 2200);
  }

  flashDamage() {
    const v = this.el.vignette;
    v.classList.remove('hit');
    void v.offsetWidth; // restart the CSS animation
    v.classList.add('hit');
  }

  setMuted(m) {
    this.el.mute.hidden = !m;
  }

  refreshObjective() {
    const ws = this.game.worldState;
    const quest = ws.objectiveQuest;
    const stage = ws.questStage(quest.id);
    this.el.objectiveTitle.textContent = quest.name;
    this.el.objective.textContent = stage.text;
    this.el.objectiveState.textContent = stage.label;
    this.el.objectiveState.className = stage.style || '';
  }

  refreshStats() {
    const { player, progression, inventory } = this.game;
    this.el.level.textContent = progression.level;
    const hp = Math.max(0, Math.ceil(player.health));
    this.el.hpFill.style.width = `${(player.health / player.maxHealth) * 100}%`;
    this.el.hpText.textContent = `${hp} / ${player.maxHealth}`;
    this.el.xpFill.style.width = `${(progression.xp / progression.xpToNext) * 100}%`;
    this.el.xpText.textContent = `Level ${progression.level}  ·  ${progression.xp} / ${progression.xpToNext} experience`;
    this.el.coins.textContent = inventory.coins;
    const n = inventory.draughts;
    for (const el of this.barSlots) {
      const isDraught = el.dataset.ability === 'draught';
      el.querySelector('.count').textContent = isDraught ? n : '';
      el.classList.toggle('none', isDraught && n === 0);
    }
  }

  // Cooldown sweep per slot, plus the shared GCD sweep on GCD abilities.
  _refreshSlots() {
    const gcd = this.game.player.cooldowns.gcd;
    for (const el of this.barSlots) {
      const a = el.dataset.ability;
      const [remaining, total, onGcd] = a ? this.cooldowns[a]() : [0, 0, false];
      const own = total > 0 ? remaining / total : 0;
      // whichever finishes later is what the player is waiting on
      const showGcd = onGcd && gcd > remaining;
      el.style.setProperty('--cd', (showGcd ? 0 : own).toFixed(3));
      el.style.setProperty('--gcd', (showGcd ? gcd / this.game.stats.globalCooldown : 0).toFixed(3));
      el.classList.toggle('cooling', remaining > 0 || showGcd);
      el.classList.toggle('active', a === 'brace' && this.game.player.isBraced);
    }
  }

  update(dt = 0) {
    const { interaction, enemies, camera, renderer } = this.game;
    this.numbers.update(dt);
    if (this.levelUpTime > 0) {
      this.levelUpTime -= dt;
      const lu = $('levelup');
      lu.style.opacity = Math.min(1, Math.max(0, this.levelUpTime)).toFixed(2);
      if (this.levelUpTime <= 0) lu.hidden = true;
    }
    this.recentFoeTime = Math.max(0, this.recentFoeTime - dt);
    this.refreshStats();
    this._refreshSlots();

    const c = interaction.current;
    const promptText = c && !this.modal ? c.prompt : '';
    const key = this.padMode ? 'A' : 'E';
    if (this.el.prompt.dataset.text !== promptText + key) {
      this.el.prompt.dataset.text = promptText + key;
      this.el.prompt.innerHTML = promptText ? `<kbd>${key}</kbd> ${promptText}` : '';
      this.el.prompt.hidden = !promptText;
    }

    // target frame: the hard lock, else the soft-lock target, else the
    // enemy you last traded blows with. Health always, mana if it has any.
    const t = this.game.targeting.current;
    const recent = this.recentFoeTime > 0 && this.recentFoe && this.recentFoe.alive ? this.recentFoe : null;
    const shown = t || this.game.targeting.soft || recent;
    this.shownTarget = shown;
    this.el.target.hidden = !shown;
    if (shown) {
      const c = shown.cfg;
      this.el.targetName.textContent = c.name;
      this.el.targetLabel.textContent = t ? 'Locked' : `Level ${c.level || 1}`;
      this.el.targetFill.style.width = `${(shown.health / c.health) * 100}%`;
      this.el.targetText.textContent = `${Math.ceil(shown.health)} / ${c.health}`;
      this.el.target.classList.toggle('elite', !!c.elite);
      this.el.target.classList.toggle('locked', !!t);
      this.el.targetManaBar.hidden = !c.mana;
      if (c.mana) {
        this.el.targetMana.style.width = `${(shown.mana / c.mana) * 100}%`;
        this.el.targetManaText.textContent = `${Math.ceil(shown.mana)} / ${c.mana}`;
      }
    }

    // enemy health bars, shown when engaged or damaged
    const w = renderer.domElement.clientWidth;
    const h = renderer.domElement.clientHeight;
    const seen = new Set();
    for (const e of enemies.list) {
      if (!e.alive) continue;
      if (e.engaged <= 0 && e.health >= e.cfg.health && e !== t && e !== shown) continue;
      seen.add(e.id);
      let bar = this.enemyBars.get(e.id);
      if (!bar) {
        bar = document.createElement('div');
        bar.className = 'ebar' + (e.cfg.elite ? ' elite' : '');
        bar.innerHTML = `<span class="ename">${e.cfg.name}</span><div class="etrack"><div class="efill"></div></div>${e.cfg.mana ? '<div class="emana"><div class="emana-fill"></div></div>' : ''}<div class="ecast"><div class="ecast-fill"></div><span class="ecast-name"></span></div>`;
        this.el.bars.appendChild(bar);
        this.enemyBars.set(e.id, bar);
      }
      this.tmp.set(e.position.x, e.position.y + (e.cfg.barHeight || (e.cfg.elite ? 3.0 : 2.1)), e.position.z).project(camera);
      const visible = this.tmp.z < 1 && Math.abs(this.tmp.x) < 1.1 && Math.abs(this.tmp.y) < 1.1;
      bar.style.display = visible ? '' : 'none';
      bar.style.transform = `translate(${((this.tmp.x + 1) / 2) * w}px, ${((1 - this.tmp.y) / 2) * h}px) translate(-50%, -100%)`;
      bar.querySelector('.efill').style.width = `${(e.health / e.cfg.health) * 100}%`;
      if (e.cfg.mana) bar.querySelector('.emana-fill').style.width = `${(e.mana / e.cfg.mana) * 100}%`;
      bar.classList.toggle('winding', e.windup > 0 || !!e.casting);
      bar.classList.toggle('targeted', e === t);
      // FFXIV-style cast bar under the name while a telegraphed attack winds up
      const cast = e.casting;
      bar.classList.toggle('casting', !!cast);
      if (cast) {
        const t = cast.telegraph;
        bar.querySelector('.ecast-fill').style.width = `${t ? Math.min(100, (t.t / t.duration) * 100) : 0}%`;
        bar.querySelector('.ecast-name').textContent = cast.label || '';
        bar.classList.toggle('heavy', cast.kind === 'special');
      }
    }
    for (const [id, bar] of this.enemyBars) {
      if (!seen.has(id)) {
        bar.remove();
        this.enemyBars.delete(id);
      }
    }
  }
}
