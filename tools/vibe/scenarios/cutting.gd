@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## The operations that take a brush apart: clip, carve, hollow, inset and the
## duplicate arrays that copy the result.
##
## What these have in common is that they replace geometry. A brush goes in and
## different brushes come out, and nothing downstream re-checks the result --
## the bake takes the faces it is given. So the questions are the same each
## time: is what comes out still a closed convex solid wound the right way, does
## it still occupy the space the input did, and does an operation that refuses
## leave the level exactly as it found it.


func id() -> String:
	return "cutting"


func summary() -> String:
	return "clip, carve, hollow, inset and arrays: winding, volume and refusals"


func run() -> void:
	await _clip_halves_a_brush()
	await _clip_by_a_plane_that_misses()
	await _carve_leaves_a_shell()
	await _hollow_thickness_edges()
	await _inset_edges()
	await _array_counts()


func _bid(node: Node) -> String:
	return str(node.get_meta("brush_id", ""))


func _brush_ids(root: Node3D) -> PackedStringArray:
	var out := PackedStringArray()
	for b in root.draft_brushes_node.get_children():
		out.append(_bid(b))
	return out


## The volume of a brush's own face geometry, by the divergence theorem over its
## triangles. Independent of anything the brush says about itself.
func _volume(brush: Node3D) -> float:
	var total := 0.0
	for face in brush.faces:
		var tri: Dictionary = face.triangulate()
		var verts: PackedVector3Array = tri["verts"]
		var i := 0
		while i + 2 < verts.size():
			var a: Vector3 = brush.global_transform * verts[i]
			var b: Vector3 = brush.global_transform * verts[i + 1]
			var c: Vector3 = brush.global_transform * verts[i + 2]
			total += a.dot(b.cross(c)) / 6.0
			i += 3
	return absf(total)


func _level_volume(root: Node3D) -> float:
	var total := 0.0
	for b in root.draft_brushes_node.get_children():
		total += _volume(b)
	return total


## A plane through the middle splits the brush in two. The two halves together
## are the brush that went in -- no volume created, none lost.
func _clip_halves_a_brush() -> void:
	var root: Node3D = await fresh_root()
	var b = box(root, Vector3(128, 64, 64))
	var before := _volume(b)
	var id := _bid(b)
	var result = root.clip_brush_by_plane(id, Plane(Vector3.RIGHT, 0.0))
	await frame()
	if result == null or not result.ok:
		flag("clipping a box down the middle failed", result.message if result else "null")
		return
	var survivors: Array = root.draft_brushes_node.get_children()
	var after := _level_volume(root)
	note(
		"clip a 128x64x64 box at x = 0",
		"%d brushes, volume %.0f -> %.0f" % [survivors.size(), before, after]
	)
	if survivors.size() != 2:
		flag(
			"clipping a box down its middle does not leave two halves",
			"%d brushes on the level afterwards" % survivors.size()
		)
	if absf(after - before) > before * 0.02:
		flag(
			"clipping a box changes how much material is on the level",
			"volume %.0f before, %.0f after" % [before, after]
		)
	for s in survivors:
		var half: float = _volume(s)
		if absf(half - before * 0.5) > before * 0.02:
			flag(
				"a half of a centre-clipped box is not half its volume",
				"%.0f against %.0f" % [half, before * 0.5]
			)
	for s in survivors:
		var inward: int = HFVibe.inward_face_count(s)
		if inward > 0:
			flag("a clipped brush has %d inward faces" % inward, "clip at x = 0 on a box")
	for problem in HFVibe.check_invariants(root):
		flag("clip broke an invariant", problem)


