@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## The two brush-drawing tools that are not the draw tool: Polygon and Path.
##
## Both take free-form input from the viewport, build `FaceData` by hand and
## hand it to `create_brush_from_info()`. Everything the primitives get for free
## -- consistent winding, a size that matches the geometry, a refusal when the
## input is degenerate -- these two have to do themselves, in code nothing else
## exercises. So the questions are the geometry ones: does the winding hold for
## either direction the user can trace a polygon, and what comes out when the
## input is degenerate or a setting is out of range.

const PolygonTool = preload("res://addons/hammerforge/hf_polygon_tool.gd")
const PathTool = preload("res://addons/hammerforge/hf_path_tool.gd")


func id() -> String:
	return "draw-tools"


func summary() -> String:
	return "polygon and path tool geometry: winding either way round, degenerate input, settings out of range"


func run() -> void:
	await _polygon_winding_both_ways()
	await _polygon_degenerate_input()
	await _path_winding()
	await _path_settings_out_of_range()
	await _what_the_inverted_path_bakes_to()


## Drive the polygon tool's own build path with a set of points, and return the
## brush it creates.
func _polygon_brush(root: Node3D, points: Array, height: float = 32.0) -> Node:
	var tool_instance = PolygonTool.new()
	tool_instance.root = root
	var pts := PackedVector3Array()
	for p in points:
		pts.append(p)
	tool_instance._polygon_points = pts
	tool_instance._ground_y = 0.0
	tool_instance._height = height
	var faces: Array = tool_instance._build_face_data()
	if faces.is_empty():
		return null
	var centre := Vector3.ZERO
	for p in pts:
		centre += p
	centre /= float(pts.size())
	centre.y = height * 0.5
	var info := {
		"shape": 6,
		"size": Vector3(1, 1, 1),
		"sides": pts.size(),
		"operation": 0,
		"center": centre,
		"faces": faces,
	}
	return root.brush_system.create_brush_from_info(info)


## A square traced clockwise and the same square traced anticlockwise. The user
## can do either; the brush must come out the same way up both times.
func _polygon_winding_both_ways() -> void:
	var root: Node3D = await fresh_root()
	var ccw := [Vector3(-32, 0, -32), Vector3(-32, 0, 32), Vector3(32, 0, 32), Vector3(32, 0, -32)]
	var cw := [Vector3(-32, 0, -32), Vector3(32, 0, -32), Vector3(32, 0, 32), Vector3(-32, 0, 32)]

	var a := _polygon_brush(root, ccw)
	await frame()
	var a_inward := HFVibe.inward_face_count(a)
	note("square traced one way: faces", a.faces.size())
	if a_inward > 0:
		flag("polygon tool: %d inward faces one way round" % a_inward, "faces: %d" % a.faces.size())
	else:
		note("square traced one way: inward faces", 0)

	var b := _polygon_brush(root, cw)
	await frame()
	var b_inward := HFVibe.inward_face_count(b)
	if b_inward > 0:
		flag(
			"polygon tool: %d inward faces the other way round" % b_inward,
			"same square, reversed point order -- faces: %d" % b.faces.size()
		)
	else:
		note("square traced the other way: inward faces", 0)

	# A five-sided polygon, the shape the tool exists for.
	var penta: Array = []
	for i in range(5):
		var ang := TAU * float(i) / 5.0
		penta.append(Vector3(cos(ang) * 48.0, 0, sin(ang) * 48.0))
	var p := _polygon_brush(root, penta)
	await frame()
	var p_inward := HFVibe.inward_face_count(p)
	note("pentagon faces", p.faces.size())
	if p_inward > 0:
		flag("polygon tool: pentagon has %d inward faces" % p_inward)


## What the tool's own convexity gate lets through. `_is_convex_xz()` skips any
## cross product under 0.001, which is every cross product a degenerate polygon
## has.
func _polygon_degenerate_input() -> void:
	var root: Node3D = await fresh_root()

	var collinear := [Vector3(-64, 0, 0), Vector3(0, 0, 0), Vector3(64, 0, 0)]
	note(
		"collinear points pass the convexity gate",
		PolygonTool._is_convex_xz(PackedVector3Array(collinear))
	)
	var flat := _polygon_brush(root, collinear)
	await frame()
	if flat != null:
		var extent := HFVibe.local_extent(flat)
		note("brush from three collinear points: extent", extent)
		if extent.z <= 0.001 or extent.x <= 0.001:
			known(
				398,
				"polygon tool builds a zero-thickness brush from collinear points",
				"extent %s, faces %d, volume 0 -- nothing refuses it" % [extent, flat.faces.size()]
			)
		var report: Dictionary = root.validation_system.validate(false)
		note("validate() issues on the flat brush", report.get("issues", []).size())

	var dup := [Vector3(-32, 0, -32), Vector3(-32, 0, -32), Vector3(32, 0, 32)]
	var dup_brush := _polygon_brush(root, dup)
	await frame()
	if dup_brush != null:
		known(
			399,
			"polygon tool accepts a repeated vertex",
			(
				"two of the three points are identical: %d faces, some with zero area"
				% dup_brush.faces.size()
			)
		)

	for issue in HFVibe.check_invariants(root):
		flag("invariant after degenerate polygons", issue)


func _path_brushes(root: Node3D, waypoints: Array, settings: Dictionary = {}) -> Array:
	var tool_instance = PathTool.new()
	tool_instance.root = root
	for k in settings:
		tool_instance.set_setting(k, settings[k])
	var pts := PackedVector3Array()
	for p in waypoints:
		pts.append(p)
	tool_instance._waypoints = pts
	tool_instance._ground_y = 0.0
	tool_instance._phase = 1
	var before: Array = root._iter_managed_brush_nodes()
	tool_instance._build_path()
	var made: Array = []
	for node in root._iter_managed_brush_nodes():
		if not before.has(node):
			made.append(node)
	return made


