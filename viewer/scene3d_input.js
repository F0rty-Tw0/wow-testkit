// Sim input maths: the follow camera (orbit, zoom), the ray under a screen pixel and what it hits (an actor or the
// ground). Sim coordinates throughout: pos { x, y } yards, +x east, +y north, z up; facing 0 = north, counter-clockwise,
// forward (-sin f, cos f). TK.scene3dInput.pointerDeps(state) gives TK.pointer.attach its world/claim/afterWheel deps;
// attachCamera orbits while a claimed press is held. Classic script; the maths is pure and checked by
// tests/viewer/unit_sim_input.js, attachCamera and pointerDeps by event there.
window.TK = window.TK || {};

(function (TK) {
  'use strict';

  const CAM_DEFAULT = { yaw: 0, pitch: 0.4, dist: 15 };
  const EYE_HEIGHT = 1.5;
  const ZOOM_STEP = 1.1;
  const ORBIT_RATE = 0.005;
  const LIVING_SPHERES = [{ z: 0.6, r: 0.7 }, { z: 1.2, r: 0.7 }, { z: 1.8, r: 0.7 }];
  const DEAD_SPHERES = [{ z: 0.3, r: 0.9 }];

  const { clamp } = TK.scene3d;
  const dot = (a, b) => a.x * b.x + a.y * b.y + a.z * b.z;
  const sub = (a, b) => ({ x: a.x - b.x, y: a.y - b.y, z: a.z - b.z });
  const cross = (a, b) => ({ x: a.y * b.z - a.z * b.y, y: a.z * b.x - a.x * b.z, z: a.x * b.y - a.y * b.x });
  const norm = (v) => {
    const len = Math.hypot(v.x, v.y, v.z);

    return { x: v.x / len, y: v.y / len, z: v.z / len };
  };

  function cameraPose(player, cam) {
    const angle = player.facing + cam.yaw;
    const reach = cam.dist * Math.cos(cam.pitch);
    const eye = {
      x: player.pos.x + Math.sin(angle) * reach,
      y: player.pos.y - Math.cos(angle) * reach,
      z: EYE_HEIGHT + cam.dist * Math.sin(cam.pitch),
    };
    const target = { x: player.pos.x, y: player.pos.y, z: EYE_HEIGHT };

    return { eye, target };
  }

  function zoom(cam, wheelDelta) {
    const factor = wheelDelta > 0 ? 1 / ZOOM_STEP : ZOOM_STEP;
    cam.dist = clamp(cam.dist * factor, 5, 40);

    return cam;
  }

  function orbit(cam, dx, dy) {
    cam.yaw += dx * ORBIT_RATE;
    cam.pitch = clamp(cam.pitch - dy * ORBIT_RATE, 0.1, 1.4);

    return cam;
  }

  const isOrbit = (ev) => ev.button === 1 || (ev.button === 0 && Boolean(ev.altKey));

  // The ray through a screen pixel's centre; o is the eye, d a unit direction.
  function rayFromScreen(point, screen, pose, fovDeg = TK.scene3d.FOV) {
    const forward = norm(sub(pose.target, pose.eye));
    const right = norm({ x: forward.y, y: -forward.x, z: 0 });
    const up = cross(right, forward);
    const half = Math.tan((fovDeg * Math.PI) / 360);
    const nx = ((point.x + 0.5) / screen.width) * 2 - 1;
    const ny = 1 - ((point.y + 0.5) / screen.height) * 2;
    const across = nx * half * (screen.width / screen.height);
    const down = ny * half;
    const d = norm({
      x: forward.x + right.x * across + up.x * down,
      y: forward.y + right.y * across + up.y * down,
      z: forward.z + right.z * across + up.z * down,
    });

    return { o: { ...pose.eye }, d };
  }

  function groundAt(ray) {
    if (ray.d.z >= 0) return null;
    const t = -ray.o.z / ray.d.z;
    const hit = { x: ray.o.x + ray.d.x * t, y: ray.o.y + ray.d.y * t };
    const half = TK.scene3d.SIZE / 2;
    const onMap = Math.abs(hit.x) <= half && Math.abs(hit.y) <= half;

    return onMap ? hit : null;
  }

  // Distance along the ray to a sphere, or Infinity on a miss.
  function sphereHit(ray, centre, r) {
    const oc = { x: ray.o.x - centre.x, y: ray.o.y - centre.y, z: ray.o.z - centre.z };
    const b = dot(oc, ray.d);
    const disc = b * b - (dot(oc, oc) - r * r);
    if (disc < 0) return Infinity;
    const near = -b - Math.sqrt(disc);
    const far = -b + Math.sqrt(disc);
    const t = near >= 0 ? near : far;

    return t >= 0 ? t : Infinity;
  }

  function actorHit(ray, actor) {
    const spheres = actor.dead ? DEAD_SPHERES : LIVING_SPHERES;
    const hits = spheres.map((s) => sphereHit(ray, { x: actor.pos.x, y: actor.pos.y, z: s.z }, s.r));

    return Math.min(...hits);
  }

  function pickActor(ray, actors) {
    let best = null;
    let bestT = Infinity;
    for (const actor of actors) {
      const t = actorHit(ray, actor);
      if (t >= bestT) continue;
      best = actor.guid;
      bestT = t;
    }

    return best;
  }

  function worldFor(point, screen, pose, actors) {
    const ray = rayFromScreen(point, screen, pose);
    const guid = pickActor(ray, actors);
    const ground = groundAt(ray);
    if (!guid && !ground) return null;
    const world = {};
    if (guid) world.guid = guid;
    if (ground) world.ground = ground;

    return world;
  }

  // state = { screen(), pose(), actors(), cam, repaint() }; a wheel no frame answered zooms the camera.
  function pointerDeps(state) {
    return {
      world: (point) => worldFor(point, state.screen(), state.pose(), state.actors()),
      claim: isOrbit,
      afterWheel(reply, ev) {
        if (!reply || reply.target) return;
        zoom(state.cam, TK.pointer.wheelDelta(ev));
        state.repaint();
      },
    };
  }

  // Orbits cam while a press that isOrbit is held; move and release are watched on win so the drag can leave the stage.
  function attachCamera(stage, win, cam, repaint) {
    let last = null;
    stage.addEventListener('mousedown', (ev) => {
      last = isOrbit(ev) ? { x: ev.clientX, y: ev.clientY } : null;
    });
    win.addEventListener('mousemove', (ev) => {
      if (!last) return;
      orbit(cam, ev.clientX - last.x, ev.clientY - last.y);
      last = { x: ev.clientX, y: ev.clientY };
      repaint();
    });
    win.addEventListener('mouseup', () => {
      last = null;
    });
  }

  TK.scene3dInput = {
    CAM_DEFAULT,
    cameraPose,
    zoom,
    orbit,
    isOrbit,
    rayFromScreen,
    groundAt,
    pickActor,
    worldFor,
    pointerDeps,
    attachCamera,
  };
})(window.TK);
