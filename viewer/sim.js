// Sim mode (live mode, session started with --sim or toggled on): TK.sim.detect(api) asks the session for its sim
// world; an installed sim steps every STEP_MS (createClock, one `sim step` in flight), draws the 3D scene behind the
// stage between the last two replies (sim_math.js), slows the snapshot redraws to TK.live.gapMs and turns the combat
// Play controls off. The #sim panel in #panels holds the Sim checkbox (#sim-toggle, a reload with or without the sim),
// the class select and, while installed, the spawn, pack, raid and reset buttons with a status line. A session
// without the sim changes nothing. Classic script; reloadRequest and requests are pure, createClock owns its timers,
// all checked by tests/viewer/unit_sim.js (detect takes opts.noClock so the tests run without a clock or draw loop).
window.TK = window.TK || {};

(function (TK) {
  'use strict';

  const M = TK.simMath;
  const sim = (TK.sim = {});
  const LEVEL = 10;
  const CLASSES = [['WARRIOR', 'Warrior'], ['MAGE', 'Mage']];
  const COMBAT_CONTROLS = ['combat-play', 'combat-speed'];
  const run = { installed: false, clock: null, handle: null, loop: 0, seq: 0, orbit: false };
  const buffer = M.createBuffer();
  const cam = { ...TK.scene3dInput.CAM_DEFAULT };
  const dom = {};

  sim.active = () => run.installed;

  sim.reloadRequest = (on, cls) => (on ? { sim: { class: cls, level: LEVEL } } : { sim: false });

  sim.requests = {
    spawn: () => ({ action: 'spawn' }),
    pack: (player) => M.packPositions(player).map((pos) => ({ action: 'spawn', pos })),
    raid: (size) => ({ action: 'raid', size }),
    reset: (cls) => ({ action: 'reset', class: cls }),
  };

  sim.createClock = M.createClock;

  // Scene ---------------------------------------------------------------------------------------------------------

  function drawNow() {
    const frame = buffer.sample(performance.now());
    if (!frame || !run.handle || !run.handle.ok) return;
    TK.scene3d.sync(run.handle, frame);
    run.handle.draw(TK.scene3dInput.cameraPose(frame.items[0], cam));
  }

  function nextFrame() {
    run.loop = requestAnimationFrame(nextFrame);
    if (!document.hidden) drawNow();
  }

  function startLoop() {
    const drawable = run.handle && run.handle.ok;
    if (!drawable || run.loop) return;
    run.loop = requestAnimationFrame(nextFrame);
  }

  function stopLoop() {
    cancelAnimationFrame(run.loop);
    run.loop = 0;
  }

  function ensureScene() {
    const background = document.getElementById('background');
    if (run.handle || !background) return;
    const noticeEl = document.getElementById('scene-notice');
    run.handle = TK.scene3d.create(background, { THREE: window.THREE, noticeEl });
  }

  // DOM -----------------------------------------------------------------------------------------------------------

  const el = (tag, props) => Object.assign(document.createElement(tag), props);

  function status(text) {
    if (dom.status) dom.status.textContent = text;
  }

  function note(text) {
    if (dom.note) dom.note.textContent = text;
  }

  async function command(req) {
    try {
      const reply = await TK.api('sim', req);
      status(reply.ok ? '' : reply.error || 'sim: request failed');
      if (reply.ok && req.action === 'reset') {
        buffer.clear();
        buffer.push(reply.world, performance.now());
      }
    } catch (err) {
      status(err.message);
    }
  }

  async function spawnPack() {
    const world = buffer.last();
    if (!world) return;
    for (const req of sim.requests.pack(world.player)) await command(req);
  }

  // A focused panel control would keep the keyboard: keys.js ignores keys aimed at a select or input, and arrow keys
  // change a select (a reset) or Space re-clicks a button. Every control hands the keys back to the stage once used.
  function releaseKeys(control) {
    control.blur();
  }

  function toolButton(id, text, onClick) {
    const button = el('button', { id, type: 'button', textContent: text });
    button.addEventListener('click', () => {
      onClick();
      releaseKeys(button);
    });

    return button;
  }

  function buildTools() {
    const tools = el('div', { id: 'sim-tools' });
    dom.status = el('p', { id: 'sim-status' });
    dom.status.setAttribute('role', 'status');
    const raid = (size) => () => command(sim.requests.raid(size));
    tools.append(
      toolButton('sim-spawn', 'Spawn', () => command(sim.requests.spawn())),
      toolButton('sim-pack', 'Pack of 3', spawnPack),
      toolButton('sim-raid10', 'Raid 10', raid(10)),
      toolButton('sim-raid25', 'Raid 25', raid(25)),
      toolButton('sim-reset', 'Reset', () => command(sim.requests.reset(dom.cls.value))),
      dom.status,
    );

    return tools;
  }

  function showTools(on) {
    if (!dom.section) return;
    if (on && !dom.tools) {
      dom.tools = buildTools();
      dom.section.append(dom.tools);
    }
    if (!on && dom.tools) {
      dom.tools.remove();
      dom.tools = null;
      dom.status = null;
    }
  }

  function syncToggle() {
    if (dom.toggle) dom.toggle.checked = run.installed;
  }

  function resetToClass() {
    releaseKeys(dom.cls);
    if (run.installed) command(sim.requests.reset(dom.cls.value));
  }

  function mount() {
    const title = el('h2', { textContent: 'Sim' });
    dom.toggle = el('input', { id: 'sim-toggle', type: 'checkbox' });
    dom.note = el('span', { className: 'hint' });
    const label = el('label', { textContent: ' Simulate a world ' });
    label.prepend(dom.toggle);
    label.append(dom.note);
    dom.cls = el('select', { id: 'sim-class' });
    dom.cls.setAttribute('aria-label', 'Sim class');
    CLASSES.forEach(([value, text]) => dom.cls.append(el('option', { value, textContent: text })));
    dom.section = el('section', { id: 'sim' });
    dom.section.append(title, label, dom.cls);
    const panels = document.getElementById('panels');
    panels.append(dom.section);
    panels.hidden = false;
    dom.toggle.addEventListener('change', toggle);
    dom.cls.addEventListener('change', resetToClass);
  }

  // Detect --------------------------------------------------------------------------------------------------------

  function setCombatControls(disabled) {
    COMBAT_CONTROLS.forEach((id) => {
      const node = document.getElementById(id);
      if (node) node.disabled = disabled;
    });
  }

  function startClock(api) {
    ensureScene();
    if (!run.clock) {
      run.clock = sim.createClock({
        api,
        now: () => performance.now(),
        setTimeout: (f, ms) => window.setTimeout(f, ms),
        clearTimeout: (id) => window.clearTimeout(id),
        onWorld: (world, at) => buffer.push(world, at),
        onError: status,
      });
    }
    run.clock.start();
    startLoop();
  }

  function install(api, world, opts) {
    run.installed = true;
    document.documentElement.dataset.sim = '1';
    TK.live.gapMs = M.SNAPSHOT_MS;
    setCombatControls(true);
    showTools(true);
    if (dom.cls && world.player && world.player.class) dom.cls.value = world.player.class;
    if (opts.noClock) return;
    buffer.push(world, performance.now());
    startClock(api);
  }

  function uninstall() {
    run.installed = false;
    delete document.documentElement.dataset.sim;
    TK.live.gapMs = 0;
    setCombatControls(false);
    showTools(false);
    stopLoop();
    buffer.clear();
    if (run.clock) run.clock.stop();
  }

  const ask = (api) => Promise.resolve().then(() => api('sim', { action: 'world' })).catch(() => null);

  // True when the session answers `sim world` with a world: sim mode goes on (and the clock and draw loop start, unless
  // opts.noClock); false turns it all off. Overlapping detects: the latest one applies.
  sim.detect = async (api = TK.api, opts = {}) => {
    run.seq += 1;
    const mine = run.seq;
    const reply = await ask(api);
    const installed = Boolean(reply && reply.ok && reply.world);
    if (mine !== run.seq) return installed;
    if (installed) install(api, reply.world, opts);
    else uninstall();
    syncToggle();

    return installed;
  };

  function refresh() {
    if (run.clock) run.clock.stop();
    buffer.clear();

    return sim.detect();
  }

  async function toggle() {
    dom.toggle.disabled = true;
    try {
      const reply = await TK.api('reload', sim.reloadRequest(dom.toggle.checked, dom.cls.value));
      note(reply.ok ? '' : reply.error);
    } catch (err) {
      note(err.message);
    }
    await refresh();
    dom.toggle.disabled = false;
    releaseKeys(dom.toggle);
  }

  // Pointer -------------------------------------------------------------------------------------------------------

  // Deps for TK.pointer.attach, live only while a sim world is installed and has replied; also attaches the camera
  // orbit.
  sim.pointerDeps = () => {
    const stage = document.getElementById('stage');
    if (!run.orbit && stage) TK.scene3dInput.attachCamera(stage, window, cam, drawNow);
    run.orbit = true;
    const inner = TK.scene3dInput.pointerDeps({
      screen: () => TK.state.snapshot.screen,
      pose: () => TK.scene3dInput.cameraPose(buffer.last().player, cam),
      actors: () => buffer.last().actors,
      cam,
      repaint: drawNow,
    });
    const gated = (fn, off) => (...args) => (run.installed && buffer.last() ? fn(...args) : off);

    const claim = gated(inner.claim, false);

    return { world: gated(inner.world, null), claim, afterWheel: gated(inner.afterWheel) };
  };

  sim.mount = mount; // for tests/viewer/unit_sim.js; the page mounts it itself below
  const isLive = new URLSearchParams(location.search).get('live') === '1';
  if (isLive) {
    mount();
    ['reload', 'restart', 'hello'].forEach((name) => TK.on(name, refresh));
    TK.on('snapshot', syncToggle);
    document.addEventListener('DOMContentLoaded', refresh);
  }
})(window.TK);
