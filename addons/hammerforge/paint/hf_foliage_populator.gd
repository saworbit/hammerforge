@tool
class_name HFFoliagePopulator
extends RefCounted


class FoliageSettings:
	var mesh: Mesh = null
	var density: float = 1.0  # instances per cell
	var min_height: float = 0.0
	var max_height: float = 1000.0
	var max_slope: float = 45.0  # degrees
	var scale_range: Vector2 = Vector2(0.8, 1.2)
	var random_rotation: bool = true
	var seed: int = 0


func populate(
	layer: HFPaintLayer, settings: FoliageSettings, parent: Node3D
) -> MultiMeshInstance3D:
	if not settings.mesh or not layer or not layer.grid:
		return null

	var transforms: Array[Transform3D] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = settings.seed
	var grid := layer.grid

	for cid in layer.get_chunk_ids():
		var size := layer.chunk_size
		var origin := Vector2i(cid.x * size, cid.y * size)
		for ly in range(size):
			for lx in range(size):
				var cell := origin + Vector2i(lx, ly)
				if not layer.get_cell(cell):
					continue
				var h := layer.get_height_at(cell)
				if h < settings.min_height or h > settings.max_height:
					continue
				# Slope check via finite difference
				var h_right := layer.get_height_at(cell + Vector2i(1, 0))
				var h_up := layer.get_height_at(cell + Vector2i(0, 1))
				var slope_rad := atan(
					maxf(absf(h_right - h), absf(h_up - h)) / maxf(grid.cell_size, 0.001)
				)
				if rad_to_deg(slope_rad) > settings.max_slope:
					continue
				var count := int(settings.density)
				if rng.randf() < (settings.density - float(count)):
					count += 1
				for _i in range(count):
					var jitter := Vector2(
						rng.randf_range(-0.5, 0.5) * grid.cell_size,
						rng.randf_range(-0.5, 0.5) * grid.cell_size
					)
					var pos := grid.uv_to_world(
						grid.cell_center_uv(cell) + jitter, grid.layer_y + h
					)
					var s := rng.randf_range(settings.scale_range.x, settings.scale_range.y)
					var rot := rng.randf() * TAU if settings.random_rotation else 0.0
					var xform := Transform3D(Basis(Vector3.UP, rot).scaled(Vector3(s, s, s)), pos)
					transforms.append(xform)

	if transforms.is_empty():
		return null

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = settings.mesh
	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.name = "Foliage_%s" % layer.layer_id
	if parent:
		parent.add_child(mmi)
	return mmi
