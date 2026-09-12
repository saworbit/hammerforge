@tool
class_name HFScatterBrush
extends RefCounted

## Interactive scatter/foliage placement brush with circle/spline shapes,
## density preview (MultiMesh wireframe), and slope/height filtering.
## Works with HFFoliagePopulator to commit final instances.

const HFHash = preload("hf_hash.gd")

## The most instances one scatter stroke may lay out.
##
## The candidate count is quadratic in the brush radius, so a radius a mapper
## can type by accident asks for millions of Transform3Ds and the editor is
## gone for the duration. HFDuplicator refuses past MAX_COPY_BRUSHES the same
## way rather than building whatever it was handed.
const MAX_SCATTER_INSTANCES := 50000

## Brush shape for scatter placement.
enum BrushShape { CIRCLE, SPLINE }

## Preview display mode.
enum PreviewMode { DOTS, WIREFRAME, FULL }


class ScatterSettings:
	## Mesh to scatter.
	var mesh: Mesh = null
	## Instances per square world-unit.
	var density: float = 0.5
	## Brush radius in world units (circle mode).
	var radius: float = 5.0
	## Brush shape.
	var shape: int = BrushShape.CIRCLE  # raw int for default param safety
	## Spline points (world XZ) — used when shape == SPLINE.
	var spline_points: PackedVector3Array = PackedVector3Array()
	## Spline width in world units.
	var spline_width: float = 3.0
	## Height constraints (world Y).
	var min_height: float = -1000.0
	var max_height: float = 1000.0
	## Maximum slope in degrees.
	var max_slope: float = 45.0
	## Scale variation.
	var scale_range: Vector2 = Vector2(0.8, 1.2)
	## Random Y rotation.
	var random_rotation: bool = true
	## Align to surface normal.
	var align_to_normal: bool = false
	## RNG seed (0 = random).
	var seed: int = 0
	## Preview mode.
	var preview_mode: int = PreviewMode.DOTS  # raw int


class ScatterResult:
	var transforms: Array[Transform3D] = []
	var rejected_count: int = 0  # Filtered by slope/height
	var total_candidates: int = 0
	## Set when the stroke was refused before it ran. Null on a normal result.
	var refusal: HFOpResult = null


## Generate scatter transforms for a circle brush centered at `center`.
func scatter_circle(
	center: Vector3, layer: HFPaintLayer, settings: ScatterSettings
) -> ScatterResult:
	var result := ScatterResult.new()
	if not layer or not layer.grid:
		return result

	var grid := layer.grid
	var r := maxf(settings.radius, 0.1)
	var area := PI * r * r
	var count := int(ceil(area * settings.density))
	result.total_candidates = count
	result.refusal = check_candidate_count(count, "radius %s" % r)
	if result.refusal:
		return result

	var rng := RandomNumberGenerator.new()
	rng.seed = settings.seed if settings.seed != 0 else Time.get_ticks_usec()

	for _i in range(count):
		# Uniform random point in circle
		var angle := rng.randf() * TAU
		var dist := r * sqrt(rng.randf())
		var world_x := center.x + cos(angle) * dist
		var world_z := center.z + sin(angle) * dist
		var cell := grid.world_to_cell(Vector3(world_x, 0, world_z))

		# Height sampling
		var h := layer.get_height_at(cell) + grid.layer_y
		if h < settings.min_height or h > settings.max_height:
			result.rejected_count += 1
			continue

		# Slope check
		var slope := _compute_slope(layer, cell, grid)
		if slope > settings.max_slope:
			result.rejected_count += 1
			continue

		var pos := Vector3(world_x, h, world_z)
		var xform := _build_transform(pos, rng, settings, layer, cell, grid)
		result.transforms.append(xform)

	return result


