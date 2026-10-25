// The browser host's folder handling (browser host spec 4.1, 5.2, 5.8): walks a picked directory handle into the
// [{ path, file }] lists the worker mounts, picks the WTF files of one addon, and polls the addon folder for edits. It
// touches a handle only through entries() and getFile(), so the checks pass fakes (tests/wasm/fakes.js). Classic script
// on the global TK; host.js builds the controller on these.
window.TK = window.TK || {};

(function (TK) {
  'use strict';

  const SOURCES = /\.(lua|xml|toc)$/i;
  const byPath = (a, b) => Number(a.path > b.path) - Number(a.path < b.path);
  const byName = (a, b) => Number(a[0] > b[0]) - Number(a[0] < b[0]);
  // setTimeout and clearTimeout behind arrows: the browser's own lose their window when called as a method of deps.
  const realTimers = { setTimeout: (fn, ms) => setTimeout(fn, ms), clearTimeout: (id) => clearTimeout(id) };

  // The [name, handle] pairs of dir, sorted by name.
  async function list(dir) {
    const out = [];
    for await (const entry of dir.entries()) out.push(entry);

    return out.sort(byName);
  }

  // Every file under dir whose name keep() accepts, as { path, file } (one getFile() each); dot-directories are skipped.
  async function collect(dir, keep, prefix = '') {
    const found = await Promise.all(
      (await list(dir)).map(async ([name, handle]) => {
        if (handle.kind === 'directory') return name.startsWith('.') ? [] : collect(handle, keep, prefix + name + '/');

        return keep(name) ? [{ path: prefix + name, file: await handle.getFile() }] : [];
      }),
    );

    return found.flat();
  }

  async function walk(dir) {
    const files = await collect(dir, () => true);

    return files.sort(byPath);
  }

  // The entry of dir named name: the exact spelling, else the first that matches ignoring case (names sorted), else null.
  async function child(dir, name) {
    const entries = await list(dir);
    const want = name.toLowerCase();

    return entries.find(([entry]) => entry === name) || entries.find(([entry]) => entry.toLowerCase() === want) || null;
  }

  // The "<Realm>/<Character>" folders of a WTF account folder.
  async function characters(wtfDir) {
    const found = [];
    for (const [realm, handle] of await list(wtfDir)) {
      if (handle.kind !== 'directory' || realm.startsWith('.') || realm.toLowerCase() === 'savedvariables') continue;
      for (const [name, sub] of await list(handle)) {
        if (sub.kind === 'directory' && !name.startsWith('.')) found.push(realm + '/' + name);
      }
    }

    return found.sort();
  }

  // The character a launch may use: the stored choice only when names, the folders characters() listed (null when the
  // listing failed), hold it. The choice comes from IndexedDB, so it is never trusted on its own.
  const characterOf = (names, stored) => (names && names.includes(stored) ? stored : undefined);

  // The addon's SavedVariables file under dir, as a list of zero or one { path, file }; path keeps the on-disk spelling.
  async function savedFile(dir, prefix, addonFolder) {
    const folder = await child(dir, 'SavedVariables');
    const file = folder && folder[1].kind === 'directory' ? await child(folder[1], addonFolder + '.lua') : null;
    if (!file || file[1].kind !== 'file') return [];

    return [{ path: prefix + folder[0] + '/' + file[0], file: await file[1].getFile() }];
  }

  // Only the addon's SavedVariables files of a WTF account folder: the account file and, with a character
  // ("Realm/Character"), that character's. Names match ignoring case.
  async function wtfEntries(wtfDir, addonFolder, character) {
    const out = await savedFile(wtfDir, '', addonFolder);
    let dir = wtfDir;
    let prefix = '';
    for (const part of character ? character.split('/') : []) {
      const hit = await child(dir, part);
      if (!hit || hit[1].kind !== 'directory') return out.sort(byPath);
      dir = hit[1];
      prefix += hit[0] + '/';
    }
    if (dir !== wtfDir) out.push(...(await savedFile(dir, prefix, addonFolder)));

    return out.sort(byPath);
  }

  // path -> "lastModified:size" of the .lua .xml .toc files among files ([{ path, file }], a walk's list).
  function stampsOf(files) {
    const sources = files.filter(({ path }) => SOURCES.test(path));

    return new Map(sources.sort(byPath).map(({ path, file }) => [path, file.lastModified + ':' + file.size]));
  }

  // stampsOf every .lua .xml .toc file under dir. A File is a snapshot, so each entry gets a fresh one.
  async function stamp(dir) {
    const files = await collect(dir, (name) => SOURCES.test(name));

    return stampsOf(files);
  }

  // Whether a path was added, removed or has another stamp.
  function changed(a, b) {
    return a.size !== b.size || [...a].some(([path, value]) => b.get(path) !== value);
  }

  // Stamps dir at once and then every interval (the next wait starts when a stamp ends), calling onChange() when
  // the stamp changed. deps.since is the stamp to compare the first one with (stampsOf a walk); without it the first
  // stamp is the baseline. A throwing entries() or getFile() calls onFail(err) once and ends the polling.
  function watch(dir, onChange, onFail, deps) {
    const dep = Object.assign({ interval: 500, since: null }, realTimers, deps);
    let last = dep.since;
    let timer = null;
    let stopped = false;

    async function tick() {
      let moved = false;
      try {
        const now = await stamp(dir);
        moved = last !== null && changed(last, now);
        last = now;
      } catch (err) {
        if (!stopped) onFail(err);
        stopped = true;

        return;
      }
      if (stopped) return;
      if (moved) onChange();
      if (!stopped) timer = dep.setTimeout(tick, dep.interval);
    }

    tick();

    return {
      stop() {
        stopped = true;
        dep.clearTimeout(timer);
      },
    };
  }

  TK.host = Object.assign(TK.host || {}, { walk, characters, characterOf, wtfEntries, stamp, stampsOf, changed, watch, realTimers });
})(window.TK);
