extends GutTest

## Hidden faces (#1719): a face nobody will see, left out of the bake's mesh and
## lightmap and kept in its collision, found against solids, saved, and sent out
## to a `.map` as `skip`.

const HFHiddenFaces = preload("res://addons/hammerforge/hf_hidden_faces.gd")
const HFHiddenFaceSearch = preload("res://addons/hammerforge/hf_hidden_face_search.gd")
const HFConvexClip = preload("res://addons/hammerforge/hf_convex_clip.gd")
const LEVEL := "user://test_hidden_faces.hflevel"
const MAP := "user://test_hidden_faces.map"

var said: Array = []


func after_each():
	for path in [LEVEL, MAP]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _fresh_root() -> LevelRoot:
	var root := LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	said = []
	root.user_message.connect(func(text, _level): said.append(text))
	return root


func _box(root: LevelRoot, brush_id: String, size: Vector3, at: Vector3, info := {}) -> DraftBrush:
	var record := {
		"shape": LevelRoot.BrushShape.BOX,
		"size": size,
		"center": at,
		"operation": CSGShape3D.OPERATION_UNION,
		"brush_id": brush_id,
	}
	record.merge(info, true)
	return root.create_brush_from_info(record)


## The index of the face of `brush` whose normal is `normal`.
static func _face_facing(brush: DraftBrush, normal: Vector3) -> int:
	for i in brush.faces.size():
		if brush.faces[i].normal.dot(normal) > 0.99:
			return i
	return -1


## The triangles of every visual mesh under `node` whose corners all lie on the
## plane y = `height`, as their area.
static func _drawn_area_at(node: Node, height: float) -> float:
	var area := 0.0
	for mesh_node in _meshes(node):
		var mesh: Mesh = mesh_node.mesh
		for s in mesh.get_surface_count():
			area += _area_at(mesh_node.global_transform, mesh.surface_get_arrays(s), height)
	return area


## The same for the collision triangles under `node`.
static func _held_area_at(node: Node, height: float) -> float:
	var area := 0.0
	for shape_node in _shapes(node):
		var shape: Shape3D = shape_node.shape
		if shape is ConcavePolygonShape3D:
			var faces: PackedVector3Array = (shape as ConcavePolygonShape3D).get_faces()
			var place: Transform3D = shape_node.global_transform
			for i in range(0, faces.size(), 3):
				area += _triangle_area_at(place, faces[i], faces[i + 1], faces[i + 2], height)
	return area


static func _area_at(place: Transform3D, arrays: Array, height: float) -> float:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = (
		arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] else PackedInt32Array()
	)
	var area := 0.0
	if indices.is_empty():
		for i in range(0, verts.size(), 3):
			area += _triangle_area_at(place, verts[i], verts[i + 1], verts[i + 2], height)
	else:
		for i in range(0, indices.size(), 3):
			area += _triangle_area_at(
				place, verts[indices[i]], verts[indices[i + 1]], verts[indices[i + 2]], height
			)
	return area


static func _triangle_area_at(
	place: Transform3D, a: Vector3, b: Vector3, c: Vector3, height: float
) -> float:
	var pa := place * a
	var pb := place * b
	var pc := place * c
	for point in [pa, pb, pc]:
		if absf(point.y - height) > 0.001:
			return 0.0
	return (pb - pa).cross(pc - pa).length() * 0.5


static func _meshes(node: Node, out: Array = []) -> Array:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append(node)
	for child in node.get_children():
		_meshes(child, out)
	return out


static func _shapes(node: Node, out: Array = []) -> Array:
	if node is CollisionShape3D and (node as CollisionShape3D).shape != null:
		out.append(node)
	for child in node.get_children():
		_shapes(child, out)
	return out


static func _wears_hidden(node: Node) -> bool:
	for mesh_node in _meshes(node):
		if HFHiddenFaces.has_hidden_surface(mesh_node.mesh):
			return true
	return false


