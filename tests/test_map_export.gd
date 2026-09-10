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


# ===========================================================================
# Cutters must not export as solid worldspawn brushes (#243)
# ===========================================================================


## A root shaped like LevelRoot's containers: picking sees draft and pending
## brushes, and committed cutters are reachable only by name, exactly as the real
## one arranges them.
func _make_container_root() -> Node3D:
	var script := GDScript.new()
	script.source_code = """
extends Node3D
func _iter_pick_nodes():
	var nodes := []
	for container_name in ["DraftBrushes", "PendingCuts"]:
		var container = get_node_or_null(container_name)
		if container:
			nodes.append_array(container.get_children())
	return nodes
func is_entity_node(_n):
	return false
"""
	script.reload()
	var root := Node3D.new()
	root.set_script(script)
	add_child_autoqfree(root)
	for container_name in ["DraftBrushes", "PendingCuts", "CommittedCuts"]:
		var container := Node3D.new()
		container.name = container_name
		root.add_child(container)
	return root


func _add_box(root: Node3D, container_name: String, extent: float) -> DraftBrush:
	var brush := DraftBrush.new()
	brush.shape = LevelRoot.BrushShape.BOX
	brush.size = Vector3(extent, extent, extent) * 2.0
	root.get_node(container_name).add_child(brush)
	return brush


## The furthest any exported plane point sits from the origin on any axis. A box
## written at the origin reaches exactly its own half extent, so this says which
## brush the planes came from.
func _plane_point_reach(text: String) -> float:
	var reach := 0.0
	for line in _plane_lines(text):
		for point in _plane_points(line):
			var p: Vector3 = point
			reach = maxf(reach, maxf(absf(p.x), maxf(absf(p.y), absf(p.z))))
	return reach


func test_committed_cutter_is_not_exported_as_a_solid_brush():
	var root := _make_container_root()
	_add_box(root, "DraftBrushes", 5.0)
	var cutter := _add_box(root, "CommittedCuts", 1.0)
	cutter.set_meta("committed_cut", true)

	var text := MapIO.export_map_from_level(root)

	assert_eq(_plane_lines(text).size(), 6, "Only the solid may be written")
	assert_almost_eq(_plane_point_reach(text), 5.0, 0.001, "The planes are the solid's")


func test_subtraction_brush_is_not_exported_as_a_solid_brush():
	var root := _make_container_root()
	_add_box(root, "DraftBrushes", 5.0)
	var cutter := _add_box(root, "DraftBrushes", 1.0)
	cutter.operation = CSGShape3D.OPERATION_SUBTRACTION

	var text := MapIO.export_map_from_level(root)

	assert_eq(_plane_lines(text).size(), 6, "Only the solid may be written")
	assert_almost_eq(_plane_point_reach(text), 5.0, 0.001, "The planes are the solid's")


func test_pending_cutter_is_not_exported_as_a_solid_brush():
	var root := _make_container_root()
	_add_box(root, "DraftBrushes", 5.0)
	# Left on union on purpose: being in PendingCuts is what makes it a cutter.
	_add_box(root, "PendingCuts", 1.0)

	var text := MapIO.export_map_from_level(root)

	assert_eq(_plane_lines(text).size(), 6, "Only the solid may be written")
	assert_almost_eq(_plane_point_reach(text), 5.0, 0.001, "The planes are the solid's")


# ===========================================================================
# Face plane winding (#148)
# ===========================================================================


## Pull the three plane points out of a face line without a regex, so this
## helper stays readable next to the winding it is checking.
func _plane_points(line: String) -> Array:
	var points: Array = []
	for part in line.split("(", false):
		var close := part.find(")")
		if close < 0:
			continue
		var nums := part.substr(0, close).strip_edges().split(" ", false)
		if nums.size() < 3:
			continue
		points.append(Vector3(float(nums[0]), float(nums[1]), float(nums[2])))
		if points.size() == 3:
			break
	return points


func _first_plane_normal(line: String) -> Vector3:
	return MapIO._face_normal(_plane_points(line))


func _wrap_worldspawn(face_lines: Array) -> String:
	var text := "{\n" + '"classname" "worldspawn"' + "\n{\n"
	for line in face_lines:
		text += str(line) + "\n"
	return text + "}\n}\n"


