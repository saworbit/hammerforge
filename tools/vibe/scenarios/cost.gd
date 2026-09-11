@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## What one brush of each shape costs to hold, to save, and to reopen.
##
## Cheap to measure and easy to regress without noticing, because nothing in the
## viewport looks different when a shape starts carrying ten times the faces it
## needs. The `.hflevel` size is the honest number: it is what autosave writes on
## a timer and what undo walks.

## One brush per level, so the numbers are per brush rather than per level.
const SHAPES: Array = [
	[0, "box"],
	[4, "wedge"],
	[11, "tetrahedron"],
	[1, "cylinder"],
	[3, "cone"],
	[13, "dodecahedron"],
	[2, "sphere"],
	[10, "torus"],
]

## A brush costing more than this to save is worth a look. A box is ~1.2 KB.
const SIZE_BUDGET_BYTES := 32768


func id() -> String:
	return "cost"


func summary() -> String:
	return "faces, build time and .hflevel size for one brush of each shape"


func run() -> void:
	note("%-14s %8s %10s %12s %9s" % ["shape", "faces", "build_ms", "bytes", "save_ms"])
	for entry in SHAPES:
		var shape: int = entry[0]
		var label: String = entry[1]
		var root: Node3D = await fresh_root("Cost_%s" % label)

		var build_start := Time.get_ticks_msec()
		root.create_brush_from_info(
			{"shape": shape, "size": Vector3(64, 64, 64), "center": Vector3.ZERO, "sides": 8}
		)
		var build_ms := Time.get_ticks_msec() - build_start

		var faces := (root.draft_brushes_node.get_child(0).get("faces") as Array).size()
		var path := "user://vibe_cost_%s.hflevel" % label

		var save_start := Time.get_ticks_msec()
		root.save_hflevel(path, true)
		var settled: bool = await HFVibe.settle_save(_tree, root)
		var save_ms := Time.get_ticks_msec() - save_start
		if not settled:
			flag("%s never finished saving" % label)
			continue

		var bytes := HFVibe.file_size(path)
		note("%-14s %8d %10d %12d %9d" % [label, faces, build_ms, bytes, save_ms])
		if bytes > SIZE_BUDGET_BYTES:
			known(
				322,
				"one %s costs %d bytes to save" % [label, bytes],
				"%d faces, one per mesh triangle" % faces
			)
		root.free()
