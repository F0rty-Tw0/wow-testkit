// Sim clock maths, checked by tests/viewer/unit_sim.js. The viewer steps the sim every STEP_MS and draws between the
// last two replies, one interval behind the newest: TK.simMath.createBuffer() keeps those two worlds, blend(prev, next,
// f) mixes them into the frame TK.scene3d.sync takes. Sim coordinates: pos { x, y } yards, facing 0 = north,
// counter-clockwise, forward (-sin f, cos f), right (cos f, sin f). All of it is pure except createClock, the step
// timer (TK.sim.createClock), which owns the timers its deps give it. Classic script.
window.TK = window.TK || {};

(function (TK) {
  'use strict';

  const STEP_S = 0.033;
  const STEP_MS = 33;
  const SNAPSHOT_MS = 100;
  const PACK_AHEAD = 20;
  const PACK_SPACING = 3;
  const MAX_DT = 0.1;
  const TURN = 2 * Math.PI;

  const { clamp } = TK.scene3d;
  const mix = (a, b, f) => a + (b - a) * f;

  // How far through the newest interval `now` is: 0 when the newest reply has just come, 1 a full interval later.
  function fraction(prevAt, nextAt, now) {
    const span = nextAt - prevAt;
    if (span <= 0) return 1;

    return clamp((now - nextAt) / span, 0, 1);
  }

  // a to b along the shorter arc.
  function lerpAngle(a, b, f) {
    const turn = ((((b - a + Math.PI) % TURN) + TURN) % TURN) - Math.PI;

    return a + turn * f;
  }

  function item(raw, prevRaw, f, isPlayer) {
    const from = prevRaw || raw;
    const pos = { x: mix(from.pos.x, raw.pos.x, f), y: mix(from.pos.y, raw.pos.y, f) };
    const facing = lerpAngle(from.facing, raw.facing, f);
    const out = { raw, prevRaw, pos, facing };
    if (isPlayer) out.isPlayer = true;

    return out;
  }

  // The player first, then each actor of next: one only in next snaps (prevRaw null), one only in prev is dropped.
  function blend(prev, next, f, dt = 0) {
    const before = new Map(prev.actors.map((a) => [a.guid, a]));
    const actors = next.actors.map((a) => item(a, before.get(a.guid) || null, f, false));
    const items = [item(next.player, prev.player, f, true), ...actors];

    return { items, dt };
  }

  // n positions across the player's facing, PACK_AHEAD yards out and PACK_SPACING yards apart, centred.
  function packPositions(player, n = 3) {
    const { pos, facing } = player;
    const centre = { x: pos.x - Math.sin(facing) * PACK_AHEAD, y: pos.y + Math.cos(facing) * PACK_AHEAD };
    const right = { x: Math.cos(facing), y: Math.sin(facing) };
    const slots = Array.from({ length: n }, (_, i) => (i - (n - 1) / 2) * PACK_SPACING);

    return slots.map((s) => ({ x: centre.x + right.x * s, y: centre.y + right.y * s }));
  }

  // The last two replies; sample(now) is the frame between them, dt the seconds since the previous sample.
  function createBuffer() {
    const held = { prev: null, next: null, sampled: null };

    function push(world, at) {
      held.prev = held.next || { world, at };
      held.next = { world, at };
    }

    function sample(now) {
      if (!held.next) return null;
      const { prev, next } = held;
      const f = fraction(prev.at, next.at, now);
      const dt = held.sampled === null ? 0 : clamp((now - held.sampled) / 1000, 0, MAX_DT);
      held.sampled = now;

      return blend(prev.world, next.world, f, dt);
    }

    const last = () => (held.next ? held.next.world : null);

    function clear() {
      Object.assign(held, { prev: null, next: null, sampled: null });
    }

    return { push, sample, last, clear };
  }

  // deps = { api(method, req) -> Promise, now(), setTimeout, clearTimeout, onWorld(world, at), onError(text) }. A tick
  // every STEP_MS asks for one step; a tick while a step is pending is skipped, and the reply that ends the wait arms
  // the next. A reply that is not ok, or a rejection, stops the clock and reports.
  function createClock(deps) {
    const state = { running: false, armed: false, pending: false, token: 0, timer: null };

    function arm() {
      if (!state.running || state.armed) return;
      state.armed = true;
      state.timer = deps.setTimeout(tick, STEP_MS);
    }

    function stop() {
      state.running = false;
      state.armed = false;
      state.token += 1;
      deps.clearTimeout(state.timer);
    }

    function fail(text) {
      stop();
      deps.onError(text);
    }

    // A reply from before a stop() is dropped, but a tick skipped while it was pending leaves no timer, so re-arm.
    function landed(reply, token) {
      state.pending = false;
      if (token !== state.token) return arm();
      if (!reply.ok || !reply.world) {
        fail(reply.error || 'sim step failed');

        return;
      }
      deps.onWorld(reply.world, deps.now());
      arm();
    }

    function rejected(err, token) {
      state.pending = false;
      if (token !== state.token) return arm();
      fail(err.message);
    }

    function tick() {
      state.armed = false;
      if (!state.running || state.pending) return;
      state.pending = true;
      const token = state.token;
      const sent = deps.api('sim', { action: 'step', seconds: STEP_S });
      sent.then((reply) => landed(reply, token), (err) => rejected(err, token));
      arm();
    }

    function start() {
      if (state.running) return;
      state.running = true;
      arm();
    }

    return { start, stop, running: () => state.running };
  }

  TK.simMath = { STEP_S, STEP_MS, SNAPSHOT_MS, fraction, blend, packPositions, createBuffer, createClock };
})(window.TK);
