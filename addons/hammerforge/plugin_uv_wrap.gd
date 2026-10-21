@tool
class_name HFPluginUVWrap
extends RefCounted
## Wrap mode (#1428), started by the Wrap button in Paint > UV Editor or from the
## command palette. The selected face is where the texture comes from. Each click
## on a face beside it carries that texture over the edge the two share, as one
## undo step, and the clicked face becomes the one the next click carries from, so
## a run of clicks walks round a pillar or along a corridor. Escape or a right
## click ends it. It works as the Texture Picker's one-shot mode does, held until
## it is ended rather than for one click.
##
## The face is kept on the plugin as `_wrap_source`, a brush id and a face index,
## so an undo that rebuilds its brush still finds it. It is read and written with
## `get()` and `set()`, so a plugin stand-in without it reads as no Wrap.

const STOP := EditorPlugin.AFTER_GUI_INPUT_STOP
const PASS := EditorPlugin.AFTER_GUI_INPUT_PASS
# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const DraftBrush = preload("brush_instance.gd")
const HFUVWrap = preload("hf_uv_wrap.gd")
const HFUndoHelper = preload("undo_helper.gd")
@warning_ignore_restore("shadowed_global_identifier")

## What a toast calls the axis whose scale a wrap changed.
const ADJUSTED_AXES := ["U", "V", "U and V"]


static func is_active(plugin: Object) -> bool:
	var source = plugin.get("_wrap_source")
	return source is Dictionary and not (source as Dictionary).is_empty()


## Start Wrap from the selected face, or say why it cannot start.
static func begin(plugin: Object, root: Node) -> void:
	if root == null:
		_toast(plugin, "Wrap: open a level first", 1)
		return
	var picked: Dictionary = root.get_primary_selected_face()
	var brush = picked.get("brush", null)
	var face_idx := int(picked.get("face_idx", -1))
	if not (brush is DraftBrush) or face_idx < 0 or face_idx >= (brush as DraftBrush).faces.size():
		_toast(plugin, "Wrap: select the face whose texture to carry on first", 1)
		return
	var brush_id := _brush_id(root, brush)
	if brush_id == "":
		_toast(plugin, "Wrap: the selected face's brush has no id to keep", 1)
		return
	# One click mode at a time: a click is the Wrap's from here.
	plugin.set("_texture_picker_active", false)
	plugin.set("_wrap_source", {"brush_id": brush_id, "face_idx": face_idx})
	_toast(
		plugin,
		"Wrap: click a face beside the selected one to carry its texture over. Esc or right click ends",
		0
	)


## End Wrap. True when it was on, which is what the Escape ladder asks.
static func end(plugin: Object, notify: bool) -> bool:
	if not is_active(plugin):
		return false
	plugin.set("_wrap_source", {})
	if notify:
		_toast(plugin, "Wrap ended", 1)
	return true


## A viewport event while Wrap is on. A left click wraps onto the face under the
## cursor, and its release is Wrap's too; a right click or Escape ends it. Anything
## else goes on, so the editor's own keys, Ctrl+Z among them, still work.
static func handle_input(plugin: Object, root: Node, event: InputEvent) -> int:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				wrap_onto_face_under_cursor(plugin, root)
			return STOP
		if button.button_index == MOUSE_BUTTON_RIGHT and button.pressed:
			end(plugin, true)
			return STOP
		return PASS
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
			end(plugin, true)
			return STOP
	return PASS


## Carry the texture onto the face under the cursor, as one undo step, and make
## that face the one the next click carries from. A refusal says why and changes
## nothing, and Wrap stays on for another click.
static func wrap_onto_face_under_cursor(plugin: Object, root: Node) -> void:
	var camera: Camera3D = plugin.get("last_3d_camera")
	if root == null or camera == null:
		return
	var hit: Dictionary = root.pick_face(camera, plugin.get("last_3d_mouse_pos"))
	var target = hit.get("brush", null)
	var target_idx := int(hit.get("face_idx", -1))
	if not (target is DraftBrush) or target_idx < 0:
		_toast(plugin, "Wrap: no face under the cursor", 1)
		return
	var source: Dictionary = plugin.get("_wrap_source")
	var source_id := str(source.get("brush_id", ""))
	var source_idx := int(source.get("face_idx", -1))
	var source_brush = root.find_brush_by_id(source_id)
	if not (source_brush is DraftBrush) or source_idx >= (source_brush as DraftBrush).faces.size():
		end(plugin, false)
		_toast(plugin, "Wrap ended: the face the texture came from is gone", 1)
		return
	var target_id := _brush_id(root, target)
	var before := HFUndoHelper.capture_scope_or_state(root, [target_id])
	var result: Dictionary = root.wrap_face_texture(source_id, source_idx, target_id, target_idx)
	if not bool(result.get("ok", false)):
		var reason := str(result.get("reason", ""))
		_toast(plugin, "Wrap: %s" % str(HFUVWrap.REFUSALS.get(reason, reason)), 1)
		return
	HFUndoHelper.commit_completed_if_changed(
		plugin.call("_get_undo_redo"),
		root,
		"Wrap Texture",
		before["state"],
		Callable(plugin, "_record_history"),
		before["scope_ids"]
	)
	plugin.set("_wrap_source", {"brush_id": target_id, "face_idx": target_idx})
	# Selected, so the UV Editor shows the face the next click carries from.
	root.toggle_face_selection(target, target_idx, false)
	var adjusted := int(result.get("adjusted", -1))
	if adjusted >= 0 and adjusted < ADJUSTED_AXES.size():
		_toast(
			plugin,
			(
				"Wrapped, with the %s scale changed to meet the edge: this face measures it differently"
				% ADJUSTED_AXES[adjusted]
			),
			1
		)
	else:
		_toast(plugin, "Wrapped. Click the next face, or Esc to end", 0)


static func _brush_id(root: Node, brush: DraftBrush) -> String:
	if brush.brush_id == "":
		root.get_brush_info_from_node(brush)
	return str(brush.brush_id)


static func _toast(plugin: Object, message: String, level: int) -> void:
	var dock = plugin.get("dock")
	if dock:
		dock.show_toast(message, level)
