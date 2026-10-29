// P5 (tests/bench/bench_viewer.sh): the draw time of a large snapshot. Writes { "P5": [ms...] } as JSON into #out: ms of
// each render(snapshot, baseUrl) call (viewer/viewer.js) on a stage that already holds the previous draw.
// ?snap= is the generated script that sets SNAPSHOT (tests/wasm/fixture_js.py --json); ?runs=<n> the samples (default 5);
// ?base= the snapshot.json url its asset urls resolve against (else a font 404s and every redraw waits on it).
// The page loads with live=1 so viewer.js does not look for a snapshot of its own.
(function () {
  'use strict';

  const params = new URLSearchParams(location.search);
  const runs = Number(params.get('runs')) || 5;
  const base = params.get('base') || location.href;

  async function run() {
    await TKPage.load('snap');
    const samples = [];
    for (let i = 0; i < runs; i++) {
      const start = performance.now();
      await window.render(SNAPSHOT, base);
      samples.push(performance.now() - start);
    }
    const drawn = document.getElementById('stage').children.length;
    const expected = SNAPSHOT.items.filter((item) => item.rect).length;
    if (drawn !== expected) throw new Error('drew ' + drawn + ' of ' + expected + ' items: the bench measures nothing');

    return { P5: samples };
  }

  document.addEventListener('DOMContentLoaded', async () => {
    const out = document.getElementById('out');
    try {
      out.textContent = JSON.stringify(await run());
    } catch (err) {
      out.textContent = 'FAIL viewer_draw: ' + String((err && err.message) || err);
    }
    out.setAttribute('data-done', '1');
  });
})();
