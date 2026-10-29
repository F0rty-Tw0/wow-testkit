// FontString text (viewer/viewer_text.js, viewer/viewer_font.js): Viewer.parseEscapes picks the |4 plural form, and a
// FontString shorter than one line still draws that line (rows V14, V15).
(function () {
  'use strict';

  const V = window.Viewer;

  function textOf(text) {
    return V.parseEscapes(text)
      .map((segment) => segment.text)
      .join('');
  }

  TK_TESTS.push({
    name: 'parseEscapes shows the |4 form its number picks',
    fn() {
      A.eq(textOf('1 |4Day:Days;'), '1 Day');
      A.eq(textOf('29 |4Day:Days;'), '29 Days');
      A.eq(textOf('|4Day:Days;'), 'Days', 'no number');
      A.eq(textOf('1 |4Day:Days'), '1 |4Day:Days', 'no ";" is not an escape');
      A.eq(textOf('1 day|n2 |4Day:Days;'), '1 day\n2 Days', 'the number on its own line');
    },
  });

  // /(\d+)\D*$/ backtracks over every start of a long digit run: minutes for this line. The harness clock is virtual
  // (unit.sh --virtual-time-budget), so the guard is unit.sh's 60 s dump timeout, not a time assertion.
  TK_TESTS.push({
    name: 'parseEscapes reads the last number of a long line in linear time, as ui/measure.lua does',
    fn() {
      const digits = '1'.repeat(200000);
      const text = textOf(`${digits} 1 |4Day:Days;`);
      A.eq(text.slice(-5), '1 Day');
      A.eq(textOf('x12y |4Day:Days;'), 'x12y Days');
      A.eq(textOf('a 01 b |4Day:Days;'), 'a 01 b Day');
      A.eq(textOf('no digits |4Day:Days;'), 'no digits Days');
    },
  });

  TK_TESTS.push({
    name: 'parseEscapes keeps the colour of a |4 inside |c, and the hex is no number',
    fn() {
      const segments = V.parseEscapes('|cff19ff1912 |4Day:Days; |r');
      A.eq(segments.length, 1);
      A.eq(segments[0].text, '12 Days ');
      A.same(segments[0].color, [0x19 / 255, 1, 0x19 / 255, 1]);
    },
  });

  TK_TESTS.push({
    name: 'fontString draws one line in a rect shorter than the line',
    fn() {
      const node = document.createElement('div');
      node.className = 'item fontstring';
      node.style.cssText = 'left: 0; top: 0; width: 200px; height: 1px;';
      document.body.append(node);
      const ctx = { families: new Map(), assets: {}, baseUrl: location.href };
      V.fontString(node, { text: '|cffffffffLinen Cloth|r', size: 14, justifyH: 'LEFT' }, ctx);
      const height = node.querySelector('.lines').getBoundingClientRect().height;
      node.remove();
      A.eq(height, 14, 'lines height');
    },
  });

  TK_TESTS.push({
    name: 'loadFonts builds one FontFace per font url across redraws, also for a url that fails',
    async fn() {
      const RealFontFace = window.FontFace;
      let built = 0;
      window.FontFace = function (...args) {
        built += 1;

        return new RealFontFace(...args);
      };
      V.forgetFonts();
      try {
        const assets = { 'Fonts/MISSING.TTF': { kind: 'font', url: 'fixtures/missing-font.ttf' } };
        await V.loadFonts(assets, location.href);
        const families = await V.loadFonts(assets, location.href);
        A.eq(built, 1, 'FontFace count');
        A.eq(families.size, 0, 'a font that failed stays out');
      } finally {
        window.FontFace = RealFontFace;
      }
    },
  });

  // Runs fn(log) with FontFace and document.fonts.add/delete faked, as the repo has no font file: every face loads.
  async function withFakeFonts(fn) {
    const RealFontFace = window.FontFace;
    const log = { built: [], added: [], deleted: [] };
    window.FontFace = function (family) {
      const face = { family, load: () => Promise.resolve() };
      log.built.push(face);

      return face;
    };
    document.fonts.add = (face) => log.added.push(face);
    document.fonts.delete = (face) => log.deleted.push(face);
    V.forgetFonts();
    try {
      await fn(log);
    } finally {
      // The fake faces leave document.fonts through the fake delete (an empty load drops the forgotten faces, a
      // microtask later) before the real one is back.
      V.forgetFonts();
      await V.loadFonts({}, location.href);
      await new Promise((resolve) => setTimeout(resolve, 0));
      window.FontFace = RealFontFace;
      delete document.fonts.add;
      delete document.fonts.delete;
    }
  }

  const TWO_FONTS = {
    'Fonts/A.TTF': { kind: 'font', url: 'fixtures/a.ttf' },
    'Fonts/B.TTF': { kind: 'font', url: 'fixtures/b.ttf' },
  };

  TK_TESTS.push({
    name: 'loadFonts gives each font url its own family and loads it once across redraws',
    async fn() {
      await withFakeFonts(async (log) => {
        const first = await V.loadFonts(TWO_FONTS, location.href);
        const second = await V.loadFonts(TWO_FONTS, location.href);
        A.eq(log.built.length, 2, 'FontFace count');
        A.eq(log.added.length, 2, 'faces added to document.fonts');
        A.eq(new Set(first.values()).size, 2, 'distinct families');
        A.same([...second.entries()], [...first.entries()], 'a redraw keeps the families');
      });
    },
  });

  TK_TESTS.push({
    name: 'after forgetFonts the next loadFonts loads each url under a new family, then drops the old faces',
    async fn() {
      await withFakeFonts(async (log) => {
        const before = await V.loadFonts(TWO_FONTS, location.href);
        V.forgetFonts();
        await new Promise((resolve) => setTimeout(resolve, 0));
        A.same(log.deleted, [], 'the drawn stage keeps its faces until the next load');
        const after = await V.loadFonts(TWO_FONTS, location.href);
        A.eq(log.built.length, 4, 'FontFace count');
        A.same(log.deleted, log.built.slice(0, 2), 'dropped faces');
        for (const ref of Object.keys(TWO_FONTS)) A.eq(after.get(ref) !== before.get(ref), true, ref + ' family');
      });
    },
  });
})();
