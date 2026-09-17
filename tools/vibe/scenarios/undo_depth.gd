@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Forty edits, then Ctrl+Z forty times.
##
## The dock registers almost every command through `HFUndoHelper.commit()`,
## which snapshots the whole level with `capture_state()` before the method runs
## and registers that dictionary as the undo half. Undoing an action is
## therefore `restore_state(the snapshot taken before it)` -- not an inverse
## operation, a whole-level replacement.
##
## That design makes one thing worth measuring and nothing else: whether
## `capture_state()` describes enough of the level that replaying it lands back
## where the level was. Any field the capture misses is a field that silently
## does not come back, and it will not come back for *any* action, so it only
## shows up when a mapper undoes past the point where they set it.
##
## `persistence` covers one round trip of `capture_state`/`restore_state`. This
## covers forty, of forty different kinds, interleaved -- which is the thing an
## evening of level building is.

const DraftEntity = preload("res://addons/hammerforge/draft_entity.gd")
const HFLevelIO = preload("res://addons/hammerforge/hflevel_io.gd")

const SAVE_PATH := "user://vibe_undo_depth.hflevel"


func id() -> String:
	return "undo-depth"


func summary() -> String:
	return "forty mixed edits, undone all the way back and redone, diffed at every step"


func run() -> void:
	await _is_a_snapshot_a_fixed_point()
	await _what_the_reorder_costs()
	await _undo_all_the_way_back()
	await _redo_all_the_way_forward()
	await _the_settings_a_snapshot_forgets()


## The smallest question underneath all of this: capture a state, restore it,
## capture again. Undo and redo are whole-level snapshots, so the second capture
## has to equal the first or every step of a long undo chain drifts.
func _is_a_snapshot_a_fixed_point() -> void:
	note("-- capture, restore, capture --")
	var root: Node3D = await fresh_root()
	root.auto_spawn_player = false
	var a = box(root, Vector3(2, 2, 2), Vector3.ZERO)
	await frame()
	var b = box(root, Vector3(2, 2, 2), Vector3(4, 0, 0))
	await frame()
	root.create_visgroup("walls")
	root.add_selection_to_visgroup("walls", [a, b])
	root.group_selection("pair", [a, b])
	await frame()

	var first: Dictionary = root.capture_state()
	note("id_counter at capture", first.get("id_counter"))
	note("brush ids at capture", _ids_in(first))
	root.restore_state(first)
	await frame()
	var second: Dictionary = root.capture_state()
	note("id_counter after one restore", second.get("id_counter"))
	note("brush ids after one restore", _ids_in(second))
	note("visgroup members after one restore", root.get_visgroup_names())
	note("group members after one restore", root.get_group_members("pair").size())

	if _ids_in(first) != _ids_in(second):
		flag(
			"restoring an undo snapshot renames every brush in it",
			(
				(
					"the ids captured were %s and the same level re-captured after one "
					+ "restore_state() holds %s. Every reference held by id -- a group, a "
					+ "visgroup, a prefab instance record, a generator's piece list, a "
					+ "duplicator's source list -- is aimed at the old ones"
				)
				% [_ids_in(first), _ids_in(second)]
			)
		)
	if int(first.get("id_counter", 0)) != int(second.get("id_counter", 0)):
		flag(
			"the brush id counter advances on every undo",
			(
				(
					"capture said %s, one restore later it says %s. Undo is a whole-level "
					+ "snapshot restore, so a long session's counter climbs by the level's "
					+ "brush count on every Ctrl+Z"
				)
				% [first.get("id_counter"), second.get("id_counter")]
			)
		)

	# Ten restores of the same snapshot: whatever drifts, drifts ten times.
	for _i in 10:
		root.restore_state(first)
		await frame()
	var tenth: Dictionary = root.capture_state()
	note("id_counter after ten restores of the same snapshot", tenth.get("id_counter"))
	note("brush ids after ten restores", _ids_in(tenth))
	note("brushes after ten restores", root.get_live_brush_count())
	note("group members after ten restores", root.get_group_members("pair").size())
	if root.get_group_members("pair").size() != 2:
		flag(
			"a group loses its members to repeated undo",
			(
				"2 brushes went in, %s are in the group after ten restores"
				% root.get_group_members("pair").size()
			)
		)


func _ids_in(state: Dictionary) -> Array:
	var out: Array = []
	for entry in state.get("brushes", []):
		if entry is Dictionary:
			out.append(str((entry as Dictionary).get("brush_id", "?")))
	return out


