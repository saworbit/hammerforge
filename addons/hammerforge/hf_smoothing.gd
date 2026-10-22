@tool
extends RefCounted
class_name HFSmoothing

## Smoothing groups (#1429): the normal each corner of a smoothed face shades with.
##
## A face in group 0 is flat and shades with its own normal, as every face did
## before. Faces in the same group above 0 that meet at a corner share the average
## of their normals there, each face counted once, whichever brush it is on and
## whatever it is painted with. So a cylinder's sides read as round, and an arch
## built of separate brushes reads as one curve. A cut never shares with a solid:
## one faces into the hole the other faces out of.
##
## One routine for every place a face is drawn. The face bake adds every brush it
## takes, the CSG bake adds every brush the level's bake takes and then reshades
## what the boolean made, and a brush's preview adds its own faces. A brush shades
## the same whichever path bakes it, and the preview shows what the bake will,
## apart from the joins to other brushes, which only the bake sees.
##
## Free of the scene: corners in, normals out.

# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const FaceData = preload("face_data.gd")
const HFVertexWeld = preload("hf_vertex_weld.gd")
@warning_ignore_restore("shadowed_global_identifier")

## Corners this close are one corner: the thousandth of a unit the brush tools
## weld by. Two brushes placed side by side meet a rounding error apart.
const WELD := 0.001
## A CSG triangle lies on a face facing within this of its own way.
const SAME_DIRECTION := 0.999
## How far off a face's plane a CSG triangle's centre may be and still lie on it.
const ON_PLANE := 0.005
## How far outside a face, in the weights of its own triangles, a CSG triangle's
## centre may be and still lie on it.
const INSIDE := 0.01
## A CSG triangle is looked for only among the faces filed under the cell its
## centre and its way lie in (`_index_faces()`). Ways are filed in cells this wide
## on each axis, a face under every cell within `DIRECTION_REACH` of its own way:
## two ways within `SAME_DIRECTION` are at most 0.0448 apart on any axis.
const DIRECTION_CELL := 0.25
const DIRECTION_REACH := 0.05
## A face is filed under the places past the box of its corners by up to this
## share of the box's width on each axis, and this distance. A centre `INSIDE`
## outside one of its triangles lies at most twice `INSIDE` of that triangle's
## width past it, and one `ON_PLANE` off the face that distance, so both are
## covered with room to spare.
const PLACE_REACH_SHARE := 0.05
const PLACE_REACH := 0.01

## Every corner of every face added, face after face.
var _corners := PackedVector3Array()
## Per face: where its corners start in `_corners`, its outward normal, and its
## group and side as one number, `group * 2`, plus 1 for a cut.
var _first := PackedInt32Array()
var _face_normals := PackedVector3Array()
var _face_keys := PackedInt32Array()
## Per corner, once worked out: the normal it shades with.
var _shared := PackedVector3Array()
var _resolved := false
## The faces by where they lie and the way they face as seen, for `reshade()`:
## per grid, `[cell width, {Vector4i(x, y, z, way): [faces]}]`. Built on first use.
var _grids: Array = []
var _indexed := false


## Whether `face` shades smooth: in a group, and flat. A sculpted face has normals
## of its own, worked out over its grid, and keeps them.
static func smooths(face: FaceData) -> bool:
	return (
		face != null
		and face.smoothing_group > 0
		and face.displacement == null
		and face.local_verts.size() >= 3
	)


