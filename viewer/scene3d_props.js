// Props of the sim scene: TK.scene3dProps.LAYOUT is the fixed placement table (yards, +x east, +y north, rot in
// radians about the vertical, scale 1 = the primitive's world size), build(T, models) the three.js Group with one child
// per row. Trees, rocks and bushes ring the edges (max(|x|, |y|) >= 36) and leave the south path (x = 0) open; the camp
// sits within 8 yd of TK.scene3d.CAMP (18, 22) and nothing stands within 4 yd of spawn (0, -10). A row whose kind the
// optional models table has becomes a clone of that model; camp pieces are always primitives. modelSet(T, loaded) makes
// that table from loaded { tree, rock } models (null ones skipped), each fitted to its primitive's world size: a tree
// TREE_HEIGHT tall, a rock 1.5 yd wide. Classic script; the layout is pure data for tests/viewer/unit_sim_scene.js,
// modelSet is checked by tests/viewer/unit_sim_models.js.
window.TK = window.TK || {};

(function (TK) {
  'use strict';

  const CAMP_KINDS = ['tent', 'crate', 'fire'];
  const TREE_HEIGHT = 5.6;
  const ROCK_WIDTH = 1.5;

  const LAYOUT = [
    { kind: 'tree', x: -42, y: 44, rot: 0.3, scale: 1.1 },
    { kind: 'tree', x: -30, y: 41, rot: 1.9, scale: 0.9 },
    { kind: 'tree', x: -17, y: 46, rot: 4.0, scale: 1.2 },
    { kind: 'tree', x: -5, y: 40, rot: 2.6, scale: 1.0 },
    { kind: 'tree', x: 8, y: 44, rot: 5.1, scale: 1.3 },
    { kind: 'tree', x: 22, y: 42, rot: 0.8, scale: 0.95 },
    { kind: 'tree', x: 34, y: 46, rot: 3.3, scale: 1.15 },
    { kind: 'tree', x: 45, y: 39, rot: 1.2, scale: 1.0 },
    { kind: 'tree', x: 43, y: 27, rot: 4.6, scale: 1.25 },
    { kind: 'tree', x: 40, y: 12, rot: 2.2, scale: 0.9 },
    { kind: 'tree', x: 46, y: -4, rot: 0.5, scale: 1.1 },
    { kind: 'tree', x: 41, y: -20, rot: 3.8, scale: 1.0 },
    { kind: 'tree', x: 44, y: -34, rot: 5.6, scale: 1.2 },
    { kind: 'tree', x: -44, y: 30, rot: 2.9, scale: 1.0 },
    { kind: 'tree', x: -40, y: 16, rot: 1.5, scale: 1.3 },
    { kind: 'tree', x: -46, y: 2, rot: 4.4, scale: 0.9 },
    { kind: 'tree', x: -41, y: -14, rot: 0.1, scale: 1.15 },
    { kind: 'tree', x: -45, y: -28, rot: 3.1, scale: 1.05 },
    { kind: 'tree', x: -38, y: -43, rot: 5.0, scale: 1.2 },
    { kind: 'tree', x: -24, y: -40, rot: 2.0, scale: 0.95 },
    { kind: 'tree', x: -12, y: -45, rot: 0.7, scale: 1.1 },
    { kind: 'tree', x: 12, y: -42, rot: 3.6, scale: 1.0 },
    { kind: 'tree', x: 26, y: -46, rot: 1.0, scale: 1.25 },
    { kind: 'tree', x: 38, y: -40, rot: 4.8, scale: 0.9 },
    { kind: 'rock', x: -36, y: 38, rot: 0.4, scale: 1.4 },
    { kind: 'rock', x: 30, y: -38, rot: 2.3, scale: 1.0 },
    { kind: 'rock', x: -47, y: -44, rot: 1.7, scale: 1.8 },
    { kind: 'rock', x: 47, y: 47, rot: 3.9, scale: 1.5 },
    { kind: 'rock', x: -8, y: -38, rot: 5.2, scale: 0.8 },
    { kind: 'rock', x: 38, y: 1, rot: 0.9, scale: 1.2 },
    { kind: 'bush', x: -38, y: 8, rot: 0.0, scale: 1.2 },
    { kind: 'bush', x: 38, y: -12, rot: 1.0, scale: 1.0 },
    { kind: 'bush', x: 14, y: 38, rot: 2.0, scale: 1.3 },
    { kind: 'bush', x: -20, y: -38, rot: 3.0, scale: 0.9 },
    { kind: 'bush', x: -48, y: 46, rot: 4.0, scale: 1.1 },
    { kind: 'bush', x: 6, y: -38, rot: 5.0, scale: 1.0 },
    { kind: 'tent', x: 22, y: 26, rot: 0.6, scale: 1.0 },
    { kind: 'tent', x: 13, y: 25, rot: 5.4, scale: 0.9 },
    { kind: 'crate', x: 22, y: 18.5, rot: 0.3, scale: 1.0 },
    { kind: 'crate', x: 23.1, y: 19.4, rot: 1.1, scale: 0.8 },
    { kind: 'crate', x: 12.5, y: 21, rot: 0.8, scale: 1.0 },
    { kind: 'fire', x: 18, y: 22, rot: 0.0, scale: 1.0 },
  ];

  function material(T, color, extra) {
    const options = Object.assign({ color, roughness: 0.9, flatShading: true }, extra);

    return new T.MeshStandardMaterial(options);
  }

  function mesh(T, geometry, mat, up) {
    const out = new T.Mesh(geometry, mat);
    out.position.y = up;
    out.castShadow = true;
    out.receiveShadow = true;

    return out;
  }

  function tree(T) {
    const trunk = mesh(T, new T.CylinderGeometry(0.22, 0.32, 1.6, 7), material(T, 0x6b4a2f), 0.8);
    const crown = mesh(T, new T.ConeGeometry(1.6, 3.8, 8), material(T, 0x2f6b34), 1.6 + 1.9);
    const top = mesh(T, new T.ConeGeometry(1.1, 2.4, 8), material(T, 0x3a7d3c), 4.4);

    return [trunk, crown, top];
  }

  function fire(T) {
    const glow = { emissive: 0xff7a1a, emissiveIntensity: 1.6 };
    const flame = mesh(T, new T.ConeGeometry(0.35, 0.9, 6), material(T, 0xffa040, glow), 0.45);
    const logs = mesh(T, new T.CylinderGeometry(0.6, 0.7, 0.15, 8), material(T, 0x4a3322), 0.07);
    const light = new T.PointLight(0xff9a40, 12, 14, 1.5);
    flame.castShadow = false;
    light.position.y = 1.1;

    return [logs, flame, light];
  }

  function primitive(T, kind) {
    if (kind === 'tree') return tree(T);
    if (kind === 'fire') return fire(T);
    if (kind === 'rock') return [mesh(T, new T.IcosahedronGeometry(0.75, 0), material(T, 0x84807a), 0.35)];
    if (kind === 'bush') return [mesh(T, new T.SphereGeometry(0.75, 9, 6), material(T, 0x3d7a33), 0.5)];
    if (kind === 'tent') return [mesh(T, new T.ConeGeometry(1.8, 2.4, 4), material(T, 0xc8b48a), 1.2)];

    return [mesh(T, new T.BoxGeometry(0.8, 0.8, 0.8), material(T, 0x9a6b3c), 0.4)];
  }

  function piece(T, row, models) {
    const modelled = models && models.has(row.kind) && !CAMP_KINDS.includes(row.kind);
    const parts = modelled ? [models.clone(row.kind)] : primitive(T, row.kind);
    const out = new T.Group();
    out.add(...parts);
    out.position.set(row.x, 0, -row.y);
    out.rotation.y = row.rot;
    out.scale.setScalar(row.scale);
    out.userData.kind = row.kind;

    return out;
  }

  function build(T, models) {
    const group = new T.Group();
    const pieces = LAYOUT.map((row) => piece(T, row, models));
    group.name = 'props';
    group.add(...pieces);

    return group;
  }

  // The vendored tree and rock are tiny hex-tile props (about 1.2 and 0.07 units tall), so each is scaled to the size
  // of the primitive it replaces, measured once on the loaded scene.
  function fit(T, scene, kind) {
    const size = new T.Box3().setFromObject(scene).getSize(new T.Vector3());
    const span = kind === 'tree' ? size.y : Math.max(size.x, size.z);
    const target = kind === 'tree' ? TREE_HEIGHT : ROCK_WIDTH;
    const out = scene.clone();
    out.scale.multiplyScalar(span > 0 ? target / span : 1);
    out.traverse((node) => {
      node.castShadow = node.isMesh;
      node.receiveShadow = node.isMesh;
    });

    return out;
  }

  function modelSet(T, loaded) {
    const fitted = {};
    Object.keys(loaded).forEach((kind) => {
      if (loaded[kind]) fitted[kind] = fit(T, loaded[kind].scene, kind);
    });
    const out = { has: (kind) => kind in fitted, clone: (kind) => fitted[kind].clone() };

    return out;
  }

  TK.scene3dProps = { LAYOUT, TREE_HEIGHT, build, modelSet };
})(window.TK);
