// The browser host's controller (browser host spec 4.1, 5, 6, 7): sole owner of the picked directory handles, it starts
// the worker, sends the open, remount and call messages, and moves the host states by the table in host_state.js.
// Needs host_fs.js and host_state.js. Classic script on the global TK.
window.TK = window.TK || {};

(function (TK) {
  'use strict';

  const { walk, wtfEntries, watch, next, watchdog, realTimers } = TK.host;

  // A worker over the bundled source (TK_WORKER_SRC); file:// pages cannot start one from a URL, so it runs from a Blob.
  function spawnWorker() {
    const url = URL.createObjectURL(new Blob([TK_WORKER_SRC]));
    const worker = new Worker(url);
    const end = worker.terminate.bind(worker);
    worker.terminate = () => {
      end();
      URL.revokeObjectURL(url);
    };

    return worker;
  }

  const byPath = (entries) => new Map(entries.map((entry) => [entry.path, entry.file]));

  // The messages of the controller to its worker, and what comes back, run through the table. deps = { addon, extract?,
  // wtf?, character?, account, timers?, poll?, spawn? } with handles already granted. timers hold setTimeout and
  // clearTimeout and the watchdog's callMs and openMs; poll the addon poll interval and quiet window in ms; spawn makes the
  // worker (the checks pass a scripted one). A call of the method reimport lists the WTF files again and posts reimport.
  // files() is the last walk of the addon and the extract, as Maps of path -> File, for the page's asset urls.
  function start(deps) {
    const dep = Object.assign({ timers: {}, poll: {}, win: window, spawn: spawnWorker }, deps);
    const clock = Object.assign({}, realTimers, dep.timers);
    const poll = Object.assign({ interval: 500, quiet: 300 }, dep.poll);
    const stateFns = [];
    const eventFns = [];
    const pending = new Map();
    let state = 'Picking';
    let worker = null;
    let dog = null;
    let watcher = null;
    let quietTimer = null;
    let remounts = 0;
    let edited = false;
    let queue = [];
    let nextId = 1;
    let shutDown = false;
    let files = { addon: new Map(), extract: new Map() };

    const show = (text) => {
      const el = document.getElementById('host-state');
      if (el) el.textContent = text;
    };

    function post(type, fields, method) {
      const id = nextId++;
      const sent = new Promise((resolve, fail) => pending.set(id, { type, method: method || type, resolve, fail }));
      dog.posted(id, type);
      worker.postMessage(Object.assign({ id, type }, fields));

      return sent;
    }

    // Ends the worker and fails everything it still owed an answer to.
    function closeWorker(reason) {
      clock.clearTimeout(quietTimer);
      if (dog) dog.stop();
      if (worker) worker.terminate();
      worker = null;
      remounts = 0;
      edited = false;
      const why = new Error(reason || 'runtime stopped');
      pending.forEach((entry) => entry.fail(why));
      pending.clear();
      queue.forEach((call) => call.reject(why));
      queue = [];
    }

    const handleFailed = (err) => dispatch('handleFail', 're-pick folder: ' + ((err && err.message) || err));

    async function openMessage() {
      const folder = dep.addon.name;
      const msg = { addonFolder: folder, addon: await walk(dep.addon), account: dep.account, character: dep.character };
      if (dep.extract) msg.extract = await walk(dep.extract);
      if (dep.wtf) msg.wtf = await wtfEntries(dep.wtf, folder, dep.character);
      files = { addon: byPath(msg.addon), extract: byPath(msg.extract || []) };

      return msg;
    }

    async function openSession() {
      closeWorker('restarted');
      shutDown = false;
      const mine = (worker = dep.spawn());
      dog = watchdog(Object.assign({}, clock, { onExpire: (type, seconds, id) => onExpire(mine, seconds, id) }));
      mine.onmessage = ({ data }) => mine === worker && onMessage(data);
      mine.onerror = (ev) => mine === worker && dispatch('fatal', 'runtime stopped: ' + ev.message);
      if (watcher) watcher.stop();
      watcher = watch(dep.addon, () => dispatch('fileChange'), handleFailed, Object.assign({}, clock, { interval: poll.interval }));
      let msg;
      try {
        msg = await openMessage();
      } catch (err) {
        if (mine === worker) handleFailed(err);

        return;
      }
      if (mine !== worker) return;
      post('open', msg).then((reply) => {
        const info = JSON.parse(reply);
        dispatch(info.ok ? 'openOk' : 'luaError', info.error);
      }, () => {});
    }

    function onExpire(mine, seconds, id) {
      if (mine !== worker || !pending.has(id)) return;
      dispatch('watchdog', 'addon code ran over ' + seconds + ' s (' + pending.get(id).method + ')');
    }

    function onMessage(data) {
      if (data.type === 'event') return eventFns.slice().forEach((fn) => fn(data.name, data.data));
      if (data.type === 'fatal') return dispatch('fatal', 'runtime stopped: ' + data.error);
      const entry = pending.get(data.id);
      if (data.type !== 'reply' || !entry) return undefined;
      pending.delete(data.id);
      dog.replied(data.id);

      return entry.resolve(data.json);
    }

    // The addon folder is quiet: list it again and have the worker remount it and reload. An edit can land while an earlier
    // remount is out, so the state leaves Reloading only when no remount is out and no edit waits for its quiet window.
    async function remount() {
      const mine = worker;
      edited = false;
      remounts++;
      let addon;
      try {
        addon = await walk(dep.addon);
      } catch (err) {
        remounts--;
        if (mine === worker) handleFailed(err);

        return;
      }
      if (mine !== worker) return;
      files = { addon: byPath(addon), extract: files.extract };
      post('remount', { addon }).then((reply) => {
        remounts--;
        if (remounts === 0 && !edited) dispatch(JSON.parse(reply).ok ? 'reloadReply' : 'luaError');
      }, () => {});
    }

    async function reimportMessage() {
      const mine = worker;
      const wtf = dep.wtf ? await wtfEntries(dep.wtf, dep.addon.name, dep.character) : [];
      if (mine !== worker) throw new Error('runtime stopped');

      return post('reimport', { wtf });
    }

    function send(call) {
      const sent = call.method === 'reimport' ? reimportMessage() : post('call', { method: call.method, req: call.req }, call.method);
      sent.then(call.resolve, call.reject);
    }

    const actions = {
      open: openSession,
      flush() {
        const calls = queue;
        queue = [];
        calls.forEach(send);
      },
      queue: (call) => queue.push(call),
      send,
      quiet() {
        edited = true;
        clock.clearTimeout(quietTimer);
        quietTimer = clock.setTimeout(remount, poll.quiet);
      },
      showError(text) {
        closeWorker('open failed');
        show(text);
      },
      terminate(text) {
        closeWorker(text);
        show(text);
      },
      shutdown() {
        shutDown = true;
        post('pagehide', {}).catch(() => {});
      },
    };

    function dispatch(event, info) {
      const step = next(state, event);
      const moved = step.state !== state;
      state = step.state;
      if (moved) stateFns.slice().forEach((fn) => fn(state));
      if (step.action && step.action.startsWith('reject:')) info.reject(new Error(step.action.slice(7)));
      else if (step.action) actions[step.action](info);
    }

    function postCall(method, req) {
      return new Promise((resolve, rejectCall) => dispatch('call', { method, req, resolve, reject: rejectCall }));
    }

    const onHide = () => dispatch('pagehide');
    const onShow = (ev) => ev.persisted && shutDown && dispatch('pageshowPersisted');
    dep.win.addEventListener('pagehide', onHide);
    dep.win.addEventListener('pageshow', onShow);

    dispatch('granted');

    return {
      state: () => state,
      files: () => files,
      postCall,
      api: (method, req) => postCall(method, req).then(JSON.parse),
      restart: () => dispatch('restart'),
      onState: (fn) => stateFns.push(fn),
      onEvent: (fn) => eventFns.push(fn),
      stop() {
        if (watcher) watcher.stop();
        closeWorker('stopped');
        dep.win.removeEventListener('pagehide', onHide);
        dep.win.removeEventListener('pageshow', onShow);
      },
    };
  }

  TK.host.start = start;
})(window.TK);