## A 4 x 1 x 4 floor whose underside is at y = 0, baked, then baked again with the
## underside Hidden. The underside's area drawn and held, before and after.
func _bake_floor_both_ways(root: LevelRoot) -> Dictionary:
	var floor_brush := _box(root, "floor", Vector3(4, 1, 4), Vector3(0, 0.5, 0))
	await root.bake(true, false, 0)
	var before := {
		"drawn": _drawn_area_at(root.baked_container, 0.0),
		"held": _held_area_at(root.baked_container, 0.0),
	}
	floor_brush.faces[_face_facing(floor_brush, Vector3.DOWN)].face_type = FaceData.FaceType.HIDDEN
	floor_brush.rebuild_preview()
	root.tag_brush_dirty("floor")
	await root.bake(true, false, 0)
	var after := {
		"drawn": _drawn_area_at(root.baked_container, 0.0),
		"held": _held_area_at(root.baked_container, 0.0),
	}
	return {"before": before, "after": after}


func test_a_hidden_underside_is_not_drawn_and_still_collides_on_the_face_path():
	var root := _fresh_root()
	var areas: Dictionary = await _bake_floor_both_ways(root)
	assert_almost_eq(areas["before"]["drawn"], 16.0, 0.01, "fixture: the underside is drawn")
	assert_almost_eq(areas["after"]["drawn"], 0.0, 0.001, "Hidden: no triangle on it")
	assert_almost_eq(areas["after"]["held"], areas["before"]["held"], 0.001, "same collision")
	assert_almost_eq(areas["after"]["held"], 16.0, 0.01)
	assert_false(_wears_hidden(root.baked_container), "the stripes never reach the bake")


func test_the_same_on_the_csg_path_with_a_cut_in_the_level():
	var root := _fresh_root()
	_box(
		root,
		"notch",
		Vector3(1, 1, 1),
		Vector3(2, 1, 2),
		{"operation": CSGShape3D.OPERATION_SUBTRACTION}
	)
	var areas: Dictionary = await _bake_floor_both_ways(root)
	assert_gt(areas["before"]["drawn"], 14.0, "fixture: the underside is drawn")
	assert_almost_eq(areas["after"]["drawn"], 0.0, 0.001, "Hidden: no triangle on it")
	assert_almost_eq(areas["after"]["held"], areas["before"]["held"], 0.001, "same collision")
	assert_false(_wears_hidden(root.baked_container))


func test_the_same_with_face_materials_off():
	var root := _fresh_root()
	root.bake_use_face_materials = false
	_box(
		root,
		"notch",
		Vector3(1, 1, 1),
		Vector3(2, 1, 2),
		{"operation": CSGShape3D.OPERATION_SUBTRACTION}
	)
	var areas: Dictionary = await _bake_floor_both_ways(root)
	assert_almost_eq(areas["after"]["drawn"], 0.0, 0.001, "Hidden: no triangle on it")
	assert_almost_eq(areas["after"]["held"], areas["before"]["held"], 0.001, "same collision")


func test_the_bake_says_how_many_faces_and_how_much_area_it_left_out():
	var root := _fresh_root()
	await _bake_floor_both_ways(root)
	var left: Dictionary = root.bake_system.last_hidden_faces
	assert_eq(int(left.get("faces", 0)), 1)
	assert_almost_eq(float(left.get("area", 0.0)), 16.0, 0.01)
	var lines := said.filter(func(text): return str(text).contains("Hidden face"))
	assert_eq(lines.size(), 1, str(said))
	if not lines.is_empty():
		assert_string_contains(str(lines[0]), "left out 1 Hidden face")
		assert_string_contains(str(lines[0]), "16.0 square metres")


