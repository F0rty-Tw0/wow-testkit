// The toolbar's pure parts (viewer/toolbar.js): TK.toolbar.parseSize reads a typed WxH screen size, TK.toolbar.PRESETS
// names the screen presets, TK.toolbar.statusText writes the session status line.
(function () {
  'use strict';

  TK_TESTS.push({
    name: 'toolbar.parseSize reads WxH within the session limits',
    fn() {
      A.same(TK.toolbar.parseSize('2560x1440'), { width: 2560, height: 1440 });
      A.same(TK.toolbar.parseSize(' 320X240 '), { width: 320, height: 240 });
      A.same(TK.toolbar.parseSize('7680x4320'), { width: 7680, height: 4320 });
    },
  });

  TK_TESTS.push({
    name: 'toolbar.parseSize rejects partial, zero, out-of-range and non-numeric sizes',
    fn() {
      for (const text of ['12x', '0x0', '9000x100', 'abc', '319x240', '1920x1080.5', '']) {
        A.eq(TK.toolbar.parseSize(text), null, text);
      }
    },
  });

  TK_TESTS.push({
    name: 'toolbar.PRESETS names 1080p, 1440p and 4k in that order',
    fn() {
      A.same(
        TK.toolbar.PRESETS.map((preset) => preset.name),
        ['1080p', '1440p', '4k'],
      );
      A.same(TK.toolbar.PRESETS[2], { name: '4k', width: 3840, height: 2160 });
    },
  });

  TK_TESTS.push({
    name: 'toolbar.statusText lists addon, flavor, size, loads and errors',
    fn() {
      const info = { addon: 'SessionDemo', flavor: 'vanilla', screen: { width: 3840, height: 2160 }, loads: 3, errors: 1 };
      A.eq(TK.toolbar.statusText(info), 'SessionDemo · vanilla · 3840x2160 · 3 loads · 1 error');
      A.eq(TK.toolbar.statusText({ ...info, loads: 1, errors: 0 }), 'SessionDemo · vanilla · 3840x2160 · 1 load · 0 errors');
    },
  });
})();
