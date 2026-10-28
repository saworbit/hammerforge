@tool
class_name HFPluginEditActions
extends RefCounted
## Undoable managed-object edit actions dispatched by HammerForge's command surfaces.

# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFUndoHelper = preload("undo_helper.gd")
const HFPluginGroups = preload("plugin_groups.gd")
const HFOpResult = preload("hf_op_result.gd")
const HFBrushEntity = preload("hf_brush_entity.gd")
const HFBrushConversion = preload("hf_brush_conversion.gd")
const HFGeneratorSystem = preload("systems/hf_generator_system.gd")
const HFNumberFormat = preload("hf_number_format.gd")
const DraftBrush = preload("brush_instance.gd")
const FaceData = preload("face_data.gd")
const HFTransformSystem = preload("systems/hf_transform_system.gd")
@warning_ignore_restore("shadowed_global_identifier")
const HFViewAxes = preload("hf_view_axes.gd")
const HFHiddenFaceSearch = preload("hf_hidden_face_search.gd")
const HFTranslationType = preload("hf_translation.gd")
const HFDimensions = preload("hf_dimensions.gd")
## The axes by index, as the settings Adjust Last shows name them.
const AXES := ["x", "y", "z"]


static func delete_selected(plugin: Object, root: Node) -> bool:
	var selection = plugin.get_editor_interface().get_selection()
	var targets := collect_managed_targets(plugin, root)
	var brush_ids: Array = targets["brush_ids"]
	var entity_paths: Array = targets["entity_paths"]
	var object_count := brush_ids.size() + entity_paths.size()
	if object_count == 0:
		return false
	var action_name := (
		"Delete Brushes"
		if entity_paths.is_empty()
		else ("Delete Entities" if brush_ids.is_empty() else "Delete HammerForge Objects")
	)
	if object_count >= 3:
		var dlg = ConfirmationDialog.new()
		dlg.title = action_name
		var ask := HFTranslationType.tn(
			"Delete {count} HammerForge object? This can be undone with Ctrl+Z.",
			"Delete {count} HammerForge objects? This can be undone with Ctrl+Z.",
			object_count
		)
		dlg.dialog_text = ask.format({"count": object_count})
		dlg.min_size = Vector2i(280, 80)
		plugin._add_confirmable_dialog(dlg)
		dlg.confirmed.connect(
			func():
				if not is_instance_valid(plugin) or not is_instance_valid(root):
					dlg.queue_free()
					return
				plugin.hf_selection.clear()
				selection.clear()
				HFUndoHelper.commit(
					plugin._get_undo_redo(),
					root,
					action_name,
					"delete_managed_nodes",
					[brush_ids, entity_paths],
					false,
					Callable(plugin, "_record_history")
				)
				dlg.queue_free()
		)
		dlg.canceled.connect(
			func():
				if not is_instance_valid(plugin):
					return
				dlg.queue_free()
		)
		dlg.popup_centered()
		return true
	plugin.hf_selection.clear()
	selection.clear()
	HFUndoHelper.commit(
		plugin._get_undo_redo(),
		root,
		action_name,
		"delete_managed_nodes",
		[brush_ids, entity_paths],
		false,
		Callable(plugin, "_record_history")
	)
	return true


## The selected brushes and entities, as the nodes themselves.
##
## `collect_managed_targets()` below answers the same question as ids and paths,
## which is what the `*_managed_nodes` methods take. The prefab capture path takes
## nodes, so this is the same walk with the other answer.
static func collect_managed_nodes(plugin: Object, root: Node) -> Dictionary:
	var brush_nodes: Array = []
	var entity_nodes: Array = []
	for node in plugin._current_selection_nodes():
		if node and node is Node3D and root.is_brush_node(node):
			brush_nodes.append(node)
		elif node and node is Node3D and root.is_entity_node(node):
			var entity: Node = plugin._managed_entity_owner(root, node)
			if entity:
				entity_nodes.append(entity)
	return {"brush_nodes": brush_nodes, "entity_nodes": entity_nodes}


## Put the selection on the clipboard. Changes nothing in the level, so there is
## no undo step: copying is not an edit (#703).
static func copy_selection(plugin: Object, root: Node) -> bool:
	var targets: Dictionary = collect_managed_nodes(plugin, root)
	return root.prefab_system.copy_to_clipboard(targets["brush_nodes"], targets["entity_nodes"])


## Place what is on the clipboard, where it was copied from.
##
## Registered through `commit_completed()` rather than `commit()`, for the reason
## that function exists: the paste has to be run to learn what it made, and what
## it made is what gets selected afterwards. It also makes redo deterministic,
## because redo puts back the state this paste produced rather than reading the
## clipboard a second time and pasting whatever is on it by then.
static func paste_clipboard(plugin: Object, root: Node) -> bool:
	# `.map` text copied since the last Copy goes in through the importer, at the
	# cursor, as the buffer holds no place for it (#1722).
	if root.prefab_system.newer_map_text() != "":
		return paste_at_cursor(plugin, root)
	var selection = plugin.get_editor_interface().get_selection()
	var before: Dictionary = root.capture_state()
	var result: Dictionary = root.prefab_system.paste_from_clipboard()
	var brush_ids: Array = result.get("brush_ids", [])
	var entity_nodes: Array = result.get("entity_nodes", [])
	if brush_ids.is_empty() and entity_nodes.is_empty():
		return false
	# Pasted work joins the current visgroup, inside the step (#1732).
	if root.visgroup_system:
		root.visgroup_system.join_current_all(brush_ids, entity_nodes)
	HFUndoHelper.commit_completed(
		plugin._get_undo_redo(), root, "Paste", before, Callable(plugin, "_record_history")
	)
	# Selected, because the first thing anyone does with a pasted piece is move
	# it, and hunting for it in the level first is not part of that.
	plugin.hf_selection.clear()
	for brush_id in brush_ids:
		var pasted = root.find_brush_by_id(str(brush_id))
		if pasted:
			plugin.hf_selection.append(pasted)
	for entity in entity_nodes:
		if is_instance_valid(entity):
			plugin.hf_selection.append(entity)
	plugin._apply_hf_selection(selection)
	return true


## Paste at Cursor (#1722): what is on the clipboard with the bottom centre of its
## box on the snapped point under the cursor, on the surface there or on the
## grid, as one undo step, and selected. Pasting into another level put a piece
## at its old coordinates, inside a wall or far from the work. `.map` text on the
## system clipboard newer than the buffer goes in through the importer, what it
## could not read counted in the message; otherwise the buffer, with its paint,
## sculpts and structures. `screen` is where the cursor was, or the last mouse
## position.
static func paste_at_cursor(plugin: Object, root: Node, screen: Variant = null) -> bool:
	var camera = plugin.get("last_3d_camera")
	if not (screen is Vector2):
		screen = plugin.get("last_3d_mouse_pos")
	var hit = root._raycast(camera, screen) if camera and screen is Vector2 else null
	if not hit:
		root.user_message.emit("Paste at Cursor: point at the level in the viewport", 1)
		return false
	var at: Vector3 = root._snap_point(hit.position)
	var before: Dictionary = root.capture_state()
	var brushes: Array = []
	var entities: Array = []
	var text: String = root.prefab_system.newer_map_text()
	var dropped := 0
	var first_dropped := ""
	if text != "":
		var made: Dictionary = root.file_system.paste_map_text(text, at)
		brushes = made["brushes"]
		entities = made["entities"]
		dropped = int(made["dropped"])
		first_dropped = str(made["first_dropped"])
	else:
		var result: Dictionary = root.prefab_system.paste_from_clipboard(at)
		for brush_id in result.get("brush_ids", []):
			var pasted = root.find_brush_by_id(str(brush_id))
			if pasted:
				brushes.append(pasted)
		entities = result.get("entity_nodes", [])
		_stand_on(brushes, entities, at)
	if brushes.is_empty() and entities.is_empty():
		root.user_message.emit("Paste at Cursor: the clipboard holds nothing to paste", 1)
		return false
	var brush_ids: Array = []
	for brush in brushes:
		brush_ids.append(str(brush.brush_id))
	if root.visgroup_system:
		root.visgroup_system.join_current_all(brush_ids, entities)
	HFUndoHelper.commit_completed(
		plugin._get_undo_redo(),
		root,
		"Paste at Cursor",
		before,
		Callable(plugin, "_record_history")
	)
	var said := (
		"Pasted %d brush%s and %d entit%s"
		% [
			brushes.size(),
			"" if brushes.size() == 1 else "es",
			entities.size(),
			"y" if entities.size() == 1 else "ies"
		]
	)
	if text != "":
		said += " from .map text"
	if dropped > 0:
		said += (
			"; left out %d line%s it could not read (%s)"
			% [dropped, "" if dropped == 1 else "s", first_dropped]
		)
	root.user_message.emit(said, 1 if dropped > 0 else 0)
	var selection = plugin.get_editor_interface().get_selection()
	plugin.hf_selection.clear()
	for node in brushes + entities:
		if is_instance_valid(node):
			plugin.hf_selection.append(node)
	plugin._apply_hf_selection(selection)
	return true