func test_a_hidden_face_wears_the_level_s_stripes_in_the_editor():
	var root := _fresh_root()
	var box := _box(root, "box", Vector3.ONE, Vector3(0, 0.5, 0))
	var bottom := _face_facing(box, Vector3.DOWN)
	box.faces[bottom].face_type = FaceData.FaceType.HIDDEN
	box.rebuild_preview()
	var look: Material = root.material_manager.hidden_face_material()
	assert_true(HFHiddenFaces.is_hidden_material(look))
	assert_true(HFHiddenFaces.has_hidden_surface(box.mesh_instance.mesh), "a box draws its faces")
	var surfaces: Array = []
	for i in box.mesh_instance.mesh.get_surface_count():
		surfaces.append(box.mesh_instance.mesh.surface_get_material(i))
	assert_true(surfaces.has(look), "the level's own look")
	root.set_view_filter("hidden_faces", true)
	assert_false(look.get_shader_parameter("shown"), "View Filters hides the stripes")
	root.set_view_filter("hidden_faces", false)
	assert_true(look.get_shader_parameter("shown"))


func test_a_material_laid_on_a_hidden_face_shows_it_and_the_slot_waits_under_it():
	var root := _fresh_root()
	root.set_materials([StandardMaterial3D.new(), StandardMaterial3D.new()])
	var box := _box(root, "box", Vector3.ONE, Vector3.ZERO)
	box.faces[0].material_idx = 1
	root.face_selection = {"box": [0]}
	assert_eq(root.set_selected_faces_hidden(true), 1)
	assert_true(box.faces[0].is_hidden())
	assert_eq(box.faces[0].material_idx, 1, "the slot is kept under it")
	root.assign_material_to_faces_by_id("box", [0], 1)
	assert_false(box.faces[0].is_hidden(), "the same material shows it again")


func test_hidden_goes_where_the_texture_goes_but_not_onto_a_cut_s_cap():
	var source := FaceData.new()
	source.face_type = FaceData.FaceType.HIDDEN
	var copy := FaceData.new()
	copy.copy_appearance_from(source)
	assert_true(copy.is_hidden(), "Alt+T, a resize and a clip carry it")
	assert_false(copy.appearance_matches(FaceData.new()))
	var root := _fresh_root()
	var box := _box(root, "box", Vector3(2, 2, 2), Vector3.ZERO)
	for face in box.faces:
		face.face_type = FaceData.FaceType.HIDDEN
	var halves: Dictionary = HFConvexClip.split(box.faces, Plane(Vector3.RIGHT, 0.0))
	var caps := 0
	for face in halves["front"]:
		if not face.is_hidden():
			caps += 1
	assert_eq(caps, 1, "the cut opens new surface, there to be seen")


func test_hidden_survives_a_save_and_a_load_and_an_older_file_has_none():
	var data := FaceData.new()
	data.face_type = FaceData.FaceType.HIDDEN
	assert_eq(FaceData.from_dict(data.to_dict()).face_type, FaceData.FaceType.HIDDEN)
	assert_false(FaceData.new().to_dict().has("face_type"), "a plain face writes what it did")
	assert_eq(FaceData.from_dict({"face_type": 7}).face_type, FaceData.FaceType.NORMAL)
	var root := _fresh_root()
	var box := _box(root, "box", Vector3.ONE, Vector3.ZERO)
	box.faces[2].face_type = FaceData.FaceType.HIDDEN
	assert_eq(root.save_hflevel(LEVEL, true), OK)
	await _finish_saving(root)
	var again := _fresh_root()
	assert_true(again.load_hflevel(LEVEL))
	var loaded: DraftBrush = again.brush_system.find_brush_by_id("box")
	assert_not_null(loaded)
	if loaded:
		var hidden := []
		for i in loaded.faces.size():
			if loaded.faces[i].is_hidden():
				hidden.append(i)
		assert_eq(hidden, [2])


