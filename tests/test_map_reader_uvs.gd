extends GutTest

## What another editor draws from a `.map` face line: each face's UVs worked out
## from the exported line the way a reader works them out, against the UVs the
## viewport draws on that face.
##
## Valve 220 readers project with the axes as written and leave the rotation
## field alone. Classic Quake readers pick base axes from the plane's normal and
## turn them by the rotation themselves, which is qbsp's `TextureAxisFromPlane`.
## Either way the texture is taken as 64 pixels, the size of a face with none.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const MapIOType = preload("res://addons/hammerforge/map_io.gd")

const UNITS_PER_METRE := 32.0
const TEXELS := 64.0

## qbsp's base axes: a normal, then the S and T axes for planes facing it.
const BASE_AXES := [
	[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, -1, 0)],
	[Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, -1, 0)],
	[Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1)],
	[Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1)],
	[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)],
	[Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)],
]

var root: LevelRoot


## Writes face lines as Valve 220 does, and keeps each one beside its face.
class RecordingValve220:
	extends "res://addons/hammerforge/map_adapters/hf_map_valve220.gd"

	var written: Array = []

	func format_face_line(
		a: Vector3, b: Vector3, c: Vector3, texture: String, face_data: Variant
	) -> String:
		var line := super(a, b, c, texture, face_data)
		written.append([face_data, line])
		return line


## Writes face lines as Classic Quake does, and keeps each one beside its face.
class RecordingQuake:
	extends "res://addons/hammerforge/map_adapters/hf_map_quake.gd"

	var written: Array = []

	func format_face_line(
		a: Vector3, b: Vector3, c: Vector3, texture: String, face_data: Variant
	) -> String:
		var line := super(a, b, c, texture, face_data)
		written.append([face_data, line])
		return line


func before_each():
	root = LevelRootType.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)


## The numbers after the texture name, brackets dropped.
static func _numbers(line: String) -> Array:
	var tail := line.substr(line.rfind(")") + 1).replace("[", " ").replace("]", " ")
	var parts := tail.split(" ", false)
	var out: Array = []
	for i in range(1, parts.size()):
		out.append(float(parts[i]))
	return out


## The three plane points of a face line, in file order.
static func _plane_points(line: String) -> Array:
	var bracket := RegEx.new()
	bracket.compile("\\(([^\\)]+)\\)")
	var out: Array = []
	for found in bracket.search_all(line):
		var parts := found.get_string(1).split(" ", false)
		out.append(Vector3(float(parts[0]), float(parts[1]), float(parts[2])))
	return out.slice(0, 3)


## qbsp's S and T axes for a plane, turned by `degrees`.
static func _quake_axes(points: Array, degrees: float) -> Array:
	var normal: Vector3 = (points[0] - points[1]).cross(points[2] - points[1])
	var best := 0.0
	var picked := 0
	for i in BASE_AXES.size():
		var along: float = normal.dot(BASE_AXES[i][0])
		if along > best:
			best = along
			picked = i
	var s_axis: Vector3 = BASE_AXES[picked][1]
	var t_axis: Vector3 = BASE_AXES[picked][2]
	var s_index := 0 if s_axis.x != 0.0 else (1 if s_axis.y != 0.0 else 2)
	var t_index := 0 if t_axis.x != 0.0 else (1 if t_axis.y != 0.0 else 2)
	var sine := sin(deg_to_rad(degrees))
	var cosine := cos(deg_to_rad(degrees))
	var out: Array = []
	for axis in [s_axis, t_axis]:
		var turned: Vector3 = axis
		turned[s_index] = cosine * axis[s_index] - sine * axis[t_index]
		turned[t_index] = sine * axis[s_index] + cosine * axis[t_index]
		out.append(turned)
	return out


## The UVs a reader works out for `face` from `line`, at each corner, in repeats.
func _reader_uvs(brush: DraftBrush, face: FaceData, line: String, valve: bool) -> Array:
	var n := _numbers(line)
	var u_axis: Vector3
	var v_axis: Vector3
	var offset: Vector2
	var scale: Vector2
	if valve:
		u_axis = Vector3(n[0], n[1], n[2])
		offset = Vector2(n[3], n[7])
		v_axis = Vector3(n[4], n[5], n[6])
		scale = Vector2(n[9], n[10])
	else:
		var axes := _quake_axes(_plane_points(line), n[2])
		u_axis = axes[0]
		v_axis = axes[1]
		offset = Vector2(n[0], n[1])
		scale = Vector2(n[3], n[4])
	var out: Array = []
	for corner in face.local_verts:
		var p: Vector3 = MapIOType.to_map_axes(brush.global_transform * corner * UNITS_PER_METRE)
		var texel := Vector2(p.dot(u_axis) / scale.x, p.dot(v_axis) / scale.y) + offset
		out.append(texel / TEXELS)
	return out


## Every face line agrees with the viewport, corner for corner. A whole number of
## repeats either way draws the same, so only the part after it is compared.
func _assert_reader_draws_the_viewport(brush: DraftBrush, valve: bool, what: String) -> void:
	var adapter = RecordingValve220.new() if valve else RecordingQuake.new()
	MapIOType.export_map_from_level(root, adapter, UNITS_PER_METRE, true)
	assert_gt(adapter.written.size(), 0, "%s writes face lines" % what)
	for entry in adapter.written:
		var face: FaceData = entry[0]
		var shown := face._project_uvs_for_vertices(face.local_verts)
		var read := _reader_uvs(brush, face, entry[1], valve)
		var worst := 0.0
		for i in shown.size():
			var gap: Vector2 = read[i] - shown[i]
			if i == 0:
				gap -= gap.round()
			else:
				gap = (read[i] - read[0]) - (shown[i] - shown[0])
			worst = maxf(worst, gap.length())
		assert_almost_eq(worst, 0.0, 0.002, "%s, the face facing %s" % [what, face.normal])


func _box(centre: Vector3) -> DraftBrush:
	var brush := (
		root.create_brush_from_info({"shape": 0, "size": Vector3(2, 1, 1.5), "center": centre})
		as DraftBrush
	)
	brush.sync_face_world_transform()
	return brush


func _align(brush: DraftBrush, degrees: float, offset: Vector2, scale: Vector2) -> void:
	for face in brush.faces:
		face.uv_rotation = deg_to_rad(degrees)
		face.uv_offset = offset
		face.uv_scale = scale


## A Valve 220 reader never applies the rotation field, so the axes have to be
## written turned (#899).
func test_a_valve_220_reader_draws_every_face_as_the_viewport_does():
	for degrees in [0.0, 30.0, 90.0, -45.0, 137.0]:
		root.clear_brushes()
		var brush := _box(Vector3(1, 0.5, -2))
		_align(brush, degrees, Vector2(0.25, 0.125), Vector2(2.0, 0.5))
		_assert_reader_draws_the_viewport(brush, true, "Valve 220 at %s degrees" % degrees)


func test_a_valve_220_reader_draws_a_turned_box_as_the_viewport_does():
	var brush := _box(Vector3(3, 1, 2))
	brush.rotation = Vector3(0.3, 0.7, 0.0)
	brush.sync_face_world_transform()
	_align(brush, 20.0, Vector2(0.5, 0.25), Vector2.ONE)
	_assert_reader_draws_the_viewport(brush, true, "Valve 220 on a turned box")
