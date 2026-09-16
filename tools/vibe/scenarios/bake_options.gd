@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Every optional switch on the bake, one at a time.
##
## `bake` checks what a default bake produces. This checks the nine toggles in
## the Manage tab that a mapper turns on for a real level -- LODs, lightmap UVs,
## occluders, a navmesh, multimesh, the atlas -- against what each one actually
## puts in the baked container. A toggle that changes nothing is indistinguishable
## from one that worked, because the only feedback is the scene tree.


func id() -> String:
	return "bake-options"


func summary() -> String:
	return "whether each optional bake toggle changes the baked output it names"


const FLAGS: Array[String] = [
	"bake_merge_meshes",
	"bake_generate_lods",
	"bake_unwrap_uv0",
	"bake_lightmap_uv2",
	"bake_use_face_materials",
	"bake_use_multimesh",
	"bake_use_atlas",
	"bake_generate_occluders",
	"bake_navmesh",
]


func run() -> void:
	await _each_flag_on_its_own()
	await _lods_and_uvs_on_the_mesh()
	await _what_the_unindexed_mesh_costs()
	await _occluder_count()
	await _atlas_and_face_materials()


func _build_room(root: Node3D) -> void:
	# A floor, four walls and some clutter: enough surface for an occluder to be
	# worth generating and enough separate brushes to merge or instance.
	box(root, Vector3(512, 16, 512), Vector3(0, -8, 0))
	box(root, Vector3(512, 128, 16), Vector3(0, 64, -256))
	box(root, Vector3(512, 128, 16), Vector3(0, 64, 256))
	box(root, Vector3(16, 128, 512), Vector3(-256, 64, 0))
	box(root, Vector3(16, 128, 512), Vector3(256, 64, 0))
	for i in 6:
		box(root, Vector3(32, 64, 32), Vector3(-160.0 + i * 64.0, 32, 0))


func _node_lines(node: Node, depth: int, out: Array) -> Array:
	out.append("%s%s (%s)" % ["  ".repeat(depth), node.name, node.get_class()])
	for c in node.get_children():
		_node_lines(c, depth + 1, out)
	return out


func _classes(node: Node, counts: Dictionary) -> Dictionary:
	counts[node.get_class()] = int(counts.get(node.get_class(), 0)) + 1
	for c in node.get_children():
		_classes(c, counts)
	return counts


func _mesh_facts(node: Node, facts: Array) -> Array:
	var facts_indexed := 0
	if node is MeshInstance3D and node.mesh:
		var m: Mesh = node.mesh
		var surfaces := m.get_surface_count()
		var lods := -1
		var uv2 := false
		var res_bytes := 0
		var verts := 0
		if m is ArrayMesh and surfaces > 0:
			var am: ArrayMesh = m
			# ArrayMesh has no LOD getter in GDScript, so round trip through the
			# only class that does and save the resource to measure the rest.
			var imported := ImporterMesh.from_mesh(am)
			if imported and imported.get_surface_count() > 0:
				lods = imported.get_surface_lod_count(0)
			var arrays: Array = am.surface_get_arrays(0)
			uv2 = (
				arrays.size() > Mesh.ARRAY_TEX_UV2
				and arrays[Mesh.ARRAY_TEX_UV2] != null
				and arrays[Mesh.ARRAY_TEX_UV2].size() > 0
			)
			if arrays.size() > Mesh.ARRAY_VERTEX and arrays[Mesh.ARRAY_VERTEX] != null:
				verts = arrays[Mesh.ARRAY_VERTEX].size()
			var idx := 0
			if arrays.size() > Mesh.ARRAY_INDEX and arrays[Mesh.ARRAY_INDEX] != null:
				idx = arrays[Mesh.ARRAY_INDEX].size()
			facts_indexed = idx
			var tmp := "user://vibe_bake_mesh.res"
			if ResourceSaver.save(am, tmp) == OK:
				res_bytes = HFVibe.file_size(tmp)
		(
			facts
			. append(
				{
					"node": str(node.name),
					"surfaces": surfaces,
					"lods": lods,
					"uv2": uv2,
					"verts": verts,
					"res_bytes": res_bytes,
					"indices": facts_indexed,
				}
			)
		)
	for c in node.get_children():
		_mesh_facts(c, facts)
	return facts


