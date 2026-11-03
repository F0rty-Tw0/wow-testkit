// Sim actor models: which vendored KayKit model a world entry wears (modelFor: class token -> CLASS_MODEL, other class
// -> barbarian, no class -> skeleton), its size variant, its animation state (stateOf) and the clip that plays it
// (clipFor). load(name, deps) injects viewer/vendor/models/<name>.js once, decodes the base64 GLB it sets on TK.models
// and parses it with THREE.GLTFLoader, hiding the hand items KEEP_NODES does not keep; it resolves null on any failure.
// makeActor clones a loaded model to 1.8 yd with its own materials and one AnimationMixer: attack and hit play once and
// return to the base state, death plays once and holds. primitive is the capsule stand-in while a model is pending or
// failed. Classic script; tests/viewer/unit_sim_models.js.
window.TK = window.TK || {};

(function (TK) {
  'use strict';

  const CLASS_MODEL = {
    WARRIOR: 'knight',
    PALADIN: 'knight',
    MAGE: 'mage',
    WARLOCK: 'mage',
    PRIEST: 'mage',
    EVOKER: 'mage',
    ROGUE: 'rogue',
    MONK: 'rogue',
    DEMONHUNTER: 'rogue',
    HUNTER: 'ranger',
    DRUID: 'ranger',
    SHAMAN: 'barbarian',
    DEATHKNIGHT: 'barbarian',
  };
  // Hand items shown per model (viewer/vendor/models/CREDITS.md, Hand-item nodes); every other child of a hand slot
  // hides. Helmets, hats, hoods and capes are body meshes and never hide.
  const KEEP_NODES = {
    knight: ['1H_Sword', 'Round_Shield'],
    mage: ['2H_Staff'],
    barbarian: ['1H_Axe'],
    ranger: ['1H_Crossbow'],
    rogue: ['Knife', 'Knife_Offhand'],
  };
  const HAND_SLOTS = ['handslot.r', 'handslot.l'];
  const IDLE = /idle/i;
  const ATTACK = /attack|slice|chop|stab|swing/i;
  // Per state, patterns tried in order over the clip names; only the first counts as exact. Cast tries the channel
  // (Spellcasting) before the pack's shots, which sort ahead of it.
  const CLIP_PATTERNS = {
    idle: [IDLE],
    run: [/run/i, /walk/i],
    attack: [ATTACK],
    cast: [/casting/i, /cast|spell|shoot/i, ATTACK],
    hit: [/hit|damage/i, IDLE],
    death: [/death|die/i, IDLE],
  };
  const STATIC_POSE = /pose/i;
  const ONE_SHOTS = ['attack', 'hit'];
  const HELD = ['death'];
  const FADE = 0.15;
  const HEIGHT = 1.8;
  const COLORS = { friendly: 0x2f9e94, hostile: 0xa8502e };
  const BASE = scriptBase();
  const loads = new Map();
  const heights = new WeakMap();

  // The models folder beside this script, so the host's file:// page and the viewer's /viewer/ page both find it.
  function scriptBase() {
    const script = document.currentScript;
    const src = script && script.src ? script.src : '';

    return src.replace(/[^/]*$/, '') + 'vendor/models/';
  }

  function modelFor(raw) {
    if (!raw.class) return 'skeleton';

    return CLASS_MODEL[raw.class] || 'barbarian';
  }

  function variant(guid) {
    let h = 0;
    for (const ch of String(guid)) h = (h * 31 + ch.charCodeAt(0)) >>> 0;

    return 0.95 + (h % 1001) / 10000;
  }

  function moved(prevRaw, raw) {
    if (!prevRaw || !prevRaw.pos || !raw.pos) return false;

    return Math.hypot(raw.pos.x - prevRaw.pos.x, raw.pos.y - prevRaw.pos.y) > 0.01;
  }

  function stateOf(prevRaw, raw) {
    if (raw.dead) return 'death';
    if (prevRaw && raw.swings > prevRaw.swings) return 'attack';
    if (raw.casting) return 'cast';
    if (prevRaw && raw.health < prevRaw.health) return 'hit';
    if (raw.moving !== undefined) return raw.moving ? 'run' : 'idle';

    return moved(prevRaw, raw) ? 'run' : 'idle';
  }

  function clipFor(state, clipNames) {
    const names = clipNames.filter((n) => !STATIC_POSE.test(n));
    const patterns = CLIP_PATTERNS[state] || [];
    for (let i = 0; i < patterns.length; i++) {
      const name = names.find((n) => patterns[i].test(n));
      if (name) return { name, exact: i === 0 };
    }

    return null;
  }

  function decode(base64) {
    const text = atob(base64);
    const bytes = Uint8Array.from(text, (c) => c.charCodeAt(0));

    return bytes.buffer;
  }

  function injectScript(url) {
    return new Promise((resolve, reject) => {
      const el = document.createElement('script');
      el.src = url;
      el.onload = resolve;
      el.onerror = () => reject(new Error('cannot load ' + url));
      document.head.appendChild(el);
    });
  }

  // GLTFLoader strips '.' from node names, so 'handslot.r' is found by its sanitized name.
  function hideHandItems(T, scene, name) {
    const keep = KEEP_NODES[name] || [];
    HAND_SLOTS.forEach((slot) => {
      const node = scene.getObjectByName(T.PropertyBinding.sanitizeNodeName(slot));
      if (!node) return;
      node.children.forEach((child) => {
        child.visible = keep.includes(child.name);
      });
    });
  }

  async function fetchModel(name, deps) {
    const T = deps.THREE || window.THREE;
    const loadScript = deps.loadScript || injectScript;
    const base = deps.base || BASE;
    try {
      await loadScript(base + name + '.js');
      const b64 = TK.models && TK.models[name];
      if (!b64) return null;
      const gltf = await new T.GLTFLoader().parseAsync(decode(b64), '');
      hideHandItems(T, gltf.scene, name);
      const out = { scene: gltf.scene, animations: gltf.animations };

      return out;
    } catch {
      return null;
    }
  }

  function load(name, deps = {}) {
    if (!loads.has(name)) loads.set(name, fetchModel(name, deps));

    return loads.get(name);
  }

  function primitive(T, opts) {
    const color = opts.hostile ? COLORS.hostile : COLORS.friendly;
    const skin = new T.MeshStandardMaterial({ color, roughness: 0.8 });
    const torso = new T.Mesh(new T.CapsuleGeometry(0.32, 0.9, 4, 10), skin);
    const head = new T.Mesh(new T.BoxGeometry(0.34, 0.34, 0.34), skin);
    const visor = new T.Mesh(new T.BoxGeometry(0.24, 0.08, 0.06), new T.MeshStandardMaterial({ color: 0x222222 }));
    const out = new T.Group();
    torso.position.y = 0.77;
    head.position.y = 1.62;
    visor.position.set(0, 1.66, 0.18);
    [torso, head, visor].forEach((part) => {
      part.castShadow = true;
    });
    out.add(torso, head, visor);

    return out;
  }

  // Skinned bounds need the bones' world matrices, so the model is posed before it is measured.
  function fitScale(T, model) {
    if (!heights.has(model)) {
      model.scene.updateMatrixWorld(true);
      heights.set(model, new T.Box3().setFromObject(model.scene).getSize(new T.Vector3()).y);
    }
    const height = heights.get(model);

    return height > 0 ? HEIGHT / height : 1;
  }

  // Disposes the materials of one node; the geometry stays, because a clone shares it with the loaded model.
  function freeMaterials(node) {
    [].concat(node.material || []).forEach((m) => m.dispose());
  }

  // Clones keep their own materials, so a hover lift on one actor leaves the others alone.
  function ownMaterials(body) {
    body.traverse((node) => {
      if (!node.isMesh) return;
      node.material = Array.isArray(node.material) ? node.material.map((m) => m.clone()) : node.material.clone();
      node.castShadow = true;
    });
  }

  function makeActor(T, opts) {
    const model = opts.model;
    const body = T.SkeletonUtils.clone(model.scene);
    const group = new T.Group();
    const mixer = new T.AnimationMixer(body);
    const names = model.animations.map((clip) => clip.name);
    let base = 'idle';
    let current = null;
    let action = null;
    let left = Infinity;
    ownMaterials(body);
    body.scale.multiplyScalar(fitScale(T, model));
    group.add(body);

    function play(state) {
      const pick = clipFor(state, names) || clipFor('idle', names);
      const once = ONE_SHOTS.includes(state) || HELD.includes(state);
      current = state;
      left = Infinity;
      if (!pick) return;
      const clip = T.AnimationClip.findByName(model.animations, pick.name);
      const next = mixer.clipAction(clip);
      if (action && action !== next) action.fadeOut(FADE);
      next.reset().setLoop(once ? T.LoopOnce : T.LoopRepeat, Infinity);
      next.clampWhenFinished = once;
      next.fadeIn(FADE).play();
      action = next;
      if (ONE_SHOTS.includes(state)) left = clip.duration;
    }

    function setState(state) {
      if (ONE_SHOTS.includes(state)) {
        play(state);

        return;
      }
      base = state;
      const busy = ONE_SHOTS.includes(current);
      if (!busy && state !== current) play(state);
    }

    function update(dt) {
      mixer.update(dt);
      left -= dt;
      if (left <= 0) play(base);
    }

    function dispose() {
      mixer.stopAllAction();
      mixer.uncacheRoot(body);
      body.traverse(freeMaterials);
    }

    play('idle');
    const out = { group, setState, update, playing: () => current, dispose };

    return out;
  }

  TK.scene3dModels = {
    CLASS_MODEL,
    modelFor,
    variant,
    decode,
    load,
    clipFor,
    stateOf,
    primitive,
    makeActor,
    freeMaterials,
  };
})(window.TK);
