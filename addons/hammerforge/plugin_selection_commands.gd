@tool
class_name HFPluginSelectionCommands
extends RefCounted
## User-invoked bulk selection commands: Select All, Deselect All, Invert
## Selection, Select Similar, selecting with a throwaway brush, the selection
## filter popup, and Apply Last Texture.
##
## These are the commands a shortcut, the hotkey palette, or the context toolbar
## fires. Pointer arbitration lives in HFPluginSelectionInput and EditorSelection
## synchronization lives in HFPluginSelectionState.

const HFSelectionGrowType = preload("hf_selection_grow.gd")
const HFSelectByVolume = preload("hf_select_by_volume.gd")
const HFSimilarType = preload("hf_similar.gd")
const HFQuickSelectType = preload("hf_quick_select.gd")
# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFCommandRegistry = preload("hf_command_registry.gd")
const HFUndoHelper = preload("undo_helper.gd")
const DraftEntity = preload("draft_entity.gd")
@warning_ignore_restore("shadowed_global_identifier")
const HFTranslationType = preload("hf_translation.gd")

# ---------------------------------------------------------------------------
# Face selection
# ---------------------------------------------------------------------------


static func face_key_for(brush: DraftBrush) -> String:
	return HFBrushSystem.face_key(brush)


static func apply_face_selection(plugin: Object, root: Node, face_sel: Dictionary) -> void:
	# Similar, grow and the filters walk every brush; a locked one's faces stay out.
	var system = root.get("visgroup_system")
	if system and root.has_method("find_brush_by_id"):
		for key in face_sel.keys():
			var brush = root.find_brush_by_id(str(key))
			if brush and system.is_locked(brush):
				face_sel.erase(key)
	root.face_selection = face_sel
	root.face_selection_changed.emit()
	plugin._update_hud_context()


# ---------------------------------------------------------------------------
# Apply Last Texture
# ---------------------------------------------------------------------------


static func apply_last_texture(plugin: Object, root: Node) -> void:
	if plugin._last_picked_material_index < 0:
		if plugin.dock:
			plugin.dock.show_toast("No texture picked yet — use T to pick first", 1)
		return
	if not plugin.dock:
		return
	plugin.dock._selected_material_index = plugin._last_picked_material_index
	var face_count = plugin.dock._count_selected_faces()
	if face_count > 0:
		plugin.dock._on_face_assign_material()
		plugin.dock.show_toast(
			"Applied last texture to %d face%s" % [face_count, "" if face_count == 1 else "s"], 0
		)
		return
	var applied_count := 0
	var mat = (
		root.material_manager.get_material(plugin._last_picked_material_index)
		if root.material_manager
		else null
	)
	if mat:
		var brushes: Array = []
		for node in plugin.hf_selection:
			if node is DraftBrush:
				brushes.append(node)
		# One step for the selection. Each brush used to commit its own, so three
		# brushes took three Ctrl+Z to take back (#1565).
		applied_count = plugin._paint_brushes_with_undo(root, brushes, mat)
	if applied_count > 0:
		plugin.dock.show_toast(
			(
				"Applied last texture to %d brush%s"
				% [applied_count, "" if applied_count == 1 else "es"]
			),
			0
		)
	else:
		plugin.dock.show_toast("No brushes or faces selected", 1)


# ---------------------------------------------------------------------------
# Select All / Deselect All
# ---------------------------------------------------------------------------


## Select every brush and entity in view. What is hidden stays out, as Invert
## Selection leaves it out, so Select All then Delete deletes only what the
## mapper can see, and the toast says how many hidden ones it left (#1974).
static func select_all(plugin: Object, root: Node) -> void:
	if not root:
		return
	var selection = plugin.get_editor_interface().get_selection()
	if not selection:
		return
	# Clear face selection first so context toolbar switches to object context
	if root.has_method("clear_face_selection"):
		root.clear_face_selection()
	var hidden := 0
	plugin.hf_selection.clear()
	for node in root._iter_pick_nodes():
		if not is_instance_valid(node):
			continue
		if node is Node3D and not (node as Node3D).is_visible_in_tree():
			hidden += 1
		else:
			plugin.hf_selection.append(node)
	plugin._apply_hf_selection(selection)
	plugin._update_hud_context()
	if plugin.dock:
		var count: int = plugin.hf_selection.size()
		plugin.dock.set_selection_count(count)
		plugin.dock.set_selection_nodes(plugin.hf_selection)
		var said := HFTranslationType.tn(
			"Selected {count} object", "Selected {count} objects", count
		)
		said = said.format({"count": count})
		if hidden > 0:
			var left := HFTranslationType.tn(
				"left out {count} hidden", "left out {count} hidden", hidden
			)
			said += ", " + left.format({"count": hidden})
		plugin.dock.show_toast(said, 0)


