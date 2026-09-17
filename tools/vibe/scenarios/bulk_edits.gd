@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Editing two hundred brushes at once, which is most of a mapper's day.
##
## Every transform scenario in the sweep moves one brush, or three. What a mapper
## does on a real map is select a whole wing and move it four units left, rotate
## a room ninety degrees to fit the corridor it meets, retexture every wall in a
## floor, and hide the half of the level they are not working on. Those are the
## same operations with a different argument, and the argument is what makes them
## slow or wrong.
##
## Two questions per operation: does it do the same thing to two hundred brushes
## that it does to one, and what does it cost.


func id() -> String:
	return "bulk-edits"


func summary() -> String:
	return "the Build tab's transforms and selections applied to 200 brushes at once"


const COUNT := 200


func _build(root: Node3D) -> Array:
	var made: Array = []
	for i in COUNT:
		made.append(box(root, Vector3(1, 1, 1), Vector3((i % 20) * 2.0, 0.5, (i / 20) * 2.0)))
	return made


func _ids(brushes: Array) -> Array:
	return brushes.map(func(b): return str(b.brush_id))


func _positions(brushes: Array) -> Array:
	return brushes.map(func(b): return b.global_position)


func run() -> void:
	await _nudge_two_hundred()
	await _rotate_two_hundred()
	await _retexture_two_hundred()
	await _hide_and_show_two_hundred()
	await _delete_two_hundred()


func _nudge_two_hundred() -> void:
	var root: Node3D = await fresh_root()
	var brushes := _build(root)
	await frame()
	var before := _positions(brushes)
	var t := Time.get_ticks_msec()
	root.nudge_brushes_by_id(_ids(brushes), Vector3(4, 0, 0))
	await frame()
	var ms := Time.get_ticks_msec() - t
	var after := _positions(brushes)
	note("nudging %d brushes 4 units" % COUNT, "%d ms" % ms)
	var moved := 0
	var wrong := 0
	for i in before.size():
		var d: Vector3 = after[i] - before[i]
		if d.is_equal_approx(Vector3(4, 0, 0)):
			moved += 1
		elif not d.is_equal_approx(Vector3.ZERO):
			wrong += 1
	note("brushes that moved by exactly the offset", moved)
	note("brushes that moved by something else", wrong)
	if moved != COUNT:
		flag(
			"a bulk nudge did not move every brush by the same offset",
			"%d of %d moved correctly, %d moved by something else" % [moved, COUNT, wrong]
		)
	if ms > 400:
		flag(
			"nudging %d brushes takes %d ms" % [COUNT, ms],
			(
				"a nudge is a held arrow key, so this is the interval between repeats -- at "
				+ "this cost the selection lags behind the key by a visible amount"
			)
		)


func _rotate_two_hundred() -> void:
	var root: Node3D = await fresh_root()
	var brushes := _build(root)
	await frame()
	var before := _positions(brushes)
	var pivot := Vector3(19, 0.5, 9)
	var t := Time.get_ticks_msec()
	root.rotate_managed_nodes(_ids(brushes), [], 1, 90.0, pivot)
	await frame()
	note(
		"rotating %d brushes 90 degrees about a pivot" % COUNT,
		"%d ms" % (Time.get_ticks_msec() - t)
	)
	var after := _positions(brushes)
	# A rotation about a pivot preserves every brush's distance from it.
	var kept := 0
	for i in before.size():
		var d0: float = (before[i] - pivot).length()
		var d1: float = (after[i] - pivot).length()
		if absf(d0 - d1) < 0.01:
			kept += 1
	note("brushes whose distance from the pivot is unchanged", kept)
	if kept != COUNT:
		flag(
			"a bulk rotation moved brushes off their radius from the pivot",
			"%d of %d kept their distance" % [kept, COUNT]
		)
	# And back again: four right angles is the identity.
	for _i in 3:
		root.rotate_managed_nodes(_ids(brushes), [], 1, 90.0, pivot)
	await frame()
	var round_trip := _positions(brushes)
	var home := 0
	var worst := 0.0
	for i in before.size():
		var err: float = (round_trip[i] - before[i]).length()
		worst = maxf(worst, err)
		if err < 0.01:
			home += 1
	note("brushes back where they started after four 90-degree turns", home)
	note("worst drift", worst)
	if home != COUNT:
		flag(
			"four 90-degree rotations of %d brushes is not the identity" % COUNT,
			"%d of %d returned; worst drift %.4f units" % [home, COUNT, worst]
		)


func _retexture_two_hundred() -> void:
	var root: Node3D = await fresh_root()
	for i in 4:
		var mat := StandardMaterial3D.new()
		mat.resource_name = "m%d" % i
		root.material_manager.materials.append(mat)
	var brushes := _build(root)
	await frame()
	var t := Time.get_ticks_msec()
	var faces := 0
	for b in brushes:
		for face in b.faces:
			if face:
				face.material_idx = 2
				faces += 1
	await frame()
	note("assigning one material to %d faces" % faces, "%d ms" % (Time.get_ticks_msec() - t))
	t = Time.get_ticks_msec()
	await root.bake(false, false)
	await frame()
	note("baking the retextured level", "%d ms" % (Time.get_ticks_msec() - t))
	var surfaces := 0
	var stack: Array = [root.get_node_or_null("BakedGeometry")]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n == null:
			continue
		if n is MeshInstance3D and n.mesh:
			surfaces += n.mesh.get_surface_count()
		for c in n.get_children():
			stack.append(c)
	note("surfaces after one material over everything", surfaces)
	if surfaces > 2:
		flag(
			"%d brushes all on one material bake to %d surfaces" % [COUNT, surfaces],
			(
				"the face-material path groups faces by material, so a level where every face "
				+ "shares one material is one surface and one draw call. More than that means "
				+ "the grouping is per-brush and a greyboxed map pays a draw call per box."
			)
		)


func _hide_and_show_two_hundred() -> void:
	var root: Node3D = await fresh_root()
	var brushes := _build(root)
	await frame()
	root.create_visgroup("wing_a")
	root.add_selection_to_visgroup("wing_a", brushes)
	await frame()
	var t := Time.get_ticks_msec()
	root.set_visgroup_visible("wing_a", false)
	await frame()
	note("hiding a %d-brush visgroup" % COUNT, "%d ms" % (Time.get_ticks_msec() - t))
	var hidden := 0
	for b in brushes:
		if not b.visible:
			hidden += 1
	note("brushes actually hidden", hidden)
	if hidden != COUNT:
		flag("hiding a visgroup left %d of its %d brushes visible" % [COUNT - hidden, COUNT])
	t = Time.get_ticks_msec()
	root.set_visgroup_visible("wing_a", true)
	await frame()
	note("showing it again", "%d ms" % (Time.get_ticks_msec() - t))
	var shown := 0
	for b in brushes:
		if b.visible:
			shown += 1
	note("brushes visible again", shown)
	if shown != COUNT:
		flag("showing a visgroup left %d of its %d brushes hidden" % [COUNT - shown, COUNT])


func _delete_two_hundred() -> void:
	var root: Node3D = await fresh_root()
	var brushes := _build(root)
	await frame()
	var t := Time.get_ticks_msec()
	root.delete_brushes_by_id(_ids(brushes))
	await frame()
	note("deleting %d brushes" % COUNT, "%d ms" % (Time.get_ticks_msec() - t))
	note("live brush count afterwards", root.brush_system.get_live_brush_count())
	if root.brush_system.get_live_brush_count() != 0:
		flag(
			"a bulk delete left brushes behind",
			"%d still live" % root.brush_system.get_live_brush_count()
		)