## `restore_state()` keeps the brushes whose record it can match and rebuilds the
## rest, and a rebuilt brush is added to the container at the end. So an undo
## moves exactly the brushes it changed to the back of the list. Brush order is
## CSG order: a SUBTRACT brush only cuts what is above it in the tree.
func _what_the_reorder_costs() -> void:
	note("-- a subtract brush, undone past, and what the bake then makes --")
	var root: Node3D = await fresh_root()
	root.auto_spawn_player = false
	# The CSG path is the one brush order decides. The per-face path is #656.
	root.bake_use_face_materials = false
	var solid = box(root, Vector3(4, 4, 4), Vector3.ZERO)
	await frame()
	var cutter = root.create_brush_from_info(
		{"shape": 0, "size": Vector3(2, 6, 2), "center": Vector3.ZERO, "operation": 2}
	)
	await frame()
	note("order as drawn", _order(root))
	note("the cutter's operation", cutter.operation)

	var path := "user://vibe_undo_depth_order.hflevel"
	root.hflevel_autosave_path = path
	root.save_hflevel(path)
	await HFVibe.settle_save(_tree, root)
	var before_bytes := HFVibe.file_size(path)
	var before_text := _brush_order_text(path)
	note("the .hflevel as drawn", "%s bytes" % before_bytes)

	# Nudge the solid, which is the edit; then take it back, which rebuilds the
	# solid and appends it after the cutter.
	var snapshot: Dictionary = root.capture_state()
	root.nudge_brushes_by_id([str(solid.brush_id)], Vector3(0, 1, 0))
	await frame()
	root.restore_state(snapshot)
	await frame()
	note("order after one undo of a nudge", _order(root))

	var path2 := "user://vibe_undo_depth_order2.hflevel"
	root.save_hflevel(path2)
	await HFVibe.settle_save(_tree, root)
	note("the .hflevel after the undo", "%s bytes" % HFVibe.file_size(path2))
	var after_text := _brush_order_text(path2)
	note("brush order in the file, before", before_text)
	note("brush order in the file, after", after_text)
	if before_text != after_text:
		known(
			660,
			"a save taken after an undo writes the brushes in a different order",
			(
				(
					"nothing about the level changed -- an edit was made and taken back -- "
					+ "and the file's brush order went from %s to %s. Every undo/redo pair a "
					+ "mapper makes rewrites the .hflevel and the .tscn with the touched "
					+ "brushes moved to the end, so version control sees a change on every "
					+ "session whether or not the level was edited"
				)
				% [before_text, after_text]
			)
		)
	var unused_ref = cutter
	if _order(root) != _order_of(snapshot):
		known(
			660,
			"an undo changes the order of the brushes in the level",
			(
				(
					"the level was %s and after restoring a snapshot of that same order it "
					+ "is %s. `restore_state()` keeps the brushes whose record still matches "
					+ "and rebuilds the rest, and a rebuilt brush is appended, so every undo "
					+ "moves the brushes it touched to the end"
				)
				% [_order_of(snapshot), _order(root)]
			)
		)


## The brush ids in the order the file records them, so a reorder is read off
## the bytes a mapper's version control would see rather than off the tree.
func _brush_order_text(path: String) -> Array:
	var data: Dictionary = HFLevelIO.load_from_path(path)
	if data.is_empty():
		return []
	var decoded = HFLevelIO.decode_variant(data)
	if not (decoded is Dictionary):
		return []
	var state = (decoded as Dictionary).get("state", {})
	if not (state is Dictionary):
		return []
	return _ids_in(state as Dictionary)


func _order(root: Node3D) -> Array:
	var out: Array = []
	if root.draft_brushes_node:
		for child in root.draft_brushes_node.get_children():
			if root.is_brush_node(child):
				out.append(str(child.get("brush_id")))
	return out


func _order_of(state: Dictionary) -> Array:
	return _ids_in(state)


func _triangles(root: Node3D) -> int:
	var total := 0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			if child is MeshInstance3D and not root.is_brush_node(child):
				var mesh: Mesh = (child as MeshInstance3D).mesh
				if mesh:
					for surf in mesh.get_surface_count():
						total += mesh.surface_get_array_len(surf) / 3
			stack.append(child)
	return total


