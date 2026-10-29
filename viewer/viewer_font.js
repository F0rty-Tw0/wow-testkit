// FontString items and escaped text: one span per colour run, an <img> per resolved |T or |A, the addon's fonts.
(function (V) {
  'use strict';

  const FALLBACK_FAMILY = '"Friz Quadrata TT", "Segoe UI", sans-serif';
  const DEFAULT_SIZE = 12;
  const JUSTIFY_H = { LEFT: 'left', CENTER: 'center', RIGHT: 'right' };
  const JUSTIFY_V = { TOP: 'flex-start', MIDDLE: 'center', BOTTOM: 'flex-end' };
  const OUTLINE = {
    thin: '-1px 0 0 #000, 1px 0 0 #000, 0 -1px 0 #000, 0 1px 0 #000',
    thick: '-2px 0 0 #000, 2px 0 0 #000, 0 -2px 0 #000, 0 2px 0 #000',
  };

  // One load per font url until forgetFonts: a live redraw calls loadFonts again with the same assets, and a new
  // FontFace each time added duplicate faces and re-fetched a url that had already failed. url -> Promise<FontFace|null>.
  const faces = new Map();
  // Family names never repeat, so a face loaded after forgetFonts cannot share a family with one still being dropped.
  let made = 0;

  async function addFace(ref, href) {
    const face = new FontFace('wtk-font-' + made++, V.cssUrl(href));
    try {
      await face.load();
      document.fonts.add(face);

      return face;
    } catch (err) {
      console.warn('viewer: font ' + ref + ' did not load, using the fallback family', err);

      return null;
    }
  }

  async function loadFont(ref, href, families) {
    if (!faces.has(href)) faces.set(href, addFace(ref, href));
    const face = await faces.get(href);
    if (face) families.set(ref, `"${face.family}", ${FALLBACK_FAMILY}`);
  }

  // Faces forgotten but still in document.fonts: the drawn stage uses them until the next loadFonts has loaded the new.
  let retired = [];

  // A session reload can serve new font bytes at the same url (tools/preview_assets.py names files by ref): forgets
  // every face, so the next loadFonts fetches each url again and then removes the old faces from document.fonts.
  V.forgetFonts = function () {
    retired.push(...faces.values());
    faces.clear();
  };

  // A Map from font ref to CSS font-family for every font asset with a url; a font that fails to load is left out.
  V.loadFonts = async function (assets, baseUrl) {
    const families = new Map();
    const ctx = { assets, baseUrl };
    const refs = Object.keys(assets).filter((ref) => assets[ref].kind === 'font' && V.assetUrl(ctx, ref));
    await Promise.all(refs.map((ref) => loadFont(ref, V.assetUrl(ctx, ref), families)));
    const old = retired;
    retired = [];
    for (const pending of old) pending.then((face) => face && document.fonts.delete(face));

    return families;
  };

  V.fontFamily = (ctx, ref) => ctx.families.get(ref) || FALLBACK_FAMILY;

  function textRun(segment, color) {
    const span = document.createElement('span');
    span.textContent = segment.text;
    span.style.color = V.rgb(segment.color || color);

    return span;
  }

  function inlineImage(segment, ctx, size) {
    const height = segment.height || size;
    const width = segment.width || height;
    const href = V.assetUrl(ctx, segment.ref);
    const node = document.createElement(href ? 'img' : 'span');
    node.className = href ? 'inline' : 'inline placeholder';
    if (href) node.src = href;
    else node.title = V.assetLabel(ctx, segment.ref);
    node.style.width = width + 'px';
    node.style.height = height + 'px';

    return node;
  }

  // Appends text to parent: colour runs default to color; a |T or |A of height 0 takes the font size.
  V.appendText = function (parent, text, color, ctx, size) {
    for (const segment of V.parseEscapes(text)) {
      const isText = segment.kind === 'text';
      parent.append(isText ? textRun(segment, color) : inlineImage(segment, ctx, size));
    }
  };

  function outlineOf(flags) {
    if (/THICKOUTLINE/.test(flags)) return OUTLINE.thick;

    return /OUTLINE/.test(flags) ? OUTLINE.thin : null;
  }

  function textShadow(item) {
    const outline = outlineOf(String(item.flags || ''));
    const shadow = item.shadow;
    const drop = shadow && `${shadow.x || 0}px ${-(shadow.y || 0)}px 0 ${V.rgba(shadow.color || [0, 0, 0, 1])}`;

    return [outline, drop].filter(Boolean).join(', ');
  }

  V.fontString = function (node, item, ctx) {
    const size = Number(item.size) || DEFAULT_SIZE;
    const lines = document.createElement('div');
    node.style.justifyContent = JUSTIFY_V[item.justifyV] || 'center';
    node.style.fontFamily = V.fontFamily(ctx, item.font);
    node.style.fontSize = size + 'px';
    lines.className = 'lines';
    lines.style.textAlign = JUSTIFY_H[item.justifyH] || 'center';
    lines.style.lineHeight = size + (Number(item.spacing) || 0) + 'px';
    // Row V15: a rect shorter than one line still draws that line, centred on the rect like any overflow.
    lines.style.minHeight = lines.style.lineHeight;
    const unwrapped = item.wrap === false || item.autoWidth === true;
    lines.style.whiteSpace = unwrapped ? 'pre' : 'pre-wrap';
    if (item.autoWidth === true) lines.classList.add('auto');
    lines.style.textShadow = textShadow(item);
    if (item.maxLines > 0) {
      lines.classList.add('clamped');
      lines.style.webkitLineClamp = String(item.maxLines);
    }
    V.appendText(lines, String(item.text || ''), item.color || V.WHITE, ctx, size);
    node.append(lines);
  };
})((window.Viewer = window.Viewer || {}));
