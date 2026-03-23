extends GutTest

const HFMapAdapter = preload("res://addons/hammerforge/map_adapters/hf_map_adapter.gd")
const HFMapQuake = preload("res://addons/hammerforge/map_adapters/hf_map_quake.gd")
const HFMapValve220 = preload("res://addons/hammerforge/map_adapters/hf_map_valve220.gd")
const FaceData = preload("res://addons/hammerforge/face_data.gd")

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


func test_valve220_fmt_float_fractional():
	var result = HFMapValve220._fmt_float(0.333)
	assert_true(result.begins_with("0.33"))
