// Console panel (live mode): the session's console lines (print, chat, error-frame, send, error, system), coloured by
// kind or by the line's own r, g, b, kept scrolled to the newest unless the reader scrolled up, and a Clear button that
// empties the view. It loads the lines so far, then appends each console event. A reload keeps the lines and their
// seq (session_console.lua copies the ring); a restarted server (live.js's 'restart') numbers them from 1 again, so
// the last seq resets and its lines load afresh. Classic script; colorOf is pure for tests/viewer/unit_panels.js.
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

  const ui = { seq: 0 };
  const dom = {};

  function addRow(kind, text, color) {
    const atBottom = dom.lines.scrollTop + dom.lines.clientHeight >= dom.lines.scrollHeight - 4;
    const row = document.createElement('li');
    row.className = 'line ' + kind;
    row.textContent = text;
    if (color) row.style.color = color;
    dom.lines.append(row);
    if (atBottom) dom.lines.scrollTop = dom.lines.scrollHeight;
  }

  // Adds a session line once: the backlog and the stream may both carry it.
  function append(line) {
    if (line.seq <= ui.seq) return;
    ui.seq = line.seq;
    addRow(line.kind, line.text, panel.colorOf(line));
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
    TK.on('restart', () => {
      ui.seq = 0;
      loadLines();
    });
    loadLines();
  }

  const isLive = new URLSearchParams(location.search).get('live') === '1';
  if (isLive) {
    mount();
    document.addEventListener('DOMContentLoaded', start);
  }
})(window.TK);
