// The browser host's rules (browser host spec 6, 7): the state table as data, the watchdog timer for the message the
// worker is running, and the IndexedDB store of the picked handles. Pure of the page and the worker, so the checks call
// them directly. Needs host_fs.js. Classic script on the global TK.
window.TK = window.TK || {};

(function (TK) {
  'use strict';

  const { realTimers } = TK.host;

  // Spec 6 as data: event -> state -> [new state (null: stays), action]. A missing cell ignores the event.
  const refuse = (why) => [null, 'reject:' + why];
  const live = ['Loading', 'Running', 'Reloading'];
  const toAll = (to, action) => Object.fromEntries(live.map((state) => [state, [to, action]]));
  const TABLE = {
    granted: { Picking: ['Loading', 'open'], NeedsRepick: ['Loading', 'open'] },
    openOk: { Loading: ['Running', 'flush'] },
    call: {
      Picking: refuse('not running'),
      Loading: [null, 'queue'],
      Running: [null, 'send'],
      Reloading: [null, 'queue'],
      Stopped: refuse('runtime stopped'),
      NeedsRepick: refuse('re-pick folder'),
    },
    fileChange: { Running: ['Reloading', 'quiet'], Reloading: [null, 'quiet'] },
    reloadReply: { Reloading: ['Running', 'flush'] },
    luaError: { Loading: ['Picking', 'showError'], Reloading: ['Running', 'flush'] },
    watchdog: toAll('Stopped', 'terminate'),
    fatal: toAll('Stopped', 'terminate'),
    handleFail: toAll('NeedsRepick', 'terminate'),
    restart: { Stopped: ['Loading', 'open'] },
    pagehide: { Running: ['Stopped', 'shutdown'], Reloading: ['Stopped', 'shutdown'] },
    pageshowPersisted: { Stopped: ['Loading', 'open'] },
  };

  function next(state, event) {
    const cell = (TABLE[event] || {})[state];

    return cell ? { state: cell[0] || state, action: cell[1] } : { state, action: null };
  }

  // One timer for the message the worker is running. It starts when the message is posted to an idle worker, else when
  // the one before it is answered; the matching reply clears it, and expiry calls onExpire(type, seconds, id).
  function watchdog(deps) {
    const dep = Object.assign({ callMs: 10000, openMs: 60000 }, realTimers, deps);
    let waiting = [];
    let timer = null;

    function arm() {
      const head = waiting[0];
      if (!head) return;
      const ms = head.type === 'open' ? dep.openMs : dep.callMs;
      timer = dep.setTimeout(() => dep.onExpire(head.type, ms / 1000, head.id), ms);
    }

    return {
      posted(id, type) {
        waiting.push({ id, type });
        if (waiting.length === 1) arm();
      },
      replied(id) {
        const running = waiting.length > 0 && waiting[0].id === id;
        waiting = waiting.filter((entry) => entry.id !== id);
        if (!running) return;
        dep.clearTimeout(timer);
        arm();
      },
      stop() {
        waiting = [];
        dep.clearTimeout(timer);
      },
    };
  }

  // The directory handles live in IndexedDB (database tk-host, object store handles) under addon, extract, wtf, character.
  let opened = null;
  function request(mode, make) {
    opened =
      opened ||
      new Promise((resolve, reject) => {
        const req = indexedDB.open('tk-host', 1);
        req.onupgradeneeded = () => req.result.createObjectStore('handles');
        req.onsuccess = () => resolve(req.result);
        req.onerror = () => reject(req.error);
      });

    return opened.then(
      (db) =>
        new Promise((resolve, reject) => {
          const tx = db.transaction('handles', mode);
          const req = make(tx.objectStore('handles'));
          tx.oncomplete = () => resolve(req.result);
          tx.onerror = tx.onabort = () => reject(tx.error);
        }),
    );
  }
  const store = {
    get: (key) => request('readonly', (handles) => handles.get(key)),
    put: (key, value) => request('readwrite', (handles) => handles.put(value, key)),
  };

  TK.host = Object.assign(TK.host || {}, { next, watchdog, store });
})(window.TK);
