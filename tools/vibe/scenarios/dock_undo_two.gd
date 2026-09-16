@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## The second half of `dock-undo`: the commands that scenario does not reach.
##
## `dock-undo` covers visgroups, groups, entities, their wiring and the floor
## paint layers. The buttons below change the level too and live in handler
## files it does not read -- structures, the material library, the terrain
## slots, the cordon and the per-face surface paint layers.
##
## The test is the same: a button that changes something `capture_state()`
## carries, and never names an undo wrapper, is changing it outside the undo
## system. The difference from `dock-undo` is that this one follows a
## delegation two steps -- a dock method to its handler, and that handler to the
## private helper it commits through -- because several of these register their
## undo action one level further down than the button.

const DockScene = preload("res://addons/hammerforge/dock.tscn")

const HANDLER_SOURCES := [
	"res://addons/hammerforge/dock.gd",
	"res://addons/hammerforge/dock_brush_handler.gd",
	"res://addons/hammerforge/dock_entity_handler.gd",
	"res://addons/hammerforge/dock_file_handler.gd",
	"res://addons/hammerforge/dock_manage_handler.gd",
	"res://addons/hammerforge/dock_paint_handler.gd",
	"res://addons/hammerforge/dock_visgroup_handler.gd",
]

## Dock method -> [label, what `capture_state()` carries that it changes].
## Every one of these alters state a `_commit_state_action()` would restore.
const COMMANDS := [
	["_on_create_structure", "Create Structure", "brushes"],
	["_on_detach_structure", "Detach Structure", "generator records"],
	["_on_scatter_commit", "Scatter Commit", "scene nodes"],
	["_on_terrain_slot_texture_selected", "Terrain slot texture", "paint_layers"],
	["_on_terrain_slot_scale_changed", "Terrain slot UV scale", "paint_layers"],
	["_on_material_library_load_selected", "Load Material Library", "materials"],
	["_on_surface_paint_layer_add", "Add Surface Paint Layer", "brushes (face data)"],
	["_on_surface_paint_layer_remove", "Remove Surface Paint Layer", "brushes (face data)"],
	["_on_cordon_from_selection", "Set Cordon from Selection", "cordon (settings only)"],
]


func id() -> String:
	return "dock-undo-two"


func summary() -> String:
	return "undo coverage for the structure, library, terrain slot and surface paint commands"


func run() -> void:
	await _which_commands_reach_the_undo_stack()


func _body(function_name: String) -> String:
	for path in HANDLER_SOURCES:
		var source := FileAccess.get_file_as_string(path)
		var start := source.find("\nfunc %s(" % function_name)
		if start < 0:
			start = source.find("\nstatic func %s(" % function_name)
		if start < 0:
			continue
		var rest := source.substr(start + 1)
		var end := rest.find("\n\n\n")
		return rest if end < 0 else rest.substr(0, end)
	return ""


func _names_a_wrapper(body: String) -> bool:
	return (
		body.contains("_commit_state_action")
		or body.contains("_commit_full_state_action")
		or body.contains("_commit_done_state_action")
		or body.contains("HFUndoHelper")
		or body.contains("create_action(")
	)


## Function names this body hands off to: `HFDockX.name(`, and plain `_name(`
## helpers in the same files. Scatter Commit registers its action in a private
## helper two steps down, so a one-level follow reads it as unwrapped.
func _callees(body: String) -> Array:
	var out: Array = []
	var qualified := RegEx.new()
	qualified.compile("HFDock\\w+\\.(\\w+)\\(")
	for m in qualified.search_all(body):
		out.append(m.get_string(1))
	var private := RegEx.new()
	private.compile("(?:^|[^\\w.])(_[a-z]\\w+)\\(")
	for m in private.search_all(body):
		out.append(m.get_string(1))
	return out


## Whether a command registers an undo step within two steps of the button.
func _undo_wrapped(function_name: String) -> bool:
	var body := _body(function_name)
	if body == "":
		return false
	if _names_a_wrapper(body):
		return true
	for first in _callees(body):
		var inner := _body(first)
		if inner == "":
			continue
		if _names_a_wrapper(inner):
			return true
		for second in _callees(inner):
			if _names_a_wrapper(_body(second)):
				return true
	return false


func _which_commands_reach_the_undo_stack() -> void:
	var root: Node3D = await fresh_root("UndoTwo")
	var dock = DockScene.instantiate()
	_tree.get_root().add_child(dock)
	await frame()
	dock.level_root = root
	await frame()

	var unwrapped: Array = []
	var missing: Array = []
	for entry in COMMANDS:
		var method: String = entry[0]
		var label: String = entry[1]
		var carries: String = entry[2]
		if not dock.has_method(method):
			missing.append("%s (%s)" % [label, method])
			continue
		var wrapped: bool = _undo_wrapped(method)
		note("%s registers an undo step" % label, "%s   [changes %s]" % [wrapped, carries])
		if not wrapped:
			unwrapped.append("%s (%s, changes %s)" % [label, method, carries])
	note("commands that never name an undo wrapper", unwrapped.size())
	if not missing.is_empty():
		note("dock methods this scenario names that are not there", missing)

	# The cordon is carried by `capture_hflevel_settings()` rather than by
	# `capture_state()`, so a `_commit_state_action()` would not restore it even
	# if one were used. Recorded rather than counted against the same rule.
	note(
		"the cordon is settings rather than state",
		"hf_state_system.gd:405 puts cordon_enabled and cordon_aabb in capture_hflevel_settings()"
	)
	if not unwrapped.is_empty():
		known(
			573,
			"dock commands that change undoable state without registering an undo step",
			(
				(
					"each of these alters something `capture_state()` carries and never names"
					+ " `_commit_state_action()`, `HFUndoHelper` or `create_action()` within two"
					+ " steps of the button, so Ctrl+Z steps past it to whatever happened"
					+ " before: %s"
				)
				% str(unwrapped)
			)
		)
	dock.queue_free()
	await frame()
