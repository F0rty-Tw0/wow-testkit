// The browser host's worker: wasm/bundle.py appends this file to the kit files (TK_KIT_FILES) and the Emscripten module
// (Module), and the page starts a Blob worker from the whole. It owns the Lua runtime: writes the kit to /kit, mounts
// the picked folders, runs the messages one at a time in arrival order and answers each with one reply, then the
// events SessionHost queued. A reply never arrives before the IndexedDB sync of the state it reports (a failed sync
// adds syncError to it). Each session folder is its own IDBFS mount, held by one worker at a time. File names under
// the picked folders match case-insensitively, like Windows and the game client (caseInsensitive).
(function () {
  const post = (msg) => self.postMessage(msg);
  const message = (err) => String((err && err.message) || err);
  const READ_AHEAD = 1 << 20;
  const LOCK_WAIT_MS = 2000;
  const PICKED_ROOTS = ['/addon', '/extract', '/wtf'];

  const TKW = (self.TKW = { mod: null, sessionDir, caseInsensitive });

  const unsafePart = (part) =>
    typeof part !== 'string' || part === '' || part === '.' || part === '..' || /[/\\\x00-\x1f]/.test(part);

  // The session folder of one addon for one account and character: SavedVariables live per combination. The names come
  // from the page's stored choices, so a character that is not "Realm/Character" or a part that is empty, "." or ".."
  // or holds a slash, a backslash or a control character throws.
  function sessionDir(account, character, addonFolder) {
    const where = character ? character.split('/') : ['_account'];
    const parts = [account || '_none', ...where, addonFolder];
    const shaped = !character || where.length === 2;
    if (!shaped || parts.some(unsafePart)) throw new Error('bad session folder: ' + JSON.stringify([account, character, addonFolder]));

    return '/session/' + parts.join('/');
  }

  // Holds the Web Lock named dir for the life of the worker, so a second tab on the same session is refused. The lock of
  // this tab's previous worker goes a moment after its terminate, so the wait lasts up to LOCK_WAIT_MS.
  function lockSession(dir) {
    return new Promise((resolve, reject) => {
      const abort = new AbortController();
      const timer = setTimeout(() => abort.abort(), LOCK_WAIT_MS);
      const held = () => {
        clearTimeout(timer);
        resolve();

        return new Promise(() => {});
      };
      const refused = (err) => reject(err.name === 'AbortError' ? new Error('this session is open in another tab: ' + dir) : err);
      navigator.locks.request(dir, { signal: abort.signal }, held).catch(refused);
    });
  }

  // WORKERFS reads one BUFSIZ piece of a Blob per synchronous slice read, about 0.72 ms per KB, so a 20 MB SavedVariables
  // file took 15 s through Lua's io. This keeps the last 1 MiB read of each file and serves the pieces from it.
  function readAhead(WORKERFS) {
    WORKERFS.stream_ops.read = (stream, buffer, offset, length, position) => {
      const node = stream.node;
      const want = Math.min(length, node.size - position);
      let got = 0;
      while (got < want) {
        const at = position + got;
        let cache = node.readAhead;
        if (!cache || at < cache.start || at >= cache.start + cache.bytes.length) {
          const slice = node.contents.slice(at, Math.min(node.size, at + READ_AHEAD));
          cache = node.readAhead = { start: at, bytes: new Uint8Array(WORKERFS.reader.readAsArrayBuffer(slice)) };
        }
        const from = at - cache.start;
        const take = Math.min(want - got, cache.bytes.length - from);
        buffer.set(cache.bytes.subarray(from, from + take), offset + got);
        got += take;
      }

      return got;
    };
  }

  // Emscripten resolves every path component through FS.lookupNode. Under roots, a name with no exact match resolves to the
  // entry of its parent that matches ignoring case (the first in sorted order when several do); listings keep the real
  // names, and names elsewhere stay exact.
  function caseInsensitive(FS, roots) {
    const exact = FS.lookupNode;
    FS.lookupNode = function (parent, name) {
      try {
        return exact.call(FS, parent, name);
      } catch (err) {
        const dir = err && err.errno === 44 ? FS.getPath(parent) : null;
        if (dir === null || !roots.some((root) => dir === root || dir.startsWith(root + '/'))) throw err;
        const want = name.toLowerCase();
        const hit = FS.readdir(dir)
          .filter((entry) => entry !== '.' && entry !== '..')
          .sort()
          .find((entry) => entry.toLowerCase() === want);
        if (hit === undefined) throw err;

        return exact.call(FS, parent, hit);
      }
    };
  }

  // Encodes with the native TextEncoder and hands MEMFS the bytes (canOwn): FS.writeFile on a string runs a JS loop per
  // character twice (length, then encode) and copies, ~290 ms of the worker's ~570 ms start-up for the 21 MB kit.
  function writeKit(FS) {
    const encoder = new TextEncoder();
    for (const path of Object.keys(TK_KIT_FILES)) {
      const full = '/kit/' + path;
      FS.mkdirTree(full.slice(0, full.lastIndexOf('/')));
      FS.writeFile(full, encoder.encode(TK_KIT_FILES[path]), { canOwn: true });
    }
  }

  function syncfs(populate) {
    return new Promise((resolve, reject) => {
      TKW.mod.FS.syncfs(populate, (err) => (err ? reject(err) : resolve()));
    });
  }

  const mounted = new Set();
  let addonFolder = null;

  // A read-only WORKERFS folder at dir holding the picked files ([{ path, file }], path relative to the folder); a folder
  // mounted there before is replaced.
  function mountFiles(dir, entries) {
    const mod = TKW.mod;
    if (mounted.has(dir)) mod.FS.unmount(dir);
    mod.FS.mkdirTree(dir);
    mod.FS.mount(mod.WORKERFS, { blobs: entries.map((entry) => ({ name: entry.path, data: entry.file })) }, dir);
    mounted.add(dir);
  }

  // opts.wtf of an open: the paths under /wtf of the addon's account file and its character file (Realm/Character/...),
  // each key only when the walk found that file. Names match ignoring case, the paths keep the real ones.
  function wtfPaths(entries, folder) {
    const tail = ('SavedVariables/' + folder + '.lua').toLowerCase();
    const paths = entries.map((entry) => entry.path);
    const account = paths.find((path) => path.toLowerCase() === tail);
    const character = paths.find((path) => path.split('/').length === 4 && path.toLowerCase().endsWith('/' + tail));
    const out = {};
    if (account) out.account = '/wtf/' + account;
    if (character) out.character = '/wtf/' + character;

    return out;
  }

  let lastError = '';
  const ready = Module({
    print: (text) => console.log(text),
    printErr: (text) => {
      lastError = text;
      console.warn(text);
    },
    onAbort: (what) => post({ type: 'fatal', error: String(what) }),
  }).then((mod) => {
    TKW.mod = mod;
    writeKit(mod.FS);
    readAhead(mod.WORKERFS);
    caseInsensitive(mod.FS, PICKED_ROOTS);
    if (mod.ccall('tk_init', 'number', [], []) !== 0) throw new Error('tk_init failed: ' + lastError);
  });
  ready.catch((err) => post({ type: 'fatal', error: message(err) }));

  const ccall = (name, args) => TKW.mod.ccall(name, 'string', args.map(() => 'string'), args);
  const body = (req) => (typeof req === 'string' ? req : JSON.stringify(req || {}));

  // The events SessionHost queued since the last drain, as the messages the page gets.
  function drained() {
    const queued = JSON.parse(ccall('tk_drain', []));

    return Array.isArray(queued) ? queued.map((e) => ({ type: 'event', name: e.event, data: e.data })) : [];
  }

  // The reply and events after the IndexedDB sync of what the message wrote. A failed sync still answers with the
  // message's reply, plus syncError, and its events.
  async function synced(json, events) {
    try {
      await syncfs(false);
    } catch (err) {
      const reply = JSON.parse(json);
      reply.syncError = message(err);

      return { json: JSON.stringify(reply), events };
    }

    return { json, events };
  }

  // The reply of a call that may have reloaded the session: the events SessionHost queued, and the sync of the saved
  // variables a reload wrote before the reply goes out.
  function settled(json) {
    const events = drained();
    const reloaded = events.some((e) => e.name === 'reload');

    return reloaded ? synced(json, events) : { json, events };
  }

  const handlers = {
    async open(msg) {
      const FS = TKW.mod.FS;
      const dir = sessionDir(msg.account, msg.character, msg.addonFolder);
      await lockSession(dir);
      addonFolder = msg.addonFolder;
      mountFiles('/addon/' + addonFolder, msg.addon);
      if (msg.extract) mountFiles('/extract', msg.extract);
      if (msg.wtf) mountFiles('/wtf', msg.wtf);
      // IDBFS names its database after the mount point, so each session folder has its own: a sync writes and deletes
      // only this session's files, and a tab on another session keeps its own.
      FS.mkdirTree(dir);
      FS.mount(TKW.mod.IDBFS, {}, dir);
      await syncfs(true);
      const opts = { addonDir: '/addon/' + msg.addonFolder, sessionDir: dir, flavor: 'auto' };
      if (msg.extract) opts.extract = '/extract';
      if (msg.wtf) Object.assign(opts, { wtf: wtfPaths(msg.wtf, addonFolder), wtfRoot: '/wtf' }); // reimport paths stay in /wtf
      const json = ccall('tk_open', [JSON.stringify(opts)]);
      const events = drained();

      return msg.wtf ? synced(json, events) : { json, events }; // the import wrote saved.lua
    },

    call(msg) {
      return settled(ccall('tk_call', [msg.method, body(msg.req)]));
    },

    // The picked addon folder changed: mount its new files and reload the session over them.
    remount(msg) {
      if (addonFolder) mountFiles('/addon/' + addonFolder, msg.addon);

      return settled(ccall('tk_call', ['reload', '{}']));
    },

    // The WTF folder was listed again: mount its new files; SessionHost re-reads the paths found in them and reloads.
    reimport(msg) {
      if (!addonFolder) return settled(ccall('tk_call', ['reimport', '{}']));
      mountFiles('/wtf', msg.wtf);
      const req = { wtf: wtfPaths(msg.wtf, addonFolder) };

      return settled(ccall('tk_call', ['reimport', JSON.stringify(req)]));
    },

    pagehide() {
      TKW.mod.ccall('tk_shutdown', null, [], []);

      return synced('{"ok":true}', []);
    },
  };

  async function handle(msg) {
    const handler = handlers[msg.type];
    let result;
    try {
      result = handler ? await handler(msg) : { json: JSON.stringify({ ok: false, error: 'unknown message ' + msg.type }) };
    } catch (err) {
      result = { json: JSON.stringify({ ok: false, error: message(err) }) };
    }
    post({ type: 'reply', id: msg.id, json: result.json });
    (result.events || []).forEach(post);
  }

  // One promise chain: a startup failure was posted as fatal, and later messages answer with their own error.
  let chain = ready.catch(() => {});
  self.onmessage = (ev) => {
    chain = chain.then(() => handle(ev.data));
  };
})();
