@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## The mistakes a real map is full of, put in front of Validate.
##
## `validation` establishes what `validate_level()` reports: NaN sizes, NaN
## vertices, missing faces, non-planar faces. Every one of those is a corrupted
## brush -- something that should never exist. None of them is a mistake a
## careful mapper makes.
##
## This scenario builds a level with the mistakes people do make, one at a time,
## and asks the validator about each. A check that is missing is only worth
## reporting once you have shown the defect is real and the level is otherwise
## clean, so each case is built on its own root and measured for its own
## consequence first.


func id() -> String:
	return "map-quality"


func summary() -> String:
	return "the defects a real map has, against what Validate looks for"


func run() -> void:
	await _two_brushes_in_the_same_place()
	await _a_face_with_no_material()
	await _a_wire_aimed_at_nothing()
	await _two_entities_with_one_name()
	await _a_brush_with_no_volume()
	await _what_the_checks_are()


func _issues(root: Node3D) -> Array:
	var report: Dictionary = root.validate_level()
	var out: Array = report.get("issues", [])
	return out


func _face_count(root: Node3D) -> int:
	var n := 0
	for b in root.draft_brushes_node.get_children():
		if "faces" in b:
			n += b.faces.size()
	return n


func _baked_triangles(root: Node3D) -> int:
	var container := root.get_node_or_null("BakedGeometry")
	if container == null:
		return 0
	var tris := 0
	var stack: Array = [container]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D and node.mesh:
			var m: Mesh = node.mesh
			for s in m.get_surface_count():
				var arrays: Array = m.surface_get_arrays(s)
				var idx = arrays[Mesh.ARRAY_INDEX]
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				tris += int(idx.size() / 3) if idx != null else int(verts.size() / 3)
		for c in node.get_children():
			stack.append(c)
	return tris


## Two coincident brushes: the single most common thing to do by accident, with
## Ctrl+D and then forgetting to move the copy. The consequence is z-fighting
## and a doubled triangle count over the whole overlap.
func _two_brushes_in_the_same_place() -> void:
	var root: Node3D = await fresh_root()
	root.auto_spawn_player = false
	box(root, Vector3(6, 0.2, 6), Vector3(0, -0.1, 0))
	await frame()
	await root.bake(false, false)
	await frame()
	var tris_one := _baked_triangles(root)
	# The duplicate, left exactly where the original is.
	box(root, Vector3(6, 0.2, 6), Vector3(0, -0.1, 0))
	await frame()
	await root.bake(false, false)
	await frame()
	var tris_two := _baked_triangles(root)
	note("triangles with one floor", tris_one)
	note("triangles with a coincident duplicate on top of it", tris_two)
	var issues := _issues(root)
	note("what Validate says about it", issues)
	if issues.is_empty():
		flag(
			"Validate says nothing about two brushes occupying the same space",
			(
				(
					"An exact duplicate left on top of the original doubles the baked triangles "
					+ "(%d -> %d), z-fights in every frame the player can see it, and is what "
					+ "Ctrl+D followed by a missed drag leaves behind. The validator checks "
					+ "for NaN and for missing faces -- corrupted brushes -- and for nothing a "
					+ "mapper does by hand."
				)
				% [tris_one, tris_two]
			)
		)


func _a_face_with_no_material() -> void:
	var root: Node3D = await fresh_root()
	root.auto_spawn_player = false
	var mat := StandardMaterial3D.new()
	mat.resource_name = "wall"
	root.material_manager.materials.append(mat)
	var b = box(root, Vector3(2, 2, 2))
	await frame()
	for i in b.faces.size():
		b.faces[i].material_idx = 0 if i > 0 else -1
	note("one face left on the null slot, five textured", true)
	var issues := _issues(root)
	note("what Validate says", issues)
	if issues.is_empty():
		note(
			"an untextured face is not reported",
			(
				"it bakes as the fallback material, which reads as a deliberate choice; a "
				+ "count of untextured faces is what a mapper wants before a bake"
			)
		)


