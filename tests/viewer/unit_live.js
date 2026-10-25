// Live mode against a fake backend (unit_live.html?live=1): the session is down for the first snapshot and the first
// two info calls, then a stream hello names server "a", a console line arrives, the server restarts as "b" (hello with
// a new boot, its seq and console lines from 1 again) and sends its own line 2 and snapshot 2. Each console backlog
// answers late, after a stream line newer than its own lines (and, on "b", one it also holds). Writes PASS/FAIL lines
// into #out like unit.js, for check_unit.py.
window.TK = window.TK || {};

(function (TK) {
  'use strict';

  const calls = [];
  const marks = { beforeSnapshot2: 0 };
  const attached = [];
  const server = { boot: 'a', seq: 5, snapshotFailures: 1, infoFailures: 2 };
  const NEW_2 = { seq: 2, kind: 'print', text: 'new-2' };
  const LINES = { a: [{ seq: 1, kind: 'print', text: 'old-1' }], b: [{ seq: 1, kind: 'print', text: 'new-1' }, NEW_2] };
  // ms each server's console backlog takes to answer: "a" is asked at load and answers after old-2 (400 ms) streams,
  // "b" is asked at its hello (600 ms) and answers after new-2 (800 ms) streams.
  const BACKLOG_MS = { a: 500, b: 250 };
  const INFO = { ok: true, flavors: ['retail', 'vanilla'], flavor: 'retail', addon: 'X', loads: 1, errors: 0 };

  function down(field) {
    server[field] -= 1;

    return server[field] >= 0;
  }

  const ANSWERS = {
    snapshot: () => (down('snapshotFailures') ? null : { screen: { width: 100, height: 100 }, items: [], session: { seq: server.seq } }),
    info: () => (down('infoFailures') ? null : { ...INFO, screen: { width: 1920, height: 1080 }, seq: server.seq }),
    console: () => {
      const lines = LINES[server.boot];

      return new Promise((resolve) => setTimeout(() => resolve({ ok: true, lines }), BACKLOG_MS[server.boot]));
    },
  };

  function call(method) {
    calls.push(method);
    const answer = ANSWERS[method] ? ANSWERS[method]() : { ok: true, nodes: [] };
    if (!answer) return Promise.reject(new Error('session down'));

    return Promise.resolve(answer);
  }

  function spy(module, name) {
    const original = TK[module].attach;
    TK[module].attach = (...args) => {
      attached.push(name);

      return original(...args);
    };
  }

  const texts = (selector) => [...document.querySelectorAll(selector)].map((node) => node.textContent || node.value);

  function check(out, name, actual, expected) {
    const got = JSON.stringify(actual);
    const want = JSON.stringify(expected);
    out.textContent += got === want ? `PASS ${name}\n` : `FAIL ${name}: got ${got}, want ${want}\n`;
  }

  function report() {
    const out = document.getElementById('out');
    check(out, 'live attaches the pointer and keys on the first snapshot drawn', attached, ['pointer', 'keys']);
    check(out, "a restart lets the new server's lower seq draw", TK.state.seq, 2);
    check(out, 'console merges a late backlog with earlier stream lines by seq, across a restart', texts('#console .line'), [
      'old-1',
      'old-2',
      'new-1',
      'new-2',
    ]);
    const treesAfter = calls.slice(marks.beforeSnapshot2).filter((method) => method === 'tree').length;
    check(out, "the inspector takes the restarted server's snapshot 2 though the old one was at 5", treesAfter > 0, true);
    check(out, 'toolbar fills the flavor list once the session answers', texts('#flavor option'), ['Auto', 'retail', 'vanilla']);
    out.setAttribute('data-done', '1');
  }

  function start(emit) {
    const at = (ms, fn) => setTimeout(fn, ms);
    at(200, () => emit('hello', { boot: 'a' }));
    at(300, () => emit('snapshot', { seq: 6 }));
    at(400, () => emit('console', { seq: 2, kind: 'print', text: 'old-2' }));
    at(600, () => {
      Object.assign(server, { boot: 'b', seq: 1 });
      emit('hello', { boot: 'b' });
    });
    at(800, () => emit('console', NEW_2));
    at(900, () => {
      marks.beforeSnapshot2 = calls.length;
      server.seq = 2;
      emit('snapshot', { seq: 2 });
    });
    at(1200, report);
  }

  spy('pointer', 'pointer');
  spy('keys', 'keys');
  TK.transport.use({ call, start });
})(window.TK);
