extends GutTest

## A new structure with nothing selected stands on the floor (#1821). A structure
## is built round its own middle, and the Structure section placed it at the
## transform pivot, which with nothing selected is the world origin. So a
## staircase on a floor at y = 0 had its lower half under the floor, and Validate
## found a tread wholly inside it.

const DockScene = preload("res://addons/hammerforge/dock.tscn")
const HFSolidMeasure = preload("res://addons/hammerforge/hf_solid_measure.gd")

var dock: HammerForgeDock
var root: LevelRoot


func before_each() -> void:
	dock = DockScene.instantiate()
	add_child_autoqfree(dock)
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	dock.level_root = root
	dock._structure_section.set_expanded(true)


func after_each() -> void:
	dock = null
	root = null


func _choose(type: String) -> void:
	for index in dock.structure_type_option.item_count:
		if str(dock.structure_type_option.get_item_metadata(index)) == type:
			dock.structure_type_option.selected = index
			break
	HFDockBrushHandler.on_structure_type_changed(dock)


## The solid pieces of the structure made last, as brushes.
func _solid_pieces(generator_id: String) -> Array:
	var out: Array = []
	for brush_id in root.generator_system.generators[generator_id].brush_ids:
		var brush = root.brush_system.find_brush_by_id(str(brush_id))
		if brush != null and brush.operation != CSGShape3D.OPERATION_SUBTRACTION:
			out.append(brush)
	return out


func _lowest(brushes: Array) -> float:
	var lowest := INF
	for brush in brushes:
		lowest = minf(lowest, HFSolidMeasure.bounds(HFSolidMeasure.world_faces(brush)).position.y)
	return lowest


func _create(type: String) -> String:
	_choose(type)
	var before: Array = root.generator_system.generators.keys()
	dock._on_create_structure()
	for generator_id in root.generator_system.generators:
		if not before.has(generator_id):
			return str(generator_id)
	return ""


func test_with_nothing_selected_each_structure_stands_on_y_0():
	for type in HFGeneratorSystem.known_types():
		var generator_id := _create(type)
		assert_ne(generator_id, "", "%s builds at its defaults" % type)
		if generator_id == "":
			continue
		var pieces := _solid_pieces(generator_id)
		assert_gt(pieces.size(), 0, "%s has solid pieces" % type)
		assert_almost_eq(_lowest(pieces), 0.0, 0.001, "%s stands on y = 0" % type)


func test_the_ghost_stands_where_create_will_build():
	var spiral := HFGeneratorSystem.default_settings("spiral_stairs")
	assert_gt(
		HFGeneratorSystem.stand_height("spiral_stairs", spiral),
		0.0,
		"fixture: a spiral flight is built round its middle"
	)
	for type in HFGeneratorSystem.known_types():
		_choose(type)
		HFDockBrushHandler.refresh_structure_preview(dock)
		var placement := HFDockBrushHandler.create_placement(dock)
		var lift := HFGeneratorSystem.stand_height(
			type, HFDockBrushHandler.collect_structure_settings(dock)
		)
		assert_almost_eq(placement.origin, Vector3(0, lift, 0), Vector3.ONE * 0.001)
		assert_almost_eq(
			root.structure_preview._mesh_instance.global_transform.origin,
			placement.origin,
			Vector3.ONE * 0.001,
			"the %s ghost stands there too" % type
		)


func test_with_a_selection_it_is_still_centred_on_the_selection():
	var wall = root.create_brush_from_info(
		{"shape": 0, "size": Vector3(4, 3, 0.5), "center": Vector3(6, 1.5, -2)}
	)
	dock.set_selection_nodes([wall])
	_choose("door_frame")
	var placement := HFDockBrushHandler.create_placement(dock)
	assert_almost_eq(
		placement.origin,
		root.resolve_transform_pivot([str(wall.brush_id)], []),
		Vector3.ONE * 0.001,
		"a door frame set in a wall is centred on it, as before"
	)


func test_validate_finds_nothing_on_structures_made_on_a_floor_at_y_0():
	for type in ["stairs", "spiral_stairs", "arch", "dome", "ring"]:
		_use_a_new_level()
		var floor_brush = root.create_brush_from_info(
			{"shape": 0, "size": Vector3(40, 0.2, 40), "center": Vector3(0, -0.1, 0)}
		)
		var names: Array = [str(floor_brush.name)]
		for brush in _solid_pieces(_create(type)):
			names.append(str(brush.name))
		var found: Array = []
		for issue in root.validate_level().get("issues", []):
			for brush_name in names:
				if str(issue).contains(brush_name):
					found.append(str(issue))
					break
		assert_eq(found, [], "nothing on the floor or the %s" % type)


func _use_a_new_level() -> void:
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	dock.level_root = root
