extends GutTest

const MapIO = preload("res://addons/hammerforge/map_io.gd")
const LevelRoot = preload("res://addons/hammerforge/level_root.gd")
const HFMapAdapter = preload("res://addons/hammerforge/map_adapters/hf_map_adapter.gd")
const HFMapQuake = preload("res://addons/hammerforge/map_adapters/hf_map_quake.gd")
const HFMapValve220 = preload("res://addons/hammerforge/map_adapters/hf_map_valve220.gd")
const FaceData = preload("res://addons/hammerforge/face_data.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")
const DraftEntity = preload("res://addons/hammerforge/draft_entity.gd")

# ===========================================================================
# Quake adapter tests
# ===========================================================================


func test_quake_format_name():
	var adapter = HFMapQuake.new()
	assert_eq(adapter.format_name(), "Classic Quake")


func test_quake_format_face_line_basic():
	var adapter = HFMapQuake.new()
	var a = Vector3(0, 0, 0)
	var b = Vector3(64, 0, 0)
	var c = Vector3(64, 64, 0)
	var line = adapter.format_face_line(a, b, c, "brick", null)
	assert_string_contains(line, "( 0 0 0 )")
	assert_string_contains(line, "( 64 0 0 )")
	assert_string_contains(line, "( 64 64 0 )")
	assert_string_contains(line, "brick")
	assert_string_contains(line, "0 0 0 1 1")


func test_quake_format_face_line_with_face_data():
	# Quake adapter ignores face_data — output should be the same
	var adapter = HFMapQuake.new()
	var fd = FaceData.new()
	fd.uv_scale = Vector2(2.0, 2.0)
	fd.uv_offset = Vector2(16.0, 32.0)
	var a = Vector3(0, 0, 0)
	var b = Vector3(32, 0, 0)
	var c = Vector3(32, 32, 0)
	var line = adapter.format_face_line(a, b, c, "stone", fd)
	# Classic Quake always uses 0 0 0 1 1 for UV params
	assert_string_contains(line, "0 0 0 1 1")


func test_quake_format_face_line_fractional_coords():
	var adapter = HFMapQuake.new()
	var a = Vector3(0.5, 1.25, -3.75)
	var b = Vector3(10, 0, 0)
	var c = Vector3(0, 10, 0)
	var line = adapter.format_face_line(a, b, c, "tex", null)
	assert_string_contains(line, "( 0.5 1.25 -3.75 )")


# ===========================================================================
# Valve 220 adapter tests
# ===========================================================================


func test_valve220_format_name():
	var adapter = HFMapValve220.new()
	assert_eq(adapter.format_name(), "Valve 220")


func test_valve220_format_face_line_no_face_data():
	var adapter = HFMapValve220.new()
	var a = Vector3(0, 0, 0)
	var b = Vector3(64, 0, 0)
	var c = Vector3(64, 64, 0)
	var line = adapter.format_face_line(a, b, c, "brick", null)
	# Should contain bracket-delimited UV axes
	assert_string_contains(line, "[")
	assert_string_contains(line, "]")
	assert_string_contains(line, "brick")
	# No face data → default UV axes and zero offsets
	assert_string_contains(line, "( 0 0 0 )")
	assert_string_contains(line, "( 64 0 0 )")


func test_valve220_format_face_line_with_face_data():
	var adapter = HFMapValve220.new()
	var fd = FaceData.new()
	fd.uv_projection = FaceData.UVProjection.PLANAR_Z
	fd.uv_scale = Vector2(0.5, 0.5)
	fd.uv_offset = Vector2(16.0, 32.0)
	fd.uv_rotation = 45.0
	var a = Vector3(0, 0, 0)
	var b = Vector3(64, 0, 0)
	var c = Vector3(64, 64, 0)
	var line = adapter.format_face_line(a, b, c, "metal", fd)
	assert_string_contains(line, "metal")
	assert_string_contains(line, "16")
	assert_string_contains(line, "32")
	assert_string_contains(line, "45")
	assert_string_contains(line, "0.5")


func test_valve220_auto_axes_floor():
	var adapter = HFMapValve220.new()
	var axes = adapter._auto_axes(Vector3.UP)
	# Floor → u=RIGHT, v=BACK
	assert_eq(axes[0], Vector3.RIGHT)
	assert_eq(axes[1], Vector3.BACK)