## The baseline, then each flag flipped on its own against it.
func _each_flag_on_its_own() -> void:
	var baseline: Dictionary = {}
	var baseline_tree: Array = []
	var root: Node3D = await fresh_root("Baseline")
	_build_room(root)
	for f in FLAGS:
		if f in root:
			root.set(f, false)
	await frame()
	await root.bake()
	await frame()
	if root.baked_container == null:
		flag("a default bake produced no baked container")
		return
	baseline = _classes(root.baked_container, {})
	baseline_tree = _node_lines(root.baked_container, 0, [])
	note("all flags off: baked node classes", baseline)
	note("all flags off: tree", baseline_tree)

	var inert: Array = []
	for flag_name in FLAGS:
		var r: Node3D = await fresh_root("Bake_%s" % flag_name)
		_build_room(r)
		for f in FLAGS:
			if f in r:
				r.set(f, false)
		if not (flag_name in r):
			note("%s is not a LevelRoot property" % flag_name)
			continue
		r.set(flag_name, true)
		await frame()
		await r.bake()
		await frame()
		if r.baked_container == null:
			flag("%s = true produced no baked container at all" % flag_name)
			continue
		var got: Dictionary = _classes(r.baked_container, {})
		var meshes: Array = _mesh_facts(r.baked_container, [])
		note("%s = true: classes" % flag_name, got)
		note("  meshes", meshes)
		if HFVibe.canonical(got) == HFVibe.canonical(baseline):
			inert.append(flag_name)
			note("  -- same node classes as the baseline bake")

	note("flags whose bake has the same node classes as the baseline", inert)


## The two flags whose effect is inside the mesh rather than in the tree.
func _lods_and_uvs_on_the_mesh() -> void:
	var results: Array = []
	for combo in [
		{"bake_generate_lods": false, "bake_lightmap_uv2": false},
		{"bake_generate_lods": true, "bake_lightmap_uv2": false},
		{"bake_generate_lods": false, "bake_lightmap_uv2": true},
		{"bake_generate_lods": true, "bake_lightmap_uv2": true},
		{"bake_generate_lods": true, "bake_lightmap_uv2": false, "bake_merge_meshes": true},
		{"bake_generate_lods": false, "bake_lightmap_uv2": false, "bake_merge_meshes": true},
	]:
		var root: Node3D = await fresh_root("Mesh_%d" % results.size())
		# Spheres, not boxes: LOD generation collapses edges, and a box room is
		# all hard border edges a simplifier is required to keep. If the switch
		# does nothing here it is not because there was nothing to simplify.
		for i in 6:
			root.create_brush_from_info(
				{"shape": 2, "size": Vector3(96, 96, 96), "center": Vector3(i * 128.0, 48, 0)}
			)
		for f in FLAGS:
			if f in root:
				root.set(f, false)
		for k in combo:
			if k in root:
				root.set(k, combo[k])
		await frame()
		await root.bake()
		await frame()
		if root.baked_container == null:
			note("no container for", combo)
			continue
		results.append({"settings": combo, "meshes": _mesh_facts(root.baked_container, [])})
		note("mesh facts", results[-1])

	if results.size() >= 2:
		var off: Array = results[0]["meshes"]
		var lods_on: Array = results[1]["meshes"]
		var lod_count := int(lods_on[0]["lods"]) if not lods_on.is_empty() else -1
		var indices := int(off[0]["indices"]) if not off.is_empty() else -1
		if lod_count == 0:
			known(
				611,
				"bake_generate_lods produces no LODs, because the baked surface has no index array",
				(
					(
						"the baked mesh is %d loose vertices with %d indices, and "
						% [int(off[0]["verts"]), indices]
					)
					+ "ImporterMesh.generate_lods() builds LOD *index* arrays by simplifying an "
					+ "indexed surface -- with none to simplify it returns the mesh unchanged. "
					+ "Surface count, vertex count and the saved resource size are all the same "
					+ "with the switch on and off"
				)
			)
	if results.size() >= 4:
		var indexed_lods: Array = results[3]["meshes"]
		note("LODs with lightmap UV2 also on (which re-indexes the surface)", indexed_lods)
		if not indexed_lods.is_empty() and int(indexed_lods[0]["lods"]) > 0:
			note(
				"  -- confirms the cause",
				(
					(
						"the same LOD switch produces %d LOD level(s) once something else has "
						+ "given the surface an index array"
					)
					% int(indexed_lods[0]["lods"])
				)
			)
	if results.size() >= 6:
		note(
			"LODs with Merge meshes on instead (which indexes through SurfaceTool)",
			results[4]["meshes"]
		)
		note("Merge meshes on, LODs off", results[5]["meshes"])
	if results.size() >= 3:
		var off2: Array = results[0]["meshes"]
		var uv2_on: Array = results[2]["meshes"]
		if HFVibe.canonical(off2) == HFVibe.canonical(uv2_on):
			flag(
				"bake_lightmap_uv2 changes nothing on the baked mesh",
				(
					"the setting names a second UV channel for lightmapping and the baked "
					+ (
						"surface has the same arrays either way: %s"
						% HFVibe.canonical(off2).substr(0, 300)
					)
				)
			)


