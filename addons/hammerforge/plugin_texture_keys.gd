@tool
extends RefCounted
## The nudge keys slide and turn the texture on the selected faces in Face Select
## (#1728).
##
## Face Select puts the object selection aside, so the arrows had nothing to move
## there, and lining a texture up by eye meant typing offsets. An arrow slides
## each selected face's texture one grid step the way it points on screen, worked
## out from the face's own texture axes, and Alt makes it a tenth. Shift with Left
## or Right turns it 15 degrees about the middle of each face, Alt makes that 1,
## and Shift with Up or Down turns it a quarter. A quick run of presses is one
## undo step.

# Preloaded under its global name so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFUndoHelper = preload("undo_helper.gd")
const HFNumberFormat = preload("hf_number_format.gd")
@warning_ignore_restore("shadowed_global_identifier")
const HFUVMultiType = preload("hf_uv_multi.gd")

const SCREEN := {
	KEY_LEFT: Vector2(-1, 0),
	KEY_RIGHT: Vector2(1, 0),
	KEY_UP: Vector2(0, 1),
	KEY_DOWN: Vector2(0, -1),
}


## Whether the arrows move textures now: Face Select on, faces selected, and
## neither paint nor vertex mode.
static func active(plugin: Object, root: Node) -> bool:
	var dock = plugin.get("dock")
	if dock == null or root == null or not dock.is_face_select_mode_enabled():
		return false
	if plugin.get("_vertex_mode") or dock.is_paint_mode_enabled():
		return false
	return root.picked_face_count() > 0


## How far a slide goes in metres: the grid step, or a tenth of it.
static func slide_step(root: Node, fine: bool) -> float:
	var step: float = root.grid_snap if float(root.grid_snap) > 0.0 else 1.0
	return step * (HFUVMultiType.FINE_SLIDE if fine else 1.0)


## Slide or turn the selected faces' textures for an arrow press. True when the
## press was theirs.
static func handle(plugin: Object, root: Node, event: InputEventKey) -> bool:
	if not SCREEN.has(event.keycode) or not active(plugin, root):
		return false
	var records := HFUVMultiType.picked(root)
	var result: Dictionary
	var action_name := ""
	var told := ""
	if event.shift_pressed:
		var degrees := turn_degrees(event.keycode, event.alt_pressed)
		result = HFUVMultiType.turn_changes(records, degrees)
		action_name = "Turn Texture"
		told = "Texture %s°" % HFNumberFormat.number(degrees, 1.0)
	else:
		var camera: Camera3D = plugin.get("last_3d_camera")
		if camera == null:
			return false
		var step := slide_step(root, event.alt_pressed)
		result = HFUVMultiType.slide_changes(
			records, camera.global_basis.x, camera.global_basis.y, SCREEN[event.keycode], step
		)
		action_name = "Slide Texture"
		told = "Texture %s m" % HFNumberFormat.number(step, root.grid_snap)
	var changes: Array = result["changes"]
	var dock = plugin.get("dock")
	if changes.is_empty():
		if dock:
			dock.show_toast(
				"The selected faces are edge on or Cylindrical; use the UV boxes for them", 1
			)
		return true
	var keys := PackedStringArray()
	for change in changes:
		keys.append("%s:%d" % [change[0], change[1]])
	HFUndoHelper.commit(
		plugin._get_undo_redo(),
		root,
		action_name,
		"set_uv_params_on_faces",
		[changes],
		false,
		Callable(plugin, "_record_history"),
		"texture_keys_%s" % ",".join(keys),
		true,
		HFUVMultiType.brush_ids_of(changes)
	)
	if int(result["skipped"]) > 0:
		told += ", %d left as they were" % int(result["skipped"])
	plugin.read_out_move(told)
	if dock and dock.has_method("_refresh_uv_face"):
		dock._refresh_uv_face()
	return true


## The turn a Shift press makes, in degrees: Left 15 and Right -15, or 1 either
## way with Alt, and Up or Down a quarter turn.
static func turn_degrees(keycode: int, fine: bool) -> float:
	match keycode:
		KEY_UP:
			return HFUVMultiType.QUARTER_TURN
		KEY_DOWN:
			return -HFUVMultiType.QUARTER_TURN
	var step := HFUVMultiType.FINE_TURN_STEP if fine else HFUVMultiType.TURN_STEP
	return step if keycode == KEY_LEFT else -step


## The HUD's lines for the keys while they move textures, with their steps.
static func hud_lines(root: Node) -> PackedStringArray:
	var step := slide_step(root, false)
	var fine := slide_step(root, true)
	return PackedStringArray(
		[
			(
				"Arrows: Slide texture %s m | Alt: %s m"
				% [HFNumberFormat.number(step, root.grid_snap), HFNumberFormat.number(fine, 0.0)]
			),
			(
				"Shift+Left/Right: Turn texture %d° | Alt: %d° | Shift+Up/Down: %d°"
				% [
					int(HFUVMultiType.TURN_STEP),
					int(HFUVMultiType.FINE_TURN_STEP),
					int(HFUVMultiType.QUARTER_TURN)
				]
			),
		]
	)