## One edit: what it was called, and the closure that performs it.
func _script(root: Node3D) -> Array:
	var ops: Array = []
	var made: Array = []
	# Short names so every closure below stays on one line. gdformat will happily
	# break a long lambda body across lines, and GDScript cannot parse a
	# multi-line `func():` inside an array literal -- the run then dies with
	# "Unindent doesn't match the previous indentation level" pointing at the
	# closing bracket rather than at the lambda.
	var id0 := func(): return str(made[0].brush_id)
	var id1 := func(): return str(made[1].brush_id)
	var id2 := func(): return str(made[2].brush_id)
	var zero := Vector3.ZERO

	ops.append(["draw a floor", func(): made.append(_slab(root))])
	ops.append(["draw a wall", func(): made.append(_wall_z(root))])
	ops.append(["draw a second wall", func(): made.append(_wall_x(root))])
	ops.append(["add the prototype palette", func(): root.add_prototype_materials()])
	ops.append(["texture the floor", func(): _texture(root, id0.call())])
	ops.append(["set the grid to 0.25", func(): root.grid_snap = 0.25])
	ops.append(["make a visgroup", func(): root.create_visgroup("shell")])
	ops.append(["put the walls in it", func(): _to_visgroup(root, made)])
	ops.append(["hide it", func(): root.set_visgroup_visible("shell", false)])
	ops.append(["show it", func(): root.set_visgroup_visible("shell", true)])
	ops.append(["group the shell", func(): _group(root, made)])
	ops.append(["nudge the floor", func(): _nudge(root, id0.call())])
	ops.append(["rotate a wall", func(): _rotate(root, id1.call())])
	ops.append(["flip a wall", func(): root.flip_managed_nodes([id2.call()], [], 0, zero)])
	ops.append(["place a light", func(): made.append(_entity(root, "lamp"))])
	ops.append(["place a second light", func(): made.append(_entity(root, "lamp_two"))])
	ops.append(["wire one to the other", func(): _wire(root, made)])
	ops.append(["add a paint layer", func(): root.add_paint_layer()])
	ops.append(["rename it", func(): root.rename_paint_layer(0, "ground")])
	ops.append(["set the layer height", func(): root.set_layer_y(0.5)])
	ops.append(["turn texture lock off", func(): root.texture_lock = false])
	ops.append(["set a cordon", func(): _cordon(root)])
	ops.append(["turn the cordon on", func(): root.cordon_enabled = true])
	ops.append(["select two faces", func(): _select_faces(root, made)])
	ops.append(["justify them", func(): root.justify_selected_faces("fit", false)])
	ops.append(["reproject a face", func(): root.reproject_face_uvs(id0.call(), 1, 1)])
	ops.append(["set UV params on a face", func(): _uv_params(root, id0.call())])
	ops.append(["hollow a new box", func(): made.append(_hollowed(root))])
	ops.append(["clip a wall", func(): root.clip_brush_by_id(id1.call(), 0, 0.0)])
	ops.append(["array the floor", func(): _array(root, id0.call())])
	ops.append(["build an arch", func(): root.create_arch({}, Vector3(0, 0, 16))])
	ops.append(["set the bake chunk size", func(): root.bake_chunk_size = 8.0])
	ops.append(["turn face materials off", func(): root.bake_use_face_materials = false])
	ops.append(["set the autosave path", func(): root.hflevel_autosave_path = SAVE_PATH])
	ops.append(["rename the visgroup", func(): root.rename_visgroup("shell", "outer_shell")])
	ops.append(["move a brush to the floor", func(): root.move_brushes_to_floor([id2.call()])])
	ops.append(["tie brushes to an entity", func(): _tie(root, id2.call())])
	ops.append(["untie them", func(): root.untie_brushes_from_entity([id2.call()])])
	ops.append(["delete a light", func(): _delete_entity(root, made)])
	ops.append(["draw one last brush", func(): made.append(_cube(root))])
	return ops


# The bodies the closures above call, kept out of them so each stays one line.


func _slab(root: Node3D) -> Node:
	return box(root, Vector3(8, 0.25, 8), Vector3(0, -0.125, 0))


func _wall_z(root: Node3D) -> Node:
	return box(root, Vector3(8, 3, 0.25), Vector3(0, 1.5, -4))


func _wall_x(root: Node3D) -> Node:
	return box(root, Vector3(0.25, 3, 8), Vector3(-4, 1.5, 0))


func _cube(root: Node3D) -> Node:
	return box(root, Vector3(1, 1, 1), Vector3(0, 8, 0))


func _texture(root: Node3D, brush_id: String) -> void:
	root.assign_material_to_whole_brushes(2, [brush_id])


func _to_visgroup(root: Node3D, made: Array) -> void:
	root.add_selection_to_visgroup("shell", [made[1], made[2]])


func _group(root: Node3D, made: Array) -> void:
	root.group_selection("shell_group", [made[1], made[2]])


