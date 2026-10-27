// Combat toolbar and log panel (live mode). #combat, a bar under #toolbar: preset (Solo, Dungeon, Raid 10 to 40),
// faction, race (the flavor's races of that faction), class, In combat, Apply, Pull, the enemy to kill and Kill target,
// Play / Pause, speed and the time readout. Every control posts /call/combat (session_combat.lua). Play posts a step of
// 0.1 * speed seconds every 100 ms until Pause, so the session's clock moves only while this page asks (a background
// tab's timers slow to about 1 s). #combatlog lists the combat log's text lines (/call/combatlog) after every combat
// reply and combatlog event, kept scrolled to the newest unless the reader scrolled up, with Clear. Each ok reply emits
// 'combat' { action, inCombat } on the TK bus, so the Mock state panel (state.js) re-reads. A reload is a new
// world whose log numbers its lines from 1 again. Classic script; parseSpeed, formatTime and presetRequest are pure for
// tests/viewer/unit_combat.js.
window.TK = window.TK || {};

(function (TK) {
  'use strict';

  const combat = (TK.combat = {});

  combat.SPEEDS = [0.25, 0.5, 1, 2, 4, 8];
  const TICK_MS = 100;
  const PRESETS = [
    ['solo', 'Solo'],
    ['dungeon', 'Dungeon'],
    ['raid:10', 'Raid 10'],
    ['raid:20', 'Raid 20'],
    ['raid:25', 'Raid 25'],
    ['raid:40', 'Raid 40'],
  ];
  const FACTIONS = ['Alliance', 'Horde'];

  // The speed a picker's text names, or null unless it is one of the six speeds.
  combat.parseSpeed = (text) => {
    const speed = String(text).trim() === '' ? NaN : Number(text);

    return combat.SPEEDS.includes(speed) ? speed : null;
  };

  // "m:ss.t" of a time in seconds, tenths truncated.
  combat.formatTime = (seconds) => {
    const tenths = Math.floor(seconds * 10 + 1e-6);
    const rest = tenths % 600;
    const whole = String(Math.floor(rest / 10)).padStart(2, '0');

    return `${Math.floor(tenths / 600)}:${whole}.${rest % 10}`;
  };

  // The /call/combat preset request of a preset picker value ("dungeon", "raid:25") and the picks { faction, race,
  // className, inCombat }; an empty race or class is left to the session's default.
  combat.presetRequest = (value, picks) => {
    const [name, size] = value.split(':');
    const opts = { faction: picks.faction, inCombat: picks.inCombat };
    if (size) opts.size = Number(size);
    if (picks.race) opts.race = picks.race;
    if (picks.className) opts.class = picks.className;

    return { action: 'preset', name, opts };
  };

  // DOM ------------------------------------------------------------------------------------------------------------

  // since: the seq of the newest log line shown; timer: the play interval while playing.
  const ui = { roster: null, since: 0, timer: null, stepping: false, log: { busy: false, again: false } };
  const dom = {};

  function el(tag, props) {
    return Object.assign(document.createElement(tag), props);
  }

  function labelled(node, label) {
    node.setAttribute('aria-label', label);

    return node;
  }

  function options(select, pairs) {
    const kept = select.value;
    select.replaceChildren(...pairs.map(([value, text]) => el('option', { value, textContent: text })));
    if (pairs.some(([value]) => value === kept)) select.value = kept;
  }

  function say(text) {
    dom.status.textContent = text;
  }

  function fillRaces() {
    const races = (ui.roster && ui.roster.races[dom.faction.value]) || [];
    options(dom.race, races.map((name) => [name, name]));
  }

  function fillEnemies(enemies) {
    options(dom.target, enemies.map((enemy) => [enemy.guid, enemy.name]));
    dom.kill.disabled = enemies.length === 0;
  }

  function show(reply) {
    if (!reply.ok) {
      say(reply.error);

      return;
    }
    say('');
    dom.time.textContent = combat.formatTime(reply.time);
    fillEnemies(reply.enemies || []);
  }

  function appendLine(line) {
    if (line.seq <= ui.since) return;
    ui.since = line.seq;
    const atBottom = dom.lines.scrollTop + dom.lines.clientHeight >= dom.lines.scrollHeight - 4;
    const row = el('li', { className: 'line', textContent: line.text });
    row.dataset.subevent = line.subevent;
    dom.lines.append(row);
    if (atBottom) dom.lines.scrollTop = dom.lines.scrollHeight;
  }

  // One read at a time; a request while one is out reads again once it is back.
  async function fetchLog() {
    if (ui.log.busy) {
      ui.log.again = true;

      return;
    }
    ui.log.busy = true;
    try {
      do {
        ui.log.again = false;
        const reply = await TK.api('combatlog', { since: ui.since });
        (reply.lines || []).forEach(appendLine);
      } while (ui.log.again);
    } catch (err) {
      say('Combat log: ' + err.message);
    } finally {
      ui.log.busy = false;
    }
  }

  async function send(req) {
    try {
      const reply = await TK.api('combat', req);
      show(reply);
      fetchLog();
      if (reply.ok) TK.emit('combat', { action: req.action, inCombat: reply.inCombat });

      return reply;
    } catch (err) {
      say('Combat: ' + err.message);

      return { ok: false };
    }
  }

  async function loadRoster() {
    const reply = await send({ action: 'roster' });
    if (!reply.ok) return;
    ui.roster = { races: reply.races };
    options(dom.className, reply.classes.map((entry) => [entry.file, entry.name]));
    fillRaces();
  }

  function apply() {
    const picks = {
      faction: dom.faction.value,
      race: dom.race.value,
      className: dom.className.value,
      inCombat: dom.inCombat.checked,
    };
    send(combat.presetRequest(dom.preset.value, picks));
  }

  function stopTimer() {
    clearInterval(ui.timer);
    ui.timer = null;
    dom.play.textContent = 'Play';
  }

  async function tick() {
    if (ui.stepping) return;
    ui.stepping = true;
    const reply = await send({ action: 'step', seconds: 0.1 * combat.parseSpeed(dom.speed.value) });
    ui.stepping = false;
    if (!reply.ok && ui.timer) stopTimer();
  }

  async function play() {
    const speed = combat.parseSpeed(dom.speed.value);
    if (speed === null) {
      say('Speed must be one of ' + combat.SPEEDS.join(', '));

      return;
    }
    const reply = await send({ action: 'play', speed });
    if (reply.ok && !ui.timer) {
      ui.timer = setInterval(tick, TICK_MS);
      dom.play.textContent = 'Pause';
    }
  }

  function togglePlay() {
    if (!ui.timer) {
      play();

      return;
    }
    stopTimer();
    send({ action: 'pause' });
  }

  // A reload builds a new world: its log starts over, its flavor may differ, and nothing is playing there.
  function reset() {
    if (ui.timer) stopTimer();
    ui.since = 0;
    loadRoster();
  }

  function button(id, text, onClick) {
    const node = el('button', { id, type: 'button', textContent: text });
    node.addEventListener('click', onClick);

    return node;
  }

  function mountBar() {
    dom.preset = labelled(el('select', { id: 'combat-preset' }), 'Combat preset');
    options(dom.preset, PRESETS);
    dom.preset.value = 'dungeon';
    dom.faction = labelled(el('select', { id: 'combat-faction' }), 'Faction');
    options(dom.faction, FACTIONS.map((name) => [name, name]));
    dom.race = labelled(el('select', { id: 'combat-race' }), 'Race');
    dom.className = labelled(el('select', { id: 'combat-class' }), 'Class');
    dom.inCombat = el('input', { id: 'combat-incombat', type: 'checkbox' });
    const inCombat = el('label');
    inCombat.append(dom.inCombat, ' In combat');
    dom.target = labelled(el('select', { id: 'combat-target' }), 'Enemy to kill');
    dom.kill = button('combat-kill', 'Kill target', () => send({ action: 'kill', target: dom.target.value }));
    dom.play = button('combat-play', 'Play', togglePlay);
    dom.speed = labelled(el('select', { id: 'combat-speed' }), 'Speed');
    options(dom.speed, combat.SPEEDS.map((speed) => [String(speed), speed + 'x']));
    dom.speed.value = '1';
    dom.time = el('span', { id: 'combat-time', textContent: combat.formatTime(0) });
    dom.status = el('span', { id: 'combat-status' });
    dom.status.setAttribute('role', 'status');
    const bar = el('div', { id: 'combat' });
    bar.append(
      dom.preset,
      dom.faction,
      dom.race,
      dom.className,
      inCombat,
      button('combat-apply', 'Apply', apply),
      button('combat-pull', 'Pull', () => send({ action: 'pull' })),
      dom.target,
      dom.kill,
      dom.play,
      dom.speed,
      dom.time,
      dom.status,
    );
    document.getElementById('toolbar').after(bar);
    dom.faction.addEventListener('change', fillRaces);
    dom.speed.addEventListener('change', () => ui.timer && play());
  }

  function mountLog() {
    const section = el('section', { id: 'combatlog' });
    const header = el('header');
    const clear = button('combatlog-clear', 'Clear', () => dom.lines.replaceChildren());
    header.append(el('h2', { textContent: 'Combat log' }), clear);
    dom.lines = el('ol', { className: 'lines' });
    dom.lines.setAttribute('aria-live', 'polite');
    section.append(header, dom.lines);
    const panels = document.getElementById('panels');
    panels.append(section);
    panels.hidden = false;
  }

  function start() {
    TK.on('combatlog', fetchLog);
    TK.on('reload', reset);
    TK.on('restart', reset);
    loadRoster();
  }

  const isLive = new URLSearchParams(location.search).get('live') === '1';
  if (isLive) {
    mountBar();
    mountLog();
    document.addEventListener('DOMContentLoaded', start);
  }
})(window.TK);
