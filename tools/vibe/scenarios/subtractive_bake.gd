@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## One subtract brush, and what it does to the rest of the map.
##
## Subtraction is not an advanced feature in this lineage -- it is how you cut a
## window, a doorway, an alcove or a vent, and a real map has dozens. `cutting`
## checks that carve and hollow change the volume they should. `bake-materials`
## checks that per-face materials reach the baked mesh. Neither one has a
## subtractor and a textured level at the same time, and that combination is the
## whole of a mapper's Tuesday.
##
## `_has_effective_structural_subtractors()` is the switch: any one of them
## anywhere in the level moves the entire bake onto the CSG path, because
## independent face triangulation has no boolean stage. What the level keeps
## across that switch is the question here.


func id() -> String:
	return "subtractive-bake"


func summary() -> String:
	return "what one subtract brush does to the materials and the cost of the whole bake"


func run() -> void:
	await _what_one_subtractor_does_to_the_materials()
	await _what_it_does_to_the_cost()
	await _what_the_mapper_is_told()


func _palette(root: Node3D, count: int) -> void:
	for i in count:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color.from_hsv(float(i) / count, 0.7, 0.9)
		mat.resource_name = "mat_%d" % i
		root.material_manager.materials.append(mat)


## A textured room: six brushes, each face given a material, the way a mapper
## leaves a room before moving on to the next one.
func _textured_room(root: Node3D) -> Array:
	var made: Array = []
	made.append(box(root, Vector3(10, 0.2, 10), Vector3(0, -0.1, 0)))
	made.append(box(root, Vector3(10, 0.2, 10), Vector3(0, 3.1, 0)))
	made.append(box(root, Vector3(10, 3, 0.3), Vector3(0, 1.5, -5)))
	made.append(box(root, Vector3(10, 3, 0.3), Vector3(0, 1.5, 5)))
	made.append(box(root, Vector3(0.3, 3, 10), Vector3(-5, 1.5, 0)))
	made.append(box(root, Vector3(0.3, 3, 10), Vector3(5, 1.5, 0)))
	for i in made.size():
		for face in made[i].faces:
			if face:
				face.material_idx = i % 6
	return made


func _surface_materials(node: Node, out: Array) -> Array:
	if node is MeshInstance3D and node.mesh:
		var m: Mesh = node.mesh
		for s in m.get_surface_count():
			var mat := m.surface_get_material(s)
			out.append(mat.resource_name if mat else "<none>")
	for c in node.get_children():
		_surface_materials(c, out)
	return out


func _what_one_subtractor_does_to_the_materials() -> void:
	var root: Node3D = await fresh_root()
	root.auto_spawn_player = false
	_palette(root, 6)
	_textured_room(root)
	await frame()
	note("bake_use_face_materials", root.bake_use_face_materials)

	await root.bake(false, false)
	await frame()
	var before := _surface_materials(root.get_node_or_null("BakedGeometry"), [])
	note("surfaces before any subtractor", before)
	var distinct_before: Dictionary = {}
	for n in before:
		distinct_before[n] = true
	note("distinct materials on the baked mesh", distinct_before.keys())

	# One window, cut into one wall. This is a single brush set to subtract.
	var cutter = box(root, Vector3(1.2, 1.2, 1.0), Vector3(0, 1.6, -5))
	cutter.operation = CSGShape3D.OPERATION_SUBTRACTION
	await frame()
	note("brushes now", root.brush_system.get_live_brush_count())
	await root.bake(false, false)
	await frame()
	var after := _surface_materials(root.get_node_or_null("BakedGeometry"), [])
	note("surfaces after adding one subtract brush", after)
	var distinct_after: Dictionary = {}
	for n in after:
		distinct_after[n] = true
	note("distinct materials on the baked mesh", distinct_after.keys())

	# Named, not counted. A cut adds a `<none>` surface for the interior it
	# exposes, so counting distinct surfaces lets a lost material hide behind a
	# gained one.
	var lost: Array = []
	for name in distinct_before:
		if not distinct_after.has(name):
			lost.append(name)
	note("materials the cut cost the level", lost)
	if not lost.is_empty():
		flag(
			"one subtract brush drops the per-face materials of the whole level",
			(
				(
					"Six textured brushes baked with %d distinct materials. Adding a single "
					+ "subtractive brush -- a window in one wall -- re-bakes the same six "
					+ "without %s. The CSG path resolves one material per brush, so a level "
					+ "that falls back to it for the cut loses the texturing of every brush in "
					+ "the map, not just the ones the cut touches. On a real map, where cutting "
					+ "a vent is routine, that is the first cut onwards."
				)
				% [distinct_before.size(), str(lost)]
			)
		)


