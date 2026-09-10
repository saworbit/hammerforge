@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## What the level-management commands do with input at their edges.
##
## Zero, negative, absurd, empty, duplicate, missing. Most of these come back
## refused with a message, which is what should happen and is worth recording so
## the next reader knows the ground is covered. The interesting ones are where
## something succeeded that should not have, or where a value went in that has no
## relationship to the geometry it governs.


func id() -> String:
	return "limits"


func summary() -> String:
	return "arrays, generators, prefabs, visgroups and paint layers at their edges"


func run() -> void:
	var root: Node3D = await fresh_root()

	note("--- generators")
	for type in ["stairs", "spiral_stairs", "arch", "dome"]:
		var res = root.create_generator(type, {}, Transform3D())
		note("%-15s defaults" % type, "%s / %s" % [res.ok, res.message])
		if not res.ok:
			flag("%s could not be created with its own defaults" % type, res.message)
	var refusals := {
		"unknown type": root.create_generator("no_such_type", {}, Transform3D()),
		"stairs steps=0": root.create_generator("stairs", {"steps": 0}, Transform3D()),
		"stairs steps=-5": root.create_generator("stairs", {"steps": -5}, Transform3D()),
		"stairs steps=100000": root.create_generator("stairs", {"steps": 100000}, Transform3D()),
		"arch segments=1": root.create_generator("arch", {"segments": 1}, Transform3D()),
		"dome rings=0": root.create_generator("dome", {"rings": 0}, Transform3D()),
		"spiral steps=NaN": root.create_generator("spiral_stairs", {"steps": NAN}, Transform3D()),
	}
	for label in refusals:
		var res = refusals[label]
		note("%-22s" % label, "%s / %s" % [res.ok, res.message])
		if res.ok:
			flag("%s was accepted" % label)

	note("--- generator ids that do not exist")
	note("regenerate", root.generator_system.regenerate("nope", {"steps": 2}).ok)
	note("remove", root.generator_system.remove("nope"))
	note("detach", root.generator_system.detach("nope"))
	note("edited_piece_count", root.generator_system.edited_piece_count("nope"))

	note("--- arrays")
	var b = box(root, Vector3(32, 32, 32), Vector3(-400, 0, 0))
	var brush_id := str(b.get_meta("brush_id"))
	var ids := PackedStringArray([brush_id])
	note("linear count=0", root.create_duplicate_array(ids, 0, Vector3(64, 0, 0)) != null)
	note("linear count=-3", root.create_duplicate_array(ids, -3, Vector3(64, 0, 0)) != null)
	var before: int = root.brush_system.get_live_brush_count()
	var big = root.create_duplicate_array(ids, 1000, Vector3(64, 0, 0))
	var made: int = root.brush_system.get_live_brush_count() - before
	note("linear count=1000", "created %d copies" % made)
	if big != null and made > 256:
		known(300, "the 256-copy cap did not apply", "%d copies created" % made)
	note("radial count=0", root.create_radial_array(ids, 0, 64.0, 1, Vector3.ZERO, true) != null)
	note("update an array id that does not exist", root.update_duplicate_array("nope", 0, {}))
	note("detach an array id that does not exist", root.detach_duplicate_array("nope"))

	note("--- prefab ids that do not exist")
	var prefabs = root.prefab_system
	note("get_instance", prefabs.get_instance("nope"))
	note("cycle_variant", prefabs.cycle_variant("nope"))
	note("set_variant", prefabs.set_variant("nope", "v"))
	note("push_to_source", prefabs.push_instance_to_source("nope"))
	note("compute_diff", prefabs.compute_instance_diff("nope"))
	note("propagate_from_source", prefabs.propagate_from_source("res://no_such.tres"))

	note("--- visgroups")
	root.create_visgroup("", Color.RED)
	note("after creating one with an empty name", root.get_visgroup_names())
	if "" in Array(root.get_visgroup_names()):
		flag("a visgroup was created with an empty name")
	root.create_visgroup("A")
	root.create_visgroup("A")
	note("after creating 'A' twice", root.get_visgroup_names())
	root.remove_visgroup("does_not_exist")

	note("--- a hidden visgroup, then deleted")
	var member = box(root, Vector3(32, 32, 32), Vector3(-500, 0, 0))
	root.create_visgroup("Hidden")
	root.add_selection_to_visgroup("Hidden", [member])
	root.set_visgroup_visible("Hidden", false)
	note("member hidden with the visgroup", member.visible)
	root.remove_visgroup("Hidden")
	note("member after the visgroup is deleted", member.visible)
	if not member.visible:
		known(
			316,
			"deleting a hidden visgroup left its member invisible",
			"nothing in the UI can show it again"
		)

	note("--- paint layers")
	root.paint_system.add_paint_layer()
	root.paint_system.add_paint_layer()
	root.paint_system.rename_paint_layer(1, "Same")
	root.paint_system.rename_paint_layer(0, "Same")
	var names: Array = root.paint_system.get_paint_layer_names()
	note("after renaming two layers to one name", names)
	if names.count("Same") > 1:
		known(321, "two paint layers share a name", names)
	root.paint_system.rename_paint_layer(99, "out of range")
	root.paint_system.set_active_paint_layer(99)
	note("active index after an out-of-range set", root.paint_system.get_active_paint_layer_index())
	for _i in range(8):
		root.paint_system.remove_active_paint_layer()
	note("layers left after removing more than exist", root.paint_system.get_paint_layer_names())
	if root.paint_system.get_paint_layer_names().is_empty():
		flag("every paint layer was removed, leaving nothing to paint on")

	note("--- empty selections")
	# The two disagree on purpose. `can_merge_brushes()` is the whole precondition
	# for merging, and merging fewer than two brushes is meaningless, so it
	# refuses. `can_flip_brushes()` only asks whether any of the brushes carries a
	# displacement -- an empty list carries none, so it passes -- and the caller in
	# plugin_edit_actions.gd has already returned on an empty selection before it
	# is reached. Recorded rather than flagged, so a future reader does not
	# rediscover it as a defect.
	note("can_merge []", root.brush_system.can_merge_brushes([]).ok)
	note(
		"can_flip [] (a displacement check, not a count check)",
		root.transform_system.can_flip_brushes([]).ok
	)
