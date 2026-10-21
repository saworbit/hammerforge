@tool
extends Resource
class_name HFDisplacementData

## Per-face displacement data. Subdivides a face into a grid of vertices
## that can be offset along the face normal (or freely) to create terrain
## and organic surfaces. Matches Source Engine displacement semantics.

## Subdivision power: 2 = 4×4 (9 verts), 3 = 8×8 (25 verts), 4 = 16×16 (81 verts).
@export_range(2, 4) var power: int = 3

## Per-vertex offset distances along the face normal (or custom direction).
## Length must be (2^power + 1)^2. Stored row-major.
@export var distances: PackedFloat32Array = PackedFloat32Array()

## Per-vertex offset directions in local space. If empty, face normal is used.
@export var offsets: PackedVector3Array = PackedVector3Array()

## Per-vertex alpha for blending two materials on the displacement surface.
@export var alphas: PackedFloat32Array = PackedFloat32Array()

## Sew group ID. Displacements sharing a sew group along an edge will have
## their boundary vertices snapped together during sew().
@export var sew_group: int = -1

## The elevation scale multiplier applied to all distances.
@export var elevation: float = 1.0

## Which diagonal splits each grid cell. Off is the split every displacement has
## always had, from (row, col + 1) to (row + 1, col). A mirror sends that diagonal
## onto the other one, and so does a quarter turn, so `remapped()` turns this over
## whenever its relabelling does, and every cell keeps folding the way it did. A
## resize can set it with no mirror involved: a face saved starting a quarter
## turn round has its sculpt relabelled to the order its shape generates. Written
## to a file only when on, so a sculpt nothing has relabelled saves exactly as it
## did.
@export var flip_diagonals: bool = false

## Where each face corner sits on the grid, by the corner's index in the face, as
## (row, col) with 1 standing for the last row or column. The corners follow the
## face round, so the face's own order is TL, TR, BR, BL.
## `FaceData.triangulate()` hands them on as TL, TR, BL, BR.
const CORNER_CELLS: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 0)
]

## Subdivision dimension: 2^power + 1 vertices per side.
var _dim: int = 0


func get_dim() -> int:
	if _dim == 0:
		_dim = (1 << power) + 1
	return _dim


func get_vertex_count() -> int:
	var d: int = get_dim()
	return d * d


## Initialize displacement arrays to default (flat) values for the given power.
func init_flat(p_power: int = 3) -> void:
	power = clampi(p_power, 2, 4)
	_dim = 0  # force recompute
	var count: int = get_vertex_count()
	distances = PackedFloat32Array()
	distances.resize(count)
	distances.fill(0.0)
	offsets = PackedVector3Array()
	alphas = PackedFloat32Array()
	alphas.resize(count)
	alphas.fill(0.0)
	sew_group = -1
	elevation = 1.0
	flip_diagonals = false


## Set the displacement distance at grid position (row, col).
func set_distance(row: int, col: int, value: float) -> void:
	var d: int = get_dim()
	var idx: int = row * d + col
	if idx >= 0 and idx < distances.size():
		distances[idx] = value


## Get the displacement distance at grid position (row, col).
func get_distance(row: int, col: int) -> float:
	var d: int = get_dim()
	var idx: int = row * d + col
	if idx >= 0 and idx < distances.size():
		return distances[idx]
	return 0.0


## Set a custom offset direction at grid position. If empty array, uses normal.
func set_offset(row: int, col: int, dir: Vector3) -> void:
	var d: int = get_dim()
	var idx: int = row * d + col
	var count: int = get_vertex_count()
	if offsets.size() != count:
		offsets.resize(count)
		for i in range(count):
			offsets[i] = Vector3.ZERO
	if idx >= 0 and idx < offsets.size():
		offsets[idx] = dir


## Set the alpha blend value at grid position.
func set_alpha(row: int, col: int, value: float) -> void:
	var d: int = get_dim()
	var idx: int = row * d + col
	if idx >= 0 and idx < alphas.size():
		alphas[idx] = clampf(value, 0.0, 1.0)


## Get the alpha blend value at grid position.
func get_alpha(row: int, col: int) -> float:
	var d: int = get_dim()
	var idx: int = row * d + col
	if idx >= 0 and idx < alphas.size():
		return alphas[idx]
	return 0.0


