// The developer panel's pure part: TK.dev.rows (viewer/dev.js) turns the session's dev report into table rows.
(function () {
  'use strict';

  TK_TESTS.push({
    name: 'dev.rows formats load time and memory and counts each list',
    fn() {
      const addon = {
        name: 'A',
        loadMs: 12.345,
        memoryKb: 1234.6,
        widgets: [
          { type: 'Frame', count: 2 },
          { type: 'Texture', count: 1 },
        ],
        unscripted: [{ name: 'x', count: 3 }],
        missing: [],
      };
      A.same(TK.dev.rows({ addons: [addon] }), [{ name: 'A', load: '12.3 ms', memory: '~1235 KB', widgets: 3, unscripted: 1, missing: 0 }]);
    },
  });

  TK_TESTS.push({
    name: 'dev.rows of no addons is empty',
    fn() {
      A.same(TK.dev.rows({ addons: [] }), []);
    },
  });
})();
