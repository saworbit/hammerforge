extends GutTest

## A brush entity is a class, a name and an identity (#668, #659).
##
## Geometry tied to a class becomes a door, a platform, a trigger. The class was
## all a brush carried: `find_entities_by_name()` looks for an `entity_name` on
## brushes and says so in its own comment, and the `.map` exporter writes one,
## but the only code that ever *set* it was the `.map` import path. So a door
## imported from someone else's map could be targeted and a door built here
## could not.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")


func _fresh_root() -> LevelRoot:
	var root := LevelRootType.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	root.owner = self
	return root


func _leaf(root: LevelRoot, at: Vector3) -> Node:
	return (
		root
		. create_brush_from_info(
			{
				"shape": root.BrushShape.BOX,
				"size": Vector3(1, 2, 0.25),
				"transform": Transform3D(Basis.IDENTITY, at),
				"operation": CSGShape3D.OPERATION_UNION,
			}
		)
	)


func _door(root: LevelRoot) -> Array:
	return [_leaf(root, Vector3(-0.5, 1, 0)), _leaf(root, Vector3(0.5, 1, 0))]


func _ids(nodes: Array) -> Array:
	return nodes.map(func(b): return str(b.get("brush_id")))


# ===========================================================================
# The name
# ===========================================================================


func test_a_tied_brush_can_be_given_a_name_that_io_resolves():
	var root := _fresh_root()
	var leaves := _door(root)
	root.tie_brushes_to_entity(_ids(leaves), "func_door", "gate")

	assert_eq(root.find_entities_by_name("gate").size(), 2, "both leaves answer to the name")
	for leaf in leaves:
		assert_eq(str(leaf.get_meta("entity_name", "")), "gate")


func test_tying_without_a_name_leaves_no_name_behind():
	var root := _fresh_root()
	var leaves := _door(root)
	root.tie_brushes_to_entity(_ids(leaves), "func_door")
	for leaf in leaves:
		assert_false(leaf.has_meta("entity_name"), "an unnamed door has no address")


func test_untie_takes_the_name_and_the_identity_with_the_class():
	# A brush that is no longer an entity must not keep answering to one, or
	# #620's dangling wire check finds a target that is ordinary geometry.
	var root := _fresh_root()
	var leaves := _door(root)
	root.tie_brushes_to_entity(_ids(leaves), "func_door", "gate")
	root.untie_brushes_from_entity(_ids(leaves))

	assert_eq(root.find_entities_by_name("gate").size(), 0, "nothing answers to it now")
	for leaf in leaves:
		assert_eq(str(leaf.get_meta("brush_entity_class", "")), "")
		assert_false(leaf.has_meta("entity_name"))
		assert_false(leaf.has_meta("brush_entity_group"))


# ===========================================================================
# Identity is not the name
# ===========================================================================


func test_one_tie_is_one_entity_even_with_no_name():
	var root := _fresh_root()
	var leaves := _door(root)
	root.tie_brushes_to_entity(_ids(leaves), "func_door")
	var first := str(leaves[0].get_meta("brush_entity_group", ""))
	assert_ne(first, "", "the tie minted an identity")
	assert_eq(str(leaves[1].get_meta("brush_entity_group", "")), first, "shared by both leaves")


func test_two_separate_ties_are_two_entities():
	# Keying the export on `(class, name)` alone would merge these into one door,
	# which is the opposite mistake from splitting a two leaf door into two.
	var root := _fresh_root()
	var first := [_leaf(root, Vector3(0, 1, 0))]
	var second := [_leaf(root, Vector3(4, 1, 0))]
	root.tie_brushes_to_entity(_ids(first), "func_door")
	root.tie_brushes_to_entity(_ids(second), "func_door")

	assert_ne(
		str(first[0].get_meta("brush_entity_group", "")),
		str(second[0].get_meta("brush_entity_group", "")),
		"two doors tied separately stay two doors"
	)


func test_the_identity_survives_a_snapshot_round_trip():
	var root := _fresh_root()
	var leaves := _door(root)
	root.tie_brushes_to_entity(_ids(leaves), "func_door", "gate")
	var group := str(leaves[0].get_meta("brush_entity_group", ""))

	var state: Dictionary = root.state_system.capture_state()
	root.state_system.restore_state(state)

	var seen := 0
	for child in root.draft_brushes_node.get_children():
		if root.is_brush_node(child) and str(child.get_meta("brush_entity_group", "")) == group:
			seen += 1
	assert_eq(seen, 2, "an undo does not dissolve the grouping")
	assert_eq(root.find_entities_by_name("gate").size(), 2, "or the name")


# ===========================================================================
# The classes that ship (#659)
# ===========================================================================


