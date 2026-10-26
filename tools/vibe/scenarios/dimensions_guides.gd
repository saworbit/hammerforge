@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Dimensions (#1889, #1912) promise to follow the brushes they measure through
## a move, a turn, a resize and an undo, with no step of their own, and to come
## loose only when what they were on is gone. Each end is kept as a feature of a
## brush by its id. So this measures a doorway four ways -- corner to corner,
## face to face, edge to edge, and a corner to a free point -- and puts the walls
## through each edit, reading where every end is against where it should be,
## computed here and not by the dimension. Then the copies: a doorway duplicated
## with its dimension, a `.hflevel` and a state round trip.
##
## And the guides from points you rest on (#1887): a distance typed along a guide
## is "the next pick", so what does a Draw that starts from one do.

const HFDimensions = preload("res://addons/hammerforge/hf_dimensions.gd")
const HFSnapSystem = preload("res://addons/hammerforge/hf_snap_system.gd")
const HFBrushEntity = preload("res://addons/hammerforge/hf_brush_entity.gd")

const LEVEL_PATH := "user://vibe_dimensions_guides.hflevel"


func id() -> String:
	return "dimensions-guides"


func summary() -> String:
	return "dimensions through edits, undo, copies and saves; a typed guide distance as a draw's start"


func expected_issues() -> Array[int]:
	return [2000, 2001, 2003, 2004]


func run() -> void:
	await _dimensions_through_edits()
	await _a_doorway_copied_with_its_dimension()
	await _a_typed_guide_point_starts_a_draw()
	if FileAccess.file_exists(LEVEL_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LEVEL_PATH))


func _box(root: Node3D, brush_id: String, size: Vector3, centre: Vector3) -> Node:
	return root.create_brush_from_info(
		{"shape": 0, "size": size, "center": centre, "brush_id": brush_id}
	)


## A doorway 1.2 wide between two 1 x 3 x 1 walls at `at`, and four dimensions
## across it. Returns the dimensions by name, and what each end is on as a world
## point, for checking against later.
func _doorway(root: Node3D, at: Vector3) -> Dictionary:
	_box(root, "wall_l", Vector3(1, 3, 1), at + Vector3(-1.1, 1.5, 0))
	_box(root, "wall_r", Vector3(1, 3, 1), at + Vector3(1.1, 1.5, 0))
	var pairs := {
		"corners": [at + Vector3(-0.6, 0, 0.5), at + Vector3(0.6, 0, 0.5)],
		"faces": [at + Vector3(-0.6, 1.5, 0), at + Vector3(0.6, 1.5, 0)],
		"edges": [at + Vector3(-0.6, 1.5, 0.5), at + Vector3(0.6, 1.5, 0.5)],
		"free": [at + Vector3(1.6, 3, 0.5), at + Vector3(1.6, 5, 0.5)],
	}
	var out := {}
	for title in pairs:
		var info := HFDimensions.info_between(root, pairs[title][0], pairs[title][1], title)
		out[title] = root.entity_system.restore_entity_from_info(info)
	return out


static func _kinds(dimension: Node) -> Array:
	var data: Dictionary = dimension.entity_data
	var out: Array = []
	for key in [HFDimensions.END_A, HFDimensions.END_B]:
		var end = data.get(key, {})
		out.append(str(end.get("kind", "point")) if end is Dictionary else "?")
	return out


func _read(root: Node3D) -> Dictionary:
	var out := {}
	for d in HFDimensions.dimensions(root):
		var m := HFDimensions.measure(root, d)
		out[str(d.entity_data.get("title", d.name))] = {
			"length": snappedf(float(m["length"]), 0.0001),
			"a": (m["a"] as Vector3).snapped(Vector3.ONE * 0.0001),
			"b": (m["b"] as Vector3).snapped(Vector3.ONE * 0.0001),
			"detached": m["detached"],
		}
	return out


## A brush's middle in the world, found by id: a restore makes new nodes.
func _middle(root: Node3D, brush_id: String) -> Vector3:
	return (root.find_brush_by_id(brush_id) as Node3D).global_position


