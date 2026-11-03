// Vendored three bundle (viewer/vendor/three.bundle.js, tools/vendor/build_three.mjs): it sets window.THREE with the
// GLTFLoader and SkeletonUtils the scene uses.
(function () {
  'use strict';

  TK_TESTS.push({
    name: 'vendor bundle sets THREE at revision 170',
    fn() {
      A.eq(THREE.REVISION, '170');
    },
  });

  TK_TESTS.push({
    name: 'vendor bundle carries GLTFLoader and SkeletonUtils.clone',
    fn() {
      A.eq(typeof THREE.GLTFLoader, 'function');
      A.eq(typeof THREE.SkeletonUtils.clone, 'function');
    },
  });
})();