## Select every visible brush and entity that is not selected, and none of what
## is (#1717). What a visgroup hides stays out, so hiding the rest and then
## inverting does what a mapper expects.
static func invert_selection(plugin: Object, root: Node) -> void:
	if not root:
		return
	var selected: Array = plugin._current_selection_nodes()
	var out: Array = []
	for node in root._iter_pick_nodes():
		if not is_instance_valid(node) or not (node is Node3D) or selected.has(node):
			continue
		if (node as Node3D).is_visible_in_tree():
			out.append(node)
	select_nodes(plugin, root, out, "Inverted the selection: %d selected" % out.size())


## The commands that select with a throwaway brush, and how each picks.
const WITH_BRUSH := {
	"select_inside": "inside",
	"select_partly_inside": "partly",
	"select_touching": "touching",
	"select_column": "column",
}


## Select what the one selected brush picks, then delete that brush as one undo
## step, so the level is as it was and only the selection changes (#1717).
static func select_with_brush(plugin: Object, root: Node, action: String) -> void:
	if not root or not WITH_BRUSH.has(action):
		return
	var nodes: Array = plugin._current_selection_nodes()
	var label: String = HFCommandRegistry.label(action)
	var dock = plugin.get("dock")
	if nodes.size() != 1 or not root.is_brush_node(nodes[0]):
		if dock:
			dock.show_toast("%s: select the one brush to select with" % label, 1)
		return
	var volume: Node3D = nodes[0]
	var picked := HFSelectByVolume.pick(root, volume, WITH_BRUSH[action])
	var brush_id: String = root.brush_system.ensure_brush_id(volume)
	HFUndoHelper.commit(
		plugin._get_undo_redo(),
		root,
		label,
		"delete_brushes_by_id",
		[[brush_id]],
		false,
		Callable(plugin, "_record_history")
	)
	select_nodes(plugin, root, picked, "%s: %d selected" % [label, picked.size()])


## Make `nodes` the selection, as Select All does, and say so. Select Linked
## Copies uses it too.
static func select_nodes(plugin: Object, root: Node, nodes: Array, message: String) -> void:
	var selection = plugin.get_editor_interface().get_selection()
	if not selection:
		return
	if root.has_method("clear_face_selection"):
		root.clear_face_selection()
	plugin.hf_selection.clear()
	for node in nodes:
		if is_instance_valid(node):
			plugin.hf_selection.append(node)
	plugin._apply_hf_selection(selection)
	plugin._update_hud_context()
	if plugin.dock:
		plugin.dock.set_selection_count(plugin.hf_selection.size())
		plugin.dock.set_selection_nodes(plugin.hf_selection)
		plugin.dock.show_toast(message, 0)


static func deselect_all(plugin: Object, root: Node) -> void:
	if not root:
		return
	var selection = plugin.get_editor_interface().get_selection()
	if not selection:
		return
	if plugin.dock:
		plugin.dock.emit_signal("selection_clear_requested")
	plugin.hf_selection.clear()
	selection.clear()
	# Also clear face selection
	if root.has_method("clear_face_selection"):
		root.clear_face_selection()
	elif root.get("face_selection") is Dictionary:
		root.face_selection.clear()
	plugin._update_hud_context()
	if plugin.dock:
		plugin.dock.set_selection_count(0)
		plugin.dock.set_selection_nodes([])


# ---------------------------------------------------------------------------
# Select Similar
# ---------------------------------------------------------------------------


