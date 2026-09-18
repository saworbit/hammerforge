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
	await _what_fills_the_interior_a_cut_exposes()
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


## Signed volume of every baked surface, which says where the cut landed without
## needing to know what the mesh looks like.
func _baked_volume(node: Node) -> float:
	var total := 0.0
	if node is MeshInstance3D and node.mesh:
		var m: Mesh = node.mesh
		for s in m.get_surface_count():
			var verts: PackedVector3Array = m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			var i := 0
			while i + 2 < verts.size():
				total += verts[i].dot(verts[i + 1].cross(verts[i + 2])) / 6.0
				i += 3
	for c in node.get_children():
		total += _baked_volume(c)
	return total


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


## The faces a cut creates, and whether a mapper can texture them.
##
## Cutting a window leaves a reveal: the four faces the cutter carved out of the
## wall. They do not exist until the boolean runs, so no panel in the editor can
## select one. The cutter is the only handle, and the boolean already gives a
## carved face the material of the face that cut it, which is also how the
## Quake-family editors this lineage comes from behave.
func _what_fills_the_interior_a_cut_exposes() -> void:
	var root: Node3D = await fresh_root()
	root.auto_spawn_player = false
	_palette(root, 6)
	_textured_room(root)

	# One more material, used by nothing but the cutter, so finding it on the
	# baked mesh can only mean it came through the boolean.
	var reveal := StandardMaterial3D.new()
	reveal.albedo_color = Color(0.2, 0.9, 0.4)
	reveal.resource_name = "reveal_only"
	root.material_manager.materials.append(reveal)
	var reveal_idx: int = root.material_manager.materials.size() - 1

	var bare = box(root, Vector3(1.2, 1.2, 1.0), Vector3(-2, 1.6, -5))
	bare.operation = CSGShape3D.OPERATION_SUBTRACTION
	await frame()
	await root.bake(false, false)
	await frame()
	var untextured := _surface_materials(root.get_node_or_null("BakedGeometry"), [])
	note("surfaces with an untextured cutter", untextured)
	note("interiors left bare", untextured.count("<none>"))

	# The same window, with the cutter textured the way any other brush is.
	for face in bare.faces:
		if face:
			face.material_idx = reveal_idx
	bare.rebuild_preview()
	await frame()
	await root.bake(false, false)
	await frame()
	var textured := _surface_materials(root.get_node_or_null("BakedGeometry"), [])
	note("surfaces with the cutter textured", textured)
	note("the cutter's own material reached the bake", textured.has("reveal_only"))

	if not textured.has("reveal_only"):
		flag(
			"a textured cutter still leaves the interior it carved untextured",
			(
				"The cutter was given a material no other brush uses and the baked mesh "
				+ "came back without it. The reveal is the first thing a mapper sees after "
				+ "cutting a window, and nothing in the editor can reach those faces."
			)
		)

	# The other half: texturing the cutter must not cost the wall its own.
	var lost: Array = []
	for mat in root.material_manager.materials:
		if mat and mat != reveal and not textured.has(mat.resource_name):
			lost.append(mat.resource_name)
	note("room materials missing once the cutter was textured", lost)
	if not lost.is_empty():
		flag(
			"texturing the cutter cost the room its own materials",
			(
				(
					"Handing the cutter over as a mesh changed what the boolean operates on, "
					+ "and %s no longer reaches the baked mesh. A reveal is not worth a wall."
				)
				% str(lost)
			)
		)

	await _whether_texturing_a_cutter_moves_the_cut()


## Whether texturing a cutter changes where it cuts.
##
## A textured cutter stops being an exact prefab primitive and becomes a
## triangulated mesh, which is the risk: on the additive side a bad operand is
## one wrong-looking brush, on the subtractive side it is a wrong cut. The
## awkward cases are the ones a prefab is exact at and a mesh has to reproduce --
## an angle that is not axis aligned, and a mirrored brush, whose negative
## determinant inverts face winding invisibly until a bake.
func _whether_texturing_a_cutter_moves_the_cut() -> void:
	for subtracts in [true, false]:
		for placement in ["axis aligned", "rotated", "mirrored"]:
			var volumes: Array = []
			for textured in [false, true]:
				var root: Node3D = await fresh_root()
				root.auto_spawn_player = false
				_palette(root, 2)
				var wall = box(root, Vector3(6, 4, 1), Vector3(0, 2, 0))
				for face in wall.faces:
					if face:
						face.material_idx = 0
				var second = box(root, Vector3(1.5, 1.5, 3), Vector3(0.4, 2.2, 0))
				if subtracts:
					second.operation = CSGShape3D.OPERATION_SUBTRACTION
				if placement == "rotated":
					second.rotation = Vector3(0.3, 0.7, 0.2)
				elif placement == "mirrored":
					second.scale = Vector3(-1, 1, 1)
				if textured:
					for face in second.faces:
						if face:
							face.material_idx = 1
					second.rebuild_preview()
				await frame()
				await root.bake(false, false)
				await frame()
				var baked := root.get_node_or_null("BakedGeometry")
				volumes.append(absf(_baked_volume(baked)) if baked else -1.0)
			var kind: String = "cutter" if subtracts else "added brush"
			note(
				"%s %s, volume baked" % [placement, kind],
				"primitive operand %.4f, mesh operand %.4f" % [volumes[0], volumes[1]]
			)
			if volumes[0] < 0.0 or volumes[1] < 0.0:
				flag(
					"a %s %s baked nothing at all" % [placement, kind],
					"One of the two operand paths produced no baked geometry for the same level."
				)
			elif absf(volumes[0] - volumes[1]) > 0.01:
				flag(
					"texturing a %s %s changed the geometry" % [placement, kind],
					(
						(
							"The same pair of brushes bakes %.4f with the second one as a "
							+ "prefab primitive and %.4f once it is textured and goes in as a "
							+ "mesh. Texturing a brush must not change its geometry."
						)
						% [volumes[0], volumes[1]]
					)
				)


## What the two paths cost, textured and not.
##
## Keeping the materials through the boolean is not free: a textured brush is
## triangulated and snapshotted before it goes into the CSG tree, which is the
## face path's own cost moved onto the CSG path. An untextured level pays none of
## it and still goes in as a prefab primitive. The textured-with-a-cutter row is
## the one a real map pays on every bake, so it is the one to watch.
func _what_it_does_to_the_cost() -> void:
	for textured in [false, true]:
		for with_cutter in [false, true]:
			var root: Node3D = await fresh_root()
			root.auto_spawn_player = false
			_palette(root, 6)
			for i in 60:
				var wall = box(
					root, Vector3(2, 3, 0.3), Vector3((i % 10) * 2.5, 1.5, (i / 10) * 4.0)
				)
				if textured:
					for f in wall.faces.size():
						if wall.faces[f]:
							wall.faces[f].material_idx = f % 6
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
				"60 walls, textured = %s, one subtractor = %s" % [textured, with_cutter],
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