## Each triangle corner's normal, in the order `FaceData.triangulate()` fans a
## flat face, from the normals at the face's own corners.
static func fan(at_corners: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in range(1, at_corners.size() - 1):
		out.append(at_corners[0])
		out.append(at_corners[i])
		out.append(at_corners[i + 1])
	return out


## Add a face whose corners and outward normal are already in the space this
## works in. Returns its number for `corner_normals()`, or -1 for group 0.
func add(corners: PackedVector3Array, normal: Vector3, group: int, cut: bool = false) -> int:
	if group <= 0 or corners.size() < 3:
		return -1
	_resolved = false
	_indexed = false
	_grids.clear()
	var handle := _first.size()
	_first.append(_corners.size())
	_corners.append_array(corners)
	_face_normals.append(normal.normalized())
	_face_keys.append(group * 2 + (1 if cut else 0))
	return handle


## Add `face` where `xform` places it. -1 when it does not smooth.
func add_face(face: FaceData, xform: Transform3D = Transform3D.IDENTITY, cut: bool = false) -> int:
	if not smooths(face):
		return -1
	var normal := face.normal
	if not xform.basis.is_equal_approx(Basis.IDENTITY):
		normal = face.normal_through(xform.basis)
	return add(xform * face.local_verts, normal, face.smoothing_group, cut)


func is_empty() -> bool:
	return _first.is_empty()


## The normal face `handle` shades with at each of its corners, in their order.
## Empty for -1.
func corner_normals(handle: int) -> PackedVector3Array:
	if handle < 0 or handle >= _first.size():
		return PackedVector3Array()
	_resolve()
	return _shared.slice(_first[handle], _end_of(handle))


## `mesh`, which a CSG boolean made of the faces added here, shaded as they shade.
##
## Godot's CSG keeps no normal it is handed. It works out its own, flat or
## averaged by a rule of its own, and knows nothing of groups. So the bake hands
## it every brush flat and the shading goes back on here: a triangle that lies on
## a smoothed face takes that face's corner normals, spread across it the way the
## face's own triangles spread them, however the boolean divided the face up. The
## faces a cut leaves lie on no smoothed face of a solid, so they stay flat and
## nothing smooths into them. A round cutter's own faces are smoothed, so the hole
## it carves is round too, facing in.
##
## Every other triangle stays as the boolean wrote it. Returns `mesh` itself when
## nothing in it lies on a smoothed face, and a copy otherwise. The boolean writes
## every triangle's corners apart; on an indexed mesh a corner two faces share
## takes the normal of the last one read.
func reshade(mesh: Mesh) -> Mesh:
	if mesh == null or is_empty():
		return mesh
	_resolve()
	_index_faces()
	var out := ArrayMesh.new()
	var changed := false
	for s in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(s)
		var primitive: Mesh.PrimitiveType = mesh.surface_get_primitive_type(s)
		if primitive == Mesh.PRIMITIVE_TRIANGLES and _reshade_arrays(arrays):
			changed = true
		out.add_surface_from_arrays(primitive, arrays)
		out.surface_set_material(out.get_surface_count() - 1, mesh.surface_get_material(s))
	return out if changed else mesh


func _end_of(face: int) -> int:
	return _first[face + 1] if face + 1 < _first.size() else _corners.size()


## Work out every corner's normal: the faces of one group and side that meet at a
## corner add their normals there once each.
func _resolve() -> void:
	if _resolved:
		return
	_resolved = true
	# Each place once, so the weld looks at it once: a brush's faces share their
	# corners exactly.
	var places := PackedVector3Array()
	var place_of := PackedInt32Array()
	place_of.resize(_corners.size())
	var index_of: Dictionary = {}
	for i in _corners.size():
		var at: Vector3 = _corners[i]
		var found: Variant = index_of.get(at)
		if found == null:
			found = places.size()
			index_of[at] = found
			places.append(at)
		place_of[i] = int(found)
	var welded := PackedInt32Array()
	welded.resize(places.size())
	for i in places.size():
		welded[i] = i
	for group: PackedInt32Array in HFVertexWeld.cluster(places, WELD):
		for member in group:
			welded[member] = group[0]
	var sums: Dictionary = {}
	for face in _first.size():
		var key := _face_keys[face]
		var counted: Dictionary = {}
		for i in range(_first[face], _end_of(face)):
			var place := welded[place_of[i]]
			# A face with two corners welded into one still counts once there.
			if counted.has(place):
				continue
			counted[place] = true
			var slot := Vector2i(place, key)
			sums[slot] = (sums.get(slot, Vector3.ZERO) as Vector3) + _face_normals[face]
	_shared.resize(_corners.size())
	for face in _first.size():
		var key := _face_keys[face]
		for i in range(_first[face], _end_of(face)):
			var total: Vector3 = sums[Vector2i(welded[place_of[i]], key)]
			# Faces that cancel out, the two sides of a thin plate, keep their own.
			_shared[i] = (
				total.normalized() if total.length_squared() > 0.000001 else _face_normals[face]
			)


## The way face `face` faces as the mesh shows it. A cut shows the inside of its
## faces, so the hole it carves faces the other way.
func _shown_normal(face: int) -> Vector3:
	return -_face_normals[face] if _face_keys[face] & 1 else _face_normals[face]


## Every face under each cell of place and way a triangle on it could be found
## from (#1612). Filed by way alone, a cell held that way's faces from every
## round brush in the level, and each triangle tested them all.
##
## Each grid's cells are a power of two wide, and a face goes in the grid whose
## cells are at least twice as wide as its box, so it is filed under one or two
## cells along each axis whatever its size. A face facing no way is never found,
## so it is left out.
func _index_faces() -> void:
	if _indexed:
		return
	_indexed = true
	var cells_by_width: Dictionary = {}
	for face in _first.size():
		var normal := _shown_normal(face)
		var box: Variant = _reach_of(face)
		if box == null or not (normal.length_squared() > 0.5):
			continue
		var reach: AABB = box
		var width := pow(2.0, ceili(log(reach.get_longest_axis_size()) / log(2.0)) + 1)
		if not cells_by_width.has(width):
			cells_by_width[width] = {}
		var cells: Dictionary = cells_by_width[width]
		var low := reach.position
		var high := reach.end
		var ways := _ways_near(normal)
		for x in range(floori(low.x / width), floori(high.x / width) + 1):
			for y in range(floori(low.y / width), floori(high.y / width) + 1):
				for z in range(floori(low.z / width), floori(high.z / width) + 1):
					for way in ways:
						var key := Vector4i(x, y, z, way)
						var listed: Variant = cells.get(key)
						if listed == null:
							cells[key] = [face]
						else:
							(listed as Array).append(face)
	for width: float in cells_by_width:
		_grids.append([width, cells_by_width[width]])


## The box face `face` is filed over: its corners' box, grown by how far past it
## a centre that lies on it can be. A triangle of its with a corner that is not a
## number holds nothing, so that corner is left out, and a face with no box at
## all gets null.
func _reach_of(face: int) -> Variant:
	var box := AABB()
	var started := false
	for i in range(_first[face], _end_of(face)):
		var corner := _corners[i]
		if not corner.is_finite():
			continue
		if started:
			box = box.expand(corner)
		else:
			box = AABB(corner, Vector3.ZERO)
			started = true
	if not started:
		return null
	var grow := box.size * PLACE_REACH_SHARE + Vector3.ONE * PLACE_REACH
	var reach := AABB(box.position - grow, box.size + grow * 2.0)
	if not reach.is_finite():
		return null
	return reach


## The cell of ways `direction` lies in, as one number.
static func _way(direction: Vector3) -> int:
	return _way_number(
		floori(direction.x / DIRECTION_CELL),
		floori(direction.y / DIRECTION_CELL),
		floori(direction.z / DIRECTION_CELL)
	)


## The cells of ways within `DIRECTION_REACH` of `normal` on each axis.
static func _ways_near(normal: Vector3) -> PackedInt32Array:
	var out := PackedInt32Array()
	var low := (normal - Vector3.ONE * DIRECTION_REACH) / DIRECTION_CELL
	var high := (normal + Vector3.ONE * DIRECTION_REACH) / DIRECTION_CELL
	for x in range(floori(low.x), floori(high.x) + 1):
		for y in range(floori(low.y), floori(high.y) + 1):
			for z in range(floori(low.z), floori(high.z) + 1):
				out.append(_way_number(x, y, z))
	return out


## Four bits an axis: a way of length 1, give or take `DIRECTION_REACH`, lies
## between cells -5 and 4.
static func _way_number(x: int, y: int, z: int) -> int:
	return (x + 8) + (y + 8) * 16 + (z + 8) * 256


## Shade the triangles in one surface's arrays that lie on a smoothed face. True
## when any did.
func _reshade_arrays(arrays: Array) -> bool:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if verts.is_empty() or not (arrays[Mesh.ARRAY_NORMAL] is PackedVector3Array):
		return false
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	if normals.size() != verts.size():
		return false
	var indices := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
		indices = arrays[Mesh.ARRAY_INDEX]
	var count := indices.size() if not indices.is_empty() else verts.size()
	var changed := false
	var t := 0
	while t + 2 < count:
		var ia := indices[t] if not indices.is_empty() else t
		var ib := indices[t + 1] if not indices.is_empty() else t + 1
		var ic := indices[t + 2] if not indices.is_empty() else t + 2
		t += 3
		var a := verts[ia]
		var b := verts[ib]
		var c := verts[ic]
		# Clockwise from outside, as Godot draws a front face.
		var facing := (c - a).cross(b - a)
		var length := facing.length()
		if length <= 0.0 or not is_finite(length):
			continue
		var face := _face_under(facing / length, (a + b + c) / 3.0)
		if face < 0:
			continue
		normals[ia] = _normal_at(face, a)
		normals[ib] = _normal_at(face, b)
		normals[ic] = _normal_at(face, c)
		changed = true
	if not changed:
		return false
	arrays[Mesh.ARRAY_NORMAL] = normals
	_square_tangents(arrays, normals)
	return true


## The smoothed face a triangle facing `direction` with its centre at `centre`
## lies on, or -1. Of two that could hold it, the one it is least outside of, and
## of two it is as far outside of, the one added last, whichever grid holds it.
func _face_under(direction: Vector3, centre: Vector3) -> int:
	var way := _way(direction)
	var best := -1
	var best_outside := INSIDE
	for grid: Array in _grids:
		var width: float = grid[0]
		var found: Variant = (grid[1] as Dictionary).get(
			Vector4i(
				floori(centre.x / width), floori(centre.y / width), floori(centre.z / width), way
			)
		)
		if found == null:
			continue
		for face: int in found:
			var normal := _shown_normal(face)
			if normal.dot(direction) < SAME_DIRECTION:
				continue
			if absf(normal.dot(centre - _corners[_first[face]])) > ON_PLANE:
				continue
			var outside: float = _fan_weights(face, centre)[2]
			if outside < best_outside or (outside == best_outside and face > best):
				best = face
				best_outside = outside
	return best


## Which of `face`'s own triangles `point` lies in, or is least outside of:
## `[i, weights, outside]` for the triangle of its corners 0, i and i + 1.
func _fan_weights(face: int, point: Vector3) -> Array:
	var start := _first[face]
	var count := _end_of(face) - start
	var best_i := 1
	var best_weights := Vector3(1.0, 0.0, 0.0)
	var best_outside := INF
	for i in range(1, count - 1):
		var weights: Vector3 = Geometry3D.get_triangle_barycentric_coords(
			point, _corners[start], _corners[start + i], _corners[start + i + 1]
		)
		if not weights.is_finite():
			continue
		var outside := -minf(0.0, minf(weights.x, minf(weights.y, weights.z)))
		if outside < best_outside:
			best_i = i
			best_weights = weights
			best_outside = outside
	return [best_i, best_weights, best_outside]


## The normal `face` shades with at `point` on it, as the mesh shows it: its
## corner normals spread across the triangle of its own that holds the point.
func _normal_at(face: int, point: Vector3) -> Vector3:
	var found := _fan_weights(face, point)
	var start := _first[face]
	var i: int = found[0]
	var weights: Vector3 = found[1]
	var spread: Vector3 = (
		_shared[start] * weights.x
		+ _shared[start + i] * weights.y
		+ _shared[start + i + 1] * weights.z
	)
	if spread.length_squared() <= 0.000001:
		return _shown_normal(face)
	return -spread.normalized() if _face_keys[face] & 1 else spread.normalized()


## Turn each tangent back to a right angle with its corner's new normal, keeping
## its handedness, so a normal map still lies flat on the surface.
static func _square_tangents(arrays: Array, normals: PackedVector3Array) -> void:
	if not (arrays[Mesh.ARRAY_TANGENT] is PackedFloat32Array):
		return
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
	if tangents.size() != normals.size() * 4:
		return
	for i in normals.size():
		var tangent := Vector3(tangents[i * 4], tangents[i * 4 + 1], tangents[i * 4 + 2])
		var normal := normals[i]
		var squared := tangent - normal * normal.dot(tangent)
		if squared.length_squared() <= 0.000001:
			continue
		squared = squared.normalized()
		tangents[i * 4] = squared.x
		tangents[i * 4 + 1] = squared.y
		tangents[i * 4 + 2] = squared.z
	arrays[Mesh.ARRAY_TANGENT] = tangents
