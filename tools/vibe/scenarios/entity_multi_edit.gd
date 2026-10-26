@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Two newer surfaces of the entity work, asked what they do beyond their tests.
##
## Editing one property on several entities at once (#1796), through the dock the
## way a mapper does it: notes, dimensions and a light selected together, a value
## typed, Reset to Default, and the undo and redo of each. A dimension is an
## entity with data the panel does not show (its two ends), so a reset or an undo
## that rewrites its data is the place to look.
##
## And the two brush entity classes from #1914: does a `func_illusionary` really
## bake with no collision, and a `func_physbox` as a RigidBody3D, through a
## chunked bake, Bake Changed and the game scene export -- and what does the
## occluder pass make of a curtain the player is meant to see through, or a crate
## that moves.

const DockScene = preload("res://addons/hammerforge/dock.tscn")
const HFDockEntityHandler = preload("res://addons/hammerforge/dock_entity_handler.gd")
const HFEntityPropUtils = preload("res://addons/hammerforge/ui/hf_entity_prop_utils.gd")
const HFEntityMultiEdit = preload("res://addons/hammerforge/ui/hf_entity_multi_edit.gd")
const HFDimensions = preload("res://addons/hammerforge/hf_dimensions.gd")
const UndoStandIn = preload("res://tests/mcp/mcp_undo_stand_in.gd")

const BAKE_LAYER_INDEX := 9
const SCENE_PATH := "user://vibe_entity_multi_edit_game.tscn"


func id() -> String:
	return "entity-multi-edit"


func summary() -> String:
	return "several entities edited at once through the dock, and func_physbox / func_illusionary through bakes and exports"


func expected_issues() -> Array[int]:
	return [1961]


func run() -> void:
	await _multi_edit_through_the_dock()
	await _occluders_over_things_that_are_not_walls()
	await _illusionary_and_physbox_paths()
	if FileAccess.file_exists(SCENE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCENE_PATH))


func _box(root: Node3D, brush_id: String, size: Vector3, centre: Vector3) -> Node:
	return root.create_brush_from_info(
		{"shape": 0, "size": size, "center": centre, "brush_id": brush_id}
	)


func _data(node: Node) -> Dictionary:
	return HFEntityPropUtils.get_entity_data(node)


# ---------------------------------------------------------------------------
# Multi-edit
# ---------------------------------------------------------------------------