func test_custom_face_planes_point_outward_like_box_planes():
	var brush := DraftBrush.new()
	add_child_autoqfree(brush)
	brush.shape = LevelRoot.BrushShape.BOX
	brush.size = Vector3(2, 2, 2)
	var box_lines: Array[String] = MapIO._box_to_map_lines(brush)
	brush.shape = LevelRoot.BrushShape.CUSTOM
	brush.faces = brush._build_box_faces()
	var face_lines: Array[String] = MapIO._faces_to_map_lines(brush)

	assert_eq(face_lines.size(), box_lines.size(), "Both paths write six planes")
	for i in range(box_lines.size()):
		var box_n := _first_plane_normal(box_lines[i])
		var face_n := _first_plane_normal(face_lines[i])
		assert_almost_eq(
			face_n.dot(box_n),
			1.0,
			0.001,
			"Face plane %d must point the same way as the box plane" % i
		)


func test_custom_face_plane_normal_matches_the_face_it_came_from():
	var brush := DraftBrush.new()
	add_child_autoqfree(brush)
	brush.shape = LevelRoot.BrushShape.CUSTOM
	brush.size = Vector3(2, 2, 2)
	brush.faces = brush._build_box_faces()
	var lines: Array[String] = MapIO._faces_to_map_lines(brush)
	# _build_box_faces order starts with Right (+X).
	assert_almost_eq(_first_plane_normal(lines[0]).x, 1.0, 0.001)