## Where the end on wall_r should be after `edit`, worked out from the corner it
## was on, carried by the wall's transform change. `local` is that corner in the
## wall's own space before the edit.
func _expect(root: Node3D, brush_id: String, local: Vector3) -> Vector3:
	var brush: Node = root.find_brush_by_id(brush_id)
	return (brush.global_transform * local).snapped(Vector3.ONE * 0.0001)


func _dimensions_through_edits() -> void:
	var root: Node3D = await fresh_root("Dimensions")
	root.hflevel_autosave_enabled = false
	var at := Vector3(0, 0, 0)
	var dims := _doorway(root, at)
	await frame()
	var kinds := {}
	for title in dims:
		kinds[title] = _kinds(dims[title])
	note("what each end attached to", kinds)
	var start := _read(root)
	note("at the start", start)
	var wall_r: Node = root.find_brush_by_id("wall_r")
	# The wall_r ends, in its own space, to carry by hand through each edit.
	var local_r := {}
	for title in ["corners", "faces", "edges"]:
		local_r[title] = wall_r.global_transform.affine_inverse() * (start[title]["b"] as Vector3)
	local_r["free"] = wall_r.global_transform.affine_inverse() * (start["free"]["a"] as Vector3)

	var edits := [
		["nudge wall_r +0.5 X", func(): root.nudge_brushes_by_id(["wall_r"], Vector3(0.5, 0, 0))],
		[
			"turn wall_r 30 degrees about its middle",
			func(): root.rotate_managed_nodes(["wall_r"], [], 1, 30.0, _middle(root, "wall_r"))
		],
		[
			"turn wall_r 90 degrees about the doorway's middle",
			func(): root.rotate_managed_nodes(["wall_r"], [], 1, 90.0, at)
		],
		[
			"tip wall_r over 90 degrees about Z",
			func(): root.rotate_managed_nodes(["wall_r"], [], 2, 90.0, _middle(root, "wall_r"))
		],
		[
			"flip wall_r on X",
			func(): root.flip_managed_nodes(["wall_r"], [], 0, _middle(root, "wall_r"))
		],
		[
			"move wall_r and both its ends' brushes together +2 Z",
			func(): root.nudge_brushes_by_id(["wall_l", "wall_r"], Vector3(0, 0, 2))
		],
	]
	for edit in edits:
		var before: Dictionary = root.capture_state()
		(edit[1] as Callable).call()
		await frame()
		var now := _read(root)
		var report := {}
		var wrong := []
		for title in ["corners", "faces", "edges", "free"]:
			var end_key := "a" if title == "free" else "b"
			var expected := _expect(root, "wall_r", local_r[title])
			var got: Vector3 = now[title][end_key]
			report[title] = [got, expected, now[title]["detached"]]
			if now[title]["detached"] or got.distance_to(expected) > 0.001:
				wrong.append(
					(
						"%s end at %s, the corner it was on is at %s%s"
						% [title, got, expected, " (detached)" if now[title]["detached"] else ""]
					)
				)
		note(edit[0], report)
		if not wrong.is_empty():
			flag(
				"a dimension's end does not follow wall_r through '%s'" % edit[0], "; ".join(wrong)
			)
		root.restore_state(before)
		await frame()
		var back := _read(root)
		for title in back:
			if back[title]["length"] != start[title]["length"] or back[title]["detached"]:
				flag(
					"undo of '%s' does not give the dimensions back" % edit[0],
					"%s: %s -> %s" % [title, start[title], back[title]]
				)

	# A resize: wall_r made thicker toward the doorway, its -X face from 0.6 to 0.1.
	var before_resize: Dictionary = root.capture_state()
	root.set_brush_transform_by_id("wall_r", Vector3(1.5, 3, 1), at + Vector3(0.85, 1.5, 0))
	await frame()
	var resized := _read(root)
	note(
		"resize wall_r 1 -> 1.5 wide toward the doorway",
		(
			"corners %.4f, faces %.4f, edges %.4f (want 0.7), detached %s"
			% [
				resized["corners"]["length"],
				resized["faces"]["length"],
				resized["edges"]["length"],
				[
					resized["corners"]["detached"],
					resized["faces"]["detached"],
					resized["edges"]["detached"]
				]
			]
		)
	)
	for title in ["corners", "faces", "edges"]:
		if absf(float(resized[title]["length"]) - 0.7) > 0.001:
			flag(
				"a resize leaves the '%s' dimension wrong" % title, "%s, want 0.7" % resized[title]
			)
	root.restore_state(before_resize)
	await frame()

	# A resize of a turned wall.
	root.rotate_managed_nodes(["wall_r"], [], 1, 30.0, _middle(root, "wall_r"))
	await frame()
	var turned_start := _read(root)
	var turned_wall: Node = root.find_brush_by_id("wall_r")
	var corner_local: Vector3 = (
		turned_wall.global_transform.affine_inverse() * (turned_start["corners"]["b"] as Vector3)
	)
	# 1 -> 2 along its own X, its -X side kept in place.
	var own_x: Vector3 = turned_wall.global_transform.basis.x.normalized()
	root.set_brush_transform_by_id(
		"wall_r", Vector3(2, 3, 1), turned_wall.global_position + own_x * 0.5
	)
	await frame()
	turned_wall = root.find_brush_by_id("wall_r")
	var turned_now := _read(root)
	# The corner on the -X side did not move in the world.
	var want: Vector3 = turned_start["corners"]["b"] as Vector3
	note(
		"resize of wall_r turned 30, 1 -> 2 along its own X, its -X side held",
		(
			"corner end %s, it was at %s, detached %s (local corner was %s)"
			% [turned_now["corners"]["b"], want, turned_now["corners"]["detached"], corner_local]
		)
	)
	if (
		turned_now["corners"]["detached"]
		or (turned_now["corners"]["b"] as Vector3).distance_to(want) > 0.001
	):
		flag(
			"a resize of a turned wall moves or loosens a dimension's corner end",
			"%s, want %s" % [turned_now["corners"], want]
		)
	root.restore_state(before_resize)
	await frame()

	# Delete and undo.
	var before_delete: Dictionary = root.capture_state()
	root.delete_brush_by_id("wall_r")
	await frame()
	var deleted := _read(root)
	root.restore_state(before_delete)
	await frame()
	var undeleted := _read(root)
	note(
		"delete wall_r",
		(
			"detached %s; after undo detached %s"
			% [deleted["corners"]["detached"], undeleted["corners"]["detached"]]
		)
	)
	if not deleted["corners"]["detached"]:
		flag("a dimension whose brush was deleted does not say it is detached")
	if undeleted["corners"]["detached"]:
		flag("undoing the delete does not reattach the dimension")

	# A clip that keeps the corner, and one that cuts it away.
	var before_clip: Dictionary = root.capture_state()
	var clip: HFOpResult = root.clip_brush_by_plane("wall_r", Plane(Vector3.RIGHT, at.x + 1.3))
	await frame()
	var clipped := _read(root)
	note(
		"clip wall_r at x 1.3, leaving its doorway side",
		"%s: corners %s" % [clip.message if clip else "null", clipped["corners"]]
	)
	var loose := []
	if clipped["corners"]["detached"]:
		loose.append("Clip at x 1.3 (the corner at x 0.6 stays a corner of the 0.6..1.3 piece)")
	root.restore_state(before_clip)
	await frame()
	_read(root)
	# A carve that takes a notch out of the far top of the wall, nowhere near the
	# doorway's bottom corner.
	_box(root, "notch", Vector3(0.4, 0.4, 2), at + Vector3(1.4, 2.9, 0))
	var carve: HFOpResult = root.carve_with_brush("notch")
	await frame()
	var carved := _read(root)
	note(
		"carve a notch from wall_r's far top corner",
		"%s: corners %s" % [carve.message if carve else "null", carved["corners"]]
	)
	if carve and carve.ok and carved["corners"]["detached"]:
		loose.append("Carve of a notch at the wall's far top")
	if not loose.is_empty():
		known(
			2003,
			"an edit that keeps a dimension's corner still detaches its end",
			(
				"%s: the bottom doorway corner (0.6, 0, 0.5) is still a corner of one of the pieces, and the end reads detached. The pieces are made with new brush ids (_piece_infos_from_faces passes none to create_brush_from_info) and the end is held by the old id; the guide says only an end whose corner the Clip cut away comes loose"
				% "; ".join(loose)
			)
		)
	root.restore_state(before_clip)
	await frame()
	_read(root)

	# A detached dimension held to the player's width, read by Validate after a
	# load, when nothing remembers where its end was last seen.
	var held: Node = null
	for d in HFDimensions.dimensions(root):
		if str(d.entity_data.get("title", "")) == "faces":
			held = d
	root.set_entity_property(held, "check", "At least player width")
	var before_gone: Dictionary = root.capture_state()
	root.delete_brush_by_id("wall_r")
	await frame()
	var says: Array = []
	for issue in root.validate_level(false).get("issues", []):
		if str(issue).begins_with("Dimension"):
			says.append(str(issue))
	note("Validate on the doorway with wall_r deleted, in the session", says)
	root.save_hflevel(LEVEL_PATH, true)
	await HFVibe.settle_save(_tree, root)
	var gone: Node3D = await fresh_root("DimensionsGone")
	gone.hflevel_autosave_enabled = false
	gone.load_hflevel(LEVEL_PATH)
	await frame()
	var says_after: Array = []
	for issue in gone.validate_level(false).get("issues", []):
		if str(issue).begins_with("Dimension"):
			says_after.append(str(issue))
	note("and after a save and load", "%s, summary %s" % [says_after, HFDimensions.summary(gone)])
	if says.is_empty() and not says_after.is_empty():
		known(
			2004,
			"Validate judges a detached dimension by a length it makes up once the level is reopened",
			(
				"with wall_r deleted the doorway dimension held to player width passes in the session (it reads its last seen 1.2 m) and after a save and load fails as %s: measure() puts a detached end with no last-seen place on the dimension's own origin, which is its other end, and failure_text() never says the dimension is detached"
				% [says_after]
			)
		)
	await drop_root(gone)
	root.restore_state(before_gone)
	await frame()
	for d in HFDimensions.dimensions(root):
		if str(d.entity_data.get("title", "")) == "faces":
			root.set_entity_property(d, "check", "None")

	# Save and load, and a state round trip.
	root.save_hflevel(LEVEL_PATH, true)
	await HFVibe.settle_save(_tree, root)
	var back: Node3D = await fresh_root("DimensionsBack")
	back.hflevel_autosave_enabled = false
	var loaded: bool = back.load_hflevel(LEVEL_PATH)
	await frame()
	var after_load := _read(back)
	note(".hflevel round trip", "load %s, %s" % [loaded, after_load])
	for title in start:
		if not after_load.has(title):
			flag(".hflevel loses the '%s' dimension" % title)
		elif after_load[title]["length"] != start[title]["length"] or after_load[title]["detached"]:
			flag(
				".hflevel changes the '%s' dimension" % title,
				"%s -> %s" % [start[title], after_load[title]]
			)
	# And the loaded level resized, which needs the faces each end was saved with.
	back.set_brush_transform_by_id("wall_r", Vector3(1.5, 3, 1), at + Vector3(0.85, 1.5, 0))
	await frame()
	var loaded_resized := _read(back)
	note("the loaded level, wall_r resized as before", "corners %s" % [loaded_resized["corners"]])
	if (
		loaded_resized["corners"]["detached"]
		or absf(float(loaded_resized["corners"]["length"]) - 0.7) > 0.001
	):
		flag(
			"after a .hflevel load a resize loosens a dimension it kept before the save",
			loaded_resized["corners"]
		)
	await drop_root(back)
	await drop_root(root)


