// Frame inspector (live mode): a panel in #panels with a name filter, the session's widget tree, a Pick toggle (while
// on, a stage click selects the topmost drawn item instead of clicking it) and the selected widget's properties, with
// #selection outlining it on the stage. ?select=<name or id> preselects. Tree and selection refresh on each snapshot
// event, keeping the filter and the open nodes. The panel mounts as the script runs, so the first fit zoom already
// leaves room for it; its session calls start on DOMContentLoaded, after live.js (loaded first) installed the
// transport. The roots start open. Classic script; buildTree, filterTree, pick, outlineBox and propRows are pure for
// tests/viewer/unit_inspector.js.
window.TK = window.TK || {};

(function (TK) {
  'use strict';

  const inspector = (TK.inspector = {});

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

  // The id of the topmost drawn item (snapshot items are back to front) whose rect and clip hold the screen point.
  inspector.pick = (snapshot, x, y) => {
    const items = snapshot.items || [];
    for (let i = items.length - 1; i >= 0; i--) {
      const item = items[i];
      const unclipped = !item.clip || contains(item.clip, x, y);
      if (item.rect && contains(item.rect, x, y) && unclipped) return item.id;
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

  // DOM ------------------------------------------------------------------------------------------------------------

  const ui = { nodes: [], names: {}, open: new Set(), filter: '', selected: null, picking: false, screen: null, seq: -1 };
  const fetching = { busy: false, again: false };
  const dom = {};

  function el(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;

    return node;
  }

  function rowNode(entry, allOpen) {
    const { node, children } = entry;
    const open = allOpen || ui.open.has(node.id);
    const li = el('li', node.visible ? '' : 'dim');
    li.dataset.id = node.id;
    li.classList.toggle('selected', node.id === ui.selected);
    const twisty = el('button', 'twisty', children.length ? (open ? '▾' : '▸') : '');
    twisty.type = 'button';
    twisty.disabled = children.length === 0;
    twisty.setAttribute('aria-label', open ? 'Collapse' : 'Expand');
    const label = el('button', 'label');
    label.type = 'button';
    label.append(el('span', 'node-name', node.name || '(anonymous)'), el('span', 'node-meta', `${node.type} ${node.id}`));
    const row = el('div', 'row');
    row.append(twisty, label);
    li.append(row);
    if (!children.length) return li;
    const list = el('ul');
    list.hidden = !open;
    list.append(...children.map((child) => rowNode(child, allOpen)));
    li.append(list);

    return li;
  }

  function renderTree() {
    const roots = inspector.filterTree(inspector.buildTree(ui.nodes), ui.filter);
    dom.tree.replaceChildren(...roots.map((entry) => rowNode(entry, ui.filter !== '')));
  }

  function renderProps(props, message) {
    const rows = props ? inspector.propRows(props, ui.names) : [['', message]];
    const cells = rows.flatMap(([key, text]) => [el('dt', '', key), el('dd', '', text)]);
    dom.props.replaceChildren(...cells);
  }

  function placeSelection(props) {
    const rect = props && props.screenRect;
    const shown = Boolean(rect && ui.screen);
    dom.selection.hidden = !shown;
    if (!shown) return;
    Object.assign(dom.selection.style, inspector.outlineBox(rect, ui.screen));
    dom.selection.classList.toggle('undrawn', !props.render);
  }

  async function showSelected() {
    const reply = ui.selected ? await TK.api('frame', { id: ui.selected }) : null;
    const props = reply && reply.ok ? reply.props : null;
    renderProps(props, ui.selected ? `${ui.selected} is gone` : 'Nothing selected');
    placeSelection(props);
  }

  function openAncestors(id) {
    const byId = new Map(ui.nodes.map((node) => [node.id, node]));
    let node = byId.get(id);
    while (node && node.parent) {
      ui.open.add(node.parent);
      node = byId.get(node.parent);
    }
  }

  async function select(id) {
    ui.selected = id;
    openAncestors(id);
    renderTree();
    const row = dom.tree.querySelector('li.selected > .row');
    if (row) row.scrollIntoView({ block: 'nearest' });
    await showSelected();
  }

  async function refreshOnce() {
    const [tree, info] = await Promise.all([TK.api('tree', {}), TK.api('info', {})]);
    const first = ui.nodes.length === 0;
    ui.nodes = tree.ok ? tree.nodes : [];
    if (first) inspector.buildTree(ui.nodes).forEach((entry) => ui.open.add(entry.node.id));
    ui.names = Object.fromEntries(ui.nodes.filter((node) => node.name).map((node) => [node.id, node.name]));
    if (info.ok) Object.assign(ui, { screen: info.screen, seq: info.seq });
    renderTree();
    await showSelected();
  }

  // Reloads the tree and the selection; a call while one runs makes that one run again afterwards.
  async function refresh() {
    if (fetching.busy) {
      fetching.again = true;

      return;
    }
    fetching.busy = true;
    try {
      do {
        fetching.again = false;
        await refreshOnce();
      } while (fetching.again);
    } catch (err) {
      renderProps(null, 'Inspector: ' + err.message);
    } finally {
      fetching.busy = false;
    }
  }

  function onTreeClick(ev) {
    const button = ev.target.closest('button');
    const li = button && button.closest('li[data-id]');
    if (!li) return;
    const id = li.dataset.id;
    if (button.classList.contains('label')) {
      select(id);

      return;
    }
    if (ui.open.has(id)) ui.open.delete(id);
    else ui.open.add(id);
    renderTree();
  }

  function setPicking(on) {
    ui.picking = on;
    dom.pick.setAttribute('aria-pressed', String(on));
    document.getElementById('viewport').classList.toggle('picking', on);
  }

  // While Pick is on, a stage click (either button) selects the item under it; the capture phase on #viewport runs
  // before pointer.js's stage listeners, so the session never sees the click.
  function onStageClick(ev) {
    const snapshot = TK.state && TK.state.snapshot;
    if (!ui.picking || !snapshot) return;
    ev.stopPropagation();
    ev.preventDefault();
    const stage = document.getElementById('stage');
    const point = TK.pointer.toScreen(ev, stage.getBoundingClientRect(), snapshot.screen);
    const id = inspector.pick(snapshot, point.x, point.y);
    if (id) select(id);
  }

  function mount() {
    const panel = el('section');
    panel.id = 'inspector';
    const header = el('header');
    dom.pick = el('button', 'pick', 'Pick');
    dom.pick.type = 'button';
    dom.pick.setAttribute('aria-pressed', 'false');
    header.append(el('h2', '', 'Inspector'), dom.pick);
    const filter = el('input', 'filter');
    Object.assign(filter, { type: 'search', placeholder: 'Filter by name' });
    filter.setAttribute('aria-label', 'Filter by name');
    dom.tree = el('ul', 'tree');
    dom.props = el('dl', 'props');
    dom.selection = document.getElementById('selection');
    panel.append(header, filter, dom.tree, dom.props);
    const panels = document.getElementById('panels');
    panels.append(panel);
    panels.hidden = false;
    filter.addEventListener('input', () => {
      ui.filter = filter.value.trim();
      renderTree();
    });
    dom.tree.addEventListener('click', onTreeClick);
    dom.pick.addEventListener('click', () => setPicking(!ui.picking));
    const viewport = document.getElementById('viewport');
    viewport.addEventListener('click', onStageClick, true);
    viewport.addEventListener('contextmenu', onStageClick, true);
  }

  async function start() {
    TK.on('snapshot', (data) => {
      const newer = !data || data.seq > ui.seq;
      if (newer) refresh();
    });
    await refresh();
    const wanted = new URLSearchParams(location.search).get('select');
    const node = wanted && ui.nodes.find((n) => n.id === wanted || n.name === wanted);
    if (node) await select(node.id);
  }

  const isLive = new URLSearchParams(location.search).get('live') === '1';
  if (isLive) {
    mount();
    document.addEventListener('DOMContentLoaded', start);
  }
})(window.TK);
