// Texture and frame items: solid and image textures, placeholders, backdrops and widget state.
(function (V) {
  'use strict';

  const MESSAGE_SIZE = 14;

  function div(className) {
    const node = document.createElement('div');
    node.className = className;

    return node;
  }

  function placeholder(node, label) {
    const span = document.createElement('span');
    span.className = 'label';
    span.textContent = label;
    node.classList.add('placeholder');
    node.append(span);
  }

  function tinted(color, vertex) {
    if (!vertex) return color;

    return [color[0] * vertex[0], color[1] * vertex[1], color[2] * vertex[2], color[3]];
  }

  // HORIZONTAL runs min (left) to max (right); VERTICAL runs min (bottom) to max (top).
  function gradientCss(gradient) {
    const direction = gradient.orientation === 'VERTICAL' ? 'to top' : 'to right';

    return `linear-gradient(${direction}, ${V.rgba(gradient.min || V.WHITE)}, ${V.rgba(gradient.max || V.WHITE)})`;
  }

  function solid(node, item) {
    if (item.color) node.style.backgroundColor = V.rgba(tinted(item.color, item.vertexColor));
    if (!item.gradient) return;
    node.style.backgroundImage = gradientCss(item.gradient);
    node.style.backgroundBlendMode = 'multiply';
  }

  // texCoord as left, right, top, bottom (4 numbers) or the corners UL, LL, UR, LR (8); the corner form keeps only its
  // bounding box. A reversed axis mirrors the image.
  function cropOf(item) {
    const coords = item.texCoord;
    const known = Array.isArray(coords) && (coords.length === 4 || coords.length === 8);
    if (!known) return null;
    const corners = coords.length === 4 ? [coords[0], coords[2], coords[0], coords[3], coords[1]] : coords;
    const [left, top, , bottom, right] = corners.map(Number);
    const imageWidth = item.rect.width / Math.max(Math.abs(right - left), 1e-6);
    const imageHeight = item.rect.height / Math.max(Math.abs(bottom - top), 1e-6);
    const x = -Math.min(left, right) * imageWidth;
    const y = -Math.min(top, bottom) * imageHeight;

    return { size: `${imageWidth}px ${imageHeight}px`, position: `${x}px ${y}px`, flipX: right < left, flipY: bottom < top };
  }

  function tiling(item) {
    if (item.horizTile && item.vertTile) return 'repeat';
    if (item.horizTile) return 'repeat-x';

    return item.vertTile ? 'repeat-y' : null;
  }

  // The image layer, a gradient layer under it, vertexColor as the background colour; any tint multiplies and a mask
  // of the same image keeps the tint inside the image's alpha.
  function image(node, item, href) {
    const crop = cropOf(item);
    const repeat = tiling(item);
    const layer = { image: V.cssUrl(href), size: '100% 100%', position: '0px 0px', repeat: repeat || 'no-repeat' };
    if (crop) Object.assign(layer, { size: crop.size, position: crop.position });
    else if (repeat) layer.size = 'auto';
    const gradient = item.gradient && gradientCss(item.gradient);
    const isTinted = Boolean(item.vertexColor || gradient);
    node.style.backgroundImage = gradient ? `${layer.image}, ${gradient}` : layer.image;
    node.style.backgroundSize = gradient ? `${layer.size}, 100% 100%` : layer.size;
    node.style.backgroundPosition = gradient ? `${layer.position}, 0px 0px` : layer.position;
    node.style.backgroundRepeat = gradient ? `${layer.repeat}, no-repeat` : layer.repeat;
    if (item.vertexColor) node.style.backgroundColor = V.rgb(item.vertexColor);
    if (isTinted) {
      node.style.backgroundBlendMode = 'multiply';
      Object.assign(node.style, { maskImage: layer.image, maskSize: layer.size, maskPosition: layer.position, maskRepeat: layer.repeat });
    }
    if (crop && (crop.flipX || crop.flipY)) node.style.transform = `scale(${crop.flipX ? -1 : 1}, ${crop.flipY ? -1 : 1})`;
  }

  // WoW's SetRotation turns counter-clockwise; CSS rotate turns clockwise.
  function effects(node, item) {
    if (item.blendMode === 'ADD') node.style.mixBlendMode = 'plus-lighter';
    if (item.desaturated) node.style.filter = 'grayscale(1)';
    if (item.rotation) node.style.transform = `${node.style.transform} rotate(${-item.rotation}rad)`.trim();
  }

  V.texture = function (node, item, ctx) {
    const ref = item.atlas || item.file;
    const href = ref && V.assetUrl(ctx, ref);
    if (ref && !href) return placeholder(node, V.assetLabel(ctx, ref));
    if (href) image(node, item, href);
    else solid(node, item);
    effects(node, item);
  };

  // The center piece draws the colour as the fill and bgFile over it; the edge piece draws the border from borderColor and
  // edgeSize. Insets and the edge art are not drawn.
  V.backdrop = function (node, item, ctx) {
    const info = item.backdrop;
    if (item.piece === 'edge') {
      if (info.edgeFile) node.style.border = `${Number(info.edgeSize) || 1}px solid ${V.rgba(info.borderColor || V.WHITE)}`;

      return;
    }
    const href = info.bgFile && V.assetUrl(ctx, info.bgFile);
    const tileSize = Number(info.tileSize) > 0 ? `${info.tileSize}px` : 'auto';
    if (info.color) node.style.backgroundColor = V.rgba(info.color);
    if (href) {
      node.style.backgroundImage = V.cssUrl(href);
      node.style.backgroundBlendMode = 'multiply';
      node.style.backgroundRepeat = info.tile ? 'repeat' : 'no-repeat';
      node.style.backgroundSize = info.tile ? tileSize : '100% 100%';
    }
  };

  function fraction(widget) {
    const span = Number(widget.max) - Number(widget.min);
    const value = (Number(widget.value) - Number(widget.min)) / span;

    return span > 0 && Number.isFinite(value) ? Math.min(1, Math.max(0, value)) : 0;
  }

  // The fill's box inside its bar. A Standard fill grows from the left (bottom when vertical) and from the opposite edge
  // when reversed or the Reverse fill style; a Center fill grows from the middle, as long as the fraction.
  V.fillRect = function (widget) {
    const part = fraction(widget) * 100;
    const style = String(widget.fillStyle || 'STANDARD').toUpperCase();
    const reversed = Boolean(widget.reverse) || style === 'REVERSE';
    const vertical = widget.orientation === 'VERTICAL';
    const box = vertical
      ? { left: '0px', right: 'auto', top: 'auto', bottom: 'auto', width: '100%', height: part + '%' }
      : { top: '0px', bottom: 'auto', left: 'auto', right: 'auto', width: part + '%', height: '100%' };
    const near = vertical ? 'bottom' : 'left';
    const far = vertical ? 'top' : 'right';
    if (style === 'CENTER') box[vertical ? 'top' : 'left'] = (100 - part) / 2 + '%';
    else box[reversed ? far : near] = '0px';

    return box;
  };

  // The bar colour is the vertex colour of the bar texture, so it multiplies the texture's own: a white colour texture
  // under a green bar colour is green. null when the product is white, which tints nothing.
  function barTint(widget) {
    const bar = widget.color || V.WHITE;
    const own = widget.texture.vertexColor || V.WHITE;
    const tint = [own[0] * bar[0], own[1] * bar[1], own[2] * bar[2]];

    return tint.every((channel) => channel === 1) ? null : tint;
  }

  // The bar texture is the fill; a bar without one fills with the bar colour.
  function statusBar(node, widget, ctx, item) {
    const fill = div('fill');
    const alpha = widget.color ? Number(widget.color[3] ?? 1) : 1;
    const texture = widget.texture && Object.assign({ rect: { width: item.rect.width, height: item.rect.height } }, widget.texture);
    Object.assign(fill.style, V.fillRect(widget));
    if (alpha < 1) fill.style.opacity = String(alpha);
    if (!texture) fill.style.backgroundColor = V.rgba(widget.color || V.WHITE);
    else V.texture(fill, Object.assign(texture, { vertexColor: barTint(widget) || texture.vertexColor }));
    node.append(fill);
  }

  // The selected characters as [from, to) in 0-based positions, clamped to the text; null when nothing is selected.
  V.selectionRange = function (widget, length) {
    const range = widget.selection;
    if (!range) return null;
    const from = Math.min(length, Math.max(0, Number(range.from) || 0));
    const to = Math.min(length, Math.max(from, Number(range.to) || 0));

    return to > from ? [from, to] : null;
  }

  // Appends value[from, to) to parent, with the caret where the cursor falls in it the first time; returns whether it did.
  function appendSlice(parent, value, from, to, caretAt) {
    const placed = caretAt !== null && caretAt >= from && caretAt <= to;
    if (!placed) {
      parent.append(document.createTextNode(value.slice(from, to)));

      return false;
    }
    parent.append(document.createTextNode(value.slice(from, caretAt)), div('caret'), document.createTextNode(value.slice(caretAt, to)));

    return true;
  }

  // The text split around the selection, which is one .selection span; the caret goes in the first piece that holds it.
  function editBox(node, widget) {
    const text = div('text');
    const value = String(widget.text || '');
    const cursor = Math.min(value.length, Math.max(0, Number(widget.cursor) || 0));
    const range = V.selectionRange(widget, value.length) || [value.length, value.length];
    const selection = document.createElement('span');
    let caretAt = widget.focused ? cursor : null;
    selection.className = 'selection';
    text.style.whiteSpace = widget.multiLine ? 'pre-wrap' : 'pre';
    const pieces = [[text, 0, range[0]], [selection, range[0], range[1]], [text, range[1], value.length]];
    for (const [parent, from, to] of pieces) {
      if (parent === selection && from === to) continue;
      if (appendSlice(parent, value, from, to, caretAt)) caretAt = null;
      if (parent === selection) text.append(selection);
    }
    node.append(text);
  }

  // A checked box with no art of its own gets a stand-in check mark.
  function checkButton(node, widget) {
    if (widget.checked && !widget.checkedTexture) node.append(div('check'));
  }

  // The thumb's box: centred on the value fraction along the track (a vertical slider's minimum is at the top), and, when
  // the thumb texture has a size, that size centred across it.
  V.thumbRect = function (widget) {
    const at = fraction(widget) * 100 + '%';
    const horizontal = widget.orientation === 'HORIZONTAL';
    const size = widget.thumb || {};
    const box = horizontal ? { left: at } : { top: at };
    if (size.width > 0 && size.height > 0) {
      Object.assign(box, horizontal ? { top: '50%' } : { left: '50%' }, { width: `${size.width}px`, height: `${size.height}px` });
      box.transform = 'translate(-50%, -50%)';
    }

    return box;
  };

  function slider(node, widget, ctx) {
    const thumb = div('thumb');
    thumb.classList.add(widget.orientation === 'HORIZONTAL' ? 'horizontal' : 'vertical');
    Object.assign(thumb.style, V.thumbRect(widget));
    if (widget.thumb) V.texture(thumb, Object.assign({ rect: { width: widget.thumb.width, height: widget.thumb.height } }, widget.thumb), ctx);
    node.append(thumb);
  }

  function messageFrame(node, widget, ctx) {
    const box = div('messages');
    for (const message of Array.isArray(widget.lines) ? widget.lines : []) {
      const line = div('line');
      const color = [message.r ?? 1, message.g ?? 1, message.b ?? 1, 1];
      V.appendText(line, String(message.text || ''), color, ctx, MESSAGE_SIZE);
      box.append(line);
    }
    node.append(box);
  }

  const WIDGETS = { StatusBar: statusBar, EditBox: editBox, CheckButton: checkButton, Slider: slider, ScrollingMessageFrame: messageFrame };

  V.frame = function (node, item, ctx) {
    const build = item.widget && WIDGETS[item.widget.type];
    if (build) build(node, item.widget, ctx, item);
  };
})((window.Viewer = window.Viewer || {}));
