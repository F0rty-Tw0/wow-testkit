// Side B of the parity check (tests/wasm/parity.sh): opens SessionDemo in the worker, runs the cases of parity_cases.json
// (PARITY_CASES, fixture_js.py) and writes [{ method, reply, events }] as JSON into #out, the shape parity_side_a.lua
// writes. worker_tests.js is loaded for its helpers (TKW_TEST); the tests it registers on the stub TK_TESTS never run.
(function () {
  'use strict';

  const { startWorker, send, events, open, fixtures } = window.TKW_TEST;

  // The events of a message follow its reply, so the read-only `info` call is sent after it: its reply arrives after
  // them. Returns the events the worker posted since the last take, as SessionHost's drain lists them: [{ event, data }].
  async function take(worker, seen) {
    await send(worker, { type: 'call', method: 'info', req: {} });

    return seen.splice(0).map((e) => ({ event: e.name, data: e.data }));
  }

  async function run() {
    await Promise.all([fixtures, TKPage.load('cases')]);
    const worker = startWorker(null);
    const seen = events(worker);
    const steps = [];
    try {
      const reply = await open(worker);
      steps.push({ method: 'open', reply, events: await take(worker, seen) });
      for (const item of PARITY_CASES) {
        const result = await send(worker, { type: 'call', method: item.method, req: item.req });
        steps.push({ method: item.method, reply: result, events: await take(worker, seen) });
      }
    } finally {
      worker.terminate();
    }

    return steps;
  }

  document.addEventListener('DOMContentLoaded', async () => {
    const out = document.getElementById('out');
    try {
      out.textContent = JSON.stringify(await run());
    } catch (err) {
      out.textContent = 'FAIL parity: ' + String((err && err.message) || err);
    }
    out.setAttribute('data-done', '1');
  });
})();
