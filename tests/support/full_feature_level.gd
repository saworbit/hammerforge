extends RefCounted
## A level with as much of what a level can save switched on as a test can put
## in one place: the reference map's materials, world UVs, visgroups, ties and
## wires, with cordons, a structure, an array, a hollow, a pending and a
## committed cut, notes, floor paint, an accepted finding and saved views on top.
## `test_format_record.gd` takes its census, so a key a build starts saving is
## named before an older build can drop it (#1638).

const REFERENCE := "res://addons/hammerforge/data/reference_map.hflevel"
const HFAcceptedFindings = preload("res://addons/hammerforge/hf_accepted_findings.gd")


## Fill `level`, which is in the tree. Awaits a frame for the load to settle.
static func fill(level: Node, tree: SceneTree) -> void:
	level.load_hflevel(REFERENCE)
	await tree.process_frame
	level.cordon_enabled = true
	level.cordon_aabb = AABB(Vector3(-20, -1, -8), Vector3(40, 6, 16))
	var extra: Array[AABB] = [AABB(Vector3(-4, 0, -2), Vector3(8, 3, 4))]
	level.cordon_extra_aabbs = extra
	var box = level.create_brush_from_info(
		{"shape": 0, "size": Vector3(2, 2, 2), "center": Vector3(30, 1, 0)}
	)
	# A Hidden face (#1719).
	box.faces[0].face_type = FaceData.FaceType.HIDDEN
	if level.has_method("create_generator"):
		level.create_generator(
			"spiral_stairs",
			level.generator_system.default_settings("spiral_stairs"),
			Transform3D(Basis.IDENTITY, Vector3(40, 0, 0))
		)
	if level.has_method("hollow_brush_by_id"):
		var shell = level.create_brush_from_info(
			{"shape": 0, "size": Vector3(4, 4, 4), "center": Vector3(50, 2, 0)}
		)
		level.hollow_brush_by_id(str(shell.brush_id), 0.25)
	(
		level
		. create_brush_from_info(
			{
				"shape": 0,
				"size": Vector3(1, 1, 1),
				"center": Vector3(30, 2, 0),
				"operation": CSGShape3D.OPERATION_SUBTRACTION,
				"pending": true,
			}
		)
	)
	(
		level
		. entity_system
		. restore_entity_from_info(
			{
				"name": "Note",
				"entity_type": "note",
				"properties":
				{"title": "Check", "body": "", "kind": "To Do", "author": "", "done": false},
				"transform": Transform3D(Basis.IDENTITY, Vector3(30, 3, 0)),
			}
		)
	)
	if level.get("validation_system"):
		var finding := {"type": "validate", "message": "kept", "node": box}
		HFAcceptedFindings.accept(level, finding, "kept for the test")
	if level.visgroup_system and level.visgroup_system.has_method("save_view"):
		level.visgroup_system.save_view("everything")
	if level.paint_layers and not level.paint_layers.layers.is_empty():
		level.paint_layers.layers[0].set_cell(Vector2i(2, 2), true)
	level.create_duplicate_array(PackedStringArray([str(box.brush_id)]), 2, Vector3(3, 0, 0))
	var wall = level.create_brush_from_info(
		{"shape": 0, "size": Vector3(4, 3, 0.5), "center": Vector3(60, 1.5, 0)}
	)
	(
		level
		. create_brush_from_info(
			{
				"shape": 0,
				"size": Vector3(1, 2, 1),
				"center": Vector3(60, 1, 0),
				"operation": CSGShape3D.OPERATION_SUBTRACTION,
				"pending": true,
			}
		)
	)
	if wall != null:
		level.commit_cuts()
	# Per brush bake options are kept as metadata, written only when set.
	if level.brush_system.has_method("set_brushes_cast_shadow"):
		level.brush_system.set_brushes_cast_shadow([str(box.brush_id)], 0)
		level.brush_system.set_brushes_lightmap_scale([str(box.brush_id)], 2.0)
	await tree.process_frame