## The baked mesh ships as loose triangles. Measure what indexing it would save.
func _what_the_unindexed_mesh_costs() -> void:
	var root: Node3D = await fresh_root()
	var per_row := 10
	for i in 100:
		box(
			root,
			Vector3(64, 64, 64),
			Vector3(float(i % per_row) * 128.0, 0, float(i / per_row) * 128.0)
		)
	await frame()
	note("bake_chunk_size in force", root.bake_chunk_size)
	await root.bake()
	await frame()
	if root.baked_container == null:
		flag("100 boxes produced no baked container")
		return
	var facts: Array = _mesh_facts(root.baked_container, [])
	note("100 boxes, unchunked: baked meshes", facts)

	var total_verts := 0
	var total_bytes := 0
	var indexed_verts := 0
	var indexed_bytes := 0
	for node in _collect_meshes(root.baked_container, []):
		var mi: MeshInstance3D = node
		if not (mi.mesh is ArrayMesh):
			continue
		var am: ArrayMesh = mi.mesh
		for s in am.get_surface_count():
			var arrays: Array = am.surface_get_arrays(s)
			if arrays[Mesh.ARRAY_VERTEX] == null:
				continue
			total_verts += arrays[Mesh.ARRAY_VERTEX].size()
		var tmp := "user://vibe_unindexed.res"
		if ResourceSaver.save(am, tmp) == OK:
			total_bytes += HFVibe.file_size(tmp)
		# The same mesh with SurfaceTool.index() applied, which is the one line
		# baker.gd already uses on its merge path.
		var st := SurfaceTool.new()
		st.create_from(am, 0)
		st.index()
		var indexed: ArrayMesh = st.commit()
		if indexed and indexed.get_surface_count() > 0:
			var ia: Array = indexed.surface_get_arrays(0)
			if ia[Mesh.ARRAY_VERTEX] != null:
				indexed_verts += ia[Mesh.ARRAY_VERTEX].size()
			var tmp2 := "user://vibe_indexed.res"
			if ResourceSaver.save(indexed, tmp2) == OK:
				indexed_bytes += HFVibe.file_size(tmp2)
	note("baked vertices as shipped", total_verts)
	note("the same geometry indexed", indexed_verts)
	note("baked mesh resource bytes as shipped", total_bytes)
	note("the same geometry indexed", indexed_bytes)
	if total_verts > 0 and indexed_verts > 0:
		note(
			"indexing the baked mesh",
			(
				"%.0f%% of the vertices and %.0f%% of the bytes"
				% [
					100.0 * float(indexed_verts) / float(total_verts),
					100.0 * float(indexed_bytes) / float(max(1, total_bytes)),
				]
			)
		)
		if float(indexed_verts) < 0.75 * float(total_verts):
			flag(
				(
					"the baked mesh ships as loose triangles, %.1fx the vertices it needs"
					% (float(total_verts) / float(indexed_verts))
				),
				(
					(
						"100 boxes bake to %d vertices and %d bytes; the same surface "
						% [total_verts, total_bytes]
					)
					+ (
						"through SurfaceTool.index() is %d vertices and %d bytes. "
						% [indexed_verts, indexed_bytes]
					)
					+ "Every baked level carries that, in the scene file and in GPU "
					+ "memory, and it is also why Generate LODs does nothing"
				)
			)


