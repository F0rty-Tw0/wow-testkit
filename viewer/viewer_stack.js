// Stacking order of the stage. Items arrive in draw order, so each gets a z-index of its position. A frame's widget
// content (the status bar fill, the slider thumb, the edit text) sits in the frame's own node, which is ahead of the
// frame's regions, so a frame with widget content is raised to just above the last region of its own that draws below
// that content.
(function (V) {
  'use strict';

  // source: row V5, wiki Layer: the five layers, back to front.
  const LAYER_RANK = { BACKGROUND: 1, BORDER: 2, ARTWORK: 3, OVERLAY: 4, HIGHLIGHT: 5 };
  const DEFAULT_LAYER = 'ARTWORK';
  const LAYER_SPAN = 100;
  const SUBLEVEL_BIAS = 8;
  const TEXT_LEVEL = LAYER_SPAN - 1;

  // Where a part draws in its frame: by layer, then sublevel; text draws above every texture of its layer (row V6).
  function slotOf(part, isText) {
    const rank = LAYER_RANK[part.layer] || LAYER_RANK[DEFAULT_LAYER];
    const level = isText ? TEXT_LEVEL : Number(part.sublevel || 0) + SUBLEVEL_BIAS;

    return rank * LAYER_SPAN + level;
  }

  // The slot of a frame's widget content: the status bar fill and the slider thumb draw in their texture's layer, any
  // other content (text, messages) as ARTWORK text; null for a frame with none.
  function contentSlot(widget) {
    if (!widget) return null;
    const part = { StatusBar: widget.texture, Slider: widget.thumb }[widget.type];

    return part ? slotOf(part, false) : slotOf({ layer: DEFAULT_LAYER }, true);
  }

  // place(item, element, index) for each item in order; element is the item's own node, never its .clip box, which would
  // make a stacking context of its own.
  V.stacker = function () {
    const frames = new Map();

    return {
      place(item, element, index) {
        const z = 2 * index + 2;
        element.style.zIndex = String(z);
        if (item.kind === 'frame') return void frames.set(item.id, { element, slot: contentSlot(item.widget) });
        const frame = frames.get(item.parent);
        const draws = frame && frame.slot !== null && slotOf(item, item.kind === 'fontstring') <= frame.slot;
        if (draws) frame.element.style.zIndex = String(z + 1);
      },
    };
  };
})((window.Viewer = window.Viewer || {}));
