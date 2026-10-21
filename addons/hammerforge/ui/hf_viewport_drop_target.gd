@tool
extends Control
## Where a drag over the 3D viewport reaches the plugin (#1417).
##
## Godot hands a drag over the 3D viewport to the Control the viewport draws
## through, which takes files and nothing else and offers the drag to no plugin:
## an EditorPlugin has no drop hook in 4.7. So the plugin's `_can_drop_data()` and
## `_drop_data()` were never called by the editor, and neither HammerForge's own
## drags nor a material from the FileSystem dock landed.
##
## This Control is a child of that one, under every other overlay, and lets the
## mouse through until a drag begins. It answers with the plugin's answer. What
## it refuses goes on to its parent, the viewport's own drop, so a scene dragged
## in still instances where Godot puts it.

## The plugin's `_can_drop_data(position, data)` and `_drop_data(position, data)`.
var can_drop := Callable()
var drop := Callable()

## True while this has a FileSystem drag that it takes.
var _taking_files := false


func _init() -> void:
	name = "HFViewportDropTarget"
	mouse_filter = MOUSE_FILTER_IGNORE
	focus_mode = FOCUS_NONE
	set_anchors_preset(PRESET_FULL_RECT)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_DRAG_BEGIN:
			# Pass, not Stop: pointer moves and anything refused still reach the
			# viewport under it.
			mouse_filter = MOUSE_FILTER_PASS
		NOTIFICATION_DRAG_END:
			mouse_filter = MOUSE_FILTER_IGNORE
			_taking_files = false


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	var taken := can_drop.is_valid() and bool(can_drop.call(at_position, data))
	var files := (
		taken and data is Dictionary and str((data as Dictionary).get("type", "")) == "files"
	)
	if files and not _taking_files:
		# The viewport lays a dragged material on the mesh under the cursor as a
		# preview, and only takes it off when its own drop is refused or the mouse
		# leaves it. A drop taken here is neither, so a mesh crossed on the way to
		# a brush would keep the preview. Leaving is what it is told.
		var viewport_control := get_parent_control()
		if viewport_control:
			viewport_control.mouse_exited.emit()
	_taking_files = files
	return taken


func _drop_data(at_position: Vector2, data: Variant) -> void:
	if drop.is_valid():
		drop.call(at_position, data)
