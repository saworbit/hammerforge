extends "res://tests/mcp/mcp_dispatcher_case.gd"
## Every command the bridge runs, through `hf_run_command`, in awkward states.
##
## The commands are `HFCommandRegistry.bridge_ids()`, so one given a bridge entry
## is swept without being listed here. Each runs once in every state below, on a
## level built for it, with the brushes the state offers trimmed or topped up to
## what the command takes, and its defaults for parameters. It must raise no
## script error. A refusal must leave the level and the undo history as they
## were. A success must add exactly one step, named `MCP: ...`; `hf_undo` must
## give back the level from before it and `hf_redo` the level from after, brush
## ids and all.

const HFCommandRegistry = preload("res://addons/hammerforge/hf_command_registry.gd")
const HFGeneratorSystem = preload("res://addons/hammerforge/systems/hf_generator_system.gd")
const DraftEntityScript = preload("res://addons/hammerforge/draft_entity.gd")
const HFPrefab = preload("res://addons/hammerforge/hf_prefab.gd")

## A scratch prefab library, so place_prefab places something in every state
## without reading or writing the project's own.
const LIBRARY := "user://hf_test_sweep_prefab_library"

const STATES := [
	"no_level",
	"made_up_id",
	"committed_cut",
	"pending_cut",
	"generator_piece",
	"brush_entity",
	"displaced_brush",
	"deleted_brush",
	"entity_only",
	"two_boxes",
]

## Stands for the structure the state built, or a made-up id where it built none.
const STRUCTURE := "$structure"

## Required parameters a sweep cannot take a default for.
const REQUIRED := {
	"clip_to_face": {"plane_brush_id": "b", "plane_face": "-x"},
	"create_arch": {"type": "stairs", "position": [20, 0, 0]},
	"update_structure": {"generator_id": STRUCTURE},
	"detach_structure": {"generator_id": STRUCTURE},
	"place_prefab": {"prefab": "sweep_crate", "position": [30, 0, 0]},
}

## Failures this sweep found that are filed and not fixed yet, as
## "command|state": issue.
const KNOWN := {}

var _scene: Node3D = null


func before_all() -> void:
	var shop := LevelRoot.new()
	shop.auto_spawn_player = false
	shop.hflevel_autosave_enabled = false
	add_child(shop)
	var crate := _box(shop, "crate", Vector3(0, 2, 0))
	var prefab = HFPrefab.capture_from_selection(shop.brush_system, shop.entity_system, [crate], [])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LIBRARY))
	assert_eq(prefab.save_to_file(LIBRARY.path_join("sweep_crate.hfprefab")), OK)
	remove_child(shop)
	shop.free()


func after_all() -> void:
	DirAccess.remove_absolute(
		ProjectSettings.globalize_path(LIBRARY.path_join("sweep_crate.hfprefab"))
	)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LIBRARY))


func before_each() -> void:
	super.before_each()
	dispatcher.commands.prefab_dir = LIBRARY


func after_each() -> void:
	_leave()
	super.after_each()


func test_every_command_in_every_state(command = use_parameters(_commands())):
	for state in STATES:
		await _check(command, state)
		_leave()
		# What the level queued for freeing goes before GUT counts orphans.
		await get_tree().process_frame
		await get_tree().process_frame
		assert_no_new_orphans("%s in %s left nodes behind" % [command, state])


static func _commands() -> Array:
	return Array(HFCommandRegistry.bridge_ids())


func _check(command: String, state: String) -> void:
	var label := "%s in %s" % [command, state]
	var picked := _enter(state)
	var level: LevelRoot = picked.get("level")
	var params := _params_for(command, picked)
	var errors_before := get_errors().size()
	var steps_before: int = undo.scene_history.get_history_count()
	var before := _state(level)
	var r := await call_tool("hf_run_command", params)
	var errors: Array = get_errors().slice(errors_before)
	var known := "%s|%s" % [command, state]
	if KNOWN.has(known):
		for e in errors:
			e.handled = true
		pending("%s: %s" % [label, KNOWN[known]])
		return
	assert_eq(_describe(errors), [], "%s raised no error" % label)
	if not r.get("ok", false):
		assert_true(r.has("error"), "%s: a refusal says why: %s" % [label, str(r)])
		assert_eq(_state(level), before, "%s: refused, and the level is as it was" % label)
		assert_eq(undo.scene_history.get_history_count(), steps_before, "%s: no step" % label)
		return
	assert_eq(undo.scene_history.get_history_count(), steps_before + 1, "%s: one step" % label)
	assert_true(
		undo.scene_history.get_current_action_name().begins_with("MCP: "),
		"%s: named for the agent" % label
	)
	var after := _state(level)
	var undone := await call_tool("hf_undo")
	assert_true(undone.get("ok", false), "%s: undone: %s" % [label, str(undone)])
	assert_eq(_state(level), before, "%s: undo gives back the level from before" % label)
	var redone := await call_tool("hf_redo")
	assert_true(redone.get("ok", false), "%s: redone: %s" % [label, str(redone)])
	assert_eq(_state(level), after, "%s: redo gives back the level from after" % label)


func _state(level: LevelRoot) -> String:
	if level == null or not is_instance_valid(level):
		return ""
	return var_to_str(level.capture_state(false))


