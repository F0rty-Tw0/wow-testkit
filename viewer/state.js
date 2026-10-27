// Mock state panel (live mode): a JSON fixture editor per unit token, the mouseover unit, the shift/ctrl/alt keys, the
// combat flag and the group kind. Each change sends a patch (TK.api('state')) and shows the merged state the session
// answers; a reload and a combat action (combat.js) read the session's state afresh.
window.TK = window.TK || {};

(function (TK) {
  'use strict';

  const TOKENS = ['player', 'target', 'focus', 'pet', 'party1', 'party2', 'party3', 'party4', 'mouseover'];
  const MODIFIERS = ['shift', 'ctrl', 'alt'];
  const GROUPS = ['none', 'party', 'raid'];

  const ui = { state: null };
  const dom = {};

  function el(tag, props) {
    return Object.assign(document.createElement(tag), props);
  }

  function options(select, values, blank) {
    const first = blank ? [el('option', { value: '', textContent: '(none)' })] : [];
    select.replaceChildren(...first, ...values.map((value) => el('option', { value, textContent: value })));
  }

  function showUnit() {
    const units = (ui.state && ui.state.units) || {};
    const fixture = units[dom.token.value];
    dom.fixture.value = fixture ? JSON.stringify(fixture, null, 2) : '{}';
  }

  function show(state) {
    ui.state = state;
    MODIFIERS.forEach((key) => {
      dom[key].checked = Boolean(state.modifiers && state.modifiers[key]);
    });
    dom.combat.checked = Boolean(state.combat);
    dom.group.value = state.group || 'none';
    dom.mouseover.value = state.mouseover || '';
    showUnit();
  }

  async function send(patch) {
    try {
      const reply = await TK.api('state', patch);
      dom.status.textContent = reply.ok ? '' : reply.error;
      if (reply.ok) show(reply.state);
    } catch (err) {
      dom.status.textContent = 'State: ' + err.message;
    }
  }

  function applyUnit() {
    let fixture;
    try {
      fixture = JSON.parse(dom.fixture.value);
    } catch (err) {
      dom.status.textContent = `${dom.token.value}: ${err.message}`;

      return;
    }
    send({ units: { [dom.token.value]: fixture } });
  }

  function checkbox(label) {
    const input = el('input', { type: 'checkbox' });
    const wrap = el('label');
    wrap.append(input, ' ' + label);

    return [input, wrap];
  }

  function labelled(text, control) {
    const wrap = el('label', { textContent: text + ' ' });
    wrap.append(control);

    return wrap;
  }

  function mountUnits(section) {
    dom.token = el('select');
    options(dom.token, TOKENS, false);
    dom.token.setAttribute('aria-label', 'Unit token');
    dom.fixture = el('textarea', { rows: 4, spellcheck: false });
    dom.fixture.setAttribute('aria-label', 'Unit fixture JSON');
    const apply = el('button', { type: 'button', textContent: 'Apply' });
    const row = el('div', { className: 'units' });
    row.append(dom.token, apply);
    section.append(row, dom.fixture);
    dom.token.addEventListener('change', showUnit);
    apply.addEventListener('click', applyUnit);
  }

  function mountFlags(section) {
    const keys = el('div', { className: 'flags' });
    MODIFIERS.concat('combat').forEach((key) => {
      const [input, wrap] = checkbox(key);
      dom[key] = input;
      keys.append(wrap);
      input.addEventListener('change', () => {
        const patch = key === 'combat' ? { combat: input.checked } : { modifiers: { [key]: input.checked } };
        send(patch);
      });
    });
    dom.mouseover = el('select');
    options(dom.mouseover, TOKENS.filter((token) => token !== 'mouseover'), true);
    dom.group = el('select');
    options(dom.group, GROUPS, false);
    const selects = el('div', { className: 'flags' });
    selects.append(labelled('mouseover', dom.mouseover), labelled('group', dom.group));
    section.append(keys, selects);
    dom.mouseover.addEventListener('change', () => dom.mouseover.value && send({ mouseover: dom.mouseover.value }));
    dom.group.addEventListener('change', () => send({ group: dom.group.value }));
  }

  function mount() {
    const section = el('section', { id: 'state' });
    section.append(el('h2', { textContent: 'Mock state' }));
    mountUnits(section);
    mountFlags(section);
    dom.status = el('p', { className: 'hint' });
    dom.status.setAttribute('role', 'status');
    section.append(dom.status);
    const panels = document.getElementById('panels');
    panels.append(section);
    panels.hidden = false;
  }

  // A combat action may set the combat flag, the group and the fixtures. A step re-reads only when it flips combat, so
  // a playing fight does not overwrite a fixture being edited ten times a second.
  function onCombat(change) {
    const flipped = Boolean(change.inCombat) !== dom.combat.checked;
    if (change.action !== 'step' || flipped) send({});
  }

  function start() {
    TK.on('reload', () => send({}));
    TK.on('combat', onCombat);
    send({});
  }

  const isLive = new URLSearchParams(location.search).get('live') === '1';
  if (isLive) {
    mount();
    document.addEventListener('DOMContentLoaded', start);
  }
})(window.TK);
