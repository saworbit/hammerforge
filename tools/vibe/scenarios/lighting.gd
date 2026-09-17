@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Getting light into a level, which is the step after the geometry is right.
##
## A Godot level is lit one of three ways: real-time lights, `LightmapGI`, or
## `VoxelGI`. Two of the three need the geometry to carry a second UV set and to
## be marked as static, and all three need `Light3D` nodes in the scene that
## ships. `bake-options` confirms the Lightmap UV2 toggle puts a UV2 on the mesh.
## This goes the rest of the way: what else a `LightmapGI` needs from the baked
## container, whether the unwrap can fail quietly, and what the texel size means
## in a project whose player is 1.6 units tall.


func id() -> String:
	return "lighting"


func summary() -> String:
	return "what the baked geometry gives a LightmapGI, and what it still needs by hand"


func run() -> void:
	await _what_the_baked_mesh_is_marked_as()
	await _what_the_texel_size_buys()
	await _can_the_unwrap_fail_quietly()
	await _what_a_level_has_to_light_itself_with()


func _room(root: Node3D) -> void:
	box(root, Vector3(10, 0.2, 10), Vector3(0, -0.1, 0))
	box(root, Vector3(10, 0.2, 10), Vector3(0, 3.1, 0))
	box(root, Vector3(10, 3, 0.3), Vector3(0, 1.5, -5))
	box(root, Vector3(10, 3, 0.3), Vector3(0, 1.5, 5))
	box(root, Vector3(0.3, 3, 10), Vector3(-5, 1.5, 0))
	box(root, Vector3(0.3, 3, 10), Vector3(5, 1.5, 0))


func _meshes(node: Node, out: Array) -> Array:
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		_meshes(c, out)
	return out


func _what_the_baked_mesh_is_marked_as() -> void:
	var root: Node3D = await fresh_root()
	root.auto_spawn_player = false
	_room(root)
	root.bake_lightmap_uv2 = true
	await root.bake(false, false)
	await frame()
	var container := root.get_node_or_null("BakedGeometry")
	if container == null:
		flag("lighting: nothing baked")
		return
	var rows: Array = []
	for mi in _meshes(container, []):
		var m: Mesh = mi.mesh
		var has_uv2 := false
		if m and m.get_surface_count() > 0:
			has_uv2 = (m.surface_get_format(0) & Mesh.ARRAY_FORMAT_TEX_UV2) != 0
		(
			rows
			. append(
				{
					"node": mi.name,
					"uv2": has_uv2,
					"gi_mode": mi.gi_mode,
					"lightmap_scale": mi.gi_lightmap_scale,
					"cast_shadow": mi.cast_shadow,
				}
			)
		)
	note("what a LightmapGI would see", rows)
	note("gi_mode values", "0 = DISABLED, 1 = STATIC (what LightmapGI needs), 2 = DYNAMIC")
	for r in rows:
		if int(r["gi_mode"]) != 1:
			flag(
				"a baked mesh is not marked GI_MODE_STATIC",
				(
					(
						"%s has gi_mode=%s, so LightmapGI skips it even with the UV2 the Lightmap "
						+ "toggle just produced"
					)
					% [r["node"], r["gi_mode"]]
				)
			)
		if not bool(r["uv2"]):
			flag("Lightmap UV2 was on and the baked mesh has no UV2 channel", r["node"])


func _what_the_texel_size_buys() -> void:
	var root: Node3D = await fresh_root()
	root.auto_spawn_player = false
	note("bake_lightmap_texel_size default", root.bake_lightmap_texel_size)
	note("the playtest player's height, for scale", 1.6)
	note(
		"texels across a player at the default",
		"%.1f" % (1.6 / max(root.bake_lightmap_texel_size, 0.0001))
	)
	# A 10x10 room's floor at the default texel size.
	var texels: float = (
		(10.0 / root.bake_lightmap_texel_size) * (10.0 / root.bake_lightmap_texel_size)
	)
	note("texels one 10x10 floor needs at the default", int(texels))
	note(
		"what that is as a lightmap",
		(
			"%d x %d, before any other surface in the level"
			% [int(10.0 / root.bake_lightmap_texel_size), int(10.0 / root.bake_lightmap_texel_size)]
		)
	)
	# The range the spin allows, against the range that is useful here.
	root.bake_lightmap_texel_size = 0.0
	note("after setting texel size to 0", root.bake_lightmap_texel_size)
	root.bake_lightmap_texel_size = 1000.0
	note("after setting texel size to 1000", root.bake_lightmap_texel_size)
	root.bake_lightmap_texel_size = -1.0
	note("after setting texel size to -1", root.bake_lightmap_texel_size)


