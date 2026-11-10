// Original spell effects in the 3D scene (spec 7.3): the world reply's `effects` (projectile, hit, ground, charge, aura)
// as plain shapes and colours made for this kit, no WoW spell art. plan(effects, now, places) is pure: it maps the list to
// items { kind, x, y, alpha, phase, ... } in sim yards, fading the ring's events over RING seconds. sync(handle, frame, now)
// plans from frame.effects (positions of afflicted actors come from frame.items) and draw(handle) places one pooled
// three.js object per item and hides the rest. Both are no-ops on a handle without a scene (no WebGL). now is the sim clock
// in seconds, the clock the events' `t` is stamped in. Classic script; tests/viewer/unit_sim_fx.js.
window.TK = window.TK || {};

(function (TK) {
  'use strict';

  // source: assumed (spec 7.3) the seconds an event stays in the world's ring.
  const RING = 2;
  // source: assumed (sim_effects.lua RULES.PROJECTILE_SPEED) yards per second a projectile flies.
  const PROJECTILE_SPEED = 24;
  const STYLE_OF_AURA = { root: 'ice', stun: 'stars' };
  const COLOR = { fire: 0xff8a2a, glow: 0xffd36b, flash: 0xfff0b0, area: 0x7fb8ff, dash: 0xffe9b0, ice: 0xbfeaff, star: 0xffe14a };
  const STARS = 3;
  const SPIKES = 8;
  const ICE_RADIUS = 1.1;
  const GROUND = 0.07;
  const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));
  const states = new WeakMap();

  // Planning ------------------------------------------------------------------------------------------------------

  const fade = (t, now) => clamp(1 - (now - t) / RING, 0, 1);

  function projectile(e, now) {
    const dx = e.to.x - e.from.x;
    const dy = e.to.y - e.from.y;
    const length = Math.hypot(dx, dy);
    const flown = (now - e.t) * PROJECTILE_SPEED;
    if (length === 0 || flown >= length) return null;
    const dir = { x: dx / length, y: dy / length };

    return { x: e.from.x + dir.x * flown, y: e.from.y + dir.y * flown, dir, alpha: 1, phase: now - e.t };
  }

  const hit = (e, now) => ({ x: e.at.x, y: e.at.y, alpha: fade(e.t, now), phase: now - e.t });

  function area(e, now) {
    const timed = typeof e.t === 'number';

    return { x: e.at.x, y: e.at.y, radius: e.radius, alpha: timed ? fade(e.t, now) : 1, phase: timed ? now - e.t : now };
  }

  const charge = (e, now) => ({ x: e.from.x, y: e.from.y, to: { x: e.to.x, y: e.to.y }, alpha: fade(e.t, now), phase: now - e.t });

  function aura(e, now, places) {
    const at = places && places[e.guid];
    const style = STYLE_OF_AURA[e.style];

    return at && style ? { x: at.x, y: at.y, style, alpha: 1, phase: now } : null;
  }

  const PLANNERS = { projectile, hit, ground: area, charge, aura };

  // The items of effects at sim time now; places maps an actor guid to its { x, y } (for auras). An unknown kind, a
  // faded event, an arrived projectile and an aura of a missing actor are left out.
  function plan(effects, now, places) {
    const items = [];
    (effects || []).forEach((e) => {
      const planner = PLANNERS[e.kind];
      const item = planner && planner(e, now, places);
      if (item && item.alpha > 0) items.push({ kind: e.kind, ...item });
    });

    return { items };
  }

  // Objects -------------------------------------------------------------------------------------------------------

  function mesh(T, geometry, color, opacity) {
    const material = new T.MeshBasicMaterial({ color, transparent: true, opacity, depthWrite: false });
    const out = new T.Mesh(geometry, material);
    out.userData.base = opacity;
    out.renderOrder = 2;

    return out;
  }

  // A cone that tapers away from the ball along +z, the trail of a projectile.
  function trail(T) {
    const geometry = new T.CylinderGeometry(0.02, 0.3, 2.4, 10, 1, true).translate(0, 1.2, 0).rotateX(Math.PI / 2);

    return mesh(T, geometry, COLOR.fire, 0.55);
  }

  function projectileNode(T) {
    const root = new T.Group();
    root.add(mesh(T, new T.SphereGeometry(0.32, 16, 12), COLOR.fire, 1), mesh(T, new T.SphereGeometry(0.55, 16, 12), COLOR.glow, 0.35), trail(T));

    return { root, place: placeProjectile };
  }

  function placeProjectile(root, item) {
    root.position.set(item.x, 1.2, -item.y);
    root.rotation.y = Math.atan2(-item.dir.x, item.dir.y);
  }

  function hitNode(T) {
    const root = new T.Group();
    root.add(mesh(T, new T.SphereGeometry(0.6, 16, 12), COLOR.flash, 0.9));

    return { root, place: placeHit };
  }

  function placeHit(root, item) {
    root.position.set(item.x, 1, -item.y);
    root.scale.setScalar(0.4 + item.phase * 0.9);
  }

  function groundNode(T) {
    const root = new T.Group();
    const ring = new T.RingGeometry(0.94, 1, 64).rotateX(-Math.PI / 2);
    const fill = new T.CircleGeometry(1, 48).rotateX(-Math.PI / 2);
    root.add(mesh(T, fill, COLOR.area, 0.16), mesh(T, ring, COLOR.area, 0.9));

    return { root, place: placeGround };
  }

  function placeGround(root, item) {
    root.position.set(item.x, GROUND, -item.y);
    root.scale.setScalar(item.radius * (1 + 0.012 * Math.sin(item.phase * 4)));
  }

  function chargeNode(T) {
    const root = new T.Group();
    const strip = new T.BoxGeometry(1, 0.05, 1).translate(0, 0, 0.5);
    root.add(mesh(T, strip, COLOR.dash, 0.6));

    return { root, place: placeCharge };
  }

  // The strip runs +z from the start; scale.z is its length and the yaw turns +z to the dash direction.
  function placeCharge(root, item) {
    const dx = item.to.x - item.x;
    const dy = item.to.y - item.y;
    root.position.set(item.x, 0.9, -item.y);
    root.rotation.y = Math.atan2(dx, -dy);
    root.scale.set(0.7, 1, Math.hypot(dx, dy));
  }

  function iceNode(T) {
    const root = new T.Group();
    root.add(mesh(T, new T.TorusGeometry(ICE_RADIUS, 0.09, 8, 40).rotateX(Math.PI / 2), COLOR.ice, 0.85));
    for (let i = 0; i < SPIKES; i++) {
      const angle = (i / SPIKES) * Math.PI * 2;
      const spike = mesh(T, new T.ConeGeometry(0.13, 0.7, 5), COLOR.ice, 0.8);
      spike.position.set(Math.cos(angle) * ICE_RADIUS, 0.35, Math.sin(angle) * ICE_RADIUS);
      root.add(spike);
    }

    return { root, place: placeAura };
  }

  function starsNode(T) {
    const root = new T.Group();
    for (let i = 0; i < STARS; i++) {
      const angle = (i / STARS) * Math.PI * 2;
      const star = mesh(T, new T.OctahedronGeometry(0.17), COLOR.star, 1);
      star.position.set(Math.cos(angle) * 0.7, 2.4, Math.sin(angle) * 0.7);
      root.add(star);
    }

    return { root, place: placeAura };
  }

  function placeAura(root, item) {
    root.position.set(item.x, 0, -item.y);
    root.rotation.y = item.phase * (item.style === 'stars' ? 3 : 0.6);
  }

  const BUILDERS = {
    projectile: projectileNode,
    hit: hitNode,
    ground: groundNode,
    charge: chargeNode,
    aura: (T, item) => (item.style === 'stars' ? starsNode(T) : iceNode(T)),
  };

  // Scales every translucent part of root to alpha (each part keeps the opacity it was made with).
  function fadeNode(root, alpha) {
    root.traverse((node) => {
      if (node.isMesh) node.material.opacity = node.userData.base * alpha;
    });
  }

  function stateOf(handle) {
    const held = states.get(handle);
    if (held || !handle.THREE || !handle.scene) return held;
    const group = new handle.THREE.Group();
    group.name = 'fx';
    handle.scene.add(group);
    handle.groups = handle.groups || {};
    handle.groups.fx = group;
    const created = { group, pool: {}, items: [] };
    states.set(handle, created);

    return created;
  }

  // The pooled object for the n-th item of its key, made on first use.
  function nodeFor(handle, state, key, n, item) {
    const list = state.pool[key] || [];
    state.pool[key] = list;
    if (list[n]) return list[n];
    const built = BUILDERS[item.kind](handle.THREE, item);
    built.root.userData.kind = item.kind;
    state.group.add(built.root);
    list[n] = built;

    return built;
  }

  // Sync and draw ------------------------------------------------------------------------------------------------

  // Plans the frame's effects. frame = { items: [{ raw, pos }], effects, now }; now defaults to frame.now.
  function sync(handle, frame, now) {
    const state = stateOf(handle);
    if (!state) return;
    const places = {};
    (frame.items || []).forEach((item) => {
      places[item.raw.guid] = item.pos;
    });
    const at = now === undefined ? frame.now : now;
    state.items = plan(frame.effects, at, places).items;
  }

  // Places the planned items and hides every pooled object past them.
  function draw(handle) {
    const state = states.get(handle);
    if (!state) return;
    const used = {};
    state.items.forEach((item) => {
      const key = item.kind + (item.style || '');
      used[key] = (used[key] || 0) + 1;
      const node = nodeFor(handle, state, key, used[key] - 1, item);
      node.root.visible = true;
      node.place(node.root, item);
      fadeNode(node.root, item.alpha);
    });
    Object.keys(state.pool).forEach((key) => {
      state.pool[key].forEach((node, n) => {
        if (n >= (used[key] || 0)) node.root.visible = false;
      });
    });
  }

  TK.scene3dFx = { RING, PROJECTILE_SPEED, plan, create: stateOf, sync, draw };
})(window.TK);
