// The one seam between the viewer and a session. TK.api(method, req) forwards to the current backend; server events
// arrive through TK.on(name, fn). A backend is { call(method, req) -> Promise, start(emit) }; the http backend talks to
// tools/session.py (POST /call/<method>, SSE /stream). Classic script, no DOM access.
window.TK = window.TK || {};

(function (TK) {
  'use strict';

  const handlers = {};

  TK.on = (name, fn) => {
    (handlers[name] = handlers[name] || []).push(fn);
  };

  TK.emit = (name, data) => {
    (handlers[name] || []).slice().forEach((fn) => fn(data));
  };

  const transport = (TK.transport = { current: null, EVENTS: ['hello', 'snapshot', 'console', 'reload'] });

  transport.use = (backend) => {
    transport.current = backend;
    backend.start(TK.emit);
  };

  TK.api = (method, req) => {
    if (!transport.current) return Promise.reject(new Error('no transport'));

    return transport.current.call(method, req);
  };

  transport.http = (base, deps) => {
    const dep = Object.assign(
      {
        fetch: (...args) => window.fetch(...args),
        EventSource: window.EventSource,
        stream: true,
      },
      deps,
    );

    return {
      call(method, req) {
        return dep
          .fetch(base + '/call/' + method, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(req || {}),
          })
          .then((response) => {
            if (response.status !== 200) throw new Error('HTTP ' + response.status);

            return response.json();
          });
      },

      start(emit) {
        if (!dep.stream) return;
        const source = new dep.EventSource(base + '/stream');
        transport.EVENTS.forEach((name) => {
          source.addEventListener(name, (ev) => emit(name, JSON.parse(ev.data)));
        });
      },
    };
  };
})(window.TK);
