@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Prefabs: capture a selection, write it to a `.hfprefab`, read it back and
## place it, and see what survived.
##
## A prefab is the only path in the editor that carries geometry *between*
## levels. Everything it loses is lost silently, because the placement succeeds
## and the mapper is looking at a shape that is roughly right. And everything it
## carries that it should not -- a reference to something that only existed in
## the level it was captured from -- lands in a level that has no such thing.


func id() -> String:
	return "prefabs"


func summary() -> String:
	return "prefab capture, .hfprefab round trip, placement, and the instance registry"


func run() -> void:
	await _a_prefab_round_trips_its_geometry()
	await _a_prefab_carries_visgroup_membership_into_a_level_without_it()
	await _placing_a_prefab_that_is_empty()
	await _the_instance_registry_after_a_restore()
	await _malformed_prefab_files()


func _bid(node: Node) -> String:
	return str(node.get_meta("brush_id", ""))


func _tmp(suffix: String) -> String:
	return "user://vibe_%s.hfprefab" % suffix


## A box with per-face materials and UVs, captured, saved, loaded and placed.
## The placed brush should be the captured one in a different spot.
func _a_prefab_round_trips_its_geometry() -> void:
	var root: Node3D = await fresh_root()
	var b := box(root, Vector3(64, 48, 32))
	# Give every face something to lose.
	for i in range(b.faces.size()):
		# Set the face data directly. What is under test is the serializer, not
		# the setters -- and a fresh root has no material palette, so the
		# editor-facing assign path would refuse every slot.
		b.faces[i].material_idx = i % 3
		b.faces[i].uv_scale = Vector2(2.0, 3.0)
		b.faces[i].uv_offset = Vector2(8 + i, 16)
		b.faces[i].uv_rotation = 0.25 * i
	await frame()

	var before_faces: Array = []
	for face in b.faces:
		before_faces.append([face.material_idx, face.uv_scale, face.uv_offset, face.uv_rotation])

	var prefab = HFPrefab.capture_from_selection(root.brush_system, root.entity_system, [b], [])
	var path := _tmp("roundtrip")
	var err: int = prefab.save_to_file(path)
	note("save_to_file", "err %d, %d bytes" % [err, HFVibe.file_size(path)])
	var loaded = HFPrefab.load_from_file(path)
	if loaded == null:
		flag("a prefab just written by save_to_file will not load back")
		return

	var placed: Dictionary = loaded.instantiate(
		root.brush_system, root.entity_system, root, Vector3(256, 0, 0)
	)
	await frame()
	var ids: Array = placed.get("brush_ids", [])
	note("placed", "%d brushes from a 1-brush prefab" % ids.size())
	if ids.size() != 1:
		flag("a one-brush prefab placed %d brushes" % ids.size())
		return

	var placed_brush = root.brush_system.find_managed_brush_by_id(str(ids[0]))
	if placed_brush == null:
		flag("the prefab reported a brush id that is not in the level", ids[0])
		return

	var after_faces: Array = []
	for face in placed_brush.faces:
		after_faces.append([face.material_idx, face.uv_scale, face.uv_offset, face.uv_rotation])

	if before_faces.size() != after_faces.size():
		flag(
			"a prefab round trip changed the face count",
			"%d -> %d" % [before_faces.size(), after_faces.size()]
		)
	elif HFVibe.canonical(before_faces) != HFVibe.canonical(after_faces):
		flag(
			"a prefab round trip did not preserve per-face appearance",
			"before %s / after %s" % [before_faces, after_faces]
		)
	else:
		note("per-face appearance survived the round trip", "%d faces" % after_faces.size())

	note("placed centre", placed_brush.global_transform.origin)
	for problem in HFVibe.check_invariants(root):
		flag("after placing a prefab: %s" % problem)


## `capture_from_selection()` clears `brush_id` and `group_id` from the captured
## info because the instance gets its own. It does not clear `visgroups`, which
## are names that only mean anything in the level they were captured from.
func _a_prefab_carries_visgroup_membership_into_a_level_without_it() -> void:
	var root: Node3D = await fresh_root()
	var b := box(root, Vector3(64, 64, 64))
	root.create_visgroup("Lighting")
	root.add_selection_to_visgroup("Lighting", [b])
	await frame()

	var prefab = HFPrefab.capture_from_selection(root.brush_system, root.entity_system, [b], [])
	var captured: Dictionary = prefab.brush_infos[0]
	note("captured info keys", captured.keys())
	note("brush_id cleared", not captured.has("brush_id"))
	note("group_id cleared", not captured.has("group_id"))
	note("visgroups carried", captured.get("visgroups", []))

	var path := _tmp("visgroup")
	prefab.save_to_file(path)

	# A different level, which has never heard of "Lighting".
	var other: Node3D = await fresh_root("OtherLevel")
	var loaded = HFPrefab.load_from_file(path)
	loaded.instantiate(other.brush_system, other.entity_system, other, Vector3.ZERO)
	await frame()

	var names := Array(other.get_visgroup_names())
	var placed_list: Array = other.draft_brushes_node.get_children()
	var member: Array = []
	if not placed_list.is_empty():
		member = Array(placed_list[0].get_meta("visgroups", PackedStringArray()))
	note("visgroups registered in the receiving level", names)
	note("visgroups on the placed brush", member)
	if not member.is_empty() and not names.has(member[0]):
		known(
			368,
			"a placed prefab brush belongs to a visgroup the level does not have",
			(
				"the brush carries visgroup '%s'; the receiving level knows %s -- nothing registers it on placement, so the brush is in a group that cannot be listed, toggled or deleted"
				% [member[0], names]
			)
		)


