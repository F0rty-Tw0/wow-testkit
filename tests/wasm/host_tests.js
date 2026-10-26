// Host core checks (Task 5b.5): the state table, the folder walks, the watcher, the watchdog and the store on fake handles
// and timers. The helpers go out on TKH_TEST for host_run_tests.js and host_fault_tests.js.
(function () {
  'use strict';

  const T = window.TK_TESTS;
  const H = window.TK.host;
  const fixtures = TKPage.load('fixtures');
  const STATES = ['Picking', 'Loading', 'Running', 'Reloading', 'Stopped', 'NeedsRepick'];

  // Resolves after the microtasks of fake handles have run.
  const settle = () => new Promise((resolve) => setTimeout(resolve, 20));
  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

  async function until(cond, what) {
    for (let waited = 0; !cond(); waited += 10) {
      if (waited > 20000) throw new Error('timed out waiting for ' + what);
      await sleep(10);
    }
  }

  async function rejects(promise, pattern) {
    try {
      await promise;
    } catch (err) {
      A.eq(new RegExp(pattern).test(err.message), true, 'rejected with ' + err.message);

      return;
    }
    throw new Error('did not reject, want ' + pattern);
  }

  const running = ['Loading', 'Running', 'Reloading'];
  const toAll = (to, action) => Object.fromEntries(running.map((state) => [state, [to, action]]));

  T.push({
    name: 'next_follows_the_state_table',
    fn: () => {
      // Every cell of spec 6 that does something: event -> state -> [new state, action]. The rest stay put and do nothing.
      const cells = {
        granted: { Picking: ['Loading', 'open'], NeedsRepick: ['Loading', 'open'] },
        openOk: { Loading: ['Running', 'flush'] },
        call: {
          Picking: ['Picking', 'reject:not running'],
          Loading: ['Loading', 'queue'],
          Running: ['Running', 'send'],
          Reloading: ['Reloading', 'queue'],
          Stopped: ['Stopped', 'reject:runtime stopped'],
          NeedsRepick: ['NeedsRepick', 'reject:re-pick folder'],
        },
        fileChange: { Running: ['Reloading', 'quiet'], Reloading: ['Reloading', 'quiet'] },
        reloadReply: { Reloading: ['Running', 'flush'] },
        luaError: { Loading: ['Picking', 'showError'], Reloading: ['Running', 'flush'] },
        watchdog: toAll('Stopped', 'terminate'),
        fatal: toAll('Stopped', 'terminate'),
        handleFail: toAll('NeedsRepick', 'terminate'),
        restart: { Stopped: ['Loading', 'open'] },
        pagehide: { Running: ['Stopped', 'shutdown'], Reloading: ['Stopped', 'shutdown'] },
        pageshowPersisted: { Stopped: ['Loading', 'open'] },
      };
      Object.keys(cells).forEach((event) => {
        STATES.forEach((state) => {
          const [to, action] = cells[event][state] || [state, null];
          A.same(H.next(state, event), { state: to, action }, event + ' in ' + state);
        });
      });
    },
  });

  T.push({
    name: 'walk_lists_nested_files_and_skips_dot_dirs',
    fn: async () => {
      const out = await H.walk(fakeDir({ 'A.toc': 't', Sub: { 'b.lua': 'x' }, '.git': { x: '' } }));
      A.same(out.map((entry) => entry.path), ['A.toc', 'Sub/b.lua']);
      A.eq(await out[1].file.text(), 'x');
    },
  });

  T.push({
    name: 'wtf_entries_pick_only_the_addon_files',
    fn: async () => {
      const wtf = fakeDir({
        SavedVariables: { 'SessionDemo.lua': '', 'Other.lua': '', 'SessionDemo.lua.bak': '' },
        Realm: { Char: { SavedVariables: { 'sessiondemo.lua': '' } } },
      });
      const paths = (entries) => entries.map((entry) => entry.path);
      A.same(paths(await H.wtfEntries(wtf, 'SessionDemo', 'Realm/Char')), ['Realm/Char/SavedVariables/sessiondemo.lua', 'SavedVariables/SessionDemo.lua']);
      A.same(paths(await H.wtfEntries(wtf, 'SessionDemo')), ['SavedVariables/SessionDemo.lua']);
      A.same(paths(await H.wtfEntries(wtf, 'SessionDemo', 'Realm/Nobody')), ['SavedVariables/SessionDemo.lua']);
      A.same(await H.characters(wtf), ['Realm/Char']);
    },
  });

  T.push({
    name: 'character_of_keeps_only_a_listed_choice',
    fn: () => {
      A.eq(H.characterOf(['Realm/Char'], 'Realm/Char'), 'Realm/Char');
      A.eq(H.characterOf(['Realm/Char'], '../../x'), undefined, 'a stored choice the folder does not hold');
      A.eq(H.characterOf(null, 'Realm/Char'), undefined, 'a folder that could not be listed');
    },
  });

  T.push({
    name: 'watch_reports_edits_new_and_deleted_files',
    fn: async () => {
      await fixtures;
      const dir = fakeDir(treeOf(Object.assign({ 'notes.txt': 'n' }, FIXTURE_FILES.SessionDemo)));
      const timers = fakeTimers();
      let changes = 0;
      const watcher = H.watch(dir, () => changes++, () => {}, Object.assign({ interval: 500 }, timers));
      await settle();
      timers.advance(500);
      await settle();
      A.eq(changes, 0, 'nothing changed');
      const steps = [() => dir.edit('Main.lua', 'x = 1'), () => dir.add('New.lua', 'y = 2'), () => dir.remove('Buttons.lua')];
      for (const [index, step] of steps.entries()) {
        step();
        timers.advance(500);
        await settle();
        A.eq(changes, index + 1, 'after step ' + index);
      }
      dir.edit('notes.txt', 'changed');
      timers.advance(500);
      await settle();
      A.eq(changes, 3, 'a file that is not .lua .xml .toc is not watched');
      watcher.stop();
    },
  });

  T.push({
    name: 'watch_failure_calls_on_fail_once',
    fn: async () => {
      const dir = fakeDir({ 'Main.lua': 'x' });
      const timers = fakeTimers();
      const failures = [];
      H.watch(dir, () => {}, (err) => failures.push(err.name), Object.assign({ interval: 500 }, timers));
      await settle();
      dir.failOn('Main.lua');
      for (let tick = 0; tick < 3; tick++) {
        timers.advance(500);
        await settle();
      }
      A.same(failures, ['NotFoundError']);
    },
  });

  T.push({
    name: 'watchdog_counts_only_the_running_message',
    fn: () => {
      const timers = fakeTimers();
      const expired = [];
      const dog = H.watchdog(Object.assign({ callMs: 1000, openMs: 5000, onExpire: (type, seconds) => expired.push([type, seconds]) }, timers));
      dog.posted(1, 'call');
      timers.advance(500);
      dog.posted(2, 'call');
      timers.advance(400);
      dog.replied(1);
      timers.advance(900);
      A.same(expired, [], 'message 2 has waited 900 ms of its own');
      timers.advance(100);
      A.same(expired, [['call', 1]]);
      dog.replied(2);

      const opened = [];
      const opening = H.watchdog(Object.assign({ callMs: 1000, openMs: 5000, onExpire: (type, seconds) => opened.push([type, seconds]) }, timers));
      opening.posted(3, 'open');
      timers.advance(4999);
      A.same(opened, []);
      timers.advance(1);
      A.same(opened, [['open', 5]]);
    },
  });

  T.push({
    name: 'store_round_trips_a_value',
    fn: async () => {
      A.eq(await H.store.get('character'), undefined);
      await H.store.put('character', 'Realm/Char');
      A.eq(await H.store.get('character'), 'Realm/Char');
    },
  });

  window.TKH_TEST = { sleep, until, rejects, fixtures };
})();
