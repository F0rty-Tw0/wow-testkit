// Tests for viewer/transport.js with a fake fetch and a fake EventSource.
(function () {
  'use strict';

  const T = window.TK_TESTS;

  function fakeFetch(reply) {
    const calls = [];
    const fetch = (url, init) => {
      calls.push({ url, init });
      if (reply instanceof Error) return Promise.reject(reply);

      return Promise.resolve({ status: reply.status, json: () => Promise.resolve(reply.json) });
    };

    return { fetch, calls };
  }

  function fakeEventSource() {
    const made = [];
    function EventSource(url) {
      this.url = url;
      this.listeners = {};
      made.push(this);
    }
    EventSource.prototype.addEventListener = function (name, fn) {
      this.listeners[name] = fn;
    };
    EventSource.prototype.fire = function (name, data) {
      this.listeners[name]({ data });
    };

    return { EventSource, made };
  }

  function rejection(promise) {
    return promise.then(
      () => {
        throw new Error('resolved, want rejection');
      },
      (err) => err.message,
    );
  }

  T.push({
    name: 'transport_http_posts_to_call',
    fn: async () => {
      const { fetch, calls } = fakeFetch({ status: 200, json: { ok: true, n: 1 } });
      const backend = TK.transport.http('http://127.0.0.1:9', { fetch, EventSource: null, stream: false });
      const reply = await backend.call('slash', { text: '/x' });
      A.eq(calls.length, 1);
      A.eq(calls[0].url, 'http://127.0.0.1:9/call/slash');
      A.eq(calls[0].init.method, 'POST');
      A.eq(calls[0].init.headers['Content-Type'], 'application/json');
      A.eq(calls[0].init.body, '{"text":"/x"}');
      A.same(reply, { ok: true, n: 1 });
    },
  });

  T.push({
    name: 'transport_http_missing_request_sends_an_empty_object',
    fn: async () => {
      const { fetch, calls } = fakeFetch({ status: 200, json: {} });
      await TK.transport.http('http://h', { fetch, stream: false }).call('snapshot');
      A.eq(calls[0].init.body, '{}');
    },
  });

  T.push({
    name: 'transport_http_rejects_non_200',
    fn: async () => {
      const denied = fakeFetch({ status: 403, json: {} });
      const backend = TK.transport.http('http://h', { fetch: denied.fetch, stream: false });
      A.eq(await rejection(backend.call('info')), 'HTTP 403');
      const down = fakeFetch(new Error('network down'));
      A.eq(await rejection(TK.transport.http('http://h', { fetch: down.fetch, stream: false }).call('info')), 'network down');
    },
  });

  T.push({
    name: 'transport_http_stream_events_reach_emit',
    fn: () => {
      const { fetch } = fakeFetch({ status: 200, json: {} });
      const es = fakeEventSource();
      const seen = [];
      TK.transport.http('http://h', { fetch, EventSource: es.EventSource, stream: true }).start((name, data) => seen.push([name, data]));
      A.eq(es.made.length, 1);
      A.eq(es.made[0].url, 'http://h/stream');
      es.made[0].fire('console', '{"text":"hi"}');
      A.same(seen, [['console', { text: 'hi' }]]);
      A.same(TK.transport.EVENTS, ['snapshot', 'console', 'reload']);
      A.same(Object.keys(es.made[0].listeners).sort(), ['console', 'reload', 'snapshot']);
      const quiet = fakeEventSource();
      TK.transport.http('http://h', { fetch, EventSource: quiet.EventSource, stream: false }).start(() => {});
      A.eq(quiet.made.length, 0);
    },
  });

  T.push({
    name: 'transport_api_uses_the_current_backend',
    fn: async () => {
      A.eq(await rejection(TK.api('x')), 'no transport');
      let started = null;
      const backend = { call: (m, r) => Promise.resolve({ m, r }), start: (emit) => (started = emit) };
      TK.transport.use(backend);
      A.eq(TK.transport.current, backend);
      A.eq(started, TK.emit);
      A.same(await TK.api('info', { a: 1 }), { m: 'info', r: { a: 1 } });
      const got = [];
      TK.on('snapshot', (data) => got.push(data));
      TK.emit('snapshot', { seq: 3 });
      A.same(got, [{ seq: 3 }]);
    },
  });
})();
