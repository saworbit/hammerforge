extends GutTest

## A copy of a brush entity is an entity of its own (#1161).
##
## Duplicate, `duplicate_brush()` and the Duplicator's arrays copied a brush with
## the tie and the name of the brush it came from, and brushes with one tie, or
## one class and one name, are one entity. So a duplicated door joined the door it
## was copied from, and an array of five doors was one door.

const HFBrushEntity = preload("res://addons/hammerforge/hf_brush_entity.gd")
const HFDuplicator = preload("res://addons/hammerforge/hf_duplicator.gd")

var root: LevelRoot


func before_each():
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)


func after_each():
	root = null


func _door(door_name: String = "") -> Array:
	var leaves: Array = []
	for i in 2:
		(
			leaves
			. append(
				(
					root
					. create_brush_from_info(
						{
							"size": Vector3(1, 2, 0.25),
							"center": Vector3(i, 1, 0),
							"brush_id": "l%d" % i,
						}
					)
				)
			)
		)
	root.tie_brushes_to_entity(["l0", "l1"], "func_door", door_name)
	return leaves


func _doors_in_export() -> int:
	return MapIO.export_map_from_level(root).count('"classname" "func_door"')


func _brush(brush_id: String) -> Node:
	return root.find_brush_by_id(brush_id)


## What Duplicate does with what is selected: a record per brush, made entities
## of their own, then made.
func _duplicate(brushes: Array) -> Array:
	var infos: Array = brushes.map(func(b): return root.build_duplicate_info(b, Vector3(4, 0, 0)))
	HFBrushEntity.fresh_identities(infos, [], root.entity_system)
	root.create_managed_duplicates(infos, [])
	return infos.map(func(info): return _brush(str(info["brush_id"])))


func test_duplicating_a_door_gives_two_doors():
	var leaves := _door("gate")
	var copy := _duplicate(leaves)
	assert_eq(root.brush_system.brushes_of_entity(leaves[0]).size(), 2, "the door is two leaves")
	assert_eq(root.brush_system.brushes_of_entity(copy[0]).size(), 2, "and so is its copy")
	assert_eq(_doors_in_export(), 2)


func test_a_duplicated_door_has_a_name_of_its_own():
	var copy := _duplicate(_door("gate"))
	var copy_name := str(copy[0].get_meta("entity_name", ""))
	assert_ne(copy_name, "gate")
	assert_eq(str(copy[1].get_meta("entity_name", "")), copy_name, "one name for both leaves")


func test_a_duplicated_button_still_fires_at_what_it_fired_at():
	# As a duplicated point entity does (#359).
	var button = root.create_brush_from_info(
		{"size": Vector3.ONE, "center": Vector3(5, 0, 0), "brush_id": "b0"}
	)
	root.tie_brushes_to_entity(["b0"], "func_button", "btn")
	root.add_entity_output(button, "OnPressed", "gate", "Open")
	var copy := _duplicate([button])
	var wires: Array = copy[0].get_meta("entity_io_outputs", [])
	assert_eq(str(wires[0].get("target_name", "")), "gate")


func test_duplicating_one_leaf_makes_a_door_of_its_own():
	var leaves := _door()
	var copy: Node = root.brush_system.duplicate_brush(leaves[0])
	assert_eq(root.brush_system.brushes_of_entity(copy).size(), 1)
	assert_eq(root.brush_system.brushes_of_entity(leaves[0]).size(), 2, "the door keeps its leaves")


func _array_of(leaves: Array) -> HFDuplicator:
	var dup := HFDuplicator.new()
	dup.source_brush_ids = PackedStringArray(leaves.map(func(b): return str(b.brush_id)))
	return dup


func _each_copy_is_one_door(dup: HFDuplicator) -> void:
	for group in dup.instance_groups:
		var first := _brush(str(group[0]))
		assert_eq(root.brush_system.brushes_of_entity(first).size(), 2, "one door per copy")


func test_a_linear_array_of_a_door_is_a_door_per_copy():
	var dup := _array_of(_door("gate"))
	assert_true(dup.generate(root.brush_system, 2, Vector3(4, 0, 0)))
	assert_eq(_doors_in_export(), 3)
	_each_copy_is_one_door(dup)


func test_a_radial_array_of_a_door_is_a_door_per_copy():
	var dup := _array_of(_door())
	assert_true(dup.generate_radial(root.brush_system, 2, 1, 90.0, Vector3(0, 0, 8)))
	assert_eq(_doors_in_export(), 3)
	_each_copy_is_one_door(dup)


func test_a_grid_array_of_a_door_is_a_door_per_copy():
	var dup := _array_of(_door())
	assert_true(dup.generate_grid(root.brush_system, Vector3i(2, 1, 2), Vector3(4, 4, 4)))
	assert_eq(_doors_in_export(), 4)
	_each_copy_is_one_door(dup)
