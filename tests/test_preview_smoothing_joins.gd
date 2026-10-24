extends GutTest

## The preview shades a join between two brushes in one smoothing group as the
## bake does (#1625). It smoothed within one brush only, so the segments of an
## arch showed a hard edge at every join that the bake did not have.

const HFGeneratorSystemScript = preload("res://addons/hammerforge/systems/hf_generator_system.gd")

## How near two corners are to be one, and two normals to be the same.
const NEAR := 0.002
const SAME := 0.01


func _fresh_root() -> LevelRoot:
	var root := LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	return root


func _arch(root: LevelRoot) -> Array:
	var settings: Dictionary = HFGeneratorSystemScript.default_settings("arch")
	assert_true(root.create_generator("arch", settings, Transform3D.IDENTITY).ok)
	var pieces: Array = []
	for brush in root._iter_managed_brush_nodes():
		pieces.append(brush)
	return pieces


static func _key(point: Vector3) -> Vector3i:
	return Vector3i((point / NEAR).round())


## Every corner of every triangle under `node` in the level, with its normal there:
## key -> [normals].
static func _normals_under(node: Node, out: Dictionary = {}) -> Dictionary:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh_node := node as MeshInstance3D
		var place := mesh_node.global_transform
		var turn := place.basis.inverse().transposed()
		for s in mesh_node.mesh.get_surface_count():
			var arrays: Array = mesh_node.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: Variant = arrays[Mesh.ARRAY_NORMAL]
			if not (normals is PackedVector3Array):
				continue
			for i in verts.size():
				var key := _key(place * verts[i])
				if not out.has(key):
					out[key] = []
				out[key].append((turn * (normals as PackedVector3Array)[i]).normalized())
	for child in node.get_children():
		_normals_under(child, out)
	return out


## The corners two pieces share, where a join is.
static func _joins(pieces: Array) -> Dictionary:
	var owners: Dictionary = {}
	for piece in pieces:
		var place: Transform3D = piece.global_transform
		var seen: Dictionary = {}
		for face in piece.faces:
			for corner in face.local_verts:
				seen[_key(place * corner)] = true
		for key in seen:
			owners[key] = int(owners.get(key, 0)) + 1
	var out: Dictionary = {}
	for key in owners:
		if owners[key] > 1:
			out[key] = true
	return out


static func _corners(pieces: Array) -> Dictionary:
	var out: Dictionary = {}
	for piece in pieces:
		var place: Transform3D = piece.global_transform
		for face in piece.faces:
			for corner in face.local_verts:
				out[_key(place * corner)] = true
	return out


## How many of the preview's normals at a join no normal of the bake there
## matches, and how many were held up against the bake. `everywhere` holds up
## every corner of the pieces, not only the joins between them.
func _misses(root: LevelRoot, pieces: Array, everywhere := false) -> Dictionary:
	var joins := _joins(pieces) if not everywhere else _corners(pieces)
	var shown: Dictionary = {}
	for piece in pieces:
		_normals_under(piece.mesh_instance, shown)
	var baked := _normals_under(root.baked_container)
	var misses := 0
	var held := 0
	for key in joins:
		for normal in shown.get(key, []):
			held += 1
			var matched := false
			for other in baked.get(key, []):
				if (normal as Vector3).distance_to(other) < SAME:
					matched = true
					break
			if not matched:
				misses += 1
	return {"misses": misses, "held": held}


func test_the_joins_of_an_arch_shade_as_the_bake_shades_them():
	var root := _fresh_root()
	var pieces := _arch(root)
	assert_gt(pieces.size(), 1, "fixture: an arch of several pieces")
	# The neighbours draw again at the end of the frame.
	await get_tree().process_frame
	await get_tree().process_frame
	await root.bake(true, false, 0)
	var result := _misses(root, pieces)
	assert_gt(result["held"], 0, "fixture: the pieces share corners")
	assert_eq(result["misses"], 0, "every normal at a join is one the bake has there")


func test_a_piece_moved_away_leaves_its_neighbour_shaded_as_the_bake():
	var root := _fresh_root()
	var pieces := _arch(root)
	await get_tree().process_frame
	pieces[0].global_position += Vector3(0, 0, 3)
	await get_tree().process_frame
	await get_tree().process_frame
	await root.bake(true, false, 0)
	var rest := pieces.slice(1)
	var result := _misses(root, rest, true)
	assert_gt(result["held"], 0)
	assert_eq(result["misses"], 0, "the join it left is a plain edge again, as in the bake")
