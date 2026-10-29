// Events panel (live mode): fires a game event at the session. The name field suggests every event of the flavor's API
// docs (TK.api('events')); picking one shows an input per payload parameter, and Fire sends the typed values
// (TK.api('fire')). Classic script; parseArg and argsFor are pure for tests/viewer/unit_panels.js.
window.TK = window.TK || {};

(function (TK) {
  'use strict';

  const events = (TK.events = {});

  function bad(type, text) {
    return new Error(`bad ${type}: ${text}`);
  }

  function parseJson(text, type) {
    try {
      return JSON.parse(text);
    } catch {
      throw bad(type, text);
    }
  }

  // The value text stands for as a payload parameter of Lua type `type`: the word nil is null; number, boolean and
  // table must parse as one; string is the text as typed; any other type reads JSON when it can, else the text.
  events.parseArg = (text, type) => {
    if (text === 'nil') return null;
    if (type === 'string') return text;
    if (type === 'number') {
      const value = Number(text);
      if (text.trim() === '' || !Number.isFinite(value)) throw bad(type, text);

      return value;
    }
    if (type === 'boolean') {
      if (text !== 'true' && text !== 'false') throw bad(type, text);

      return text === 'true';
    }
    if (type === 'table') return parseJson(text, type);
    try {
      return JSON.parse(text);
    } catch {
      return text;
    }
  };

  // One value per payload parameter, in order; an empty field is null.
  events.argsFor = (payload, texts) => payload.map((param, i) => (texts[i] ? events.parseArg(texts[i], param.type) : null));

  // DOM ------------------------------------------------------------------------------------------------------------

  const ui = { byName: new Map(), loaded: false };
  const dom = {};

  function el(tag, props) {
    return Object.assign(document.createElement(tag), props);
  }

  function payloadOf(name) {
    const event = ui.byName.get(name.trim());

    return event ? event.payload : [];
  }

  function renderParams() {
    const fields = payloadOf(dom.name.value).map((param) => {
      const input = el('input', { type: 'text', placeholder: `${param.name}: ${param.type}${param.nilable ? '?' : ''}` });
      input.setAttribute('aria-label', param.name);

      return input;
    });
    dom.params.replaceChildren(...fields);
  }

  async function fire() {
    const event = dom.name.value.trim();
    if (!event) return;
    const texts = [...dom.params.querySelectorAll('input')].map((input) => input.value);
    try {
      const args = events.argsFor(payloadOf(event), texts);
      const reply = await TK.api('fire', { event, args });
      dom.status.textContent = reply.ok ? `Fired ${event}` : reply.error;
    } catch (err) {
      dom.status.textContent = err.message;
    }
  }

  function mount() {
    const section = el('section', { id: 'events' });
    const title = el('h2', { textContent: 'Events' });
    const list = el('datalist', { id: 'event-names' });
    dom.name = el('input', { type: 'text', placeholder: 'EVENT_NAME', spellcheck: false, autocomplete: 'off' });
    dom.name.setAttribute('list', 'event-names');
    dom.name.setAttribute('aria-label', 'Event name');
    dom.params = el('div', { className: 'params' });
    const button = el('button', { type: 'button', textContent: 'Fire' });
    dom.status = el('p', { className: 'hint' });
    dom.status.setAttribute('role', 'status');
    dom.list = list;
    section.append(title, dom.name, list, dom.params, button, dom.status);
    const panels = document.getElementById('panels');
    panels.append(section);
    panels.hidden = false;
    dom.name.addEventListener('input', renderParams);
    button.addEventListener('click', fire);
  }

  // The flavor's event names. A failed load is tried again when the session says hello, so a session that was down at
  // start fills the list later; a reload loads them again, as it may change the flavor.
  async function load() {
    try {
      const reply = await TK.api('events', {});
      ui.byName = new Map((reply.events || []).map((event) => [event.name, event]));
      dom.list.replaceChildren(...[...ui.byName.keys()].map((name) => el('option', { value: name })));
      if (!ui.loaded) dom.status.textContent = '';
      ui.loaded = true;
    } catch (err) {
      dom.status.textContent = 'Events: ' + err.message;
    }
  }

  function start() {
    TK.on('hello', () => ui.loaded || load());
    TK.on('reload', load);
    load();
  }

  const isLive = new URLSearchParams(location.search).get('live') === '1';
  if (isLive) {
    mount();
    document.addEventListener('DOMContentLoaded', start);
  }
})(window.TK);
