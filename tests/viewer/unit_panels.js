// The live panels' pure parts: TK.events.parseArg and argsFor (viewer/events.js) turn typed text into fire arguments,
// TK.cmdline.History and normalize (viewer/cmdline.js) recall and check command lines, TK.console.colorOf
// (viewer/console.js) colours a line from its r, g, b.
(function () {
  'use strict';

  TK_TESTS.push({
    name: 'events.parseArg reads each payload type',
    fn() {
      const parse = TK.events.parseArg;
      A.eq(parse('12', 'number'), 12);
      A.eq(parse('true', 'boolean'), true);
      A.eq(parse('false', 'boolean'), false);
      A.eq(parse('nil', 'string'), null);
      A.eq(parse('abc', 'string'), 'abc');
      A.same(parse('{"a":1}', 'table'), { a: 1 });
      A.eq(parse('7', 'any'), 7);
      A.eq(parse('player', 'any'), 'player');
    },
  });

  TK_TESTS.push({
    name: 'events.parseArg throws on a value its type cannot hold',
    fn() {
      A.throws(() => TK.events.parseArg('x', 'number'), '^bad number: x$');
      A.throws(() => TK.events.parseArg('yes', 'boolean'), '^bad boolean: yes$');
      A.throws(() => TK.events.parseArg('{', 'table'), '^bad table: \\{$');
    },
  });

  TK_TESTS.push({
    name: 'events.argsFor sends one value per payload parameter, empty fields as null',
    fn() {
      const payload = [
        { name: 'a', type: 'number' },
        { name: 'b', type: 'string' },
        { name: 'c', type: 'boolean' },
      ];
      A.same(TK.events.argsFor(payload, ['3', '', 'true']), [3, null, true]);
    },
  });

  TK_TESTS.push({
    name: 'cmdline.History walks back from the newest and forward to an empty line',
    fn() {
      const history = new TK.cmdline.History();
      A.eq(history.up(), '');
      history.push('a');
      history.push('b');
      A.eq(history.up(), 'b');
      A.eq(history.up(), 'a');
      A.eq(history.up(), 'a');
      A.eq(history.down(), 'b');
      A.eq(history.down(), '');
      A.eq(history.down(), '');
      history.push('c');
      A.eq(history.up(), 'c');
    },
  });

  TK_TESTS.push({
    name: 'cmdline.normalize trims a slash command and refuses anything else',
    fn() {
      A.eq(TK.cmdline.normalize('  /sdemo hi '), '/sdemo hi');
      A.eq(TK.cmdline.normalize('hello'), null);
      A.eq(TK.cmdline.normalize('   '), null);
    },
  });

  TK_TESTS.push({
    name: 'console.colorOf turns r, g, b into a CSS colour, none without them',
    fn() {
      A.eq(TK.console.colorOf({ r: 1, g: 0.5, b: 0 }), 'rgb(255, 128, 0)');
      A.eq(TK.console.colorOf({ kind: 'print' }), null);
    },
  });
})();
