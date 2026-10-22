# Conventions

What the numbers in every `hf_*` tool mean.

- **Units and axes.** Metres, Godot's axes: Y is up. Positions are world space.
- **Size is the full extent**, not a half size: a 4 by 3 by 1 wall is
  `"size": [4, 3, 1]`.
- **Position is the centre.** A box of height 3 standing on y = 1 has its centre
  at y = 2.5.
- **Rotation** is degrees, Euler XYZ, absolute: the same call twice leaves it
  where the first one put it.
- **Snapping.** With snap on, a size snaps to whole grid steps and an unrotated
  brush's lowest corner lands on the grid. A centred brush whose size is an odd
  number of half grid steps then moves off the centre you asked for. The answer
  says `snapped` true when anything moved, with `requested` beside what was
  applied. Pass `"snap": false` for a piece that must sit exactly where planned.
- **Wedges.** Before rotation a wedge's tall vertical face is on -x and its slope
  rises toward -x. Turn it with `rotation_degrees` to face a ramp another way.
- **Round shapes** stand along Y. A cylinder's `size` y is its height. A torus
  lies flat, with `size` y the thickness of its tube.
- **Cuts.** A brush placed with `"operation": "subtract"` is a cut. It waits as a
  pending cut, drawn see-through, until `hf_bake` applies it. Make it reach a
  little past both faces of the wall it cuts, so it cuts clean through.
- **The spawn.** `hf_set_spawn` takes where the player's feet go. Yaw 0 faces -Z,
  and a positive yaw turns toward -X.
- **The player.** The playtest player is 0.35 m in radius and 1.6 m tall, walks
  up steps of 0.4 m or less, and walks slopes up to 45 degrees. Doorways need to
  be taller and wider than that; `hf_validate` checks steps and doorways against
  these numbers.
- **Faces.** A face is named by its index, by a world side such as `"+y"`, or by
  `{"normal": [x, y, z]}`. A box's faces are stored +X, -X, +Y, -Y, +Z, -Z.
