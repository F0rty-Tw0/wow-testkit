// Snapshot text and asset helpers. refPath/refId/refAtlas mirror the ref keys of render_assets.lua; parseEscapes splits
// the UI escape sequences of a FontString text into colour runs and inline textures.
(function (V) {
  'use strict';

  // |cAARRGGBB, |r, |n, ||, |T...|t, |A:...|a, |4singular:plural; and the |H...|h hyperlink wrappers (dropped, their
  // text kept).
  const ESCAPE = /\|\||\|c([0-9a-fA-F]{8})|\|r|\|n|\|T([^|]*)\|t|\|A:([^|]*)\|a|\|4([^;|]*);|\|H[^|]*\|h|\|h/g;
  const WHITE = [1, 1, 1, 1];

  // Lua's string.lower only folds ASCII.
  function asciiLower(text) {
    return text.replace(/[A-Z]/g, (letter) => letter.toLowerCase());
  }

  function slashed(path) {
    return path.replace(/\\/g, '/');
  }

  V.refPath = (path) => 'path:' + asciiLower(slashed(path));
  V.refId = (n) => 'id:' + String(n);
  V.refAtlas = (atlas) => 'atlas:' + asciiLower(atlas);

  function hexColor(hex) {
    const byte = (at) => parseInt(hex.slice(at, at + 2), 16) / 255;

    return [byte(2), byte(4), byte(6), 1];
  }

  // A numeric |T target is a fileID (render_fields.lua addEscapes: tonumber(target) or target).
  function inlineRef(kind, target) {
    if (kind === 'atlas') return V.refAtlas(target);
    const isFileId = /^\d+$/.test(target);

    return isFileId ? V.refId(Number(target)) : V.refPath(target);
  }

  // "path:height:width:..." of |T, or "atlas:height:width:..." of |A; width 0 or absent means the height.
  function inline(kind, spec) {
    const [target, height, width] = spec.split(':');
    const ref = inlineRef(kind, target);

    return { kind, ref, height: Number(height) || 0, width: Number(width) || 0 };
  }

  function isDigit(text, at) {
    const char = text[at];

    return char >= '0' && char <= '9';
  }

  // The last run of digits in line as a number, or null. A backwards scan: /(\d+)\D*$/ backtracks over every start of
  // a long digit run, quadratic in its length (ui/measure.lua lastNumber scans the same way).
  function lastNumber(line) {
    let stop = line.length;
    while (stop > 0 && !isDigit(line, stop - 1)) stop -= 1;
    let start = stop;
    while (start > 0 && isDigit(line, start - 1)) start -= 1;
    if (start === stop) return null;
    const digits = line.slice(start, stop);

    return Number(digits);
  }

  // Row V14, as ui/measure.lua pluralForm: the last number shown ahead of the escape on its line picks the singular
  // when it is 1, else (or with no number) the plural.
  function pluralForm(forms, before) {
    const [singular, plural = ''] = forms.split(':');
    const line = before.slice(before.lastIndexOf('\n') + 1);
    const isOne = lastNumber(line) === 1;

    return isOne ? singular : plural;
  }

  // Segments of text: { kind: 'text', text, color } (color null for the item's colour), { kind: 'texture' | 'atlas',
  // ref, height, width }. Adjacent text of one colour is one segment; |n becomes "\n"; |4 becomes
  // the form it picks.
  V.parseEscapes = function (text) {
    const segments = [];
    const colors = [];
    let shown = '';
    const pushText = (chunk) => {
      if (chunk === '') return;
      shown += chunk;
      const color = colors.length > 0 ? colors[colors.length - 1] : null;
      const last = segments[segments.length - 1];
      if (last && last.kind === 'text' && last.color === color) last.text += chunk;
      else segments.push({ kind: 'text', text: chunk, color });
    };
    let at = 0;
    for (const match of text.matchAll(ESCAPE)) {
      pushText(text.slice(at, match.index));
      at = match.index + match[0].length;
      const token = match[0];
      if (token === '||') pushText('|');
      else if (token === '|n') pushText('\n');
      else if (token === '|r') colors.pop();
      else if (match[1]) colors.push(hexColor(match[1]));
      else if (match[2] !== undefined) segments.push(inline('texture', match[2]));
      else if (match[3] !== undefined) segments.push(inline('atlas', match[3]));
      else if (match[4] !== undefined) pushText(pluralForm(match[4], shown));
    }
    pushText(text.slice(at));

    return segments;
  };

  function channel(color, i) {
    const value = color[i] === null ? NaN : Number(color[i]);
    const clamped = Math.min(1, Math.max(0, Number.isFinite(value) ? value : 1));

    return Math.round(clamped * 255);
  }

  // CSS colours from a snapshot { r, g, b, a } list; a missing or bad channel reads as 1.
  V.rgb = (color) => `rgb(${channel(color, 0)}, ${channel(color, 1)}, ${channel(color, 2)})`;

  V.rgba = function (color) {
    const alpha = Math.min(1, Math.max(0, Number(color[3] ?? 1)));

    return `rgba(${channel(color, 0)}, ${channel(color, 1)}, ${channel(color, 2)}, ${alpha})`;
  };

  V.cssUrl = (href) => 'url("' + href.replace(/["\\]/g, (c) => '\\' + c) + '")';

  V.WHITE = WHITE;

  // The absolute url of a resolved asset, or null for a placeholder, a missing asset or one without a url.
  V.assetUrl = function (ctx, ref) {
    const asset = ctx.assets[ref];
    const resolved = asset && asset.source !== 'placeholder' && typeof asset.url === 'string';

    return resolved ? new URL(asset.url, ctx.baseUrl).href : null;
  };

  V.assetLabel = function (ctx, ref) {
    const asset = ctx.assets[ref];

    return (asset && asset.label) || ref;
  };
})((window.Viewer = window.Viewer || {}));