static func select_similar(plugin: Object, root: Node) -> void:
	if not root:
		return
	# If faces are selected, find similar faces across all brushes
	var face_count := 0
	for key in root.face_selection.keys():
		face_count += root.face_selection.get(key, []).size()
	if face_count > 0:
		select_similar_faces(plugin, root)
		return
	# Otherwise the brushes and entities like the selected ones.
	for node in plugin.hf_selection:
		if is_instance_valid(node) and (node is DraftBrush or node is DraftEntity):
			select_similar_nodes(plugin, root)
			return
	if plugin.dock:
		plugin.dock.show_toast("Select a face, brush or entity first", 1)


static func select_similar_faces(plugin: Object, root: Node) -> void:
	var keys := HFSimilarType.keys_for(plugin.get("_user_prefs"), "face")
	if keys.is_empty():
		_ask_for_keys(plugin, "faces")
		return
	var face_sel := similar_face_selection(root, keys)
	if face_sel.is_empty():
		if plugin.dock:
			plugin.dock.show_toast(
				"No visible face matches the selected one on %s" % HFSimilarType.describe(keys), 1
			)
		return
	var total := 0
	for key in face_sel:
		total += (face_sel[key] as Array).size()
	apply_face_selection(plugin, root, face_sel)
	if plugin.dock:
		plugin.dock.show_toast("Selected %d similar face%s" % [total, "" if total == 1 else "s"], 0)


## The faces Similar Faces selects for the faces selected now, keyed the way
## `face_selection` is: every face on a visible brush that agrees with one of
## them on `keys`, material and normal unless told otherwise (#1698). Empty when
## no selected face can be found.
##
## The command and the Selection Filters popover both ask this, so the two ways
## in cannot select different faces for the same reference (#896). The command
## had its own copy, which reached into hidden brushes, so a texture applied to
## what it selected landed on faces nobody could see.
static func similar_face_selection(root: Node, keys: Variant = null) -> Dictionary:
	return HFSimilarType.faces(root, keys if keys is Array else HFSimilarType.DEFAULTS["face"])


## Select the brushes like the selected brushes and the entities like the
## selected entities, on the keys the user prefs keep for each (#1698).
static func select_similar_nodes(plugin: Object, root: Node) -> void:
	var prefs = plugin.get("_user_prefs")
	var seeds: Array = plugin.hf_selection
	var kinds: Array = []
	for node in seeds:
		if not is_instance_valid(node):
			continue
		if node is DraftBrush and not kinds.has("brush"):
			kinds.append("brush")
		elif node is DraftEntity and not kinds.has("entity"):
			kinds.append("entity")
	var picked: Array = []
	var asked: Array = []
	for kind in kinds:
		var keys := HFSimilarType.keys_for(prefs, kind)
		if keys.is_empty():
			_ask_for_keys(plugin, "brushes" if kind == "brush" else "entities")
			return
		for key in keys:
			if not asked.has(key):
				asked.append(key)
		if kind == "brush":
			picked.append_array(similar_brushes(root, seeds, keys))
		else:
			picked.append_array(
				HFSimilarType.entities(root, seeds, keys, HFSimilarType.property_for(prefs))
			)
	var noun := _similar_noun(kinds, 2)
	if picked.is_empty():
		if plugin.dock:
			plugin.dock.show_toast(
				"No visible %s match on %s" % [noun, HFSimilarType.describe(asked)], 1
			)
		return
	plugin._apply_selection_list(picked, false)
	if plugin.dock:
		plugin.dock.show_toast(
			"Selected %d similar %s" % [picked.size(), _similar_noun(kinds, picked.size())], 0
		)


static func _similar_noun(kinds: Array, count: int) -> String:
	if kinds.size() > 1:
		return "object" if count == 1 else "objects"
	if kinds.has("entity"):
		return "entity" if count == 1 else "entities"
	return "brush" if count == 1 else "brushes"


static func _ask_for_keys(plugin: Object, what: String) -> void:
	if plugin.dock:
		plugin.dock.show_toast("Tick what similar %s match on in Selection Filters" % what, 1)


