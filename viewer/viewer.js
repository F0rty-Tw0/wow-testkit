// Static render-snapshot viewer. index.html?snapshot=<url>[&zoom=1|fit|<n>][&bare=1][&outline=1]. loadSnapshot(url)
// fetches a snapshot; render(snapshot, baseUrl) replaces the content of #stage with its items in snapshot order
// (already draw order) and resolves relative asset urls against baseUrl. <html data-ready="1"> is set once drawing is
// done or has failed. With live=1 the snapshot comes from the session instead and live.js sets data-ready.
(function (V) {
  'use strict';

  const ZOOM_STEP = 1.25;
  const ORIGIN = { x: 0, y: 0 };
  const TINT_FIELD = { texture: 'vertexColor', fontstring: 'color' };
  const BUILD = { frame: V.frame, texture: V.texture, fontstring: V.fontString };
  const params = new URLSearchParams(location.search);
  const view = { zoom: params.get('zoom') || '1', screen: null, outline: params.get('outline') === '1' };

  async function loadSnapshot(url) {
    const response = await fetch(url);
    if (!response.ok) throw new Error(`HTTP ${response.status} for ${url}`);

    return response.json();
  }

  function place(node, rect, origin) {
    node.style.left = rect.x - origin.x + 'px';
    node.style.top = rect.y - origin.y + 'px';
    node.style.width = rect.width + 'px';
    node.style.height = rect.height + 'px';
  }

  function opacityOf(item) {
    const tint = item[TINT_FIELD[item.kind]];
    const tintAlpha = Array.isArray(tint) ? Number(tint[3] ?? 1) : 1;

    return Number(item.alpha ?? 1) * tintAlpha;
  }

  function nameTag(item) {
    const tag = document.createElement('span');
    tag.className = 'name';
    tag.textContent = item.name || item.id;

    return tag;
  }

  function itemNode(item, ctx) {
    const node = document.createElement('div');
    const opacity = opacityOf(item);
    const build = BUILD[item.kind];
    node.className = 'item ' + item.kind;
    node.dataset.id = item.id;
    node.dataset.kind = item.kind;
    if (item.name) node.dataset.name = item.name;
    place(node, item.rect, item.clip || ORIGIN);
    if (opacity < 1) node.style.opacity = String(opacity);
    if (build) build(node, item, ctx);
    if (item.kind === 'frame' && view.outline) node.append(nameTag(item));

    return node;
  }

  // A clipped item sits in its own .clip box at the clip rect, positioned relative to it.
  function placed(item, ctx) {
    const node = itemNode(item, ctx);
    if (!item.clip) return node;
    const clip = document.createElement('div');
    clip.className = 'clip';
    place(clip, item.clip, ORIGIN);
    clip.append(node);

    return clip;
  }

  function showMessages(id, messages) {
    const box = document.getElementById(id);
    const lines = messages.map((message) => {
      const line = document.createElement('div');
      line.textContent = String(message);

      return line;
    });
    box.replaceChildren(...lines);
    box.hidden = lines.length === 0;
  }

  function fitScale() {
    const viewport = document.getElementById('viewport');
    const top = viewport.getBoundingClientRect().top;
    const width = document.documentElement.clientWidth - 2 * viewport.offsetLeft;
    const height = window.innerHeight - top - viewport.offsetLeft;

    return Math.max(0.05, Math.min(width / view.screen.width, height / view.screen.height));
  }

  function applyZoom() {
    if (!view.screen) return;
    const scale = view.zoom === 'fit' ? fitScale() : Number(view.zoom) || 1;
    const viewport = document.getElementById('viewport');
    document.getElementById('stage').style.transform = `scale(${scale})`;
    viewport.style.width = view.screen.width * scale + 'px';
    viewport.style.height = view.screen.height * scale + 'px';
    document.getElementById('zoom-label').textContent = Math.round(scale * 100) + '%';
  }

  async function render(snapshot, baseUrl) {
    const stage = document.getElementById('stage');
    const screen = snapshot.screen || { width: 0, height: 0 };
    const assets = snapshot.assets || {};
    const ctx = { assets, baseUrl, families: await V.loadFonts(assets, baseUrl) };
    const problems = (snapshot.errors || []).map((err) => err.message);
    stage.replaceChildren();
    stage.style.width = screen.width + 'px';
    stage.style.height = screen.height + 'px';
    for (const item of snapshot.items || []) {
      try {
        if (item.rect) stage.append(placed(item, ctx));
      } catch (err) {
        problems.push(`viewer: item ${item.id} not drawn: ${err.message}`);
      }
    }
    showMessages('errors', problems);
    view.screen = screen;
    applyZoom();
  }

  function zoomBy(factor) {
    const current = view.zoom === 'fit' ? fitScale() : Number(view.zoom) || 1;
    view.zoom = String(current * factor);
    applyZoom();
  }

  function wireToolbar() {
    document.getElementById('zoom-out').addEventListener('click', () => zoomBy(1 / ZOOM_STEP));
    document.getElementById('zoom-in').addEventListener('click', () => zoomBy(ZOOM_STEP));
    document.getElementById('zoom-fit').addEventListener('click', () => {
      view.zoom = 'fit';
      applyZoom();
    });
    window.addEventListener('resize', () => view.zoom === 'fit' && applyZoom());
  }

  async function main() {
    const source = params.get('snapshot');
    document.body.classList.toggle('bare', params.get('bare') === '1');
    document.body.classList.toggle('outlined', view.outline);
    wireToolbar();
    if (params.get('live') === '1') return;
    try {
      if (!source) throw new Error('no snapshot given: open index.html?snapshot=<url>');
      const url = new URL(source, location.href).href;
      await render(await loadSnapshot(url), url);
    } catch (err) {
      showMessages('status', ['Could not show the snapshot: ' + err.message]);
    }
    document.documentElement.dataset.ready = '1';
  }

  V.showMessages = showMessages;
  Object.assign(window, { loadSnapshot, render, parseEscapes: V.parseEscapes, refPath: V.refPath, refId: V.refId, refAtlas: V.refAtlas });
  main();
})((window.Viewer = window.Viewer || {}));
