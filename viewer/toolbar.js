// Toolbar (live mode): a flavour picker (#flavor: Auto, then the session's flavors), a screen size picker (#size: the
// presets, and Custom with two number inputs), a Reload button and the status line (#session-status: addon · flavor ·
// WxH · loads · errors). Picking a flavor or a preset reloads the session with it (TK.api('reload')); Reload sends both
// pickers, Custom's inputs included. A skipped addon's reason shows in #skipped. Classic script; parseSize and
// statusText are pure for tests/viewer/unit_toolbar.js.
window.TK = window.TK || {};

(function (TK) {
  'use strict';

  const toolbar = (TK.toolbar = {});
  // The sizes the session accepts (session_options.lua).
  const LIMITS = { width: [320, 7680], height: [240, 4320] };
  const CUSTOM = 'custom';

  toolbar.PRESETS = [
    { name: '1080p', width: 1920, height: 1080 },
    { name: '1440p', width: 2560, height: 1440 },
    { name: '4k', width: 3840, height: 2160 },
  ];

  function inLimits(value, side) {
    const [low, high] = LIMITS[side];

    return Number.isInteger(value) && value >= low && value <= high;
  }

  // { width, height } of a typed size such as "2560x1440", or null unless both sides are whole and within the limits.
  toolbar.parseSize = (text) => {
    const match = /^\s*(\d+)\s*[xX]\s*(\d+)\s*$/.exec(String(text));
    if (!match) return null;
    const size = { width: Number(match[1]), height: Number(match[2]) };
    const fits = inLimits(size.width, 'width') && inLimits(size.height, 'height');

    return fits ? size : null;
  };

  function counted(count, noun) {
    const plural = count === 1 ? '' : 's';

    return `${count} ${noun}${plural}`;
  }

  // "addon · flavor · WxH · N loads · N errors" from the session info block.
  toolbar.statusText = (info) => {
    const size = `${info.screen.width}x${info.screen.height}`;
    const parts = [info.addon, info.flavor, size, counted(info.loads, 'load'), counted(info.errors || 0, 'error')];

    return parts.join(' · ');
  };

  // DOM ------------------------------------------------------------------------------------------------------------

  const dom = {};
  const ui = { flavorsFilled: false };

  function el(tag, props) {
    return Object.assign(document.createElement(tag), props);
  }

  function labelled(node, label) {
    node.setAttribute('aria-label', label);

    return node;
  }

  function option(value, text) {
    return el('option', { value, textContent: text });
  }

  function presetOf(screen) {
    const preset = toolbar.PRESETS.find((p) => p.width === screen.width && p.height === screen.height);

    return preset ? preset.name : CUSTOM;
  }

  function showCustom() {
    const custom = dom.size.value === CUSTOM;
    dom.width.hidden = !custom;
    dom.height.hidden = !custom;
  }

  function show(info) {
    dom.status.textContent = toolbar.statusText(info);
    if (dom.flavor.value !== 'auto') dom.flavor.value = info.flavor;
    dom.size.value = presetOf(info.screen);
    dom.width.value = info.screen.width;
    dom.height.value = info.screen.height;
    showCustom();
    dom.skipped.textContent = info.skipped ? `${info.addon} is skipped on ${info.flavor}: ${info.skipped}` : '';
    dom.skipped.hidden = !info.skipped;
  }

  // The flavor list fills from the first info that answers, so a session that was down at start fills it later.
  function fillFlavors(info) {
    if (ui.flavorsFilled || !info.flavors) return;
    ui.flavorsFilled = true;
    const options = info.flavors.map((name) => option(name, name));
    dom.flavor.append(...options);
    dom.flavor.value = info.flavor;
  }

  async function update() {
    try {
      const info = await TK.api('info', {});
      fillFlavors(info);
      if (info.ok) show(info);
    } catch (err) {
      dom.status.textContent = 'Session: ' + err.message;
    }
  }

  // The size the pickers name: a preset name, a { width, height } from Custom's inputs, or null when those are bad.
  function chosenSize() {
    if (dom.size.value !== CUSTOM) return dom.size.value;

    return toolbar.parseSize(`${dom.width.value}x${dom.height.value}`);
  }

  async function reload(req) {
    try {
      const reply = await TK.api('reload', req);
      if (!reply.ok) dom.status.textContent = 'Reload failed: ' + reply.error;
      else await update();
    } catch (err) {
      dom.status.textContent = 'Reload failed: ' + err.message;
    }
  }

  function reloadBoth() {
    const size = chosenSize();
    if (!size) {
      dom.status.textContent = 'Size must be WxH within 320x240 to 7680x4320';

      return;
    }
    reload({ flavor: dom.flavor.value, size });
  }

  function onSizeChange() {
    showCustom();
    if (dom.size.value !== CUSTOM) reload({ size: dom.size.value });
  }

  function mount() {
    const bar = document.getElementById('toolbar');
    dom.flavor = labelled(el('select', { id: 'flavor' }), 'Flavor');
    dom.flavor.append(option('auto', 'Auto'));
    dom.size = labelled(el('select', { id: 'size' }), 'Screen size');
    const presets = toolbar.PRESETS.map((p) => option(p.name, `${p.name} (${p.width}x${p.height})`));
    dom.size.append(...presets, option(CUSTOM, 'Custom'));
    const side = (id, label, [min, max]) => {
      const input = el('input', { id, type: 'number', min, max, step: 1, hidden: true });

      return labelled(input, label);
    };
    dom.width = side('size-width', 'Screen width', LIMITS.width);
    dom.height = side('size-height', 'Screen height', LIMITS.height);
    const button = el('button', { id: 'reload', type: 'button', textContent: 'Reload' });
    dom.status = el('span', { id: 'session-status' });
    dom.status.setAttribute('role', 'status');
    dom.skipped = document.getElementById('skipped');
    bar.append(dom.flavor, dom.size, dom.width, dom.height, button, dom.status);
    dom.flavor.addEventListener('change', () => reload({ flavor: dom.flavor.value }));
    dom.size.addEventListener('change', onSizeChange);
    button.addEventListener('click', reloadBoth);
  }

  function start() {
    TK.on('hello', update);
    TK.on('snapshot', update);
    TK.on('reload', update);
    update();
  }

  const isLive = new URLSearchParams(location.search).get('live') === '1';
  if (isLive) {
    mount();
    document.addEventListener('DOMContentLoaded', start);
  }
})(window.TK);