## The brushes Similar Brushes selects for `selection`: every visible brush that
## agrees with one of its brushes on `keys`, size unless told otherwise (#1698).
## Empty when `selection` holds no brush.
##
## The command and the Selection Filters popover both ask this, for the reason
## `similar_face_selection()` gives. The command's own copy reached into hidden
## brushes too (#897).
static func similar_brushes(root: Node, selection: Array, keys: Variant = null) -> Array:
	return HFSimilarType.brushes(
		root, selection, keys if keys is Array else HFSimilarType.DEFAULTS["brush"]
	)


# ---------------------------------------------------------------------------
# Grow / Shrink Selection
# ---------------------------------------------------------------------------


static func grow_selection(plugin: Object, root: Node) -> void:
	_grow_or_shrink(plugin, root, true)


static func shrink_selection(plugin: Object, root: Node) -> void:
	_grow_or_shrink(plugin, root, false)


## Same plane only and Max angle, as the Selection Filters row holds them. The
## keys read the row too, so a setting made there holds for Ctrl+] as well.
static func grow_options(plugin: Object) -> Dictionary:
	var popup = plugin.get("_selection_filter")
	if popup != null and is_instance_valid(popup) and popup.has_method("grow_options"):
		return popup.grow_options()
	return {"same_plane": false, "max_angle": HFSelectionGrowType.DEFAULT_MAX_ANGLE}


static func _grow_or_shrink(plugin: Object, root: Node, grow: bool) -> void:
	if not root:
		return
	var options := grow_options(plugin)
	var result := grown_selection(
		root,
		plugin._current_selection_nodes(),
		grow,
		bool(options.get("same_plane", false)),
		float(options.get("max_angle", HFSelectionGrowType.DEFAULT_MAX_ANGLE))
	)
	if result.has("message"):
		if plugin.dock:
			plugin.dock.show_toast(str(result["message"]), 1)
		return
	var count := int(result.get("count", 0))
	var what := "face" if result.has("faces") else "brush"
	if result.has("faces"):
		apply_face_selection(plugin, root, result["faces"])
	else:
		plugin._apply_selection_list(result["nodes"], false)
	if plugin.dock:
		var plural := "" if count == 1 else ("es" if what == "brush" else "s")
		plugin.dock.show_toast(
			"%s %d %s%s" % ["Grow added" if grow else "Shrink dropped", count, what, plural], 0
		)


## What Grow (or Shrink, with `grow` false) makes of the selection: `faces`, the
## whole new face selection, or `nodes`, the whole new object selection, with
## `count` the faces or brushes added or dropped; or `message`, saying why it
## changes nothing. A face selection is grown when there is one, as Select
## Similar does, and the brushes in `nodes` otherwise.
##
## The command and the Selection Filters row both ask this, so the two ways in
## cannot reach different faces. A Shrink that would drop everything is refused
## rather than done: selecting is no undo step, so an empty selection could not
## be got back, and Grow cannot grow from nothing.
static func grown_selection(
	root: Node, nodes: Array, grow: bool, same_plane: bool, max_angle: float
) -> Dictionary:
	var faces = root.get("face_selection")
	if faces is Dictionary and HFSelectionGrowType.face_count(faces) > 0:
		return _grown_faces(root, faces, grow, same_plane, max_angle)
	var has_brush := false
	for node in nodes:
		if is_instance_valid(node) and node is DraftBrush and root.is_brush_node(node):
			has_brush = true
			break
	if not has_brush:
		return {"message": "Select a face or brush first"}
	var walk := HFSelectionGrowType.walk_brushes(root, nodes)
	if grow:
		var added: Array = walk["added"]
		if added.is_empty():
			return {"message": "No visible brush touches the selection"}
		return {"nodes": nodes + added, "count": added.size()}
	var border: Array = walk["border"]
	if border.is_empty():
		return {"message": "No selected brush touches one that is not selected"}
	var kept: Array = []
	for node in nodes:
		if not border.has(node):
			kept.append(node)
	if kept.is_empty():
		return {"message": "Shrink would leave nothing selected"}
	return {"nodes": kept, "count": border.size()}