## A plane that misses the brush entirely should either refuse or leave it
## whole. What it must not do is delete it.
func _clip_by_a_plane_that_misses() -> void:
	var root: Node3D = await fresh_root()
	var b = box(root, Vector3(64, 64, 64))
	var id := _bid(b)
	var cases := {
		"plane 10000 units away": Plane(Vector3.RIGHT, 10000.0),
		"plane tangent to one face": Plane(Vector3.RIGHT, 32.0),
		"zero normal": Plane(Vector3.ZERO, 0.0),
		"non-finite distance": Plane(Vector3.UP, NAN),
	}
	for label in cases:
		var plane: Plane = cases[label]
		var splits: bool = root.plane_splits_brush(id, plane)
		var result = root.clip_brush_by_plane(id, plane)
		await frame()
		var live: int = root.draft_brushes_node.get_child_count()
		note(
			label,
			(
				"plane_splits_brush %s, clip %s, %d brushes left"
				% [splits, "ok" if result and result.ok else "refused", live]
			)
		)
		if live == 0:
			flag("clipping by a %s deletes the brush" % label, "nothing is left on the level")
			return
		for problem in HFVibe.check_invariants(root):
			flag("clip by a %s broke an invariant" % label, problem)


## Carving one brush out of another leaves the shell around the hole.
func _carve_leaves_a_shell() -> void:
	var root: Node3D = await fresh_root()
	var target = box(root, Vector3(256, 128, 256))
	var target_volume := _volume(target)
	var cutter = box(root, Vector3(64, 64, 64))
	var cutter_volume := _volume(cutter)
	var result = root.carve_with_brush(_bid(cutter))
	await frame()
	if result == null or not result.ok:
		note(
			"carve a 64 cube out of a 256x128x256 box",
			"refused: %s" % (result.message if result else "null")
		)
		return
	var after := _level_volume(root)
	var pieces: int = root.draft_brushes_node.get_child_count()
	note(
		"carve a 64 cube out of a 256x128x256 box",
		(
			"%d pieces, total volume %.0f (was %.0f, cutter %.0f)"
			% [pieces, after, target_volume, cutter_volume]
		)
	)
	# The carve should remove the cutter's volume from the target, no more.
	var expected := target_volume - cutter_volume
	if absf(after - expected) > target_volume * 0.02:
		flag(
			"carving does not remove the cutter's volume",
			(
				"%.0f left, expected about %.0f (%.0f minus the %.0f cutter)"
				% [after, expected, target_volume, cutter_volume]
			)
		)
	var inward := 0
	for p in root.draft_brushes_node.get_children():
		inward += HFVibe.inward_face_count(p)
	if inward > 0:
		flag("carving leaves %d inward-facing faces" % inward, "across %d pieces" % pieces)
	for problem in HFVibe.check_invariants(root):
		flag("carve broke an invariant", problem)


## Hollow thickness at its edges: zero, negative, thicker than the brush, and
## non-finite. A refusal is a fine answer. A wall of nothing is not.
func _hollow_thickness_edges() -> void:
	for thickness in [16.0, 0.0, -16.0, 512.0, NAN, INF]:
		var root: Node3D = await fresh_root()
		var b = box(root, Vector3(256, 256, 256))
		var before := _volume(b)
		var result = root.hollow_brush_by_id(_bid(b), thickness)
		await frame()
		var ok: bool = result != null and result.ok
		var walls: int = root.draft_brushes_node.get_child_count()
		var after := _level_volume(root)
		note(
			"hollow a 256 cube with thickness %s" % thickness,
			(
				"%s, %d brushes, volume %.0f (solid was %.0f)"
				% ["ok" if ok else "refused", walls, after, before]
			)
		)
		if not ok:
			continue
		if after <= 0.0 or not is_finite(after):
			flag(
				"hollow with thickness %s reports success and leaves no volume" % thickness,
				"%d brushes totalling %.0f" % [walls, after]
			)
		if after > before * 1.01:
			flag(
				(
					"hollow with thickness %s leaves more material than the solid brush had"
					% thickness
				),
				"%.0f against %.0f" % [after, before]
			)
		for problem in HFVibe.check_invariants(root):
			flag("hollow with thickness %s broke an invariant" % thickness, problem)