## Compute the displaced world position for grid cell (row, col) given
## the base quad corners and face normal.
## corners: [TL, TR, BL, BR] — the four corners of the original face,
## bilinearly interpolated to find the base position.
func get_displaced_position(
	row: int, col: int, corners: Array[Vector3], face_normal: Vector3
) -> Vector3:
	var d: int = get_dim()
	var u: float = float(col) / float(d - 1)
	var v: float = float(row) / float(d - 1)
	# Bilinear interpolation: TL(0,0) TR(1,0) BL(0,1) BR(1,1)
	var top: Vector3 = corners[0].lerp(corners[1], u)
	var bot: Vector3 = corners[2].lerp(corners[3], u)
	var base_pos: Vector3 = top.lerp(bot, v)
	var dist: float = get_distance(row, col) * elevation
	var dir: Vector3 = face_normal
	var idx: int = row * d + col
	if offsets.size() > idx and offsets[idx].length_squared() > 0.0001:
		dir = offsets[idx].normalized()
	return base_pos + dir * dist


## Generate a subdivided triangle mesh from the displacement grid.
## corners: [TL, TR, BL, BR] of the original quad face.
## Returns {"verts": PackedVector3Array, "uvs": PackedVector2Array,
##          "normals": PackedVector3Array}.
func triangulate_displaced(
	corners: Array[Vector3], face_normal: Vector3, uv_corners: Array[Vector2]
) -> Dictionary:
	var d: int = get_dim()
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()

	# Build the grid of displaced positions and UVs.
	var grid_pos: Array[Vector3] = []
	var grid_uv: Array[Vector2] = []
	grid_pos.resize(d * d)
	grid_uv.resize(d * d)
	for row in range(d):
		for col in range(d):
			grid_pos[row * d + col] = get_displaced_position(row, col, corners, face_normal)
			var u: float = float(col) / float(d - 1)
			var v: float = float(row) / float(d - 1)
			var top_uv: Vector2 = uv_corners[0].lerp(uv_corners[1], u)
			var bot_uv: Vector2 = uv_corners[2].lerp(uv_corners[3], u)
			grid_uv[row * d + col] = top_uv.lerp(bot_uv, v)

	var triangles := cell_triangles()
	var accum: PackedVector3Array = PackedVector3Array()
	accum.resize(d * d)
	for t in range(0, triangles.size(), 3):
		var a: int = triangles[t]
		var b: int = triangles[t + 1]
		var c: int = triangles[t + 2]
		# Outward for a triangle wound clockwise from outside, the convention
		# `FaceData.ensure_geometry()` measures faces by.
		var n: Vector3 = (grid_pos[c] - grid_pos[a]).cross(grid_pos[b] - grid_pos[a])
		if n.length_squared() > 0.0001:
			n = n.normalized()
		else:
			n = face_normal
		accum[a] += n
		accum[b] += n
		accum[c] += n
	for i in range(accum.size()):
		if accum[i].length_squared() > 0.0001:
			accum[i] = accum[i].normalized()
		else:
			accum[i] = face_normal

	# Emit the triangles with smooth vertex normals.
	for index in triangles:
		verts.append(grid_pos[index])
		uvs.append(grid_uv[index])
		normals.append(accum[index])

	return {"verts": verts, "uvs": uvs, "normals": normals}


## Every grid cell's two triangles, as grid indices, three to a triangle, wound
## clockwise from outside like every other face.
##
## A cell's corners in the face's own order are (row, col), (row, col + 1),
## (row + 1, col + 1), (row + 1, col), and each triangle keeps that rotation. These
## were once emitted the other way round, which put every displaced surface inside
## out: it faced into its brush, so it was culled from outside in the viewport and
## in the bake.
func cell_triangles() -> PackedInt32Array:
	var d: int = get_dim()
	var out := PackedInt32Array()
	out.resize((d - 1) * (d - 1) * 6)
	var t := 0
	for row in range(d - 1):
		for col in range(d - 1):
			var i00: int = row * d + col
			var i10: int = i00 + 1
			var i01: int = i00 + d
			var i11: int = i01 + 1
			if flip_diagonals:
				out[t] = i00
				out[t + 1] = i10
				out[t + 2] = i11
				out[t + 3] = i00
				out[t + 4] = i11
				out[t + 5] = i01
			else:
				out[t] = i00
				out[t + 1] = i10
				out[t + 2] = i01
				out[t + 3] = i10
				out[t + 4] = i11
				out[t + 5] = i01
			t += 6
	return out