func _a_wire_aimed_at_nothing() -> void:
	var root: Node3D = await fresh_root()
	root.auto_spawn_player = false
	box(root, Vector3(6, 0.2, 6), Vector3(0, -0.1, 0))
	var button = (
		root
		. _restore_entity_from_info(
			{
				"entity_type": "func_button",
				"entity_class": "func_button",
				"transform": Transform3D(Basis.IDENTITY, Vector3(1, 1, 0)),
				"properties": {},
				"name": "b1",
				"entity_name": "b1",
			}
		)
	)
	await frame()
	root.add_entity_output(button, "OnPressed", "a_door_that_does_not_exist", "Open")
	note("outputs on the button", root.get_entity_outputs(button))
	var names: Array = []
	for c in root.entities_node.get_children():
		names.append(str(c.get_meta("entity_name", "")))
	note("entity names in the level", names)
	var issues := _issues(root)
	note("what Validate says about a wire with no target", issues)
	if issues.is_empty():
		flag(
			"Validate says nothing about an entity output aimed at a name that does not exist",
			(
				"The I/O panel lets a target be typed freely, deleting an entity leaves the "
				+ "wires pointing at it (the `entities` scenario already records that), and "
				+ "renaming one does the same. At runtime HFIORuntime looks the name up, finds "
				+ "nothing and returns quietly, so a broken wire is invisible from the level, "
				+ "from the validator and from the game. This is the one check a level with "
				+ "any scripting in it needs most."
			)
		)


func _two_entities_with_one_name() -> void:
	var root: Node3D = await fresh_root()
	root.auto_spawn_player = false
	for i in 2:
		(
			root
			. _restore_entity_from_info(
				{
					"entity_type": "func_door",
					"entity_class": "func_door",
					"transform": Transform3D(Basis.IDENTITY, Vector3(i * 2.0, 1, 0)),
					"properties": {},
					"name": "gate",
					"entity_name": "gate",
				}
			)
		)
	await frame()
	var names: Array = []
	for c in root.entities_node.get_children():
		names.append(str(c.get_meta("entity_name", "")))
	note("entity names", names)
	var issues := _issues(root)
	note("what Validate says about two entities called 'gate'", issues)
	note(
		"why this is sometimes right",
		(
			"HFIORuntime caches several nodes per name on purpose, so a two-leaf door is two "
			+ "nodes answering to one name. A duplicate is only a defect when it is not that, "
			+ "which is why a warning rather than an error is the shape this wants"
		)
	)


func _a_brush_with_no_volume() -> void:
	var root: Node3D = await fresh_root()
	box(root, Vector3(2, 2, 2))
	box(root, Vector3(2, 0.0, 2), Vector3(4, 0, 0))
	box(root, Vector3(0.0001, 2, 2), Vector3(8, 0, 0))
	await frame()
	var sizes: Array = []
	for b in root.draft_brushes_node.get_children():
		sizes.append(str(b.size))
	note("sizes asked for", ["(2, 2, 2)", "(2, 0, 2)", "(0.0001, 2, 2)"])
	note("sizes the level holds", sizes)
	note(
		"the create path clamps a collapsed axis",
		(
			"a zero or near-zero extent comes back as 0.1, so a degenerate brush cannot "
			+ "be made this way at all -- the validator never sees one because nothing "
			+ "upstream lets one through"
		)
	)
	var issues := _issues(root)
	note("what Validate says about the clamped brushes", issues)
	# The other way in: writing `size` on the node directly, which is what the
	# Inspector and a vertex edit reach.
	var victim = root.draft_brushes_node.get_child(0)
	victim.size = Vector3(2, 0, 2)
	await frame()
	note("after writing size = (2, 0, 2) on the node", str(victim.size))
	var after := _issues(root)
	note("what Validate says then", after)
	if str(victim.size) == "(2.0, 0.0, 2.0)" and after.is_empty():
		flag(
			"Validate accepts a brush whose size has a zero axis",
			(
				"`create_brush_from_info()` clamps a collapsed axis to 0.1, so this cannot "
				+ "arrive through the draw tools. Writing `size` on the node -- which is what "
				+ "the Inspector does -- puts it there anyway, and the brush then has "
				+ "coincident faces, no interior, and bakes to geometry that z-fights with "
				+ "itself. The validator checks that every number is finite and never that an "
				+ "extent is non-zero."
			)
		)


## What the validator does look at, read off the system itself, so the report
## says what is there rather than only what is not.
func _what_the_checks_are() -> void:
	var root: Node3D = await fresh_root()
	root.auto_spawn_player = false
	var vs = root.get("validation_system")
	if vs == null:
		note("no validation_system on the root", true)
		return
	var methods: Array = []
	for m in vs.get_method_list():
		var n := str(m.get("name", ""))
		if not n.begins_with("_") and not n.begins_with("get_") and not n.begins_with("set_"):
			methods.append(n)
	note("what the validation system offers", methods)