## Move `brushes` and `entities` together so the bottom centre of their box is at
## `at`.
static func _stand_on(brushes: Array, entities: Array, at: Vector3) -> void:
	var bounds := AABB()
	var first := true
	for brush in brushes:
		var place: Transform3D = (brush as Node3D).global_transform
		for face in brush.faces:
			if face == null:
				continue
			for corner in face.local_verts:
				var point: Vector3 = place * corner
				bounds = AABB(point, Vector3.ZERO) if first else bounds.expand(point)
				first = false
	for entity in entities:
		if is_instance_valid(entity):
			var point: Vector3 = (entity as Node3D).global_position
			bounds = AABB(point, Vector3.ZERO) if first else bounds.expand(point)
			first = false
	if first:
		return
	var bottom := Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
	var shift := at - bottom
	for node in brushes + entities:
		if is_instance_valid(node):
			(node as Node3D).global_position += shift


## Shift with an arrow: duplicate the selection and move the copy one step that
## way, as one undo step (#1716). The copy is the selection after, so pressing it
## again makes the next copy from that one, and a row is a key a copy.
static func duplicate_and_move(plugin: Object, root: Node, direction: Vector3) -> bool:
	var step = root.grid_snap if root.grid_snap > 0.0 else 1.0
	_read_out(plugin, direction * step)
	return duplicate_selected(plugin, root, direction * step, "Duplicate and Move")


## Show a move on the HUD for a moment, as "+Y 0.25 m".
static func _read_out(plugin: Object, offset: Vector3) -> void:
	if plugin.has_method("read_out_move"):
		plugin.read_out_move(HFViewAxes.describe(offset))


## `offset` is where the copy goes from the original: one grid step along +X
## unless given, as Duplicate has always put it.
static func duplicate_selected(
	plugin: Object, root: Node, offset: Variant = null, action := ""
) -> bool:
	var selection = plugin.get_editor_interface().get_selection()
	var nodes = plugin._current_selection_nodes()
	var shift: Vector3 = offset if offset is Vector3 else duplicate_shift(root)
	if _duplicates_keep_links(plugin) and root.prefab_system:
		var iid: String = root.prefab_system.whole_linked_copy(nodes)
		if iid != "":
			return _duplicate_linked_copy(plugin, root, iid, shift, selection)
	var infos := duplicate_infos(plugin, root, nodes, shift)
	var brush_infos: Array = infos[0]
	var entity_infos: Array = infos[1]
	var groups: Dictionary = infos[2]
	if brush_infos.is_empty() and entity_infos.is_empty():
		return false
	var action_name := (
		"Duplicate Brushes"
		if entity_infos.is_empty()
		else ("Duplicate Entities" if brush_infos.is_empty() else "Duplicate HammerForge Objects")
	)
	if action != "":
		action_name = action
	HFUndoHelper.commit(
		plugin._get_undo_redo(),
		root,
		action_name,
		"create_managed_duplicates",
		[brush_infos, entity_infos, groups],
		false,
		Callable(plugin, "_record_history")
	)
	plugin.hf_selection = duplicates_made(root, brush_infos, entity_infos)
	plugin._apply_hf_selection(selection)
	return true


## Where Duplicate puts a copy from its original: one grid step along +X.
static func duplicate_shift(root: Node) -> Vector3:
	return Vector3(root.grid_snap if root.grid_snap > 0.0 else 1.0, 0.0, 0.0)


## The copies of `nodes` `shift` along, as `create_managed_duplicates()` takes
## them: `[brush_infos, entity_infos, groups]`, `groups` the new groups a whole
## group copied makes (#1723).
static func duplicate_infos(plugin: Object, root: Node, nodes: Array, shift: Vector3) -> Array:
	var brush_infos: Array = []
	var entity_infos: Array = []
	# Each brush's id to its copy's, for a dimension copied with it (#2000).
	var copies: Dictionary = {}
	for node in nodes:
		if root.is_brush_node(node):
			var info = root.build_duplicate_info(node, shift)
			if not info.is_empty():
				brush_infos.append(info)
				copies[str(node.get("brush_id"))] = str(info.get("brush_id", ""))
		elif root.is_entity_node(node):
			var entity: Node = plugin._managed_entity_owner(root, node)
			if entity:
				var info: Dictionary = root.build_duplicate_entity_info(entity, shift)
				if not info.is_empty():
					entity_infos.append(info)
	# Each copy an entity of its own, as a duplicated point entity already is: a
	# duplicated door that kept its tie and its name joined the door it came from
	# (#1161). Its wires are left as they are, as a point entity's are.
	if not brush_infos.is_empty():
		HFBrushEntity.fresh_identities(brush_infos, [], root.entity_system)
	# A dimension copied with the walls it measures measures the copies (#2000).
	HFDimensions.follow_copies(entity_infos, copies)
	# A whole group copied is a new group of its own (#1723).
	var groups: Dictionary = (
		root.visgroup_system.regroup_copies(nodes, brush_infos, entity_infos)
		if root.visgroup_system
		else {}
	)
	return [brush_infos, entity_infos, groups]


## The copies `duplicate_infos()` described, once they are made.
static func duplicates_made(root: Node, brush_infos: Array, entity_infos: Array) -> Array:
	var made: Array = []
	for info in brush_infos:
		var duplicate_brush = root.find_brush_by_id(info.get("brush_id", ""))
		if duplicate_brush:
			made.append(duplicate_brush)
	for info in entity_infos:
		var duplicate_entity: Node = root.entities_node.get_node_or_null(
			NodePath(str(info.get("name", "")))
		)
		if duplicate_entity:
			made.append(duplicate_entity)
	return made


## Copies of `nodes` `shift` along, as Duplicate makes them, with no undo step:
## for Repeat Run, which makes one step for all it plays (#1735). The copies, or
## none.
static func make_duplicates(plugin: Object, root: Node, nodes: Array, shift: Vector3) -> Array:
	if _duplicates_keep_links(plugin) and root.prefab_system:
		var iid: String = root.prefab_system.whole_linked_copy(nodes)
		if iid != "":
			var copy: String = root.prefab_system.duplicate_linked(iid, shift)
			if copy == "":
				return []
			return root.prefab_system.pieces_of(root.prefab_system.get_instance(copy))
	var infos := duplicate_infos(plugin, root, nodes, shift)
	if (infos[0] as Array).is_empty() and (infos[1] as Array).is_empty():
		return []
	root.create_managed_duplicates(infos[0], infos[1], infos[2])
	return duplicates_made(root, infos[0], infos[1])


## Whether Ctrl+D of a whole linked prefab copy makes another linked copy, as
## the user preference says (#1734). Off, it makes ordinary geometry, as before.
static func _duplicates_keep_links(plugin: Object) -> bool:
	var prefs = plugin.get("_user_prefs")
	return prefs != null and bool(prefs.get_pref("duplicate_keeps_prefab_link", false))


## Another linked copy of the copy selected, `shift` along, as one undo step, and
## selected.
static func _duplicate_linked_copy(
	plugin: Object, root: Node, iid: String, shift: Vector3, selection
) -> bool:
	var before: Dictionary = root.capture_state()
	var made: String = root.prefab_system.duplicate_linked(iid, shift)
	if made == "":
		return false
	HFUndoHelper.commit_completed(
		plugin._get_undo_redo(),
		root,
		"Duplicate Linked Copy",
		before,
		Callable(plugin, "_record_history")
	)
	plugin.hf_selection = root.prefab_system.pieces_of(root.prefab_system.get_instance(made))
	plugin._apply_hf_selection(selection)
	return true


