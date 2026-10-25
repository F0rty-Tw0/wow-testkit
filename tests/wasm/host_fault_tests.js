// Host controller checks over a scripted worker (Task 5b.5): the faults a real worker cannot be made to give on demand,
// an open that fails and a WASM abort. Uses the helpers host_tests.js exports on TKH_TEST.
(function () {
  'use strict';

  const T = window.TK_TESTS;
  const H = window.TK.host;
  const { until, rejects } = window.TKH_TEST;

  // A spawn function for start(), and the workers it made. script(msg, say) answers each message the controller posts, a
  // microtask later, by calling say(data) for every worker message it wants delivered.
  function scripted(script) {
    const made = [];
    const spawn = () => {
      const worker = {
        ended: false,
        postMessage: (msg) => Promise.resolve().then(() => script(msg, (data) => worker.onmessage({ data }))),
        terminate: () => (worker.ended = true),
      };
      made.push(worker);

      return worker;
    };

    return { spawn, made };
  }

  const reply = (say, msg, body) => say({ type: 'reply', id: msg.id, json: JSON.stringify(body) });
  const shown = () => document.getElementById('host-state').textContent;

  function launch(fake) {
    return H.start({ addon: fakeDir({ 'A.toc': 'x' }, 'A'), account: 'F', spawn: fake.spawn, poll: { interval: 50 } });
  }

  T.push({
    name: 'host_open_message_carries_the_walked_folders',
    fn: async () => {
      const opens = [];
      const fake = scripted((msg, say) => {
        if (msg.type === 'open') opens.push(msg);
        reply(say, msg, { ok: true });
      });
      const wtf = fakeDir({ SavedVariables: { 'a.lua': '', 'B.lua': '' }, Realm: { Char: { SavedVariables: { 'A.lua': '' } } } });
      const extract = fakeDir({ 'manifest.lua': 'return {}', '.hidden': { x: '' } });
      const ctl = H.start({ addon: fakeDir({ 'A.toc': 'x' }, 'A'), extract, wtf, character: 'Realm/Char', account: 'F', spawn: fake.spawn });
      try {
        await until(() => ctl.state() === 'Running', 'Running');
        const paths = (list) => list.map((entry) => entry.path);
        A.eq(opens[0].addonFolder, 'A');
        A.same(paths(opens[0].addon), ['A.toc']);
        A.same(paths(opens[0].extract), ['manifest.lua']);
        A.same(paths(opens[0].wtf), ['Realm/Char/SavedVariables/A.lua', 'SavedVariables/a.lua']);
        A.eq(opens[0].account, 'F');
        A.eq(opens[0].character, 'Realm/Char');
      } finally {
        ctl.stop();
      }
    },
  });

  T.push({
    name: 'host_open_failure_returns_to_picking_with_the_error',
    fn: async () => {
      const fake = scripted((msg, say) => reply(say, msg, { ok: false, error: 'no such addon' }));
      const ctl = launch(fake);
      try {
        await until(() => ctl.state() !== 'Loading', 'the open reply');
        A.eq(ctl.state(), 'Picking');
        A.eq(shown(), 'no such addon');
        A.eq(fake.made[0].ended, true, 'the worker of a failed open is ended');
        await rejects(ctl.api('snapshot'), '^not running$');
      } finally {
        ctl.stop();
      }
    },
  });

  T.push({
    name: 'host_abort_stops_the_runtime_and_restart_reopens',
    fn: async () => {
      const fake = scripted((msg, say) => {
        if (msg.type === 'call') say({ type: 'fatal', error: 'out of memory' });
        else reply(say, msg, { ok: true });
      });
      const ctl = launch(fake);
      try {
        await until(() => ctl.state() === 'Running', 'Running');
        await rejects(ctl.api('snapshot'), '^runtime stopped: out of memory$');
        A.eq(ctl.state(), 'Stopped');
        A.eq(shown(), 'runtime stopped: out of memory');
        A.eq(fake.made[0].ended, true);
        await rejects(ctl.api('snapshot'), '^runtime stopped$');
        ctl.restart();
        A.eq(ctl.state(), 'Loading');
        await until(() => ctl.state() === 'Running', 'Running after restart');
        A.eq(fake.made.length, 2, 'a restart makes a new worker');
      } finally {
        ctl.stop();
      }
    },
  });
})();
