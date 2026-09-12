@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Which dock buttons reach the undo stack, and which change the level behind it.
##
## The dock has one wrapper for a command that changes the level:
## `_commit_state_action()`, which snapshots the level, runs the method and
## registers the pair with `EditorUndoRedoManager` so Ctrl+Z puts it back. Forty
## of the dock's buttons use it. This asks which ones do not, and what a mapper
## loses when they press one.
##
## `capture_state()` carries visgroups, groups, entities and paint layers, so
## every action below *could* be undone through the same wrapper its neighbours
## use. Nothing about the data is in the way.

const DockScene = preload("res://addons/hammerforge/dock.tscn")
const DraftEntity = preload("res://addons/hammerforge/draft_entity.gd")

## The files a dock button's body lives in, for the "which wrapper does it use"
## reading. A button that changes the level and never names one of these is
## changing it outside the undo system.
const HANDLER_SOURCES := [
	"res://addons/hammerforge/dock.gd",
	"res://addons/hammerforge/dock_visgroup_handler.gd",
	"res://addons/hammerforge/dock_entity_handler.gd",
	"res://addons/hammerforge/dock_paint_handler.gd",
]


func id() -> String:
	return "dock-undo"


func summary() -> String:
	return "which dock commands change the level without registering an undo step"


func run() -> void:
	await _visgroups_and_groups()
	await _entities_and_their_wiring()
	await _paint_layers()


## The dock, wired to a root, the way the plugin hands it one.
func _dock(root: Node3D) -> Node:
	var dock = DockScene.instantiate()
	_tree.get_root().add_child(dock)
	await frame()
	dock.level_root = root
	return dock


## Every `func <name>` body in the handler sources, so a claim about which
## wrapper a button uses is read off the code rather than guessed.
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


## Whether a button's body registers an undo step at all.
func _undo_wrapped(function_name: String) -> bool:
	var body := _body(function_name)
	return (
		body.contains("_commit_state_action")
		or body.contains("_commit_full_state_action")
		or body.contains("_commit_done_state_action")
		or body.contains("HFUndoHelper")
	)


func _visgroup_names(root: Node3D) -> Array:
	return Array(root.visgroup_system.get_visgroup_names())


func _visgroups_and_groups() -> void:
	var root: Node3D = await fresh_root("VisgroupLevel")
	var dock = await _dock(root)
	var brush_a := box(root, Vector3(64, 64, 64), Vector3(0, 0, 0))
	var brush_b := box(root, Vector3(64, 64, 64), Vector3(128, 0, 0))
	await frame()

	dock.visgroup_name_input.text = "Lights"
	dock._on_visgroup_add()
	await frame()
	note("visgroups after New", _visgroup_names(root))
	note("New Visgroup registers an undo step", _undo_wrapped("on_visgroup_add"))

	dock.set_selection_nodes([brush_a, brush_b])
	dock.visgroup_list.select(0)
	dock._on_visgroup_add_selection()
	await frame()
	var members_a := Array(brush_a.get_meta("visgroups", PackedStringArray()))
	note("brush A visgroups after Add Sel", members_a)

	# The same button a second time, exactly as a mapper would press it after
	# selecting more geometry. Nothing about the selection changed.
	var selected_after: PackedInt32Array = dock.visgroup_list.get_selected_items()
	note("visgroup list selection after Add Sel", selected_after)
	if selected_after.is_empty():
		known(
			476,
			"Add Sel clears the visgroup it just added to",
			(
				"HFDockVisgroupHandler.on_visgroup_add_selection() ends in refresh_visgroup_ui(),"
				+ " which calls ItemList.clear() and rebuilds the rows. The highlighted row is"
				+ ' gone, so get_selected_visgroup_name() answers "" and the next Add Sel,'
				+ " Rem Sel or Delete is a silent no-op until the mapper clicks the visgroup"
				+ " again. on_visgroup_item_clicked() re-selects its row after the same refresh,"
				+ " so the loss was known about on the neighbouring path."
			)
		)

	var before_delete: Dictionary = root.capture_state()
	dock.visgroup_list.select(0)
	dock._on_visgroup_delete()
	await frame()
	var after_delete: Dictionary = root.capture_state()
	note("visgroups after Delete", _visgroup_names(root))
	note(
		"brush A visgroups after Delete", Array(brush_a.get_meta("visgroups", PackedStringArray()))
	)
	note("Delete Visgroup registers an undo step", _undo_wrapped("on_visgroup_delete"))
	var state_moved: bool = (
		HFVibe.canonical(before_delete.get("visgroups", []))
		!= HFVibe.canonical(after_delete.get("visgroups", []))
	)
	if state_moved and not _undo_wrapped("on_visgroup_delete"):
		known(
			470,
			"Delete Visgroup is not undoable",
			(
				"on_visgroup_delete() calls level_root.remove_visgroup() directly. That erases"
				+ " the visgroup record and strips the membership meta off every node that"
				+ ' carried it, and capture_state() holds both under "visgroups" -- so the'
				+ " wrapper every neighbouring button uses would have restored it. Ctrl+Z after"
				+ " it undoes whatever the mapper did before instead."
			)
		)

	dock.set_selection_nodes([brush_a, brush_b])
	var before_group: Dictionary = root.capture_state()
	dock._on_group_selection()
	await frame()
	var after_group: Dictionary = root.capture_state()
	note("groups after Group Sel", after_group.get("groups", []))
	note("Group Selection registers an undo step", _undo_wrapped("on_group_selection"))
	if (
		(
			HFVibe.canonical(before_group.get("groups", []))
			!= HFVibe.canonical(after_group.get("groups", []))
		)
		and not _undo_wrapped("on_group_selection")
	):
		known(
			471,
			"Group Selection and Ungroup are not undoable",
			(
				"Both call record_history(), which only appends a row to the dock's own history"
				+ " list -- it never touches undo_redo. The group registry and the group_id meta"
				+ " on every member move with no undo step behind them."
			)
		)

	dock.queue_free()
	await frame()