## Brush ids and entity paths for the current selection, shaped the way the
## `*_managed_nodes` methods on LevelRoot take them.
##
## The four transform commands pass both arrays on to `HFUndoHelper.commit()` as
## a scope, which is a claim that the command changes those objects and nothing
## else (#737, #761). They can make it: they move, rotate, mirror and unrotate
## brushes and entities that are already there, and touch no registry, no palette
## and nothing else in the level. Nothing in a record can check a claim, so
## `test_scoped_undo_step.gd` is what holds them to it.
##
## There is no filter on the way. An entity used to end the claim, because a
## scope had nowhere to put one, and now it has one. The only rule left is "at
## least one object", which each command has already checked by the time it
## commits, and an id or a path that cannot be recorded makes
## `capture_brush_scope()` refuse and take the whole snapshot instead.
static func collect_managed_targets(plugin: Object, root: Node) -> Dictionary:
	var nodes = plugin._current_selection_nodes()
	var entity_paths: Array = []
	for node in nodes:
		if node and node is Node3D and root.is_entity_node(node):
			var entity: Node = plugin._managed_entity_owner(root, node)
			if entity:
				entity_paths.append(root.get_path_to(entity))
	return {"brush_ids": selection_brush_ids(plugin, root), "entity_paths": entity_paths}


## The ids of the selected brushes, as `HFBrushSystem.brush_ids_of()` gives them.
static func selection_brush_ids(plugin: Object, root: Node) -> Array:
	return Array(root.brush_system.brush_ids_of(plugin._current_selection_nodes()))


## A collation key that changes whenever the next press would mean something
## different. Two commands only merge into one undo entry when they are the same
## command, on the same objects, going the same way.
static func collation_tag(
	action: String, brush_ids: Array, entity_paths: Array, inputs: Array
) -> String:
	var parts := PackedStringArray([action])
	for brush_id in brush_ids:
		parts.append(str(brush_id))
	for entity_path in entity_paths:
		parts.append(str(entity_path))
	for value in inputs:
		parts.append(str(value))
	return "|".join(parts)


## Tell the plugin what a command ran with, for Adjust Last (#1867). A stand-in
## plugin without Adjust Last is told nothing.
static func _note_run(plugin: Object, id: String, settings: Dictionary, recipe: Dictionary) -> void:
	if plugin.has_method("_note_last_run"):
		plugin.call("_note_last_run", id, settings, recipe)


## A Hollow's thickness changed in Adjust Last, on the dock's Hollow box too, so
## the next Hollow and Repeat Last Command take it (#1896).
static func _hollow_to_dock(settings: Dictionary, plugin: Object) -> void:
	if not is_instance_valid(plugin):
		return
	var dock = plugin.get("dock")
	if dock and dock.get("hollow_thickness") and settings.has("thickness"):
		dock.hollow_thickness.value = float(settings["thickness"])


## A copy of the faces of brush `brush_id` as they are now, which the brush
## changing or going does not touch. Empty when there is no such brush.
static func _faces_of(root: Node, brush_id: String) -> Array:
	var brush = root.find_brush_by_id(brush_id)
	var out: Array = []
	if brush is DraftBrush:
		for data in (brush as DraftBrush).serialize_faces():
			out.append(FaceData.from_dict(data))
	return out


static func nudge_selected(plugin: Object, root: Node, direction: Vector3) -> bool:
	var step = root.grid_snap if root.grid_snap > 0.0 else 1.0
	var targets := collect_managed_targets(plugin, root)
	var brush_ids: Array = targets["brush_ids"]
	var entity_paths: Array = targets["entity_paths"]
	if brush_ids.is_empty() and entity_paths.is_empty():
		return false
	var offset = direction * step
	_read_out(plugin, offset)
	HFUndoHelper.commit(
		plugin._get_undo_redo(),
		root,
		"Nudge HammerForge Objects",
		"nudge_managed_nodes",
		[brush_ids, entity_paths, offset],
		false,
		Callable(plugin, "_record_history"),
		collation_tag("nudge", brush_ids, entity_paths, [direction, step]),
		true,
		brush_ids,
		entity_paths
	)
	var again := func(s: Dictionary) -> Array: return [brush_ids, entity_paths, s["offset"]]
	var recipe := {"action": "Nudge HammerForge Objects", "method": "nudge_managed_nodes"}
	recipe["args"] = again
	recipe["scope_ids"] = brush_ids
	recipe["scope_paths"] = entity_paths
	_note_run(plugin, "nudge", {"offset": offset}, recipe)
	return true


## Group Selection and Ungroup, which `plugin_groups.gd` makes (#1723).
static func group_selected(plugin: Object, root: Node) -> bool:
	return HFPluginGroups.group_selected(plugin, root)


static func ungroup_selected(plugin: Object, root: Node) -> bool:
	return HFPluginGroups.ungroup_selected(plugin, root)


static func hollow_selected(plugin: Object, root: Node) -> bool:
	var nodes = plugin._current_selection_nodes()
	if nodes.is_empty():
		return false
	var brush = nodes[0]
	if not root.is_brush_node(brush):
		return false
	# A wall of a hollow re-hollows it, as the dock's button does with the same
	# selection (#1675).
	var dock = plugin.get("dock")
	if dock and str(dock.get("_active_hollow_id")) != "":
		dock._on_hollow()
		return true
	var brush_id: String = root.brush_system.ensure_brush_id(brush)
	var thickness = plugin.dock.get_hollow_thickness() if plugin.dock else 0.25
	var check: HFOpResult = root.can_hollow_brush(brush_id, thickness)
	if not check.ok:
		root.user_message.emit(check.user_text(), 1)
		return true
	if root.hollow_preview:
		root.hollow_preview.show_preview(brush_id, thickness)
	var dlg = ConfirmationDialog.new()
	dlg.title = "Hollow Brush"
	dlg.dialog_text = hollow_question(root, thickness, check)
	dlg.min_size = Vector2i(300, 100)
	plugin._add_confirmable_dialog(dlg)
	dlg.confirmed.connect(
		func():
			if not is_instance_valid(plugin) or not is_instance_valid(root):
				dlg.queue_free()
				return
			if root.hollow_preview:
				root.hollow_preview.clear()
			# The solid as it is before the walls take its place, for Adjust Last to
			# ask whether a new thickness fits it (#1995).
			var solid := _faces_of(root, brush_id)
			HFUndoHelper.commit(
				plugin._get_undo_redo(),
				root,
				"Hollow",
				"hollow_brush_by_id",
				[brush_id, thickness],
				false,
				Callable(plugin, "_record_history"),
				"",
				true
			)
			var again := func(s: Dictionary) -> Array: return [brush_id, float(s["thickness"])]
			var fits := func(s: Dictionary, level: Node) -> HFOpResult:
				return level.brush_system.can_hollow_faces(solid, float(s["thickness"]))
			var recipe := {
				"action": "Hollow",
				"method": "hollow_brush_by_id",
				"args": again,
				"check": fits,
				"dock": _hollow_to_dock.bind(plugin),
			}
			_note_run(plugin, "hollow", {"thickness": thickness}, recipe)
			dlg.queue_free()
	)
	dlg.canceled.connect(
		func():
			if not is_instance_valid(plugin):
				return
			if root and is_instance_valid(root) and root.hollow_preview:
				root.hollow_preview.clear()
			dlg.queue_free()
	)
	dlg.popup_centered()
	return true


static func merge_selected(plugin: Object, root: Node) -> bool:
	var brush_ids := selection_brush_ids(plugin, root)
	if brush_ids.size() < 2:
		if plugin.dock:
			plugin.dock.show_toast("Select at least 2 brushes to merge", 1)
		return false
	# The check holds the plan it makes for the merge committed below, so a press
	# plans once, and lets go of it after (#1257). A redo merges nothing: it puts
	# back the level this merge made (#1275).
	var check: HFOpResult = root.can_merge_brushes(brush_ids, true)
	if not check.ok:
		root.user_message.emit(check.user_text(), 1)
		return true
	HFUndoHelper.commit(
		plugin._get_undo_redo(),
		root,
		"Merge Brushes",
		"merge_brushes_by_ids",
		[brush_ids],
		false,
		Callable(plugin, "_record_history"),
		"",
		true
	)
	root.release_merge_plan()
	return true


static func move_selected_to_floor(plugin: Object, root: Node) -> bool:
	return move_selected_vertical(plugin, root, "Move to Floor", "move_brushes_to_floor")


static func move_selected_to_ceiling(plugin: Object, root: Node) -> bool:
	return move_selected_vertical(plugin, root, "Move to Ceiling", "move_brushes_to_ceiling")


static func move_selected_vertical(
	plugin: Object, root: Node, action_name: String, method_name: String
) -> bool:
	var brush_ids := selection_brush_ids(plugin, root)
	if brush_ids.is_empty():
		return false
	# A brush already resting where it would go leaves no step (#1303).
	HFUndoHelper.commit_if_changed(
		plugin._get_undo_redo(),
		root,
		action_name,
		method_name,
		[brush_ids],
		Callable(plugin, "_record_history")
	)
	return true


