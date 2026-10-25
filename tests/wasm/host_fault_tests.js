// Host controller checks over a scripted worker (Task 5b.5): the faults a real worker cannot be made to give on demand,
// an open that fails and a WASM abort, and the timing of what the controller posts: edits while loading, a page hidden
// in the quiet window, calls behind a reimport, and a restore behind the shutdown sync. Uses the helpers host_tests.js
// exports on TKH_TEST and adds recorded() to them.
(function () {
  'use strict';

  const T = window.TK_TESTS;
  const H = window.TK.host;
  const { sleep, until, rejects } = window.TKH_TEST;

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

  // A scripted worker that answers every message ok, but holds the messages hold(msg) picks until release() of the
  // returned held list; posted lists each message as its type, or its method for a call.
  function recorded(hold) {
    const posted = [];
    const held = [];
    const fake = scripted((msg, say) => {
      posted.push(msg.type === 'call' ? msg.method : msg.type);
      if (hold && hold(msg)) held.push(() => reply(say, msg, { ok: true }));
      else reply(say, msg, { ok: true });
    });

    return Object.assign(fake, { posted, held });
  }

  T.push({
    name: 'host_edit_while_loading_reloads_once_running',
    fn: async () => {
      const fake = recorded((msg) => msg.type === 'open');
      const addon = fakeDir({ 'A.toc': 'x', 'Main.lua': 'a = 1' }, 'A');
      const ctl = H.start({ addon, account: 'F', spawn: fake.spawn, poll: { interval: 50, quiet: 100 } });
      try {
        await until(() => fake.held.length === 1, 'the open');
        addon.edit('Main.lua', 'a = 2'); // after the open walk, before its reply
        await sleep(200);
        A.eq(ctl.state(), 'Loading');
        fake.held[0]();
        await until(() => fake.posted.includes('remount'), 'a remount for the edit made while loading');
      } finally {
        ctl.stop();
      }
    },
  });

  T.push({
    name: 'host_pagehide_in_the_quiet_window_sends_no_remount',
    fn: async () => {
      const fake = recorded();
      const addon = fakeDir({ 'A.toc': 'x', 'Main.lua': 'a = 1' }, 'A');
      const ctl = H.start({ addon, account: 'F', spawn: fake.spawn, poll: { interval: 50, quiet: 300 } });
      try {
        await until(() => ctl.state() === 'Running', 'Running');
        addon.edit('Main.lua', 'a = 2');
        await until(() => ctl.state() === 'Reloading', 'Reloading');
        window.dispatchEvent(new Event('pagehide'));
        A.eq(ctl.state(), 'Stopped');
        await sleep(500);
        A.same(fake.posted, ['open', 'pagehide'], 'the quiet window ended with the page');
      } finally {
        ctl.stop();
      }
    },
  });

  T.push({
    name: 'host_calls_sent_after_a_reimport_post_after_it',
    fn: async () => {
      const fake = recorded();
      const wtf = fakeDir({ SavedVariables: { 'A.lua': '' }, Realm: { Char: { SavedVariables: { 'A.lua': '' } } } });
      const ctl = H.start({ addon: fakeDir({ 'A.toc': 'x' }, 'A'), wtf, character: 'Realm/Char', account: 'F', spawn: fake.spawn });
      try {
        await until(() => ctl.state() === 'Running', 'Running');
        await Promise.all([ctl.postCall('reimport', {}), ctl.postCall('snapshot', {})]);
        A.same(fake.posted, ['open', 'reimport', 'snapshot'], 'the reimport lists the WTF folder first, the snapshot waits');
      } finally {
        ctl.stop();
      }
    },
  });

  T.push({
    name: 'host_restore_waits_for_the_shutdown_sync_at_most_hide_ms',
    fn: async () => {
      const fake = recorded((msg) => msg.type === 'pagehide'); // never answered
      const ctl = H.start({ addon: fakeDir({ 'A.toc': 'x' }, 'A'), account: 'F', spawn: fake.spawn, timers: { hideMs: 400 } });
      try {
        await until(() => ctl.state() === 'Running', 'Running');
        window.dispatchEvent(new Event('pagehide'));
        window.dispatchEvent(new PageTransitionEvent('pageshow', { persisted: true }));
        A.eq(ctl.state(), 'Loading');
        await sleep(150);
        A.same([fake.made.length, fake.made[0].ended], [1, false], 'the shut-down worker may still be syncing');
        await until(() => fake.made.length === 2, 'a new worker after hideMs');
        A.eq(fake.made[0].ended, true);
        await until(() => ctl.state() === 'Running', 'Running after the restore');
      } finally {
        ctl.stop();
      }
    },
  });

  window.TKH_TEST.recorded = recorded;
})();