## Ctrl+D on both walls and the dimension across them, as the plugin's Duplicate
## builds it: the copies one step along Z.
func _a_doorway_copied_with_its_dimension() -> void:
	var root: Node3D = await fresh_root("DimensionCopy")
	root.hflevel_autosave_enabled = false
	var at := Vector3(40, 0, 0)
	var dims := _doorway(root, at)
	await frame()
	var shift := Vector3(0, 0, 5)
	var brush_infos: Array = []
	for brush_id in ["wall_l", "wall_r"]:
		brush_infos.append(root.build_duplicate_info(root.find_brush_by_id(brush_id), shift))
	var entity_infos: Array = [root.build_duplicate_entity_info(dims["corners"], shift)]
	HFBrushEntity.fresh_identities(brush_infos, [], root.entity_system)
	root.create_managed_duplicates(brush_infos, entity_infos, {})
	await frame()
	var copy: Node = null
	for d in HFDimensions.dimensions(root):
		if d != dims["corners"] and str(d.entity_data.get("title", "")) == "corners":
			copy = d
	if copy == null:
		note("the duplicated dimension was not made")
		await drop_root(root)
		return
	var m := HFDimensions.measure(root, copy)
	var copy_ids: Array = []
	for info in brush_infos:
		copy_ids.append(str(info.get("brush_id", "")))
	var end_ids: Array = []
	for key in [HFDimensions.END_A, HFDimensions.END_B]:
		end_ids.append(str(copy.entity_data[key].get("brush_id", "")))
	note(
		"the copy of the corner dimension",
		(
			"sits at %s, measures from %s to %s, its ends on brushes %s, the copied walls are %s"
			% [copy.global_position, m["a"], m["b"], end_ids, copy_ids]
		)
	)
	if not copy_ids.has(end_ids[0]) and not copy_ids.has(end_ids[1]):
		known(
			2000,
			"a dimension duplicated with the walls it measures still measures the original walls",
			(
				"Duplicate of both walls and their dimension, 5 along Z: the copy is drawn from %s to %s, across the original doorway, not the copy at z+5 -- its ends keep the original brush ids %s while the copied walls are %s; nothing remaps them"
				% [m["a"], m["b"], end_ids, copy_ids]
			)
		)
		# Then a change to the copy doorway does not show on the copy dimension.
		root.nudge_brushes_by_id([copy_ids[1]], Vector3(0.5, 0, 0))
		var after := HFDimensions.measure(root, copy)
		note(
			"the copied wall_r widened by 0.5",
			"the copy dimension reads %.3f" % float(after["length"])
		)

	# Mirror Copy of the doorway and the dimension across z = 3.
	var path := str(root.get_path_to(dims["corners"]))
	var made: Dictionary = root.mirror_copy_managed_nodes(
		["wall_l", "wall_r"], [path], 4, at + Vector3(0, 0, 3)
	)
	await frame()
	for entity_path in made.get("entity_paths", []):
		var mirrored: Node = root.get_node_or_null(NodePath(str(entity_path)))
		if mirrored and HFDimensions.is_dimension(mirrored):
			var mm := HFDimensions.measure(root, mirrored)
			note(
				"Mirror Copy across z = 3: the mirrored dimension",
				"from %s to %s, mirrored walls %s" % [mm["a"], mm["b"], made.get("brush_ids", [])]
			)
	await drop_root(root)