## Snap to Grid: each selected brush's bounds corner and each entity's origin onto
## the grid, as one step, and none when the selection is on the grid already. The
## step records the selected brushes alone when that is all there is;
## `commit_if_changed()` scopes brushes only, so a selection with an entity in it
## records the whole level, or undo would leave the entity where it was snapped.
static func snap_selected_to_grid(plugin: Object, root: Node) -> bool:
	if not root:
		return false
	var targets := collect_managed_targets(plugin, root)
	var brush_ids: Array = targets["brush_ids"]
	var entity_paths: Array = targets["entity_paths"]
	if brush_ids.is_empty() and entity_paths.is_empty():
		return false
	var check: HFOpResult = root.can_snap_to_grid()
	if not check.ok:
		root.user_message.emit(check.user_text(), 1)
		return true
	HFUndoHelper.commit_if_changed(
		plugin._get_undo_redo(),
		root,
		"Snap to Grid",
		"snap_managed_nodes_to_grid",
		[brush_ids, entity_paths],
		Callable(plugin, "_record_history"),
		brush_ids if entity_paths.is_empty() else []
	)
	return true


## Cut every selected brush along the plane of the currently selected face.
##
## With rotation in the toolbox this is the cheapest route to an angled cut:
## pick the face whose plane you want, select what to cut, and clip.
static func clip_to_face_plane_selected(plugin: Object, root: Node) -> bool:
	if not root:
		return false
	var face_selection: Dictionary = root.face_selection
	if face_selection.is_empty():
		root.user_message.emit(
			"Clip to Face: select a face to cut along first — enter Face Select and click one", 1
		)
		return false
	var source_id := ""
	var face_index := -1
	for key in face_selection:
		var indices: Array = face_selection.get(key, [])
		if indices.is_empty():
			continue
		var source = root.find_brush_by_id(str(key))
		if source == null:
			continue
		source_id = str(key)
		face_index = int(indices[0])
		break
	if source_id == "" or face_index < 0:
		root.user_message.emit("Clip to Face: no usable face is selected", 1)
		return false

	var plane: Plane = root.brush_system.face_world_plane(source_id, face_index)
	if plane.normal.length_squared() < 0.5:
		root.user_message.emit("Clip to Face: the selected face has no usable plane", 1)
		return false

	var brush_ids := clip_target_brush_ids(plugin, root)
	if brush_ids.is_empty():
		root.user_message.emit("Clip to Face: select the brushes to cut", 1)
		return false

	# Ask before committing. An action that cuts nothing would still open an undo
	# entry and claim the level changed.
	var cuttable: Array = []
	for brush_id in brush_ids:
		if root.brush_system.plane_splits_brush(str(brush_id), plane):
			cuttable.append(str(brush_id))
	if cuttable.is_empty():
		root.user_message.emit(
			"Clip to Face: that plane does not pass through any selected brush", 1
		)
		return false

	HFUndoHelper.commit(
		plugin._get_undo_redo(),
		root,
		"Clip to Face Plane",
		"clip_brushes_by_plane",
		[cuttable, plane],
		false,
		Callable(plugin, "_record_history"),
		"",
		true
	)
	# Which face it cut along, as the bridge's clip_to_face takes it, so the
	# Adjust panel shows it and Repeat Run cuts the next brushes along it (#1896).
	var again := func(_s: Dictionary) -> Array: return [cuttable, plane]
	var recipe := {"action": "Clip to Face Plane", "method": "clip_brushes_by_plane", "args": again}
	_note_run(
		plugin, "clip_to_face", {"plane_brush_id": source_id, "plane_face": face_index}, recipe
	)
	_release_face_select_after_cut(plugin, root)
	return true


## Build a Trim Run along the faces picked in Face Select (#1414), with the
## Structure section's Trim Run settings. No face picked, a picked face that is
## not upright, or a trim that cannot turn the run's corners builds nothing and
## leaves no step, and the message says which.
static func run_trim_along_faces(plugin: Object, root: Node) -> bool:
	if not root:
		return false
	var picked: Dictionary = root.face_selection
	if picked.is_empty():
		root.user_message.emit(
			"Run Trim Along Faces: pick the wall faces first — enter Face Select and click them", 1
		)
		return false
	var read: Dictionary = root.trim_run_from_faces(picked)
	if read.has("refused"):
		root.user_message.emit(_refusal_text(read), 1)
		return false
	var type := HFGeneratorSystem.TYPE_TRIM_RUN
	var dock = plugin.get("dock")
	var settings: Dictionary = (
		dock.trim_run_settings() if dock else HFGeneratorSystem.default_settings(type)
	)
	var check: HFOpResult = HFGeneratorSystem.can_build(type, settings, read["run"])
	if not check.ok:
		root.user_message.emit(check.user_text(), 1)
		return false
	var before: int = root.generator_count()
	# An absolute redo, as Create Structure has: the pieces are minted once.
	HFUndoHelper.commit(
		plugin._get_undo_redo(),
		root,
		"Run Trim Along Faces",
		"create_generator",
		[type, settings, read["placement"], root.active_material, read["run"]],
		false,
		Callable(plugin, "_record_history"),
		"",
		true
	)
	if root.generator_count() <= before:
		return false
	root.user_message.emit(_built_text("Trim Run built along", read), 0)
	return true


## Lay the selected Trim Run along the faces picked now (#1414). The run is the
## one a selected piece belongs to, or, in Face Select, the one a piece selected
## on the way in belongs to, as Clip to Face Plane reads its brushes. Its
## settings stay. A refusal leaves the run it has and records nothing, and so do
## the faces it already follows.
static func repick_trim_run(plugin: Object, root: Node) -> bool:
	if not root:
		return false
	var label := "Re-pick Trim Run"
	var record = root.generator_for_selection(clip_target_brush_ids(plugin, root))
	if record == null:
		var how := "select a piece of the trim run, then pick the faces it should follow"
		root.user_message.emit("%s: %s in Face Select" % [label, how], 1)
		return false
	if not HFGeneratorSystem.follows_run(record.type):
		var named := HFGeneratorSystem.display_name(record.type)
		root.user_message.emit(
			"%s: the selected %s is not built along faces" % [label, named.to_lower()], 1
		)
		return false
	if root.face_selection.is_empty():
		root.user_message.emit("%s: pick the faces it should follow in Face Select" % label, 1)
		return false
	# Read as its own type reads a run: a Trim Run's walls or a Sweep's faces (#1885).
	var read: Dictionary = root.run_from_faces(record.type, root.face_selection)
	if read.has("refused"):
		root.user_message.emit(_refusal_text(read), 1)
		return false
	var check: HFOpResult = HFGeneratorSystem.can_build(record.type, record.settings, read["run"])
	if not check.ok:
		root.user_message.emit(HFGeneratorSystem.not_changed_text(record.type, check), 1)
		return false
	var generator_id := str(record.generator_id)
	if root.generator_repick_changes_nothing(generator_id, read["run"], read["placement"]):
		root.user_message.emit("Nothing to re-pick: those faces give the run it has", 0)
		return false
	HFUndoHelper.commit(
		plugin._get_undo_redo(),
		root,
		label,
		"repick_generator",
		[generator_id, read["run"], read["placement"]],
		false,
		Callable(plugin, "_record_history"),
		"",
		true
	)
	# The pieces selected on the way into Face Select are gone, rebuilt under
	# new ids. The new pieces take their place, so leaving the mode selects the
	# run again, and another Re-pick still knows which run it means.
	var saved: Array = plugin.get("_face_mode_saved_object_selection")
	if saved != null:
		var lost := false
		for node in saved.duplicate():
			if not is_instance_valid(node) or not (node as Node).is_inside_tree():
				saved.erase(node)
				lost = true
		var rebuilt = root.generator_for_id(generator_id)
		if lost and rebuilt != null:
			for brush_id in rebuilt.brush_ids:
				var piece = root.find_brush_by_id(str(brush_id))
				if piece != null:
					saved.append(piece)
	var lead := "%s re-picked along" % HFGeneratorSystem.display_name(record.type)
	root.user_message.emit(_built_text(lead, read), 0)
	return true


## A refusal from `trim_run_from_faces()`, with its hint.
static func _refusal_text(read: Dictionary) -> String:
	var hint := str(read.get("hint", ""))
	return str(read["refused"]) + (". " + hint if hint != "" else "")


## What a Trim Run was built along, and the faces it left out because another
## brush covers every edge they have.
static func _built_text(lead: String, read: Dictionary) -> String:
	var used := int(read["used"])
	var text := "%s %d face%s" % [lead, used, "" if used == 1 else "s"]
	var hidden: PackedStringArray = read["hidden"]
	if not hidden.is_empty():
		text += (". Left out, with no edge open to the room: %s" % ", ".join(hidden))
	return text


