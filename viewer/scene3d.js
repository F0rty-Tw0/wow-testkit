// The static 3D world behind the UI stage in sim mode. Sim positions are yards (+x east, +y north, facing 0 = north,
// counter-clockwise); three.js is y-up, so TK.scene3d.toScene maps a sim point to (x, up, -y). build(T) makes the scene
// graph: gradient sky dome, hemisphere and shadow-casting sun, fog, a 100 x 100 yd vertex-coloured terrain with a dirt
// path from the south edge past spawn (0, -10) to the camp, and the props of viewer/scene3d_props.js. create(container,
// deps) puts a renderer canvas in container (#background) and returns draw(cameraPose) / dispose plus the scene, its
// groups and loadModel(name), or a notice when WebGL or three.js is missing; it loads the tree and rock models itself
// and swaps the props to them once both settle. toScene, yawOf and sync(handle, frame) are viewer/scene3d_actors.js,
// which loads first. Nothing here runs on page load; the sim loop calls create and sync. Classic script; the pure parts
// are checked by tests/viewer/unit_sim_scene.js and tests/viewer/unit_sim_models.js.
window.TK = window.TK || {};

(function (TK) {
  'use strict';

  const { toScene, yawOf, sync, free } = TK.scene3dActors;
  const CAMP = { x: 18, y: 22 };
  const PATH = [{ x: 0, y: -50 }, { x: 0, y: -10 }, CAMP];
  const NOTICE = '3D view unavailable: WebGL or three.js missing';
  const SIZE = 100;
  const FOV = 50;
  const SEGMENTS = 50;
  const PATH_HALF_WIDTH = 1.4;
  const PATH_EDGE = 1.6;
  const CLEARING = 5;
  const GRASS = [0.3, 0.47, 0.19];
  const GRASS_FAR = [0.29, 0.45, 0.2];
  const DIRT = [0.47, 0.36, 0.23];
  const SKY_TOP = [0.32, 0.55, 0.86];
  const SKY_HORIZON = [0.78, 0.86, 0.9];
  const PROP_MODELS = ['tree', 'rock'];

  const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));

  // A repeatable value in [0, 1) for a point (sine hash; no Math.random so every load looks the same).
  function hash(x, y) {
    const s = Math.sin(x * 127.1 + y * 311.7) * 43758.5453;

    return s - Math.floor(s);
  }

  function segmentDistance(p, a, b) {
    const dx = b.x - a.x;
    const dy = b.y - a.y;
    const along = ((p.x - a.x) * dx + (p.y - a.y) * dy) / (dx * dx + dy * dy);
    const t = clamp(along, 0, 1);

    return Math.hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy));
  }

  // Yards from the trodden ground: the path polyline, or the edge of the camp clearing.
  function dirtDistance(x, y) {
    const p = { x, y };
    const legs = PATH.slice(1).map((b, i) => segmentDistance(p, PATH[i], b));
    const clearing = Math.hypot(x - CAMP.x, y - CAMP.y) - CLEARING;

    return Math.min(clearing, ...legs);
  }

  const mix = (a, b, t) => a.map((v, i) => v + (b[i] - v) * t);

  function terrainColor(x, y) {
    const speck = hash(x, y);
    const patch = 0.5 + 0.25 * (Math.sin(x * 0.13 + y * 0.04) + Math.cos(y * 0.11 - x * 0.06));
    const green = GRASS[1] - 0.06 + 0.1 * patch + 0.04 * speck;
    const grass = [GRASS[0] - 0.05 + 0.08 * patch, green, GRASS[2] + 0.04 * speck];
    const dirt = DIRT.map((v) => v * (0.9 + 0.15 * speck));
    const worn = 1 - (dirtDistance(x, y) - PATH_HALF_WIDTH) / PATH_EDGE;
    const t = clamp(worn, 0, 1);

    return mix(grass, dirt, t);
  }

  function linear(T, rgb) {
    const color = new T.Color().setRGB(rgb[0], rgb[1], rgb[2], T.SRGBColorSpace);

    return [color.r, color.g, color.b];
  }

  function sky(T) {
    const geometry = new T.SphereGeometry(400, 32, 16);
    const pos = geometry.attributes.position;
    const colors = [];
    for (let i = 0; i < pos.count; i++) {
      const height = Math.max(0, pos.getY(i) / 400);
      colors.push(...linear(T, mix(SKY_HORIZON, SKY_TOP, Math.pow(height, 0.6))));
    }
    geometry.setAttribute('color', new T.Float32BufferAttribute(colors, 3));
    const options = { vertexColors: true, side: T.BackSide, fog: false, depthWrite: false };

    return new T.Mesh(geometry, new T.MeshBasicMaterial(options));
  }

  function ground(T) {
    const geometry = new T.PlaneGeometry(SIZE, SIZE, SEGMENTS, SEGMENTS).rotateX(-Math.PI / 2);
    const pos = geometry.attributes.position;
    const colors = [];
    for (let i = 0; i < pos.count; i++) colors.push(...linear(T, terrainColor(pos.getX(i), -pos.getZ(i))));
    geometry.setAttribute('color', new T.Float32BufferAttribute(colors, 3));
    const out = new T.Mesh(geometry, new T.MeshStandardMaterial({ vertexColors: true, roughness: 1 }));
    out.receiveShadow = true;

    return out;
  }

  // Grass past the play square out to the fog, so the horizon is land rather than sky.
  function outskirts(T) {
    const geometry = new T.PlaneGeometry(800, 800).rotateX(-Math.PI / 2);
    const color = new T.Color().setRGB(GRASS_FAR[0], GRASS_FAR[1], GRASS_FAR[2], T.SRGBColorSpace);
    const out = new T.Mesh(geometry, new T.MeshStandardMaterial({ color, roughness: 1 }));
    out.position.y = -0.02;
    out.receiveShadow = true;

    return out;
  }

  function sun(T) {
    const light = new T.DirectionalLight(0xfff1d6, 2.6);
    const cam = light.shadow.camera;
    light.position.set(35, 60, 25);
    light.castShadow = true;
    light.shadow.mapSize.set(2048, 2048);
    light.shadow.bias = -0.0005;
    Object.assign(cam, { left: -60, right: 60, top: 60, bottom: -60, near: 1, far: 200 });
    cam.updateProjectionMatrix();

    return light;
  }

  function build(T) {
    const scene = new T.Scene();
    const horizon = new T.Color().setRGB(SKY_HORIZON[0], SKY_HORIZON[1], SKY_HORIZON[2], T.SRGBColorSpace);
    const terrain = new T.Group();
    const props = TK.scene3dProps.build(T);
    const actors = new T.Group();
    const hemi = new T.HemisphereLight(0xd6e8ff, 0x4d5a30, 1.4);
    scene.fog = new T.Fog(horizon, 45, 170);
    terrain.name = 'terrain';
    actors.name = 'actors';
    terrain.add(ground(T), outskirts(T));
    scene.add(sky(T), hemi, sun(T), terrain, props, actors);
    const groups = { terrain, props, actors };

    return { scene, groups };
  }

  function unavailable(noticeEl) {
    if (noticeEl) {
      noticeEl.textContent = NOTICE;
      noticeEl.hidden = false;
    }

    return { ok: false, notice: NOTICE };
  }

  function makeRenderer(T, deps) {
    if (!T) return null;
    try {
      if (deps.makeRenderer) return deps.makeRenderer(T);

      return new T.WebGLRenderer({ antialias: true });
    } catch {
      return null;
    }
  }

  function watchViewport(resize) {
    const viewport = document.getElementById('viewport');
    if (!viewport || typeof ResizeObserver !== 'function') return null;
    const observer = new ResizeObserver((entries) => {
      const box = entries[0].contentRect;
      resize(box.width, box.height);
    });
    observer.observe(viewport);

    return observer;
  }

  function create(container, deps) {
    const T = deps.THREE;
    const renderer = makeRenderer(T, deps);
    if (!renderer) return unavailable(deps.noticeEl);
    const { scene, groups } = build(T);
    const loadModel = deps.loadModel || ((name) => TK.scene3dModels.load(name, { THREE: T }));
    const camera = new T.PerspectiveCamera(FOV, 1, 0.1, 1000);
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
    renderer.shadowMap.enabled = true;
    renderer.shadowMap.type = T.PCFSoftShadowMap;
    container.appendChild(renderer.domElement);

    function resize(w, h) {
      if (!(w > 0 && h > 0)) return;
      renderer.setSize(w, h, false);
      camera.aspect = w / h;
      camera.updateProjectionMatrix();
    }

    function draw(pose) {
      const eye = toScene(pose.eye, pose.eye.z);
      const target = toScene(pose.target, pose.target.z);
      camera.position.set(eye.x, eye.y, eye.z);
      camera.lookAt(target.x, target.y, target.z);
      renderer.render(scene, camera);
    }

    const observer = watchViewport(resize);
    let disposed = false;

    function swapProps(loaded) {
      if (disposed || !loaded.some(Boolean)) return;
      const byName = Object.fromEntries(PROP_MODELS.map((name, i) => [name, loaded[i]]));
      const models = TK.scene3dProps.modelSet(T, byName);
      const next = TK.scene3dProps.build(T, models);
      scene.remove(groups.props);
      groups.props.traverse(free);
      scene.add(next);
      groups.props = next;
    }

    function dispose() {
      disposed = true;
      if (observer) observer.disconnect();
      scene.traverse(free);
      renderer.dispose();
      renderer.domElement.remove();
    }

    resize(container.clientWidth, container.clientHeight);
    Promise.all(PROP_MODELS.map(loadModel)).then(swapProps);
    const handle = { ok: true, THREE: T, scene, groups, loadModel, draw, dispose };

    return handle;
  }

  TK.scene3d = { CAMP, PATH, SIZE, FOV, clamp, toScene, yawOf, terrainColor, build, create, sync };
})(window.TK);