## Smooth vertices using a simple box filter (average of neighbors).
## strength: 0.0–1.0 blend toward neighbor average.
func smooth(strength: float = 0.5) -> void:
	var d: int = get_dim()
	var count: int = d * d
	if distances.size() != count:
		return
	var new_dist := PackedFloat32Array()
	new_dist.resize(count)
	for row in range(d):
		for col in range(d):
			var idx: int = row * d + col
			var total: float = 0.0
			var n: int = 0
			for dr in range(-1, 2):
				for dc in range(-1, 2):
					var r2: int = row + dr
					var c2: int = col + dc
					if r2 >= 0 and r2 < d and c2 >= 0 and c2 < d:
						total += distances[r2 * d + c2]
						n += 1
			var avg: float = total / float(n) if n > 0 else distances[idx]
			new_dist[idx] = lerpf(distances[idx], avg, strength)
	distances = new_dist


## Apply noise displacement.
func apply_noise(noise: FastNoiseLite, scale: float = 1.0) -> void:
	var d: int = get_dim()
	for row in range(d):
		for col in range(d):
			var idx: int = row * d + col
			if idx < distances.size():
				distances[idx] += noise.get_noise_2d(float(col) * 10.0, float(row) * 10.0) * scale


## This sculpt laid against a new corner order, as a new resource.
##
## `corner_from[i]` is the index, in the face's old order, of the corner that is
## now corner `i`. Every grid value moves to where that relabelling puts it, so
## the surface stays where it was and only the indexing changes. `reflect_axis`
## names a local axis the face's geometry was reflected through, which the custom
## offset directions have to follow, or -1 for a relabelling with no reflection.
##
## A new resource rather than an edit, because a duplicate can share this one
## with another face and an undo snapshot can hold it.
##
## Null when `corner_from` is not a symmetry of the square. Corners that were
## neighbours have to stay neighbours, or the relabelling would tear the grid.
func remapped(corner_from: PackedInt32Array, reflect_axis: int = -1) -> HFDisplacementData:
	if not _is_square_symmetry(corner_from):
		return null
	var out := HFDisplacementData.new()
	out.power = power
	out.elevation = elevation
	out.sew_group = sew_group
	var last := get_dim() - 1
	var origin: Vector2i = CORNER_CELLS[corner_from[0]] * last
	# One step along the new grid, measured on the old one.
	var along_col: Vector2i = CORNER_CELLS[corner_from[1]] - CORNER_CELLS[corner_from[0]]
	var along_row: Vector2i = CORNER_CELLS[corner_from[3]] - CORNER_CELLS[corner_from[0]]
	# The new grid splits each cell from (row, col + 1) to (row + 1, col) unless
	# told otherwise. Seen on the old grid that diagonal runs along
	# `along_row - along_col`, which is either the old default split or the other
	# one, and the flag says which of the two the old grid actually drew.
	var diagonal := along_row - along_col
	out.flip_diagonals = flip_diagonals != (diagonal.x == diagonal.y)
	var count := get_vertex_count()
	var carry_distances := distances.size() == count
	var carry_alphas := alphas.size() == count
	var carry_offsets := offsets.size() == count
	# Start from copies and overwrite what moves. An array the wrong length for
	# this power is carried over untouched, so a grid that was already unreadable
	# stays unreadable in the same way rather than being read past its end.
	out.distances = distances.duplicate()
	out.alphas = alphas.duplicate()
	out.offsets = offsets.duplicate()
	for row in range(last + 1):
		for col in range(last + 1):
			var cell: Vector2i = origin + along_row * row + along_col * col
			var source := cell.x * (last + 1) + cell.y
			var target := row * (last + 1) + col
			if carry_distances:
				out.distances[target] = distances[source]
			if carry_alphas:
				out.alphas[target] = alphas[source]
			if carry_offsets:
				var direction: Vector3 = offsets[source]
				if reflect_axis >= 0 and reflect_axis <= 2:
					direction[reflect_axis] = -direction[reflect_axis]
				out.offsets[target] = direction
	return out


## Whether a corner relabelling turns or mirrors the square without tearing it:
## all four corners named once, and the corners either side of the new first one
## are the old first one's two neighbours.
static func _is_square_symmetry(corner_from: PackedInt32Array) -> bool:
	if corner_from.size() != 4:
		return false
	var seen := {}
	for corner in corner_from:
		if corner < 0 or corner > 3 or seen.has(corner):
			return false
		seen[corner] = true
	var first := corner_from[0]
	var next := (first + 1) % 4
	var previous := (first + 3) % 4
	return (
		(corner_from[1] == next and corner_from[3] == previous)
		or (corner_from[1] == previous and corner_from[3] == next)
	)


