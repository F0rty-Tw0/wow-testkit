// The Blizzard panel's pure parts (viewer/blizzard.js): TK.blizzard.describe writes the status line, layoutOptions lists
// the Edit Mode layouts (the two client presets first, so a value is the client's activeLayout), parseActions reads the
// actions line, wtfText the WTF import line and windowOptions lists the window picker's choices.
(function () {
  'use strict';

  TK_TESTS.push({
    name: 'blizzard.describe says off, why, and counts addons and errors when on',
    fn() {
      A.eq(TK.blizzard.describe({ enabled: false, available: false }), 'Blizzard UI: off (no client extract)');
      A.eq(TK.blizzard.describe({ enabled: false, available: true }), 'Blizzard UI: off');
      A.eq(TK.blizzard.describe({ enabled: true, loaded: ['a', 'b'], errors: 3 }), 'Blizzard UI: on, 2 addons, 3 errors');
      A.eq(TK.blizzard.describe({ enabled: true, loaded: ['a'], errors: 1 }), 'Blizzard UI: on, 1 addon, 1 error');
    },
  });

  TK_TESTS.push({
    name: 'blizzard.layoutOptions puts the presets first and selects the active layout',
    fn() {
      A.same(TK.blizzard.layoutOptions({ layouts: ['A', 'B'], active: 4 }), [
        { value: 1, label: 'Modern (preset)' },
        { value: 2, label: 'Classic (preset)' },
        { value: 3, label: 'A' },
        { value: 4, label: 'B', selected: true },
      ]);
      A.same(
        TK.blizzard.layoutOptions({ layouts: [], active: 1 }).map((o) => o.selected === true),
        [true, false],
      );
    },
  });

  TK_TESTS.push({
    name: 'blizzard.parseActions reads slot texture count groups and off',
    fn() {
      A.same(TK.blizzard.parseActions('1 136235 3'), { 1: { texture: 136235, count: 3 } });
      A.same(TK.blizzard.parseActions(' 2 off '), { 2: false });
      A.same(TK.blizzard.parseActions('1 136235, 180 7 0'), { 1: { texture: 136235 }, 180: { texture: 7, count: 0 } });
    },
  });

  TK_TESTS.push({
    name: 'blizzard.parseActions refuses bad slots, textures, counts and empty text',
    fn() {
      for (const text of ['1 x', '0 5', '181 5', '1.5 5', '1 5 -1', '1 5 3 4', '1', '', '1 5,']) {
        A.eq(TK.blizzard.parseActions(text), null, text);
      }
    },
  });

  TK_TESTS.push({
    name: 'blizzard.wtfText counts the import, empty without one',
    fn() {
      const wtf = { cvars: 297, bindings: 1, saved: 0, layouts: 2 };
      A.eq(TK.blizzard.wtfText(wtf), 'WTF import: 297 CVars, 1 binding, 0 saved variables, 2 layouts');
      A.eq(TK.blizzard.wtfText(undefined), '');
    },
  });

  TK_TESTS.push({
    name: 'blizzard.windowOptions puts none first and selects the open window',
    fn() {
      A.same(TK.blizzard.windowOptions({ windows: ['mail', 'merchant'], open: 'mail' }), [
        { value: 'none', label: 'none' },
        { value: 'mail', label: 'mail', selected: true },
        { value: 'merchant', label: 'merchant' },
      ]);
    },
  });

  TK_TESTS.push({
    name: 'blizzard.windowOptions says no Blizzard windows when there are none',
    fn() {
      A.same(TK.blizzard.windowOptions({ windows: [] }), [{ value: 'none', label: 'no Blizzard windows', disabled: true }]);
    },
  });
})();
