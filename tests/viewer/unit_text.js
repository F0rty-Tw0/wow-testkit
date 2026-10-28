// FontString text (viewer/viewer_text.js): Viewer.parseEscapes picks the |4 plural form (row V14).
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

  TK_TESTS.push({
    name: 'parseEscapes keeps the colour of a |4 inside |c, and the hex is no number',
    fn() {
      const segments = V.parseEscapes('|cff19ff1912 |4Day:Days; |r');
      A.eq(segments.length, 1);
      A.eq(segments[0].text, '12 Days ');
      A.same(segments[0].color, [0x19 / 255, 1, 0x19 / 255, 1]);
    },
  });
})();
