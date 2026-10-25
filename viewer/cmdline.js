// Command line panel (live mode): a chat-style input that sends a slash command to the session on Enter
// (TK.api('slash')); ArrowUp and ArrowDown recall earlier lines. The session's answer shows in the console panel.
// Classic script; History and normalize are pure for tests/viewer/unit_panels.js.
window.TK = window.TK || {};

(function (TK) {
  'use strict';

  const cmdline = (TK.cmdline = {});

  // Lines sent so far. up() walks back from the newest and stops at the oldest; down() walks forward and ends at ''.
  cmdline.History = class History {
    constructor() {
      this.lines = [];
      this.at = 0;
    }

    push(line) {
      this.lines.push(line);
      this.at = this.lines.length;
    }

    up() {
      if (this.at > 0) this.at--;

      return this.lines[this.at] ?? '';
    }

    down() {
      if (this.at < this.lines.length) this.at++;

      return this.lines[this.at] ?? '';
    }
  };

  // The trimmed text when it is a slash command, else null.
  cmdline.normalize = (text) => {
    const line = String(text).trim();

    return line.startsWith('/') ? line : null;
  };

  // DOM ------------------------------------------------------------------------------------------------------------

  const history = new cmdline.History();

  async function send(input, hint) {
    const line = cmdline.normalize(input.value);
    hint.textContent = line ? '' : 'Commands start with /';
    if (!line) return;
    history.push(line);
    input.value = '';
    try {
      const reply = await TK.api('slash', { text: line });
      if (reply.ok === false) hint.textContent = reply.error;
    } catch (err) {
      hint.textContent = 'Command failed: ' + err.message;
    }
  }

  function onKey(ev, input, hint) {
    if (ev.key === 'Enter') {
      ev.preventDefault();
      send(input, hint);
    } else if (ev.key === 'ArrowUp' || ev.key === 'ArrowDown') {
      ev.preventDefault();
      input.value = ev.key === 'ArrowUp' ? history.up() : history.down();
    }
  }

  function mount() {
    const section = document.createElement('section');
    section.id = 'cmdline';
    const input = document.createElement('input');
    Object.assign(input, { type: 'text', placeholder: '/run print("hi")', spellcheck: false, autocomplete: 'off' });
    input.setAttribute('aria-label', 'Slash command');
    const hint = document.createElement('p');
    hint.className = 'hint';
    hint.setAttribute('role', 'status');
    section.append(input, hint);
    const panels = document.getElementById('panels');
    panels.append(section);
    panels.hidden = false;
    input.addEventListener('keydown', (ev) => onKey(ev, input, hint));
  }

  const isLive = new URLSearchParams(location.search).get('live') === '1';
  if (isLive) mount();
})(window.TK);
