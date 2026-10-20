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
## Run at three tile sizes and two powers, because the gap between a tile's edge
## vertices changes with both. Sew once matched vertices within half a metre,
## which on any tile under 8 m caught a seam vertex's neighbours too (#1195).
## Where the powers differ, the finer tile's extra seam vertices have nothing to
## meet, and each should end on the line the coarser tile draws between its seam
## vertices either side, whichever tile was sculpted (#1259). Four tiles sharing
## a corner should meet there too. A sculpted floor against a wall should come
## down to the wall's foot, which cannot rise to meet it, and a second Sew should
## then move nothing (#1346).

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
	at += 100.0
	await _two_tiles(4.0, 4, 3, Vector3(at, 0, 0))
	at += 100.0
	await _four_tiles(2.0, Vector3(at, 0, 0))
	at += 100.0
	await _floor_at_a_wall(4.0, Vector3(at, 0, 0))


func _top(brush) -> int:
	return _facing(brush, Vector3.UP)


## The index of the brush's face whose normal points `dir`, or -1.
func _facing(brush, dir: Vector3) -> int:
	for i in brush.faces.size():
		if brush.faces[i].normal.dot(dir) > 0.9:
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
	# Either tile's seam vertices with no vertex of the other at their place: T
	# junctions, where the powers differ. Each should lie on the line the other
	# tile draws between its seam vertices either side.
	var t_junctions := 0
	var t_gap := 0.0
	for pair in [[after_a, after_b], [after_b, after_a]]:
		var line := _seam_line(pair[1], seam_x)
		for w in pair[0]:
			if absf(w.x - seam_x) > SEAM:
				continue
			var shared := false
			for p in line:
				if absf(p.z - w.z) <= SEAM:
					shared = true
					break
			if shared:
				continue
			t_junctions += 1
			t_gap = maxf(t_gap, absf(w.y - _height_on(line, w.z)))
	var unmatched: int = ds.unmatched_seam_vertices
	var spacing: float = tile / float(dim_a - 1)
	note(
		(
			"tiles %.2f m, powers %d/%d (edge vertices %.3f m apart)"
			% [tile, power_a, power_b, spacing]
		),
		(
			(
				"sew_all %d; %d seam pairs, worst gap after %.4f m; %d vertices off the seam "
				+ "moved, worst %.4f m; %d T junctions, worst gap to the other edge %.4f m; "
				+ "%d reported unmatched"
			)
			% [
				sewn,
				seam_pairs,
				worst_gap,
				moved_off_seam,
				worst_off,
				t_junctions,
				t_gap,
				unmatched
			]
		)
	)
	if seam_pairs == 0:
		flag("Sew test found no seam vertex pairs (%.1f m tiles)" % tile)
	if worst_gap > SEAM:
		flag(
			"Sew leaves a %.3f m step in the seam between two %.1f m tiles" % [worst_gap, tile],
			"powers %d/%d, %d seam vertex pairs" % [power_a, power_b, seam_pairs]
		)
	if moved_off_seam > 0:
		flag(
			(
				"Sew moves %d vertices that are not on the shared edge (%.1f m tiles)"
				% [moved_off_seam, tile]
			),
			"worst %.3f m, edge vertices %.3f m apart" % [worst_off, spacing]
		)
	if t_gap > SEAM:
		flag(
			"Sew leaves a %.3f m crack at a T junction between two %.1f m tiles" % [t_gap, tile],
			"powers %d/%d, %d T junctions" % [power_a, power_b, t_junctions]
		)
	if unmatched > 0:
		flag("Sew reported %d seam vertices it could not close" % unmatched, t_junctions)
	await drop_root(root)


## One tile's vertices on the seam at `seam_x`, from low z to high.
func _seam_line(points: Array, seam_x: float) -> Array:
	var line: Array = []
	for p in points:
		if absf(p.x - seam_x) <= SEAM:
			line.append(p)
	line.sort_custom(func(p: Vector3, q: Vector3) -> bool: return p.z < q.z)
	return line


## The height of a seam line at `z`, between its vertices either side.
func _height_on(line: Array, z: float) -> float:
	for k in line.size() - 1:
		var lo: Vector3 = line[k]
		var hi: Vector3 = line[k + 1]
		if z >= lo.z - SEAM and z <= hi.z + SEAM:
			return lerpf(lo.y, hi.y, clampf((z - lo.z) / (hi.z - lo.z), 0.0, 1.0))
	return NAN


