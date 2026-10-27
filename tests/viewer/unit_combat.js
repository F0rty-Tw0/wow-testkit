// The combat toolbar's pure parts (viewer/combat.js): TK.combat.parseSpeed reads the speed picker, TK.combat.formatTime
// writes the time readout and TK.combat.presetRequest builds the /call/combat preset request.
(function () {
  'use strict';

  TK_TESTS.push({
    name: 'combat.parseSpeed takes only the six speeds',
    fn() {
      A.eq(TK.combat.parseSpeed('4'), 4);
      A.eq(TK.combat.parseSpeed('0.25'), 0.25);
      A.eq(TK.combat.parseSpeed('8'), 8);
      for (const text of ['3', '0', '16', '', 'fast', '-1']) {
        A.eq(TK.combat.parseSpeed(text), null, text);
      }
    },
  });

  TK_TESTS.push({
    name: 'combat.formatTime writes m:ss.t',
    fn() {
      A.eq(TK.combat.formatTime(75.34), '1:15.3');
      A.eq(TK.combat.formatTime(0), '0:00.0');
      A.eq(TK.combat.formatTime(3), '0:03.0');
      A.eq(TK.combat.formatTime(599.99), '9:59.9');
      A.eq(TK.combat.formatTime(600), '10:00.0');
    },
  });

  TK_TESTS.push({
    name: 'combat.presetRequest sends the raid size and the picked faction, race, class and combat flag',
    fn() {
      const picks = { faction: 'Horde', race: 'Orc', className: 'MAGE', inCombat: true };
      A.same(TK.combat.presetRequest('raid:25', picks), {
        action: 'preset',
        name: 'raid',
        opts: { size: 25, faction: 'Horde', race: 'Orc', class: 'MAGE', inCombat: true },
      });
      A.same(TK.combat.presetRequest('dungeon', { faction: 'Alliance', race: '', className: '', inCombat: false }), {
        action: 'preset',
        name: 'dungeon',
        opts: { faction: 'Alliance', inCombat: false },
      });
    },
  });
})();
