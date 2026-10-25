// Host controller checks over the real worker (Task 5b.5): TK.host.start on a fake SessionDemo folder (FIXTURE_FILES,
// fixture_js.py). Uses the helpers host_tests.js exports on TKH_TEST.
(function () {
  'use strict';

  const T = window.TK_TESTS;
  const H = window.TK.host;
  const { sleep, until, rejects, fixtures } = window.TKH_TEST;

  let accounts = 0;
  const demoTree = (extra) => treeOf(Object.assign({}, FIXTURE_FILES.SessionDemo, extra));
  const mainWith = (text) => FIXTURE_FILES.SessionDemo['Main.lua'].replace('SetText("idle")', 'SetText("' + text + '")');
  const tocWith = (add) => FIXTURE_FILES.SessionDemo['SessionDemo.toc'] + add;
  const textOf = (snap) => snap.items.filter((item) => item.name === 'SessionDemoText')[0].text;
  const hasFrame = (snap, name) => snap.items.some((item) => item.name === name);
  const loadsOf = async (ctl) => (await ctl.api('snapshot')).session.loads;

  // Starts a controller on addon (a fakeDir of SessionDemo), waits for Running and runs fn(ctl, seen); seen collects the
  // states and console lines. Every test gets a session folder of its own: IDBFS keeps them across tests in one profile.
  async function using(addon, deps, fn) {
    const account = 'H' + ++accounts;
    const ctl = H.start(Object.assign({ addon, account, poll: { interval: 50, quiet: 300 } }, deps));
    const seen = { states: [ctl.state()], console: [] };
    ctl.onState((state) => seen.states.push(state));
    ctl.onEvent((name, data) => name === 'console' && seen.console.push(data.text));
    try {
      await until(() => ctl.state() === 'Running', 'Running, in ' + ctl.state());

      return await fn(ctl, seen);
    } finally {
      ctl.stop();
    }
  }

  T.push({
    name: 'host_reload_on_edit_after_the_quiet_window',
    fn: async () => {
      await fixtures;
      const addon = fakeDir(demoTree());
      await using(addon, {}, async (ctl, seen) => {
        const loads = await loadsOf(ctl);
        addon.edit('Main.lua', mainWith('edited'));
        await until(() => ctl.state() === 'Reloading', 'Reloading');
        const queued = ctl.api('snapshot'); // held until the reload is done
        await until(() => ctl.state() === 'Running', 'Running again');
        A.eq(textOf(await queued), 'edited');
        A.eq(await loadsOf(ctl), loads + 1);
        A.same(seen.states.slice(-2), ['Reloading', 'Running']);

        addon.edit('Main.lua', mainWith('first'));
        await sleep(100);
        addon.edit('Main.lua', mainWith('second'));
        await until(() => ctl.state() === 'Reloading', 'Reloading twice');
        await until(() => ctl.state() === 'Running', 'Running after two edits');
        await sleep(500);
        A.eq(textOf(await ctl.api('snapshot')), 'second');
        A.eq(await loadsOf(ctl), loads + 2, 'two edits 100 ms apart are one reload');
      });
    },
  });

  T.push({
    name: 'host_edit_during_a_reload_reloads_again',
    fn: async () => {
      await fixtures;
      const addon = fakeDir(demoTree());
      await using(addon, { poll: { interval: 50, quiet: 1000 } }, async (ctl) => {
        const loads = await loadsOf(ctl);
        addon.edit('Main.lua', mainWith('first') + '\nfor i = 1, 1e8 do end'); // the reload of this one takes a while
        await until(() => ctl.state() === 'Reloading', 'Reloading');
        await sleep(1300); // past the quiet window: the remount is out, and the next quiet window ends after it
        addon.edit('Main.lua', mainWith('second'));
        await until(() => ctl.state() === 'Running', 'Running again');
        A.eq(textOf(await ctl.api('snapshot')), 'second');
        A.eq(await loadsOf(ctl), loads + 2);
      });
    },
  });

  T.push({
    name: 'host_new_file_triggers_reload',
    fn: async () => {
      await fixtures;
      const addon = fakeDir(demoTree());
      await using(addon, {}, async (ctl) => {
        const loads = await loadsOf(ctl);
        addon.add('Extra.lua', 'local f = CreateFrame("Frame", "SessionDemoExtra", UIParent)\nf:SetSize(10, 10)\nf:SetPoint("CENTER")');
        addon.edit('SessionDemo.toc', tocWith('\nExtra.lua\n'));
        await until(() => ctl.state() === 'Reloading', 'Reloading');
        await until(() => ctl.state() === 'Running', 'Running again');
        A.eq(await loadsOf(ctl), loads + 1);
        A.eq(hasFrame(await ctl.api('snapshot'), 'SessionDemoExtra'), true);
      });
    },
  });

  T.push({
    name: 'host_deleted_file_reloads_instead_of_repick',
    fn: async () => {
      await fixtures;
      const addon = fakeDir(demoTree());
      await using(addon, {}, async (ctl, seen) => {
        A.eq(hasFrame(await ctl.api('snapshot'), 'SessionDemoButton'), true);
        addon.remove('Buttons.lua');
        addon.edit('SessionDemo.toc', FIXTURE_FILES.SessionDemo['SessionDemo.toc'].replace('Buttons.lua\n', ''));
        await until(() => ctl.state() === 'Reloading', 'Reloading');
        await until(() => ctl.state() === 'Running', 'Running again');
        A.eq(seen.states.includes('NeedsRepick'), false);
        A.eq(hasFrame(await ctl.api('snapshot'), 'SessionDemoButton'), false);
      });
    },
  });

  T.push({
    name: 'host_vanished_file_needs_repick',
    fn: async () => {
      await fixtures;
      const addon = fakeDir(demoTree());
      await using(addon, {}, async (ctl) => {
        addon.failOn('Main.lua');
        await until(() => ctl.state() === 'NeedsRepick', 'NeedsRepick');
        await rejects(ctl.api('snapshot'), '^re-pick folder$');
      });
    },
  });

  T.push({
    name: 'host_watchdog_stops_a_runaway_handler',
    fn: async () => {
      const loop = 'SLASH_SLOOP1 = "/sloop"\nSlashCmdList.SLOOP = function() while true do end end\n';
      await fixtures;
      const addon = fakeDir(demoTree({ 'Loop.lua': loop, 'SessionDemo.toc': tocWith('\nLoop.lua\n') }));
      await using(addon, { timers: { callMs: 1000 } }, async (ctl, seen) => {
        await ctl.api('reload'); // writes saved.lua with runs = 1 and syncs it; the live runs is 2
        await rejects(ctl.api('slash', { text: '/sloop' }), 'ran over 1 s \\(slash\\)');
        A.eq(ctl.state(), 'Stopped');
        const shown = document.getElementById('host-state').textContent;
        A.eq(shown.includes('ran over 1 s') && shown.includes('slash'), true, shown);
        await rejects(ctl.api('snapshot'), '^runtime stopped$');
        window.dispatchEvent(new PageTransitionEvent('pageshow', { persisted: true }));
        A.eq(ctl.state(), 'Stopped', 'a page restore does not restart a runaway worker');

        ctl.restart();
        await until(() => ctl.state() === 'Running', 'Running after restart');
        await ctl.api('slash', { text: '/dump SessionDemoDB.runs' });
        await until(() => seen.console.includes('2'), 'the dump, saw ' + JSON.stringify(seen.console));
      });
    },
  });

  T.push({
    name: 'host_pagehide_stops_and_a_restored_page_reopens',
    fn: async () => {
      await fixtures;
      const addon = fakeDir(demoTree());
      await using(addon, {}, async (ctl, seen) => {
        await ctl.api('slash', { text: '/run SessionDemoDB.tag = "live"' });
        window.dispatchEvent(new Event('pagehide'));
        A.eq(ctl.state(), 'Stopped');
        await rejects(ctl.api('snapshot'), '^runtime stopped$');
        await sleep(700); // the worker's shutdown and IndexedDB sync
        window.dispatchEvent(new PageTransitionEvent('pageshow', { persisted: true }));
        A.eq(ctl.state(), 'Loading');
        await until(() => ctl.state() === 'Running', 'Running after the restore');
        A.eq(textOf(await ctl.api('snapshot')), 'idle');
        await ctl.api('slash', { text: '/dump SessionDemoDB.tag' });
        await until(() => seen.console.includes('live'), 'the shutdown to have saved the variable, saw ' + JSON.stringify(seen.console));
      });
    },
  });
})();