## The brushes a face-plane cut should take, including the ones Face Select hid.
##
## Entering Face Select empties the object selection on purpose, so by the time a
## reference face exists there is nothing left in the live selection to cut. The
## objects that were selected on the way in are the ones the user meant.
static func clip_target_brush_ids(plugin: Object, root: Node) -> Array:
	var brush_ids := selection_brush_ids(plugin, root)
	if not brush_ids.is_empty():
		return brush_ids
	var saved: Array = plugin.get("_face_mode_saved_object_selection")
	if saved == null:
		return brush_ids
	return Array(root.brush_system.brush_ids_of(saved))


## Both selections named brushes that the cut has just replaced. Drop them and
## leave Face Select rather than restoring a selection of freed nodes.
static func _release_face_select_after_cut(plugin: Object, root: Node) -> void:
	var saved: Array = plugin.get("_face_mode_saved_object_selection")
	if saved != null:
		saved.clear()
	if root and root.has_method("clear_face_selection"):
		root.clear_face_selection()
	if plugin.has_method("_close_face_select_mode"):
		plugin._close_face_select_mode()


## A line for a cut's confirmation when the cut on show leaves a piece of a
## sculpted face with other than four corners, which cannot hold the sculpt. The
## warning after the cut stays, as the record in the log (#871).
static func _dropped_sculpts_line(preview: Object) -> String:
	var count: int = int(preview.get("sculpts_dropped")) if preview else 0
	if count <= 0:
		return ""
	var said := HFTranslationType.tn(
		"{count} sculpt cannot follow this cut and will be dropped.",
		"{count} sculpts cannot follow this cut and will be dropped.",
		count
	)
	return said.format({"count": count}) + "\n"


## What Hollow's confirmation asks, from the key and the dock's button alike, so
## both say how many walls and which sculpts the cut drops (#1675). The wall count
## comes from the same planner that built the preview. A brush with many faces
## shells into many walls, a cylinder into a tube of them, and that is worth
## knowing before committing rather than after.
static func hollow_question(root: Node, thickness: float, check: HFOpResult) -> String:
	return (
		"Hollow with wall thickness %s into %s?\n%s(Yellow wireframe shows resulting walls)"
		% [
			HFNumberFormat.number(thickness, root.grid_snap),
			check.message if check.message != "" else "walls",
			_dropped_sculpts_line(root.hollow_preview),
		]
	)


## What Clip's confirmation asks, from the key and the dock's button alike (#1675).
static func clip_question(root: Node, split_pos: float) -> String:
	return (
		"Split brush along Y axis at %s?\n%s(Cyan wireframe shows resulting pieces)"
		% [
			HFNumberFormat.number(split_pos, root.grid_snap),
			_dropped_sculpts_line(root.clip_preview),
		]
	)


static func clip_selected(plugin: Object, root: Node) -> bool:
	var nodes = plugin._current_selection_nodes()
	if nodes.is_empty():
		return false
	var brush = nodes[0]
	if not root.is_brush_node(brush):
		return false
	var brush_id: String = root.brush_system.ensure_brush_id(brush)
	var split_pos: float = root.default_clip_position(brush_id, 1)
	var check: HFOpResult = root.can_clip_brush(brush_id, 1, split_pos)
	if not check.ok:
		root.user_message.emit(check.user_text(), 1)
		return true
	if root.clip_preview:
		root.clip_preview.show_preview(brush_id, 1, split_pos)
	var dlg = ConfirmationDialog.new()
	dlg.title = "Clip Brush"
	dlg.dialog_text = clip_question(root, split_pos)
	dlg.min_size = Vector2i(300, 100)
	plugin._add_confirmable_dialog(dlg)
	dlg.confirmed.connect(
		func():
			if not is_instance_valid(plugin) or not is_instance_valid(root):
				dlg.queue_free()
				return
			if root.clip_preview:
				root.clip_preview.clear()
			# The brush whole, for Adjust Last to ask whether a new cut crosses it
			# (#1995).
			var cut = root.find_brush_by_id(brush_id)
			var whole: AABB = (
				root.brush_system.world_bounds_of(cut) if cut is DraftBrush else AABB()
			)
			HFUndoHelper.commit(
				plugin._get_undo_redo(),
				root,
				"Clip Brush",
				"clip_brush_by_id",
				[brush_id, 1, split_pos],
				false,
				Callable(plugin, "_record_history"),
				"",
				true
			)
			var again := func(s: Dictionary) -> Array:
				return [brush_id, AXES.find(str(s["axis"])), float(s["position"])]
			var crosses := func(s: Dictionary, level: Node) -> HFOpResult:
				return level.brush_system.can_clip_bounds(
					whole, AXES.find(str(s["axis"])), float(s["position"])
				)
			var recipe := {"action": "Clip Brush", "method": "clip_brush_by_id", "args": again}
			recipe["check"] = crosses
			_note_run(plugin, "clip", {"axis": "y", "position": split_pos}, recipe)
			dlg.queue_free()
	)
	dlg.canceled.connect(
		func():
			if not is_instance_valid(plugin):
				return
			if root and is_instance_valid(root) and root.clip_preview:
				root.clip_preview.clear()
			dlg.queue_free()
	)
	dlg.popup_centered()
	return true


static func carve_selected(plugin: Object, root: Node) -> bool:
	var nodes = plugin._current_selection_nodes()
	if nodes.is_empty():
		return false
	var carve_ids: Array = []
	var refusal: HFOpResult = null
	for brush_id in root.brush_system.brush_ids_of(nodes):
		# Asked before the confirmation, as Hollow and Clip ask theirs, so a carve
		# that would cut nothing says why instead of asking first (#1267).
		var check: HFOpResult = root.can_carve_brush(brush_id)
		if check.ok:
			carve_ids.append(brush_id)
		elif refusal == null:
			refusal = check
	if carve_ids.is_empty():
		if refusal == null:
			return false
		root.user_message.emit(refusal.user_text(), 1)
		return true
	if root.carve_preview:
		root.carve_preview.show_preview(carve_ids[0])
	var hidden := 0
	var locked := 0
	for brush_id in carve_ids:
		hidden += root.carve_system.hidden_overlaps(brush_id)
		locked += root.carve_system.locked_overlaps(brush_id)
	var hidden_line := ""
	if hidden > 0:
		var left := HFTranslationType.tn(
			"{count} hidden brush overlaps and is left alone.",
			"{count} hidden brushes overlap and are left alone.",
			hidden
		)
		hidden_line = left.format({"count": hidden}) + "\n"
	# Carve leaves a locked brush whole, and says so before the yes (#1973).
	var locked_line := ""
	if locked > 0:
		var said := HFTranslationType.tn(
			"{count} locked brush overlaps and is left alone.",
			"{count} locked brushes overlap and are left alone.",
			locked
		)
		locked_line = said.format({"count": locked}) + "\n"
	var dlg = ConfirmationDialog.new()
	dlg.title = "Carve"
	var ask := HFTranslationType.tn(
		"Carve {count} brush?", "Carve {count} brushes?", carve_ids.size()
	)
	dlg.dialog_text = (
		ask.format({"count": carve_ids.size()})
		+ "\n"
		+ hidden_line
		+ locked_line
		+ _dropped_sculpts_line(root.carve_preview)
		+ HFTranslationType.t("(Green wireframe shows resulting pieces)")
	)
	dlg.min_size = Vector2i(300, 100)
	plugin._add_confirmable_dialog(dlg)
	dlg.confirmed.connect(
		func():
			if not is_instance_valid(plugin) or not is_instance_valid(root):
				dlg.queue_free()
				return
			if root.carve_preview:
				root.carve_preview.clear()
			for i in carve_ids.size():
				var brush_id: String = carve_ids[i]
				# The first was checked against this level as the dialog opened. A
				# carver after it can have been cut up by an earlier one, or lost
				# what it overlapped, and a carve that cuts nothing is no undo step.
				if i > 0 and not root.can_carve_brush(brush_id).ok:
					continue
				HFUndoHelper.commit(
					plugin._get_undo_redo(),
					root,
					"Carve",
					"carve_with_brush",
					[brush_id],
					false,
					Callable(plugin, "_record_history"),
					"",
					true
				)
			dlg.queue_free()
	)
	dlg.canceled.connect(
		func():
			if not is_instance_valid(plugin):
				return
			if root and is_instance_valid(root) and root.carve_preview:
				root.carve_preview.clear()
			dlg.queue_free()
	)
	dlg.popup_centered()
	return true


