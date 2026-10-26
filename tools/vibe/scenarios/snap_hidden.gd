@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Whether a snap lands on a brush the mapper has hidden.
##
## `HFSnapSystem.vertex_near_screen()` leaves a hidden brush out, "since its
## corner is not there to aim at". The snap a draw, a move and the measure tool
## take, `snap_point()`, collects its candidates from `_iter_pick_nodes()` with
## no such test. This hides one of two brushes four ways -- its visgroup, Hide
## Selection, a View Filter, and an isolate of the other -- and asks the snap
## for the point just off the hidden brush's corner.

const HFSnapSystem = preload("res://addons/hammerforge/hf_snap_system.gd")


func id() -> String:
	return "snap-hidden"


func summary() -> String:
	return "whether a snap lands on a corner of a brush the mapper has hidden"


func expected_issues() -> Array[int]:
	return [1963]


func run() -> void:
	await _case("its visgroup hidden")
	await _case("Hide Selection")
	await _case("a View Filter on world brushes")
	await _case("the other brush isolated")


func _case(how: String) -> void:
	var root: Node3D = await fresh_root("SnapLevel")
	var shown = box(root, Vector3(2, 2, 2), Vector3(-6, 1, 0))
	var hidden = box(root, Vector3(2, 2, 2), Vector3(0, 1, 0))
	await frame()
	match how:
		"its visgroup hidden":
			root.create_visgroup("away")
			root.add_selection_to_visgroup("away", [hidden])
			root.set_visgroup_visible("away", false)
		"Hide Selection":
			root.visgroup_system.hide_from_view([hidden])
		"a View Filter on world brushes":
			# Both are world brushes, so tie the shown one to a class to keep it.
			root.tie_brushes_to_entity([str(shown.get_meta("brush_id", ""))], "func_detail", "kept")
			root.view_filters = {"world": true}
			root.visgroup_system.refresh_visibility()
		"the other brush isolated":
			root.visgroup_system.isolate_nodes([shown])
	await frame()
	var snap = root.snap_system
	snap.enabled_modes = HFSnapSystem.SnapMode.VERTEX
	var corner := Vector3(1, 2, 1)
	var near := corner + Vector3(0.04, 0.03, -0.02)
	var got: Vector3 = snap.snap_point(near, 0.0)
	note(
		how,
		(
			"hidden brush visible_in_tree %s, shown %s; a snap at %s lands on %s"
			% [hidden.is_visible_in_tree(), shown.is_visible_in_tree(), near, got]
		)
	)
	if hidden.is_visible_in_tree():
		note("%s: the brush did not hide, so nothing is asked" % how)
	elif got.distance_to(corner) < 0.001:
		known(
			1963,
			"a vertex snap lands on the corner of a brush hidden by %s" % how,
			(
				"with vertex snap on, a point 0.05 from the corner %s of a hidden brush snaps to it. Nothing is drawn there; the mapper cannot see what the draw, the move or the measure caught on. vertex_near_screen() leaves hidden brushes out for this reason."
				% corner
			)
		)
	await drop_root(root)
