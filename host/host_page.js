// The browser host's page (browser host spec 4.1, 5.1, 5.7, 6, 7, 10): the folder pickers and their stored handles, the
// one-click re-grant on a revisit, and the strip over the viewer (state, kit-only banner, missing-art badge, Restart,
// Re-pick, Re-import). TK.api reaches the controller of host.js through the worker backend of transport.js; a call made
// before the first launch waits for it, so the viewer's panels can ask at DOMContentLoaded. A snapshot reply gets its
// asset urls here (host_assets.js). The pickers wire up on a page whose body has data-host-page (host/index.html); the
// checks call TK.hostPage.launch with fake handles. Classic script on the global TK.
window.TK = window.TK || {};

(function (TK) {
  'use strict';

  const { start, store, characters, characterOf } = TK.host;
  const { resolve: resolveAssets, dropAddon } = TK.hostAssets;
  const KINDS = ['addon', 'extract', 'wtf'];
  const LABELS = { addon: 'Addon folder', extract: 'Client extract (optional)', wtf: 'WTF account (optional)' };
  const NO_EXTRACT = 'No client extract: the world is kit-only and art uses stand-ins.';
  const UNSUPPORTED = 'Chromium only: this page needs the File System Access API (showDirectoryPicker).';
  const page = { ctl: null, waiting: [], listeners: [], cache: new Map(), boots: 0, repick: 'addon' };
  const picked = { addon: null, extract: null, wtf: null, character: undefined };
  const byId = (id) => document.getElementById(id);

  function reveal(id, on) {
    const node = byId(id);
    if (node) node.hidden = !on;
  }

  function say(text) {
    const node = byId('host-state');
    if (node) node.textContent = text;
  }

  function onClick(id, fn) {
    const node = byId(id);
    if (node) node.addEventListener('click', fn);
  }

  const emit = (name, data) => page.listeners.slice().forEach((fn) => fn(name, data));

  function showMissing(count) {
    const badge = byId('missing-art');
    if (!badge) return;
    badge.hidden = count === 0;
    badge.textContent = count + ' missing art';
  }

  // A snapshot reply with urls for its assets, and the badge set to its misses. An error reply passes as it came.
  async function withUrls(ctl, text) {
    const snapshot = JSON.parse(text);
    if (snapshot.ok === false) return text;
    const misses = await resolveAssets(snapshot, ctl.files(), page.cache);
    showMissing(misses);

    return JSON.stringify(snapshot);
  }

  function postCall(method, req) {
    const ctl = page.ctl;
    if (!ctl) return new Promise((resolve, reject) => page.waiting.push({ method, req, resolve, reject }));
    const sent = ctl.postCall(method, req);

    return method === 'snapshot' ? sent.then((text) => withUrls(ctl, text)) : sent;
  }

  const backend = TK.transport.worker({ postCall, onEvent: (fn) => page.listeners.push(fn) });

  // Follows ctl's states on the strip. Each worker that opens says hello with a boot of its own, as a restarted Python
  // host does, so the viewer numbers its snapshots and console lines afresh (live.js); a reload drops the addon's urls.
  function follow(ctl) {
    let last = ctl.state();
    ctl.onState((state) => {
      if (ctl !== page.ctl) return;
      if (state === 'Running' && last === 'Loading') emit('hello', { boot: 'worker-' + ++page.boots });
      if (state === 'Running' && last === 'Reloading') dropAddon(page.cache);
      last = state;
      say(state);
      reveal('restart', state === 'Stopped');
      reveal('repick', state === 'NeedsRepick');
      if (state === 'NeedsRepick') page.repick = ctl.failedKind();
    });
    ctl.onEvent((name, data) => ctl === page.ctl && emit(name, data));
  }

  // Starts a controller on granted handles (deps as TK.host.start takes them) in place of the one before, and sends it
  // the calls that waited for a launch.
  function launch(deps) {
    if (page.ctl) page.ctl.stop();
    page.cache.forEach((url) => url.then((href) => href && URL.revokeObjectURL(href)));
    page.cache = new Map();
    const ctl = (page.ctl = start(deps));
    follow(ctl);
    say(ctl.state());
    const banner = byId('banner');
    if (banner) banner.textContent = NO_EXTRACT;
    reveal('banner', !deps.extract);
    reveal('reimport', Boolean(deps.wtf));
    reveal('restart', false);
    reveal('repick', false);
    showMissing(0);
    const calls = page.waiting;
    page.waiting = [];
    calls.forEach((call) => postCall(call.method, call.req).then(call.resolve, call.reject));

    return ctl;
  }

  function reimport() {
    const failed = (why) => say('Re-import failed: ' + why);
    TK.api('reimport', {}).then((reply) => reply.ok === false && failed(reply.error), (err) => failed(err.message));
  }

  // The character select: "account only" plus the Realm/Character folders of the WTF folder. Before the folder is granted
  // again on a revisit it cannot be listed, so the stored choice is the only one shown, and kept unchecked: Start lists
  // the folder again and launches only a listed character (characterOf). Returns the listed names, or null.
  async function listCharacters() {
    const select = byId('character');
    let names = null;
    try {
      names = await characters(picked.wtf);
    } catch (err) {
      // not granted yet
    }
    if (names) picked.character = characterOf(names, picked.character);
    const shown = names || (picked.character ? [picked.character] : []);
    const options = [['account only', '']].concat(shown.map((name) => [name, name]));
    select.replaceChildren(...options.map(([text, value]) => new Option(text, value)));
    select.value = picked.character || '';

    return names;
  }

  function showPicks() {
    KINDS.forEach((kind) => {
      const handle = picked[kind];
      byId('pick-' + kind).textContent = handle ? LABELS[kind].replace(' (optional)', '') + ': ' + handle.name : LABELS[kind];
    });
    byId('character').hidden = !picked.wtf;
    byId('start').disabled = !picked.addon;
  }

  async function pick(kind) {
    let handle;
    try {
      handle = await window.showDirectoryPicker({ id: kind, mode: 'read' });
    } catch (err) {
      return false; // the picker was closed
    }
    picked[kind] = handle;
    store.put(kind, handle).catch(() => {});
    if (kind === 'wtf') await listCharacters();
    showPicks();

    return true;
  }

  // Start (also the revisit's one click): every picked handle asks for read access at once, inside the click; a denied
  // one needs a re-pick.
  async function startPicked() {
    const kinds = KINDS.filter((kind) => picked[kind]);
    const asks = kinds.map((kind) => picked[kind].requestPermission({ mode: 'read' }).catch(() => 'denied'));
    const answers = await Promise.all(asks);
    const denied = kinds.filter((kind, index) => answers[index] !== 'granted');
    if (denied.length > 0) {
      page.repick = denied[0];
      say('NeedsRepick: no read access to the ' + denied.map((kind) => LABELS[kind].split(' (')[0]).join(', ') + '; pick it again');
      reveal('repick', true);

      return;
    }
    const names = picked.wtf ? await listCharacters() : null;
    if (picked.wtf && !names) byId('character').value = ''; // the WTF folder did not list: the launch is account only
    const wtf = picked.wtf || undefined;
    const character = wtf && characterOf(names, picked.character);
    launch({ addon: picked.addon, extract: picked.extract || undefined, wtf, character, account: wtf && wtf.name });
  }

  async function repick() {
    const chosen = await pick(page.repick);
    if (chosen) await startPicked();
  }

  async function restore() {
    for (const key of KINDS.concat('character')) {
      picked[key] = await store.get(key).catch(() => undefined);
    }
    if (picked.wtf) await listCharacters();
    showPicks();
  }

  function boot() {
    if (typeof window.showDirectoryPicker !== 'function') {
      const note = document.createElement('p');
      note.id = 'unsupported';
      note.textContent = UNSUPPORTED;
      document.body.replaceChildren(note);

      return;
    }
    say('Picking: choose the addon folder (the client extract and a WTF account folder are optional), then Start.');
    KINDS.forEach((kind) => onClick('pick-' + kind, () => pick(kind)));
    byId('character').addEventListener('change', (ev) => {
      picked.character = ev.target.value || undefined;
      store.put('character', picked.character).catch(() => {});
    });
    onClick('start', startPicked);
    showPicks();
    restore();
  }

  TK.transport.use(backend);
  onClick('restart', () => page.ctl && page.ctl.restart());
  onClick('repick', repick);
  onClick('reimport', reimport);
  TK.hostPage = { launch };
  if ('hostPage' in document.body.dataset) boot();
})(window.TK);