## Inset distance and height at their edges. An inset deeper than the face is
## wide has nowhere to go.
func _inset_edges() -> void:
	for pair in [[8.0, 16.0], [0.0, 0.0], [-8.0, -16.0], [1000.0, 1000.0], [NAN, 8.0], [8.0, INF]]:
		var root: Node3D = await fresh_root()
		var b = box(root, Vector3(64, 64, 64))
		var ok: bool = root.inset_face(_bid(b), 0, pair[0], pair[1])
		await frame()
		var inward: int = HFVibe.inward_face_count(b)
		var extent := HFVibe.local_extent(b)
		note(
			"inset face 0 by %s, height %s" % [pair[0], pair[1]],
			(
				"%s, %d faces, %d inward, extent %s"
				% ["ok" if ok else "refused", b.faces.size(), inward, extent]
			)
		)
		if not ok:
			continue
		if not extent.is_finite():
			known(
				340,
				"inset with distance %s height %s leaves non-finite geometry" % [pair[0], pair[1]],
				"local extent %s" % extent
			)
		if inward > 0:
			known(
				339,
				(
					"inset with distance %s height %s leaves %d inward faces"
					% [pair[0], pair[1], inward]
				)
			)
		for problem in HFVibe.check_invariants(root):
			known(340, "inset %s/%s broke an invariant" % [pair[0], pair[1]], problem)


## Array counts at their edges. #300 put a 256 cap on the dock's linear path;
## these are the other two paths and the numbers either side of the cap.
func _array_counts() -> void:
	var root: Node3D = await fresh_root()
	var b = box(root, Vector3(32, 32, 32))
	var ids := PackedStringArray([_bid(b)])
	for count in [0, 1, -4, 257, 100000]:
		var before: int = root.draft_brushes_node.get_child_count()
		var linear = root.create_duplicate_array(ids, count, Vector3(64, 0, 0))
		await frame()
		var made: int = root.draft_brushes_node.get_child_count() - before
		note(
			"linear array of %d" % count,
			"%s, %d brushes added" % ["ok" if linear else "refused", made]
		)
		if made > 1000:
			flag(
				"a linear array of %d copies is built without a cap" % count,
				"%d brushes added in one call" % made
			)
		if linear and made < 0:
			flag("a linear array of %d removed brushes" % count, "%d fewer than before" % -made)
		if made > 0 and typeof(linear) == TYPE_STRING:
			root.remove_duplicate_array(str(linear))
			await frame()
	for counts in [Vector3i(0, 0, 0), Vector3i(-2, 2, 2), Vector3i(50, 50, 50)]:
		var before: int = root.draft_brushes_node.get_child_count()
		var grid = root.create_grid_array(ids, counts, Vector3(64, 64, 64))
		await frame()
		var made: int = root.draft_brushes_node.get_child_count() - before
		note("grid array %s" % counts, "%s, %d brushes added" % ["ok" if grid else "refused", made])
		if grid and (counts.x < 1 or counts.y < 1 or counts.z < 1):
			known(
				346,
				"a grid array with a negative count is built rather than refused",
				(
					"counts %s made %d copies; the linear path refuses a negative count outright"
					% [counts, made]
				)
			)
		if made > 1000:
			flag(
				"a grid array of %s is built without a cap" % counts,
				"%d brushes added in one call" % made
			)
		if made > 0 and typeof(grid) == TYPE_STRING:
			root.remove_duplicate_array(str(grid))
			await frame()
	for count in [0, -4, 5000]:
		var before: int = root.draft_brushes_node.get_child_count()
		var radial = root.create_radial_array(ids, count, 1, 15.0, Vector3.ZERO, 0.0)
		await frame()
		var made: int = root.draft_brushes_node.get_child_count() - before
		note(
			"radial array of %d" % count,
			"%s, %d brushes added" % ["ok" if radial else "refused", made]
		)
		if made > 1000:
			flag(
				"a radial array of %d copies is built without a cap" % count,
				"%d brushes added in one call" % made
			)
		if made > 0 and typeof(radial) == TYPE_STRING:
			root.remove_duplicate_array(str(radial))
			await frame()
	for problem in HFVibe.check_invariants(root):
		flag("arrays broke an invariant", problem)