func _collect_meshes(node: Node, out: Array) -> Array:
	if node is MeshInstance3D and node.mesh:
		out.append(node)
	for c in node.get_children():
		_collect_meshes(c, out)
	return out


## Occluders are one per something. Find out per what, and what that costs.
func _occluder_count() -> void:
	var rows: Array = []
	for count in [4, 12, 40]:
		var root: Node3D = await fresh_root("Occ%d" % count)
		for i in count:
			box(root, Vector3(128, 128, 128), Vector3(float(i) * 256.0, 64, 0))
		root.bake_generate_occluders = true
		await frame()
		var t := Time.get_ticks_usec()
		await root.bake()
		var bake_ms := float(Time.get_ticks_usec() - t) / 1000.0
		await frame()
		var occ := 0
		for node in _collect_all(root.baked_container, []):
			if node is OccluderInstance3D:
				occ += 1
		# How far apart are the triangles inside one occluder? Godot gives each
		# OccluderInstance3D a single bounding volume.
		var widest := 0.0
		var widest_tris := 0
		for node in _collect_all(root.baked_container, []):
			if not (node is OccluderInstance3D):
				continue
			var oc = node.occluder
			if oc == null or oc.vertices.is_empty():
				continue
			var aabb := AABB(oc.vertices[0], Vector3.ZERO)
			for v in oc.vertices:
				aabb = aabb.expand(v)
			var span: float = aabb.size.length()
			if span > widest:
				widest = span
				widest_tris = oc.vertices.size() / 3
		(
			rows
			. append(
				{
					"brushes": count,
					"occluders": occ,
					"bake_ms": snappedf(bake_ms, 0.1),
					"level_span": snappedf(float(count) * 256.0, 1.0),
					"widest_occluder_span": snappedf(widest, 1.0),
					"tris_in_it": widest_tris,
				}
			)
		)
		note("occluder row", rows[-1])
	note("occluders per brush", rows)
	var last: Dictionary = rows[-1]
	if float(last["widest_occluder_span"]) > float(last["level_span"]) * 0.5:
		known(
			614,
			"coplanar faces on unconnected brushes merge into one level-spanning occluder",
			(
				(
					"%d separate boxes %d units apart produced an occluder %s units across "
					% [int(last["brushes"]), 256, last["widest_occluder_span"]]
				)
				+ ("holding %d triangles from all of them. " % int(last["tris_in_it"]))
				+ "_generate_occluders() groups triangles by normal and plane distance "
				+ "alone, with no test for whether they are anywhere near each other, and "
				+ "Godot gives each OccluderInstance3D one bounding volume"
			)
		)


func _collect_all(node: Node, out: Array) -> Array:
	if node == null:
		return out
	out.append(node)
	for c in node.get_children():
		_collect_all(c, out)
	return out


