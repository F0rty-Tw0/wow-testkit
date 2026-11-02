// AC6 probe, the WASM half (spec 13): opens SessionDemo in the worker, reloads it with a sim world, holds W and times 300
// `sim step` calls two ways: page side, each round trip with performance.now (`page`), then worker side, a batch of
// tk_call + tk_drain timed one by one inside the worker by a test hook (`worker`, the Lua cost without postMessage).
// Writes {"mode", "flavor", "blizzardErrors", "page": {median_ms, p95_ms}, "worker": {...}, ...} into #out;
// tests/sim/perf_probe.lua is the lupa half. ?extract= is the generated list of a client extract's files
// (tests/wasm/sim_perf.sh): the page reads them over file:// (Chrome's --allow-file-access-from-files), opens with them
// as the host does and reloads with Blizzard's UI. worker_tests.js is loaded for its helpers (TKW_TEST); the tests it
// registers on the stub TK_TESTS never run. ?fixtures= is the generated script of tests/wasm/fixture_js.py.
(function () {
  'use strict';

  const { startWorker, send, open, fixtures } = window.TKW_TEST;
  const STEPS = 300;
  const STEP = { action: 'step', seconds: 0.033 };
  const READERS = 16;

  const call = (worker, method, req) => send(worker, { type: 'call', method, req });

  const percentile = (sorted, fraction) => sorted[Math.max(1, Math.ceil(sorted.length * fraction)) - 1];

  function summary(samples) {
    const sorted = samples.slice().sort((a, b) => a - b);

    return { median_ms: percentile(sorted, 0.5), p95_ms: percentile(sorted, 0.95) };
  }

  function checked(reply, what) {
    if (reply.ok === false) throw new Error(what + ' failed: ' + JSON.stringify(reply));

    return reply;
  }

  // Runs after worker.js inside the worker (startWorker): answers { type: "steps", id, count, req } by running count sim
  // calls straight through the module, each timed with the worker's performance.now, and replies { samples, error? }.
  // Other messages go to worker.js's handler; the page sends steps only while that handler is idle.
  function stepHook() {
    const next = self.onmessage;
    self.onmessage = (ev) => {
      if (ev.data.type !== 'steps') return next(ev);
      const mod = TKW.mod;
      const req = JSON.stringify(ev.data.req);
      const samples = [];
      let error;
      for (let i = 0; i < ev.data.count && !error; i++) {
        const start = performance.now();
        const json = mod.ccall('tk_call', 'string', ['string', 'string'], ['sim', req]);
        mod.ccall('tk_drain', 'string', [], []);
        samples.push(performance.now() - start);
        if (JSON.parse(json).ok === false) error = json;
      }
      self.postMessage({ type: 'reply', id: ev.data.id, json: JSON.stringify({ samples, error }) });
    };
  }

  // One extract file read over file:// as a Blob; fetch refuses the scheme, XHR takes it with the Chrome flag.
  function readFile(url) {
    return new Promise((resolve, reject) => {
      const xhr = new XMLHttpRequest();
      xhr.open('GET', url);
      xhr.responseType = 'blob';
      xhr.onload = () => (xhr.response ? resolve(xhr.response) : reject(new Error('empty read: ' + url)));
      xhr.onerror = () => reject(new Error('cannot read ' + url + ' (is --allow-file-access-from-files set?)'));
      xhr.send();
    });
  }

  // [{ path, file }] of EXTRACT_FILES ({ base, paths }), the shape the host hands the worker (host/host.js).
  async function extractEntries() {
    const { base, paths } = EXTRACT_FILES;
    const entries = new Array(paths.length);
    let next = 0;
    const reader = async () => {
      while (next < paths.length) {
        const at = next++;
        const url = base + paths[at].split('/').map(encodeURIComponent).join('/');
        entries[at] = { path: paths[at], file: await readFile(url) };
      }
    };
    await Promise.all(Array.from({ length: READERS }, reader));

    return entries;
  }

  async function pageSteps(worker) {
    const samples = [];
    for (let i = 0; i < STEPS; i++) {
      const start = performance.now();
      const reply = await call(worker, 'sim', STEP);
      samples.push(performance.now() - start);
      checked(reply, 'sim step');
    }

    return samples;
  }

  async function workerSteps(worker) {
    const reply = await send(worker, { type: 'steps', count: STEPS, req: STEP });
    if (reply.error) throw new Error('worker sim step failed: ' + reply.error);

    return reply.samples;
  }

  async function run() {
    const withExtract = new URLSearchParams(location.search).has('extract');
    await Promise.all([fixtures, withExtract ? TKPage.load('extract') : null]);
    const readStart = performance.now();
    const extract = withExtract ? await extractEntries() : undefined;
    const readMs = performance.now() - readStart;
    const worker = startWorker(stepHook);
    try {
      checked(await open(worker, { extract }), 'open');
      const reloadStart = performance.now();
      checked(await call(worker, 'reload', { sim: {}, blizzardUi: withExtract }), 'reload');
      const reloadMs = performance.now() - reloadStart;
      const info = checked(await call(worker, 'info', {}), 'info');
      checked(await call(worker, 'input', { kind: 'keydown', key: 'W' }), 'keydown W');
      const page = summary(await pageSteps(worker));
      const inWorker = summary(await workerSteps(worker));
      const result = {
        mode: withExtract ? 'blizzardUi' : 'kit-only',
        flavor: info.flavor,
        files: extract ? extract.length : 0,
        readMs,
        reloadMs,
        blizzardEnabled: info.blizzard.enabled,
        blizzardErrors: info.blizzard.errors,
        page,
        worker: inWorker,
      };

      return result;
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
