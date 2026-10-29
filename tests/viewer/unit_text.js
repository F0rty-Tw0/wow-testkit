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
})();