## Four tiles of a terrain grid meeting at one corner, each at its own height.
## After a sew, every place two or more of them draw a vertex should be at one
## height, the shared corner included.
func _four_tiles(tile: float, origin: Vector3) -> void:
	var root: Node3D = await fresh_root()
	var ds = root.displacement_system
	var tiles: Array = []
	var i := 0
	for side in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var centre := origin + Vector3(side.x * tile * 0.5, -0.1, side.y * tile * 0.5)
		var b = box(root, Vector3(tile, 0.2, tile), centre)
		if not ds.create_displacement(str(b.brush_id), _top(b), 3):
			flag("could not create the displacement", i)
			await drop_root(root)
			return
		var d = b.faces[_top(b)].displacement
		d.sew_group = 1
		for r in d.get_dim():
			for c in d.get_dim():
				d.set_distance(r, c, 0.1 * float(i + 1))
		tiles.append(b)
		i += 1
	var sewn: int = ds.sew_all()
	var heights := {}
	for b in tiles:
		b.rebuild_preview()
		for w in _world_points(b):
			var key := "%.4f,%.4f" % [w.x, w.z]
			if not heights.has(key):
				heights[key] = []
			heights[key].append(w.y)
	var shared := 0
	var worst := 0.0
	var corner_tiles := 0
	for key in heights:
		var here: Array = heights[key]
		if here.size() < 2:
			continue
		shared += 1
		worst = maxf(worst, here.max() - here.min())
		corner_tiles = maxi(corner_tiles, here.size())
	note(
		"four %.2f m tiles round one corner" % tile,
		(
			"sew_all %d; %d shared places, %d tiles at the corner, worst spread after %.4f m"
			% [sewn, shared, corner_tiles, worst]
		)
	)
	if corner_tiles != 4:
		flag("the four tiles do not share a corner", corner_tiles)
	if worst > SEAM:
		flag("Sew leaves four tiles %.3f m apart where they meet" % worst)
	await drop_root(root)


## A floor raised by a flat 0.3 m against a wall standing on its edge, both
## displaced and in one sew group. A wall's foot vertex moves only sideways, so
## the floor's seam vertices, which share its places, should come down to the
## foot after one Sew, and a second Sew should move nothing. Sew once averaged
## the two heights, which left the floor halfway up and the wall where it was,
## and each Sew after halved the gap again (#1346).
func _floor_at_a_wall(tile: float, origin: Vector3) -> void:
	var root: Node3D = await fresh_root()
	var ds = root.displacement_system
	var floor_box = box(root, Vector3(tile, 0.2, tile), origin + Vector3(-tile * 0.5, -0.1, 0))
	var wall_box = box(root, Vector3(0.2, tile, tile), origin + Vector3(0.1, tile * 0.5, 0))
	var wall_face := _facing(wall_box, Vector3.LEFT)
	var ok_floor: bool = ds.create_displacement(str(floor_box.brush_id), _top(floor_box), 2)
	var ok_wall: bool = ds.create_displacement(str(wall_box.brush_id), wall_face, 2)
	if not (ok_floor and ok_wall):
		flag("could not create the displacements", [ok_floor, ok_wall])
		await drop_root(root)
		return
	var df = floor_box.faces[_top(floor_box)].displacement
	df.sew_group = 1
	wall_box.faces[wall_face].displacement.sew_group = 1
	for r in df.get_dim():
		for c in df.get_dim():
			df.set_distance(r, c, 0.3)
	floor_box.rebuild_preview()
	var sewn: int = ds.sew_all()
	var unmatched: int = ds.unmatched_seam_vertices
	floor_box.rebuild_preview()
	var after_first := _world_points(floor_box)
	var seam_x: float = origin.x
	var seam_vertices := 0
	var foot_gap := 0.0
	for p in after_first:
		if absf(p.x - seam_x) <= SEAM:
			seam_vertices += 1
			foot_gap = maxf(foot_gap, absf(p.y))
	var sewn_again: int = ds.sew_all()
	floor_box.rebuild_preview()
	var after_second := _world_points(floor_box)
	var moved_again := 0
	var worst_again := 0.0
	for i in mini(after_first.size(), after_second.size()):
		var d: float = (after_second[i] as Vector3).distance_to(after_first[i])
		if d > 0.0005:
			moved_again += 1
			worst_again = maxf(worst_again, d)
	note(
		"a %.1f m floor raised 0.3 m against a wall" % tile,
		(
			(
				"sew_all %d, %d reported unmatched; %d seam vertices, worst gap to the foot "
				+ "%.4f m; a second sew_all %d, moved %d vertices, worst %.4f m"
			)
			% [sewn, unmatched, seam_vertices, foot_gap, sewn_again, moved_again, worst_again]
		)
	)
	if seam_vertices == 0:
		flag("the floor has no vertices on the wall's foot")
	if foot_gap > SEAM:
		flag("Sew leaves the floor %.3f m off the wall's foot" % foot_gap)
	if unmatched > 0:
		flag("Sew reported %d seam vertices it could not close at a wall's foot" % unmatched)
	if moved_again > 0:
		flag(
			"a second Sew moves %d of the floor's vertices" % moved_again,
			"worst %.4f m" % worst_again
		)
	await drop_root(root)
