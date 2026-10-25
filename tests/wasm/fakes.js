// Fakes for the host checks: fakeDir(tree, name) stands in for a FileSystemDirectoryHandle (kind, name, entries(),
// requestPermission(); a file has kind, name, getFile()) and fakeTimers() for setTimeout, so the checks drive time by hand.
// treeOf(flat) nests { "a/b.lua": text } into the { name: text | Blob | subtree } shape fakeDir takes.
(function () {
  'use strict';

  // lastModified of the next edit: a counter, so two edits inside one millisecond still differ.
  let clock = 1000;
  const bump = () => ++clock;

  const gone = () => new DOMException('The file or directory could not be found.', 'NotFoundError');

  const fileNode = (text) => ({ text, mtime: bump(), fail: false });

  // A file's content is a string or a Blob (an image a check drew); any other value is a subtree.
  const isContent = (value) => typeof value === 'string' || value instanceof Blob;

  function dirNode(tree) {
    const kids = new Map();
    Object.keys(tree).forEach((name) => kids.set(name, isContent(tree[name]) ? fileNode(tree[name]) : dirNode(tree[name])));

    return { kids, fail: false };
  }

  // A handle over node. A node made to fail throws NotFoundError from getFile() (a file) or entries() (a folder).
  function handleOf(name, node) {
    if (!node.kids) {
      return {
        kind: 'file',
        name,
        async getFile() {
          if (node.fail) throw gone();

          return new File([node.text], name, { lastModified: node.mtime });
        },
      };
    }

    return {
      kind: 'directory',
      name,
      async *entries() {
        if (node.fail) throw gone();
        for (const [kid, child] of [...node.kids]) yield [kid, handleOf(kid, child)];
      },
      async requestPermission() {
        return 'granted';
      },
    };
  }

  window.fakeDir = (tree, name) => {
    const root = dirNode(tree);
    const handle = handleOf(name || 'root', root);

    // The folder holding path (made on the way when make is set) and the last segment.
    function parent(path, make) {
      const parts = path.split('/');
      const last = parts.pop();
      let dir = root;
      for (const part of parts) {
        if (!dir.kids.has(part) && make) dir.kids.set(part, dirNode({}));
        dir = dir.kids.get(part);
      }

      return { dir, last };
    }

    const node = (path) => {
      const { dir, last } = parent(path, false);

      return dir.kids.get(last);
    };

    return Object.assign(handle, {
      edit(path, text) {
        Object.assign(node(path), { text, mtime: bump() });
      },
      add(path, text) {
        const { dir, last } = parent(path, true);
        dir.kids.set(last, fileNode(text));
      },
      remove(path) {
        const { dir, last } = parent(path, false);
        dir.kids.delete(last);
      },
      failOn(path) {
        node(path).fail = true;
      },
    });
  };

  window.treeOf = (flat) => {
    const tree = {};
    Object.keys(flat).forEach((path) => {
      const parts = path.split('/');
      const last = parts.pop();
      const dir = parts.reduce((at, part) => (at[part] = at[part] || {}), tree);
      dir[last] = flat[path];
    });

    return tree;
  };

  // setTimeout and clearTimeout over a manual clock: advance(ms) runs every timer that falls due, in order, including
  // the ones those callbacks set.
  window.fakeTimers = () => {
    let now = 0;
    let nextId = 1;
    const timers = new Map();

    return {
      setTimeout(fn, ms) {
        timers.set(nextId, { at: now + ms, fn });

        return nextId++;
      },
      clearTimeout(id) {
        timers.delete(id);
      },
      advance(ms) {
        const target = now + ms;
        for (;;) {
          const due = [...timers].filter(([, timer]) => timer.at <= target).sort((a, b) => a[1].at - b[1].at || a[0] - b[0])[0];
          if (!due) break;
          timers.delete(due[0]);
          now = due[1].at;
          due[1].fn();
        }
        now = target;
      },
      now: () => now,
    };
  };
})();
