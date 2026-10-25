// The browser host's art (browser host spec 5.7): turns the located of each snapshot asset (where Lua's Assets.locate
// found the file) into a blob url of the walked File, cutting an atlas crop from its sheet on a canvas, and marks the
// rest as the viewer's stand-ins, as tools/session_host.py does for the Python host. Classic script on the global TK.
window.TK = window.TK || {};

(function (TK) {
  'use strict';

  // Chrome decodes neither, and addons ship both.
  const UNDECODED = /\.(tga|blp)$/i;

  // Python's round(): a half goes to the even neighbour (tools/client/atlas.py crops with it).
  function roundHalfEven(x) {
    const half = Math.abs(x % 1) === 0.5;

    return half ? 2 * Math.round(x / 2) : Math.round(x);
  }

  // The pixel rect of a crop in texture coordinates (0-1) on a w x h sheet.
  function cropRect(crop, w, h) {
    const sx = roundHalfEven(crop.left * w);
    const sy = roundHalfEven(crop.top * h);
    const rect = { sx, sy, sw: roundHalfEven(crop.right * w) - sx, sh: roundHalfEven(crop.bottom * h) - sy };

    return rect;
  }

  // The stand-in label of an asset, as preview_assets.label_of.
  function labelOf(asset) {
    if (asset.kind === 'fileID') return '#' + asset.fileID;
    if (asset.kind === 'atlas') return String(asset.atlas);
    const path = String(asset.path ?? '').replace(/\\/g, '/');

    return path.split('/').pop().toLowerCase();
  }

  // The crop of a sheet as a PNG blob url, or null when the sheet does not decode or the crop is empty.
  async function cut(file, crop) {
    try {
      const sheet = await createImageBitmap(file);
      const { sx, sy, sw, sh } = cropRect(crop, sheet.width, sheet.height);
      const canvas = new OffscreenCanvas(sw, sh);
      canvas.getContext('2d').drawImage(sheet, sx, sy, sw, sh, 0, 0, sw, sh);
      const png = await canvas.convertToBlob({ type: 'image/png' });

      return URL.createObjectURL(png);
    } catch (err) {
      return null;
    }
  }

  // A promise of the blob url of one located file (files = { addon, extract }: Maps of path -> File), or of null when
  // there is no such File or it is a .tga or .blp. cache maps source/path, plus the crop, to that promise.
  function urlFor(located, files, cache) {
    const file = files[located.source] && files[located.source].get(located.path);
    const undecoded = UNDECODED.test(located.path);
    if (!file || undecoded) return Promise.resolve(null);
    const crop = located.crop;
    const cropKey = crop ? '#' + [crop.left, crop.right, crop.top, crop.bottom].join(',') : '';
    const key = located.source + '/' + located.path + cropKey;
    const cached = cache.has(key);
    if (!cached) cache.set(key, crop ? cut(file, crop) : Promise.resolve(URL.createObjectURL(file)));

    return cache.get(key);
  }

  // Forgets (and revokes) the addon's urls: a remount walks new Files.
  function dropAddon(cache) {
    const keys = [...cache.keys()].filter((key) => key.startsWith('addon/'));
    for (const key of keys) {
      cache.get(key).then((url) => url && URL.revokeObjectURL(url));
      cache.delete(key);
    }
  }

  // Gives every asset of a snapshot, in place, what session_host.py's resolve_located gives it: a hit gets url and its
  // located source; a font miss is a stand-in; any other miss is a placeholder with missing and label. located goes.
  // Returns the number of placeholders.
  async function resolve(snapshot, files, cache) {
    const assets = Object.values(snapshot.assets || {});
    const urls = await Promise.all(assets.map((asset) => (asset.located ? urlFor(asset.located, files, cache) : null)));
    let misses = 0;
    assets.forEach((asset, index) => {
      const source = asset.located && asset.located.source;
      delete asset.located;
      if (urls[index]) Object.assign(asset, { source, url: urls[index] });
      else if (asset.kind === 'font') asset.source = 'standin';
      else {
        misses++;
        Object.assign(asset, { source: 'placeholder', missing: true, label: labelOf(asset) });
      }
    });

    return misses;
  }

  TK.hostAssets = { cropRect, labelOf, urlFor, dropAddon, resolve };
})(window.TK);