## This sculpt laid onto a quad that lies inside the face it was made on, as a new
## resource of the same power. This is how a sculpt follows a Clip or a Carve.
##
## `face_corners` are the face's four corners in its own order, and
## `piece_corners` the quad's, in the same space. Each grid point of the quad takes
## the height the face's surface has at the same place, read off the triangle of
## the face's grid it falls in, so every new grid point sits on the surface the
## face showed. Between grid points the new grid is as fine as itself, so a bump
## smaller than one of its cells is smoothed over.
##
## Null unless both are quads. An array the wrong length for this power is carried
## over untouched, as `remapped()` does.
func resampled_onto(
	face_corners: PackedVector3Array, piece_corners: PackedVector3Array
) -> HFDisplacementData:
	if face_corners.size() != 4 or piece_corners.size() != 4:
		return null
	var out := HFDisplacementData.new()
	out.power = power
	out.elevation = elevation
	out.sew_group = sew_group
	var last := get_dim() - 1
	# The quad's grid splits each cell from (row, col + 1) to (row + 1, col). Seen
	# on the face's grid that runs along `along_row - along_col`, which is the
	# face's own default split when its two parts have opposite signs, and the other
	# split when they share one. Keep folding the way the face folded.
	var origin := _place_on_quad(face_corners, piece_corners[0])
	var along_col := _place_on_quad(face_corners, piece_corners[1]) - origin
	var along_row := _place_on_quad(face_corners, piece_corners[3]) - origin
	var diagonal := along_row - along_col
	out.flip_diagonals = flip_diagonals != (diagonal.x * diagonal.y > 0.0)
	var count := get_vertex_count()
	var carry_distances := distances.size() == count
	var carry_alphas := alphas.size() == count
	var carry_offsets := offsets.size() == count
	out.distances = distances.duplicate()
	out.alphas = alphas.duplicate()
	out.offsets = offsets.duplicate()
	for row in range(last + 1):
		for col in range(last + 1):
			var u := float(col) / float(last)
			var v := float(row) / float(last)
			var top: Vector3 = piece_corners[0].lerp(piece_corners[1], u)
			var bottom: Vector3 = piece_corners[3].lerp(piece_corners[2], u)
			var on_face := _place_on_quad(face_corners, top.lerp(bottom, v)) * float(last)
			var weights := _triangle_weights(on_face)
			var target := row * (last + 1) + col
			var distance := 0.0
			var alpha := 0.0
			var offset := Vector3.ZERO
			for k in range(0, 6, 2):
				var source: int = weights[k]
				var weight: float = weights[k + 1]
				if carry_distances:
					distance += distances[source] * weight
				if carry_alphas:
					alpha += alphas[source] * weight
				if carry_offsets:
					offset += offsets[source] * weight
			if carry_distances:
				out.distances[target] = distance
			if carry_alphas:
				out.alphas[target] = alpha
			if carry_offsets:
				out.offsets[target] = offset
	return out


## The three grid points of the triangle `at` falls in, with their weights, as
## `[index, weight, index, weight, index, weight]`. `at` is (col, row) on this grid,
## and the triangles are the ones `cell_triangles()` draws.
func _triangle_weights(at: Vector2) -> Array:
	var dim := get_dim()
	var last := dim - 1
	var across := clampf(at.x, 0.0, float(last))
	var down := clampf(at.y, 0.0, float(last))
	var col := mini(int(floor(across)), last - 1)
	var row := mini(int(floor(down)), last - 1)
	var fu := across - float(col)
	var fv := down - float(row)
	var i00 := row * dim + col
	var i10 := i00 + 1
	var i01 := i00 + dim
	var i11 := i01 + 1
	if flip_diagonals:
		if fu >= fv:
			return [i00, 1.0 - fu, i10, fu - fv, i11, fv]
		return [i00, 1.0 - fv, i11, fu, i01, fv - fu]
	if fu + fv <= 1.0:
		return [i00, 1.0 - fu - fv, i10, fu, i01, fv]
	return [i10, 1.0 - fv, i11, fu + fv - 1.0, i01, 1.0 - fu]