func test_a_map_round_trip_writes_skip_and_reads_it_back_hidden():
	var root := _fresh_root()
	var box := _box(root, "box", Vector3(2, 2, 2), Vector3(0, 1, 0))
	var bottom := _face_facing(box, Vector3.DOWN)
	box.faces[bottom].face_type = FaceData.FaceType.HIDDEN
	assert_eq(root.export_map(MAP), OK)
	var text := FileAccess.get_file_as_string(MAP)
	assert_eq(text.count(" skip "), 1, "one face named skip:\n%s" % text)
	var again := _fresh_root()
	assert_eq(again.import_map(MAP), OK)
	var hidden := 0
	var downward := 0
	for brush in again.draft_brushes_node.get_children():
		for face in brush.faces:
			if face.is_hidden():
				hidden += 1
				if face.normal.y < -0.99:
					downward += 1
	assert_eq(hidden, 1)
	assert_eq(downward, 1, "the underside")
	assert_true(HFHiddenFaces.is_map_name("COMMON/NODRAW"), "and the other names for it")


func test_faces_flat_against_a_solid_are_found_and_no_others():
	var root := _fresh_root()
	_box(root, "slab", Vector3(4, 1, 4), Vector3(0, 0.5, 0))
	var block := _box(root, "block", Vector3.ONE, Vector3(0, 1.5, 0))
	# Its underside is half over the slab's edge, so half of it can be seen.
	var ledge := _box(root, "ledge", Vector3(1, 1, 1), Vector3(2, 1.5, 0))
	# Against a cut and a trigger, which nobody sees as a wall.
	_box(
		root,
		"hole",
		Vector3(1, 1, 1),
		Vector3(-6, 1.5, 0),
		{"operation": CSGShape3D.OPERATION_SUBTRACTION}
	)
	var by_hole := _box(root, "by_hole", Vector3.ONE, Vector3(-6, 0.5, 0))
	var trigger := _box(root, "zone", Vector3.ONE, Vector3(6, 1.5, 0))
	trigger.set_meta("brush_entity_class", "trigger_once")
	var by_zone := _box(root, "by_zone", Vector3.ONE, Vector3(6, 0.5, 0))
	var found := HFHiddenFaceSearch.against_solids(
		root, [root.brush_system.find_brush_by_id("slab"), block, ledge, by_hole, by_zone]
	)
	assert_eq(found.keys(), ["block"], "only the block's underside: %s" % found)
	assert_eq(found.get("block", []), [_face_facing(block, Vector3.DOWN)])


func test_validate_hints_at_a_hidden_face_with_open_space_in_front():
	var root := _fresh_root()
	_box(root, "slab", Vector3(4, 1, 4), Vector3(0, 0.5, 0))
	var block := _box(root, "block", Vector3.ONE, Vector3(0, 1.5, 0))
	block.faces[_face_facing(block, Vector3.DOWN)].face_type = FaceData.FaceType.HIDDEN
	var report: Dictionary = root.validation_system.validate()
	assert_eq(_hints(report), 0, "against the slab: nothing to say")
	block.faces[_face_facing(block, Vector3.UP)].face_type = FaceData.FaceType.HIDDEN
	report = root.validation_system.validate()
	assert_eq(_hints(report), 1, "the top faces the sky")
	assert_false(str(report["issues"]).contains("Hidden face"), "a hint, not a fault in the count")


static func _hints(report: Dictionary) -> int:
	var count := 0
	for finding in report.get("findings", []):
		if str(finding.get("kind", "")) == "hidden_face_in_the_open":
			assert(int(finding.get("severity", -1)) == 0)
			count += 1
	return count


## The write runs on a thread of its own, so wait for it as the file system's
## own test does.
func _finish_saving(level: LevelRoot) -> void:
	var files = level.file_system
	for _i in 400:
		if files._hflevel_thread and files._hflevel_thread.is_alive():
			await get_tree().process_frame
			continue
		files.process_thread_queue()
		if not files._hflevel_thread and files._hflevel_pending.is_empty():
			return
		await get_tree().process_frame
