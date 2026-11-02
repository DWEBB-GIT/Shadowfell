import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { fallbackModel } from './fallback.js';

// The Blender-built .glb files are embedded into the bundle at build time
// (esbuild's binary loader), so the game runs from a double-clicked
// index.html with no web server and no network access.
import warden from '../../assets/models/characters/warden.glb';
import ghoul from '../../assets/models/characters/ghoul.glb';
import brute from '../../assets/models/characters/brute.glb';
import cart from '../../assets/models/environment/props/cart.glb';
import crate from '../../assets/models/environment/props/crate.glb';
import crate_broken from '../../assets/models/environment/props/crate_broken.glb';
import wheel from '../../assets/models/environment/props/wheel.glb';
import shrine from '../../assets/models/environment/props/shrine.glb';
import watch_post from '../../assets/models/environment/buildings/watch_post.glb';
import pine from '../../assets/models/environment/trees/pine.glb';
import dead_tree from '../../assets/models/environment/trees/dead_tree.glb';
import rock0 from '../../assets/models/environment/rocks/rock0.glb';
import rock1 from '../../assets/models/environment/rocks/rock1.glb';
import grave0 from '../../assets/models/environment/props/grave0.glb';
import grave1 from '../../assets/models/environment/props/grave1.glb';
import ruin_wall from '../../assets/models/environment/buildings/ruin_wall.glb';
import waymarker from '../../assets/models/environment/props/waymarker.glb';
import fence from '../../assets/models/environment/props/fence.glb';
import watchmans_edge from '../../assets/models/items/weapons/watchmans_edge.glb';
import coin_purse from '../../assets/models/items/supplies/coin_purse.glb';
import manifest from '../../assets/models/items/supplies/manifest.glb';
import grave_iron from '../../assets/models/items/supplies/grave_iron.glb';
import draught from '../../assets/models/items/supplies/draught.glb';
import worn_sword from '../../assets/models/items/supplies/worn_sword.glb';
import watch_helm from '../../assets/models/items/armour/watch_helm.glb';
import satchel from '../../assets/models/items/supplies/satchel.glb';
import kite_shield from '../../assets/models/items/armour/kite_shield.glb';
import clothes from '../../assets/models/items/armour/clothes.glb';
import mara from '../../assets/models/characters/mara.glb';
import anvil from '../../assets/models/environment/props/anvil.glb';
import forge from '../../assets/models/environment/props/forge.glb';
import awning from '../../assets/models/environment/props/awning.glb';
import iron_gloves from '../../assets/models/items/armour/iron_gloves.glb';
import hob_boots from '../../assets/models/items/armour/hob_boots.glb';
import mail_chausses from '../../assets/models/items/armour/mail_chausses.glb';
import iron_shield from '../../assets/models/items/armour/iron_shield.glb';
import hound from '../../assets/models/characters/hound.glb';
import archer from '../../assets/models/characters/archer.glb';
import seer from '../../assets/models/characters/seer.glb';
import black_pine from '../../assets/models/environment/trees/black_pine.glb';
import standing_stone from '../../assets/models/environment/rocks/standing_stone.glb';
import palisade from '../../assets/models/environment/props/palisade.glb';
import bone_pile from '../../assets/models/environment/props/bone_pile.glb';
import rusted_falchion from '../../assets/models/items/weapons/rusted_falchion.glb';
import warden_hauberk from '../../assets/models/items/armour/warden_hauberk.glb';
import plate_sabatons from '../../assets/models/items/armour/plate_sabatons.glb';
import blackwood_cleaver from '../../assets/models/items/weapons/blackwood_cleaver.glb';
import hound_pelt from '../../assets/models/items/supplies/hound_pelt.glb';
import cracked_bone from '../../assets/models/items/supplies/cracked_bone.glb';
import bent_arrowhead from '../../assets/models/items/supplies/bent_arrowhead.glb';
import hound_meat from '../../assets/models/items/supplies/hound_meat.glb';
import old_watch_helm from '../../assets/models/items/armour/old_watch_helm.glb';
import witchbane from '../../assets/models/items/weapons/witchbane.glb';
import arming_sword from '../../assets/models/items/weapons/arming_sword.glb';
import militia_sword from '../../assets/models/items/weapons/militia_sword.glb';
import dirk from '../../assets/models/items/weapons/dirk.glb';
import hunting_bow from '../../assets/models/items/weapons/hunting_bow.glb';
import arrow from '../../assets/models/environment/props/arrow.glb';
import arrow_bundle from '../../assets/models/items/weapons/arrow_bundle.glb';
import arrow_bundle_barbed from '../../assets/models/items/weapons/arrow_bundle_barbed.glb';
import quiver from '../../assets/models/items/supplies/quiver.glb';
import bone_knife from '../../assets/models/items/supplies/bone_knife.glb';
import cooked_fish from '../../assets/models/items/supplies/cooked_fish.glb';
import steak from '../../assets/models/items/supplies/steak.glb';
import stew from '../../assets/models/items/supplies/stew.glb';
import innkeeper from '../../assets/models/characters/innkeeper.glb';
import inn_shell from '../../assets/models/environment/buildings/inn_shell.glb';
import inn_front from '../../assets/models/environment/buildings/inn_front.glb';
import inn_roof from '../../assets/models/environment/buildings/inn_roof.glb';
import cottage from '../../assets/models/environment/buildings/cottage.glb';
import well from '../../assets/models/environment/props/well.glb';
import lamp_post from '../../assets/models/environment/props/lamp_post.glb';
import tam from '../../assets/models/characters/tam.glb';
import camp from '../../assets/models/environment/props/camp.glb';
import torch from '../../assets/models/items/supplies/torch.glb';
import fishing_rod from '../../assets/models/items/supplies/fishing_rod.glb';
import perch from '../../assets/models/items/supplies/perch.glb';
import dace from '../../assets/models/items/supplies/dace.glb';
import eel from '../../assets/models/items/supplies/eel.glb';
import old_boot from '../../assets/models/items/supplies/old_boot.glb';
import chest from '../../assets/models/environment/props/chest.glb';
import signpost from '../../assets/models/environment/props/signpost.glb';
import sign_arm from '../../assets/models/environment/props/sign_arm.glb';

