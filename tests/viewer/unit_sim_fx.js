// The original spell effects of the 3D scene (viewer/scene3d_fx.js): plan (pure), and sync / draw over a real three.js
// scene with no renderer, which is all the GL path needs to be checked. Effects are the world reply's `effects` list.
(function () {
  'use strict';

  const near = (a, b, e = 1e-6) => Math.abs(a - b) < e;
  const plan = (effects, now, places) => TK.scene3dFx.plan(effects, now, places).items;
  const ground = (extra) => ({ kind: 'ground', at: { x: 0, y: 10 }, radius: 8, spellID: 1, ...extra });
  const handle = () => ({ ok: true, THREE, scene: new THREE.Scene(), groups: {} });
  const fxGroup = (h) => h.scene.children.find((node) => node.name === 'fx');
  const shown = (h) => fxGroup(h).children.filter((node) => node.visible).length;

  TK_TESTS.push({
    name: 'fx plan fades effects over two seconds and keeps the real radius',
    fn() {
      const [item] = plan([ground({ t: 10 })], 11);
      A.eq(item.kind, 'ground');
      A.eq(item.radius, 8);
      A.same([item.x, item.y], [0, 10]);
      A.eq(near(item.alpha, 0.5), true, 'half way through the ring');
      A.eq(near(plan([ground({ t: 10 })], 10)[0].alpha, 1), true, 'fresh');
      A.same(plan([ground({ t: 10 })], 12.1), [], 'older than the ring is gone');
    },
  });

  TK_TESTS.push({
    name: 'fx plan keeps a live area (no t) opaque and animates it by the clock',
    fn() {
      const [a] = plan([ground()], 50);
      const [b] = plan([ground()], 51);
      A.same([a.alpha, b.alpha], [1, 1]);
      A.eq(a.phase !== b.phase, true, 'phase moves with now');
    },
  });

  TK_TESTS.push({
    name: 'fx plan moves a projectile from its start to its target by (now - t) * speed and drops it on arrival',
    fn() {
      const flying = { kind: 'projectile', from: { x: 0, y: 0 }, to: { x: 0, y: 48 }, spellID: 133, t: 10 };
      const speed = TK.scene3dFx.PROJECTILE_SPEED;
      const [half] = plan([flying], 10.5);
      A.same([half.x, half.y], [0, speed * 0.5]);
      A.same([half.dir.x, half.dir.y], [0, 1], 'unit direction of travel');
      A.eq(plan([flying], 10.25)[0].y < half.y, true, 'earlier is nearer the start');
      A.same(plan([flying], 10 + 48 / speed + 0.01), [], 'arrived: the hit takes over');
      A.eq(half.alpha, 1, 'opaque in flight');
    },
  });

  TK_TESTS.push({
    name: 'fx plan maps a hit and a charge to their points and fades them',
    fn() {
      const [hit] = plan([{ kind: 'hit', at: { x: 3, y: 4 }, spellID: 1, t: 5 }], 5.5);
      A.same([hit.kind, hit.x, hit.y], ['hit', 3, 4]);
      A.eq(near(hit.alpha, 0.75), true);
      const [dash] = plan([{ kind: 'charge', from: { x: 0, y: 0 }, to: { x: 0, y: 12 }, spellID: 100, t: 5 }], 6);
      A.same([dash.kind, dash.x, dash.y, dash.to], ['charge', 0, 0, { x: 0, y: 12 }]);
      A.eq(near(dash.alpha, 0.5), true);
    },
  });

  TK_TESTS.push({
    name: 'fx plan styles a root as an ice ring and a stun as stars at the afflicted actor',
    fn() {
      const places = { g1: { x: 1, y: 2 }, g2: { x: 5, y: 6 } };
      const auras = [
        { kind: 'aura', guid: 'g1', spellID: 122, style: 'root' },
        { kind: 'aura', guid: 'g2', spellID: 100, style: 'stun' },
        { kind: 'aura', guid: 'gone', spellID: 100, style: 'stun' },
        { kind: 'aura', guid: 'g1', spellID: 1, style: 'periodic' },
      ];
      const items = plan(auras, 7, places);
      A.same(
        items.map((i) => [i.kind, i.style, i.x, i.y, i.alpha]),
        [
          ['aura', 'ice', 1, 2, 1],
          ['aura', 'stars', 5, 6, 1],
        ],
      );
    },
  });

  TK_TESTS.push({
    name: 'fx plan drops an unknown kind and answers an empty or missing list with no items',
    fn() {
      A.same(plan([{ kind: 'meteor', t: 1 }, { kind: 'hit', at: { x: 0, y: 0 }, t: 1 }], 1).map((i) => i.kind), ['hit']);
      A.same([plan([], 1), plan(undefined, 1)], [[], []]);
      A.same(TK.scene3dFx.plan(undefined, 1), { items: [] });
    },
  });

  TK_TESTS.push({
    name: 'fx sync and draw show one object per planned item, place a ground ring at its radius, and hide the rest',
    fn() {
      const h = handle();
      const world = { items: [], dt: 0.016, now: 20, effects: [ground({ t: 20 }), { kind: 'hit', at: { x: 1, y: 1 }, spellID: 1, t: 20 }] };
      TK.scene3dFx.sync(h, world);
      TK.scene3dFx.draw(h);
      A.eq(shown(h), 2, 'a ground ring and a hit flash');
      const ring = fxGroup(h).children.find((node) => node.userData.kind === 'ground');
      A.same([ring.position.x, ring.position.z], [0, -10]);
      A.eq(ring.scale.x, 8, 'ring drawn at the real radius');
      TK.scene3dFx.sync(h, { items: [], dt: 0.016, now: 20.5, effects: [] });
      TK.scene3dFx.draw(h);
      A.eq(shown(h), 0, 'nothing planned, nothing shown');
    },
  });

  TK_TESTS.push({
    name: 'fx sync puts an aura on the actor it afflicts and draw fades with alpha',
    fn() {
      const h = handle();
      const raw = { guid: 'g1', pos: { x: 4, y: 5 } };
      const effects = [{ kind: 'aura', guid: 'g1', spellID: 100, style: 'stun' }, { kind: 'charge', from: { x: 0, y: 0 }, to: { x: 0, y: 8 }, t: 30 }];
      TK.scene3dFx.sync(h, { items: [{ raw, pos: raw.pos, facing: 0 }], dt: 0.016, now: 31, effects });
      TK.scene3dFx.draw(h);
      const stars = fxGroup(h).children.find((node) => node.userData.kind === 'aura' && node.visible);
      A.same([stars.position.x, stars.position.z], [4, -5]);
      const dash = fxGroup(h).children.find((node) => node.userData.kind === 'charge');
      let opacity = 1;
      dash.traverse((node) => {
        if (node.isMesh) opacity = Math.min(opacity, node.material.opacity);
      });
      A.eq(opacity < 0.6, true, 'the dash is faded half way through the ring');
    },
  });

  TK_TESTS.push({
    name: 'fx without WebGL: sync and draw on a handle with no scene throw nothing',
    fn() {
      const dead = { ok: false, notice: 'no gl' };
      TK.scene3dFx.sync(dead, { items: [], dt: 0, now: 1, effects: [ground()] });
      TK.scene3dFx.draw(dead);
      TK.scene3dFx.draw({ ok: true, THREE, scene: new THREE.Scene(), groups: {} });
      A.eq(TK.scene3dFx.plan([ground()], 1).items.length, 1, 'plan still works');
    },
  });
})();
