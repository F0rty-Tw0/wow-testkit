// Worker core checks: the Blob worker built from TK_WORKER_SRC (wasm/bundle.py) running the kit's SessionHost on
// SessionDemo (FIXTURE_FILES, tests/wasm/fixture_js.py). The helpers are exported on TKW_TEST for the mount checks.
(function () {
  'use strict';

  const T = window.TK_TESTS;
  const fixtures = TKPage.load('fixtures');
  let nextId = 1;

  // A worker over the bundle. hook: the source of a function that runs after worker.js (see fsHook).
  function startWorker(hook) {
    const src = [TK_WORKER_SRC, hook ? '(' + hook + ')();' : ''];

    return new Worker(URL.createObjectURL(new Blob(src)));
  }

  // Posts msg with a fresh id; resolves the parsed JSON of its reply. A fatal message or a worker error rejects.
  function send(worker, msg) {
    const id = nextId++;

    return new Promise((resolve, reject) => {
      const done = () => {
        worker.removeEventListener('message', onMessage);
        worker.removeEventListener('error', onError);
      };
      const onMessage = ({ data }) => {
        if (data.type === 'fatal') {
          done();
          reject(new Error('fatal: ' + data.error));
        } else if (data.type === 'reply' && data.id === id) {
          done();
          resolve(JSON.parse(data.json));
        }
      };
      const onError = (ev) => {
        done();
        reject(new Error('worker error: ' + ev.message));
      };
      worker.addEventListener('message', onMessage);
      worker.addEventListener('error', onError);
      worker.postMessage(Object.assign({ id }, msg));
    });
  }

  // Every event and fatal message the worker posts, in order; the array fills as they arrive.
  function events(worker) {
    const seen = [];
    worker.addEventListener('message', ({ data }) => data.type !== 'reply' && seen.push(data));

    return seen;
  }

  // [{ path, file }] of fixture name. edits = { path: text | null }: null deletes, a new key adds.
  function filesOf(name, edits) {
    const tree = Object.assign({}, FIXTURE_FILES[name], edits);

    return Object.keys(tree)
      .filter((path) => tree[path] !== null)
      .map((path) => ({ path, file: new File([tree[path]], path.split('/').pop()) }));
  }

  // The source of a hook that answers { type: "probe", id } by running fnSource, the source of function (FS, TKW),
  // and replying with its JSON-able result (a throw replies { threw: message }).
  function fsHook(fnSource) {
    return (
      'function () {' +
      ' var run = ' + fnSource + ';' +
      ' var next = self.onmessage;' +
      ' self.onmessage = function (ev) {' +
      '   if (ev.data.type !== "probe") return next(ev);' +
      '   var out;' +
      '   try { out = run(TKW.mod.FS, TKW); } catch (e) { out = { threw: String(e && e.message || e) }; }' +
      '   self.postMessage({ type: "reply", id: ev.data.id, json: JSON.stringify(out) });' +
      ' };' +
      '}'
    );
  }

  // Runs fn(worker) on a started worker and always terminates it.
  async function using(hook, fn) {
    const worker = startWorker(hook);
    try {
      return await fn(worker);
    } finally {
      worker.terminate();
    }
  }

  function open(worker, over) {
    const msg = { type: 'open', addonFolder: 'SessionDemo', addon: filesOf('SessionDemo'), account: null };

    return send(worker, Object.assign(msg, over));
  }

  const call = (worker, method, req) => send(worker, { type: 'call', method, req: req || {} });
  const slash = (worker, text) => call(worker, 'slash', { text });
  const consoleText = (seen) => seen.filter((e) => e.name === 'console').map((e) => e.data.text);

  window.TKW_TEST = { startWorker, send, events, filesOf, fsHook, using, open, call, slash, consoleText, fixtures };

  T.push({
    name: 'worker_opens_session_demo_and_snapshots',
    fn: async () => {
      await fixtures;
      await using(null, async (worker) => {
        A.eq((await open(worker)).ok, true);
        const snap = await call(worker, 'snapshot');
        A.eq(snap.session.addon, 'SessionDemo');
        A.eq(snap.items.filter((item) => item.name === 'SessionDemoText')[0].text, 'idle');
      });
    },
  });

  T.push({
    name: 'worker_mutation_emits_a_snapshot_event',
    fn: async () => {
      await fixtures;
      await using(null, async (worker) => {
        const seen = events(worker);
        await open(worker);
        A.eq((await slash(worker, '/sdemo hi')).ok, true);
        await call(worker, 'snapshot');
        const seqs = seen.filter((e) => e.name === 'snapshot').map((e) => e.data.seq);
        A.eq(seqs[seqs.length - 1], 1);
      });
    },
  });

  T.push({
    name: 'worker_errors_stay_replies',
    fn: async () => {
      await fixtures;
      await using(null, async (worker) => {
        await open(worker);
        A.eq((await slash(worker, '/sdemo boom')).ok, true);
        A.eq((await call(worker, 'nope')).ok, false);
        A.eq((await call(worker, 'snapshot')).ok, undefined, 'a snapshot has no ok field unless it failed');
      });
    },
  });

  T.push({
    name: 'worker_c_stack_overflow_is_a_lua_error',
    fn: async () => {
      await fixtures;
      await using(null, async (worker) => {
        const seen = events(worker);
        await open(worker);
        const chunk =
          'local function f(n) if n == 0 then return true end local ok, e = pcall(f, n - 1) if not ok then error(e, 0) end return true end print(pcall(f, 300))';
        await slash(worker, '/run ' + chunk);
        await call(worker, 'snapshot'); // the events of a message follow its reply
        A.eq(consoleText(seen).some((text) => text.includes('C stack overflow')), true);
        A.eq(seen.some((e) => e.type === 'fatal'), false);
        A.eq((await call(worker, 'snapshot')).ok, undefined);
      });
    },
  });

  T.push({
    name: 'worker_addon_mount_is_read_only',
    fn: async () => {
      await fixtures;
      const probe = fsHook(
        'function (FS, TKW) {' +
          ' var out = {};' +
          ' try { FS.writeFile("/addon/SessionDemo/x.lua", "x"); out.addon = "wrote"; } catch (e) { out.addon = "threw"; }' +
          ' FS.writeFile(TKW.sessionDir(null, null, "SessionDemo") + "/x.lua", "x"); out.session = "wrote";' +
          ' return out; }',
      );
      await using(probe, async (worker) => {
        await open(worker);
        A.same(await send(worker, { type: 'probe' }), { addon: 'threw', session: 'wrote' });
      });
    },
  });

  T.push({
    name: 'worker_session_dir_per_account_character_addon',
    fn: async () => {
      await fixtures;
      const run = (character, text, reload) =>
        using(null, async (worker) => {
          const seen = events(worker);
          await open(worker, { account: 'A', character });
          await slash(worker, text);
          if (reload) await call(worker, 'reload');
          await call(worker, 'snapshot'); // the events of a message follow its reply

          return consoleText(seen);
        });
      await run('Realm/Char', '/run SessionDemoDB.tag = "A1"', true);
      A.same((await run('Realm/Other', '/dump SessionDemoDB.tag')).slice(-1), ['nil']);
      A.same((await run('Realm/Char', '/dump SessionDemoDB.tag')).slice(-1), ['A1']);
      const dirs = fsHook(
        'function (FS, TKW) { return [TKW.sessionDir("A", "Realm/Char", "SessionDemo"), TKW.sessionDir(null, null, "SessionDemo")]; }',
      );
      await using(dirs, async (worker) => {
        await open(worker);
        A.same(await send(worker, { type: 'probe' }), ['/session/A/Realm/Char/SessionDemo', '/session/_none/_account/SessionDemo']);
      });
    },
  });

  T.push({
    name: 'worker_unknown_message_and_early_call_are_error_replies',
    fn: async () => {
      await using(null, async (worker) => {
        A.same(await send(worker, { type: 'nope' }), { ok: false, error: 'unknown message nope' });
        A.same(await call(worker, 'snapshot'), { ok: false, error: 'not open' });
      });
    },
  });

  T.push({
    name: 'worker_workerfs_reads_ahead',
    fn: async () => {
      await fixtures;
      const size = 3 * 1048576 + 5;
      const probe = fsHook(
        'function (FS, TKW) {' +
          ' var bytes = new Uint8Array(' + size + '); for (var i = 0; i < bytes.length; i++) bytes[i] = i % 251;' +
          ' FS.mkdirTree("/ra"); FS.mount(TKW.mod.WORKERFS, { blobs: [{ name: "big.bin", data: new Blob([bytes]) }] }, "/ra");' +
          ' var reader = TKW.mod.WORKERFS.reader, slices = 0, real = reader.readAsArrayBuffer.bind(reader);' +
          ' reader.readAsArrayBuffer = function (blob) { slices++; return real(blob); };' +
          ' var stream = FS.open("/ra/big.bin", "r"), buf = new Uint8Array(4096), pos = 0, bad = 0, n;' +
          ' while ((n = FS.read(stream, buf, 0, 4096, pos)) > 0) {' +
          '   for (var j = 0; j < n; j++) if (buf[j] !== (pos + j) % 251) bad++;' +
          '   pos += n;' +
          ' }' +
          ' FS.close(stream); return { total: pos, slices: slices, bad: bad }; }',
      );
      await using(probe, async (worker) => {
        await open(worker);
        A.same(await send(worker, { type: 'probe' }), { total: size, slices: 4, bad: 0 });
      });
    },
  });
})();
