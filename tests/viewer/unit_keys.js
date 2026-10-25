// TK.keys (viewer/keys.js): browser key events mapped to the client's key names and to a type or press request, and the
// pointer's drag decision (viewer/pointer.js): one drag request when the pointer moved at least DRAG_PX between mousedown
// and mouseup, a click otherwise, and the wheel as +-1.
(function () {
  'use strict';

  const RECT = { left: 100, top: 50, width: 960, height: 540 };
  const SCREEN = { width: 1920, height: 1080 };

  // A detached stage wired with recording deps, like unit_pointer.js's.
  function attached() {
    const stage = document.createElement('div');
    const posts = [];
    TK.pointer.attach(stage, { post: (req) => posts.push(req), rect: () => RECT, screen: () => SCREEN, now: () => 0 });

    return { stage, posts };
  }

  function mouse(stage, type, x, y, button) {
    const ev = new MouseEvent(type, { clientX: x, clientY: y, button: button || 0, cancelable: true });
    stage.dispatchEvent(ev);

    return ev;
  }

  // What the browser does for a press and release: mousedown, mouseup, then click when both hit the same element.
  function press(stage, from, to) {
    mouse(stage, 'mousedown', from[0], from[1]);
    mouse(stage, 'mouseup', to[0], to[1]);
    mouse(stage, 'click', to[0], to[1]);
  }

  TK_TESTS.push({
    name: 'keys.toWow names letters, digits, named and function keys',
    fn() {
      const table = {
        KeyA: 'A',
        Digit1: '1',
        Enter: 'ENTER',
        NumpadEnter: 'ENTER',
        Escape: 'ESCAPE',
        Tab: 'TAB',
        Space: 'SPACE',
        Backspace: 'BACKSPACE',
        ArrowUp: 'UP',
        ArrowLeft: 'LEFT',
        F1: 'F1',
        F12: 'F12',
      };
      for (const [code, key] of Object.entries(table)) {
        A.same(TK.keys.toWow({ code }), { key, mods: {} }, code);
      }
    },
  });

  TK_TESTS.push({
    name: 'keys.toWow carries the held modifiers and drops a bare modifier key',
    fn() {
      const held = { code: 'KeyK', shiftKey: true, ctrlKey: true, altKey: false };
      A.same(TK.keys.toWow(held), { key: 'K', mods: { shift: true, ctrl: true } });
      for (const code of ['ShiftLeft', 'ControlRight', 'AltLeft', 'MetaLeft', 'CapsLock', 'Unidentified']) {
        A.eq(TK.keys.toWow({ code }), null, code);
      }
    },
  });

  TK_TESTS.push({
    name: 'keys.plan types a printable key into a focused EditBox',
    fn() {
      A.same(TK.keys.plan({ key: 'a', code: 'KeyA' }, true), { kind: 'type', text: 'a' });
      A.same(TK.keys.plan({ key: 'A', code: 'KeyA', shiftKey: true }, true), { kind: 'type', text: 'A' });
      A.same(TK.keys.plan({ key: ' ', code: 'Space' }, true), { kind: 'type', text: ' ' });
    },
  });

  TK_TESTS.push({
    name: 'keys.plan presses the key without a focused EditBox',
    fn() {
      A.same(TK.keys.plan({ key: 'a', code: 'KeyA' }, false), { kind: 'press', key: 'A', mods: {} });
      A.eq(TK.keys.plan({ key: 'Shift', code: 'ShiftLeft', shiftKey: true }, false), null);
    },
  });

  TK_TESTS.push({
    name: 'keys.plan presses named keys and ctrl or alt combinations even with a focused EditBox',
    fn() {
      A.same(TK.keys.plan({ key: 'Enter', code: 'Enter' }, true), { kind: 'press', key: 'ENTER', mods: {} });
      A.same(TK.keys.plan({ key: 'Backspace', code: 'Backspace' }, true), { kind: 'press', key: 'BACKSPACE', mods: {} });
      const ctrl = TK.keys.plan({ key: 'a', code: 'KeyA', ctrlKey: true }, true);
      A.same(ctrl, { kind: 'press', key: 'A', mods: { ctrl: true } });
      const alt = TK.keys.plan({ key: 'a', code: 'KeyA', altKey: true }, true);
      A.same(alt, { kind: 'press', key: 'A', mods: { alt: true } });
    },
  });

  TK_TESTS.push({
    name: 'keys.attach ignores keys typed into a panel input and posts the plan for the rest',
    fn() {
      const posts = [];
      const doc = document.createElement('div');
      const field = document.createElement('input');
      doc.append(field);
      TK.keys.attach(doc, { post: (req) => posts.push(req), focused: () => false });
      field.dispatchEvent(new KeyboardEvent('keydown', { code: 'KeyA', key: 'a', bubbles: true }));
      A.same(posts, [], 'typing in a panel input');
      const free = new KeyboardEvent('keydown', { code: 'Tab', key: 'Tab', bubbles: true, cancelable: true });
      doc.dispatchEvent(free);
      A.same(posts, [{ kind: 'press', key: 'TAB', mods: {} }]);
      A.eq(free.defaultPrevented, true, 'Tab stays in the viewer');
    },
  });

  TK_TESTS.push({
    name: 'pointer posts a click, not a drag, when the pointer moved less than DRAG_PX',
    fn() {
      const { stage, posts } = attached();
      A.eq(TK.pointer.DRAG_PX, 4);
      press(stage, [580, 320], [581, 320]);
      A.same(posts, [{ kind: 'click', target: { x: 962, y: 540 }, button: 'LeftButton' }]);
    },
  });

  TK_TESTS.push({
    name: 'pointer posts one drag and swallows the click when the pointer moved DRAG_PX or more',
    fn() {
      const { stage, posts } = attached();
      press(stage, [580, 320], [590, 320]);
      A.same(posts, [{ kind: 'drag', from: { x: 960, y: 540 }, to: { x: 980, y: 540 }, button: 'LeftButton' }]);
      press(stage, [580, 320], [580, 320]);
      A.eq(posts.length, 2, 'the next click is not swallowed');
      A.eq(posts[1].kind, 'click');
    },
  });

  TK_TESTS.push({
    name: 'pointer ignores a press that starts or ends outside the stage',
    fn() {
      const { stage, posts } = attached();
      press(stage, [580, 320], [99, 320]);
      A.same(
        posts.filter((req) => req.kind === 'drag'),
        [],
      );
    },
  });

  TK_TESTS.push({
    name: 'pointer posts the wheel as +1 up and -1 down at the point under the cursor',
    fn() {
      const { stage, posts } = attached();
      const up = new WheelEvent('wheel', { clientX: 580, clientY: 320, deltaY: -120, cancelable: true });
      const down = new WheelEvent('wheel', { clientX: 580, clientY: 320, deltaY: 53, cancelable: true });
      stage.dispatchEvent(up);
      stage.dispatchEvent(down);
      A.same(posts, [
        { kind: 'wheel', target: { x: 960, y: 540 }, delta: 1 },
        { kind: 'wheel', target: { x: 960, y: 540 }, delta: -1 },
      ]);
      A.eq(up.defaultPrevented, true, 'the page does not scroll');
    },
  });

  TK_TESTS.push({
    name: 'live.hasEditFocus is true only when a drawn EditBox has the focus',
    fn() {
      const box = (focused) => ({ widget: { type: 'EditBox', focused } });
      A.eq(TK.live.hasEditFocus({ items: [{}, box(false)] }), false);
      A.eq(TK.live.hasEditFocus({ items: [{}, box(true)] }), true);
      A.eq(TK.live.hasEditFocus(null), false);
    },
  });
})();
