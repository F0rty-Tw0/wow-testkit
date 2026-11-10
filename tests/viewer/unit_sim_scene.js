// The static sim scene (viewer/scene3d.js, viewer/scene3d_props.js): coordinate mapping, terrain colour, prop layout,
// the built scene graph and the WebGL-less fallback.
(function () {
  'use strict';

  const near = (a, b, e = 1e-6) => Math.abs(a - b) < e;

  TK_TESTS.push({
    name: 'scene3d.toScene maps east,north to three x,-z; yawOf points a +z model along the kit forward',
    fn() {
      A.same(
        [TK.scene3d.toScene({ x: 3, y: 4 }), TK.scene3d.toScene({ x: 3, y: 4 }, 1.5)],
        [
          { x: 3, y: 0, z: -4 },
          { x: 3, y: 1.5, z: -4 },
        ],
      );
      for (const f of [0, 1, Math.PI / 2, 4]) {
        const ry = TK.scene3d.yawOf(f);
        // kit forward (−sin f, cos f) = three (x, z) (−sin f, −cos f)
        A.eq(near(Math.sin(ry), -Math.sin(f)), true, 'facing ' + f + ' x');
        A.eq(near(Math.cos(ry), -Math.cos(f)), true, 'facing ' + f + ' z');
      }
    },
  });

  TK_TESTS.push({
    name: 'scene3d.toScene and yawOf are the actors module, which depends on nothing of scene3d',
    fn() {
      const actors = TK.scene3dActors;
      A.eq(TK.scene3d.toScene, actors.toScene, 'toScene');
      A.eq(TK.scene3d.yawOf, actors.yawOf, 'yawOf');
      const scene3d = TK.scene3d;
      TK.scene3d = undefined;
      try {
        const handle = { THREE, groups: { actors: new THREE.Group() }, loadModel: () => new Promise(() => {}) };
        const raw = { guid: 'g', hostile: true, health: 1 };
        actors.sync(handle, { items: [{ raw, prevRaw: null, pos: { x: 1, y: 2 }, facing: 0 }], dt: 0 });
        A.eq(handle.groups.actors.children[0].position.z, -2, 'placed with no TK.scene3d present');
      } finally {
        TK.scene3d = scene3d;
      }
    },
  });

  TK_TESTS.push({
    name: 'scene3d.sync syncs the actors, then the spell effects; draw draws them; a page without the effects module still syncs actors',
    fn() {
      const note = document.createElement('div');
      const fake = {
        domElement: document.createElement('canvas'),
        setSize() {},
        setPixelRatio() {},
        shadowMap: {},
        render() {},
      };
      const view = TK.scene3d.create(note, { THREE, makeRenderer: () => fake, loadModel: () => new Promise(() => {}) });
      const raw = { guid: 'g', hostile: true, health: 1 };
      const effects = [{ kind: 'ground', at: { x: 0, y: 5 }, radius: 4, spellID: 1 }];
      const frame = { items: [{ raw, prevRaw: null, pos: { x: 1, y: 2 }, facing: 0 }], dt: 0, effects, now: 3 };
      TK.scene3d.sync(view, frame);
      view.draw({ eye: { x: 0, y: -25, z: 8 }, target: { x: 0, y: 0, z: 1.5 } });
      const fx = view.scene.children.find((node) => node.name === 'fx');
      A.eq(view.groups.actors.children.length, 1, 'the actor');
      A.eq(fx.children.filter((node) => node.visible).length, 1, 'the ground ring, drawn by view.draw');
      const fxModule = TK.scene3dFx;
      TK.scene3dFx = undefined;
      try {
        TK.scene3d.sync(view, { ...frame, items: [] });
        view.draw({ eye: { x: 0, y: -25, z: 8 }, target: { x: 0, y: 0, z: 1.5 } });
        A.eq(view.groups.actors.children.length, 0, 'the actor left');
      } finally {
        TK.scene3dFx = fxModule;
      }
    },
  });

  TK_TESTS.push({
    name: 'scene3d.terrainColor is deterministic, green off the path, brown on it',
    fn() {
      const grass = TK.scene3d.terrainColor(-30, 10);
      const dirt = TK.scene3d.terrainColor(0, -30);
      A.same(grass, TK.scene3d.terrainColor(-30, 10));
      A.eq(grass[1] > grass[0], true, 'grass is green over red');
      A.eq(dirt[0] >= dirt[1], true, 'dirt is red over green');
      A.eq(dirt[1] > dirt[2], true, 'dirt is green over blue');
    },
  });

  TK_TESTS.push({
    name: 'scene3dProps.LAYOUT: spawn clear, edges planted, camp together, camp has tent+crate+fire',
    fn() {
      const L = TK.scene3dProps.LAYOUT;
      const edge = ['tree', 'rock', 'bush'];
      const camp = ['tent', 'crate', 'fire'];
      const inMap = (p) => Math.abs(p.x) <= 50 && Math.abs(p.y) <= 50;
      const clearOfSpawn = (p) => Math.hypot(p.x, p.y + 10) >= 4;
      const nearCamp = (p) => Math.hypot(p.x - 18, p.y - 22) <= 8;
      A.eq(L.length >= 20, true, 'at least 20 props');
      A.eq(L.every(inMap), true, 'every prop inside the map');
      A.eq(L.every(clearOfSpawn), true, 'spawn clear');
      A.eq(
        L.filter((p) => edge.includes(p.kind)).every((p) => Math.max(Math.abs(p.x), Math.abs(p.y)) >= 36),
        true,
        'edge props at the edge',
      );
      A.eq(L.filter((p) => camp.includes(p.kind)).every(nearCamp), true, 'camp props together');
      A.eq(
        camp.every((k) => L.some((p) => p.kind === k)),
        true,
        'camp has tent, crate and fire',
      );
    },
  });

  TK_TESTS.push({
    name: 'scene3d.build: fog, both lights with shadows, coloured 51x51 terrain, one prop per row (primitives)',
    fn() {
      const { scene, groups } = TK.scene3d.build(THREE);
      const geo = groups.terrain.children[0].geometry;
      A.eq(scene.fog instanceof THREE.Fog, true, 'fog');
      A.eq(scene.children.some((c) => c.isHemisphereLight), true, 'hemisphere light');
      A.eq(scene.children.some((c) => c.isDirectionalLight && c.castShadow), true, 'shadow-casting sun');
      A.eq(geo.attributes.position.count, 51 * 51, 'terrain vertices');
      A.eq(!!geo.attributes.color, true, 'vertex colours');
      A.eq(groups.props.children.length, TK.scene3dProps.LAYOUT.length, 'one prop per row');
    },
  });

  TK_TESTS.push({
    name: 'scene3d.create: no WebGL gives a notice and no throw; with a renderer draw renders once',
    fn() {
      const note = document.createElement('div');
      const makeRenderer = () => {
        throw new Error('no gl');
      };
      const bad = TK.scene3d.create(document.createElement('div'), { THREE, noticeEl: note, makeRenderer });
      A.eq(bad.ok, false, 'create reports not ok');
      A.eq(/3D view unavailable/.test(note.textContent), true, 'notice text');
      let renders = 0;
      const fake = {
        domElement: document.createElement('canvas'),
        setSize() {},
        setPixelRatio() {},
        shadowMap: {},
        render() {
          renders++;
        },
      };
      const view = TK.scene3d.create(document.createElement('div'), { THREE, makeRenderer: () => fake });
      view.draw({ eye: { x: 0, y: -25, z: 8 }, target: { x: 0, y: 0, z: 1.5 } });
      A.eq(renders, 1);
    },
  });
})();