func _multi_edit_through_the_dock() -> void:
	var root: Node3D = await fresh_root("MultiEdit")
	root.hflevel_autosave_enabled = false
	var dock = DockScene.instantiate()
	_tree.get_root().add_child(dock)
	await frame()
	dock.level_root = root
	dock.connected_root = root
	dock._connect_root_signals()
	if dock.entity_defs.is_empty():
		dock._load_entity_definitions()
	var undo = UndoStandIn.new()
	dock.undo_redo = undo

	# A doorway, two walls 1.2 apart, with two dimensions across it.
	_box(root, "wall_l", Vector3(1, 3, 1), Vector3(-1.1, 1.5, 0))
	_box(root, "wall_r", Vector3(1, 3, 1), Vector3(1.1, 1.5, 0))
	await frame()
	var dims: Array = []
	for y in [0.0, 3.0]:
		var info := HFDimensions.info_between(
			root, Vector3(-0.6, y, 0.5), Vector3(0.6, y, 0.5), "Doorway %d" % int(y)
		)
		dims.append(root.entity_system.restore_entity_from_info(info))
	var notes: Array = []
	for i in 2:
		(
			notes
			. append(
				(
					root
					. entity_system
					. restore_entity_from_info(
						{
							"name": "Note%d" % i,
							"entity_type": "note",
							"properties":
							{
								"title": "N%d" % i,
								"body": "",
								"kind": "To Do",
								"author": "",
								"done": false
							},
							"transform": Transform3D(Basis(), Vector3(i * 2.0, 2, 3)),
						}
					)
				)
			)
		)
	var light: Node = root._create_entity_from_map(
		{"classname": "light_point", "origin": Vector3(0, 2.5, -3)}
	)
	await frame()
	var lengths_before: Array = []
	for d in dims:
		lengths_before.append(snappedf(float(HFDimensions.measure(root, d)["length"]), 0.0001))
	note("two dimensions across a 1.2 doorway", lengths_before)

	var everything: Array = dims + notes + [light]
	dock.set_selection_nodes(everything)
	await frame()
	var rows := HFEntityMultiEdit.rows(
		dock.entity_defs, HFEntityMultiEdit.subjects(root, everything)
	)
	var holders: Dictionary = {}
	for row in rows:
		holders[row["name"]] = (row["holders"] as Array).size()
	note("rows over 2 dimensions, 2 notes and a light: holders by property", holders)

	# One title on the four that have one.
	var title_holders: Array = []
	for row in rows:
		if row["name"] == "title":
			title_holders = row["holders"]
	var v0: int = undo.scene_history.get_version()
	HFDockEntityHandler.on_entities_prop_changed(dock, "Same", title_holders, "title")
	await frame()
	var titles: Array = []
	for e in everything:
		titles.append(str(_data(e).get("title", "-")))
	note(
		"after typing one title for the four",
		"%s, %d undo step(s)" % [titles, undo.scene_history.get_version() - v0]
	)

	# Hold both dimensions to "At least player width", then Reset to Default.
	HFDockEntityHandler.on_entities_prop_changed(dock, "At least player width", dims, "check")
	await frame()
	var failing := 0
	for d in dims:
		if not bool(HFDimensions.measure(root, d)["passes"]):
			failing += 1
	note("dimensions held to player width", "%d of 2 fail" % failing)
	dock.set_selection_nodes(everything)
	HFDockEntityHandler.reset_to_default(dock, dims, [])
	await frame()
	var after_reset: Array = []
	for d in root.entities_node.get_children():
		if HFDimensions.is_dimension(d):
			var m := HFDimensions.measure(root, d)
			after_reset.append(
				[
					str(_data(d).get("title")),
					str(_data(d).get("check")),
					snappedf(float(m["length"]), 0.0001),
					m["detached"]
				]
			)
	note("dimensions after Reset to Default", after_reset)
	for entry in after_reset:
		if entry[3]:
			flag("Reset to Default on a dimension detaches its ends", str(after_reset))
			break

	# Undo all three steps and redo them, measuring the dimensions each time.
	var trail: Array = []
	for step in 3:
		undo.scene_history.undo()
		await frame()
		trail.append(_dims_now(root))
	for step in 3:
		undo.scene_history.redo()
		await frame()
		trail.append(_dims_now(root))
	note("undo x3 then redo x3, the dimensions at each step", trail)
	for reading in trail:
		for d in reading:
			if d[3]:
				flag("an undo or redo of a multi-edit detaches a dimension", str(trail))
				break
			if absf(float(d[2]) - lengths_before[0]) > 0.001:
				flag("an undo or redo of a multi-edit changes a dimension's length", str(trail))
				break

	# The notes' Done ticked together, against what Validate says.
	root.validate_warns_open_todos = true
	var open_before := _open_todos(root)
	dock.set_selection_nodes(notes)
	HFDockEntityHandler.on_entities_prop_changed(dock, true, notes, "done")
	await frame()
	note(
		"open To Do findings before and after ticking Done on both",
		"%d -> %d" % [open_before, _open_todos(root)]
	)
	if _open_todos(root) != 0:
		flag(
			"Validate still lists To Do notes ticked Done through the multi-edit", _open_todos(root)
		)

	dock.undo_redo = null
	undo.free_histories()
	dock.queue_free()
	await drop_root(root)


func _dims_now(root: Node3D) -> Array:
	var out: Array = []
	for d in root.entities_node.get_children():
		if HFDimensions.is_dimension(d):
			var m := HFDimensions.measure(root, d)
			out.append(
				[
					str(_data(d).get("title")),
					str(_data(d).get("check")),
					snappedf(float(m["length"]), 0.0001),
					m["detached"]
				]
			)
	return out