func _can_the_unwrap_fail_quietly() -> void:
	# A mesh the unwrapper is known to struggle with: degenerate slivers.
	var root: Node3D = await fresh_root()
	root.auto_spawn_player = false
	for i in 8:
		box(root, Vector3(0.001, 2.0, 2.0), Vector3(i * 0.5, 1, 0))
	root.bake_lightmap_uv2 = true
	await root.bake(false, false)
	await frame()
	var container := root.get_node_or_null("BakedGeometry")
	if container == null:
		note("eight sliver brushes baked nothing", true)
		return
	var without: Array = []
	for mi in _meshes(container, []):
		var m: Mesh = mi.mesh
		if m and m.get_surface_count() > 0:
			if (m.surface_get_format(0) & Mesh.ARRAY_FORMAT_TEX_UV2) == 0:
				without.append(mi.name)
	note("sliver-brush meshes with no UV2 after asking for one", without)
	note(
		"how a failure would be reported",
		(
			"baker.gd:585 writes `var unwrapped = arr_mesh.lightmap_unwrap(...)` and then "
			+ "tests `if unwrapped is Mesh`. lightmap_unwrap() returns an Error code, never a "
			+ "Mesh, so that branch is dead and the Error is discarded. The unwrap does work, "
			+ "because it mutates the mesh in place -- but when it fails there is no warning, "
			+ "no log line and no difference in what the bake reports"
		)
	)
	if not without.is_empty():
		flag(
			"the lightmap unwrap silently produced no UV2 for %d mesh(es)" % without.size(),
			(
				"Lightmap UV2 was on, the bake reported success, and these meshes have no UV2 "
				+ "channel. A LightmapGI over this level bakes black for them and nothing said "
				+ "anything: the Error from lightmap_unwrap() is assigned and never read."
			)
		)


func _what_a_level_has_to_light_itself_with() -> void:
	var root: Node3D = await fresh_root()
	root.auto_spawn_player = false
	_room(root)
	for cls in ["light_point", "light_spot", "light_directional"]:
		(
			root
			. _restore_entity_from_info(
				{
					"entity_type": cls,
					"entity_class": cls,
					"transform": Transform3D(Basis.IDENTITY, Vector3(0, 2, 0)),
					"properties": {},
					"name": cls,
					"entity_name": cls,
				}
			)
		)
	await frame()
	var lights: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Light3D:
			lights.append(n.name)
		for c in n.get_children():
			stack.append(c)
	note("the three light classes placed", 3)
	note("Light3D nodes in the level", lights)
	await root.bake(false, false)
	await frame()
	var container := root.get_node_or_null("BakedGeometry")
	var baked_lights: Array = []
	if container:
		stack = [container]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n is Light3D:
				baked_lights.append(n.name)
			for c in n.get_children():
				stack.append(c)
	note("Light3D nodes in the baked container", baked_lights)
	if lights.is_empty() and baked_lights.is_empty():
		flag(
			"the three light entity classes put no Light3D anywhere the level keeps",
			(
				"light_point, light_spot and light_directional are Node3D placeholders with "
				+ "colour, energy and range properties. Only export_playtest_scene() turns "
				+ "them into real lights, and that writes a throwaway scene. A level saved as "
				+ "its own .tscn and used as a game scene, or a level baked and shipped, has "
				+ "no lights in it at all -- so neither a LightmapGI nor a real-time pass has "
				+ "anything to work from, however carefully the mapper placed them."
			)
		)
