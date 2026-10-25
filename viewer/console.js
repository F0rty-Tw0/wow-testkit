// Console panel (live mode): the session's console lines (print, chat, error-frame, send, error, system), coloured by
// kind or by the line's own r, g, b, kept scrolled to the newest unless the reader scrolled up, and a Clear button that
// empties the view. It loads the lines so far and takes each console event, merged by seq: a line shows once, in seq
// order, whichever of the two brings it first. A reload keeps the lines and their seq (session_console.lua copies the
// ring); a restarted server (live.js's 'restart') numbers them from 1 again, so the rows shown so far count as older
// than all of its lines, and its lines load afresh. Classic script; colorOf is pure for tests/viewer/unit_panels.js.
window.TK = window.TK || {};

(function (TK) {
  'use strict';

  const panel = (TK.console = {});

  const channel = (value) => Math.round(Math.min(1, Math.max(0, Number(value) || 0)) * 255);

  // The CSS colour of a line's r, g, b, or null when the line has none (its kind colours it).
  panel.colorOf = (line) => {
    if (line.r === undefined) return null;

    return `rgb(${channel(line.r)}, ${channel(line.g)}, ${channel(line.b)})`;
  };

  // DOM ------------------------------------------------------------------------------------------------------------

  // seen: the seqs of this server's lines taken so far, shown or cleared.
  const ui = { seen: new Set() };
  const dom = {};

  // The row a line of this seq goes before: the first of this server's rows with a higher seq, or null for the end.
  function rowAfter(seq) {
    let next = null;
    for (let row = dom.lines.lastElementChild; row && row.dataset.seq !== undefined; row = row.previousElementSibling) {
      const rowSeq = Number(row.dataset.seq);
      if (rowSeq < seq) break;
      next = row;
    }

    return next;
  }

  // seq is undefined for the panel's own lines, which go at the end.
  function addRow(kind, text, color, seq) {
    const atBottom = dom.lines.scrollTop + dom.lines.clientHeight >= dom.lines.scrollHeight - 4;
    const row = document.createElement('li');
    row.className = 'line ' + kind;
    row.textContent = text;
    if (color) row.style.color = color;
    const next = seq === undefined ? null : rowAfter(seq);
    if (seq !== undefined) row.dataset.seq = seq;
    dom.lines.insertBefore(row, next);
    if (atBottom) dom.lines.scrollTop = dom.lines.scrollHeight;
  }

  // Adds a session line once, in seq order: the backlog and the stream may both carry it, in either order.
  function append(line) {
    if (ui.seen.has(line.seq)) return;
    ui.seen.add(line.seq);
    addRow(line.kind, line.text, panel.colorOf(line), line.seq);
  }

  // A restarted server numbers its lines from 1: forget the old seqs, and the rows shown stay above its lines.
  function restart() {
    ui.seen = new Set();
    dom.lines.querySelectorAll('[data-seq]').forEach((row) => row.removeAttribute('data-seq'));
    loadLines();
  }

  function mount() {
    const section = document.createElement('section');
    section.id = 'console';
    const header = document.createElement('header');
    const title = document.createElement('h2');
    title.textContent = 'Console';
    const clear = document.createElement('button');
    clear.type = 'button';
    clear.textContent = 'Clear';
    header.append(title, clear);
    dom.lines = document.createElement('ol');
    dom.lines.className = 'lines';
    dom.lines.setAttribute('aria-live', 'polite');
    section.append(header, dom.lines);
    const panels = document.getElementById('panels');
    panels.append(section);
    panels.hidden = false;
    clear.addEventListener('click', () => dom.lines.replaceChildren());
  }

  async function loadLines() {
    try {
      const reply = await TK.api('console', { since: 0 });
      (reply.lines || []).forEach(append);
    } catch (err) {
      addRow('system', 'Console: ' + err.message, null);
    }
  }

  function start() {
    TK.on('console', append);
    TK.on('restart', restart);
    loadLines();
  }

  const isLive = new URLSearchParams(location.search).get('live') === '1';
  if (isLive) {
    mount();
    document.addEventListener('DOMContentLoaded', start);
  }
})(window.TK);