func _entities_and_their_wiring() -> void:
	var root: Node3D = await fresh_root("EntityLevel")
	var dock = await _dock(root)
	await frame()

	var before_create: Dictionary = root.capture_state()
	dock._on_create_entity()
	await frame()
	var after_create: Dictionary = root.capture_state()
	var created: int = (
		(after_create.get("entities", []) as Array).size()
		- (before_create.get("entities", []) as Array).size()
	)
	note("entities added by Create Entity", created)
	note("Create Entity registers an undo step", _undo_wrapped("on_create_entity"))
	if created > 0 and not _undo_wrapped("on_create_entity"):
		known(
			472,
			"Create Entity is not undoable",
			(
				"on_create_entity() calls level_root.add_entity() straight. Placing a brush"
				+ ' goes through HFUndoHelper (plugin._commit_brush_placement, "Place Brush");'
				+ " creating an entity goes through nothing, so the new node cannot be taken"
				+ " back with Ctrl+Z and the next undo removes something else."
			)
		)

	var entity: Node3D = null
	for child in root.entities_node.get_children():
		if child is DraftEntity:
			entity = child
	if entity == null:
		note("no entity to wire", "skipping the I/O half")
		dock.queue_free()
		await frame()
		return

	entity.entity_data["targetname"] = "door_1"
	dock.set_selection_nodes([entity])
	dock.io_output_name.text = "OnPressed"
	dock.io_target_name.text = "door_1"
	dock.io_input_name.text = "Open"
	var before_wire: Dictionary = root.capture_state()
	dock._on_io_add()
	await frame()
	var after_wire: Dictionary = root.capture_state()
	note("outputs on the entity", root.get_entity_outputs(entity).size())
	note("Add Output registers an undo step", _undo_wrapped("on_io_add"))
	if (
		(
			HFVibe.canonical(before_wire.get("entities", []))
			!= HFVibe.canonical(after_wire.get("entities", []))
		)
		and not _undo_wrapped("on_io_add")
	):
		known(
			473,
			"Entity I/O add and remove are not undoable",
			(
				"on_io_add() and on_io_remove() call add_entity_output()/remove_entity_output()"
				+ " directly. The connections are in capture_state() under the entity, so the"
				+ " wrapper would carry them; Remove in particular destroys a connection with"
				+ " nothing to get it back."
			)
		)

	dock.queue_free()
	await frame()


func _paint_layers() -> void:
	var root: Node3D = await fresh_root("PaintLevel")
	var dock = await _dock(root)
	await frame()
	if not root.paint_layers:
		note("no paint layer manager", "skipping")
		dock.queue_free()
		await frame()
		return

	dock._on_paint_layer_add()
	await frame()
	note("paint layers after Add", root.paint_layers.layers.size())
	var layer = root.paint_layers.get_active_layer()
	if layer:
		layer.set_cell(Vector2i(0, 0), true)
		layer.set_cell(Vector2i(1, 0), true)
	var before_remove: Dictionary = root.capture_state()
	var painted_before: int = (
		(before_remove.get("paint_layers", []) as Array).size()
		if before_remove.has("paint_layers")
		else 0
	)
	dock._on_paint_layer_remove()
	await frame()
	var after_remove: Dictionary = root.capture_state()
	var painted_after: int = (
		(after_remove.get("paint_layers", []) as Array).size()
		if after_remove.has("paint_layers")
		else 0
	)
	note("captured paint layers, before and after Remove", [painted_before, painted_after])
	note("Remove Layer registers an undo step", _undo_wrapped("on_paint_layer_remove"))
	if painted_after < painted_before and not _undo_wrapped("on_paint_layer_remove"):
		known(
			474,
			"Remove Paint Layer is not undoable",
			(
				"on_paint_layer_remove() calls remove_active_paint_layer() straight, and the"
				+ " manager's remove_layer() frees the layer node and everything painted into"
				+ " it. add_surface_paint_layer() on the face side of the same dock goes through"
				+ " _commit_state_action(); this one does not, so a misclick on a terrain layer"
				+ " is permanent."
			)
		)

	var before_noise: Dictionary = root.capture_state()
	dock._on_heightmap_generate()
	await frame()
	var after_noise: Dictionary = root.capture_state()
	note("Generate Noise registers an undo step", _undo_wrapped("on_heightmap_generate"))
	if (
		(
			HFVibe.canonical(before_noise.get("paint_layers", []))
			!= HFVibe.canonical(after_noise.get("paint_layers", []))
		)
		and not _undo_wrapped("on_heightmap_generate")
	):
		known(
			475,
			"Generate Noise overwrites the heightmap with no undo step",
			(
				"on_heightmap_generate() calls generate_heightmap_noise() directly. It replaces"
				+ " the active layer's heightmap wholesale -- sculpted terrain included -- and"
				+ " nothing registers the state it replaced."
			)
		)

	dock.queue_free()
	await frame()