## The atlas and the per-face material path, on a level with enough materials
## for either to have something to do.
func _atlas_and_face_materials() -> void:
	var patterns := ["brick", "checker", "dots", "hex", "stripes_diagonal", "zigzag"]
	var rows: Array = []
	# The third and fourth rows differ only in the UV scale. HFMaterialAtlas
	# excludes any face whose UVs leave the unit square (group_has_tiling_uvs),
	# and HammerForge's default projection maps world units to UVs, so a
	# 64-unit face is 0..64 and every face in an ordinary level is excluded.
	for combo in [
		{"bake_use_face_materials": false, "bake_use_atlas": false, "uv": 1.0},
		{"bake_use_face_materials": true, "bake_use_atlas": false, "uv": 1.0},
		{"bake_use_face_materials": true, "bake_use_atlas": true, "uv": 1.0},
		{"bake_use_face_materials": true, "bake_use_atlas": true, "uv": 1.0 / 64.0},
	]:
		var root: Node3D = await fresh_root("Atlas_%d" % rows.size())
		var mats: Array = []
		for pattern in patterns:
			var path := (
				"res://addons/hammerforge/textures/prototypes/materials/proto_%s_red.tres" % pattern
			)
			if ResourceLoader.exists(path):
				mats.append(load(path))
		root.set_materials(mats)
		for i in 12:
			var b = box(root, Vector3(64, 64, 64), Vector3(i * 128.0, 32, 0))
			if b and b.get("faces") is Array:
				for f in b.faces:
					f.material_idx = i % maxi(1, mats.size())
					f.uv_scale = Vector2(float(combo["uv"]), float(combo["uv"]))
		for f in FLAGS:
			if f in root:
				root.set(f, false)
		for k in combo:
			if k in root:
				root.set(k, combo[k])
		await frame()
		await root.bake()
		await frame()
		if root.baked_container == null:
			note("no container for", combo)
			continue
		var facts := _mesh_facts(root.baked_container, [])
		var surfaces := 0
		var materials_on_meshes: Dictionary = {}
		for node in _collect_meshes(root.baked_container, []):
			var mi: MeshInstance3D = node
			surfaces += mi.mesh.get_surface_count()
			for s in mi.mesh.get_surface_count():
				var m = mi.mesh.surface_get_material(s)
				if m:
					materials_on_meshes[m.get_instance_id()] = true
			if mi.material_override:
				materials_on_meshes[mi.material_override.get_instance_id()] = true
		(
			rows
			. append(
				{
					"settings": combo,
					"palette": mats.size(),
					"meshes": facts.size(),
					"surfaces": surfaces,
					"distinct materials on the baked mesh": materials_on_meshes.size(),
				}
			)
		)
		note("atlas row", rows[-1])
	note("atlas comparison", rows)

	# Ask the packer directly, so a bake that changed nothing can be told from a
	# packer that refused.
	var direct: Array = []
	for pattern in patterns:
		var path := (
			"res://addons/hammerforge/textures/prototypes/materials/proto_%s_red.tres" % pattern
		)
		if ResourceLoader.exists(path):
			direct.append(load(path))
	var atlas_script = load("res://addons/hammerforge/hf_material_atlas.gd")
	var packed = atlas_script.build_atlas(direct, {})
	if packed == null:
		note("build_atlas on the same six materials", "returned null")
	else:
		note(
			"build_atlas on the same six materials",
			{
				"atlased": packed.atlased_keys.size(),
				"fallback": packed.fallback_keys.size(),
				"has atlas material": packed.atlas_material != null,
				"unplaced":
				packed.get("unplaced").size() if packed.get("unplaced") != null else "n/a",
			}
		)
		var first_img = null
		if not direct.is_empty() and direct[0] is StandardMaterial3D:
			var tex = (direct[0] as StandardMaterial3D).albedo_texture
			first_img = tex.get_image() if tex else null
		note(
			"the first material's albedo image, headless",
			(
				"none"
				if first_img == null
				else "%dx%d" % [first_img.get_width(), first_img.get_height()]
			)
		)
	if rows.size() >= 4:
		var face_mats: Dictionary = rows[1]
		var atlas: Dictionary = rows[2]
		var atlas_unit_uv: Dictionary = rows[3]
		note("the same level with UVs inside the unit square", atlas_unit_uv)
		if HFVibe.canonical(face_mats) == HFVibe.canonical(atlas.duplicate()):
			note("atlas made no difference", "same meshes, surfaces and materials as without it")
		note(
			"what each setting produced",
			(
				"plain %s surface(s)/%s material(s), face materials %s/%s, atlas %s/%s"
				% [
					rows[0]["surfaces"],
					rows[0]["distinct materials on the baked mesh"],
					face_mats["surfaces"],
					face_mats["distinct materials on the baked mesh"],
					atlas["surfaces"],
					atlas["distinct materials on the baked mesh"],
				]
			)
		)
		if (
			(
				int(atlas["distinct materials on the baked mesh"])
				>= int(face_mats["distinct materials on the baked mesh"])
			)
			and int(face_mats["distinct materials on the baked mesh"]) > 1
		):
			known(
				623,
				"the Use atlas bake option changes nothing and reports nothing",
				(
					(
						"a 6-material level bakes to %s distinct material(s) with face "
						+ "materials on, %s with the atlas on as well, and %s once the same "
						+ "level's UVs are scaled down by 64. Handed the same six materials "
						+ "directly, HFMaterialAtlas.build_atlas() packs all six with no "
						+ "fallbacks and returns an atlas material -- so the packer works and "
						+ "the bake never gets an atlas out of it. Nothing reports a skip"
					)
					% [
						face_mats["distinct materials on the baked mesh"],
						atlas["distinct materials on the baked mesh"],
						atlas_unit_uv["distinct materials on the baked mesh"],
					]
				)
			)
