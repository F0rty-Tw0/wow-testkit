// Fixture for tests/viewer/scene_png.sh: builds the sim scene in #background, waits for the actor, tree and rock models,
// syncs one fixed world, draws once (no rAF) and reports on <body> for tests/viewer/check_scene.py: data-gl ("webgl" or
// "none"), data-drawn (meshes in the scene), data-models (actors wearing a real model, not the capsule), data-done.
(function () {
  'use strict';

  const MODEL_NAMES = ['knight', 'skeleton', 'tree', 'rock'];
  const SETTLE_STEPS = 12;
  const STEP_SECONDS = 0.1;

  const unit = (guid, extra) => ({
    guid, name: guid, kind: 'unit', pos: { x: 0, y: 0 }, facing: 0, health: 100, healthMax: 100, dead: false,
    hostile: false, lootable: false, isTarget: false, isMouseover: false, swings: 0, ...extra,
  });

  const skeleton = (guid, x, y, extra) => unit(guid, { name: 'Skeleton', pos: { x, y }, facing: Math.PI, hostile: true, ...extra });

  // The player at the end of the path, facing the camp (18, 22) across the fight.
  const WORLD = [
    unit('player', { name: 'Knight', class: 'WARRIOR', pos: { x: 4, y: 6 }, facing: -0.5, isPlayer: true }),
    skeleton('skel-target', 7.4, 12.2, { isTarget: true }),
    skeleton('skel-hover', 11, 11, { isMouseover: true }),
    skeleton('skel-corpse', 4.5, 13.5, { dead: true, lootable: true, health: 0 }),
  ];

  const toItem = (raw) => ({ raw, prevRaw: raw, pos: raw.pos, facing: raw.facing, isPlayer: !!raw.isPlayer });

  const frame = (dt) => ({ items: WORLD.map(toItem), dt });

  const nextTick = () => new Promise((resolve) => setTimeout(resolve, 0));

  function countMeshes(scene) {
    let meshes = 0;
    scene.traverse((node) => {
      if (node.isMesh) meshes++;
    });

    return meshes;
  }

  function countModelActors(handle) {
    const actors = handle.groups.actors.children;

    return actors.filter((actor) => actor.userData.body !== 'primitive').length;
  }

  async function run(body) {
    const handle = TK.scene3d.create(document.getElementById('background'), { THREE: window.THREE });
    if (!handle.ok) {
      body.dataset.gl = 'none';

      return;
    }
    await Promise.all(MODEL_NAMES.map(handle.loadModel));
    await nextTick();
    TK.scene3d.sync(handle, frame(0));
    await nextTick();
    for (let i = 0; i < SETTLE_STEPS; i++) TK.scene3d.sync(handle, frame(STEP_SECONDS));
    const player = toItem(WORLD[0]);
    handle.draw(TK.scene3dInput.cameraPose(player, TK.scene3dInput.CAM_DEFAULT));
    body.dataset.gl = 'webgl';
    body.dataset.drawn = String(countMeshes(handle.scene));
    body.dataset.models = String(countModelActors(handle));
  }

  const body = document.body;
  run(body)
    .catch((error) => {
      body.dataset.error = String(error && error.stack ? error.stack : error);
    })
    .finally(() => {
      body.dataset.done = '1';
    });
})();
