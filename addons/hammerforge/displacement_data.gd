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
	corners: Array[Vector3], face_normal: Vector3,
	uv_corners: Array[Vector2]
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
			grid_pos[row * d + col] = get_displaced_position(
				row, col, corners, face_normal
			)
			var u: float = float(col) / float(d - 1)
			var v: float = float(row) / float(d - 1)
			var top_uv: Vector2 = uv_corners[0].lerp(uv_corners[1], u)
			var bot_uv: Vector2 = uv_corners[2].lerp(uv_corners[3], u)
			grid_uv[row * d + col] = top_uv.lerp(bot_uv, v)

	# Emit triangles (two per grid cell) in CW winding.
	for row in range(d - 1):
		for col in range(d - 1):
			var i00: int = row * d + col
			var i10: int = row * d + col + 1
			var i01: int = (row + 1) * d + col
			var i11: int = (row + 1) * d + col + 1
			var p00: Vector3 = grid_pos[i00]
			var p10: Vector3 = grid_pos[i10]
			var p01: Vector3 = grid_pos[i01]
			var p11: Vector3 = grid_pos[i11]
			# Triangle 1: 00 → 01 → 10 (CW from outside)
			var n1: Vector3 = (p01 - p00).cross(p10 - p00)
			if n1.length_squared() > 0.0001:
				n1 = n1.normalized()
			else:
				n1 = face_normal
			verts.append(p00)
			verts.append(p01)
			verts.append(p10)
			uvs.append(grid_uv[i00])
			uvs.append(grid_uv[i01])
			uvs.append(grid_uv[i10])
			normals.append(n1)
			normals.append(n1)
			normals.append(n1)
			# Triangle 2: 10 → 01 → 11 (CW from outside)
			var n2: Vector3 = (p01 - p10).cross(p11 - p10)
			if n2.length_squared() > 0.0001:
				n2 = n2.normalized()
			else:
				n2 = face_normal
			verts.append(p10)
			verts.append(p01)
			verts.append(p11)
			uvs.append(grid_uv[i10])
			uvs.append(grid_uv[i01])
			uvs.append(grid_uv[i11])
			normals.append(n2)
			normals.append(n2)
			normals.append(n2)

	return {"verts": verts, "uvs": uvs, "normals": normals}


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
	return data


## Deserialize from dictionary.
static func from_dict(data: Dictionary) -> HFDisplacementData:
	var disp = HFDisplacementData.new()
	disp.power = int(data.get("power", 3))
	disp.elevation = float(data.get("elevation", 1.0))
	disp.sew_group = int(data.get("sew_group", -1))
	var dist_arr: Array = data.get("distances", [])
	disp.distances = PackedFloat32Array()
	disp.distances.resize(dist_arr.size())
	for i in range(dist_arr.size()):
		disp.distances[i] = float(dist_arr[i])
	var off_arr: Array = data.get("offsets", [])
	if off_arr.size() > 0:
		disp.offsets = PackedVector3Array()
		disp.offsets.resize(off_arr.size())
		for i in range(off_arr.size()):
			var e: Array = off_arr[i]
			if e.size() >= 3:
				disp.offsets[i] = Vector3(float(e[0]), float(e[1]), float(e[2]))
	var alpha_arr: Array = data.get("alphas", [])
	if alpha_arr.size() > 0:
		disp.alphas = PackedFloat32Array()
		disp.alphas.resize(alpha_arr.size())
		for i in range(alpha_arr.size()):
			disp.alphas[i] = float(alpha_arr[i])
	return disp
