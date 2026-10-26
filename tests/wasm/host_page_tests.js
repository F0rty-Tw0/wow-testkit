// Host page checks (Task 5b.6): the asset rules of host_assets.js, then the page wiring of host_page.js over the real
// worker: TK.api through the worker backend, the kit-only banner, the missing-art badge, Re-import and the background
// slot. host.html?shot=1 only launches SessionDemo and draws it, for the screenshot host_check.sh takes.
(function () {
  'use strict';

  const T = window.TK_TESTS;
  const HA = window.TK.hostAssets;
  const { until, fixtures } = window.TKH_TEST;
  const shown = (id) => !document.getElementById(id).hidden;
  const textOf = (id) => document.getElementById(id).textContent;

  // A w x h PNG whose left half is red and right half blue.
  function halves(w, h) {
    const canvas = new OffscreenCanvas(w, h);
    const ctx = canvas.getContext('2d');
    ctx.fillStyle = '#f00';
    ctx.fillRect(0, 0, w / 2, h);
    ctx.fillStyle = '#00f';
    ctx.fillRect(w / 2, 0, w / 2, h);

    return canvas.convertToBlob({ type: 'image/png' });
  }

  // The size of the image at url and its pixels as [r, g, b, a].
  async function pixels(url) {
    const blob = await (await fetch(url)).blob();
    const bitmap = await createImageBitmap(blob);
    const ctx = new OffscreenCanvas(bitmap.width, bitmap.height).getContext('2d');
    ctx.drawImage(bitmap, 0, 0);
    const at = (x, y) => [...ctx.getImageData(x, y, 1, 1).data];

    return { width: bitmap.width, height: bitmap.height, at };
  }

  // SessionDemo plus a frame with two textures: Art/pic.png (a real 2x2 PNG) and Art/Glow.blp, which Chrome cannot decode.
  const ART = [
    'local art = CreateFrame("Frame", "SessionDemoArt", UIParent)',
    'art:SetSize(96, 48)',
    'art:SetPoint("TOPLEFT", 40, -40)',
    'local pic = art:CreateTexture()',
    'pic:SetSize(48, 48)',
    'pic:SetPoint("LEFT")',
    String.raw`pic:SetTexture("Interface\\AddOns\\SessionDemo\\Art\\pic")`,
    'local glow = art:CreateTexture()',
    'glow:SetSize(48, 48)',
    'glow:SetPoint("RIGHT")',
    String.raw`glow:SetTexture("Interface\\AddOns\\SessionDemo\\Art\\Glow")`,
  ].join('\n');

  async function demoDir() {
    await fixtures;
    const toc = FIXTURE_FILES.SessionDemo['SessionDemo.toc'] + '\nArt.lua\n';
    const extra = { 'Art.lua': ART, 'Art/pic.png': await halves(2, 2), 'Art/Glow.blp': 'BLP2', 'SessionDemo.toc': toc };

    return fakeDir(treeOf(Object.assign({}, FIXTURE_FILES.SessionDemo, extra)), 'SessionDemo');
  }

  // Launches the page on deps (the addon defaults to a new demoDir()) under an account of its own and waits for Running.
  let accounts = 0;
  async function demo(deps) {
    const addon = (deps && deps.addon) || (await demoDir());
    const ctl = TK.hostPage.launch(Object.assign({ addon, account: 'P' + ++accounts }, deps));
    await until(() => ctl.state() === 'Running', 'Running, in ' + ctl.state());

    return ctl;
  }

  const assetAt = (snapshot, tail) => Object.values(snapshot.assets).find((asset) => String(asset.path).endsWith(tail));

  T.push({
    name: 'crop_rect_rounds_half_to_even',
    fn: () => {
      A.same(HA.cropRect({ left: 0.25, right: 0.75, top: 0, bottom: 0.5 }, 10, 10), { sx: 2, sy: 0, sw: 6, sh: 5 });
      A.same(HA.cropRect({ left: 0.125, right: 0.375, top: 0.125, bottom: 0.375 }, 4, 4), { sx: 0, sy: 0, sw: 2, sh: 2 });
    },
  });

  T.push({
    name: 'atlas_crop_becomes_a_png_blob',
    fn: async () => {
      const sheet = new File([await halves(4, 4)], '1.png');
      const files = { addon: new Map(), extract: new Map([['art/by-id/1.png', sheet]]) };
      const crop = { left: 0.5, right: 1, top: 0, bottom: 0.5 };
      const url = await HA.urlFor({ source: 'extract', path: 'art/by-id/1.png', crop }, files, new Map());
      A.eq(/^blob:/.test(url), true, String(url));
      const image = await pixels(url);
      A.same([image.width, image.height], [2, 2]);
      A.same(image.at(0, 0), [0, 0, 255, 255], 'the right half of the sheet');
    },
  });

  T.push({
    name: 'tga_and_blp_count_as_missing',
    fn: async () => {
      const blp = new File(['BLP2'], 'Glow.blp');
      const files = { addon: new Map([['Art/Glow.blp', blp], ['Art/Old.TGA', blp]]), extract: new Map() };
      const cache = new Map();
      A.eq(await HA.urlFor({ source: 'addon', path: 'Art/Glow.blp' }, files, cache), null);
      A.eq(await HA.urlFor({ source: 'addon', path: 'Art/Old.TGA' }, files, cache), null);
      const glowPath = 'Interface\\AddOns\\Demo\\Art\\Glow.blp';
      const assets = {
        glow: { kind: 'path', path: glowPath, located: { source: 'addon', path: 'Art/Glow.blp' } },
        font: { kind: 'font', path: 'Fonts\\FRIZQT__.TTF' },
        icon: { kind: 'fileID', fileID: 136235 },
      };
      A.eq(await HA.resolve({ assets }, files, cache), 2, 'the font is a stand-in, not missing art');
      A.same(assets.glow, { kind: 'path', path: glowPath, source: 'placeholder', missing: true, label: 'glow.blp' });
      A.same(assets.font, { kind: 'font', path: 'Fonts\\FRIZQT__.TTF', source: 'standin' });
      A.eq(assets.icon.label, '#136235');
    },
  });

  T.push({
    name: 'addon_cache_is_dropped_on_remount',
    fn: async () => {
      const files = { addon: new Map([['a.png', new File(['a'], 'a.png')]]), extract: new Map([['art/b.png', new File(['b'], 'b.png')]]) };
      const cache = new Map();
      const addonUrl = () => HA.urlFor({ source: 'addon', path: 'a.png' }, files, cache);
      const extractUrl = () => HA.urlFor({ source: 'extract', path: 'art/b.png' }, files, cache);
      const first = await addonUrl();
      A.eq(await addonUrl(), first, 'one url per file');
      const kept = await extractUrl();
      HA.dropAddon(cache);
      const again = await addonUrl();
      A.eq(/^blob:/.test(again) && again !== first, true, again);
      A.eq(await extractUrl(), kept, 'the extract keeps its url');
    },
  });

  T.push({
    name: 'a_call_before_the_first_launch_waits_for_it',
    fn: async () => {
      let answered = false;
      const early = TK.api('info', {}).then((info) => (answered = true) && info);
      await new Promise((resolve) => setTimeout(resolve, 100));
      A.eq(answered, false, 'no controller yet');
      A.eq(shown('banner'), false, 'no banner before a launch');
      const ctl = await demo();
      try {
        A.eq((await early).addon, 'SessionDemo');
      } finally {
        ctl.stop();
      }
    },
  });

  T.push({
    name: 'no_extract_shows_the_banner',
    fn: async () => {
      const ctl = await demo();
      try {
        A.eq(shown('banner'), true);
        A.eq(textOf('banner').includes('kit-only'), true, textOf('banner'));
        A.eq(shown('reimport'), false, 'no WTF folder, no Re-import');
      } finally {
        ctl.stop();
      }
    },
  });

  T.push({
    name: 'snapshot_through_the_worker_backend_has_urls',
    fn: async () => {
      const ctl = await demo();
      try {
        const snapshot = await TK.api('snapshot', {});
        const pic = assetAt(snapshot, 'pic');
        A.eq(/^blob:/.test(pic.url), true, JSON.stringify(pic));
        A.eq(pic.source, 'addon');
        A.eq(assetAt(snapshot, 'Glow').missing, true);
        A.eq(shown('missing-art'), true);
        A.eq(textOf('missing-art').startsWith('1 '), true, textOf('missing-art'));
      } finally {
        ctl.stop();
      }
    },
  });

  T.push({
    name: 'addon_urls_change_after_a_reload',
    fn: async () => {
      const addon = await demoDir();
      const ctl = await demo({ addon });
      let reloads = 0;
      TK.on('reload', () => reloads++);
      try {
        const before = assetAt(await TK.api('snapshot', {}), 'pic').url;
        A.eq(assetAt(await TK.api('snapshot', {}), 'pic').url, before, 'one url while the file stays');
        addon.edit('Art/pic.png', await halves(4, 4));
        addon.edit('Art.lua', ART + '\n-- edited');
        await until(() => reloads === 1, 'the reload');
        const after = assetAt(await TK.api('snapshot', {}), 'pic').url;
        A.eq(after !== before, true, after);
        A.eq((await pixels(after)).width, 4, 'the url serves the new file');
      } finally {
        ctl.stop();
      }
    },
  });

  T.push({
    name: 'restart_reopens_and_says_hello_again',
    fn: async () => {
      const boots = [];
      TK.on('hello', (data) => boots.push(data.boot));
      const ctl = await demo();
      try {
        A.eq(boots.length, 1, 'the open says hello');
        window.dispatchEvent(new Event('pagehide'));
        A.eq(ctl.state(), 'Stopped');
        A.eq(shown('restart'), true);
        document.getElementById('restart').click();
        await until(() => ctl.state() === 'Running', 'Running after Restart');
        A.eq(shown('restart'), false);
        A.eq(boots.length === 2 && boots[0] !== boots[1], true, JSON.stringify(boots));
      } finally {
        ctl.stop();
      }
    },
  });

  T.push({
    name: 'reimport_resets_to_the_wtf_copy',
    fn: async () => {
      const wtf = fakeDir({ SavedVariables: { 'SessionDemo.lua': 'SessionDemoDB = { runs = 40 }\n' } }, 'ACCOUNT');
      const lines = [];
      let reloads = 0;
      TK.on('console', (data) => lines.push(data.text));
      TK.on('reload', () => reloads++);
      const ctl = await demo({ wtf });
      try {
        A.eq(shown('reimport'), true);
        await TK.api('slash', { text: '/dump SessionDemoDB.runs' });
        await until(() => lines.includes('41'), 'the imported copy counted up once, saw ' + JSON.stringify(lines));
        await TK.api('slash', { text: '/run SessionDemoDB.runs = 7' });
        wtf.edit('SavedVariables/SessionDemo.lua', 'SessionDemoDB = { runs = 60 }\n'); // the game wrote it since
        document.getElementById('reimport').click();
        await until(() => reloads === 1, 'the reload of the re-import');
        await TK.api('slash', { text: '/dump SessionDemoDB.runs' });
        await until(() => lines.includes('61'), 'the new WTF copy counted up once, saw ' + JSON.stringify(lines));
      } finally {
        ctl.stop();
      }
    },
  });

  T.push({
    name: 'background_sits_under_the_stage',
    fn: async () => {
      const ctl = await demo();
      try {
        await TK.start();
        document.getElementById('zoom-fit').click();
        const background = document.getElementById('background');
        const stage = document.getElementById('stage');
        A.eq(getComputedStyle(background).backgroundColor, 'rgb(26, 26, 26)');
        A.eq(getComputedStyle(stage).backgroundColor, 'rgba(0, 0, 0, 0)', 'the stage lets the slot show through');
        const box = document.getElementById('viewport').getBoundingClientRect();
        const hits = document.elementsFromPoint(box.left + box.width / 2, box.top + box.height / 2);
        const onStage = hits.findIndex((el) => stage.contains(el));
        const names = hits.map((el) => el.id || el.className || el.tagName).join(',');
        A.eq(onStage >= 0 && onStage < hits.indexOf(background), true, names);
      } finally {
        ctl.stop();
      }
    },
  });

  // The screenshot run: SessionDemo with its art, drawn to fit, left running.
  if (new URLSearchParams(location.search).get('shot') === '1') {
    T.length = 0;
    T.push({
      name: 'shot',
      fn: async () => {
        await demo();
        await TK.start();
        document.getElementById('zoom-fit').click();
      },
    });
  }
})();