func _face_outward(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	# FaceData is clockwise from outside, so its normal is (c - a) x (b - a).
	return (c - a).cross(b - a).normalized()


func test_exported_plane_normal_matches_the_source_face_normal():
	var source := [Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(0, 10, 0)]
	var brush := DraftBrush.new()
	add_child_autoqfree(brush)
	brush.shape = LevelRoot.BrushShape.CUSTOM
	var face := FaceData.new()
	face.local_verts = PackedVector3Array(source)
	var faces: Array[FaceData] = []
	faces.append(face)
	brush.faces = faces
	var line: String = MapIO._faces_to_map_lines(brush)[0]
	var expected := _face_outward(source[0], source[1], source[2])
	assert_almost_eq(
		MapIO._face_normal(_plane_points(line)).dot(expected),
		1.0,
		0.001,
		"The written plane must face the same way as the face it came from"
	)


func test_tilted_hull_round_trip_keeps_face_winding():
	var brush := DraftBrush.new()
	add_child_autoqfree(brush)
	brush.shape = LevelRoot.BrushShape.CUSTOM
	var source := [
		[Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(0, 10, 0)],
		[Vector3(0, 0, 0), Vector3(0, 10, 0), Vector3(0, 0, 10)],
		[Vector3(0, 0, 0), Vector3(0, 0, 10), Vector3(10, 0, 0)],
		[Vector3(10, 0, 0), Vector3(0, 0, 10), Vector3(0, 10, 0)],
	]
	var faces: Array[FaceData] = []
	for verts in source:
		var fd := FaceData.new()
		fd.local_verts = PackedVector3Array(verts)
		faces.append(fd)
	brush.faces = faces
	var parsed: Dictionary = MapIO.parse_map_text(
		_wrap_worldspawn(MapIO._faces_to_map_lines(brush))
	)
	assert_eq(parsed.get("errors", []), [], "Our own export has to parse clean")
	var brushes: Array = parsed.get("brushes", [])
	assert_eq(brushes.size(), 1)
	assert_eq(int(brushes[0]["shape"]), LevelRoot.BrushShape.CUSTOM)
	var imported: Array = brushes[0]["faces"]
	assert_eq(imported.size(), source.size())
	for i in range(source.size()):
		var v: Array = imported[i]["local_verts"]
		var got := _face_outward(
			Vector3(v[0][0], v[0][1], v[0][2]),
			Vector3(v[1][0], v[1][1], v[1][2]),
			Vector3(v[2][0], v[2][1], v[2][2])
		)
		var want := _face_outward(source[i][0], source[i][1], source[i][2])
		assert_almost_eq(got.dot(want), 1.0, 0.001, "Face %d came back inside out" % i)


# ===========================================================================
# Face polygons are worked out, not read off the plane line (#244)
# ===========================================================================


## A `.map` face line whose three points sit on the plane but nowhere near the
## face polygon, which is all a plane definition ever promised to be. Reading
## these three back as corners is the bug.
func _plane_line(plane: Plane, spread: float) -> String:
	var normal := plane.normal.normalized()
	var reference := Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var u := normal.cross(reference).normalized()
	# u cross v is the normal, and the reader takes (p1 - p0) cross (p2 - p0),
	# so these three points name the plane facing outward.
	var v := normal.cross(u)
	var origin := normal * plane.d
	return HFMapQuake.new().format_face_line(
		origin, origin + u * spread, origin + v * spread, "brick", null
	)


func _face_lines_for_planes(planes: Array, spread: float) -> Array[String]:
	var lines: Array[String] = []
	for plane in planes:
		lines.append(_plane_line(plane, spread))
	return lines


## The six outward planes of a box brush, in world space.
func _box_planes(brush: DraftBrush) -> Array:
	var planes: Array = []
	var half := [brush.size.x * 0.5, brush.size.y * 0.5, brush.size.z * 0.5]
	var placement := brush.global_transform
	var axes := [placement.basis.x, placement.basis.y, placement.basis.z]
	for axis in range(3):
		var normal: Vector3 = (axes[axis] as Vector3).normalized()
		var reach: float = half[axis]
		planes.append(Plane(normal, normal.dot(placement.origin + normal * reach)))
		planes.append(Plane(-normal, -normal.dot(placement.origin - normal * reach)))
	return planes


func _box_corners(brush: DraftBrush) -> PackedVector3Array:
	var half: Vector3 = brush.size * 0.5
	var corners := PackedVector3Array()
	for x in [-half.x, half.x]:
		for y in [-half.y, half.y]:
			for z in [-half.z, half.z]:
				corners.append(brush.global_transform * Vector3(x, y, z))
	return corners


func _face_world_verts(face: Dictionary, center: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	for entry in face["local_verts"]:
		out.append(Vector3(entry[0], entry[1], entry[2]) + center)
	return out


func _nearest_distance(point: Vector3, candidates: PackedVector3Array) -> float:
	var best := INF
	for candidate in candidates:
		best = minf(best, point.distance_to(candidate))
	return best


## A box turned off every axis, written out as plane definitions that are not its
## corners, then read back.
func _import_tilted_box(brush: DraftBrush) -> Dictionary:
	brush.shape = LevelRoot.BrushShape.BOX
	brush.size = Vector3(8, 8, 8)
	brush.rotation = Vector3(deg_to_rad(15), deg_to_rad(30), deg_to_rad(20))
	var parsed: Dictionary = MapIO.parse_map_text(
		_wrap_worldspawn(_face_lines_for_planes(_box_planes(brush), 20.0))
	)
	assert_eq(parsed.get("errors", []), [], "Well formed planes parse clean")
	var brushes: Array = parsed.get("brushes", [])
	assert_eq(brushes.size(), 1, "Six planes are one brush")
	return brushes[0] if brushes.size() == 1 else {}


func test_tilted_brush_faces_come_back_as_polygons_not_plane_points():
	var brush := DraftBrush.new()
	add_child_autoqfree(brush)
	var imported := _import_tilted_box(brush)
	assert_eq(int(imported["shape"]), LevelRoot.BrushShape.CUSTOM)

	var corners := _box_corners(brush)
	var center: Vector3 = imported["center"]
	var faces: Array = imported["faces"]
	assert_eq(faces.size(), 6, "A box has six faces")
	for i in range(faces.size()):
		var verts := _face_world_verts(faces[i], center)
		assert_eq(
			verts.size(), 4, "Face %d is a quad, not the three points that named its plane" % i
		)
		for vertex in verts:
			assert_lt(
				_nearest_distance(vertex, corners), 0.02, "Face %d has a corner off the box" % i
			)


func test_tilted_brush_size_comes_from_the_hull_not_the_plane_points():
	var brush := DraftBrush.new()
	add_child_autoqfree(brush)
	var imported := _import_tilted_box(brush)

	var corners := _box_corners(brush)
	var low := corners[0]
	var high := corners[0]
	for corner in corners:
		low = Vector3(minf(low.x, corner.x), minf(low.y, corner.y), minf(low.z, corner.z))
		high = Vector3(maxf(high.x, corner.x), maxf(high.y, corner.y), maxf(high.z, corner.z))
	var size: Vector3 = imported["size"]
	assert_lt(
		size.distance_to(high - low), 0.02, "The brush is as big as its hull, not as its planes"
	)


func test_wedge_imports_with_triangle_ends_and_quad_sides():
	# x >= 0, z >= 0, x + z <= 10, extruded along y from -4 to 4.
	var diagonal := Vector3(1, 0, 1).normalized()
	var planes := [
		Plane(Vector3(-1, 0, 0), 0.0),
		Plane(Vector3(0, 0, -1), 0.0),
		Plane(diagonal, diagonal.dot(Vector3(10, 0, 0))),
		Plane(Vector3(0, 1, 0), 4.0),
		Plane(Vector3(0, -1, 0), 4.0),
	]
	var parsed: Dictionary = MapIO.parse_map_text(
		_wrap_worldspawn(_face_lines_for_planes(planes, 20.0))
	)

	assert_eq(parsed.get("errors", []), [], "Well formed planes parse clean")
	var brushes: Array = parsed.get("brushes", [])
	assert_eq(brushes.size(), 1)
	assert_eq(int(brushes[0]["shape"]), LevelRoot.BrushShape.CUSTOM)
	var counts: Array = []
	for face in brushes[0]["faces"]:
		counts.append((face["local_verts"] as Array).size())
	assert_eq(counts.size(), 5, "Five planes, five faces")
	assert_eq(counts.count(3), 2, "The two ends are triangles")
	assert_eq(counts.count(4), 3, "The three sides are quads")


func test_planes_that_close_nothing_still_import():
	# Two planes bound no solid. The old reading of the plane points as corners is
	# all there is to fall back on, and losing the brush would be worse.
	var lines: Array[String] = [
		"( 0 0 0 ) ( 4 0 0 ) ( 4 4 0 ) brick 0 0 0 1 1",
		"( 0 0 8 ) ( 4 4 8 ) ( 4 0 8 ) brick 0 0 0 1 1",
	]
	var parsed: Dictionary = MapIO.parse_map_text(_wrap_worldspawn(lines))
	assert_eq((parsed.get("brushes", []) as Array).size(), 1, "The brush survives an open hull")


# ===========================================================================
# Malformed map input (#174)
# ===========================================================================


func test_parse_arbitrary_text_reports_an_error():
	var parsed: Dictionary = MapIO.parse_map_text("not a map")
	assert_gt((parsed.get("errors", []) as Array).size(), 0, "Garbage is not a valid map")
	assert_eq(parsed.get("brushes", []), [])


func test_parse_empty_text_is_not_an_error():
	var parsed: Dictionary = MapIO.parse_map_text("")
	assert_eq(parsed.get("errors", []), [], "An empty file has nothing wrong with it")


func test_parse_unbalanced_braces_reports_an_error():
	var parsed: Dictionary = MapIO.parse_map_text("{\n" + '"classname" "worldspawn"' + "\n")
	assert_gt((parsed.get("errors", []) as Array).size(), 0)


func test_parse_stray_closing_brace_reports_an_error():
	var text := "{\n" + '"classname" "worldspawn"' + "\n}\n}\n"
	var parsed: Dictionary = MapIO.parse_map_text(text)
	assert_gt((parsed.get("errors", []) as Array).size(), 0)


func test_parse_invalid_face_line_reports_an_error():
	var parsed: Dictionary = MapIO.parse_map_text(
		_wrap_worldspawn(["( 0 0 0 ) ( 10 0 0 ) brick 0 0 0 1 1"])
	)
	assert_gt((parsed.get("errors", []) as Array).size(), 0, "Two points do not define a plane")


func test_parse_well_formed_map_reports_no_errors():
	var parsed: Dictionary = (
		MapIO
		. parse_map_text(
			_wrap_worldspawn(
				[
					"( 0 0 0 ) ( 10 0 0 ) ( 0 10 0 ) brick 0 0 0 1 1",
					"( 0 0 0 ) ( 0 10 0 ) ( 0 0 10 ) brick 0 0 0 1 1",
					"( 0 0 0 ) ( 0 0 10 ) ( 10 0 0 ) brick 0 0 0 1 1",
					"( 10 0 0 ) ( 0 0 10 ) ( 0 10 0 ) brick 0 0 0 1 1",
				]
			)
		)
	)
	assert_eq(parsed.get("errors", []), [], "A good map must not raise a false alarm")
	assert_eq((parsed.get("brushes", []) as Array).size(), 1)


# ---------------------------------------------------------------------------
# Valve 220 texture axes must lie in the face (#317)
# ---------------------------------------------------------------------------


func _axes_from_face_line(line: String) -> Array:
	# ... texture [ ux uy uz uoff ] [ vx vy vz voff ] rot us vs
	var open_brackets: PackedStringArray = line.split("[")
	assert_eq(open_brackets.size(), 3, "A Valve 220 face line carries two axis brackets")
	if open_brackets.size() != 3:
		return []
	var out: Array = []
	for i in [1, 2]:
		var inner: String = open_brackets[i].split("]")[0].strip_edges()
		var parts: PackedStringArray = inner.split(" ", false)
		out.append(Vector3(float(parts[0]), float(parts[1]), float(parts[2])))
	return out


func test_valve220_axes_lie_in_the_face_for_every_direction():
	# FaceData defaults to PLANAR_Z, whose axes are RIGHT and UP. On a +/-X or
	# +/-Y face one of those is the face normal, which is a degenerate
	# projection that TrenchBroom and J.A.C.K. cannot use.
	var adapter = HFMapValve220.new()
	var triangles := {
		"+X": [Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(1, 1, 1)],
		"-X": [Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 1)],
		"+Y": [Vector3(0, 1, 0), Vector3(0, 1, 1), Vector3(1, 1, 1)],
		"-Y": [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1)],
		"+Z": [Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 1, 1)],
		"-Z": [Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0)],
	}
	for label in triangles:
		var tri: Array = triangles[label]
		var fd = FaceData.new()
		fd.uv_projection = FaceData.UVProjection.PLANAR_Z
		var line: String = adapter.format_face_line(tri[0], tri[1], tri[2], "brick", fd)
		var normal: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0]).normalized()
		var axes: Array = _axes_from_face_line(line)
		assert_eq(axes.size(), 2, "%s face should carry two axes" % label)
		if axes.size() != 2:
			continue
		assert_almost_eq(
			axes[0].dot(normal), 0.0, 0.001, "%s: the U axis must lie in the face" % label
		)
		assert_almost_eq(
			axes[1].dot(normal), 0.0, 0.001, "%s: the V axis must lie in the face" % label
		)