## A straight corridor and an L-bend. The bend is where the miter brush comes
## in, and the miter is the one piece of this geometry built by sorting points
## by angle rather than by writing the corners out.
func _path_winding() -> void:
	var root: Node3D = await fresh_root()

	var straight := _path_brushes(root, [Vector3(0, 0, 0), Vector3(256, 0, 0)])
	await frame()
	note("straight path brushes", straight.size())
	for b in straight:
		var inward := HFVibe.inward_face_count(b)
		if inward > 0:
			known(397, "path tool: straight segment has %d inward faces" % inward)

	var bend := _path_brushes(
		root, [Vector3(0, 0, 256), Vector3(0, 0, 0), Vector3(256, 0, 0)], {"miter_joints": true}
	)
	await frame()
	note("L-bend path brushes (2 segments + miter)", bend.size())
	for b in bend:
		var inward := HFVibe.inward_face_count(b)
		if inward > 0:
			known(
				397,
				(
					"path tool: an L-bend brush has %d of %d faces pointing inward"
					% [inward, b.faces.size()]
				),
				"size %s" % b.size
			)

	for issue in HFVibe.check_invariants(root):
		flag("invariant after paths", issue)


## `set_setting()` writes whatever it is handed; the schema's min/max is only
## consulted for the default. So the question is what the geometry does when a
## width outside the schema range reaches it.
func _path_settings_out_of_range() -> void:
	var root: Node3D = await fresh_root()

	var negative := _path_brushes(
		root, [Vector3(0, 0, 0), Vector3(256, 0, 0)], {"path_width": -16.0}
	)
	await frame()
	note("path with width -16: brushes", negative.size())
	for b in negative:
		var inward := HFVibe.inward_face_count(b)
		note("  size", b.size)
		if inward > 0:
			flag(
				"path tool: a negative width inverts the corridor (%d inward faces)" % inward,
				"schema says min 0.5; set_setting() does not clamp, size came out %s" % b.size
			)

	var zero := _path_brushes(
		root, [Vector3(0, 0, 512), Vector3(256, 0, 512)], {"path_height": 0.0}
	)
	await frame()
	for b in zero:
		note("path with height 0: size", b.size)
		if absf(b.size.y) <= 0.001:
			flag(
				"path tool builds a zero-height corridor",
				"schema min is 0.5; the brush has no volume and still saves and bakes"
			)

	var huge := _path_brushes(
		root, [Vector3(0, 0, 1024), Vector3(256, 0, 1024)], {"path_width": 1.0e9}
	)
	await frame()
	for b in huge:
		note("path with width 1e9: size", b.size)

	for issue in HFVibe.check_invariants(root):
		flag("invariant after out-of-range path settings", issue)


## Signed volume of every baked mesh under the root, by the divergence theorem.
## A solid wound the right way out encloses a positive volume; one wound inside
## out encloses the same magnitude negative. `bake.gd` takes the absolute value,
## which is why nothing there noticed.
func _signed_bake_volume(root: Node3D) -> float:
	var volume := 0.0
	var stack: Array = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
			if not (child is MeshInstance3D):
				continue
			var mi := child as MeshInstance3D
			if mi.mesh == null:
				continue
			var xf: Transform3D = mi.global_transform
			for s in range(mi.mesh.get_surface_count()):
				var arrays: Array = mi.mesh.surface_get_arrays(s)
				if arrays.is_empty():
					continue
				var raw_verts = arrays[Mesh.ARRAY_VERTEX]
				if not (raw_verts is PackedVector3Array):
					continue
				var verts: PackedVector3Array = raw_verts
				var raw_idx = arrays[Mesh.ARRAY_INDEX]
				var idx: PackedInt32Array = (
					raw_idx if raw_idx is PackedInt32Array else PackedInt32Array()
				)
				if idx.is_empty():
					var i := 0
					while i + 2 < verts.size():
						volume += _tet(xf * verts[i], xf * verts[i + 1], xf * verts[i + 2])
						i += 3
				else:
					var j := 0
					while j + 2 < idx.size():
						volume += _tet(
							xf * verts[idx[j]], xf * verts[idx[j + 1]], xf * verts[idx[j + 2]]
						)
						j += 3
	return volume


func _tet(a: Vector3, b: Vector3, c: Vector3) -> float:
	return a.dot(b.cross(c)) / 6.0


## The winding is only a number until it reaches the bake. A box and a path
## segment of the same dimensions, baked the same way, measured the same way.
func _what_the_inverted_path_bakes_to() -> void:
	var control: Node3D = await fresh_root()
	box(control, Vector3(256, 4, 4))
	await frame()
	await control.bake_dirty()
	await frame()
	var control_volume := _signed_bake_volume(control)
	note("signed baked volume of a 256x4x4 box", control_volume)

	var root: Node3D = await fresh_root()
	_path_brushes(root, [Vector3(0, 0, 0), Vector3(256, 0, 0)])
	await frame()
	await root.bake_dirty()
	await frame()
	var path_volume := _signed_bake_volume(root)
	note("signed baked volume of a 256-long path segment", path_volume)
	# Which sign means "outward" is Godot's business; what matters is that the two
	# disagree, measured on the baked triangles rather than on anything the
	# editor reports about itself.
	if signf(control_volume) != signf(path_volume) and absf(path_volume) > 0.0:
		known(
			397,
			"a path corridor bakes the opposite way out from every other brush",
			(
				(
					"a 256x4x4 box from the draw tool bakes to a signed volume of %.0f;"
					% control_volume
				)
				+ " the same corridor from the path tool bakes to %.0f" % path_volume
			)
		)