func test_valve220_auto_axes_east_wall():
	var adapter = HFMapValve220.new()
	var axes = adapter._auto_axes(Vector3.RIGHT)
	# East wall → u=BACK, v=UP
	assert_eq(axes[0], Vector3.BACK)
	assert_eq(axes[1], Vector3.UP)


func test_valve220_auto_axes_north_wall():
	var adapter = HFMapValve220.new()
	var axes = adapter._auto_axes(Vector3.FORWARD)
	# North wall → u=RIGHT, v=UP
	assert_eq(axes[0], Vector3.RIGHT)
	assert_eq(axes[1], Vector3.UP)


func test_valve220_compute_axes_planar_x():
	var adapter = HFMapValve220.new()
	var fd = FaceData.new()
	fd.uv_projection = FaceData.UVProjection.PLANAR_X
	var axes = adapter._compute_axes_from_projection(Vector3.RIGHT, fd)
	assert_eq(axes[0], Vector3.BACK)
	assert_eq(axes[1], Vector3.UP)


func test_valve220_compute_axes_planar_y():
	var adapter = HFMapValve220.new()
	var fd = FaceData.new()
	fd.uv_projection = FaceData.UVProjection.PLANAR_Y
	var axes = adapter._compute_axes_from_projection(Vector3.UP, fd)
	assert_eq(axes[0], Vector3.RIGHT)
	assert_eq(axes[1], Vector3.BACK)


func test_valve220_compute_axes_box_uv():
	var adapter = HFMapValve220.new()
	var fd = FaceData.new()
	fd.uv_projection = FaceData.UVProjection.BOX_UV
	# Normal pointing up → should resolve to PLANAR_Y
	var axes = adapter._compute_axes_from_projection(Vector3.UP, fd)
	assert_eq(axes[0], Vector3.RIGHT)
	assert_eq(axes[1], Vector3.BACK)


# ===========================================================================
# Entity property formatting
# ===========================================================================


func test_entity_properties_formatting():
	var adapter = HFMapAdapter.new()
	var props = {"classname": "light", "origin": "0 64 0"}
	var lines = adapter.format_entity_properties(props)
	assert_eq(lines.size(), 2)
	for line in lines:
		assert_true(line.begins_with('"'))
		assert_true(line.ends_with('"'))


# ===========================================================================
# Adapter base class
# ===========================================================================


func test_base_adapter_format_name():
	var adapter = HFMapAdapter.new()
	assert_eq(adapter.format_name(), "Base")


func test_base_adapter_format_face_line_returns_empty():
	var adapter = HFMapAdapter.new()
	var line = adapter.format_face_line(Vector3.ZERO, Vector3.RIGHT, Vector3.UP, "tex", null)
	assert_eq(line, "")


# ===========================================================================
# Format vec3 consistency
# ===========================================================================


func test_adapter_format_vec3_matches_snapped():
	# Verify adapter's _format_vec3 matches the snapped style (3 decimals)
	var result = HFMapAdapter._format_vec3(Vector3(1.5, -2.25, 0.0))
	assert_string_contains(result, "1.5")
	assert_string_contains(result, "-2.25")


func test_valve220_fmt_float_integer():
	var result = HFMapValve220._fmt_float(5.0)
	assert_eq(result, "5")


func test_custom_brush_export_emits_real_face_planes():
	var brush = DraftBrush.new()
	add_child_autoqfree(brush)
	brush.shape = LevelRoot.BrushShape.CUSTOM
	var face = FaceData.new()
	face.local_verts = PackedVector3Array([Vector3(0, 0, 0), Vector3(8, 0, 0), Vector3(0, 8, 0)])
	var faces: Array[FaceData] = []
	faces.append(face)
	brush.faces = faces
	assert_eq(brush.faces.size(), 1)
	var lines: Array[String] = MapIO._brush_to_map_lines(brush)
	assert_eq(lines.size(), 1)
	assert_string_contains(lines[0], "( 0 0 0 )")
	assert_string_contains(lines[0], "( 8 0 0 )")
	assert_string_contains(lines[0], "( 0 8 0 )")


func test_valve220_fmt_float_fractional():
	var result = HFMapValve220._fmt_float(0.333)
	assert_true(result.begins_with("0.33"))


