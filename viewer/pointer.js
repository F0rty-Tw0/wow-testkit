// Mouse input on the live stage, sent to the session as input requests in physical screen pixels (origin top-left).
// TK.pointer.attach(stage, deps) wires the listeners; deps = { post(req), rect() -> stage client rect, screen() ->
// { width, height }, now() -> ms }. Moves become enter requests at most every MOVE_MS, coalesced to the latest
// position. A press that moved DRAG_PX or more becomes one drag request on mouseup (the click that follows is
// swallowed); the wheel becomes +-1 at the point. Classic script; the mapping and naming are pure for
// tests/viewer/unit_pointer.js and unit_keys.js.
window.TK = window.TK || {};

(function (TK) {
  'use strict';

  const BUTTONS = ['LeftButton', 'MiddleButton', 'RightButton', 'Button4', 'Button5'];
  const pointer = (TK.pointer = { MOVE_MS: 40, DRAG_PX: 4 });

  // The screen pixel under a client point of a stage drawn at rect (any scale).
  pointer.toScreen = (ev, rect, screen) => {
    const x = Math.floor(((ev.clientX - rect.left) * screen.width) / rect.width);
    const y = Math.floor(((ev.clientY - rect.top) * screen.height) / rect.height);

    return { x, y };
  };

  pointer.buttonName = (n) => BUTTONS[n];

  // True when a press at from and a release at to moved at least DRAG_PX screen pixels.
  pointer.isDrag = (from, to) => Math.hypot(to.x - from.x, to.y - from.y) >= pointer.DRAG_PX;

  // The wheel's request delta: +1 for a scroll up (negative deltaY), -1 for down.
  pointer.wheelDelta = (ev) => (ev.deltaY < 0 ? 1 : -1);

  function inside(point, screen) {
    const across = point.x >= 0 && point.x < screen.width;
    const down = point.y >= 0 && point.y < screen.height;

    return across && down;
  }

  pointer.attach = (stage, deps) => {
    const move = { last: null, sentAt: -Infinity, pending: null, timer: null };
    const press = { from: null, button: null, swallow: false };

    function pointOf(ev) {
      const screen = deps.screen();
      const point = pointer.toScreen(ev, deps.rect(), screen);

      return inside(point, screen) ? point : null;
    }

    function sendMove() {
      const point = move.pending;
      move.pending = null;
      if (!point) return;
      const same = move.last && move.last.x === point.x && move.last.y === point.y;
      if (same) return;
      move.last = point;
      move.sentAt = deps.now();
      deps.post({ kind: 'enter', target: point });
    }

    function flushLater() {
      if (move.timer) return;
      const wait = pointer.MOVE_MS - (deps.now() - move.sentAt);
      move.timer = setTimeout(() => {
        move.timer = null;
        sendMove();
      }, wait);
    }

    function onMove(ev) {
      const point = pointOf(ev);
      if (!point) return;
      move.pending = point;
      const due = deps.now() - move.sentAt >= pointer.MOVE_MS;
      if (due) sendMove();
      else flushLater();
    }

    function click(ev, button) {
      const point = pointOf(ev);
      if (!point) return;
      move.pending = null;
      move.last = point;
      deps.post({ kind: 'click', target: point, button });
    }

    function onDown(ev) {
      press.swallow = false;
      press.from = pointOf(ev);
      press.button = pointer.buttonName(ev.button);
    }

    function onUp(ev) {
      const { from, button } = press;
      press.from = null;
      const to = pointOf(ev);
      if (!from || !to || !pointer.isDrag(from, to)) return;
      press.swallow = true;
      move.pending = null;
      move.last = to;
      deps.post({ kind: 'drag', from, to, button });
    }

    // The click (or contextmenu) that follows a drag's mouseup is not a click.
    function swallowed() {
      const was = press.swallow;
      press.swallow = false;

      return was;
    }

    function onWheel(ev) {
      const point = pointOf(ev);
      if (!point || ev.deltaY === 0) return;
      ev.preventDefault();
      deps.post({ kind: 'wheel', target: point, delta: pointer.wheelDelta(ev) });
    }

    stage.addEventListener('mousemove', onMove);
    stage.addEventListener('mousedown', onDown);
    stage.addEventListener('mouseup', onUp);
    stage.addEventListener('wheel', onWheel, { passive: false });
    stage.addEventListener('mouseleave', () => {
      move.pending = null;
      move.last = null;
      deps.post({ kind: 'leave' });
    });
    stage.addEventListener('click', (ev) => {
      if (!swallowed()) click(ev, pointer.buttonName(ev.button));
    });
    stage.addEventListener('contextmenu', (ev) => {
      ev.preventDefault();
      if (!swallowed()) click(ev, pointer.buttonName(2));
    });
  };
})(window.TK);