## Keep only the volume the selected brushes share, the first selected being the
## brush cut down (#1426). Asked before the confirmation, as Carve asks, so brushes
## that share nothing say so instead of asking first; then the brush that would be
## kept is shown in Carve's green.
static func intersect_selected(plugin: Object, root: Node) -> bool:
	var brush_ids := selection_brush_ids(plugin, root)
	if brush_ids.size() < 2:
		if plugin.dock:
			plugin.dock.show_toast("Select at least 2 brushes to intersect", 1)
		return false
	var check: HFOpResult = root.can_intersect_brushes(brush_ids)
	if not check.ok:
		root.user_message.emit(check.user_text(), 1)
		return true
	if root.carve_preview:
		root.carve_preview.show_intersect_preview(brush_ids)
	var dlg = ConfirmationDialog.new()
	dlg.title = "Intersect"
	var ask := HFTranslationType.tn(
		"Keep only the volume {count} brush has?",
		"Keep only the volume {count} brushes share?",
		brush_ids.size()
	)
	dlg.dialog_text = (
		ask.format({"count": brush_ids.size()})
		+ "\n"
		+ _dropped_sculpts_line(root.carve_preview)
		+ HFTranslationType.t("(Green wireframe shows the brush that is kept)")
	)
	dlg.min_size = Vector2i(300, 100)
	plugin._add_confirmable_dialog(dlg)
	dlg.confirmed.connect(
		func():
			if not is_instance_valid(plugin) or not is_instance_valid(root):
				dlg.queue_free()
				return
			if root.carve_preview:
				root.carve_preview.clear()
			# Asked again: a step is registered whatever the method then does, and an
			# intersect that keeps nothing is no step.
			var still: HFOpResult = root.can_intersect_brushes(brush_ids)
			if still.ok:
				HFUndoHelper.commit(
					plugin._get_undo_redo(),
					root,
					"Intersect",
					"intersect_brushes_by_ids",
					[brush_ids],
					false,
					Callable(plugin, "_record_history"),
					"",
					true
				)
			else:
				root.user_message.emit(still.user_text(), 1)
			dlg.queue_free()
	)
	dlg.canceled.connect(
		func():
			if not is_instance_valid(plugin):
				return
			if root and is_instance_valid(root) and root.carve_preview:
				root.carve_preview.clear()
			dlg.queue_free()
	)
	dlg.popup_centered()
	return true


## Replace the selected brushes with one brush, the convex hull of all their
## corners (#1715). Asked before the confirmation, as Intersect asks, so brushes
## that cannot be wrapped say so instead of asking first; then the brush that
## would be made is shown in Carve's green.
static func hull_selected(plugin: Object, root: Node) -> bool:
	var brush_ids := selection_brush_ids(plugin, root)
	if brush_ids.size() < 2:
		if plugin.dock:
			plugin.dock.show_toast("Select at least 2 brushes to wrap in a hull", 1)
		return false
	var check: HFOpResult = root.can_hull_brushes(brush_ids)
	if not check.ok:
		root.user_message.emit(check.user_text(), 1)
		return true
	if root.carve_preview:
		root.carve_preview.show_hull_preview(brush_ids)
	var dlg = ConfirmationDialog.new()
	dlg.title = "Hull of Selection"
	var ask := HFTranslationType.tn(
		"Replace {count} brush with one brush around it?",
		"Replace {count} brushes with one brush around them all?",
		brush_ids.size()
	)
	dlg.dialog_text = (
		ask.format({"count": brush_ids.size()})
		+ "\n"
		+ _dropped_sculpts_line(root.carve_preview)
		+ HFTranslationType.t("(Green wireframe shows the brush that is made)")
	)
	dlg.min_size = Vector2i(300, 100)
	plugin._add_confirmable_dialog(dlg)
	dlg.confirmed.connect(
		func():
			if not is_instance_valid(plugin) or not is_instance_valid(root):
				dlg.queue_free()
				return
			if root.carve_preview:
				root.carve_preview.clear()
			# Asked again: a step is registered whatever the method then does.
			var still: HFOpResult = root.can_hull_brushes(brush_ids)
			if still.ok:
				HFUndoHelper.commit(
					plugin._get_undo_redo(),
					root,
					"Hull of Selection",
					"hull_brushes_by_ids",
					[brush_ids],
					false,
					Callable(plugin, "_record_history"),
					"",
					true
				)
			else:
				root.user_message.emit(still.user_text(), 1)
			dlg.queue_free()
	)
	dlg.canceled.connect(
		func():
			if not is_instance_valid(plugin):
				return
			if root and is_instance_valid(root) and root.carve_preview:
				root.carve_preview.clear()
			dlg.queue_free()
	)
	dlg.popup_centered()
	return true


## Hide Faces Against Solids (#1719): every face of the selected brushes that lies
## flat against another solid brush, or of the selected faces when no brush is
## selected, made Hidden as one undo step. The faces it found are picked while the
## dialog asks, so the face overlay shows them, and Cancel picks what was picked
## before.
static func hide_faces_against_solids(plugin: Object, root: Node) -> bool:
	var brushes: Array = []
	for brush_id in selection_brush_ids(plugin, root):
		var brush = root.brush_system.find_brush_by_id(str(brush_id))
		if brush:
			brushes.append(brush)
	var among: Dictionary = {}
	if brushes.is_empty():
		among = root.face_selection.duplicate(true)
		for key in among:
			var brush = root.brush_system.find_brush_by_id(str(key))
			if brush:
				brushes.append(brush)
	if brushes.is_empty():
		if plugin.dock:
			plugin.dock.show_toast("Select the brushes whose faces against solids to hide", 1)
		return false
	var found := HFHiddenFaceSearch.against_solids(root, brushes)
	if not among.is_empty():
		found = _only_in(found, among)
	var count := 0
	for key in found:
		count += (found[key] as Array).size()
	if count == 0:
		if plugin.dock:
			plugin.dock.show_toast(
				"No face of the selection lies flat against another solid brush", 0
			)
		return true
	var picked_before: Dictionary = root.face_selection.duplicate(true)
	root.face_selection = found.duplicate(true)
	root.face_selection_changed.emit()
	var dlg = ConfirmationDialog.new()
	dlg.title = "Hide Faces Against Solids"
	var ask := HFTranslationType.tn(
		(
			"Make {count} face Hidden?\nIt lies flat against another solid brush, so nobody"
			+ " sees it. The bake leaves it out of the mesh and the lightmap, and it keeps"
			+ " its collision.\n(The face is picked to show which)"
		),
		(
			"Make {count} faces Hidden?\nThey lie flat against other solid brushes, so nobody"
			+ " sees them. The bake leaves them out of the mesh and the lightmap, and they"
			+ " keep their collision.\n(The faces are picked to show which)"
		),
		count
	)
	dlg.dialog_text = ask.format({"count": count})
	dlg.min_size = Vector2i(300, 100)
	plugin._add_confirmable_dialog(dlg)
	dlg.confirmed.connect(
		func():
			if is_instance_valid(plugin) and is_instance_valid(root):
				HFUndoHelper.commit_if_changed(
					plugin._get_undo_redo(),
					root,
					"Hide Faces Against Solids",
					"set_faces_hidden",
					[found, true],
					Callable(plugin, "_record_history"),
					found.keys()
				)
				if plugin.dock:
					var said := HFTranslationType.tn(
						"{count} face made Hidden", "{count} faces made Hidden", count
					)
					plugin.dock.show_toast(said.format({"count": count}), 0)
			dlg.queue_free()
	)
	dlg.canceled.connect(
		func():
			if is_instance_valid(root):
				root.face_selection = picked_before
				root.face_selection_changed.emit()
			dlg.queue_free()
	)
	dlg.popup_centered()
	return true