func _nudge(root: Node3D, brush_id: String) -> void:
	root.nudge_brushes_by_id([brush_id], Vector3(0, 0.5, 0))


func _rotate(root: Node3D, brush_id: String) -> void:
	root.rotate_managed_nodes([brush_id], [], 1, deg_to_rad(15.0), Vector3.ZERO)


func _entity(root: Node3D, entity_name: String) -> Node:
	var e := DraftEntity.new()
	e.entity_type = "light_point"
	e.entity_class = "light_point"
	e.name = entity_name
	root.add_entity(e)
	return e


func _wire(root: Node3D, made: Array) -> void:
	root.add_entity_output(made[3], "TurnOn", "lamp_two", "Toggle", "", 0.0, false)


func _cordon(root: Node3D) -> void:
	root.cordon_aabb = AABB(Vector3(-8, -1, -8), Vector3(16, 6, 16))


func _select_faces(root: Node3D, made: Array) -> void:
	root.clear_face_selection()
	root.toggle_face_selection(made[0], 0, true)
	root.toggle_face_selection(made[1], 0, true)


func _uv_params(root: Node3D, brush_id: String) -> void:
	root.set_face_uv_params(brush_id, 2, Vector2(2, 2), Vector2(0.25, 0.25), deg_to_rad(30.0))


func _hollowed(root: Node3D) -> Node:
	var b = box(root, Vector3(4, 3, 4), Vector3(16, 1.5, 0))
	root.hollow_brush_by_id(b.brush_id, 0.25)
	return b


func _array(root: Node3D, brush_id: String) -> void:
	root.create_duplicate_array(PackedStringArray([brush_id]), 3, Vector3(0, 4, 0))


func _tie(root: Node3D, brush_id: String) -> void:
	root.tie_brushes_to_entity([brush_id], "door_basic")


func _delete_entity(root: Node3D, made: Array) -> void:
	root.delete_entities_by_paths([str(root.get_path_to(made[4]))])


func _undo_all_the_way_back() -> void:
	note("-- forty edits, each snapshotted the way the dock snapshots them --")
	var root: Node3D = await fresh_root()
	root.auto_spawn_player = false
	var ops := _script(root)
	# The dock's undo half: `capture_state()` taken before the method runs.
	var before_states: Array[Dictionary] = []
	var labels: Array[String] = []
	for entry in ops:
		labels.append(str(entry[0]))
		var snap: Dictionary = root.capture_state()
		before_states.append(snap)
		(entry[1] as Callable).call()
		await frame()
	note("edits applied", ops.size())
	note("level after the run", HFVibe.describe_level(root).get("brushes", []).size())

	# Ctrl+Z, forty times: restore each recorded snapshot in reverse.
	var mismatches: Array[String] = []
	for i in range(ops.size() - 1, -1, -1):
		root.restore_state(before_states[i])
		await frame()
		var now: Dictionary = root.capture_state()
		var want := before_states[i]
		var moved := _keys_that_moved(want, now)
		if not moved.is_empty():
			mismatches.append("undoing '%s' left %s different" % [labels[i], moved])
			if mismatches.size() == 1:
				_explain(want, now)
	note("undo steps taken", ops.size())
	if mismatches.is_empty():
		note("every undo step landed on the state it recorded", "all %s" % ops.size())
	else:
		for line in mismatches:
			note("  mismatch", line)
		known(
			660,
			(
				"%s of %s undo steps do not land on the state they snapshotted"
				% [mismatches.size(), ops.size()]
			),
			(
				"the brushes and their contents come back; what does not is their order "
				+ "and the id counter, both of which `capture_state()` records. The detail "
				+ "is above: the same ids in a different order, and id_counter one higher "
				+ "after each restore"
			)
		)

	note("brushes after undoing everything", root.get_live_brush_count())
	note("entities after undoing everything", root.get_entity_count())
	note("visgroups after undoing everything", root.get_visgroup_names())
	note("materials after undoing everything", root.get_materials().size())
	if root.get_live_brush_count() != 0:
		flag(
			"undoing every edit does not give back an empty level",
			"%s brushes left" % root.get_live_brush_count()
		)


