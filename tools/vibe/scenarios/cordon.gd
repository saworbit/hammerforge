@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## The cordon: an AABB that restricts what the bake takes.
##
## `docs/features.md` says it "restrict[s] bake to an AABB region ... skip
## everything outside", and that the dry run "counts through the cordon and Bake
## Visible Only, so the number matches what the bake takes". Both of those are
## claims that can be measured.
##
## The AABB itself is the other half. `cordon_aabb` is a plain exported property
## and `apply_hflevel_settings()` rebuilds it from two arrays in the `.hflevel`
## with no checking, so what an ill-formed one does to a bake is worth knowing.


func id() -> String:
	return "cordon"


func summary() -> String:
	return "what the cordon excludes from a bake, and what an ill-formed cordon AABB does"


func _bid(node: Node) -> String:
	return str(node.get_meta("brush_id", ""))


func run() -> void:
	await _a_cordon_excludes_what_is_outside_it()
	await _a_cordon_with_no_volume()
	await _a_cordon_restored_from_a_malformed_state()
	await _the_dry_run_against_the_bake()


## Triangles under the baked container. Independent of anything the bake reports.
func _baked_tris(root: Node3D) -> int:
	var tris := 0
	var stack: Array = [root.baked_container]
	while not stack.is_empty():
		var node = stack.pop_back()
		if node == null:
			continue
		for child in node.get_children():
			if child is MeshInstance3D and (child as MeshInstance3D).mesh != null:
				var mesh: Mesh = (child as MeshInstance3D).mesh
				for s in range(mesh.get_surface_count()):
					var arrays: Array = mesh.surface_get_arrays(s)
					if arrays.is_empty():
						continue
					var raw_idx = arrays[Mesh.ARRAY_INDEX]
					var raw_verts = arrays[Mesh.ARRAY_VERTEX]
					if raw_idx is PackedInt32Array and not (raw_idx as PackedInt32Array).is_empty():
						tris += (raw_idx as PackedInt32Array).size() / 3
					elif raw_verts is PackedVector3Array:
						tris += (raw_verts as PackedVector3Array).size() / 3
			stack.append(child)
	return tris


## Two boxes far apart, and a cordon around one of them.
func _a_cordon_excludes_what_is_outside_it() -> void:
	var root: Node3D = await fresh_root()
	box(root, Vector3(64, 64, 64))
	box(root, Vector3(64, 64, 64), Vector3(2048, 0, 0))
	await frame()

	await root.bake_dirty()
	await frame()
	var both := _baked_tris(root)
	note("no cordon", "%d triangles" % both)

	var root2: Node3D = await fresh_root()
	box(root2, Vector3(64, 64, 64))
	box(root2, Vector3(64, 64, 64), Vector3(2048, 0, 0))
	root2.cordon_enabled = true
	root2.cordon_aabb = AABB(Vector3(-128, -128, -128), Vector3(256, 256, 256))
	await frame()
	await root2.bake_dirty()
	await frame()
	var inside := _baked_tris(root2)
	note("cordon around the brush at the origin", "%d triangles" % inside)

	if inside >= both:
		flag(
			"an enabled cordon did not exclude the brush outside it",
			(
				"two 64-unit boxes 2048 apart; a cordon covering only the one at the origin baked %d triangles against %d with no cordon"
				% [inside, both]
			)
		)


