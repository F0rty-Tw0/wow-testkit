// The frame inspector's pure parts (viewer/inspector.js draws them): buildTree and filterTree shape the session's
// widget tree, pick finds the topmost drawn item under a screen point, outlineBox places the selection box and
// propRows formats a widget's properties. Classic script, no DOM access; tests/viewer/unit_inspector.js covers it.
window.TK = window.TK || {};

(function (TK) {
  'use strict';

  const inspector = (TK.inspector = TK.inspector || {});

  // Nodes (each { id, parent? }) as a forest of { node, children }, in node order; a node whose parent is unknown is a root.
  inspector.buildTree = (nodes) => {
    const entries = new Map(nodes.map((node) => [node.id, { node, children: [] }]));
    const roots = [];
    for (const node of nodes) {
      const parent = node.parent && entries.get(node.parent);
      const siblings = parent ? parent.children : roots;
      siblings.push(entries.get(node.id));
    }

    return roots;
  };

  // The entries whose node name contains text (any case), with their ancestors; roots itself for an empty text.
  inspector.filterTree = (roots, text) => {
    const needle = String(text || '').toLowerCase();
    if (!needle) return roots;
    const keep = (entry) => {
      const children = entry.children.map(keep).filter(Boolean);
      const name = String(entry.node.name || '').toLowerCase();
      const kept = name.includes(needle) || children.length > 0;

      return kept ? { node: entry.node, children } : null;
    };

    return roots.map(keep).filter(Boolean);
  };

  function contains(rect, x, y) {
    const across = x >= rect.x && x < rect.x + rect.width;
    const down = y >= rect.y && y < rect.y + rect.height;

    return across && down;
  }

  // The id of the topmost drawn item (snapshot items are back to front) whose rect and clip hold the screen point; a
  // backdrop piece answers with its frame.
  inspector.pick = (snapshot, x, y) => {
    const items = snapshot.items || [];
    for (let i = items.length - 1; i >= 0; i--) {
      const item = items[i];
      const unclipped = !item.clip || contains(item.clip, x, y);
      if (item.rect && contains(item.rect, x, y) && unclipped) return item.kind === 'backdrop' ? item.parent : item.id;
    }

    return null;
  };

  const percent = (part, whole) => (100 * part) / whole + '%';

  // A screen rect as CSS percentages of the screen, so the box follows #viewport at any zoom.
  inspector.outlineBox = (rect, screen) => {
    const box = {
      left: percent(rect.x, screen.width),
      top: percent(rect.y, screen.height),
      width: percent(rect.width, screen.width),
      height: percent(rect.height, screen.height),
    };

    return box;
  };

  const num = (n) => (typeof n === 'number' ? String(Math.round(n * 100) / 100) : '?');
  const onOff = (flag) => (flag ? 'on' : 'off');
  const listText = (items) => (items && items.length ? items.join(', ') : 'none');

  function rectText(x, y, width, height) {
    return `${num(x)}, ${num(y)} ${num(width)} x ${num(height)}`;
  }

  function sizeText(size) {
    const set = size && (size.width !== undefined || size.height !== undefined);

    return set ? `${num(size.width)} x ${num(size.height)}` : 'not set';
  }

  // [key, text] rows for the properties of View.frame (session_view.lua); names maps ids to widget names.
  inspector.propRows = (props, names) => {
    const label = (id) => (names[id] ? `${names[id]} (${id})` : id);
    const pointText = (p) => `${p.point} to ${p.relativeTo ? label(p.relativeTo) : 'screen'} ${p.relativePoint} ${num(p.x)}, ${num(p.y)}`;
    const { rect, screenRect, mouse } = props;
    const rows = [
      ['id', props.id],
      ['name', props.name || '(anonymous)'],
      ['type', props.type],
      ['parent', props.parent ? label(props.parent) : 'none'],
      ['children', listText((props.children || []).map(label))],
    ];
    if (props.strata) rows.push(['strata', `${props.strata} level ${num(props.level)}`]);
    rows.push(
      ['shown', `${props.shown ? 'shown' : 'hidden'}, ${props.visible ? 'visible' : 'not visible'}`],
      ['alpha', `${num(props.alpha)} (effective ${num(props.effectiveAlpha)})`],
      ['scale', num(props.scale)],
      ['size', sizeText(props.size)],
      ['points', (props.points || []).map(pointText).join('; ') || 'none'],
      ['rect', rect ? rectText(rect.left, rect.bottom, rect.width, rect.height) : 'none'],
      ['screenRect', screenRect ? rectText(screenRect.x, screenRect.y, screenRect.width, screenRect.height) : 'none'],
      ['mouse', `click ${onOff(mouse && mouse.click)}, motion ${onOff(mouse && mouse.motion)}`],
      ['scripts', listText(props.scripts)],
      ['events', listText(props.events)],
      ['render', props.render ? `drawn (${props.render.kind})` : 'not drawn'],
    );

    return rows;
  };
})(window.TK);
