// Sim actors (viewer/scene3d_models.js, viewer/scene3d_marks.js) and their wiring: model choice, animation state,
// clip matching, on-demand GLB loading, the primitive fallback, marks, TK.scene3d.sync and modelled props.
(function () {
  'use strict';

  const near = (a, b, e = 1e-6) => Math.abs(a - b) < e;

  // 20-byte GLB header + one space-padded JSON chunk, base64.
  function glb(json) {
    const j = new TextEncoder().encode(JSON.stringify(json));
    const n = j.length + ((4 - (j.length % 4)) % 4);
    const bytes = new Uint8Array(20 + n).fill(0x20);
    const v = new DataView(bytes.buffer);
    bytes.set(j, 20);
    [0x46546c67, 2, 20 + n, n, 0x4e4f534a].forEach((x, i) => v.setUint32(4 * i, x, true));

    return { b64: btoa(String.fromCharCode(...bytes)) };
  }

  TK_TESTS.push({
    name: 'models.modelFor by class; variant stable in 0.95..1.05',
    fn() {
      const M = TK.scene3dModels;
      const classes = ['WARRIOR', 'MAGE', 'PRIEST', 'NOTACLASS'];
      A.same(
        classes.map((c) => M.modelFor({ class: c })),
        ['knight', 'mage', 'mage', 'barbarian'],
      );
      A.eq(M.modelFor({ hostile: true }), 'skeleton');
      A.eq(M.variant('g1'), M.variant('g1'), 'stable per guid');
      A.eq(M.variant('g1') >= 0.95, true, 'at least 0.95');
      A.eq(M.variant('g1') <= 1.05, true, 'at most 1.05');
    },
  });

  TK_TESTS.push({
    name: 'models.stateOf: death > attack > cast > hit > run > idle; a position change counts as run',
    fn() {
      const S = TK.scene3dModels.stateOf;
      const p = { pos: { x: 0, y: 0 }, health: 10, swings: 0 };
      const changes = [
        { dead: true, swings: 1, moving: true },
        { swings: 1, casting: {} },
        { casting: {}, health: 5 },
        { health: 5, moving: true },
        { pos: { x: 0, y: 0.5 } },
        {},
      ];
      A.same(
        changes.map((d) => S(p, { ...p, ...d })),
        ['death', 'attack', 'cast', 'hit', 'run', 'idle'],
      );
      A.eq(S(null, { ...p, swings: 3 }), 'idle', 'no previous reply, no one-shot');
    },
  });

  TK_TESTS.push({
    name: 'models.clipFor matches pack names and falls back to the nearest clip (spec R7)',
    fn() {
      const C = TK.scene3dModels.clipFor;
      const names = ['Idle', 'Running_A', '1H_Melee_Attack_Slice_Diagonal', 'Hit_A', 'Death_A'];
      A.same(C('run', names), { name: 'Running_A', exact: true });
      A.same(C('cast', names), { name: '1H_Melee_Attack_Slice_Diagonal', exact: false });
      A.same(C('hit', ['Idle']), { name: 'Idle', exact: false });
      A.eq(C('idle', []), null);
    },
  });

  TK_TESTS.push({
    name: 'models.clipFor on the pack order: death skips the static pose, cast picks the channel',
    fn() {
      const C = TK.scene3dModels.clipFor;
      const pack = ['1H_Ranged_Shoot', 'Death_A', 'Death_A_Pose', 'Idle', 'Spellcast_Shoot', 'Spellcasting'];
      A.eq(C('death', pack.filter((n) => n !== 'Death_A')).name, 'Idle');
      A.eq(C('death', pack).name, 'Death_A');
      A.eq(C('cast', pack).name, 'Spellcasting');
    },
  });

  TK_TESTS.push({
    name: 'models.decode/load: base64 to bytes; one script injection per name; failure gives null',
    async fn() {
      const M = TK.scene3dModels;
      const saved = TK.models;
      let loads = 0;
      A.same(Array.from(new Uint8Array(M.decode(btoa('abc')))), [97, 98, 99]);
      const tiny = glb({ asset: { version: '2.0' }, scenes: [{ nodes: [] }], scene: 0 }).b64;
      const loadScript = () => {
        loads++;
        TK.models = { tiny };

        return Promise.resolve();
      };
      const deps = { THREE, base: 'x/', loadScript };
      try {
        A.eq(!!(await M.load('tiny', deps)).scene, true);
        await M.load('tiny', deps);
        A.eq(loads, 1);
        A.eq(await M.load('nope', { ...deps, loadScript: () => Promise.reject(new Error('404')) }), null);
      } finally {
        TK.models = saved;
      }
    },
  });

  TK_TESTS.push({
    name: 'models.primitive is human height; makeActor one-shots return to base, death clamps',
    fn() {
      const box = new THREE.Box3().setFromObject(TK.scene3dModels.primitive(THREE, { hostile: true }));
      A.eq(box.max.y > 1.6, true, 'taller than 1.6');
      A.eq(box.max.y < 2.0, true, 'shorter than 2.0');
      const clips = ['Idle', 'Attack', 'Death'].map((n) => new THREE.AnimationClip(n, 1, []));
      const a = TK.scene3dModels.makeActor(THREE, { model: { scene: new THREE.Group(), animations: clips } });
      a.setState('attack');
      a.update(0.1);
      A.eq(a.playing(), 'attack');
      a.update(2);
      A.eq(a.playing(), 'idle');
      a.setState('death');
      a.update(5);
      A.eq(a.playing(), 'death');
    },
  });

  TK_TESTS.push({
    name: 'freeMaterials disposes every material of a node and keeps the geometry; actors.free disposes both',
    fn() {
      const disposed = { geometry: 0, materials: 0 };
      const make = () => {
        const materials = [new THREE.MeshBasicMaterial(), new THREE.MeshBasicMaterial()];
        const mesh = new THREE.Mesh(new THREE.BoxGeometry(), materials);
        mesh.geometry.addEventListener('dispose', () => disposed.geometry++);
        mesh.material.forEach((m) => m.addEventListener('dispose', () => disposed.materials++));

        return mesh;
      };
      TK.scene3dModels.freeMaterials(make());
      A.same(disposed, { geometry: 0, materials: 2 });
      TK.scene3dActors.free(make());
      A.same(disposed, { geometry: 1, materials: 4 });
    },
  });

  TK_TESTS.push({
    name: 'marks.flags: ring by reaction, sparkle only on a lootable corpse',
    fn() {
      const K = TK.scene3dMarks;
      A.same([K.flags({ hostile: true }).ring, K.flags({}).ring], [K.RING.hostile, K.RING.friendly]);
      A.same([K.flags({ dead: true, lootable: true }).sparkle, K.flags({ lootable: true }).sparkle], [true, false]);
      A.eq(K.flags({ isTarget: true }).target, true, 'target flag');
      A.eq(K.flags({ isMouseover: true }).hover, true, 'hover flag');
    },
  });

  TK_TESTS.push({
    name: 'marks.apply shows the target ring, hover ring and sparkle only when flagged',
    fn() {
      const m = TK.scene3dMarks.make(THREE);
      const shown = () => m.group.children.map((c) => c.visible);
      m.apply({ isTarget: true, hostile: true }, 0);
      A.same(shown(), [true, false, false]);
      m.apply({ isMouseover: true, dead: true, lootable: true }, 0.5);
      A.same(shown(), [false, true, true]);
    },
  });

  TK_TESTS.push({
    name: 'scene3d.sync: creates, places and removes actors by guid; primitive while the model is pending',
    async fn() {
      let resolve;
      const pending = new Promise((r) => {
        resolve = r;
      });
      const handle = { THREE, groups: { actors: new THREE.Group() }, loadModel: () => pending };
      const item = (guid, x) => ({
        raw: { guid, hostile: true, health: 10 },
        prevRaw: null,
        pos: { x, y: 4 },
        facing: 0,
        isPlayer: false,
      });
      const actors = handle.groups.actors;
      const rows = () => actors.children.map((c) => [c.userData.guid, c.userData.body, c.position.x, c.position.z]);
      TK.scene3d.sync(handle, { items: [item('a', 1), item('b', 2)], dt: 0.016 });
      A.same(rows(), [
        ['a', 'primitive', 1, -4],
        ['b', 'primitive', 2, -4],
      ]);
      A.eq(near(actors.children[0].rotation.y, TK.scene3d.yawOf(0)), true, 'yaw from the facing');
      A.eq(near(actors.children[0].scale.x, TK.scene3dModels.variant('a')), true, 'scale from the variant');
      resolve({ scene: new THREE.Group(), animations: [] });
      await pending;
      TK.scene3d.sync(handle, { items: [item('b', 3)], dt: 0.016 });
      A.same(rows(), [['b', 'skeleton', 3, -4]]);
    },
  });

  TK_TESTS.push({
    name: 'scene3d.sync: a class change under the same guid swaps the model and keeps one actor',
    async fn() {
      const asked = [];
      const loadModel = (name) => {
        asked.push(name);

        return Promise.resolve({ scene: new THREE.Group(), animations: [] });
      };
      const handle = { THREE, groups: { actors: new THREE.Group() }, loadModel };
      const player = (cls) => ({
        raw: { guid: 'Player-1', class: cls, health: 10, swings: 0, pos: { x: 0, y: 0 } },
        prevRaw: null,
        pos: { x: 0, y: 0 },
        facing: 0,
        isPlayer: true,
      });
      const actors = handle.groups.actors;
      const bodies = () => actors.children.map((c) => c.userData.body);
      const settle = () => new Promise((resolve) => setTimeout(resolve, 0));
      TK.scene3d.sync(handle, { items: [player('WARRIOR')], dt: 0 });
      await settle();
      A.same(bodies(), ['knight']);
      TK.scene3d.sync(handle, { items: [player('WARRIOR')], dt: 0 });
      A.same(asked, ['knight'], 'same class: no reload');
      TK.scene3d.sync(handle, { items: [player('MAGE')], dt: 0 });
      A.same(bodies(), ['primitive'], 'new model pending: one stand-in, the knight is gone');
      await settle();
      A.same(bodies(), ['mage']);
      A.same(asked, ['knight', 'mage']);
    },
  });

  TK_TESTS.push({
    name: 'scene3dProps.modelSet fits a loaded tree to the primitive height; a missing rock stays primitive',
    fn() {
      const tall = new THREE.Group();
      tall.add(new THREE.Mesh(new THREE.BoxGeometry(0.5, 1.2, 0.5).translate(0, 0.6, 0)));
      const models = TK.scene3dProps.modelSet(THREE, { tree: { scene: tall }, rock: null });
      const props = TK.scene3dProps.build(THREE, models);
      const first = (kind) => props.children.find((p) => p.userData.kind === kind);
      const row = TK.scene3dProps.LAYOUT[0];
      const height = new THREE.Box3().setFromObject(first('tree')).getSize(new THREE.Vector3()).y;
      A.eq(near(height, TK.scene3dProps.TREE_HEIGHT * row.scale, 0.01), true, 'tree height ' + height);
      A.eq(first('rock').children[0].geometry.type, 'IcosahedronGeometry');
    },
  });
})();
