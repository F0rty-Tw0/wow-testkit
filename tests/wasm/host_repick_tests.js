// Host page re-pick checks: the folder whose walk failed is the one Re-pick asks for. They launch the page, so they run
// after host_page_tests.js, whose first page check needs a page that has not launched yet, and not in the screenshot run.
(function () {
  'use strict';

  const T = window.TK_TESTS;
  const { until, recorded } = window.TKH_TEST;

  if (new URLSearchParams(location.search).get('shot') === '1') return;

  T.push({
    name: 'host_failed_extract_walk_asks_to_repick_the_extract',
    fn: async () => {
      const extract = fakeDir({ art: { 'x.png': '' } });
      extract.failOn('art');
      const ctl = TK.hostPage.launch({ addon: fakeDir({ 'A.toc': 'x' }, 'A'), extract, account: 'F', spawn: recorded().spawn });
      const asked = [];
      const real = window.showDirectoryPicker;
      window.showDirectoryPicker = (opts) => {
        asked.push(opts.id);

        return Promise.reject(new DOMException('The user aborted a request.', 'AbortError'));
      };
      try {
        await until(() => ctl.state() === 'NeedsRepick', 'NeedsRepick');
        A.eq(ctl.failedKind(), 'extract');
        document.getElementById('repick').click();
        await until(() => asked.length === 1, 'the picker');
        A.same(asked, ['extract']);
      } finally {
        window.showDirectoryPicker = real;
        ctl.stop();
      }
    },
  });
})();
