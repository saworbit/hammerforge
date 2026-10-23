extends GutTest

## The loader rebuilds a primitive whose faces do not close, and leaves out a
## custom brush in that state (#1769). It must never touch a brush this build
## made: every kind of brush, every structure and every cut piece here goes
## through a save and a load and comes back as it was, with nothing said.

const HFSolidMeasure = preload("res://addons/hammerforge/hf_solid_measure.gd")
const HFLevelIO = preload("res://addons/hammerforge/hflevel_io.gd")
const HFGeneratorSystem = preload("res://addons/hammerforge/systems/hf_generator_system.gd")
const LevelRootType = preload("res://addons/hammerforge/level_root.gd")


func after_each() -> void:
	HFLog.end_test_capture()


func _new_level() -> LevelRoot:
	var level := LevelRootType.new()
	level.auto_spawn_player = false
	level.commit_freeze = false
	level.hflevel_autosave_enabled = false
	level.grid_snap = 0.25
	add_child_autofree(level)
	return level


func _brush(level: LevelRoot, info: Dictionary) -> DraftBrush:
	return level.create_brush_from_info(info) as DraftBrush


## One of each thing that makes a brush, spread out so nothing touches.
func _every_kind(level: LevelRoot) -> void:
	var x := 0.0
	for shape in level.BrushShape.values():
		if shape == level.BrushShape.CUSTOM:
			continue
		for sides in [5, 16, 48]:
			var info := {
				"shape": shape,
				"size": Vector3(2, 3, 2),
				"center": Vector3(x, 1.5, 0),
				"sides": sides,
				"transform":
				Transform3D(Basis.from_euler(Vector3(0.3, 0.7, -0.2)), Vector3(x, 1.5, 0)),
			}
			_brush(level, info)
			x += 4.0
	for type in ["arch", "stairs", "spiral_stairs", "dome", "ring", "door_frame"]:
		level.create_generator(
			type, HFGeneratorSystem.default_settings(type), Transform3D(Basis(), Vector3(x, 0, 20))
		)
		x += 12.0
	var clipped := _brush(
		level, {"brush_id": "clipme", "size": Vector3(4, 4, 4), "center": Vector3(0, 2, 40)}
	)
	level.clip_brush_by_id("clipme", 0, 0.75)
	_brush(level, {"brush_id": "wall", "size": Vector3(6, 4, 1), "center": Vector3(10, 2, 40)})
	_brush(
		level,
		{
			"brush_id": "door",
			"size": Vector3(2, 3, 3),
			"center": Vector3(10, 1.5, 40),
			"operation": CSGShape3D.OPERATION_SUBTRACTION
		}
	)
	level.carve_with_brush("door")
	_brush(level, {"brush_id": "room", "size": Vector3(6, 4, 6), "center": Vector3(20, 2, 40)})
	level.hollow_brush_by_id("room", 0.5)
	_brush(level, {"brush_id": "m1", "size": Vector3(2, 2, 2), "center": Vector3(30, 1, 40)})
	_brush(level, {"brush_id": "m2", "size": Vector3(2, 2, 2), "center": Vector3(32, 1, 40)})
	level.merge_brushes_by_ids(["m1", "m2"])
	assert_not_null(clipped, "fixture")


func test_every_brush_this_build_makes_is_closed():
	var level := _new_level()
	_every_kind(level)
	var brushes := level._iter_managed_brush_nodes()
	assert_gt(brushes.size(), 60, "fixture: many kinds of brush")
	for brush in brushes:
		assert_eq(HFSolidMeasure.open_edge_count(brush.faces), 0, "%s is closed" % brush.brush_id)


func test_every_brush_this_build_makes_comes_back_from_a_file_as_it_was():
	var level := _new_level()
	_every_kind(level)
	var saved: Dictionary = level.state_system.capture_hflevel_state()
	# Through JSON text, as a file holds it.
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(saved))
	var decoded: Dictionary = HFLevelIO.decode_variant(parsed)
	var before := {}
	for brush in level._iter_managed_brush_nodes():
		before[brush.brush_id] = brush.faces.size()
	var again := _new_level()
	HFLog.begin_test_capture(["left out", "damaged corners"])
	again.restore_state(decoded.get("state", {}))
	var said := HFLog.get_captured_warnings().filter(
		func(w): return str(w).contains("left out") or str(w).contains("damaged corners")
	)
	HFLog.end_test_capture()
	assert_eq(said, [], "no brush rebuilt or left out")
	var after := {}
	for brush in again._iter_managed_brush_nodes():
		after[brush.brush_id] = brush.faces.size()
	assert_eq(after, before, "every brush back, with its faces")


func test_open_edge_count_sees_a_moved_corner_and_not_float_noise():
	var level := _new_level()
	var box := _brush(level, {"size": Vector3(2, 2, 2), "center": Vector3.ZERO})
	var rings: Array = []
	for face in box.faces:
		var ring := PackedVector3Array()
		for point in face.local_verts:
			ring.append(point + Vector3(0.0000003, -0.0000002, 0.0000001) * float(rings.size()))
		rings.append(ring)
	assert_eq(HFSolidMeasure.open_edge_count(rings), 0, "noise a weld closes")
	var moved: PackedVector3Array = rings[0]
	moved[0] = moved[0] + Vector3(0, -1, 0)
	rings[0] = moved
	assert_gt(HFSolidMeasure.open_edge_count(rings), 0, "a corner moved a metre opens it")


func test_a_corner_on_the_middle_of_an_edge_is_not_a_seam():
	var level := _new_level()
	var box := _brush(level, {"size": Vector3(2, 2, 2), "center": Vector3.ZERO})
	var rings: Array = []
	for face in box.faces:
		rings.append(PackedVector3Array(face.local_verts))
	# A clip can leave a corner on one face's edge that the face beside it lacks.
	var first: PackedVector3Array = rings[0]
	var middle := (first[0] + first[1]) * 0.5
	first.insert(1, middle)
	rings[0] = first
	assert_eq(HFSolidMeasure.open_edge_count(rings), 0)


## A record of fewer than four faces is no solid at all, such as a lone
## displaced tile, so no corner of it was moved: it loads as it is.
func test_a_record_of_fewer_than_four_faces_loads_as_it_is():
	var level := _new_level()
	_brush(level, {"brush_id": "tile", "size": Vector3(2, 2, 2), "center": Vector3.ZERO})
	var saved: Dictionary = level.state_system.capture_hflevel_state()
	var decoded: Dictionary = HFLevelIO.decode_variant(JSON.parse_string(JSON.stringify(saved)))
	var record: Dictionary = decoded["state"]["brushes"][0]
	record["faces"] = [record["faces"][0]]
	var again := _new_level()
	HFLog.begin_test_capture(["left out", "damaged corners"])
	again.restore_state(decoded["state"])
	assert_eq(HFLog.get_captured_warnings(), [], "nothing said")
	var tile: DraftBrush = again.find_brush_by_id("tile")
	assert_not_null(tile)
	if tile != null:
		assert_eq(tile.faces.size(), 1, "its one face, not a box built from its shape")