func _open_todos(root: Node3D) -> int:
	var n := 0
	for issue in root.validate_level(false).get("issues", []):
		if str(issue).begins_with("Open To Do note"):
			n += 1
	return n


# ---------------------------------------------------------------------------
# Occluders
# ---------------------------------------------------------------------------


## Each OccluderInstance3D's corners in the world.
static func _occluder_corners(container: Node) -> Array:
	var out: Array = []
	if container == null:
		return out
	for occ in container.find_children("*", "OccluderInstance3D", true, false):
		var shape = (occ as OccluderInstance3D).occluder
		if not (shape is ArrayOccluder3D):
			continue
		var corners: Array = []
		for v in (shape as ArrayOccluder3D).vertices:
			corners.append((occ as Node3D).global_transform * v)
		out.append(corners)
	return out


## How many occluders lie wholly inside `box`, grown a little.
static func _occluders_in(occluders: Array, box: AABB) -> int:
	var grown := box.grow(0.05)
	var n := 0
	for corners in occluders:
		var inside := true
		for c in corners:
			if not grown.has_point(c):
				inside = false
				break
		if inside:
			n += 1
	return n


func _occluders_over_things_that_are_not_walls() -> void:
	var root: Node3D = await fresh_root("Occluders")
	root.bake_collision_layer_index = BAKE_LAYER_INDEX
	root.bake_generate_occluders = true
	var at := Vector3(200, 0, 0)
	# A wall, as a control: big flat faces, so it gets occluders.
	_box(root, "wall", Vector3(4, 4, 0.2), at + Vector3(0, 2, -6))
	# A bead curtain the player walks through and sees through.
	_box(root, "curtain", Vector3(4, 4, 0.1), at + Vector3(0, 2, 0))
	root.tie_brushes_to_entity(["curtain"], "func_illusionary", "")
	# A plank the player can knock over.
	_box(root, "plank", Vector3(4, 0.2, 3), at + Vector3(8, 0.1, 0))
	root.tie_brushes_to_entity(["plank"], "func_physbox", "")
	# A door, which opens.
	_box(root, "door", Vector3(3, 3, 0.2), at + Vector3(-8, 1.5, 0))
	root.tie_brushes_to_entity(["door"], "func_door", "door_1")
	await frame()
	await root.bake()
	await frame()
	var occluders := _occluder_corners(root.baked_container)
	var counts := {}
	for brush_id in ["wall", "curtain", "plank", "door"]:
		var brush: Node = root.find_brush_by_id(brush_id)
		var box: AABB = root.brush_system.world_bounds_of(brush)
		counts[brush_id] = _occluders_in(occluders, box)
	note("occluders generated, by what they lie on", "%s of %d" % [counts, occluders.size()])
	if int(counts.get("wall", 0)) == 0:
		note("(the control wall got no occluder either, so the counts below say nothing)")
	else:
		if int(counts.get("curtain", 0)) > 0:
			known(
				1961,
				"Generate occluders puts an occluder on a func_illusionary curtain",
				(
					"%d occluder(s) lie on a 4 x 4 see-through curtain, so what stands behind it is culled while the player looks through it; _collect_mesh_instances() takes every MeshInstance3D under the bake, Nonstructural included"
					% counts["curtain"]
				)
			)
		if int(counts.get("plank", 0)) > 0:
			known(
				1961,
				"Generate occluders puts a static occluder on a func_physbox",
				(
					"%d occluder(s) stay where the plank was baked after it is knocked away"
					% counts["plank"]
				)
			)
		if int(counts.get("door", 0)) > 0:
			known(
				1961,
				"Generate occluders puts a static occluder on a func_door",
				"%d occluder(s) stay where the closed door was" % counts["door"]
			)
	await drop_root(root)


# ---------------------------------------------------------------------------
# func_illusionary and func_physbox
# ---------------------------------------------------------------------------


func _settle_physics() -> void:
	for _i in 3:
		await _tree.physics_frame


func _ray(root: Node3D, from: Vector3, to: Vector3) -> Variant:
	var space := root.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to, 1 << (BAKE_LAYER_INDEX - 1))
	var hit := space.intersect_ray(query)
	return hit.get("position") if not hit.is_empty() else null