func test_valve220_keeps_a_projection_that_already_lies_in_the_face():
	# The guard must not start overriding an alignment the user chose. A +Z face
	# with PLANAR_Z is exactly what PLANAR_Z is for.
	var adapter = HFMapValve220.new()
	var fd = FaceData.new()
	fd.uv_projection = FaceData.UVProjection.PLANAR_Z
	var line: String = adapter.format_face_line(
		Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 1, 1), "brick", fd
	)
	var axes: Array = _axes_from_face_line(line)
	assert_eq(axes[0], Vector3.RIGHT, "PLANAR_Z's U axis should survive on a Z facing face")
	assert_eq(axes[1], Vector3.UP, "PLANAR_Z's V axis should survive on a Z facing face")


func test_valve220_axes_of_an_exported_box_all_lie_in_their_faces():
	var brush := DraftBrush.new()
	brush.shape = LevelRoot.BrushShape.BOX
	brush.size = Vector3(64, 16, 64)
	var root := _make_export_root([brush])
	assert_eq(brush.faces.size(), 6, "Adding the box to the tree builds its six faces")
	var text := MapIO.export_map_from_level(root, HFMapValve220.new())
	var checked := 0
	for line in _plane_lines(text):
		var points: Array = _plane_points(line)
		var normal: Vector3 = (points[1] - points[0]).cross(points[2] - points[0]).normalized()
		var axes: Array = _axes_from_face_line(line)
		assert_almost_eq(axes[0].dot(normal), 0.0, 0.001, "U axis lies in the face: %s" % line)
		assert_almost_eq(axes[1].dot(normal), 0.0, 0.001, "V axis lies in the face: %s" % line)
		checked += 1
	assert_eq(checked, 6, "A box exports six face lines")