## And forward again, which is the other half of a mapper changing their mind.
func _redo_all_the_way_forward() -> void:
	note("-- the same forty, undone once and redone once --")
	var root: Node3D = await fresh_root()
	root.auto_spawn_player = false
	var ops := _script(root)
	var before_states: Array[Dictionary] = []
	var after_states: Array[Dictionary] = []
	var labels: Array[String] = []
	for entry in ops:
		labels.append(str(entry[0]))
		var snap: Dictionary = root.capture_state()
		before_states.append(snap)
		(entry[1] as Callable).call()
		await frame()
		var snap_after: Dictionary = root.capture_state()
		after_states.append(snap_after)

	for i in range(ops.size() - 1, -1, -1):
		root.restore_state(before_states[i])
		await frame()
	for i in range(ops.size()):
		root.restore_state(after_states[i])
		await frame()
	var final_state: Dictionary = root.capture_state()
	var moved := _keys_that_moved(after_states[after_states.size() - 1], final_state)
	note("keys that differ after undoing everything and redoing everything", moved)
	if not moved.is_empty():
		known(
			660,
			"undo to the start and redo to the end does not give the level back",
			"%s differ" % str(moved)
		)


## Which of the level's own settings a snapshot carries, read off the capture
## rather than guessed. A setting outside it is one a mapper can change and then
## lose to an unrelated Ctrl+Z.
func _the_settings_a_snapshot_forgets() -> void:
	note("-- which exported properties capture_state() carries --")
	var root: Node3D = await fresh_root()
	root.auto_spawn_player = false
	await frame()
	var state: Dictionary = root.capture_state()
	var carried := {}
	_flatten_keys(state, "", carried)
	note("keys in a capture", carried.keys().size())

	# Every exported property of the level, against what a capture holds.
	var missing: Array[String] = []
	for prop in root.get_property_list():
		if not (int(prop.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		if not (int(prop.get("usage", 0)) & PROPERTY_USAGE_EDITOR):
			continue
		var pname := str(prop.get("name", ""))
		if pname.begins_with("_") or pname == "":
			continue
		if not carried.has(pname):
			missing.append(pname)
	note("exported level properties a capture does not carry", missing.size())
	for name in missing:
		note("  not in a snapshot", name)
	# Recorded rather than flagged: `capture_full_state()` exists and does carry
	# them, and most of these are view settings nobody wants on the undo stack.
	# Which dock buttons pick the wrong one of the two is `dock-undo`'s ground.
	note(
		"the wrapper that does carry them",
		"capture_full_state(), used by exactly two commands: Load .hflevel and Import .map"
	)


## The first mismatch in detail, so the report names a field rather than a key.
func _explain(want: Dictionary, got: Dictionary) -> void:
	var want_ids: Array = _ids_in(want)
	var got_ids: Array = _ids_in(got)
	note("  snapshot held %s brushes, re-capture holds %s" % [want_ids.size(), got_ids.size()])
	note("  ids in the snapshot", want_ids)
	note("  ids after restoring it", got_ids)
	var only_want: Array = want_ids.filter(func(x): return not (x in got_ids))
	var only_got: Array = got_ids.filter(func(x): return not (x in want_ids))
	note("  in the snapshot and not after", only_want)
	note("  after and not in the snapshot", only_got)
	note("  id_counter", "%s -> %s" % [want.get("id_counter"), got.get("id_counter")])
	if want_ids != got_ids and only_want.is_empty() and only_got.is_empty():
		note("  the same brushes, in a different order")
	# Match records by id rather than by position, so a reorder does not read as
	# every record having changed.
	var by_id: Dictionary = {}
	for entry in got.get("brushes", []):
		if entry is Dictionary:
			by_id[str((entry as Dictionary).get("brush_id", "?"))] = entry
	var changed := 0
	for entry in want.get("brushes", []):
		if not (entry is Dictionary):
			continue
		var bid := str((entry as Dictionary).get("brush_id", "?"))
		if not by_id.has(bid):
			continue
		if HFVibe.canonical(entry) != HFVibe.canonical(by_id[bid]):
			changed += 1
			if changed == 1:
				note("  first record whose content differs, brush %s" % bid)
				note("    snapshot", HFVibe.canonical(entry).substr(0, 400))
				note("    re-capture", HFVibe.canonical(by_id[bid]).substr(0, 400))
	note("  records whose content differs once matched by id", changed)


func _keys_that_moved(before: Dictionary, after: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for k in before.keys():
		if not after.has(k):
			out.append("%s (gone)" % k)
		elif HFVibe.canonical(before[k]) != HFVibe.canonical(after[k]):
			out.append(str(k))
	for k in after.keys():
		if not before.has(k):
			out.append("%s (new)" % k)
	return out


func _flatten_keys(value: Variant, prefix: String, out: Dictionary) -> void:
	if not (value is Dictionary):
		return
	for k in (value as Dictionary).keys():
		out[str(k)] = true
		_flatten_keys((value as Dictionary)[k], "%s%s." % [prefix, k], out)
