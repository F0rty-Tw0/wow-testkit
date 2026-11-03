# Model credits

Every model is by Kay Lousberg (https://www.kaylousberg.com), released under CC0
(http://creativecommons.org/publicdomain/zero/1.0/): free for personal and commercial use, no credit required. Each
pack's `LICENSE.txt` says so. Packs are at https://github.com/KayKit-Game-Assets/.

Each `<name>.js` is a classic script setting `TK.models["<name>"]` to a base64 GLB, built with
`python -I tools/vendor/wrap_glb.py <source> <name> <name>.js [--clips ...]`.

| file | pack | author | URL | license | clips |
| --- | --- | --- | --- | --- | --- |
| knight.js | KayKit Adventurers Character Pack 1.0 (Knight.glb) | Kay Lousberg | https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0 | CC0 | Idle, Running_A, Walking_A, 1H_Melee_Attack_Chop, 1H_Melee_Attack_Slice_Diagonal, 2H_Melee_Attack_Chop, 1H_Ranged_Shoot, Spellcast_Shoot, Spellcasting, Hit_A, Death_A, Death_A_Pose |
| barbarian.js | KayKit Adventurers Character Pack 1.0 (Barbarian.glb) | Kay Lousberg | https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0 | CC0 | same 12 as knight |
| mage.js | KayKit Adventurers Character Pack 1.0 (Mage.glb) | Kay Lousberg | https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0 | CC0 | same 12 as knight |
| ranger.js | KayKit Adventurers Character Pack 1.0 (Rogue_Hooded.glb) | Kay Lousberg | https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0 | CC0 | same 12 as knight |
| rogue.js | KayKit Adventurers Character Pack 1.0 (Rogue.glb) | Kay Lousberg | https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0 | CC0 | same 12 as knight |
| skeleton.js | KayKit Character Pack Skeletons 1.0 (Skeleton_Warrior.glb) | Kay Lousberg | https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Skeletons-1.0 | CC0 | same 12 as knight |
| tree.js | KayKit Medieval Hexagon Pack 1.0 (tree_single_A.gltf) | Kay Lousberg | https://github.com/KayKit-Game-Assets/KayKit-Medieval-Hexagon-Pack-1.0 | CC0 | none (static) |
| rock.js | KayKit Medieval Hexagon Pack 1.0 (rock_single_A.gltf) | Kay Lousberg | https://github.com/KayKit-Game-Assets/KayKit-Medieval-Hexagon-Pack-1.0 | CC0 | none (static) |

## Notes

- The pack has no `Ranger.glb`; `ranger` is `Rogue_Hooded.glb`.
- The pack has no bush; bush stays a primitive.
- Characters keep 12 of 76 (Adventures) or 95 (Skeletons) clips, cut with `--clips`:
  `Idle,Running_A,Walking_A,1H_Melee_Attack_Chop,1H_Melee_Attack_Slice_Diagonal,2H_Melee_Attack_Chop,1H_Ranged_Shoot,Spellcast_Shoot,Spellcasting,Hit_A,Death_A,Death_A_Pose`.
  All twelve exist in all six characters, so no animation is missing.
- Tree and rock are tiny hex-tile props; the scene must scale them. POSITION bounds (model units):
  tree x -0.288..0.286, y -0.103..1.094, z -0.302..0.245 (about 0.57 wide, 1.20 tall, 0.55 deep);
  rock x -0.149..0.149, y 0..0.069, z -0.157..0.127 (about 0.30 wide, 0.07 tall, 0.28 deep).
  Both share one embedded texture (hexagons_medieval.png), with no skin or animation.

## Hand-item nodes

Weapons and shields are meshes parented under the `handslot.r` / `handslot.l` nodes. All are present in the file, so
a later task shows one and hides the rest by node name.

| model | handslot.r children | handslot.l children |
| --- | --- | --- |
| knight | 1H_Sword, 2H_Sword | 1H_Sword_Offhand, Badge_Shield, Rectangle_Shield, Round_Shield, Spike_Shield |
| barbarian | 1H_Axe, 2H_Axe, Mug | 1H_Axe_Offhand, Barbarian_Round_Shield |
| mage | 1H_Wand, 2H_Staff | Spellbook, Spellbook_open |
| ranger | 1H_Crossbow, 2H_Crossbow, Knife, Throwable | Knife_Offhand |
| rogue | 1H_Crossbow, 2H_Crossbow, Knife, Throwable | Knife_Offhand |
| skeleton | none (the file holds no weapon meshes) | none |

Other node names a scene may need: the rig root is `Rig` (bones `root`, `hips`, `spine`, `chest`, `head`,
`handslot.*`); the body meshes are `<Class>_Body`, `_Head`, `_ArmLeft`, `_ArmRight`, `_LegLeft`, `_LegRight`, plus
`Knight_Helmet`, `Knight_Cape`, `Barbarian_Hat`, `Barbarian_Cape`, `Mage_Hat`, `Mage_Cape`, `Rogue_Cape` (ranger's
head mesh is `Rogue_Head_Hooded`, rogue's `Rogue_Head`).
