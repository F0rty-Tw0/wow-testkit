// TK.inspector (viewer/inspector_model.js): the widget tree built from the session's flat node list, the name filter,
// the topmost drawn item under a screen point, the selection outline box and the property rows.
(function () {
  'use strict';

  const NODES = [
    { id: 'f1', name: 'f1name' },
    { id: 'f2', name: 'f2name', parent: 'f1' },
    { id: 's3', name: 's3name', parent: 'f2' },
    { id: 'f4', name: 'f4name', parent: 'f1' },
  ];

  // The tree as nested [id, [children]] pairs.
  function shape(roots) {
    return roots.map((entry) => [entry.node.id, shape(entry.children)]);
  }

  TK_TESTS.push({
    name: 'inspector.buildTree nests nodes under their parents in order',
    fn() {
      A.same(shape(TK.inspector.buildTree(NODES)), [['f1', [['f2', [['s3', []]]], ['f4', []]]]]);
    },
  });

  TK_TESTS.push({
    name: 'inspector.filterTree keeps matches with their ancestors',
    fn() {
      const roots = TK.inspector.buildTree(NODES);
      A.same(shape(TK.inspector.filterTree(roots, 'S3NAME')), [['f1', [['f2', [['s3', []]]]]]]);
      A.same(TK.inspector.filterTree(roots, 'nothing'), []);
      A.eq(TK.inspector.filterTree(roots, ''), roots, 'empty filter');
    },
  });

  TK_TESTS.push({
    name: 'inspector.pick finds the topmost drawn item under a point',
    fn() {
      const a = { id: 'A', rect: { x: 0, y: 0, width: 100, height: 100 } };
      const b = { id: 'B', rect: { x: 50, y: 50, width: 100, height: 100 } };
      A.eq(TK.inspector.pick({ items: [a, b] }, 60, 60), 'B');
      A.eq(TK.inspector.pick({ items: [a, b] }, 10, 10), 'A');
      A.eq(TK.inspector.pick({ items: [a, b] }, 500, 500), null);
      const clipped = Object.assign({}, b, { clip: { x: 0, y: 0, width: 40, height: 40 } });
      A.eq(TK.inspector.pick({ items: [a, clipped] }, 60, 60), 'A', 'clipped away');
    },
  });

  TK_TESTS.push({
    name: 'inspector.pick answers a backdrop piece with its frame',
    fn() {
      const frame = { id: 'f1', rect: { x: 0, y: 0, width: 100, height: 100 } };
      const piece = { id: 'b1.center', kind: 'backdrop', parent: 'f1', rect: frame.rect };
      A.eq(TK.inspector.pick({ items: [frame, piece] }, 10, 10), 'f1');
    },
  });

  TK_TESTS.push({
    name: 'inspector.outlineBox places a screen rect as percentages of the screen',
    fn() {
      const box = TK.inspector.outlineBox({ x: 960, y: 270, width: 192, height: 108 }, { width: 1920, height: 1080 });
      A.same(box, { left: '50%', top: '25%', width: '10%', height: '10%' });
    },
  });

  TK_TESTS.push({
    name: 'inspector.propRows lays out the properties of a frame',
    fn() {
      const props = {
        id: 'f12',
        name: 'Demo',
        type: 'Frame',
        parent: 'f3',
        children: ['f13', 's14'],
        strata: 'MEDIUM',
        level: 1,
        shown: true,
        visible: false,
        alpha: 1,
        effectiveAlpha: 0.5,
        scale: 1,
        size: { width: 200, height: 60 },
        points: [{ point: 'CENTER', relativeTo: 'f3', relativePoint: 'CENTER', x: 0, y: 0.125 }],
        screenRect: { x: 860, y: 510, width: 200, height: 60 },
        mouse: { click: false, motion: true },
        scripts: ['OnEvent'],
        events: [],
      };
      const rows = TK.inspector.propRows(props, { f3: 'UIParent' });
      const text = Object.fromEntries(rows);
      A.eq(text.parent, 'UIParent (f3)');
      A.eq(text.children, 'f13, s14');
      A.eq(text.strata, 'MEDIUM level 1');
      A.eq(text.shown, 'shown, not visible');
      A.eq(text.alpha, '1 (effective 0.5)');
      A.eq(text.size, '200 x 60');
      A.eq(text.points, 'CENTER to UIParent (f3) CENTER 0, 0.13');
      A.eq(text.rect, 'none');
      A.eq(text.screenRect, '860, 510 200 x 60');
      A.eq(text.mouse, 'click off, motion on');
      A.eq(text.scripts, 'OnEvent');
      A.eq(text.events, 'none');
      A.eq(text.render, 'not drawn');
    },
  });
})();
