// Blizzard UI panel (live mode): a toggle that reloads the session with Blizzard's UI layer on or off (#blizzard-toggle,
// disabled with the hint "no client extract" when the session has none), the layer's status line, the WTF import
// counts, an Edit Mode layout select (#blizzard-layout, posting editMode.active), a window picker (#blizzard-window: the
// Blizzard windows the session can open, posting window, or "close" for none), an action slots line (#blizzard-actions:
// "slot texture [count]" or "slot off", comma-separated, posting actions) and the first load errors. It reads the
// session info (TK.api('info')) after every snapshot and reload event. Classic script; describe, layoutOptions,
// windowOptions, parseActions and wtfText are pure for tests/viewer/unit_blizzard.js.
window.TK = window.TK || {};

(function (TK) {
  'use strict';

  const blizzard = (TK.blizzard = {});

  // The client prepends its two preset layouts to the saved ones, so the client's activeLayout 3 is the first saved one
  // (game/editmode.lua PRESET_COUNT).
  const PRESETS = ['Modern (preset)', 'Classic (preset)'];
  const MAX_SLOT = 180;
  const WHOLE = /^\d+$/;
  const NO_EXTRACT = 'no client extract';
  const NO_WINDOWS = 'no Blizzard windows';
  const ACTIONS_HINT = 'Actions: "slot texture [count]" or "slot off", comma-separated; slots 1-180';

  function counted(count, noun) {
    const plural = count === 1 ? '' : 's';

    return `${count} ${noun}${plural}`;
  }

  // "Blizzard UI: on, N addons, M errors", or off (and why, when the session has no client extract).
  blizzard.describe = (info) => {
    if (!info.enabled) return info.available ? 'Blizzard UI: off' : `Blizzard UI: off (${NO_EXTRACT})`;

    return `Blizzard UI: on, ${counted(info.loaded.length, 'addon')}, ${counted(info.errors, 'error')}`;
  };

  // The layout select's options: the presets, then the saved layouts; value is the client's activeLayout index.
  blizzard.layoutOptions = (info) => {
    const labels = [...PRESETS, ...(info.layouts || [])];

    return labels.map((label, i) => {
      const option = { value: i + 1, label };
      if (i + 1 === info.active) option.selected = true;

      return option;
    });
  };

  // The window picker's options: none (closes the open window), then the session's windows; the open one is selected.
  blizzard.windowOptions = (info) => {
    const windows = info.windows || [];
    if (windows.length === 0) return [{ value: 'none', label: NO_WINDOWS, disabled: true }];
    const options = windows.map((name) => {
      const option = { value: name, label: name };
      if (name === info.open) option.selected = true;

      return option;
    });

    return [{ value: 'none', label: 'none' }, ...options];
  };

  function parseGroup(group) {
    const words = group.trim().split(/\s+/);
    const slot = Number(words[0]);
    const slotOk = WHOLE.test(words[0]) && slot >= 1 && slot <= MAX_SLOT;
    if (!slotOk || words.length < 2 || words.length > 3) return null;
    if (words[1] === 'off') return words.length === 2 ? [slot, false] : null;
    const fieldsOk = words.slice(1).every((word) => WHOLE.test(word));
    if (!fieldsOk || Number(words[1]) < 1) return null;
    const fields = { texture: Number(words[1]) };
    if (words.length === 3) fields.count = Number(words[2]);

    return [slot, fields];
  }

  // { [slot]: { texture, count? } | false } of an actions line, or null when any group is malformed or there is none.
  blizzard.parseActions = (text) => {
    const groups = String(text).split(',');
    const parsed = groups.map(parseGroup);
    if (!String(text).trim() || parsed.includes(null)) return null;

    return Object.fromEntries(parsed);
  };

  // "WTF import: N CVars, N bindings, N saved variables, N layouts", or '' without an import.
  blizzard.wtfText = (wtf) => {
    if (!wtf) return '';
    const parts = [
      counted(wtf.cvars, 'CVar'),
      counted(wtf.bindings, 'binding'),
      counted(wtf.saved, 'saved variable'),
      counted(wtf.layouts, 'layout'),
    ];

    return 'WTF import: ' + parts.join(', ');
  };

  // DOM ------------------------------------------------------------------------------------------------------------

  const dom = {};

  function el(tag, props) {
    return Object.assign(document.createElement(tag), props);
  }

  function labelled(node, label) {
    node.setAttribute('aria-label', label);

    return node;
  }

  function showLayouts(info) {
    const options = blizzard.layoutOptions(info).map((o) => el('option', { value: o.value, textContent: o.label, selected: o.selected === true }));
    dom.layout.replaceChildren(...options);
    dom.layout.disabled = !info.enabled;
  }

  function showWindows(info) {
    const choices = blizzard.windowOptions(info);
    const options = choices.map((o) => el('option', { value: o.value, textContent: o.label, selected: o.selected === true }));
    dom.window.replaceChildren(...options);
    dom.window.disabled = choices[0].disabled === true;
  }

  function sendWindow() {
    const picked = dom.window.value === 'none' ? 'close' : dom.window.value;
    send('state', { window: picked });
  }

  function show(info) {
    dom.toggle.checked = info.enabled;
    dom.toggle.disabled = !info.available;
    dom.hint.textContent = info.available ? '' : NO_EXTRACT;
    dom.status.textContent = blizzard.describe(info);
    dom.wtf.textContent = blizzard.wtfText(info.wtf);
    showLayouts(info);
    showWindows(info);
    dom.actions.disabled = !info.enabled;
    const errors = (info.firstErrors || []).map((e) => el('li', { textContent: `${e.addon}: ${e.message}` }));
    dom.errors.replaceChildren(...errors);
  }

  async function update() {
    try {
      const info = await TK.api('info', {});
      if (info.ok && info.blizzard) show(info.blizzard);
    } catch (err) {
      dom.status.textContent = 'Blizzard UI: ' + err.message;
    }
  }

  async function send(method, req) {
    try {
      const reply = await TK.api(method, req);
      dom.message.textContent = reply.ok ? '' : reply.error;
      await update();
    } catch (err) {
      dom.message.textContent = 'Blizzard UI: ' + err.message;
    }
  }

  function sendActions(event) {
    if (event.key !== 'Enter') return;
    const actions = blizzard.parseActions(dom.actions.value);
    if (!actions) {
      dom.message.textContent = ACTIONS_HINT;

      return;
    }
    send('state', { actions });
  }

  function mount() {
    const section = el('section', { id: 'blizzard' });
    const title = el('h2', { textContent: 'Blizzard UI' });
    dom.toggle = el('input', { id: 'blizzard-toggle', type: 'checkbox', disabled: true });
    dom.hint = el('span', { className: 'hint', textContent: NO_EXTRACT });
    const label = el('label', { textContent: ' Load the Blizzard UI layer ' });
    label.prepend(dom.toggle);
    label.append(dom.hint);
    dom.status = el('p', { id: 'blizzard-status' });
    dom.status.setAttribute('role', 'status');
    dom.wtf = el('p', { className: 'hint' });
    dom.layout = labelled(el('select', { id: 'blizzard-layout', disabled: true }), 'Edit Mode layout');
    dom.window = labelled(el('select', { id: 'blizzard-window', disabled: true }), 'Blizzard window');
    dom.window.append(el('option', { value: 'none', textContent: NO_WINDOWS }));
    const placeholder = 'slot texture [count], e.g. 1 136235 3 or 1 off';
    dom.actions = labelled(el('input', { id: 'blizzard-actions', type: 'text', placeholder, disabled: true }), 'Action slots');
    dom.message = el('p', { className: 'hint' });
    dom.errors = el('ul', { className: 'errors' });
    section.append(title, label, dom.status, dom.wtf, dom.layout, dom.window, dom.actions, dom.message, dom.errors);
    const panels = document.getElementById('panels');
    panels.append(section);
    panels.hidden = false;
    dom.toggle.addEventListener('change', () => send('reload', { blizzardUi: dom.toggle.checked }));
    dom.layout.addEventListener('change', () => send('state', { editMode: { active: Number(dom.layout.value) } }));
    dom.window.addEventListener('change', sendWindow);
    dom.actions.addEventListener('keydown', sendActions);
  }

  const isLive = new URLSearchParams(location.search).get('live') === '1';
  if (isLive) {
    mount();
    TK.on('hello', update);
    TK.on('snapshot', update);
    TK.on('reload', update);
    document.addEventListener('DOMContentLoaded', update);
  }
})(window.TK);
