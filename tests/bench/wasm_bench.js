// The WASM half of the benches (tests/bench/bench_wasm.sh): writes { "<id>": [ms...] } as JSON into #out.
// ?tag=cold|warm names the start-up ids (P4.startup.<tag>, P4.open.<tag>); the worker round trips (P3b.<method>) run only for warm.
// ?runs=<n> is the samples per id; ?fixtures= and ?cases= are the generated scripts of tests/wasm/fixture_js.py.
// worker_tests.js is loaded for its helpers (TKW_TEST); the tests it registers on the stub TK_TESTS never run.
(function () {
  'use strict';

  const { startWorker, send, open, fixtures } = window.TKW_TEST;
  const query = new URLSearchParams(location.search);
  const runs = Number(query.get('runs')) || 5;
  const tag = query.get('tag') || 'warm';
  const CASE_INDEXES = [0, 1, 7, 10];

  const since = (start) => performance.now() - start;

  // { startup, open } ms of a fresh worker: startWorker to the reply of a message of an unknown type (the worker answers it
  // once its module is up, so it is the start-up alone), then the open of SessionDemo. A second open on the same worker would
  // wait LOCK_WAIT_MS (host/worker.js) for the session lock, so it cannot be the baseline to subtract.
  async function startMs() {
    const start = performance.now();
    const worker = startWorker(null);
    try {
      await send(worker, { type: 'ping' });
      const startup = since(start);
      const openStart = performance.now();
      await open(worker);

      return { startup, open: since(openStart) };
    } finally {
      worker.terminate();
    }
  }

  async function roundTrips(results) {
    const worker = startWorker(null);
    try {
      await open(worker);
      for (const index of CASE_INDEXES) {
        const item = PARITY_CASES[index];
        const samples = [];
        for (let run = 0; run < runs; run++) {
          const start = performance.now();
          const reply = await send(worker, { type: 'call', method: item.method, req: item.req });
          samples.push(since(start));
          if (reply.ok === false) throw new Error(item.method + ' failed: ' + JSON.stringify(reply));
        }
        results['P3b.' + item.method] = samples;
      }
    } finally {
      worker.terminate();
    }
  }

  async function run() {
    await Promise.all([fixtures, TKPage.load('cases')]);
    const results = {};
    const starts = [];
    for (let i = 0; i < runs; i++) starts.push(await startMs());
    results['P4.startup.' + tag] = starts.map((one) => one.startup);
    results['P4.open.' + tag] = starts.map((one) => one.open);
    if (tag === 'warm') await roundTrips(results);

    return results;
  }

  document.addEventListener('DOMContentLoaded', async () => {
    const out = document.getElementById('out');
    try {
      out.textContent = JSON.stringify(await run());
    } catch (err) {
      out.textContent = 'FAIL wasm_bench: ' + String((err && err.message) || err);
    }
    out.setAttribute('data-done', '1');
  });
})();
