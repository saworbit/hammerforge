extends GutTest

## What a .map face line has to carry: the face's own texture and UV numbers,
## and one plane per flat surface rather than one per triangle of it.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const MapIOType = preload("res://addons/hammerforge/map_io.gd")
const QuakeAdapter = preload("res://addons/hammerforge/map_adapters/hf_map_quake.gd")

var root: LevelRoot


func before_each():
	root = LevelRootType.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	root.material_manager.clear()


func _make_material(mat_name: String) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.resource_name = mat_name
	return mat


func _box(brush_id: String) -> DraftBrush:
	return (
		root.create_brush_from_info(
			{"size": Vector3(32, 32, 32), "center": Vector3.ZERO, "brush_id": brush_id}
		)
		as DraftBrush
	)


## The face lines of the exported text, in order.
func _face_lines(text: String) -> Array:
	var out: Array = []
	for raw in text.split("\n"):
		var line: String = raw.strip_edges()
		if line.begins_with("("):
			out.append(line)
	return out


## The texture token of a face line: the word after the third closing bracket.
func _texture_of(line: String) -> String:
	var tail: String = line.substr(line.rfind(")") + 1).strip_edges()
	var parts := tail.split(" ", false)
	return str(parts[0]) if parts.size() > 0 else ""


# -- The texture name reaches the file ---------------------------------------


func test_an_assigned_material_is_written_on_every_face():
	root.add_material_to_palette(_make_material("bricks"))
	_box("b1")
	root.assign_material_to_whole_brushes(0, ["b1"])

	var lines := _face_lines(MapIOType.export_map_from_level(root, QuakeAdapter.new()))

	assert_eq(lines.size(), 6, "A box is six planes")
	for line in lines:
		assert_eq(_texture_of(line), "bricks", "Each face should name its material")


func test_an_unset_face_falls_back_to_the_default_texture():
	root.add_material_to_palette(_make_material("bricks"))
	_box("b1")

	var lines := _face_lines(MapIOType.export_map_from_level(root, QuakeAdapter.new()))

	for line in lines:
		assert_eq(_texture_of(line), "__default", "An unassigned face has no material to name")


func test_an_out_of_range_index_falls_back_to_the_default_texture():
	var brush := _box("b1")
	for face in brush.faces:
		face.material_idx = 7

	var lines := _face_lines(MapIOType.export_map_from_level(root, QuakeAdapter.new()))

	for line in lines:
		assert_eq(_texture_of(line), "__default", "An index past the palette names nothing")


func test_a_name_with_a_space_is_written_as_one_token():
	assert_eq(MapIOType.texture_token("Red Brick"), "Red_Brick", "Spaces would split the field")
	assert_eq(MapIOType.texture_token("  padded  name "), "padded_name", "Runs collapse to one")
	assert_eq(MapIOType.texture_token(""), "__default", "An empty name has no token")


func test_the_uv_numbers_are_the_face_s_own():
	root.add_material_to_palette(_make_material("bricks"))
	var brush := _box("b1")
	root.assign_material_to_whole_brushes(0, ["b1"])
	for face in brush.faces:
		face.uv_offset = Vector2(8, 16)
		face.uv_scale = Vector2(2, 4)
		face.uv_rotation = 45.0

	var lines := _face_lines(MapIOType.export_map_from_level(root, QuakeAdapter.new()))

	for line in lines:
		assert_true(
			line.ends_with("bricks 8 16 45 2 4"), "Face line should carry its UVs, got: %s" % line
		)


# -- One plane per flat surface ----------------------------------------------


func test_a_cylinder_exports_one_plane_per_wall_and_one_per_cap():
	for sides in [6, 8, 16]:
		root.clear_brushes()
		root.create_brush_from_info(
			{
				"size": Vector3(32, 32, 32),
				"center": Vector3.ZERO,
				"shape": LevelRootType.BrushShape.CYLINDER,
				"sides": sides
			}
		)
		var lines := _face_lines(MapIOType.export_map_from_level(root, QuakeAdapter.new()))
		assert_eq(lines.size(), sides + 2, "A %d sided prism needs %d planes" % [sides, sides + 2])


