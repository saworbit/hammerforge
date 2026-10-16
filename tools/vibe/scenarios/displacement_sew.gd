@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Whether Sew closes the seam between two sculpted tiles, and touches nothing
## else.
##
## Terrain built from displacements is a grid of tiles, and the seam between two
## of them is a crack in the ground unless the edge heights agree. Sew is the
## tool that makes them agree. `displacement` only records that `sew_all()`
## returned a count. This measures the seam itself, off the triangles each face
## draws (`FaceData.triangulate()`), in world space: after a sew, every vertex
## on the shared edge should be at the same height on both tiles, and no vertex
## off the shared edge should have moved.
##
## Run at three tile sizes, because the sew's tolerance is a fixed distance and
## the gap between a tile's edge vertices is not.

const SEAM := 0.001


func id() -> String:
	return "displacement-sew"


func summary() -> String:
	return "whether Sew makes two tiles' shared edge agree, and what else it moves"


func run() -> void:
	var at := 0.0
	for tile in [8.0, 2.0, 0.5]:
		for power in [3]:
			await _two_tiles(tile, power, power, Vector3(at, 0, 0))
			at += 100.0
	await _two_tiles(4.0, 3, 4, Vector3(at, 0, 0))


func _top(brush) -> int:
	for i in brush.faces.size():
		if brush.faces[i].normal.y > 0.9:
			return i
	return -1


## World positions of every displaced vertex the top face draws, deduplicated.
func _world_points(brush) -> Array:
	var face = brush.faces[_top(brush)]
	var tri: Dictionary = face.triangulate()
	var seen := {}
	var out: Array = []
	for v in tri["verts"]:
		var w: Vector3 = brush.global_transform * v
		var key := "%.4f,%.4f" % [w.x, w.z]
		if seen.has(key):
			continue
		seen[key] = true
		out.append(w)
	return out


func _two_tiles(tile: float, power_a: int, power_b: int, origin: Vector3) -> void:
	var root: Node3D = await fresh_root()
	var a = box(root, Vector3(tile, 0.2, tile), origin + Vector3(-tile * 0.5, -0.1, 0))
	var b = box(root, Vector3(tile, 0.2, tile), origin + Vector3(tile * 0.5, -0.1, 0))
	var ds = root.displacement_system
	var ok_a: bool = ds.create_displacement(str(a.brush_id), _top(a), power_a)
	var ok_b: bool = ds.create_displacement(str(b.brush_id), _top(b), power_b)
	if not (ok_a and ok_b):
		flag("could not create the displacements", [ok_a, ok_b])
		await drop_root(root)
		return
	var da = a.faces[_top(a)].displacement
	var db = b.faces[_top(b)].displacement
	da.sew_group = 1
	db.sew_group = 1
	# Tile A rises in a ramp across its width; tile B is flat. Heights vary
	# along the seam too, so averaging against a neighbour shows.
	var dim_a: int = da.get_dim()
	for r in dim_a:
		for c in dim_a:
			da.set_distance(r, c, 0.05 * tile * float(r + c) / float(dim_a))
	a.rebuild_preview()
	b.rebuild_preview()
	var before_a := _world_points(a)
	var before_b := _world_points(b)
	var sewn: int = ds.sew_all()
	a.rebuild_preview()
	b.rebuild_preview()
	var after_a := _world_points(a)
	var after_b := _world_points(b)

	var seam_x: float = origin.x
	var worst_gap := 0.0
	var seam_pairs := 0
	for p in after_a:
		if absf(p.x - seam_x) > SEAM:
			continue
		for q in after_b:
			if absf(q.x - seam_x) <= SEAM and absf(q.z - p.z) <= SEAM:
				seam_pairs += 1
				worst_gap = maxf(worst_gap, absf(p.y - q.y))
	var moved_off_seam := 0
	var worst_off := 0.0
	for pair in [[before_a, after_a], [before_b, after_b]]:
		var was: Array = pair[0]
		var now: Array = pair[1]
		for i in mini(was.size(), now.size()):
			var w: Vector3 = was[i]
			if absf(w.x - seam_x) <= SEAM:
				continue
			var d: float = (now[i] as Vector3).distance_to(w)
			if d > 0.0005:
				moved_off_seam += 1
				worst_off = maxf(worst_off, d)
	var spacing: float = tile / float(dim_a - 1)
	note(
		(
			"tiles %.2f m, powers %d/%d (edge vertices %.3f m apart), sew tolerance 0.5"
			% [tile, power_a, power_b, spacing]
		),
		(
			"sew_all %d; %d seam pairs, worst gap after %.4f m; %d vertices off the seam moved, worst %.4f m"
			% [sewn, seam_pairs, worst_gap, moved_off_seam, worst_off]
		)
	)
	if seam_pairs > 0 and worst_gap > 0.001:
		known(
			1195,
			"Sew leaves a %.3f m step in the seam between two %.1f m tiles" % [worst_gap, tile],
			"powers %d/%d, %d seam vertex pairs" % [power_a, power_b, seam_pairs]
		)
	if moved_off_seam > 0:
		known(
			1195,
			(
				"Sew moves %d vertices that are not on the shared edge (%.1f m tiles)"
				% [moved_off_seam, tile]
			),
			(
				(
					"worst %.3f m. Edge vertices are %.3f m apart and the tolerance is 0.5 m, so a "
					+ "vertex is averaged with neighbours that are not its partner"
				)
				% [worst_off, spacing]
			)
		)
	await drop_root(root)