static func _grown_faces(
	root: Node, faces: Dictionary, grow: bool, same_plane: bool, max_angle: float
) -> Dictionary:
	var walk := HFSelectionGrowType.walk_faces(root, faces, same_plane, max_angle)
	if grow:
		var added: Dictionary = walk["added"]
		if added.is_empty():
			var limited := same_plane or max_angle < HFSelectionGrowType.DEFAULT_MAX_ANGLE
			return {
				"message":
				(
					"No visible face next to the selection passes Same plane only or Max angle"
					if limited
					else "No visible face shares an edge with the selection"
				)
			}
		return {
			"faces": HFSelectionGrowType.with_faces(faces, added),
			"count": HFSelectionGrowType.face_count(added),
		}
	var border: Dictionary = walk["border"]
	if border.is_empty():
		return {"message": "No selected face is on the edge of the selection"}
	var kept := HFSelectionGrowType.without_faces(faces, border)
	if kept.is_empty():
		return {"message": "Shrink would leave nothing selected"}
	return {
		"faces": kept,
		"count": HFSelectionGrowType.face_count(faces) - HFSelectionGrowType.face_count(kept)
	}


# ---------------------------------------------------------------------------
# Face X-ray
# ---------------------------------------------------------------------------


## Flip the X-ray checkbox beside Face Select Mode. Its own signal brings the
## HUD line and the marquee colour along, as a click on it does.
static func toggle_face_xray(plugin: Object) -> void:
	var dock = plugin.dock
	if not dock or not dock.face_select_xray:
		return
	dock.face_select_xray.button_pressed = not dock.face_select_xray.button_pressed
	dock.show_toast(
		(
			"Face X-ray on: the face box takes covered and back faces"
			if dock.face_select_xray.button_pressed
			else "Face X-ray off"
		),
		0
	)


# ---------------------------------------------------------------------------
# Selection Filter popup
# ---------------------------------------------------------------------------


static func show_selection_filter(plugin: Object) -> void:
	if not plugin._selection_filter:
		return
	var root = plugin.active_root if plugin.active_root else plugin._get_level_root()
	plugin._selection_filter.set_user_prefs(plugin.get("_user_prefs"))
	plugin._selection_filter.show_for(root, plugin.hf_selection)
	# Position near the mouse
	var popup_pos := Vector2i(int(plugin.last_3d_mouse_pos.x), int(plugin.last_3d_mouse_pos.y))
	plugin._selection_filter.popup(Rect2i(popup_pos, Vector2i.ZERO))


## Keep only the selected nodes of `kind`, one of `HFQuickSelect.KINDS`, as a
## click on Selection Info's kinds asks (#1698).
static func narrow_selection(plugin: Object, root: Node, kind: String) -> void:
	var kept := HFQuickSelectType.of_kind(root, plugin.hf_selection, kind)
	if kept.is_empty():
		return
	plugin._apply_selection_list(kept, false)
	if plugin.dock:
		var label := str(HFQuickSelectType.KIND_LABELS.get(kind, kind)).to_lower()
		plugin.dock.show_toast("Kept the %d %s" % [kept.size(), label], 0)


## Selection Filters with the typed rule ready to type in (#1698).
static func show_quick_select(plugin: Object) -> void:
	show_selection_filter(plugin)
	if plugin._selection_filter:
		plugin._selection_filter.focus_quick_rule()


static func on_filter_applied(plugin: Object, nodes: Array, faces: Dictionary) -> void:
	var root = plugin.active_root if plugin.active_root else plugin._get_level_root()
	if not root:
		return
	# Apply face selection if provided
	if not faces.is_empty():
		apply_face_selection(plugin, root, faces)
		var total := 0
		for key in faces.keys():
			total += faces[key].size()
		if plugin.dock:
			plugin.dock.show_toast("Selected %d face%s" % [total, "" if total == 1 else "s"], 0)
	elif not nodes.is_empty():
		# Node-only filter — clear any stale face selection first
		apply_face_selection(plugin, root, {})
		plugin._apply_selection_list(nodes, false)
		if plugin.dock:
			plugin.dock.show_toast(
				"Selected %d node%s" % [nodes.size(), "" if nodes.size() == 1 else "s"], 0
			)
	else:
		# Quick Select's Take Away took the last of the selection (#1698).
		deselect_all(plugin, root)
		if plugin.dock:
			plugin.dock.show_toast("Nothing is left selected", 0)
