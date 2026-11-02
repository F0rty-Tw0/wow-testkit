// AC6 probe, the WASM half (spec 13): opens SessionDemo in the worker, reloads it with a sim world, holds W and times 300
// `sim step` round trips with performance.now. Writes {"median_ms":..,"p95_ms":..} into #out; tests/sim/perf_probe.lua is
// the lupa half. worker_tests.js is loaded for its helpers (TKW_TEST); the tests it registers on the stub TK_TESTS never
// run. ?fixtures= is the generated script of tests/wasm/fixture_js.py.
(function () {
  'use strict';

  const { startWorker, send, open, fixtures } = window.TKW_TEST;
  const STEPS = 300;
  const STEP = { action: 'step', seconds: 0.033 };

  const call = (worker, method, req) => send(worker, { type: 'call', method, req });

  const percentile = (sorted, fraction) => sorted[Math.max(1, Math.ceil(sorted.length * fraction)) - 1];

  async function timeSteps(worker) {
    const samples = [];
    for (let i = 0; i < STEPS; i++) {
      const start = performance.now();
      const reply = await call(worker, 'sim', STEP);
      samples.push(performance.now() - start);
      if (reply.ok === false) throw new Error('sim step failed: ' + JSON.stringify(reply));
    }

    return samples.sort((a, b) => a - b);
  }

  async function run() {
    await fixtures;
    const worker = startWorker(null);
    try {
      await open(worker);
      const reloaded = await call(worker, 'reload', { sim: {} });
      if (reloaded.ok === false) throw new Error('reload failed: ' + JSON.stringify(reloaded));
      await call(worker, 'input', { kind: 'keydown', key: 'W' });
      const samples = await timeSteps(worker);

      return { median_ms: percentile(samples, 0.5), p95_ms: percentile(samples, 0.95) };
    } finally {
      worker.terminate();
    }
  }

  document.addEventListener('DOMContentLoaded', async () => {
    const out = document.getElementById('out');
    try {
      out.textContent = JSON.stringify(await run());
    } catch (err) {
      out.textContent = 'FAIL sim_perf: ' + String((err && err.message) || err);
    }
    out.setAttribute('data-done', '1');
  });
})();
