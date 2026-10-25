// Developer panel (live mode): one table row per loaded addon with its load time, heap growth (an estimate) and how many
// widgets, unscripted calls and missing globals the session credits to it (TK.api('dev')). A click on a row lists those
// entries below the table. It refetches after every snapshot and reload event. Classic script; rows is pure for
// tests/viewer/unit_dev.js.
window.TK = window.TK || {};

(function (TK) {
  'use strict';

  const dev = (TK.dev = {});

  const COLUMNS = [
    ['name', 'Addon'],
    ['load', 'Load'],
    ['memory', 'Memory (estimate)'],
    ['widgets', 'Widgets'],
    ['unscripted', 'Unscripted'],
    ['missing', 'Missing'],
  ];

  const sum = (list) => list.reduce((total, entry) => total + entry.count, 0);

  // One table row per addon of a dev report: load time and memory as text, widgets as the count of all widgets made,
  // unscripted and missing as the number of distinct entries.
  dev.rows = (report) =>
    report.addons.map((addon) => ({
      name: addon.name,
      load: addon.loadMs.toFixed(1) + ' ms',
      memory: '~' + Math.round(addon.memoryKb) + ' KB',
      widgets: sum(addon.widgets),
      unscripted: addon.unscripted.length,
      missing: addon.missing.length,
    }));

  // DOM ------------------------------------------------------------------------------------------------------------

  const ui = { addons: [], selected: null };
  const dom = {};

  function el(tag, props) {
    return Object.assign(document.createElement(tag), props);
  }

  function detailList(title, entries, label) {
    const items = entries.map((entry) => el('li', { textContent: label(entry) }));
    const list = items.length ? el('ul') : el('p', { className: 'hint', textContent: 'none' });
    list.append(...items);

    return [el('h3', { textContent: title }), list];
  }

  function renderDetail() {
    const addon = ui.addons.find((entry) => entry.name === ui.selected);
    if (!addon) {
      dom.detail.replaceChildren();
      return;
    }
    dom.detail.replaceChildren(
      ...detailList('Widgets', addon.widgets, (entry) => `${entry.type}: ${entry.count}`),
      ...detailList('Unscripted', addon.unscripted, (entry) => `${entry.name}: ${entry.count}`),
      ...detailList('Missing', addon.missing, (entry) => `${entry.name} (${entry.kind}, ${entry.file}): ${entry.count}`),
    );
  }

  function renderTable(report) {
    ui.addons = report.addons;
    const trs = dev.rows(report).map((row) => {
      const tr = el('tr', { className: row.name === ui.selected ? 'selected' : '' });
      tr.dataset.addon = row.name;
      tr.append(...COLUMNS.map(([key]) => el('td', { textContent: String(row[key]) })));

      return tr;
    });
    dom.body.replaceChildren(...trs);
    renderDetail();
  }

  function select(event) {
    const tr = event.target.closest('tr[data-addon]');
    if (!tr) return;
    ui.selected = tr.dataset.addon;
    dom.body.querySelectorAll('tr').forEach((row) => row.classList.toggle('selected', row === tr));
    renderDetail();
  }

  async function refresh() {
    try {
      const reply = await TK.api('dev', {});
      if (!reply.ok) throw new Error(reply.error);
      renderTable(reply);
      dom.status.textContent = (reply.notes || []).join('; ');
    } catch (err) {
      dom.status.textContent = 'Dev: ' + err.message;
    }
  }

  function mount() {
    const section = el('section', { id: 'dev' });
    const title = el('h2', { textContent: 'Dev' });
    const table = el('table');
    const head = el('tr');
    head.append(...COLUMNS.map(([, label]) => el('th', { scope: 'col', textContent: label })));
    const thead = el('thead');
    thead.append(head);
    dom.body = el('tbody');
    table.append(thead, dom.body);
    dom.detail = el('div', { className: 'detail' });
    dom.status = el('p', { className: 'hint' });
    section.append(title, table, dom.detail, dom.status);
    const panels = document.getElementById('panels');
    panels.append(section);
    panels.hidden = false;
    dom.body.addEventListener('click', select);
  }

  const isLive = new URLSearchParams(location.search).get('live') === '1';
  if (isLive) {
    mount();
    TK.on('snapshot', refresh);
    TK.on('reload', refresh);
    document.addEventListener('DOMContentLoaded', refresh);
  }
})(window.TK);