const SOURCES = {
  warden, ghoul, brute, cart, crate, crate_broken, wheel, shrine, watch_post,
  pine, dead_tree, rock0, rock1, grave0, grave1, ruin_wall, waymarker, fence,
  watchmans_edge, coin_purse, manifest, grave_iron, draught,
  worn_sword, watch_helm, satchel, clothes, kite_shield,
  mara, anvil, forge, awning, iron_gloves, hob_boots, mail_chausses, iron_shield,
  hound, archer, seer, black_pine, standing_stone, palisade, bone_pile,
  rusted_falchion, warden_hauberk, plate_sabatons, blackwood_cleaver, hound_pelt,
  cracked_bone, bent_arrowhead, hound_meat, old_watch_helm, witchbane,
  tam, camp, torch, fishing_rod, perch, dace, eel, old_boot, chest,
  arming_sword, militia_sword, dirk, bone_knife, hunting_bow, arrow, arrow_bundle, arrow_bundle_barbed, quiver,
  signpost, sign_arm,
  cooked_fish, steak, stew, innkeeper, inn_shell, inn_front, inn_roof, cottage, well, lamp_post,
};

// One shared material per Blender material name keeps draw state small.
export const SHARED_MATERIALS = {
  M_Base: new THREE.MeshLambertMaterial({ vertexColors: true, flatShading: true }),
  M_Glow: new THREE.MeshBasicMaterial({ vertexColors: true }),
};

function adoptSharedMaterials(root) {
  root.traverse((obj) => {
    if (!obj.isMesh) return;
    const name = obj.material && obj.material.name;
    obj.material = SHARED_MATERIALS[name] || SHARED_MATERIALS.M_Base;
    obj.castShadow = true;
    obj.receiveShadow = true;
  });
}

export class Assets {
  constructor() {
    this.templates = {};
    this.usedFallback = [];
  }

  async load() {
    const loader = new GLTFLoader();
    const jobs = Object.entries(SOURCES).map(async ([name, bytes]) => {
      try {
        const buffer = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
        const gltf = await loader.parseAsync(buffer, '');
        const root = gltf.scene;
        root.name = name;
        adoptSharedMaterials(root);
        this.templates[name] = root;
      } catch (err) {
        console.warn(`Model "${name}" failed to load, using fallback geometry.`, err);
        this.templates[name] = fallbackModel(name);
        this.usedFallback.push(name);
      }
    });
    await Promise.all(jobs);
    return this;
  }

  // Returns an independent copy (geometry and materials shared).
  instance(name) {
    const t = this.templates[name] || fallbackModel(name);
    return t.clone(true);
  }

  // Returns a single merged-geometry mesh for instancing, if the model is one mesh.
  geometryOf(name) {
    let found = null;
    this.templates[name].traverse((o) => {
      if (o.isMesh && !found) found = o;
    });
    return found;
  }
}