func _describe(errors: Array) -> Array:
	var out: Array = []
	for e in errors:
		out.append("%s:%d %s" % [str(e.file).get_file(), e.line, str(e.code)])
	return out


## `hf_run_command` arguments: the state's brushes and entities, trimmed or topped
## up to what the command takes, and its required parameters.
func _params_for(command: String, picked: Dictionary) -> Dictionary:
	var spec := HFCommandRegistry.bridge(command)
	var rule: Dictionary = spec["targets"]
	var low := int(rule["min"])
	var high := int(rule["max"])
	var ids: Array = (picked.get("brush_ids", []) as Array).duplicate()
	var entities: Array = (picked.get("entities", []) as Array).duplicate()
	for spare in picked.get("spare", []):
		if ids.size() + entities.size() >= low:
			break
		if not ids.has(spare):
			ids.append(spare)
	if high >= 0:
		while ids.size() + entities.size() > high and not ids.is_empty():
			ids.pop_back()
		while ids.size() + entities.size() > high and not entities.is_empty():
			entities.pop_back()
	var params := {"command": command, "brush_ids": ids}
	if not entities.is_empty():
		params["entities"] = entities
	if REQUIRED.has(command):
		var given := (REQUIRED[command] as Dictionary).duplicate(true)
		for key in given:
			if str(given[key]) == STRUCTURE:
				given[key] = str(picked.get("generator_id", "gen_made_up"))
		params["params"] = given
	return params


func _box(level: LevelRoot, id: String, center: Vector3) -> DraftBrush:
	return level.create_brush_from_info(
		{"size": Vector3(4, 4, 4), "center": center, "brush_id": id}
	)


## Build `state` and say what it offers: `level`, `brush_ids`, `entities`,
## `spare` brushes a command that needs more can add, and the `generator_id` of
## the structure it built, if it built one.
func _enter(state: String) -> Dictionary:
	_scene = Node3D.new()
	_scene.name = "Scene"
	add_child(_scene)
	host.scene = _scene
	if state == "no_level":
		return {"level": null, "brush_ids": ["a"]}
	var level := LevelRoot.new()
	level.name = "LevelRoot"
	level.auto_spawn_player = false
	level.hflevel_autosave_enabled = false
	level.grid_snap = 1.0
	_scene.add_child(level)
	var a := _box(level, "a", Vector3(0, 2, 0))
	var b := _box(level, "b", Vector3(8, 2, 0))
	var offer := {"level": level, "brush_ids": ["a"], "spare": ["b"]}
	match state:
		"made_up_id":
			offer["brush_ids"] = ["nope"]
		"committed_cut":
			(
				level
				. create_brush_from_info(
					{
						"size": Vector3(1, 1, 1),
						"transform": Transform3D(Basis(), Vector3(0, 2, 10)),
						"operation": CSGShape3D.OPERATION_SUBTRACTION,
						"committed": true,
						"brush_id": "frozen",
					}
				)
			)
			offer["brush_ids"] = ["frozen"]
		"pending_cut":
			(
				level
				. create_brush_from_info(
					{
						"size": Vector3(2, 2, 2),
						"center": Vector3(0, 2, 0),
						"brush_id": "cut",
						"operation": CSGShape3D.OPERATION_SUBTRACTION,
						"pending": true,
					}
				)
			)
			offer["brush_ids"] = ["cut", "a"]
		"generator_piece":
			var before: Array = level.draft_brushes_node.get_children()
			var settings: Dictionary = HFGeneratorSystem.default_settings("stairs")
			settings["steps"] = 4
			level.create_generator("stairs", settings, Transform3D(Basis(), Vector3(-10, 0, 0)))
			offer["generator_id"] = str(level.generator_system.generators.keys()[0])
			for node in level.draft_brushes_node.get_children():
				if not before.has(node):
					offer["brush_ids"] = [(node as DraftBrush).brush_id]
					break
		"brush_entity":
			level.tie_brushes_to_entity(["a"], "func_door", "door_1")
		"displaced_brush":
			var faces: Array = a.get_faces()
			for i in faces.size():
				if faces[i].normal.y > 0.9:
					assert_true(level.create_displacement("a", i, 2), "the box took a displacement")
					break
		"deleted_brush":
			level.delete_brush(b)
			offer["brush_ids"] = ["b"]
			offer["spare"] = ["a"]
		"entity_only":
			var entity = DraftEntityScript.new()
			entity.name = "lamp"
			entity.entity_type = "light_point"
			entity.entity_class = "light_point"
			level.add_entity(entity)
			entity.global_position = Vector3(0, 6, 0)
			offer["brush_ids"] = []
			offer["entities"] = [str(level.get_path_to(entity))]
		"two_boxes":
			# Side by side, so together they are one box and Merge can take them.
			b.global_position = Vector3(4, 2, 0)
			offer["brush_ids"] = ["a", "b"]
	return offer


## Out of the level the way a scene tab closes, with its history: the steps name
## nodes about to go.
func _leave() -> void:
	undo.scene_history.clear_history()
	host.scene = null
	if _scene != null and is_instance_valid(_scene):
		remove_child(_scene)
		_scene.free()
	_scene = null
