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

  // Colour as the fill, bgFile over it, the border from borderColor and edgeSize. Insets and the edge art are not drawn.
  function backdrop(info, ctx) {
    const node = div('backdrop');
    const href = info.bgFile && V.assetUrl(ctx, info.bgFile);
    const tileSize = Number(info.tileSize) > 0 ? `${info.tileSize}px` : 'auto';
    if (info.color) node.style.backgroundColor = V.rgba(info.color);
    if (href) {
      node.style.backgroundImage = V.cssUrl(href);
      node.style.backgroundBlendMode = 'multiply';
      node.style.backgroundRepeat = info.tile ? 'repeat' : 'no-repeat';
      node.style.backgroundSize = info.tile ? tileSize : '100% 100%';
    }
    if (info.edgeFile || info.borderColor) node.style.border = `${Number(info.edgeSize) || 1}px solid ${V.rgba(info.borderColor || V.WHITE)}`;

    return node;
  }

  function fraction(widget) {
    const span = Number(widget.max) - Number(widget.min);
    const value = (Number(widget.value) - Number(widget.min)) / span;

    return span > 0 && Number.isFinite(value) ? Math.min(1, Math.max(0, value)) : 0;
  }

  function statusBar(node, widget) {
    const fill = div('fill');
    const percent = fraction(widget) * 100 + '%';
    fill.style.backgroundColor = V.rgba(widget.color || V.WHITE);
    if (widget.orientation === 'VERTICAL') Object.assign(fill.style, { top: 'auto', bottom: '0px', width: '100%', height: percent });
    else fill.style.width = percent;
    node.append(fill);
  }

  function editBox(node, widget) {
    const text = div('text');
    const value = String(widget.text || '');
    const cursor = Math.min(value.length, Math.max(0, Number(widget.cursor) || 0));
    text.style.whiteSpace = widget.multiLine ? 'pre-wrap' : 'pre';
    text.append(document.createTextNode(value.slice(0, cursor)));
    if (widget.focused) text.append(div('caret'));
    text.append(document.createTextNode(value.slice(cursor)));
    node.append(text);
  }

  function checkButton(node, widget) {
    if (widget.checked) node.append(div('check'));
  }

  // A vertical slider's minimum is at the top.
  function slider(node, widget) {
    const thumb = div('thumb');
    const at = fraction(widget) * 100 + '%';
    thumb.classList.add(widget.orientation === 'HORIZONTAL' ? 'horizontal' : 'vertical');
    if (widget.orientation === 'HORIZONTAL') thumb.style.left = at;
    else thumb.style.top = at;
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
    if (item.backdrop) node.append(backdrop(item.backdrop, ctx));
    if (build) build(node, item.widget, ctx);
  };
})((window.Viewer = window.Viewer || {}));
