// Worker mount checks (Task 5b.4): case-insensitive names under the picked folders, remount, WTF import and re-import,
// pagehide. Uses the helpers worker_tests.js exports on TKW_TEST.
(function () {
  'use strict';

  const T = window.TK_TESTS;
  const { events, filesOf, fsHook, using, open, call, slash, consoleText, fixtures, send } = window.TKW_TEST;

  const WTF_PATH = 'SavedVariables/SessionDemo.lua';

  // The [{ path, file }] a WTF account folder walk gives for SessionDemo's account file.
  const wtfOf = (runs) => [{ path: WTF_PATH, file: new File(['SessionDemoDB = { runs = ' + runs + ' }'], 'SessionDemo.lua') }];

  const mainRenamed = () => filesOf('SessionDemo', { 'Main.lua': null, 'main.lua': FIXTURE_FILES.SessionDemo['Main.lua'] });
  const frameNames = (snap) => snap.items.map((item) => item.name);

  // Opens a session for account (no character), runs text as a slash command and returns the console lines.
  const dumped = (account, wtf, text) =>
    using(null, async (worker) => {
      const seen = events(worker);
      await open(worker, { account, wtf });
      await slash(worker, text);
      await call(worker, 'snapshot'); // the events of a message follow its reply

      return consoleText(seen);
    });

  T.push({
    name: 'worker_toc_naming_main_lua_loads_main_lua',
    fn: async () => {
      await fixtures;
      await using(null, async (worker) => {
        A.eq((await open(worker, { addon: mainRenamed() })).ok, true);
        A.eq(frameNames(await call(worker, 'snapshot')).includes('SessionDemoFrame'), true);
      });
    },
  });

  T.push({
    name: 'worker_listing_keeps_real_names',
    fn: async () => {
      await fixtures;
      const probe = fsHook(
        String(function (FS) {
          var out = { list: FS.readdir('/addon/SessionDemo'), stat: FS.stat('/addon/SessionDemo/MAIN.LUA').size > 0 };
          try {
            FS.stat('/session/NoSuch');
            out.missing = 'found';
          } catch (e) {
            out.missing = 'threw';
          }

          return out;
        }),
      );
      await using(probe, async (worker) => {
        await open(worker, { addon: mainRenamed() });
        const out = await send(worker, { type: 'probe' });
        A.eq(out.list.includes('main.lua') && !out.list.includes('Main.lua'), true);
        A.eq(out.stat, true);
        A.eq(out.missing, 'threw');
      });
    },
  });

  T.push({
    name: 'worker_case_wrap_prefers_the_exact_name_then_sorted_order',
    fn: async () => {
      await fixtures;
      const probe = fsHook(
        String(function (FS) {
          var read = function (path) {
            return FS.readFile(path, { encoding: 'utf8' });
          };

          return { exact: read('/addon/SessionDemo/main.lua'), sorted: read('/addon/SessionDemo/MAIN.LUA').slice(0, 5) };
        }),
      );
      await using(probe, async (worker) => {
        await open(worker, { addon: filesOf('SessionDemo', { 'main.lua': '-- lower' }) });
        A.same(await send(worker, { type: 'probe' }), { exact: '-- lower', sorted: 'local' });
      });
    },
  });

  T.push({
    name: 'worker_remount_reloads_new_files',
    fn: async () => {
      await fixtures;
      await using(null, async (worker) => {
        const seen = events(worker);
        await open(worker);
        const edited = filesOf('SessionDemo', { 'Main.lua': FIXTURE_FILES.SessionDemo['Main.lua'].replace('"idle"', '"edited"') });
        const reply = await send(worker, { type: 'remount', addon: edited });
        A.eq(reply.ok, true);
        A.eq(reply.loads, 2);
        const snap = await call(worker, 'snapshot');
        A.eq(snap.items.filter((item) => item.name === 'SessionDemoText')[0].text, 'edited');
        const names = seen.map((e) => e.name).filter((name) => name === 'reload' || name === 'snapshot');
        A.same(names.slice(0, 2), ['reload', 'snapshot']);
      });
    },
  });

  T.push({
    name: 'worker_remount_sees_a_new_file',
    fn: async () => {
      await fixtures;
      await using(null, async (worker) => {
        await open(worker);
        const toc = FIXTURE_FILES.SessionDemo['SessionDemo.toc'] + 'Extra.lua\n';
        // A frame with no size or anchor is not in the snapshot.
        const extra = 'local f = CreateFrame("Frame", "SessionDemoExtra", UIParent) f:SetSize(10, 10) f:SetPoint("CENTER")';
        A.eq((await send(worker, { type: 'remount', addon: filesOf('SessionDemo', { 'SessionDemo.toc': toc, 'Extra.lua': extra }) })).ok, true);
        A.eq(frameNames(await call(worker, 'snapshot')).includes('SessionDemoExtra'), true);
      });
    },
  });

  T.push({
    name: 'worker_wtf_import_is_copy_once',
    fn: async () => {
      await fixtures;
      A.same((await dumped('W', wtfOf(40), '/dump SessionDemoDB.runs')).slice(-1), ['41']);
      await using(null, async (worker) => {
        await open(worker, { account: 'W', wtf: wtfOf(40) });
        A.eq((await send(worker, { type: 'pagehide' })).ok, true);
      });
      A.same((await dumped('W', wtfOf(7), '/dump SessionDemoDB.runs')).slice(-1), ['42']);
    },
  });

  T.push({
    name: 'worker_open_syncs_the_wtf_import',
    fn: async () => {
      await fixtures;
      await using(null, async (worker) => {
        await open(worker, { account: 'S', wtf: wtfOf(40) }); // no reload, no pagehide: only open's own sync can persist it
      });
      A.same((await dumped('S', wtfOf(7), '/dump SessionDemoDB.runs')).slice(-1), ['41']);
    },
  });

  T.push({
    name: 'worker_reimport_overwrites',
    fn: async () => {
      await fixtures;
      await using(null, async (worker) => {
        const seen = events(worker);
        await open(worker, { account: 'R', wtf: wtfOf(40) });
        await slash(worker, '/run SessionDemoDB.runs = 99');
        A.eq((await send(worker, { type: 'reimport', wtf: wtfOf(7) })).ok, true);
        await slash(worker, '/dump SessionDemoDB.runs');
        await call(worker, 'snapshot');
        A.same(consoleText(seen).slice(-1), ['8']);
      });
    },
  });

  T.push({
    name: 'worker_remount_and_reimport_sync_before_replying',
    fn: async () => {
      await fixtures;
      await using(null, async (worker) => {
        await open(worker, { account: 'Y' });
        await slash(worker, '/run SessionDemoDB.runs = 20');
        await send(worker, { type: 'remount', addon: filesOf('SessionDemo') }); // the reload writes the live 20
      });
      A.same((await dumped('Y', null, '/dump SessionDemoDB.runs')).slice(-1), ['21']);
      await using(null, async (worker) => {
        await open(worker, { account: 'Y', wtf: wtfOf(30) });
        await send(worker, { type: 'reimport', wtf: wtfOf(7) });
      });
      A.same((await dumped('Y', null, '/dump SessionDemoDB.runs')).slice(-1), ['8']);
    },
  });

  T.push({
    name: 'worker_pagehide_persists_live_variables',
    fn: async () => {
      await fixtures;
      await using(null, async (worker) => {
        await open(worker, { account: 'P' });
        await slash(worker, '/run SessionDemoDB.x = 5');
        A.same(await send(worker, { type: 'pagehide' }), { ok: true });
      });
      A.same((await dumped('P', null, '/dump SessionDemoDB.x')).slice(-1), ['5']);
    },
  });

  T.push({
    name: 'worker_wtf_is_never_written',
    fn: async () => {
      await fixtures;
      const probe = fsHook(
        String(function (FS) {
          var file = '/wtf/SavedVariables/SessionDemo.lua';
          var out = { exists: FS.analyzePath(file).exists };
          try {
            FS.writeFile(file, 'x');
            out.write = 'wrote';
          } catch (e) {
            out.write = 'threw';
          }

          return out;
        }),
      );
      await using(probe, async (worker) => {
        await open(worker, { account: 'N', wtf: wtfOf(1) });
        A.same(await send(worker, { type: 'probe' }), { exists: true, write: 'threw' });
      });
    },
  });
})();