func test_parse_tilted_brush_imports_as_custom_faces():
	var map_text := (
		"{\n"
		+ '"classname" "worldspawn"\n'
		+ "{\n"
		+ "( 0 0 0 ) ( 10 0 0 ) ( 0 10 0 ) brick 0 0 0 1 1\n"
		+ "( 0 0 0 ) ( 0 10 0 ) ( 0 0 10 ) brick 0 0 0 1 1\n"
		+ "( 0 0 0 ) ( 0 0 10 ) ( 10 0 0 ) brick 0 0 0 1 1\n"
		+ "( 10 0 0 ) ( 0 0 10 ) ( 0 10 0 ) brick 0 0 0 1 1\n"
		+ "}\n"
		+ "}\n"
	)
	var parsed: Dictionary = MapIO.parse_map_text(map_text)
	var brushes: Array = parsed.get("brushes", [])
	assert_eq(brushes.size(), 1)
	assert_eq(int(brushes[0]["shape"]), LevelRoot.BrushShape.CUSTOM)
	assert_true(brushes[0].has("faces"))
	assert_gte((brushes[0]["faces"] as Array).size(), 3)


func test_parse_map_text_worldspawn_and_point_entity():
	var map_text := (
		"{\n"
		+ '"classname" "worldspawn"\n'
		+ "{\n"
		+ "( 0 0 0 ) ( 64 0 0 ) ( 64 64 0 ) brick 0 0 0 1 1\n"
		+ "( 0 0 16 ) ( 64 64 16 ) ( 64 0 16 ) brick 0 0 0 1 1\n"
		+ "}\n"
		+ "}\n"
		+ "{\n"
		+ '"classname" "light"\n'
		+ '"origin" "32 32 8"\n'
		+ "}\n"
	)
	var parsed: Dictionary = MapIO.parse_map_text(map_text)
	assert_eq(
		(parsed.get("brushes", []) as Array).size(), 1, "Worldspawn brush becomes authored geometry"
	)
	var entities: Array = parsed.get("entities", [])
	assert_eq(entities.size(), 1, "Point entities stay in the entity list")
	assert_eq(entities[0]["classname"], "light")
	assert_eq(str(entities[0]["properties"]["origin"]), "32 32 8")


func test_entity_export_includes_entity_data_keys():
	var entity = DraftEntity.new()
	add_child_autoqfree(entity)
	entity.entity_type = "player_start"
	entity.entity_data = {"angle": 90, "primary": "1", "targetname": "start1"}
	entity.global_position = Vector3(8, 2, 4)
	var lines: Array[String] = MapIO._entity_to_map_lines(entity)
	var text := "\n".join(lines)
	assert_string_contains(text, '"classname" "player_start"')
	assert_string_contains(text, '"angle" "90"')
	assert_string_contains(text, '"primary" "1"')
	assert_string_contains(text, '"targetname" "start1"')
	assert_true(
		text.contains('"origin" "8 2 4"') or text.contains('"origin" "8.0 2.0 4.0"'),
		"Origin should come from the entity transform",
	)


func test_entity_export_skips_empty_entity_data_and_origin_override():
	var entity = DraftEntity.new()
	add_child_autoqfree(entity)
	entity.entity_type = "light"
	entity.entity_data = {"origin": "0 0 0", "targetname": "", "brightness": "200"}
	entity.global_position = Vector3(1, 2, 3)
	var text := "\n".join(MapIO._entity_to_map_lines(entity))
	assert_true(
		text.contains('"origin" "1 2 3"') or text.contains('"origin" "1.0 2.0 3.0"'),
		"Origin should come from the entity transform",
	)
	assert_true(text.find('"origin" "0 0 0"') < 0, "Transform origin wins over entity_data origin")
	assert_true(text.find("targetname") < 0, "Empty entity_data values are omitted")
	assert_string_contains(text, '"brightness" "200"')


func _box_faces_map_text() -> String:
	return (
		"{\n"
		+ "( 0 0 0 ) ( 64 0 0 ) ( 64 64 0 ) brick 0 0 0 1 1\n"
		+ "( 0 0 16 ) ( 64 64 16 ) ( 64 0 16 ) brick 0 0 0 1 1\n"
		+ "( 0 0 0 ) ( 0 0 16 ) ( 64 0 0 ) brick 0 0 0 1 1\n"
		+ "( 64 0 0 ) ( 64 0 16 ) ( 64 64 0 ) brick 0 0 0 1 1\n"
		+ "}\n"
	)


func test_parse_func_detail_sets_brush_entity_class():
	var map_text := (
		"{\n"
		+ '"classname" "worldspawn"\n'
		+ "}\n"
		+ "{\n"
		+ '"classname" "func_detail"\n'
		+ _box_faces_map_text()
		+ "}\n"
	)
	var parsed: Dictionary = MapIO.parse_map_text(map_text)
	var brushes: Array = parsed.get("brushes", [])
	assert_eq(brushes.size(), 1)
	assert_eq(str(brushes[0].get("brush_entity_class", "")), "func_detail")


