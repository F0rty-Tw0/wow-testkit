// Sim input: held movement keys post keydown/keyup, clicks carry a world hit, a claimed press orbits the camera,
// and the camera pose, zoom and picking maths in viewer/scene3d_input.js.
(function () {
  'use strict';

  const near = (a, b, e = 1e-6) => Math.abs(a - b) < e;
  const RECT = { left: 0, top: 0, width: 960, height: 540 };
  const SCREEN = { width: 1920, height: 1080 };

  // TK.keys.attach on detached divs, recording post.
  function simKeys(over = {}) {
    const doc = document.createElement('div');
    const win = document.createElement('div');
    const posts = [];
    const o = { focusAfterDown: false, ...over };
    const post = (r) => {
      posts.push(r);
      o.focused = o.focused || o.focusAfterDown;
    };
    TK.keys.attach(doc, { post, focused: () => !!o.focused, sim: () => o.sim !== false, win });
    const key = (type, code, x = {}) => {
      const init = { code, key: x.key || code, bubbles: true, cancelable: true, ...x };
      doc.dispatchEvent(new KeyboardEvent(type, init));
    };

    return { doc, win, posts, key };
  }

  TK_TESTS.push({
    name: 'sim keys: down/up pairs, repeat dropped, Shift mid-walk still releases W',
    fn() {
      const { posts, key } = simKeys();
      key('keydown', 'KeyW');
      key('keydown', 'KeyW', { repeat: true });
      key('keydown', 'ShiftLeft', { shiftKey: true });
      key('keyup', 'KeyW', { shiftKey: true });
      key('keyup', 'KeyW');
      A.same(posts, [
        { kind: 'keydown', key: 'W', mods: {} },
        { kind: 'keyup', key: 'W', mods: { shift: true } },
      ]);
    },
  });

  TK_TESTS.push({
    name: 'sim keys: blur and tab hide release every held key once',
    fn() {
      const { win, doc, posts, key } = simKeys();
      key('keydown', 'KeyW');
      key('keydown', 'KeyA');
      win.dispatchEvent(new Event('blur'));
      win.dispatchEvent(new Event('blur'));
      A.same(posts.slice(2).map((r) => r.kind + r.key).sort(), ['keyupA', 'keyupW']);
      key('keydown', 'KeyW', { repeat: true }); // W still held when the window comes back
      A.eq(posts.length, 4, 'an OS repeat after blur starts no walk');
      key('keydown', 'KeyS');
      Object.defineProperty(doc, 'visibilityState', { value: 'hidden' });
      doc.dispatchEvent(new Event('visibilitychange'));
      A.eq(posts.length, 6, '2 downs, 2 blur ups, S down, S up');
      A.eq(posts[5].kind + posts[5].key, 'keyupS');
    },
  });

  TK_TESTS.push({
    name: 'sim keys: EditBox focus and sim off keep press/type; focus gained before keyup still releases',
    fn() {
      const t = simKeys({ focused: true });
      t.key('keydown', 'KeyA', { key: 'a' });
      t.key('keydown', 'Enter', { key: 'Enter' });
      A.same(t.posts, [
        { kind: 'type', text: 'a' },
        { kind: 'press', key: 'ENTER', mods: {} },
      ]);
      const off = simKeys({ sim: false });
      off.key('keydown', 'KeyW');
      off.key('keyup', 'KeyW');
      A.same(off.posts, [{ kind: 'press', key: 'W', mods: {} }]);
      const late = simKeys({ focusAfterDown: true }); // focused() flips true after the first keydown
      late.key('keydown', 'KeyW');
      late.key('keyup', 'KeyW');
      A.same(
        late.posts.map((r) => r.kind),
        ['keydown', 'keyup'],
      );
    },
  });

  TK_TESTS.push({
    name: 'pointer.attach: world on click, a claimed press posts nothing, afterWheel gets the reply',
    async fn() {
      const stage = document.createElement('div');
      const posts = [];
      const wheels = [];
      TK.pointer.attach(stage, {
        post: (r) => {
          posts.push(r);

          return Promise.resolve({ ok: true });
        },
        now: () => 1000,
        rect: () => RECT,
        screen: () => SCREEN,
        world: (pt) => (pt.x === 20 ? { guid: 'g1' } : null),
        claim: (ev) => ev.button === 1,
        afterWheel: (reply) => wheels.push(reply),
      });
      const m = (type, x, y, button = 0) => {
        stage.dispatchEvent(new MouseEvent(type, { clientX: x, clientY: y, button, cancelable: true }));
      };
      m('click', 10, 10);
      m('click', 30, 30);
      A.same(posts, [
        { kind: 'click', target: { x: 20, y: 20 }, button: 'LeftButton', world: { guid: 'g1' } },
        { kind: 'click', target: { x: 60, y: 60 }, button: 'LeftButton' },
      ]);
      m('mousedown', 100, 100, 1);
      m('mousemove', 140, 100, 1);
      m('mouseup', 140, 100, 1);
      m('click', 140, 100, 1);
      A.eq(posts.length, 2, 'claimed: no enter, no drag, click swallowed');
      stage.dispatchEvent(new WheelEvent('wheel', { clientX: 10, clientY: 10, deltaY: -100, cancelable: true }));
      await Promise.resolve();
      await Promise.resolve();
      A.same(wheels, [{ ok: true }]);
    },
  });

  TK_TESTS.push({
    name: 'pointer.attach: a press released off the stage ends the claim and the drag origin',
    fn() {
      const stage = document.createElement('div');
      const win = document.createElement('div');
      const posts = [];
      TK.pointer.attach(stage, {
        post: (r) => {
          posts.push(r);

          return Promise.resolve({ ok: true });
        },
        now: () => 1000,
        win,
        rect: () => RECT,
        screen: () => SCREEN,
        claim: (ev) => ev.button === 1,
      });
      const m = (target, type, x, y, button = 0) => {
        target.dispatchEvent(new MouseEvent(type, { clientX: x, clientY: y, button, cancelable: true }));
      };
      m(stage, 'mousedown', 100, 100, 1);
      m(win, 'mouseup', 700, 100, 1); // released over the panels
      m(stage, 'mousemove', 140, 100);
      A.same(posts, [{ kind: 'enter', target: { x: 280, y: 200 } }]);
      m(stage, 'mousedown', 100, 100);
      m(win, 'mouseup', 700, 100);
      m(stage, 'mouseup', 300, 100); // origin lost: no drag
      A.eq(posts.length, 1, 'a later mouseup on the stage is not a drag');
    },
  });

  TK_TESTS.push({
    name: 'camera: behind the facing, yaw swings it, zoom 5..40, pitch 0.1..1.4, isOrbit',
    fn() {
      const I = TK.scene3dInput;
      const c = { yaw: 0, pitch: 0.4, dist: 15 };
      const east = I.cameraPose({ pos: { x: 0, y: 0 }, facing: Math.PI / 2 }, c).eye; // facing west: behind is east
      A.eq(near(east.x, 15 * Math.cos(0.4)), true, 'eye x behind the facing');
      A.eq(near(east.z, 1.5 + 15 * Math.sin(0.4)), true, 'eye height from pitch');
      A.same([I.zoom({ ...c, dist: 5 }, 1).dist, I.zoom({ ...c, dist: 40 }, -1).dist], [5, 40]);
      A.same([I.orbit(c, 100, 0).yaw, I.orbit(c, 0, -1e4).pitch, I.orbit(c, 0, 1e4).pitch], [0.5, 1.4, 0.1]);
      const presses = [{ button: 1 }, { button: 0, altKey: true }, { button: 0 }, { button: 2, altKey: true }];
      A.same(presses.map(I.isOrbit), [true, true, false, false]);
    },
  });

  TK_TESTS.push({
    name: 'picking: centre ray hits ground at 1.5/tan(pitch) ahead; nearest actor; corpse; sky and off-map null',
    fn() {
      const I = TK.scene3dInput;
      const mid = { x: 959.5, y: 539.5 };
      const pose = I.cameraPose({ pos: { x: 0, y: 0 }, facing: 0 }, I.CAM_DEFAULT);
      const ray = I.rayFromScreen(mid, SCREEN, pose);
      const g = I.groundAt(ray);
      A.eq(near(g.x, 0, 1e-3), true, 'ground x under the centre ray');
      A.eq(near(g.y, 1.5 / Math.tan(0.4), 1e-3), true, 'ground y 1.5/tan(pitch) ahead');
      const at = (guid, dy, dead = false, x = 0) => ({ guid, pos: { x, y: g.y + dy }, dead });
      A.eq(I.pickActor(ray, [at('far', 6), at('near', 0)]), 'near', 'nearest actor');
      A.eq(I.pickActor(ray, [at('side', 0, false, 9)]), null, 'off the ray');
      A.eq(I.pickActor(ray, [at('c', 0, true)]), 'c', 'corpse');
      const low = { o: { x: 0.8, y: -10, z: 0.3 }, d: { x: 0, y: 1, z: 0 } }; // grazes the wide, low corpse sphere
      const still = (dead) => ({ guid: 'a', pos: { x: 0, y: 0 }, dead });
      A.same([I.pickActor(low, [still(true)]), I.pickActor(low, [still(false)])], ['a', null], 'corpse shape');
      A.eq(I.worldFor(mid, SCREEN, pose, [at('near', 0)]).guid, 'near', 'world hit');
      A.eq(I.worldFor({ x: 959.5, y: 5 }, SCREEN, pose, []), null, 'sky');
      A.eq(I.groundAt({ o: { x: 0, y: 0, z: 5 }, d: { x: 1, y: 0, z: -0.01 } }), null, 'hit beyond ±50');
    },
  });

  TK_TESTS.push({
    name: 'picking follows the scene camera FOV and map size, so clicks land where the render shows',
    fn() {
      const I = TK.scene3dInput;
      const shared = { FOV: TK.scene3d.FOV, SIZE: TK.scene3d.SIZE };
      const pose = I.cameraPose({ pos: { x: 0, y: 0 }, facing: 0 }, I.CAM_DEFAULT);
      const corner = { x: 100, y: 100 };
      try {
        A.same(I.rayFromScreen(corner, SCREEN, pose), I.rayFromScreen(corner, SCREEN, pose, shared.FOV));
        TK.scene3d.FOV = 90;
        const wide = I.rayFromScreen(corner, SCREEN, pose, 90);
        A.same(I.rayFromScreen(corner, SCREEN, pose), wide, 'default FOV is shared');
        const edge = { o: { x: 0, y: 0, z: 1 }, d: { x: 0, y: 1, z: -0.1 } }; // lands 10 yd out
        A.eq(I.groundAt(edge).y, 10);
        TK.scene3d.SIZE = 16;
        A.eq(I.groundAt(edge), null, 'map half-size is shared');
      } finally {
        Object.assign(TK.scene3d, shared);
      }
    },
  });

  TK_TESTS.push({
    name: 'afterWheel zooms only when no frame answered; attachCamera orbits on a claimed drag, then stops',
    fn() {
      const I = TK.scene3dInput;
      const cam = { ...I.CAM_DEFAULT };
      const deps = I.pointerDeps({
        screen: () => SCREEN,
        pose: () => I.cameraPose({ pos: { x: 0, y: 0 }, facing: 0 }, cam),
        actors: () => [],
        cam,
        repaint() {},
      });
      deps.afterWheel({ ok: true, target: { id: 'f1' } }, { deltaY: -1 });
      A.eq(cam.dist, 15);
      deps.afterWheel({ ok: true }, { deltaY: -1 });
      A.eq(cam.dist < 15, true);
      const stage = document.createElement('div');
      const win = document.createElement('div');
      const ev = (t, x) => win.dispatchEvent(new MouseEvent(t, { clientX: x }));
      I.attachCamera(stage, win, cam, () => {});
      stage.dispatchEvent(new MouseEvent('mousedown', { button: 1 }));
      ev('mousemove', 100);
      ev('mouseup', 100);
      ev('mousemove', 300);
      A.eq(near(cam.yaw, 0.5), true);
    },
  });
})();
