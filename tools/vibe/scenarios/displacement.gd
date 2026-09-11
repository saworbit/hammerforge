@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Displacement sculpting: the lifecycle, and what the sculpt survives.
##
## A displacement grid is the most expensive thing in the editor to recreate by
## hand -- it is minutes of shaping that no other operation can reproduce -- so
## anything that discards or corrupts one silently is worth more attention than
## the same defect elsewhere.


func id() -> String:
	return "displacement"


func summary() -> String:
	return "displacement lifecycle, input validation, and whether a sculpt survives"


func run() -> void:
	var root: Node3D = await fresh_root()
	var b = box(root, Vector3(64, 64, 64))
	var brush_id := str(b.get_meta("brush_id"))

	note("--- create")
	note("power 3", root.displacement_system.create_displacement(brush_id, 0, 3))
	note(
		"power 99 (clamped to 2..4)", root.displacement_system.create_displacement(brush_id, 1, 99)
	)
	note("power -1", root.displacement_system.create_displacement(brush_id, 2, -1))
	note("face index out of range", root.displacement_system.create_displacement(brush_id, 500, 3))
	note("resulting power on face 1", b.faces[1].displacement.power)
	if b.faces[1].displacement.power > 4:
		flag("power was not clamped", b.faces[1].displacement.power)

	note("--- does a sculpt survive a second create?")
	root.displacement_system.set_elevation(brush_id, 0, 25.0)
	var elevation_before: float = b.faces[0].displacement.elevation
	var distances_before := str(b.faces[0].displacement.distances)
	var recreated: bool = root.displacement_system.create_displacement(brush_id, 0, 3)
	var elevation_after: float = b.faces[0].displacement.elevation
	var distances_after := str(b.faces[0].displacement.distances)
	note("create on a face that already has one", recreated)
	if recreated and (elevation_before != elevation_after or distances_before != distances_after):
		known(
			319,
			"a second create discarded the sculpt",
			"elevation %s -> %s" % [elevation_before, elevation_after]
		)

	note("--- input validation")
	var painted: bool = root.displacement_system.paint(
		brush_id, 0, Vector3(NAN, NAN, NAN), 10.0, 1.0
	)
	var poisoned := false
	for d in b.faces[0].displacement.distances:
		if not is_finite(d):
			poisoned = true
			break
	note("paint with a NaN centre", "returned=%s grid_poisoned=%s" % [painted, poisoned])
	if painted and poisoned:
		known(320, "a NaN paint centre filled the grid with NaN", "every distance is non-finite")

	root.displacement_system.create_displacement(brush_id, 0, 3)
	var huge: bool = root.displacement_system.set_elevation(brush_id, 0, 1e9)
	note("set_elevation 1e9", "returned=%s value=%s" % [huge, b.faces[0].displacement.elevation])
	if huge and b.faces[0].displacement.elevation > 1e6:
		known(320, "elevation is unbounded", b.faces[0].displacement.elevation)

	note("--- destroy")
	note("destroy", root.displacement_system.destroy_displacement(brush_id, 0))
	var again: bool = root.displacement_system.destroy_displacement(brush_id, 0)
	note("destroy again", again)
	if again:
		flag("destroying a face with no displacement reported success")

	note("--- sew")
	note("sew_all", root.displacement_system.sew_all(0.5))
