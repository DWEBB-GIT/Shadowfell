import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { fallbackModel } from './fallback.js';

// The Blender-built .glb files are embedded into the bundle at build time
// (esbuild's binary loader), so the game runs from a double-clicked
// index.html with no web server and no network access.
import warden from '../../assets/models/warden.glb';
import ghoul from '../../assets/models/ghoul.glb';
import brute from '../../assets/models/brute.glb';
import cart from '../../assets/models/cart.glb';
import crate from '../../assets/models/crate.glb';
import crate_broken from '../../assets/models/crate_broken.glb';
import wheel from '../../assets/models/wheel.glb';
import shrine from '../../assets/models/shrine.glb';
import watch_post from '../../assets/models/watch_post.glb';
import pine from '../../assets/models/pine.glb';
import dead_tree from '../../assets/models/dead_tree.glb';
import rock0 from '../../assets/models/rock0.glb';
import rock1 from '../../assets/models/rock1.glb';
import grave0 from '../../assets/models/grave0.glb';
import grave1 from '../../assets/models/grave1.glb';
import ruin_wall from '../../assets/models/ruin_wall.glb';
import waymarker from '../../assets/models/waymarker.glb';
import fence from '../../assets/models/fence.glb';
import watchmans_edge from '../../assets/models/watchmans_edge.glb';
import coin_purse from '../../assets/models/coin_purse.glb';
import manifest from '../../assets/models/manifest.glb';
import grave_iron from '../../assets/models/grave_iron.glb';
import draught from '../../assets/models/draught.glb';
import worn_sword from '../../assets/models/worn_sword.glb';
import watch_helm from '../../assets/models/watch_helm.glb';
import satchel from '../../assets/models/satchel.glb';
import kite_shield from '../../assets/models/kite_shield.glb';
import clothes from '../../assets/models/clothes.glb';
import mara from '../../assets/models/mara.glb';
import anvil from '../../assets/models/anvil.glb';
import forge from '../../assets/models/forge.glb';
import awning from '../../assets/models/awning.glb';
import iron_gloves from '../../assets/models/iron_gloves.glb';
import hob_boots from '../../assets/models/hob_boots.glb';
import mail_chausses from '../../assets/models/mail_chausses.glb';
import iron_shield from '../../assets/models/iron_shield.glb';
import hound from '../../assets/models/hound.glb';
import archer from '../../assets/models/archer.glb';
import seer from '../../assets/models/seer.glb';
import black_pine from '../../assets/models/black_pine.glb';
import standing_stone from '../../assets/models/standing_stone.glb';
import palisade from '../../assets/models/palisade.glb';
import bone_pile from '../../assets/models/bone_pile.glb';
import rusted_falchion from '../../assets/models/rusted_falchion.glb';
import warden_hauberk from '../../assets/models/warden_hauberk.glb';
import plate_sabatons from '../../assets/models/plate_sabatons.glb';
import blackwood_cleaver from '../../assets/models/blackwood_cleaver.glb';
import hound_pelt from '../../assets/models/hound_pelt.glb';
import cracked_bone from '../../assets/models/cracked_bone.glb';
import bent_arrowhead from '../../assets/models/bent_arrowhead.glb';
import hound_meat from '../../assets/models/hound_meat.glb';
import old_watch_helm from '../../assets/models/old_watch_helm.glb';
import witchbane from '../../assets/models/witchbane.glb';
import arming_sword from '../../assets/models/arming_sword.glb';
import militia_sword from '../../assets/models/militia_sword.glb';
import dirk from '../../assets/models/dirk.glb';
import bone_knife from '../../assets/models/bone_knife.glb';
import cooked_fish from '../../assets/models/cooked_fish.glb';
import steak from '../../assets/models/steak.glb';
import stew from '../../assets/models/stew.glb';
import innkeeper from '../../assets/models/innkeeper.glb';
import inn_shell from '../../assets/models/inn_shell.glb';
import inn_front from '../../assets/models/inn_front.glb';
import inn_roof from '../../assets/models/inn_roof.glb';
import cottage from '../../assets/models/cottage.glb';
import well from '../../assets/models/well.glb';
import lamp_post from '../../assets/models/lamp_post.glb';
import tam from '../../assets/models/tam.glb';
import camp from '../../assets/models/camp.glb';
import torch from '../../assets/models/torch.glb';
import fishing_rod from '../../assets/models/fishing_rod.glb';
import perch from '../../assets/models/perch.glb';
import dace from '../../assets/models/dace.glb';
import eel from '../../assets/models/eel.glb';
import old_boot from '../../assets/models/old_boot.glb';
import chest from '../../assets/models/chest.glb';

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
  arming_sword, militia_sword, dirk, bone_knife,
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