func test_parse_worldspawn_brush_has_no_entity_class():
	var map_text := "{\n" + '"classname" "worldspawn"\n' + _box_faces_map_text() + "}\n"
	var parsed: Dictionary = MapIO.parse_map_text(map_text)
	var brushes: Array = parsed.get("brushes", [])
	assert_eq(brushes.size(), 1)
	assert_eq(str(brushes[0].get("brush_entity_class", "")), "")


func _make_export_root(brushes: Array) -> Node3D:
	var script := GDScript.new()
	script.source_code = """
extends Node3D
func _iter_pick_nodes():
	return get_children()
func is_entity_node(_n):
	return false
"""
	script.reload()
	var root := Node3D.new()
	root.set_script(script)
	add_child_autoqfree(root)
	for brush in brushes:
		root.add_child(brush)
	return root


func _plane_lines(text: String) -> Array[String]:
	var out: Array[String] = []
	for line in text.split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.begins_with("( "):
			out.append(trimmed)
	return out


func _plane_axis_key(line: String) -> String:
	var points: Array[Vector3] = []
	var rest := line
	for _i in range(3):
		var open_at := rest.find("(")
		var close_at := rest.find(")", open_at)
		var body := rest.substr(open_at + 1, close_at - open_at - 1).strip_edges()
		var parts := body.split(" ", false)
		points.append(Vector3(float(parts[0]), float(parts[1]), float(parts[2])))
		rest = rest.substr(close_at + 1)
	if is_equal_approx(points[0].x, points[1].x) and is_equal_approx(points[1].x, points[2].x):
		return "+x" if points[0].x > 0.0 else "-x"
	if is_equal_approx(points[0].y, points[1].y) and is_equal_approx(points[1].y, points[2].y):
		return "+y" if points[0].y > 0.0 else "-y"
	return "+z" if points[0].z > 0.0 else "-z"


func _plane_u_offset(line: String) -> float:
	var open_at := line.find("[")
	var close_at := line.find("]", open_at)
	var body := line.substr(open_at + 1, close_at - open_at - 1).strip_edges()
	return float(body.split(" ", false)[3])


func test_box_face_data_exports_onto_its_own_plane():
	var brush := DraftBrush.new()
	brush.shape = LevelRoot.BrushShape.BOX
	brush.size = Vector3(32, 32, 32)
	var root := _make_export_root([brush])
	assert_eq(brush.faces.size(), 6, "Adding the box to the tree builds its six faces")
	# One recognisable U offset per face, in _build_box_faces order.
	for i in range(brush.faces.size()):
		brush.faces[i].uv_offset = Vector2(float(i + 1) * 8.0, 0.0)
	var text := MapIO.export_map_from_level(root, HFMapValve220.new())
	var lines := _plane_lines(text)
	assert_eq(lines.size(), 6, "A box exports six planes")
	# _build_box_faces order: Right, Left, Top, Bottom, Front, Back.
	var expected := {"+x": 8.0, "-x": 16.0, "+y": 24.0, "-y": 32.0, "+z": 40.0, "-z": 48.0}
	var seen := {}
	for line in lines:
		var key := _plane_axis_key(line)
		seen[key] = true
		assert_almost_eq(
			_plane_u_offset(line),
			float(expected[key]),
			0.001,
			"Plane %s must carry the UV offset of the face with that normal" % key
		)
	assert_eq(seen.size(), 6, "Every box plane must be exported exactly once")


func test_export_writes_func_detail_as_own_entity_block():
	var world := DraftBrush.new()
	world.shape = LevelRoot.BrushShape.BOX
	world.size = Vector3(32, 32, 32)
	var detail := DraftBrush.new()
	detail.shape = LevelRoot.BrushShape.BOX
	detail.size = Vector3(16, 16, 16)
	detail.set_brush_entity_class("func_detail")
	var text := MapIO.export_map_from_level(_make_export_root([world, detail]))
	assert_string_contains(text, '"classname" "worldspawn"')
	assert_string_contains(text, '"classname" "func_detail"')
	var world_idx := text.find('"classname" "worldspawn"')
	var detail_idx := text.find('"classname" "func_detail"')
	assert_gt(detail_idx, world_idx, "Brush entity block comes after worldspawn")
