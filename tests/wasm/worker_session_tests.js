// Worker session checks: one IndexedDB database and one Web Lock per session folder, the folder names the worker
// accepts, the character WTF file, and a failed IndexedDB sync. Uses the helpers worker_tests.js exports on TKW_TEST.
(function () {
  'use strict';

  const T = window.TK_TESTS;
  const { events, filesOf, fsHook, using, open, call, slash, consoleText, fixtures, send } = window.TKW_TEST;

  const CHAR_FILE = 'Realm/Char/SavedVariables/SessionDemo.lua';
  const ACCOUNT_FILE = 'SavedVariables/SessionDemo.lua';

  // SessionDemo whose TOC also lists a per-character variable, SessionDemoCharDB.
  function perCharacterAddon() {
    const toc = FIXTURE_FILES.SessionDemo['SessionDemo.toc'];
    const listed = toc.replace('## SavedVariables: SessionDemoDB', '## SavedVariables: SessionDemoDB\n## SavedVariablesPerCharacter: SessionDemoCharDB');

    return filesOf('SessionDemo', { 'SessionDemo.toc': listed });
  }

  const wtfFile = (path, text) => ({ path, file: new File([text], path.split('/').pop()) });
  const charFile = (mark) => wtfFile(CHAR_FILE, 'SessionDemoCharDB = { mark = "' + mark + '" }');
  const accountFile = () => wtfFile(ACCOUNT_FILE, 'SessionDemoDB = { runs = 1 }');

  // The console lines of text run as a slash command in a session opened with over.
  const dumped = (over, text) =>
    using(null, async (worker) => {
      const seen = events(worker);
      await open(worker, over);
      await slash(worker, text);
      await call(worker, 'snapshot'); // the events of a message follow its reply

      return consoleText(seen);
    });

  T.push({
    name: 'worker_sessions_of_two_tabs_keep_each_other',
    fn: async () => {
      await fixtures;
      await using(null, async (first) => {
        await using(null, async (second) => {
          await open(first, { account: 'Ta' });
          await open(second, { account: 'Tb' });
          await slash(first, '/run SessionDemoDB.tag = "a"');
          await call(first, 'reload'); // writes Ta's saved.lua and syncs it
          await slash(second, '/run SessionDemoDB.tag = "b"');
          await call(second, 'reload'); // a sync of all of /session would drop Ta's file, which this worker never saw
        });
      });
      A.same((await dumped({ account: 'Ta' }, '/dump SessionDemoDB.tag')).slice(-1), ['a']);
      A.same((await dumped({ account: 'Tb' }, '/dump SessionDemoDB.tag')).slice(-1), ['b']);
    },
  });

  T.push({
    name: 'worker_second_open_of_one_session_is_refused',
    fn: async () => {
      await fixtures;
      await using(null, async (first) => {
        A.eq((await open(first, { account: 'Lk' })).ok, true);
        await using(null, async (second) => {
          const reply = await open(second, { account: 'Lk' });
          A.eq(reply.ok, false);
          A.eq(/open in another tab/.test(reply.error), true, reply.error);
        });
      });
      await using(null, async (third) => {
        A.eq((await open(third, { account: 'Lk' })).ok, true, 'an ended worker lets go of its session');
      });
    },
  });

  T.push({
    name: 'worker_imports_the_character_file',
    fn: async () => {
      await fixtures;
      const over = { account: 'Ch', character: 'Realm/Char', addon: perCharacterAddon(), wtf: [charFile('c1')] };
      A.same((await dumped(over, '/dump SessionDemoCharDB.mark')).slice(-1), ['c1']);
    },
  });

  T.push({
    name: 'worker_reimport_reads_the_files_listed_again',
    fn: async () => {
      await fixtures;
      await using(null, async (worker) => {
        const seen = events(worker);
        const over = { account: 'Ri', character: 'Realm/Char', addon: perCharacterAddon(), wtf: [accountFile()] };
        await open(worker, over);
        A.eq((await send(worker, { type: 'reimport', wtf: [accountFile(), charFile('c2')] })).ok, true);
        await slash(worker, '/dump SessionDemoCharDB.mark');
        await call(worker, 'snapshot');
        A.same(consoleText(seen).slice(-1), ['c2'], 'the character file appeared after the open');
      });
    },
  });

  T.push({
    name: 'worker_session_dir_refuses_unsafe_names',
    fn: async () => {
      await fixtures;
      const probe = fsHook(
        String(function (FS, TKW) {
          var tries = [
            ['A', '../x', 'D'],
            ['A', 'Realm/..', 'D'],
            ['A', 'Realm', 'D'],
            ['A', 'Realm/Char/x', 'D'],
            ['A', 'Realm/', 'D'],
            ['..', null, 'D'],
            ['A/B', null, 'D'],
            ['A', null, '..'],
            ['A', null, ''],
          ];

          return tries.map(function (args) {
            try {
              return TKW.sessionDir(args[0], args[1], args[2]);
            } catch (e) {
              return 'threw';
            }
          });
        }),
      );
      await using(probe, async (worker) => {
        const reply = await open(worker, { account: 'A', character: '../../escape' }); // also waits for the runtime
        A.eq(reply.ok, false);
        A.eq(/bad session folder/.test(reply.error), true, reply.error);
        A.same(await send(worker, { type: 'probe' }), ['threw', 'threw', 'threw', 'threw', 'threw', 'threw', 'threw', 'threw', 'threw']);
      });
    },
  });

  T.push({
    name: 'worker_failed_sync_still_replies_and_posts_events',
    fn: async () => {
      await fixtures;
      const failing = fsHook(
        String(function (FS) {
          var real = FS.syncfs;
          FS.syncfs = function (populate, done) {
            if (populate) return real.call(FS, populate, done);
            done(new Error('quota exceeded'));
          };

          return true;
        }),
      );
      await using(failing, async (worker) => {
        const seen = events(worker);
        await open(worker, { account: 'Sf' });
        await send(worker, { type: 'probe' });
        const reply = await call(worker, 'reload');
        A.same([reply.ok, reply.syncError], [true, 'quota exceeded']);
        await call(worker, 'snapshot');
        A.same(seen.map((e) => e.name).filter((name) => name === 'reload'), ['reload'], 'the reload event still arrives');
        A.same(await send(worker, { type: 'pagehide' }), { ok: true, syncError: 'quota exceeded' });
      });
    },
  });
})();