func test_the_shipped_classes_cover_what_the_io_system_is_for():
	var root := _fresh_root()
	var defs: Dictionary = root.get_entity_definitions()
	for expected in [
		"trigger_once",
		"trigger_multiple",
		"func_door",
		"func_button",
		"light_spot",
		"light_directional",
		"prop_static",
		"info_target",
		"logic_relay",
		"logic_timer",
	]:
		assert_true(defs.has(expected), "%s ships" % expected)


func test_the_brush_entity_classes_are_marked_as_such():
	# The dock's Tie to Entity dropdown is filled from these, and the entity
	# palette deliberately skips them: a brush entity is placed by tying
	# geometry, not by clicking a palette button.
	var root := _fresh_root()
	var defs: Dictionary = root.get_entity_definitions()
	for brush_class in ["trigger_once", "trigger_multiple", "func_door", "func_button"]:
		assert_true(
			bool(defs[brush_class].get("is_brush_entity", false)),
			"%s is geometry, not a point" % brush_class
		)
	for point_class in ["light_spot", "prop_static", "info_target"]:
		assert_false(bool(defs[point_class].get("is_brush_entity", false)))


# ===========================================================================
# One entity of several brushes in a .map (#1128)
# ===========================================================================


## The brushes a `.map` export of `root` reads back as, of one class.
func _read_back(root: LevelRoot, entity_class: String) -> Array:
	var parsed: Dictionary = MapIO.parse_map_text(MapIO.export_map_from_level(root))
	return (parsed["brushes"] as Array).filter(
		func(info): return str(info.get("brush_entity_class", "")) == entity_class
	)


func test_a_two_leaf_door_exports_as_one_entity_of_two_brushes():
	# Every leaf's planes went into one brush block, which a reader takes as one
	# brush: the space inside all twelve planes, which is neither leaf.
	var root := _fresh_root()
	var leaves := _door(root)
	root.tie_brushes_to_entity(_ids(leaves), "func_door", "gate")
	var text := MapIO.export_map_from_level(root)
	assert_eq(text.count('"classname" "func_door"'), 1, "one entity")
	var brushes := _read_back(root, "func_door")
	assert_eq(brushes.size(), 2, "of two brushes")
	for info in brushes:
		assert_eq(str(info.get("entity_name", "")), "gate")


func test_a_wire_on_any_brush_of_the_entity_is_written_once():
	# Only the first brush's wires were written, and the Entity panel puts a wire
	# on the brush that is selected.
	var root := _fresh_root()
	var leaves := _door(root)
	root.tie_brushes_to_entity(_ids(leaves), "func_door", "gate")
	root.add_entity_output(leaves[1], "OnOpen", "lamp", "TurnOn")
	var text := MapIO.export_map_from_level(root)
	assert_eq(text.count('"OnOpen"'), 1, "the second leaf's wire, once")
	for info in _read_back(root, "func_door"):
		assert_eq((info.get("entity_io_outputs", []) as Array).size(), 1, "and read back")


func test_a_wire_every_brush_holds_is_written_once():
	# A `.map` import gives each brush of an entity the entity's wires, and so
	# does the Entity panel since #1129.
	var root := _fresh_root()
	var leaves := _door(root)
	root.tie_brushes_to_entity(_ids(leaves), "func_door", "gate")
	root.add_entity_output(leaves[0], "OnOpen", "lamp", "TurnOn")
	for leaf in leaves:
		assert_eq(root.get_entity_outputs(leaf).size(), 1, "%s holds it once" % leaf.name)
	var text := MapIO.export_map_from_level(root)
	assert_eq(text.count('"OnOpen"'), 1, "not once per brush")
	for info in _read_back(root, "func_door"):
		assert_eq((info.get("entity_io_outputs", []) as Array).size(), 1, "a round trip keeps one")


func test_two_wires_on_one_event_on_one_brush_are_both_written():
	var root := _fresh_root()
	var leaves := _door(root)
	root.tie_brushes_to_entity(_ids(leaves), "func_door", "gate")
	root.add_entity_output(leaves[0], "OnOpen", "lamp", "TurnOn")
	root.add_entity_output(leaves[0], "OnOpen", "lamp", "TurnOn", "", 2.0)
	var text := MapIO.export_map_from_level(root)
	assert_eq(text.count('"OnOpen"'), 2, "two different wires stay two")


func test_a_property_any_brush_holds_is_written_once():
	var root := _fresh_root()
	var leaves := _door(root)
	root.tie_brushes_to_entity(_ids(leaves), "func_door", "gate")
	leaves[0].set_meta("brush_entity_data", {"speed": 5.0})
	leaves[1].set_meta("brush_entity_data", {"speed": 5.0, "wait": 7.0})
	var text := MapIO.export_map_from_level(root)
	assert_eq(text.count('"speed"'), 1, "once, not once per brush")
	assert_eq(text.count('"wait"'), 1, "and one only the second brush held")
