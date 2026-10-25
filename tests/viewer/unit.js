// Headless unit harness: tests push { name, fn } onto TK_TESTS; on load each runs in order (fn may return a Promise)
// and writes PASS/FAIL lines into #out, then data-done="1" marks the run finished for check_unit.py.
window.TK = window.TK || {};
window.TK_TESTS = [];

(function () {
  'use strict';

  // Deep equality through JSON with sorted keys.
  function canon(value) {
    return JSON.stringify(value, (key, v) => {
      if (v === null || typeof v !== 'object' || Array.isArray(v)) return v;
      const sorted = {};
      Object.keys(v)
        .sort()
        .forEach((k) => {
          sorted[k] = v[k];
        });

      return sorted;
    });
  }

  function fail(msg, text) {
    throw new Error(msg ? msg + ': ' + text : text);
  }

  window.A = {
    eq(actual, expected, msg) {
      if (actual !== expected) fail(msg, 'got ' + String(actual) + ', want ' + String(expected));
    },
    same(actual, expected, msg) {
      if (canon(actual) !== canon(expected)) fail(msg, 'got ' + canon(actual) + ', want ' + canon(expected));
    },
    throws(fn, pattern) {
      try {
        fn();
      } catch (err) {
        if (!new RegExp(pattern).test(String(err && err.message))) fail('', 'threw ' + err + ', want ' + pattern);

        return;
      }
      fail('', 'did not throw, want ' + pattern);
    },
  };

  async function runAll() {
    const out = document.getElementById('out');
    for (const test of window.TK_TESTS) {
      try {
        await test.fn();
        out.textContent += 'PASS ' + test.name + '\n';
      } catch (err) {
        const text = String(err && err.message ? err.message : err).replace(/\n/g, ' ');
        out.textContent += 'FAIL ' + test.name + ': ' + text + '\n';
      }
    }
    out.setAttribute('data-done', '1');
  }

  window.addEventListener('load', runAll);
})();