## Generate scatter transforms along a spline path.
func scatter_spline(layer: HFPaintLayer, settings: ScatterSettings) -> ScatterResult:
	var result := ScatterResult.new()
	if not layer or not layer.grid:
		return result
	if settings.spline_points.size() < 2:
		return result

	var grid := layer.grid
	var hw := settings.spline_width * 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = settings.seed if settings.seed != 0 else Time.get_ticks_usec()

	# Walk along spline segments, scatter in the width band
	var total_length := 0.0
	for i in range(settings.spline_points.size() - 1):
		var a := settings.spline_points[i]
		var b := settings.spline_points[i + 1]
		var seg_dir := b - a
		seg_dir.y = 0.0
		total_length += seg_dir.length()

	var area := total_length * settings.spline_width
	var count := int(ceil(area * settings.density))
	result.total_candidates = count
	result.refusal = check_candidate_count(count, "a %.1f unit path" % total_length)
	if result.refusal:
		return result

	for _i in range(count):
		# Pick random position along spline length
		var t := rng.randf() * total_length
		var offset := rng.randf_range(-hw, hw)
		var pos := _sample_spline_at(settings.spline_points, t, offset)

		var cell := grid.world_to_cell(pos)
		var h := layer.get_height_at(cell) + grid.layer_y
		if h < settings.min_height or h > settings.max_height:
			result.rejected_count += 1
			continue

		var slope := _compute_slope(layer, cell, grid)
		if slope > settings.max_slope:
			result.rejected_count += 1
			continue

		pos.y = h
		var xform := _build_transform(pos, rng, settings, layer, cell, grid)
		result.transforms.append(xform)

	return result


## Whether a stroke asking for this many candidates is allowed to run.
##
## `what` names the setting that produced the count so the message points at
## the field to change rather than at the number it arrived as.
func check_candidate_count(count: int, what: String) -> HFOpResult:
	if count <= MAX_SCATTER_INSTANCES:
		return null
	return HFOpResult.fail(
		"Scatter: %s at this density is %d instances" % [what, count],
		(
			"Keep the total at or below %d by lowering the radius or the density"
			% MAX_SCATTER_INSTANCES
		)
	)


## Build a density preview MultiMesh (lightweight wireframe dots).
func build_preview(transforms: Array[Transform3D], settings: ScatterSettings) -> MultiMesh:
	if transforms.is_empty():
		return null

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D

	match settings.preview_mode:
		PreviewMode.DOTS:
			mm.mesh = _make_dot_mesh()
		PreviewMode.WIREFRAME:
			if settings.mesh:
				mm.mesh = _make_wireframe_mesh(settings.mesh)
			else:
				mm.mesh = _make_dot_mesh()
		PreviewMode.FULL:
			mm.mesh = settings.mesh if settings.mesh else _make_dot_mesh()

	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])
	return mm


## Build the committed MultiMeshInstance3D without putting it in the scene.
##
## The caller parents it, which is what lets the dock do that inside an undo
## action instead of after one.
func build_instance(
	transforms: Array[Transform3D], settings: ScatterSettings
) -> MultiMeshInstance3D:
	if transforms.is_empty() or not settings.mesh:
		return null

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = settings.mesh
	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.name = "Scatter_%d" % Time.get_ticks_usec()
	return mmi


## Commit the scatter result as a permanent MultiMeshInstance3D.
func commit(
	transforms: Array[Transform3D], settings: ScatterSettings, parent: Node3D
) -> MultiMeshInstance3D:
	if not parent:
		return null
	var mmi := build_instance(transforms, settings)
	if not mmi:
		return null
	parent.add_child(mmi)
	assign_scene_owner(mmi)
	return mmi


## The owner the level's other generated nodes have, resolved from `parent`.
##
## A node with a null owner is not written into the .tscn, so a committed
## scatter without one is in the viewport until the scene is closed and gone
## after.
static func scene_owner_for(parent: Node) -> Node:
	if not parent:
		return null
	var tree := parent.get_tree()
	if tree and tree.edited_scene_root:
		return tree.edited_scene_root
	var up := parent
	while up:
		if up.owner:
			return up.owner
		up = up.get_parent()
	return null


## Give an already parented node that owner.
static func assign_scene_owner(node: Node) -> void:
	if not node or not node.is_inside_tree():
		return
	var scene_owner := scene_owner_for(node.get_parent())
	if scene_owner and scene_owner != node:
		node.owner = scene_owner


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------


func _compute_slope(layer: HFPaintLayer, cell: Vector2i, grid: HFPaintGrid) -> float:
	var h := layer.get_height_at(cell)
	var h_right := layer.get_height_at(cell + Vector2i(1, 0))
	var h_up := layer.get_height_at(cell + Vector2i(0, 1))
	var slope_rad := atan(maxf(absf(h_right - h), absf(h_up - h)) / maxf(grid.cell_size, 0.001))
	return rad_to_deg(slope_rad)


