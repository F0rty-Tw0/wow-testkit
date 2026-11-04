-- The unit modules Sim.install installs (each M.install(w)) after its own, in this order. Later phases append a name.
return {
  "sim_target",
  "sim_melee",
  "sim_mobs",
  "sim_bags",
  "sim_bags_api",
  "sim_loot",
  "sim_loot_api",
  "sim_spells",
  "sim_effects",
  "sim_ground",
  "sim_power",
}
