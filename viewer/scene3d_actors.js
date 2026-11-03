// Sim actors in the 3D scene: TK.scene3dActors.sync(handle, frame) keeps one actor per world entry under
// handle.groups.actors, keyed by guid. A new actor stands as TK.scene3dModels.primitive while handle.loadModel(name) is
// pending or failed, then becomes the animated model; each carries its TK.scene3dMarks. Actors missing from the frame
// are removed and disposed. TK.scene3d.sync is this function, and TK.scene3d.toScene / yawOf are the two coordinate
// maps below, which live here so scene3d.js depends on this file and not the other way round. Classic script;
// tests/viewer/unit_sim_models.js.
window.TK = window.TK || {};

(function (TK) {
  'use strict';

  const synced = new WeakMap();

  // A sim point to a three.js point: east stays x, north becomes -z, `up` is the height.
  const toScene = (pos, up = 0) => ({ x: pos.x, y: up, z: -pos.y });

  // The y rotation that turns a model facing +z to the sim facing.
  const yawOf = (facing) => facing + Math.PI;

  // Disposes a node's geometry and materials.
  function free(node) {
    if (node.geometry) node.geometry.dispose();
    TK.scene3dModels.freeMaterials(node);
  }

  function stillBody(T, hostile) {
    const group = TK.scene3dModels.primitive(T, { hostile });

    return { group, setState() {}, update() {}, playing: () => null, dispose: () => group.traverse(free) };
  }

  function swapBody(T, entry, model, name) {
    if (!model || entry.gone) return;
    const actor = TK.scene3dModels.makeActor(T, { model });
    entry.root.remove(entry.body.group);
    entry.body.dispose();
    entry.body = actor;
    entry.root.add(actor.group);
    entry.root.userData.body = name;
    actor.setState(entry.state);
  }

  function spawn(T, handle, raw) {
    const name = TK.scene3dModels.modelFor(raw);
    const root = new T.Group();
    const marks = TK.scene3dMarks.make(T);
    const body = stillBody(T, raw.hostile);
    const entry = { root, marks, raw: null, state: 'idle', body, model: name, gone: false };
    root.userData = { guid: raw.guid, body: 'primitive' };
    root.add(entry.body.group, marks.group);
    handle.loadModel(name).then((model) => swapBody(T, entry, model, name));

    return entry;
  }

  // State changes only on a new reply, so a one-shot plays once per swing or hit, not once per drawn frame.
  function place(entry, item, clock) {
    const p = toScene(item.pos);
    entry.root.position.set(p.x, p.y, p.z);
    entry.root.rotation.y = yawOf(item.facing);
    entry.root.scale.setScalar(TK.scene3dModels.variant(item.raw.guid));
    if (item.raw !== entry.raw) {
      entry.raw = item.raw;
      entry.state = TK.scene3dModels.stateOf(item.prevRaw, item.raw);
      entry.body.setState(entry.state);
    }
    entry.body.update(clock.dt);
    entry.marks.apply(item.raw, clock.time, entry.body.group);
  }

  function drop(entry) {
    entry.gone = true;
    entry.root.removeFromParent();
    entry.body.dispose();
    entry.root.remove(entry.body.group);
    entry.root.traverse(free);
  }

  // The actor for a world entry; one wearing another model than modelFor(raw) now picks (a class change keeps the guid)
  // is dropped and spawned again.
  function entryFor(T, handle, own, raw) {
    const held = own.actors.get(raw.guid);
    if (held && held.model === TK.scene3dModels.modelFor(raw)) return held;
    if (held) drop(held);
    const entry = spawn(T, handle, raw);
    own.actors.set(raw.guid, entry);

    return entry;
  }

  // frame = { items: [{ raw, prevRaw, pos, facing, isPlayer }], dt }: pos and facing are interpolated, raw and prevRaw
  // the latest two world entries.
  function sync(handle, frame) {
    const T = handle.THREE;
    const own = synced.get(handle) || { actors: new Map(), time: 0 };
    const seen = new Set();
    synced.set(handle, own);
    own.time += frame.dt;
    const clock = { dt: frame.dt, time: own.time };
    frame.items.forEach((item) => {
      const guid = item.raw.guid;
      seen.add(guid);
      const entry = entryFor(T, handle, own, item.raw);
      handle.groups.actors.add(entry.root);
      place(entry, item, clock);
    });
    own.actors.forEach((entry, guid) => {
      if (seen.has(guid)) return;
      drop(entry);
      own.actors.delete(guid);
    });
  }

  TK.scene3dActors = { free, sync, toScene, yawOf };
})(window.TK);
