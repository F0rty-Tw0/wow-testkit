// TK.pointer (viewer/pointer.js) and TK.live.hoverRect (viewer/live.js): pointer events on a half-scale stage
// mapped to physical screen pixels, the move throttle, and the hover outline's rect.
(function () {
  'use strict';

  const RECT = { left: 100, top: 50, width: 960, height: 540 };
  const SCREEN = { width: 1920, height: 1080 };

  // A detached stage div wired with recording deps; now() reads clock.t.
  function attached() {
    const stage = document.createElement('div');
    const posts = [];
    const clock = { t: 0 };
    const deps = {
      post: (req) => posts.push(req),
      rect: () => RECT,
      screen: () => SCREEN,
      now: () => clock.t,
    };
    TK.pointer.attach(stage, deps);

    return { stage, posts, clock };
  }

  function mouse(stage, type, x, y, button) {
    const ev = new MouseEvent(type, { clientX: x, clientY: y, button: button || 0, cancelable: true });
    stage.dispatchEvent(ev);

    return ev;
  }

  TK_TESTS.push({
    name: 'pointer.toScreen maps a half-scale stage to screen pixels',
    fn() {
      A.same(TK.pointer.toScreen({ clientX: 580, clientY: 320 }, RECT, SCREEN), { x: 960, y: 540 });
      A.same(TK.pointer.toScreen({ clientX: 100.4, clientY: 50.9 }, RECT, SCREEN), { x: 0, y: 1 });
    },
  });

  TK_TESTS.push({
    name: 'pointer.buttonName names the five mouse buttons',
    fn() {
      const names = [0, 1, 2, 3, 4].map(TK.pointer.buttonName);
      A.same(names, ['LeftButton', 'MiddleButton', 'RightButton', 'Button4', 'Button5']);
      A.eq(TK.pointer.MOVE_MS, 40);
    },
  });

  TK_TESTS.push({
    name: 'pointer.attach throttles moves and posts the latest position',
    fn() {
      const { stage, posts, clock } = attached();
      mouse(stage, 'mousemove', 580, 320);
      A.same(posts, [{ kind: 'enter', target: { x: 960, y: 540 } }], 'first move');
      clock.t = 10;
      mouse(stage, 'mousemove', 590, 320);
      A.eq(posts.length, 1, 'move inside the throttle window');
      clock.t = 50;
      mouse(stage, 'mousemove', 600, 330);
      A.same(posts.slice(1), [{ kind: 'enter', target: { x: 1000, y: 560 } }], 'move after the window');
      clock.t = 100;
      mouse(stage, 'mousemove', 600.2, 330.2);
      A.eq(posts.length, 2, 'move to the same pixel');
    },
  });

  TK_TESTS.push({
    name: 'pointer.attach sends a throttled move once the window ends',
    async fn() {
      const { stage, posts, clock } = attached();
      mouse(stage, 'mousemove', 580, 320);
      clock.t = 10;
      mouse(stage, 'mousemove', 590, 320);
      mouse(stage, 'mousemove', 600, 330);
      await new Promise((done) => setTimeout(done, 3 * TK.pointer.MOVE_MS));
      A.same(posts.slice(1), [{ kind: 'enter', target: { x: 1000, y: 560 } }]);
    },
  });

  TK_TESTS.push({
    name: 'pointer.attach ignores moves outside the stage',
    fn() {
      const { stage, posts } = attached();
      mouse(stage, 'mousemove', 99, 320);
      mouse(stage, 'mousemove', 580, 590);
      A.same(posts, []);
    },
  });

  TK_TESTS.push({
    name: 'pointer.attach posts leave and clicks with button names',
    fn() {
      const { stage, posts } = attached();
      mouse(stage, 'mouseleave', 0, 0);
      mouse(stage, 'click', 580, 320, 0);
      const menu = mouse(stage, 'contextmenu', 580, 320, 2);
      A.eq(menu.defaultPrevented, true, 'contextmenu default');
      A.same(posts, [
        { kind: 'leave' },
        { kind: 'click', target: { x: 960, y: 540 }, button: 'LeftButton' },
        { kind: 'click', target: { x: 960, y: 540 }, button: 'RightButton' },
      ]);
    },
  });

  TK_TESTS.push({
    name: 'live.hoverRect outlines the frame a reply names',
    fn() {
      const snapshot = { items: [{ id: 'f3', rect: { x: 1, y: 2, width: 3, height: 4 } }] };
      const hit = { ok: true, target: { id: 'f3' } };
      A.same(TK.live.hoverRect(snapshot, { kind: 'enter' }, hit), { x: 1, y: 2, width: 3, height: 4 });
      A.eq(TK.live.hoverRect(snapshot, { kind: 'leave' }, hit), null, 'leave');
      A.eq(TK.live.hoverRect(snapshot, { kind: 'enter' }, { ok: true }), null, 'empty space');
      A.eq(TK.live.hoverRect(snapshot, { kind: 'enter' }, { ok: true, target: { id: 'f9' } }), null, 'unknown id');
    },
  });
})();
