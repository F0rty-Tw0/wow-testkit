// Marks drawn with a sim actor: a ground ring under the target in the reaction colour (TK.scene3dMarks.RING), a
// pulsing white ring plus a small emissive lift on the hovered model, and a gold sparkle over a lootable corpse.
// flags(raw) reads them off a world entry; make(T) returns { group, apply(raw, t, body) } where t is seconds for the
// pulse and body the Object3D to lift. Reaction never tints the model. Classic script; tests/viewer/unit_sim_models.js.
window.TK = window.TK || {};

(function (TK) {
  'use strict';

  const RING = { hostile: 0xd24a3a, friendly: 0x3fae6b };
  const HOVER = 0xffffff;
  const GOLD = 0xffd24a;
  const SPARKS = 16;
  const LIFT = 0.06;
  const GROUND = 0.04;

  function flags(raw) {
    const ring = raw.hostile ? RING.hostile : RING.friendly;
    const sparkle = !!(raw.dead && raw.lootable);

    return { target: !!raw.isTarget, hover: !!raw.isMouseover, sparkle, ring };
  }

  function ring(T, inner, outer, color) {
    const geometry = new T.RingGeometry(inner, outer, 40).rotateX(-Math.PI / 2);
    const material = new T.MeshBasicMaterial({ color, transparent: true, opacity: 0.85, depthWrite: false });
    const out = new T.Mesh(geometry, material);
    out.position.y = GROUND;
    out.renderOrder = 1;

    return out;
  }

  // A fixed cloud of points over the corpse (sine hash, so every corpse sparkles alike).
  function sparkle(T) {
    const spots = [];
    for (let i = 0; i < SPARKS; i++) {
      const angle = i * 2.4;
      const reach = 0.2 + 0.4 * Math.abs(Math.sin(i * 12.9898));
      spots.push(Math.cos(angle) * reach, 0.3 + 0.9 * Math.abs(Math.sin(i * 78.233)), Math.sin(angle) * reach);
    }
    const geometry = new T.BufferGeometry();
    geometry.setAttribute('position', new T.Float32BufferAttribute(spots, 3));
    const options = { color: GOLD, size: 0.14, transparent: true, depthWrite: false };

    return new T.Points(geometry, new T.PointsMaterial(options));
  }

  // Adds amount to every emissive colour under body, keeping each material's own emissive (skeleton eyes glow).
  function lift(body, amount) {
    body.traverse((node) => {
      const materials = [].concat(node.material || []);
      materials.forEach((mat) => {
        if (!mat.emissive) return;
        mat.userData.baseEmissive = mat.userData.baseEmissive || mat.emissive.clone();
        mat.emissive.copy(mat.userData.baseEmissive).addScalar(amount);
      });
    });
  }

  function make(T) {
    const group = new T.Group();
    const target = ring(T, 0.55, 0.68, RING.friendly);
    const hover = ring(T, 0.72, 0.8, HOVER);
    const sparks = sparkle(T);
    group.add(target, hover, sparks);

    function apply(raw, t, body) {
      const f = flags(raw);
      const pulse = 0.5 + 0.5 * Math.sin(t * 5);
      target.visible = f.target;
      target.material.color.setHex(f.ring);
      hover.visible = f.hover;
      hover.material.opacity = 0.45 + 0.4 * pulse;
      hover.scale.setScalar(1 + 0.05 * pulse);
      sparks.visible = f.sparkle;
      sparks.rotation.y = t * 0.8;
      sparks.material.opacity = 0.55 + 0.45 * Math.abs(Math.sin(t * 3));
      if (body) lift(body, f.hover ? LIFT : 0);
    }

    const out = { group, apply };

    return out;
  }

  TK.scene3dMarks = { RING, flags, make };
})(window.TK);
