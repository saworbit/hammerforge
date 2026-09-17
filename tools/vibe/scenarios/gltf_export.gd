@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Taking a finished level out to another program.
##
## `terrain` calls `export_baked_gltf()` once, with nothing baked, and records
## the error. Nobody has looked at what it writes when there *is* something to
## write — which is the only case a mapper ever uses it in. A glTF export is how
## a level goes to Blender to be lit, dressed, or rendered for a trailer, and to
## Substance to be textured, and into a portfolio.
##
## The questions are the ones that decide whether the file is usable when it
## opens on the other side: is the geometry there, is it the right size, does it
## carry its materials and its UVs, and what has it quietly brought with it.


func id() -> String:
	return "gltf-export"


func summary() -> String:
	return "what export_baked_gltf writes for a real level, read back off disk"


const OUT := "user://vibe_export.gltf"


func _cleanup() -> void:
	for p in [OUT, OUT.replace(".gltf", ".bin")]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func run() -> void:
	await _a_real_level_out_and_back()
	await _what_it_does_with_the_bake_extras()
	_cleanup()


func _palette(root: Node3D, n: int) -> void:
	for i in n:
		var mat := StandardMaterial3D.new()
		mat.resource_name = "m%d" % i
		mat.albedo_color = Color.from_hsv(float(i) / n, 0.6, 0.9)
		root.material_manager.materials.append(mat)


func _room(root: Node3D) -> Array:
	var made: Array = []
	made.append(box(root, Vector3(10, 0.2, 10), Vector3(0, -0.1, 0)))
	made.append(box(root, Vector3(10, 0.2, 10), Vector3(0, 3.1, 0)))
	made.append(box(root, Vector3(10, 3, 0.3), Vector3(0, 1.5, -5)))
	made.append(box(root, Vector3(10, 3, 0.3), Vector3(0, 1.5, 5)))
	made.append(box(root, Vector3(0.3, 3, 10), Vector3(-5, 1.5, 0)))
	made.append(box(root, Vector3(0.3, 3, 10), Vector3(5, 1.5, 0)))
	return made


func _walk(node: Node, out: Array) -> Array:
	out.append(node)
	for c in node.get_children():
		_walk(c, out)
	return out


func _a_real_level_out_and_back() -> void:
	var root: Node3D = await fresh_root()
	_palette(root, 4)
	var made := _room(root)
	await frame()
	for i in made.size():
		for face in made[i].faces:
			if face:
				face.material_idx = i % 4
	await root.bake(false, false)
	await frame()
	var container := root.get_node_or_null("BakedGeometry")
	if container == null:
		flag("gltf-export: nothing baked")
		return

	var err: int = root.export_baked_gltf(OUT)
	note("export_baked_gltf", "error %d" % err)
	note("bytes written", HFVibe.file_size(OUT))
	if err != OK:
		flag("export_baked_gltf failed on a level that baked", "error %d" % err)
		return
	if HFVibe.file_size(OUT) <= 0:
		flag("export_baked_gltf returned OK and wrote nothing")
		return

	# Read it back the way the other program will.
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var read_err: int = doc.append_from_file(OUT, state)
	note("reading the file back", "error %d" % read_err)
	if read_err != OK:
		flag(
			"the .gltf export cannot be read back by Godot's own importer",
			"append_from_file returned %d" % read_err
		)
		return
	var scene := doc.generate_scene(state)
	if scene == null:
		flag("the .gltf export produced no scene when read back")
		return
	var nodes: Array = _walk(scene, [])
	note("nodes in the imported scene", nodes.size())
	note(
		"node names",
		nodes.map(func(n: Node) -> String: return "%s (%s)" % [n.name, n.get_class()]).slice(0, 10)
	)

	var meshes: Array = nodes.filter(func(n: Node) -> bool: return n is MeshInstance3D and n.mesh)
	note("MeshInstance3D nodes with a mesh", meshes.size())
	if meshes.is_empty():
		flag(
			"a baked level exports to a .gltf with no geometry in it",
			"the file is %d bytes and reads back with no mesh" % HFVibe.file_size(OUT)
		)
		return

	var verts := 0
	var surfaces := 0
	var named_materials: Array = []
	var with_uv := 0
	var bounds := AABB()
	var first := true
	for mi in meshes:
		var m: Mesh = mi.mesh
		for s in m.get_surface_count():
			surfaces += 1
			var arrays: Array = m.surface_get_arrays(s)
			var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			verts += v.size()
			if arrays[Mesh.ARRAY_TEX_UV] != null:
				with_uv += 1
			var mat := m.surface_get_material(s)
			named_materials.append(mat.resource_name if mat else "<none>")
		var aabb: AABB = mi.global_transform * m.get_aabb()
		if first:
			bounds = aabb
			first = false
		else:
			bounds = bounds.merge(aabb)
	note("surfaces", surfaces)
	note("vertices", verts)
	note("surfaces carrying a UV channel", "%d of %d" % [with_uv, surfaces])
	note("material names that came back", named_materials)
	note("bounds of the exported geometry", "%s .. %s" % [bounds.position, bounds.end])
	note("the room as drawn", "10 x 3.2 x 10 units")

	if with_uv < surfaces:
		flag(
			"%d of %d exported surfaces have no UVs" % [surfaces - with_uv, surfaces],
			"a mesh with no UVs cannot be textured in the program it was exported to"
		)
	var size := bounds.size
	if absf(size.x - 10.0) > 0.5 or absf(size.z - 10.0) > 0.5:
		flag(
			"the exported geometry is not the size of the level",
			"the room is 10 x 3.2 x 10 and the export measures %s" % size
		)
	var distinct: Dictionary = {}
	for n in named_materials:
		distinct[n] = true
	note("distinct materials in the export", distinct.keys())
	if distinct.size() == 1 and distinct.has("<none>"):
		flag(
			"the .gltf export carries no materials",
			(
				"four materials were assigned across the room's faces and the baked mesh has "
				+ "a surface per material; the exported file has %d surface(s) and no material "
				+ "on any of them, so the level opens in Blender as untextured grey"
			) % surfaces
		)


## The bake can add occluders, a navmesh and collision bodies. A glTF is a
## geometry format and has nowhere to put any of them, so what happens to them
## on the way out is worth knowing before a mapper wonders why their export is
## full of invisible quads.
func _what_it_does_with_the_bake_extras() -> void:
	var root: Node3D = await fresh_root()
	_room(root)
	root.bake_generate_occluders = true
	root.bake_navmesh = true
	await root.bake(false, false)
	await frame()
	var container := root.get_node_or_null("BakedGeometry")
	if container == null:
		return
	var before: Dictionary = {}
	for n in _walk(container, []):
		before[n.get_class()] = int(before.get(n.get_class(), 0)) + 1
	note("the baked container, with occluders and a navmesh", before)

	var err: int = root.export_baked_gltf(OUT)
	note("export_baked_gltf", "error %d, %d bytes" % [err, HFVibe.file_size(OUT)])
	if err != OK:
		return
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(OUT, state) != OK:
		return
	var scene := doc.generate_scene(state)
	if scene == null:
		return
	var after: Dictionary = {}
	for n in _walk(scene, []):
		after[n.get_class()] = int(after.get(n.get_class(), 0)) + 1
	note("what came back out of the .gltf", after)
	note(
		"what a geometry format can carry",
		"meshes and transforms; collision, occluders and navmeshes have no glTF equivalent"
	)
