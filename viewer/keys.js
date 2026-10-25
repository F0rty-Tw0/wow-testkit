// Keyboard input in live mode: browser key events become the client's key names (TK.keys.toWow) and then a `type` or a
// `press` request (TK.keys.plan); TK.keys.attach(doc, deps) wires the listener. deps = { post(req), focused() -> true when
// the session has a focused EditBox }. Classic script; toWow and plan are pure for tests/viewer/unit_keys.js.
window.TK = window.TK || {};

(function (TK) {
  'use strict';

  const keys = (TK.keys = {});

  // KeyboardEvent.code -> the client's key name, for the keys whose name is not derived from the code.
  const NAMED = {
    Enter: 'ENTER',
    NumpadEnter: 'ENTER',
    Escape: 'ESCAPE',
    Tab: 'TAB',
    Space: 'SPACE',
    Backspace: 'BACKSPACE',
    Delete: 'DELETE',
    Insert: 'INSERT',
    Home: 'HOME',
    End: 'END',
    PageUp: 'PAGEUP',
    PageDown: 'PAGEDOWN',
    ArrowUp: 'UP',
    ArrowDown: 'DOWN',
    ArrowLeft: 'LEFT',
    ArrowRight: 'RIGHT',
  };
  // Keys the page would otherwise scroll with or move the focus on.
  const PAGE_KEYS = new Set(['TAB', 'SPACE', 'BACKSPACE', 'UP', 'DOWN', 'LEFT', 'RIGHT', 'PAGEUP', 'PAGEDOWN', 'HOME', 'END']);

  function nameOf(code) {
    if (NAMED[code]) return NAMED[code];
    const letter = /^Key([A-Z])$/.exec(code || '');
    if (letter) return letter[1];
    const digit = /^Digit([0-9])$/.exec(code || '');
    if (digit) return digit[1];
    const fn = /^F([0-9]{1,2})$/.exec(code || '');

    return fn ? 'F' + fn[1] : null;
  }

  // The held modifiers as { shift?, ctrl?, alt? }, only the true ones.
  function modsOf(ev) {
    const mods = {};
    if (ev.shiftKey) mods.shift = true;
    if (ev.ctrlKey) mods.ctrl = true;
    if (ev.altKey) mods.alt = true;

    return mods;
  }

  keys.toWow = (ev) => {
    const key = nameOf(ev.code);

    return key ? { key, mods: modsOf(ev) } : null;
  };

  // A printable character with no ctrl or alt, while an EditBox has focus, is typed; anything else is a press.
  keys.plan = (ev, focusedEditBox) => {
    const printable = typeof ev.key === 'string' && ev.key.length === 1;
    if (focusedEditBox && printable && !ev.ctrlKey && !ev.altKey) return { kind: 'type', text: ev.key };
    const named = keys.toWow(ev);

    return named ? { kind: 'press', key: named.key, mods: named.mods } : null;
  };

  function inPanelField(ev) {
    const node = ev.target;
    const tag = node && node.tagName;

    return tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT' || Boolean(node && node.isContentEditable);
  }

  // The page keeps its own use of a key unless the session takes it: typing, and the keys that scroll or move focus.
  function swallows(plan, ev) {
    const modified = ev.ctrlKey || ev.altKey || ev.metaKey;

    return !modified && (plan.kind === 'type' || PAGE_KEYS.has(plan.key));
  }

  keys.attach = (doc, deps) => {
    doc.addEventListener('keydown', (ev) => {
      if (inPanelField(ev)) return;
      const plan = keys.plan(ev, deps.focused());
      if (!plan) return;
      if (swallows(plan, ev)) ev.preventDefault();
      deps.post(plan);
    });
  };
})(window.TK);