func test_no_two_cylinder_planes_are_the_same_plane():
	root.create_brush_from_info(
		{
			"size": Vector3(32, 32, 32),
			"center": Vector3.ZERO,
			"shape": LevelRootType.BrushShape.CYLINDER,
			"sides": 16
		}
	)
	var lines := _face_lines(MapIOType.export_map_from_level(root, QuakeAdapter.new()))

	var seen: Dictionary = {}
	for line in lines:
		var plane := _plane_of(line)
		var key := "%s|%.2f" % [MapIOType.normal_key(plane.normal), plane.d]
		assert_false(seen.has(key), "Two face lines describe the same plane: %s" % line)
		seen[key] = true


func test_every_cylinder_plane_faces_away_from_the_brush():
	root.create_brush_from_info(
		{
			"size": Vector3(32, 32, 32),
			"center": Vector3.ZERO,
			"shape": LevelRootType.BrushShape.CYLINDER,
			"sides": 8
		}
	)
	var lines := _face_lines(MapIOType.export_map_from_level(root, QuakeAdapter.new()))

	for line in lines:
		var plane := _plane_of(line)
		assert_gt(plane.d, 0.0, "The plane should be reached going out from the centre: %s" % line)


## The plane a face line describes, read the way a .map reader reads it.
func _plane_of(line: String) -> Plane:
	var re := RegEx.new()
	re.compile("\\(([^\\)]+)\\)")
	var matches := re.search_all(line)
	var pts: Array = []
	for i in range(3):
		var parts := matches[i].get_string(1).strip_edges().split(" ", false)
		pts.append(Vector3(float(parts[0]), float(parts[1]), float(parts[2])))
	var normal: Vector3 = (pts[1] - pts[0]).cross(pts[2] - pts[0]).normalized()
	return Plane(normal, normal.dot(pts[0]))


# -- Round trip ---------------------------------------------------------------


func test_a_box_material_survives_an_export_and_import():
	root.add_material_to_palette(_make_material("floor"))
	root.add_material_to_palette(_make_material("wall"))
	var brush := _box("b1")
	root.assign_material_to_whole_brushes(1, ["b1"])
	var path := "user://hf_test_map_fidelity.map"
	assert_eq(root.export_map(path), OK, "Export should succeed")

	assert_eq(root.import_map(path), OK, "Import should succeed")

	var imported: Array = root.get_all_draft_brushes()
	assert_eq(imported.size(), 1, "One brush should come back")
	for face in imported[0].faces:
		assert_eq(face.material_idx, 1, "Each face should point back at 'wall'")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_per_face_materials_survive_an_export_and_import():
	root.add_material_to_palette(_make_material("floor"))
	root.add_material_to_palette(_make_material("wall"))
	var brush := _box("b1")
	root.assign_material_to_whole_brushes(1, ["b1"])
	# Face 2 is the top of the box. Give it a different material from the rest.
	brush.faces[2].material_idx = 0
	var top_normal: Vector3 = brush.faces[2].normal
	var path := "user://hf_test_map_fidelity_perface.map"
	root.export_map(path)

	root.import_map(path)

	var imported: Array = root.get_all_draft_brushes()
	var found_top := false
	for face in imported[0].faces:
		if face.normal.dot(top_normal) > 0.99:
			found_top = true
			assert_eq(face.material_idx, 0, "The top should come back as 'floor'")
		else:
			assert_eq(face.material_idx, 1, "and every other face as 'wall'")
	assert_true(found_top, "The top face should be among the imported faces")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_a_texture_the_palette_does_not_hold_leaves_the_face_unset():
	root.add_material_to_palette(_make_material("wall"))
	var brush := _box("b1")
	root.assign_material_to_whole_brushes(0, ["b1"])
	var path := "user://hf_test_map_fidelity_unknown.map"
	root.export_map(path)
	# The palette the file was written against is gone by the time it is read.
	root.material_manager.clear()
	root.add_material_to_palette(_make_material("something_else"))

	root.import_map(path)

	var imported: Array = root.get_all_draft_brushes()
	assert_eq(imported.size(), 1, "The brush should still import")
	for face in imported[0].faces:
		assert_eq(face.material_idx, -1, "A texture the palette lacks leaves the face unset")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_the_texture_token_is_read_off_a_face_line():
	var parsed := MapIOType.parse_map_text(
		(
			"{
"
			+ '"classname" "worldspawn"
'
			+ "{
"
			+ "( 16 -16 -16 ) ( 16 16 -16 ) ( 16 16 16 ) my_tex 1 2 3 4 5
"
			+ "}
"
			+ "}"
		)
	)

	assert_eq(parsed["errors"].size(), 0, "The line should parse")
