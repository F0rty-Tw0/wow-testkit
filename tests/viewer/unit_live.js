// Live mode against a fake backend (unit_live.html?live=1): the session is down for the first snapshot and the first
// two info calls, then a stream hello names server "a", a console line arrives, the server restarts as "b" (hello with
// a new boot, its seq and console lines from 1 again) and sends its own line 2 and snapshot 2. Each console backlog
// answers late, after a stream line newer than its own lines (and, on "b", one it also holds). Then the combat bar's
// Pull puts the session in combat in a party, which the Mock state panel must show; a step that leaves combat on must
// not re-read the state, a step that ends it must, and a second Pull's re-read keeps a fixture edit not yet applied.
// The combat log takes the second panel column, not the inspector's. Writes PASS/FAIL lines
// into #out like unit.js, for check_unit.py.
window.TK = window.TK || {};

(function (TK) {
  'use strict';

  const calls = [];
  const marks = { beforeSnapshot2: 0, statesBeforeStep: 0 };
  const attached = [];
  const server = { boot: 'a', seq: 5, snapshotFailures: 1, infoFailures: 2, mock: { combat: false, group: 'none' } };
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
    state: () => ({ ok: true, state: { ...server.mock } }),
    // A pull here also groups the player, as a dungeon preset before it would.
    combat: (req) => {
      if (req.action === 'roster') return { ok: true, races: { Alliance: [], Horde: [] }, classes: [] };
      if (req.action === 'pull') Object.assign(server.mock, { combat: true, group: 'party' });

      return { ok: true, time: 0, inCombat: server.mock.combat, enemies: [] };
    },
  };

  function call(method, req) {
    calls.push(method);
    const answer = ANSWERS[method] ? ANSWERS[method](req || {}) : { ok: true, nodes: [] };
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

  const count = (method) => calls.filter((name) => name === method).length;

  const texts = (selector) => [...document.querySelectorAll(selector)].map((node) => node.textContent || node.value);

  const EDITED = '{ "health": 1 }';

  const fixtureBox = () => document.querySelector('#state textarea');

  function combatShown() {
    const combatBox = [...document.querySelectorAll('#state .flags label')].find((label) => label.textContent.trim() === 'combat');

    return { combat: combatBox.querySelector('input').checked, group: document.querySelectorAll('#state select')[2].value };
  }

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
    check(out, 'the state panel shows combat on and a party after a pull', marks.shownAfterPull, { combat: true, group: 'party' });
    check(out, 'a step that leaves combat on does not re-read the state', marks.statesAfterStep, marks.statesBeforeStep);
    check(out, 'a step that ends combat re-reads the state and unchecks combat', marks.endOfFight, { reread: true, combat: false });
    check(out, 'a re-read after a combat action keeps an unsaved fixture edit', fixtureBox().value, EDITED);
    const column = (id) => getComputedStyle(document.getElementById(id)).gridColumnStart;
    check(out, "the combat log sits beside the inspector, not under it, so it leaves the inspector's details room", column('combatlog'), '2');
  }

  // Wrapped before TK.start (DOMContentLoaded) registers it; a reload runs after report, as it re-reads the panels.
  const forgetFonts = window.Viewer.forgetFonts;
  let forgets = 0;
  window.Viewer.forgetFonts = () => {
    forgets += 1;
    forgetFonts();
  };

  function reportFonts() {
    const out = document.getElementById('out');
    check(out, 'a restart and a reload each drop the loaded fonts', forgets, 2);
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
    at(1000, () => document.getElementById('combat-pull').click());
    at(1200, () => {
      marks.shownAfterPull = combatShown();
      marks.statesBeforeStep = count('state');
      TK.emit('combat', { action: 'step', inCombat: true });
    });
    at(1300, () => {
      marks.statesAfterStep = count('state');
      server.mock.combat = false;
      TK.emit('combat', { action: 'step', inCombat: false });
    });
    at(1400, () => {
      marks.endOfFight = { reread: count('state') > marks.statesAfterStep, combat: combatShown().combat };
      fixtureBox().value = EDITED;
      fixtureBox().dispatchEvent(new Event('input'));
      document.getElementById('combat-pull').click();
    });
    at(1600, report);
    at(1700, () => emit('reload', {}));
    at(1800, reportFonts);
  }

  spy('pointer', 'pointer');
  spy('keys', 'keys');
  TK.transport.use({ call, start });
})(window.TK);