## The faces of `found` that are in `among`, both brush key -> face indices.
static func _only_in(found: Dictionary, among: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in found:
		var kept: Array = []
		for face_idx in found[key]:
			if (among.get(key, []) as Array).has(face_idx):
				kept.append(face_idx)
		if not kept.is_empty():
			out[key] = kept
	return out


# ---------------------------------------------------------------------------
# Free transform
# ---------------------------------------------------------------------------


static func rotate_selected(plugin: Object, root: Node, direction: int) -> bool:
	if not root:
		return false
	var targets := collect_managed_targets(plugin, root)
	var brush_ids: Array = targets["brush_ids"]
	var entity_paths: Array = targets["entity_paths"]
	if brush_ids.is_empty() and entity_paths.is_empty():
		return false
	var step := absf(float(root.rotate_snap_degrees))
	if is_zero_approx(step):
		return false
	var angle_degrees := step if direction >= 0 else -step
	var axis_index: int = root.transform_axis_index(1)
	var pivot: Vector3 = root.resolve_transform_pivot(brush_ids, entity_paths)
	HFUndoHelper.commit(
		plugin._get_undo_redo(),
		root,
		"Rotate HammerForge Objects",
		"rotate_managed_nodes",
		[brush_ids, entity_paths, axis_index, angle_degrees, pivot],
		false,
		Callable(plugin, "_record_history"),
		collation_tag("rotate", brush_ids, entity_paths, [axis_index, signf(angle_degrees)]),
		true,
		brush_ids,
		entity_paths
	)
	var again := func(s: Dictionary) -> Array:
		return [
			brush_ids, entity_paths, maxi(0, AXES.find(str(s["axis"]))), float(s["angle"]), pivot
		]
	var recipe := {"action": "Rotate HammerForge Objects", "method": "rotate_managed_nodes"}
	recipe["args"] = again
	recipe["scope_ids"] = brush_ids
	recipe["scope_paths"] = entity_paths
	var id := "rotate_ccw" if direction >= 0 else "rotate_cw"
	_note_run(plugin, id, {"angle": angle_degrees, "axis": AXES[axis_index]}, recipe)
	return true


static func flip_selected(plugin: Object, root: Node) -> bool:
	if not root:
		return false
	var targets := collect_managed_targets(plugin, root)
	var brush_ids: Array = targets["brush_ids"]
	var entity_paths: Array = targets["entity_paths"]
	if brush_ids.is_empty() and entity_paths.is_empty():
		return false
	var axis_index: int = root.transform_axis_index(0)
	var pivot: Vector3 = root.resolve_transform_pivot(brush_ids, entity_paths)
	HFUndoHelper.commit(
		plugin._get_undo_redo(),
		root,
		"Flip HammerForge Objects",
		"flip_managed_nodes",
		[brush_ids, entity_paths, axis_index, pivot],
		false,
		Callable(plugin, "_record_history"),
		"",
		false,
		brush_ids,
		entity_paths
	)
	return true


## Mirror Copy: the selection stays where it is and gains a mirrored copy across
## each axis the level's Mirror Copy boxes tick, and each combination of them,
## all in one undo step. The key, the palette and the dock's button all come here,
## so they make the same copies.
##
## Registered through `commit_completed()`, as Paste is: the copies' ids are
## minted as they are made, and what was made is what joins the selection, so the
## mirrored whole moves as one and a second Mirror Copy mirrors all of it. A redo
## puts back the level this one made rather than making copies with new ids.
static func mirror_copy_selected(plugin: Object, root: Node) -> bool:
	if not root:
		return false
	var targets := collect_managed_targets(plugin, root)
	var brush_ids: Array = targets["brush_ids"]
	var entity_paths: Array = targets["entity_paths"]
	if brush_ids.is_empty() and entity_paths.is_empty():
		return false
	var axes: int = int(root.mirror_copy_axes) & 7
	if axes == 0:
		root.user_message.emit("Mirror Copy: tick X, Y or Z in Selection Tools first", 1)
		return false
	var pivot: Vector3 = root.resolve_mirror_copy_pivot(brush_ids, entity_paths)
	var before: Dictionary = root.capture_state()
	var made: Dictionary = root.mirror_copy_managed_nodes(brush_ids, entity_paths, axes, pivot)
	var copy_ids: Array = made.get("brush_ids", [])
	var copy_paths: Array = made.get("entity_paths", [])
	if copy_ids.is_empty() and copy_paths.is_empty():
		return false
	HFUndoHelper.commit_completed(
		plugin._get_undo_redo(), root, "Mirror Copy", before, Callable(plugin, "_record_history")
	)
	var selection = plugin.get_editor_interface().get_selection()
	plugin.hf_selection.clear()
	for brush_id in brush_ids + copy_ids:
		var brush = root.find_brush_by_id(str(brush_id))
		if brush:
			plugin.hf_selection.append(brush)
	for entity_path in entity_paths + copy_paths:
		var entity: Node = root.get_node_or_null(NodePath(str(entity_path)))
		if entity:
			plugin.hf_selection.append(entity)
	plugin._apply_hf_selection(selection)
	return true


## What the Shear dialog last asked for, so it opens as it was left.
static var last_shear := {"along": 0, "over": 1, "amount": 0.0, "degrees": false, "high": false}


## Lean the selection (#1718): every corner moves along `along` by `amount` for
## each metre past the selection's low side on `over`, or its high side with
## `high_fixed`, which stays where it is.
static func shear_selected(
	plugin: Object, root: Node, along: int, over: int, amount: float, high_fixed := false
) -> bool:
	if not root:
		return false
	var problem := HFTransformSystem.shear_problem(along, over, amount)
	if problem != "":
		root.user_message.emit(problem, 1)
		return false
	var targets := collect_managed_targets(plugin, root)
	var brush_ids: Array = targets["brush_ids"]
	var entity_paths: Array = targets["entity_paths"]
	if brush_ids.is_empty() and entity_paths.is_empty():
		root.user_message.emit("Shear: select brushes or entities first", 1)
		return false
	var bounds: AABB = root.transform_system.selection_bounds(brush_ids, entity_paths)
	var pivot: float = bounds.end[over] if high_fixed else bounds.position[over]
	var report := commit_shear(
		plugin._get_undo_redo(),
		Callable(plugin, "_record_history"),
		root,
		brush_ids,
		entity_paths,
		along,
		over,
		amount,
		pivot
	)
	return int(report.get("changed", 0)) + int(report.get("entities", 0)) > 0


## Shear and record it as one step named Shear, and say what it did. The dialog
## and the Shear tool's drag both come here, so a typed shear and the matching
## drag cannot differ.
static func commit_shear(
	undo_redo: Object,
	history_cb: Callable,
	root: Node,
	brush_ids: Array,
	entity_paths: Array,
	along: int,
	over: int,
	amount: float,
	pivot: float
) -> Dictionary:
	var before: Dictionary = root.capture_state()
	var report: Dictionary = root.shear_managed_nodes(
		brush_ids, entity_paths, along, over, amount, pivot
	)
	var brushes := int(report.get("changed", 0))
	var entities := int(report.get("entities", 0))
	if brushes + entities > 0:
		HFUndoHelper.commit_completed(undo_redo, root, "Shear", before, history_cb)
	var lead := "Sheared %d brush%s" % [brushes, "" if brushes == 1 else "es"]
	if entities > 0:
		lead += " and moved %d entit%s" % [entities, "y" if entities == 1 else "ies"]
	var refused: Array = report.get("refused", [])
	root.user_message.emit(
		HFTransformSystem.fold_report_text(report, lead), 1 if not refused.is_empty() else 0
	)
	return report


## The typed Shear: the axis that moves, the axis it leans over, the amount in
## metres per metre or in degrees, and the side that stays put.
static func open_shear_dialog(plugin: Object, root: Node) -> ConfirmationDialog:
	if not root:
		return null
	var targets := collect_managed_targets(plugin, root)
	if (targets["brush_ids"] as Array).is_empty() and (targets["entity_paths"] as Array).is_empty():
		root.user_message.emit("Shear: select brushes or entities first", 1)
		return null
	var dialog := ConfirmationDialog.new()
	dialog.title = "Shear"
	var grid := GridContainer.new()
	grid.columns = 2
	dialog.add_child(grid)
	var along := _labelled_options(grid, "Move along", ["X", "Y", "Z"], last_shear["along"])
	along.name = "Along"
	var over := _labelled_options(grid, "Leaning over", ["X", "Y", "Z"], last_shear["over"])
	over.name = "Over"
	var label := Label.new()
	label.text = "Amount"
	grid.add_child(label)
	var amount := SpinBox.new()
	amount.name = "Amount"
	amount.min_value = -100.0
	amount.max_value = 100.0
	amount.step = 0.001
	amount.value = float(last_shear["amount"])
	grid.add_child(amount)
	var unit := _labelled_options(
		grid, "In", ["metres per metre", "degrees"], 1 if last_shear["degrees"] else 0
	)
	unit.name = "Unit"
	var side := _labelled_options(
		grid, "Stays put", ["Low side", "High side"], 1 if last_shear["high"] else 0
	)
	side.name = "Side"
	dialog.confirmed.connect(
		func():
			var degrees := unit.selected == 1
			last_shear = {
				"along": along.selected,
				"over": over.selected,
				"amount": amount.value,
				"degrees": degrees,
				"high": side.selected == 1,
			}
			var lean: float = amount.value
			if degrees:
				lean = HFTransformSystem.shear_amount_for_degrees(clampf(amount.value, -89.0, 89.0))
			shear_selected(plugin, root, along.selected, over.selected, lean, side.selected == 1)
			dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	plugin._add_confirmable_dialog(dialog)
	dialog.popup_centered()
	return dialog


static func _labelled_options(
	grid: GridContainer, text: String, items: Array, selected: int
) -> OptionButton:
	var label := Label.new()
	label.text = text
	grid.add_child(label)
	var options := OptionButton.new()
	for item in items:
		options.add_item(str(item))
	options.select(selected)
	grid.add_child(options)
	return options


## Clear rotation on the selected brushes, keeping their position and size.
##
## Hollow, clip and carve all work in the brush's own frame now, so this is a
## tidying command rather than the way back to any of them.
static func reset_rotation_selected(plugin: Object, root: Node) -> bool:
	if not root:
		return false
	var targets := collect_managed_targets(plugin, root)
	var brush_ids: Array = targets["brush_ids"]
	if brush_ids.is_empty():
		return false
	# Brushes already standing square leave no step (#1303).
	HFUndoHelper.commit_if_changed(
		plugin._get_undo_redo(),
		root,
		"Reset HammerForge Rotation",
		"reset_managed_rotation",
		[brush_ids],
		Callable(plugin, "_record_history"),
		brush_ids
	)
	return true


## Convert to Brushes (#1440): each selected MeshInstance3D or CSG node that can
## be a brush becomes one where it stands, and is hidden, not deleted. One undo
## step takes the brushes away and shows the nodes again, and the new brushes are
## what is selected. A node that cannot be a brush is named in the toast with why
## and left as it was.
static func convert_selected_to_brushes(plugin: Object, root: Node) -> bool:
	if not root:
		return false
	var nodes: Array = []
	for node in plugin._current_selection_nodes():
		if node is Node and is_instance_valid(node) and not root.is_brush_node(node):
			if not root.is_entity_node(node):
				nodes.append(node)
	if nodes.is_empty():
		root.user_message.emit("Convert to Brushes: select a MeshInstance3D or a CSG node", 1)
		return false
	var before: Dictionary = root.capture_state()
	var made: Dictionary = HFBrushConversion.convert_nodes(root, nodes)
	var converted: Array = made["converted"]
	var count := converted.size()
	var lead := "Converted %d node%s to brushes" % [count, "" if count == 1 else "s"]
	if count == 0:
		lead = "Convert to Brushes made no brushes"
	var report := {"custom": made["custom"], "refused": made["refused"]}
	var lossy: bool = (
		not (made["custom"] as Array).is_empty() or not (made["refused"] as Array).is_empty()
	)
	root.user_message.emit(root.transform_system.fold_report_text(report, lead), 1 if lossy else 0)
	if count == 0:
		return false
	var hidden: Array = []
	for node in converted:
		hidden.append([node, "visible", node.visible, false])
		node.visible = false
	HFUndoHelper.commit_completed(
		plugin._get_undo_redo(),
		root,
		"Convert to Brushes",
		before,
		Callable(plugin, "_record_history"),
		[],
		{},
		hidden
	)
	var selection = plugin.get_editor_interface().get_selection()
	plugin.hf_selection.clear()
	for brush in made["brushes"]:
		if is_instance_valid(brush):
			plugin.hf_selection.append(brush)
	plugin._apply_hf_selection(selection)
	return true


## Fold the selected brushes' rotation and scale into their shapes, leaving each
## where it stands with an identity basis (#1435). One undo step, scoped to the
## brushes, whose records carry the shape and size an undo builds back; none when
## no brush had a basis to fold. LevelRoot says what it did.
static func apply_rotation_scale_selected(plugin: Object, root: Node) -> bool:
	if not root:
		return false
	var brush_ids: Array = collect_managed_targets(plugin, root)["brush_ids"]
	if brush_ids.is_empty():
		return false
	HFUndoHelper.commit_if_changed(
		plugin._get_undo_redo(),
		root,
		"Apply Rotation and Scale",
		"apply_managed_rotation_scale",
		[brush_ids],
		Callable(plugin, "_record_history"),
		brush_ids
	)
	return true


# ---------------------------------------------------------------------------
# The viewport menu's level rows (#1724)
# ---------------------------------------------------------------------------


## Place Entity Here: `entity_class` on the surface under where the cursor was
## when the menu opened, standing on it as a drop from the palette does, as one
## undo step, and selected.
static func place_entity_here(
	plugin: Object, root: Node, entity_class: String, screen: Variant
) -> bool:
	var camera = plugin.get("last_3d_camera")
	if root == null or camera == null or not (screen is Vector2) or entity_class == "":
		return false
	var before: Dictionary = root.capture_state()
	var entity = root.place_entity_at_screen(camera, screen, entity_class)
	if entity == null:
		root.user_message.emit("Place Entity Here: point at a surface in the viewport", 1)
		return false
	HFUndoHelper.commit_completed(
		plugin._get_undo_redo(), root, "Place Entity", before, Callable(plugin, "_record_history")
	)
	var selection = plugin.get_editor_interface().get_selection()
	if selection:
		selection.clear()
		selection.add_node(entity)
	return true


## Make Brush Entity: tie the selected brushes to `entity_class`, as the Entity
## panel's Tie does, as one undo step.
static func make_brush_entity(plugin: Object, root: Node, entity_class: String) -> bool:
	var brush_ids := selection_brush_ids(plugin, root)
	if brush_ids.is_empty() or entity_class == "":
		return false
	HFUndoHelper.commit(
		plugin._get_undo_redo(),
		root,
		"Make Brush Entity",
		"tie_brushes_to_entity",
		[brush_ids, entity_class, ""],
		false,
		Callable(plugin, "_record_history")
	)
	return true


## Back to World: untie the selected brushes from their entity.
static func back_to_world(plugin: Object, root: Node) -> bool:
	var brush_ids := selection_brush_ids(plugin, root)
	if brush_ids.is_empty():
		return false
	HFUndoHelper.commit(
		plugin._get_undo_redo(),
		root,
		"Back to World",
		"untie_brushes_from_entity",
		[brush_ids],
		false,
		Callable(plugin, "_record_history")
	)
	return true


## Add the selected brushes and entities to the visgroup `vg_name`.
static func add_to_visgroup(plugin: Object, root: Node, vg_name: String) -> bool:
	var nodes := _managed_selection(plugin, root)
	if nodes.is_empty() or vg_name == "":
		return false
	HFUndoHelper.commit(
		plugin._get_undo_redo(),
		root,
		"Add to Visgroup",
		"add_selection_to_visgroup",
		[vg_name, nodes],
		false,
		Callable(plugin, "_record_history"),
		"",
		true
	)
	return true


## A new visgroup, named "Visgroup N", holding the selection, as one undo step.
## The dock's Visgroups list renames it.
static func new_visgroup(plugin: Object, root: Node) -> String:
	var nodes := _managed_selection(plugin, root)
	if nodes.is_empty():
		return ""
	var taken := Array(root.get_visgroup_names())
	var number := 1
	while taken.has("Visgroup %d" % number):
		number += 1
	var vg_name := "Visgroup %d" % number
	HFUndoHelper.commit(
		plugin._get_undo_redo(),
		root,
		"New Visgroup",
		"new_visgroup_with",
		[vg_name, nodes],
		false,
		Callable(plugin, "_record_history"),
		"",
		true
	)
	return vg_name


## Show the first picked face's material, selected, in the dock's browser.
static func show_material_in_browser(plugin: Object, root: Node) -> bool:
	var dock = plugin.get("dock")
	if dock == null or root == null:
		return false
	var index := first_face_material(root)
	if index < 0:
		return false
	dock.show_material_in_browser(index)
	return true


## The palette slot of the first face picked in Face Select, or -1.
static func first_face_material(root: Node) -> int:
	var faces = root.get("face_selection") if root else null
	if not (faces is Dictionary):
		return -1
	for key in faces:
		var brush = root.find_brush_by_id(str(key))
		var indices: Array = faces[key]
		if brush is DraftBrush and not indices.is_empty():
			var index := int(indices[0])
			if index >= 0 and index < brush.faces.size():
				return int(brush.faces[index].material_idx)
	return -1


## The selected nodes this plugin owns: brushes and entities.
static func _managed_selection(plugin: Object, root: Node) -> Array:
	var nodes: Array = []
	for node in plugin._current_selection_nodes():
		if node is DraftBrush or (root and root.is_entity_node(node)):
			nodes.append(node)
	return nodes
