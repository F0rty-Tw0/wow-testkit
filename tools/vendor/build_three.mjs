// Bundles three (+ GLTFLoader, SkeletonUtils) into one classic script that sets window.THREE.
//
//   node tools/vendor/build_three.mjs <nodeModulesParent> <out.js>
//
// <nodeModulesParent> holds node_modules/{three,esbuild}; esbuild and three resolve from there. Output: an IIFE, so
// THREE.REVISION, THREE.GLTFLoader and THREE.SkeletonUtils.clone exist after one <script> tag.
import { createRequire } from 'node:module';
import path from 'node:path';

const ENTRY = `
export * from 'three';
export { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
export * as SkeletonUtils from 'three/examples/jsm/utils/SkeletonUtils.js';
`;

async function build(parent, outfile) {
  const require = createRequire(path.join(parent, 'package.json'));
  const esbuild = require('esbuild');
  const result = await esbuild.build({
    stdin: { contents: ENTRY, resolveDir: parent, loader: 'js' },
    bundle: true,
    format: 'iife',
    globalName: 'THREE',
    // No identifier mangling: check_vendor.py greps the bundle for REVISION="170".
    minifyWhitespace: true,
    minifySyntax: true,
    legalComments: 'none',
    outfile,
  });

  return result.errors.length;
}

const [parent, outfile] = process.argv.slice(2);
if (!parent || !outfile) {
  console.error('usage: node build_three.mjs <nodeModulesParent> <out.js>');
  process.exit(2);
}
process.exit((await build(path.resolve(parent), path.resolve(outfile))) ? 1 : 0);