## Placing a prefab with nothing in it.
func _placing_a_prefab_that_is_empty() -> void:
	var root: Node3D = await fresh_root()
	var empty = HFPrefab.new()
	empty.prefab_name = "Nothing"
	var path := _tmp("empty")
	var err: int = empty.save_to_file(path)
	var loaded = HFPrefab.load_from_file(path)
	note("an empty prefab", "saved err %d, loaded %s" % [err, loaded != null])
	if loaded == null:
		return
	var placed: Dictionary = loaded.instantiate(
		root.brush_system, root.entity_system, root, Vector3.ZERO
	)
	await frame()
	note(
		"placing it",
		(
			"%d brushes, %d entities, level now holds %d"
			% [
				placed.get("brush_ids", []).size(),
				placed.get("entity_count", 0),
				root.brush_system.get_live_brush_count()
			]
		)
	)
	for problem in HFVibe.check_invariants(root):
		flag("after placing an empty prefab: %s" % problem)


## `restore_state()` takes `next_instance_id` from the saved data and does not
## reconcile it against the instance ids it just restored.
func _the_instance_registry_after_a_restore() -> void:
	var root: Node3D = await fresh_root()
	var ps = root.prefab_system
	var b := box(root, Vector3(64, 64, 64))
	var first: String = ps.register_instance("res://a.hfprefab", [_bid(b)], [])
	note("first instance id", first)

	# A state whose counter is behind its own instance list. An older save, a
	# hand-edited file, or a restore of a state captured before the counter was
	# part of it -- `data.get("next_instance_id", 1)` is the default for all three.
	var state: Dictionary = ps.capture_state()
	state["next_instance_id"] = 1
	ps.restore_state(state)

	var b2 := box(root, Vector3(32, 32, 32), Vector3(128, 0, 0))
	var second: String = ps.register_instance("res://b.hfprefab", [_bid(b2)], [])
	note("id issued after the restore", second)
	var all: Dictionary = ps.get_all_instances()
	note("instances registered", all.size())
	if second == first:
		var owner_path: String = all[second].source_path if all.has(second) else "?"
		known(
			369,
			"restore_state re-issues an instance id that is already in use",
			(
				"both instances are '%s' and the registry holds %d record(s) for two placements -- the second registration overwrites the first, so the first prefab's brushes stay tagged with an id whose record now describes a different prefab (%s)"
				% [second, all.size(), owner_path]
			)
		)


## A `.hfprefab` that is not what the loader expects.
func _malformed_prefab_files() -> void:
	var root: Node3D = await fresh_root()
	var cases: Dictionary = {
		"not-json": "this is not json at all",
		"json-array": "[1, 2, 3]",
		"empty-object": "{}",
		"brush-infos-string": '{"prefab_name": "x", "brush_infos": "nope"}',
		"null-brush-entry": '{"prefab_name": "x", "brush_infos": [null]}',
		"brush-without-shape": '{"prefab_name": "x", "brush_infos": [{"size": [1, 2, 3]}]}',
	}
	for label in cases:
		var path := _tmp("bad_%s" % str(label).replace("-", "_"))
		HFVibe.write_text(path, cases[label])
		var loaded = HFPrefab.load_from_file(path)
		if loaded == null:
			note(str(label), "refused by the loader")
			continue
		var before: int = root.brush_system.get_live_brush_count()
		var depth_before: int = root.get("_signal_batch_depth")
		var placed: Dictionary = loaded.instantiate(
			root.brush_system, root.entity_system, root, Vector3.ZERO
		)
		await frame()
		var after: int = root.brush_system.get_live_brush_count()
		note(
			str(label),
			(
				"loaded; placing it made %d brushes (level %d -> %d)"
				% [placed.get("brush_ids", []).size(), before, after]
			)
		)
		# `instantiate()` opens a signal batch before it touches anything and
		# closes it at the end. An error partway through never reaches the close.
		var depth_after: int = root.get("_signal_batch_depth")
		if depth_after > depth_before:
			known(
				370,
				"a malformed prefab leaves the level's signal batch open",
				(
					"case '%s': _signal_batch_depth %d -> %d after instantiate() aborted, so every signal from here on is queued and never emitted"
					% [label, depth_before, depth_after]
				)
			)
		for problem in HFVibe.check_invariants(root):
			flag("after placing a malformed prefab (%s): %s" % [label, problem])