func _what_it_does_to_the_cost() -> void:
	for with_cutter in [false, true]:
		var root: Node3D = await fresh_root()
		root.auto_spawn_player = false
		_palette(root, 6)
		for i in 60:
			box(root, Vector3(2, 3, 0.3), Vector3((i % 10) * 2.5, 1.5, (i / 10) * 4.0))
		if with_cutter:
			var c = box(root, Vector3(0.6, 0.6, 0.6), Vector3(0, 1.5, 0))
			c.operation = CSGShape3D.OPERATION_SUBTRACTION
		await frame()
		var t := Time.get_ticks_msec()
		await root.bake(false, false)
		await frame()
		var ms := Time.get_ticks_msec() - t
		var mats := _surface_materials(root.get_node_or_null("BakedGeometry"), [])
		note(
			"60 walls, one subtractor = %s" % with_cutter,
			"bake %d ms, %d surface(s)" % [ms, mats.size()]
		)


## The other half of a finding like this: whether what the mapper is told matches
## what the bake did.
##
## Silence used to be the defect, because the bake really was dropping the
## texturing and only the Console said so. Now the cut keeps it, so a message
## claiming a drop is the defect instead. Either way the check is the same one:
## the claim and the baked mesh have to agree.
func _what_the_mapper_is_told() -> void:
	var root: Node3D = await fresh_root()
	root.auto_spawn_player = false
	_palette(root, 4)
	_textured_room(root)
	var cutter = box(root, Vector3(1, 1, 1), Vector3(0, 1.5, -5))
	cutter.operation = CSGShape3D.OPERATION_SUBTRACTION
	await frame()
	var messages: Array = []
	root.user_message.connect(
		func(text: String, level: int) -> void: messages.append("[%d] %s" % [level, text])
	)
	await root.bake(false, false)
	await frame()
	note("user_message signals the bake emitted", messages)
	var claims_a_drop := messages.filter(
		func(m: String) -> bool: return m.contains("Per-face materials were not baked")
	)
	note("of those, ones claiming the face materials were dropped", claims_a_drop)

	var baked := _surface_materials(root.get_node_or_null("BakedGeometry"), [])
	var painted: Array = []
	for mat in root.material_manager.materials:
		if mat and baked.has(mat.resource_name):
			painted.append(mat.resource_name)
	note("palette materials that reached the baked mesh", painted)
	var kept_them: bool = painted.size() == root.material_manager.materials.size()

	if kept_them and not claims_a_drop.is_empty():
		flag(
			"the bake says it dropped the face materials and then bakes them",
			(
				(
					"Every palette material is on the baked mesh, and the bake sent %s. A mapper "
					+ "who believes it goes looking for a setting to change and there is nothing "
					+ "wrong to fix."
				)
				% str(claims_a_drop)
			)
		)
	elif not kept_them and claims_a_drop.is_empty():
		flag(
			"the cut cost the level its face materials and nothing said so",
			(
				(
					"Only %d of %d palette materials reached the baked mesh, and the bake emitted "
					+ "no user_message about it. A Console line is not where a mapper is looking."
				)
				% [painted.size(), root.material_manager.materials.size()]
			)
		)
