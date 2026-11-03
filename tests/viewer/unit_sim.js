// Sim clock, interpolation and toolbar: viewer/sim_math.js (fraction, blend, packPositions, the reply buffer),
// TK.live.throttle in viewer/live.js, and the clock, detect and request builders of viewer/sim.js.
(function () {
  'use strict';

  const near = (a, b, e = 1e-6) => Math.abs(a - b) < e;
  const pl = (g, x, f = 0) => ({ guid: g, pos: { x, y: 0 }, facing: f });

  TK_TESTS.push({
    name: 'simMath.fraction lags one interval, clamps, handles a zero interval',
    fn() {
      const F = TK.simMath.fraction;
      A.same([F(0, 33, 33), F(0, 33, 99), F(0, 33, 10), F(5, 5, 5)], [0, 1, 0, 1]);
      A.eq(near(F(0, 33, 49.5), 0.5), true);
    },
  });

  TK_TESTS.push({
    name: 'simMath.blend: interpolates, shortest arc, new actors snap, gone ones drop',
    fn() {
      const prev = { player: pl('p', 0, 0.1), actors: [pl('a', 0), pl('gone', 1)] };
      const next = { player: pl('p', 10, 2 * Math.PI - 0.1), actors: [pl('a', 4), pl('new', 9)] };
      const out = TK.simMath.blend(prev, next, 0.5);
      A.eq(out.items[0].isPlayer, true, 'first item is the player');
      A.eq(out.items[0].pos.x, 5, 'player x halfway');
      A.eq(near(Math.cos(out.items[0].facing), 1), true, 'crosses 0, not π');
      A.same(
        out.items.map((i) => i.raw.guid),
        ['p', 'a', 'new'],
      );
      A.eq(out.items[2].pos.x, 9, 'new actor snaps to its position');
      A.eq(out.items[2].prevRaw, null, 'new actor has no previous reply');
    },
  });

  TK_TESTS.push({
    name: 'simMath.packPositions: 3 mobs 3 yd apart, 20 yd ahead, centred on the facing',
    fn() {
      const P = TK.simMath.packPositions;
      const north = P({ pos: { x: 0, y: -10 }, facing: 0 });
      A.same(
        north.map((p) => [p.x, p.y]),
        [
          [-3, 10],
          [0, 10],
          [3, 10],
        ],
      );
      const w = P({ pos: { x: 0, y: -10 }, facing: Math.PI / 2 }); // west; right hand = north
      A.eq(near(w[0].x, -20), true, 'west: first mob x');
      A.eq(near(w[0].y, -13), true, 'west: first mob y');
      A.eq(near(w[2].y, -7), true, 'west: last mob y');
    },
  });

  TK_TESTS.push({
    name: 'simMath.createBuffer samples between the last two replies',
    fn() {
      const B = TK.simMath.createBuffer();
      const w = (x) => ({ player: pl('p', x), actors: [] });
      A.eq(B.sample(0), null);
      B.push(w(0), 100);
      A.eq(B.sample(100).items[0].pos.x, 0);
      B.push(w(10), 133);
      A.eq(near(B.sample(133 + 16.5).items[0].pos.x, 5), true);
      B.clear();
      A.eq(B.last(), null);
    },
  });

  TK_TESTS.push({
    name: 'live.throttle: first call at once, burst coalesced to one trailing run, gap 0 never delays',
    fn() {
      const timers = [];
      let t = 0;
      let runs = 0;
      let gap = 100;
      const call = TK.live.throttle(() => runs++, {
        gap: () => gap,
        now: () => t,
        setTimeout: (f) => timers.push({ f }),
      });
      call();
      t = 10;
      call();
      t = 20;
      call();
      A.same([runs, timers.length], [1, 1]);
      t = 100;
      timers[0].f();
      A.eq(runs, 2, 'one trailing run');
      t = 500;
      call();
      gap = 0;
      t = 501;
      call();
      call();
      A.same([runs, TK.live.gapMs], [5, 0]);
    },
  });

  TK_TESTS.push({
    name: 'clock: 33 ms ticks, seconds 0.033, one call in flight, stops on a failed reply',
    async fn() {
      const timers = [];
      const calls = [];
      const worlds = [];
      const errors = [];
      let release;
      let now = 0;
      const api = (m, req) => {
        calls.push([m, req]);

        return new Promise((r) => {
          release = () => r({ ok: true, world: {} });
        });
      };
      const timer = (f, ms) => {
        timers.push({ f, ms });

        return timers.length;
      };
      const clock = TK.sim.createClock({
        api,
        now: () => now,
        setTimeout: timer,
        clearTimeout() {},
        onWorld: (w, at) => worlds.push(at),
        onError: (e) => errors.push(e),
      });
      clock.start();
      A.eq(timers[0].ms, 33);
      timers.shift().f();
      A.same(calls, [['sim', { action: 'step', seconds: 0.033 }]]);
      timers.shift().f();
      A.eq(calls.length, 1, 'tick while pending is skipped');
      now = 40;
      release();
      await Promise.resolve();
      await Promise.resolve();
      A.same(worlds, [40]);
      const bad = TK.sim.createClock({
        api: () => Promise.resolve({ ok: false, error: 'sim clock owns time' }),
        now: () => 0,
        setTimeout: (f) => {
          f();

          return 1;
        },
        clearTimeout() {},
        onWorld() {},
        onError: (e) => errors.push(e),
      });
      bad.start();
      await Promise.resolve();
      await Promise.resolve();
      A.same([bad.running(), errors], [false, ['sim clock owns time']]);
    },
  });

  TK_TESTS.push({
    name: 'clock: stop and start while a step is pending still ticks once the stale reply or rejection lands',
    async fn() {
      for (const outcome of ['reply', 'rejection']) {
        const timers = [];
        const settles = [];
        const calls = [];
        const api = (m, req) => {
          calls.push([m, req]);

          return new Promise((resolve, reject) => {
            settles.push(outcome === 'reply' ? () => resolve({ ok: true, world: {} }) : () => reject(new Error('x')));
          });
        };
        const clock = TK.sim.createClock({
          api,
          now: () => 0,
          setTimeout: (f) => timers.push(f),
          clearTimeout() {},
          onWorld() {},
          onError() {},
        });
        clock.start();
        timers.shift()(); // step A in flight
        clock.stop();
        clock.start();
        timers.splice(0).forEach((f) => f()); // the first tick finds A pending and skips
        A.eq(calls.length, 1, outcome + ': tick while the stale step is pending is skipped');
        settles.shift()();
        await Promise.resolve();
        await Promise.resolve();
        A.eq(clock.running(), true, outcome + ': still running');
        A.eq(timers.length, 1, outcome + ': the stale settle re-arms the next tick');
        timers.shift()();
        A.eq(calls.length, 2, outcome + ': the next tick asks for a step');
      }
    },
  });

  TK_TESTS.push({
    name: 'detect: installed sets data-sim, gap 100, disables combat Play; not installed reverts',
    async fn() {
      const play = Object.assign(document.createElement('button'), { id: 'combat-play' });
      const speed = Object.assign(document.createElement('select'), { id: 'combat-speed' });
      const root = document.documentElement;
      document.body.append(play, speed);
      const live = () => Promise.resolve({ ok: true, world: { player: pl('p', 0), actors: [] } });
      A.eq(await TK.sim.detect(live, { noClock: true }), true);
      A.eq(TK.sim.active(), true, 'active');
      A.eq(root.dataset.sim, '1', 'data-sim');
      A.eq(TK.live.gapMs, 100, 'move gap');
      A.eq(play.disabled, true, 'combat Play disabled');
      A.eq(speed.disabled, true, 'combat speed disabled');
      const none = () => Promise.resolve({ ok: false, error: 'no sim' });
      A.eq(await TK.sim.detect(none, { noClock: true }), false);
      A.eq(TK.sim.active(), false, 'inactive');
      A.eq('sim' in root.dataset, false, 'data-sim cleared');
      A.eq(TK.live.gapMs, 0, 'move gap reverted');
      A.eq(play.disabled, false, 'combat Play re-enabled');
      A.eq(speed.disabled, false, 'combat speed re-enabled');
      play.remove();
      speed.remove();
    },
  });

  TK_TESTS.push({
    name: 'detect: of two overlapping detects the later one applies, though the earlier answers last',
    async fn() {
      const none = () => Promise.resolve({ ok: false });
      let answer;
      const slow = () =>
        new Promise((resolve) => {
          answer = resolve;
        });
      try {
        const first = TK.sim.detect(slow, { noClock: true });
        await TK.sim.detect(none, { noClock: true });
        answer({ ok: true, world: { player: pl('p', 0), actors: [] } });
        A.eq(await first, true, 'the earlier detect saw a world');
        A.eq(TK.sim.active(), false, 'the later detect, with no world, stands');
      } finally {
        await TK.sim.detect(none, { noClock: true });
      }
    },
  });

  TK_TESTS.push({
    name: 'a reset reply becomes the world the Pack of 3 spawns around',
    async fn() {
      const panels = Object.assign(document.createElement('aside'), { id: 'panels' });
      const asked = [];
      const savedApi = TK.api;
      const reset = { player: { pos: { x: 0, y: -10 }, facing: 0 }, actors: [] };
      const settle = () => new Promise((resolve) => setTimeout(resolve, 0));
      document.body.append(panels);
      TK.api = (_method, req) => {
        asked.push(req);

        return Promise.resolve(req.action === 'reset' ? { ok: true, world: reset } : { ok: true });
      };
      try {
        TK.sim.mount();
        await TK.sim.detect(() => Promise.resolve({ ok: true, world: { player: pl('p', 0), actors: [] } }), {
          noClock: true,
        });
        panels.querySelector('#sim-reset').click();
        await settle();
        asked.length = 0;
        panels.querySelector('#sim-pack').click();
        await settle();
        A.same(
          asked.map((req) => [req.pos.x, req.pos.y]),
          [
            [-3, 10],
            [0, 10],
            [3, 10],
          ],
        );
      } finally {
        await TK.sim.detect(() => Promise.resolve({ ok: false }), { noClock: true });
        TK.api = savedApi;
        panels.remove();
      }
    },
  });

  TK_TESTS.push({
    name: 'panel controls hand the keyboard back to the stage after use',
    async fn() {
      const root = document.createElement('div');
      const panels = Object.assign(document.createElement('aside'), { id: 'panels' });
      const posts = [];
      const savedApi = TK.api;
      root.append(panels);
      document.body.append(root);
      TK.keys.attach(root, { post: (r) => posts.push(r), focused: () => false, sim: () => true });
      // Keys go to the focused element, else to the stage (stood in for by root).
      const press = () => {
        const target = root.contains(document.activeElement) ? document.activeElement : root;
        target.dispatchEvent(new KeyboardEvent('keydown', { code: 'KeyW', bubbles: true, cancelable: true }));
      };
      TK.api = () => Promise.resolve({ ok: true });
      try {
        TK.sim.mount();
        const select = panels.querySelector('#sim-class');
        const toggle = panels.querySelector('#sim-toggle');
        select.focus();
        A.eq(document.activeElement, select, 'select focused');
        press();
        A.eq(posts.length, 0, 'a focused select swallows the key');
        select.dispatchEvent(new Event('change'));
        A.eq(document.activeElement === select, false, 'class change blurs the select');
        press();
        A.eq(posts.length, 1, 'the key walks the player again');
        toggle.focus();
        A.eq(document.activeElement, toggle, 'toggle focused');
        toggle.dispatchEvent(new Event('change'));
        await new Promise((resolve) => setTimeout(resolve, 0));
        A.eq(document.activeElement === toggle, false, 'finished toggle blurs the checkbox');
        const world = { ok: true, world: { player: pl('p', 0), actors: [] } };
        await TK.sim.detect(() => Promise.resolve(world), { noClock: true });
        const spawn = panels.querySelector('#sim-spawn');
        spawn.focus();
        A.eq(document.activeElement, spawn, 'tool button focused');
        spawn.click();
        A.eq(document.activeElement === spawn, false, 'a clicked tool button blurs');
        await TK.sim.detect(() => Promise.resolve({ ok: false }), { noClock: true });
      } finally {
        TK.api = savedApi;
        root.remove();
      }
    },
  });

  TK_TESTS.push({
    name: 'reload request and toolbar requests',
    fn() {
      const S = TK.sim;
      A.same(
        [S.reloadRequest(true, 'MAGE'), S.reloadRequest(false, 'MAGE')],
        [{ sim: { class: 'MAGE', level: 10 } }, { sim: false }],
      );
      A.same(
        [S.requests.raid(25), S.requests.reset('MAGE'), S.requests.spawn()],
        [{ action: 'raid', size: 25 }, { action: 'reset', class: 'MAGE' }, { action: 'spawn' }],
      );
      A.eq(S.requests.pack({ pos: { x: 0, y: -10 }, facing: 0 }).length, 3);
    },
  });
})();