## `cordon_aabb` is an `AABB`, and an `AABB` with a negative size is a valid
## value of the type and an empty region in practice. Nothing refuses one.
func _a_cordon_with_no_volume() -> void:
	var cases: Dictionary = {
		"zero size": AABB(Vector3.ZERO, Vector3.ZERO),
		"negative size": AABB(Vector3(128, 128, 128), Vector3(-256, -256, -256)),
		"non-finite size": AABB(Vector3.ZERO, Vector3(NAN, NAN, NAN)),
		"non-finite position": AABB(Vector3(NAN, 0, 0), Vector3(256, 256, 256)),
	}
	for label in cases:
		var root: Node3D = await fresh_root()
		box(root, Vector3(64, 64, 64))
		root.cordon_enabled = true
		root.cordon_aabb = cases[label]
		await frame()
		var ok: bool = await root.bake_dirty()
		await frame()
		var tris := _baked_tris(root)
		note(
			"cordon with a %s" % label,
			(
				"reads back %s; bake returned %s and produced %d triangles"
				% [root.cordon_aabb, ok, tris]
			)
		)
		if ok and tris == 0:
			known(
				377,
				"an enabled cordon with a %s silently bakes an empty level" % label,
				(
					"the level holds one 64-unit box at the origin; cordon_aabb is %s and the bake reports success with %d triangles. Nothing refuses the AABB and nothing says the output is empty because of it."
					% [root.cordon_aabb, tris]
				)
			)
		for problem in HFVibe.check_invariants(root):
			flag("with a %s cordon: %s" % [label, problem])


## The `.hflevel` path. `apply_hflevel_settings()` rebuilds the AABB from two
## arrays and checks neither.
func _a_cordon_restored_from_a_malformed_state() -> void:
	var root: Node3D = await fresh_root()
	box(root, Vector3(64, 64, 64))
	await frame()
	var settings: Dictionary = root.state_system.capture_hflevel_settings()

	var cases: Dictionary = {
		"negative size": [[128.0, 128.0, 128.0], [-256.0, -256.0, -256.0]],
		"non-finite size": [[0.0, 0.0, 0.0], [NAN, NAN, NAN]],
		"short arrays": [[0.0], [256.0]],
		"string entries": [["a", "b", "c"], ["d", "e", "f"]],
	}
	for label in cases:
		var poisoned: Dictionary = settings.duplicate(true)
		poisoned["cordon_enabled"] = true
		poisoned["cordon_aabb_pos"] = cases[label][0]
		poisoned["cordon_aabb_size"] = cases[label][1]
		root.state_system.apply_hflevel_settings(poisoned)
		await frame()
		note(
			"a .hflevel carrying a cordon with %s" % label,
			"cordon_enabled %s, cordon_aabb %s" % [root.cordon_enabled, root.cordon_aabb]
		)
	root.cordon_enabled = false
	root.cordon_aabb = AABB(Vector3(-128, -128, -128), Vector3(256, 256, 256))


## `docs/features.md`: the dry run "counts through the cordon and Bake Visible
## Only, so the number matches what the bake takes".
func _the_dry_run_against_the_bake() -> void:
	var root: Node3D = await fresh_root()
	for i in range(4):
		box(root, Vector3(64, 64, 64), Vector3(i * 512, 0, 0))
	root.cordon_enabled = true
	# Covers the first two of the four.
	root.cordon_aabb = AABB(Vector3(-64, -64, -64), Vector3(640, 128, 128))
	await frame()

	var dry: Dictionary = root.bake_dry_run()
	note("bake_dry_run with a cordon over 2 of 4 brushes", dry)

	await root.bake_dirty()
	await frame()
	var tris := _baked_tris(root)
	# A 64-unit box bakes to 12 triangles.
	var baked_boxes := tris / 12
	note("the bake that followed", "%d triangles, which is %d box(es)" % [tris, baked_boxes])

	# The dry run reports per container; "draft" is the one these four are in.
	var claimed: int = int(dry.get("draft", -1))
	note("the count the dry run reports", claimed)
	if claimed >= 0 and claimed != baked_boxes:
		flag(
			"bake_dry_run does not agree with the bake it is predicting",
			(
				"four 64-unit boxes with a cordon over two of them: the dry run says %d and the bake produced %d triangles, which is %d box(es). docs/features.md says the dry run counts through the cordon so the number matches what the bake takes."
				% [claimed, tris, baked_boxes]
			)
		)