func _illusionary_and_physbox_paths() -> void:
	var case_x := 400.0
	for settings in [
		{},
		{"bake_chunk_size": 2.0},
		{"bake_use_face_materials": false},
		{"bake_merge_meshes": true}
	]:
		case_x += 50.0
		var at := Vector3(case_x, 0, 0)
		var root: Node3D = await fresh_root("Classes_%d" % int(case_x))
		root.bake_collision_layer_index = BAKE_LAYER_INDEX
		for key in settings:
			root.set(key, settings[key])
		_box(root, "floor", Vector3(12, 0.4, 12), at + Vector3(0, -0.2, 0))
		_box(root, "curtain", Vector3(4, 3, 0.1), at + Vector3(0, 1.5, 0))
		root.tie_brushes_to_entity(["curtain"], "func_illusionary", "")
		_box(root, "crate", Vector3(1, 1, 1), at + Vector3(3, 0.5, 0))
		root.tie_brushes_to_entity(["crate"], "func_physbox", "")
		await frame()
		await root.bake()
		await frame()
		var bodies: Array = (
			root.baked_container.find_children("*", "RigidBody3D", true, false)
			if root.baked_container
			else []
		)
		await _settle_physics()
		var through = _ray(root, at + Vector3(0, 1.5, -3), at + Vector3(0, 1.5, 3))
		note(
			"curtain and crate, %s" % [settings if not settings.is_empty() else "defaults"],
			"RigidBody3D %d, a ray through the curtain meets %s" % [bodies.size(), through]
		)
		if through != null:
			flag("a func_illusionary curtain collides with %s" % [settings], str(through))
		if bodies.size() != 1:
			flag(
				"a func_physbox does not bake to one RigidBody3D with %s" % [settings],
				"%d bodies" % bodies.size()
			)

		# Bake Changed after the crate's mass changes and after it moves.
		if settings.is_empty():
			var crate: Node = root.find_brush_by_id("crate")
			root.set_entity_property(crate, "mass", 55.0)
			root.tag_brush_dirty("crate")
			await root.bake_dirty()
			await frame()
			bodies = root.baked_container.find_children("*", "RigidBody3D", true, false)
			var mass := -1.0 if bodies.is_empty() else (bodies[0] as RigidBody3D).mass
			note("Bake Changed after mass 55", "%d bodies, mass %s" % [bodies.size(), mass])
			if bodies.size() != 1 or absf(mass - 55.0) > 0.001:
				flag(
					"Bake Changed does not carry a physbox's new mass",
					"%d bodies, mass %s" % [bodies.size(), mass]
				)
			root.nudge_brushes_by_id(["crate"], Vector3(2, 0, 0))
			await root.bake_dirty()
			await frame()
			bodies = root.baked_container.find_children("*", "RigidBody3D", true, false)
			var x := -1.0 if bodies.is_empty() else (bodies[0] as Node3D).global_position.x - at.x
			note(
				"Bake Changed after the crate moves 2 along X",
				"%d bodies, body at x %+.2f from the case" % [bodies.size(), x]
			)

			# The game scene a game loads.
			var exported: bool = root.export_game_scene(SCENE_PATH)
			var packed := load(SCENE_PATH) as PackedScene if exported else null
			var scene: Node = packed.instantiate() if packed else null
			if scene:
				var rigid := scene.find_children("*", "RigidBody3D", true, false).size()
				var curtain_bodies := 0
				for node in scene.find_children("*", "", true, false):
					if str(node.get_meta("brush_entity_class", "")) == "func_illusionary":
						curtain_bodies += (
							node.find_children("*", "CollisionShape3D", true, false).size()
						)
				note(
					"Export Game Scene",
					(
						"%d RigidBody3D, %d collision shapes under the curtain"
						% [rigid, curtain_bodies]
					)
				)
				if rigid != 1:
					flag("the game scene does not carry the physbox as one RigidBody3D", rigid)
				if curtain_bodies > 0:
					flag("the game scene gives the illusionary curtain collision", curtain_bodies)
				scene.free()
		await drop_root(root)