# ---------------------------------------------------------------------------
# Guides
# ---------------------------------------------------------------------------


func _camera() -> Camera3D:
	var cam := Camera3D.new()
	_tree.get_root().add_child(cam)
	cam.global_position = Vector3(0, 40, 0)
	cam.look_at(Vector3.ZERO, Vector3.BACK)
	await frame()
	return cam


## One pointer event's worth of snap, as `plugin_snap_feedback` wraps every event.
func _pointer(root: Node3D, call: Callable, release: bool = false) -> void:
	var snap = root.snap_system
	snap.begin_pointer_event()
	call.call()
	snap.end_pointer_event(true)
	if release:
		snap.pick_taken()


## A Draw from (3.5, 0, 4) dragged to (6, 0, 7): once from a point the pointer is
## on, and once from the same point typed 2.5 along a guide from a tracked vertex.
func _a_typed_guide_point_starts_a_draw() -> void:
	var results := []
	for typed in [false, true]:
		var root: Node3D = await fresh_root("Guides_%s" % typed)
		root.grid_snap = 0.5
		var cam: Camera3D = await _camera()
		var snap = root.snap_system
		snap.tracking = true
		snap.clear_tracked()
		var start := Vector3(3.5, 0, 4)
		var far := Vector3(6, 0, 7)
		var start_mouse := cam.unproject_position(start)
		if typed:
			snap.toggle_tracked(Vector3(1, 0, 4), HFSnapSystem.KIND_VERTEX)
			_pointer(root, func(): root._snap_point(Vector3(3.3, 0, 4.1)))
			var on_guide: bool = snap.type_along_guide(2.5)
			note(
				"typed 2.5 along the guide from (1, 0, 4)",
				(
					"on a guide %s, pending %s, shown %s"
					% [on_guide, snap.has_pending_point(), snap.shown_pick.get("point")]
				)
			)
			# The pointer goes off somewhere else before the press, as a hand does.
			start_mouse = cam.unproject_position(Vector3(5, 0, 9))
		var began := [false]
		_pointer(
			root,
			func():
				began[0] = root.drag_system.begin_drag(
					cam, start_mouse, CSGShape3D.OPERATION_UNION, Vector3(1, 1, 1), 0
				)
		)
		var ends: Array = []
		for p in [Vector3(4.5, 0, 5), Vector3(5.5, 0, 6.5), far]:
			_pointer(root, func(): root.drag_system.update_drag(cam, cam.unproject_position(p)))
			ends.append(root.input_state.drag_end)
		# The release ends the base stage and spends the pick; a move sets the
		# height and a second click places the brush, as the Draw tool runs them.
		var placed := [{}]
		_pointer(
			root,
			func():
				root.drag_system.end_drag_info(cam, cam.unproject_position(far), Vector3(1, 1, 1)),
			true
		)
		_pointer(
			root,
			func(): root.drag_system.update_drag(cam, cam.unproject_position(far) + Vector2(0, -40))
		)
		_pointer(
			root,
			func():
				placed[0] = root.drag_system.end_drag_info(
					cam, cam.unproject_position(far) + Vector2(0, -40), Vector3(1, 1, 1)
				),
			true
		)
		var info: Dictionary = placed[0].get("info", {})
		results.append(
			{
				"typed": typed,
				"began": began[0],
				"origin": root.input_state.drag_origin,
				"drag ends": ends,
				"placed size": info.get("size"),
				"placed centre": info.get("center")
			}
		)
		note(
			"a Draw %s" % ("from a typed guide point" if typed else "from the pointer"), results[-1]
		)
		root.drag_system.cancel_drag()
		cam.queue_free()
		await drop_root(root)
	if results.size() == 2:
		var plain: Array = results[0]["drag ends"]
		var guided: Array = results[1]["drag ends"]
		var origin: Vector3 = results[1]["origin"]
		if (
			(guided[-1] as Vector3).is_equal_approx(origin)
			and not (plain[-1] as Vector3).is_equal_approx(results[0]["origin"])
		):
			known(
				2001,
				"a distance typed along a guide pins the far corner of the Draw it starts",
				(
					"after typing 2.5 on a guide and pressing, the drag starts at %s and every motion snaps to it too (%s), where the same drag from the pointer follows it to %s, and the brush placed is %s against %s: _snap() returns the typed point for every snap until pick_taken(), which only the left release calls"
					% [
						origin,
						guided,
						plain[-1],
						results[1]["placed size"],
						results[0]["placed size"]
					]
				)
			)
