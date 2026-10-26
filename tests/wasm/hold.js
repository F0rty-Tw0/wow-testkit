// Keeps the load event of a test page open, so a headless dump waits for the tests. A dump fires at load, and
// --virtual-time-budget and --timeout both dump while a worker still runs. An iframe document that stays open holds
// load; it is closed when #out gets data-done (or after 50 s, so the dump still happens). Load listeners cannot run
// while load is held, so the ones the page registers (tests/viewer/unit.js) run at DOMContentLoaded instead.
// TKPage.load(name) loads the script a ?name=<file:/// url> query points at (a generated fixture, fixture_js.py).
(function () {
  'use strict';

  const frame = document.createElement('iframe');
  frame.style.display = 'none';
  document.body.appendChild(frame);
  const hold = frame.contentDocument;
  hold.open();
  hold.write('<p>holding');
  const release = () => hold.close();
  setTimeout(release, 50000);

  window.TKPage = {
    load(name) {
      const url = new URLSearchParams(location.search).get(name);

      return new Promise((resolve, reject) => {
        const script = document.createElement('script');
        script.src = url;
        script.onload = resolve;
        script.onerror = () => reject(new Error('cannot load ?' + name + '=' + url));
        document.head.appendChild(script);
      });
    },
  };

  const loads = [];
  const add = window.addEventListener.bind(window);
  window.addEventListener = (type, fn, opts) => (type === 'load' ? loads.push(fn) : add(type, fn, opts));

  add('DOMContentLoaded', () => {
    const out = document.getElementById('out');
    new MutationObserver(() => out.getAttribute('data-done') && release()).observe(out, { attributes: true });
    loads.forEach((fn) => fn());
  });
})();