func _build_transform(
	pos: Vector3,
	rng: RandomNumberGenerator,
	settings: ScatterSettings,
	layer: HFPaintLayer,
	cell: Vector2i,
	grid: HFPaintGrid
) -> Transform3D:
	var s := rng.randf_range(settings.scale_range.x, settings.scale_range.y)
	var rot := rng.randf() * TAU if settings.random_rotation else 0.0
	var basis := Basis(Vector3.UP, rot).scaled(Vector3(s, s, s))

	if settings.align_to_normal:
		var normal := _compute_normal(layer, cell, grid)
		var up := normal.normalized()
		var right := up.cross(Vector3.FORWARD).normalized()
		if right.length_squared() < 0.01:
			right = up.cross(Vector3.RIGHT).normalized()
		var forward := right.cross(up).normalized()
		basis = Basis(right, up, forward).scaled(Vector3(s, s, s))
		if settings.random_rotation:
			basis = Basis(up, rot) * basis

	return Transform3D(basis, pos)


func _compute_normal(layer: HFPaintLayer, cell: Vector2i, grid: HFPaintGrid) -> Vector3:
	var cs := grid.cell_size
	var h := layer.get_height_at(cell)
	var h_right := layer.get_height_at(cell + Vector2i(1, 0))
	var h_up := layer.get_height_at(cell + Vector2i(0, 1))
	# Cross product of tangent vectors
	var tx := Vector3(cs, h_right - h, 0.0)
	var tz := Vector3(0.0, h_up - h, cs)
	# tz into tx, not the other way round: tx.cross(tz) has a -cs^2 Y term, so
	# it points into the ground for every cell size and stands the instance on
	# its head.
	return tz.cross(tx).normalized()


func _sample_spline_at(points: PackedVector3Array, t: float, offset: float) -> Vector3:
	var walked := 0.0
	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		var seg := b - a
		seg.y = 0.0
		var seg_len := seg.length()
		if walked + seg_len >= t:
			var local_t := (t - walked) / maxf(seg_len, 0.001)
			var pos := a.lerp(b, local_t)
			# Perpendicular offset
			var dir := seg.normalized()
			var perp := Vector3(-dir.z, 0.0, dir.x)
			return pos + perp * offset
		walked += seg_len
	# Past end — clamp to last point
	return points[points.size() - 1]


func _make_dot_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	# Small cross marker
	var s := 0.15
	st.set_color(Color(0.2, 1.0, 0.3, 0.8))
	st.add_vertex(Vector3(-s, 0, 0))
	st.set_color(Color(0.2, 1.0, 0.3, 0.8))
	st.add_vertex(Vector3(s, 0, 0))
	st.set_color(Color(0.2, 1.0, 0.3, 0.8))
	st.add_vertex(Vector3(0, 0, -s))
	st.set_color(Color(0.2, 1.0, 0.3, 0.8))
	st.add_vertex(Vector3(0, 0, s))
	st.set_color(Color(0.2, 1.0, 0.3, 0.8))
	st.add_vertex(Vector3(0, -s, 0))
	st.set_color(Color(0.2, 1.0, 0.3, 0.8))
	st.add_vertex(Vector3(0, s, 0))
	return st.commit()


func _make_wireframe_mesh(source: Mesh) -> ArrayMesh:
	if not source or source.get_surface_count() == 0:
		return _make_dot_mesh()
	var arrays := source.surface_get_arrays(0)
	if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
		return _make_dot_mesh()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = (
		arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] else PackedInt32Array()
	)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)

	if indices.size() >= 3:
		for i in range(0, indices.size(), 3):
			if i + 2 >= indices.size():
				break
			for edge in [[0, 1], [1, 2], [2, 0]]:
				st.set_color(Color(0.3, 0.9, 0.4, 0.5))
				st.add_vertex(verts[indices[i + edge[0]]])
				st.set_color(Color(0.3, 0.9, 0.4, 0.5))
				st.add_vertex(verts[indices[i + edge[1]]])
	else:
		# No indices — just draw edges between consecutive verts
		for i in range(0, verts.size(), 3):
			if i + 2 >= verts.size():
				break
			for edge in [[0, 1], [1, 2], [2, 0]]:
				st.set_color(Color(0.3, 0.9, 0.4, 0.5))
				st.add_vertex(verts[i + edge[0]])
				st.set_color(Color(0.3, 0.9, 0.4, 0.5))
				st.add_vertex(verts[i + edge[1]])

	return st.commit()