## Where `point` sits on a quad, as (u, v) from 0 to 1 along the quad's first
## edge and down its side, the way `get_displaced_position()` places grid points.
## Exact in one step on a parallelogram, and a few more for any other flat quad.
static func _place_on_quad(corners: PackedVector3Array, point: Vector3) -> Vector2:
	var u := 0.5
	var v := 0.5
	for _step in 8:
		var top: Vector3 = corners[0].lerp(corners[1], u)
		var bottom: Vector3 = corners[3].lerp(corners[2], u)
		var miss: Vector3 = point - top.lerp(bottom, v)
		var along_u: Vector3 = (corners[1] - corners[0]).lerp(corners[2] - corners[3], v)
		var along_v: Vector3 = bottom - top
		var uu := along_u.dot(along_u)
		var uv := along_u.dot(along_v)
		var vv := along_v.dot(along_v)
		var det := uu * vv - uv * uv
		if det <= uu * vv * 0.000000001:
			break
		var mu := along_u.dot(miss)
		var mv := along_v.dot(miss)
		var du := (vv * mu - uv * mv) / det
		var dv := (uu * mv - uv * mu) / det
		u += du
		v += dv
		if absf(du) + absf(dv) < 0.0000001:
			break
	return Vector2(clampf(u, 0.0, 1.0), clampf(v, 0.0, 1.0))


## Serialize to dictionary.
func to_dict() -> Dictionary:
	var data: Dictionary = {
		"power": power,
		"elevation": elevation,
		"sew_group": sew_group,
		"distances": Array(distances),
	}
	if offsets.size() > 0:
		var off_arr: Array = []
		for o in offsets:
			off_arr.append([o.x, o.y, o.z])
		data["offsets"] = off_arr
	if alphas.size() > 0:
		data["alphas"] = Array(alphas)
	if flip_diagonals:
		data["flip_diagonals"] = true
	return data


## Deserialize from dictionary.
## The power is clamped the way init_flat() clamps it, and every array is
## checked against the vertex count that power implies.
##
## get_dim() returns (1 << power) + 1 and every read is a `row * dim + col`, so a
## power that does not match the array lengths sends each index to the wrong
## cell. set_distance() and add_noise() both guard on `idx < size()`, which means
## the writes past the end are dropped in silence: the surface part flattens and
## part scrambles with nothing to trace it back to. A face that cannot be trusted
## comes back flat instead.
static func from_dict(data: Dictionary) -> HFDisplacementData:
	var disp = HFDisplacementData.new()
	var raw_power := int(data.get("power", 3))
	var power_value := clampi(raw_power, 2, 4)
	if power_value != raw_power:
		HFLog.warn(
			"Displacement: power %d is outside 2 to 4. Clamped to %d." % [raw_power, power_value]
		)
	disp.init_flat(power_value)
	disp.elevation = float(data.get("elevation", 1.0))
	disp.sew_group = int(data.get("sew_group", -1))
	disp.flip_diagonals = bool(data.get("flip_diagonals", false))
	var expected := disp.get_vertex_count()
	var dist_arr: Array = data.get("distances", [])
	if dist_arr.size() == expected:
		for i in range(expected):
			disp.distances[i] = float(dist_arr[i])
	elif dist_arr.size() > 0:
		HFLog.warn(
			(
				"Displacement: %d distances for a power %d face, which needs %d. Face left flat."
				% [dist_arr.size(), power_value, expected]
			)
		)
	var off_arr: Array = data.get("offsets", [])
	if off_arr.size() == expected:
		# init_flat() leaves offsets empty, since a flat face has none.
		disp.offsets.resize(expected)
		for i in range(expected):
			var e: Array = off_arr[i]
			if e.size() >= 3:
				disp.offsets[i] = Vector3(float(e[0]), float(e[1]), float(e[2]))
	elif off_arr.size() > 0:
		HFLog.warn(
			(
				"Displacement: %d offsets for a power %d face, which needs %d. Offsets dropped."
				% [off_arr.size(), power_value, expected]
			)
		)
	var alpha_arr: Array = data.get("alphas", [])
	if alpha_arr.size() == expected:
		for i in range(expected):
			disp.alphas[i] = float(alpha_arr[i])
	elif alpha_arr.size() > 0:
		HFLog.warn(
			(
				"Displacement: %d alphas for a power %d face, which needs %d. Alphas dropped."
				% [alpha_arr.size(), power_value, expected]
			)
		)
	return disp
