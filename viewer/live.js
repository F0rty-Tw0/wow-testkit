// Live mode: index.html?live=1[&stream=0]. TK.start() installs the http transport unless a host page installed its
// own first, draws the session snapshot with render(), draws it again on each snapshot event, and sends stage mouse
// input and key presses to the session (pointer.js, keys.js). #hover outlines the frame the last input reply named.
// stream=0 turns the event stream off. <html data-ready="1"> is set once the first snapshot is drawn or has failed.
// The input handlers attach on the first snapshot drawn, so a session that was down at start gets them once it
// answers. Each stream open says hello with the server's boot id; a boot unlike the last one seen is a restarted
// server, which numbers its snapshots and console lines from the start again: TK.state.seq resets, 'restart' is
// emitted (console.js and inspector.js reload) and the snapshot is drawn afresh.
window.TK = window.TK || {};

(function (TK) {
  'use strict';

  const live = (TK.live = {});
  const last = { req: null, reply: null };
  const fetching = { busy: false, again: false };
  const attached = { input: false };
  TK.state = { snapshot: null, seq: -1, boot: null };

  // The rect of the frame a reply's target names, or null (a leave, empty space, or an item not drawn).
  live.hoverRect = (snapshot, req, reply) => {
    const id = req.kind !== 'leave' && reply && reply.target && reply.target.id;
    if (!id) return null;
    const item = (snapshot.items || []).find((it) => it.id === id);

    return item && item.rect ? item.rect : null;
  };

  // True when the snapshot has an EditBox with the keyboard focus.
  live.hasEditFocus = (snapshot) => ((snapshot && snapshot.items) || []).some((it) => it.widget && it.widget.focused);

  function showStatus(messages) {
    window.Viewer.showMessages('status', messages);
  }

  function placeHover() {
    const node = document.getElementById('hover');
    const snapshot = TK.state.snapshot;
    const rect = snapshot && last.req ? live.hoverRect(snapshot, last.req, last.reply) : null;
    node.hidden = !rect;
    if (!rect) return;
    const scale = document.getElementById('stage').getBoundingClientRect().width / snapshot.screen.width;
    node.style.left = rect.x * scale + 'px';
    node.style.top = rect.y * scale + 'px';
    node.style.width = rect.width * scale + 'px';
    node.style.height = rect.height * scale + 'px';
  }

  // Handles a stream hello { boot }. Returns true when the boot differs from the last one seen, after resetting
  // TK.state.seq and emitting 'restart'; the first hello only records the boot.
  live.hello = (data) => {
    const boot = data && data.boot;
    const restarted = TK.state.boot !== null && boot !== TK.state.boot;
    TK.state.boot = boot;
    if (!restarted) return false;
    TK.state.seq = -1;
    TK.emit('restart', { boot });

    return true;
  };

  TK.on('hello', live.hello);

  async function drawOnce() {
    const snapshot = await TK.api('snapshot', {});
    await window.render(snapshot, location.origin + '/');
    TK.state.snapshot = snapshot;
    TK.state.seq = snapshot.session ? snapshot.session.seq : TK.state.seq;
    placeHover();
    attachInput();
  }

  // Draws the current snapshot; a call while one is drawing makes that one draw again afterwards.
  async function refresh() {
    if (fetching.busy) {
      fetching.again = true;

      return;
    }
    fetching.busy = true;
    try {
      do {
        fetching.again = false;
        await drawOnce();
      } while (fetching.again);
      showStatus([]);
    } catch (err) {
      showStatus(['Could not show the session: ' + err.message]);
    } finally {
      fetching.busy = false;
    }
  }

  function post(req) {
    const remember = (reply) => {
      Object.assign(last, { req, reply });
      placeHover();

      return reply;
    };

    return TK.api('input', req)
      .then(remember)
      .catch((err) => showStatus(['Input failed: ' + err.message]));
  }

  function attachPointer() {
    const stage = document.getElementById('stage');
    TK.pointer.attach(stage, {
      post,
      rect: () => stage.getBoundingClientRect(),
      screen: () => TK.state.snapshot.screen,
      now: () => performance.now(),
    });
  }

  function attachKeys() {
    TK.keys.attach(document, { post, focused: () => live.hasEditFocus(TK.state.snapshot) });
  }

  function attachInput() {
    if (attached.input) return;
    attached.input = true;
    attachPointer();
    attachKeys();
  }

  TK.start = async () => {
    const stream = new URLSearchParams(location.search).get('stream') !== '0';
    if (!TK.transport.current) TK.transport.use(TK.transport.http(location.origin, { stream }));
    // Before refresh below: a reloaded or restarted session may serve new font bytes at an old url.
    TK.on('reload', window.Viewer.forgetFonts);
    TK.on('restart', window.Viewer.forgetFonts);
    TK.on('snapshot', (data) => {
      const newer = !data || data.seq > TK.state.seq;
      if (newer) refresh();
    });
    TK.on('restart', refresh);
    TK.on('hello', () => {
      if (!TK.state.snapshot) refresh();
    });
    await refresh();
    document.documentElement.dataset.ready = '1';
  };

  const isLive = new URLSearchParams(location.search).get('live') === '1';
  if (isLive) document.addEventListener('DOMContentLoaded', () => TK.start());
})(window.TK);
