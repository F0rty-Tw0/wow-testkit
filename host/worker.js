// The browser host's worker: wasm/bundle.py appends this file to the kit files (TK_KIT_FILES) and the Emscripten module
// (Module), and the page starts a Blob worker from the whole. It owns the Lua runtime: writes the kit to /kit, mounts
// the picked folders, runs the messages one at a time in arrival order and answers each with one reply, then the
// events SessionHost queued. A reply never arrives before the IndexedDB sync of the state it reports.
(function () {
  const post = (msg) => self.postMessage(msg);
  const READ_AHEAD = 1 << 20;

  const TKW = (self.TKW = { mod: null, sessionDir });

  // The session folder of one addon for one account and character: SavedVariables live per combination.
  function sessionDir(account, character, addonFolder) {
    return '/session/' + (account || '_none') + '/' + (character || '_account') + '/' + addonFolder;
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

  function writeKit(FS) {
    for (const path of Object.keys(TK_KIT_FILES)) {
      const full = '/kit/' + path;
      FS.mkdirTree(full.slice(0, full.lastIndexOf('/')));
      FS.writeFile(full, TK_KIT_FILES[path]);
    }
  }

  function syncfs(populate) {
    return new Promise((resolve, reject) => {
      TKW.mod.FS.syncfs(populate, (err) => (err ? reject(err) : resolve()));
    });
  }

  // A read-only WORKERFS folder at dir holding the picked files ([{ path, file }], path relative to the folder).
  function mountFiles(dir, entries) {
    const mod = TKW.mod;
    mod.FS.mkdirTree(dir);
    mod.FS.mount(mod.WORKERFS, { blobs: entries.map((entry) => ({ name: entry.path, data: entry.file })) }, dir);
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
    if (mod.ccall('tk_init', 'number', [], []) !== 0) throw new Error('tk_init failed: ' + lastError);
  });
  ready.catch((err) => post({ type: 'fatal', error: String((err && err.message) || err) }));

  const ccall = (name, args) => TKW.mod.ccall(name, 'string', args.map(() => 'string'), args);
  const body = (req) => (typeof req === 'string' ? req : JSON.stringify(req || {}));

  // The events SessionHost queued since the last drain, as the messages the page gets.
  function drained() {
    const queued = JSON.parse(ccall('tk_drain', []));

    return Array.isArray(queued) ? queued.map((e) => ({ type: 'event', name: e.event, data: e.data })) : [];
  }

  const handlers = {
    async open(msg) {
      const FS = TKW.mod.FS;
      mountFiles('/addon/' + msg.addonFolder, msg.addon);
      if (msg.extract) mountFiles('/extract', msg.extract);
      FS.mkdirTree('/session');
      FS.mount(TKW.mod.IDBFS, {}, '/session');
      await syncfs(true);
      const dir = sessionDir(msg.account, msg.character, msg.addonFolder);
      FS.mkdirTree(dir);
      const opts = { addonDir: '/addon/' + msg.addonFolder, sessionDir: dir, flavor: 'auto' };
      if (msg.extract) opts.extract = '/extract';

      return { json: ccall('tk_open', [JSON.stringify(opts)]), events: drained() };
    },

    async call(msg) {
      const json = ccall('tk_call', [msg.method, body(msg.req)]);
      const events = drained();
      if (events.some((e) => e.name === 'reload')) await syncfs(false);

      return { json, events };
    },
  };

  async function handle(msg) {
    const handler = handlers[msg.type];
    let result;
    try {
      result = handler ? await handler(msg) : { json: JSON.stringify({ ok: false, error: 'unknown message ' + msg.type }) };
    } catch (err) {
      result = { json: JSON.stringify({ ok: false, error: String((err && err.message) || err) }) };
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
