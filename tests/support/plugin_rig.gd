extends RefCounted
## The real plugin over an edited scene a test owns, for a test that checks what
## the plugin does with a key, a palette pick or a selection, rather than how its
## source reads (#1266).
##
## The plugin is built by `plugin_stand_in.gd` inside a SubViewport of its own,
## so a key pushed into `viewport` reaches the plugin's `_shortcut_input` the way
## the editor delivers it, and `viewport.is_input_handled()` afterwards says
## whether the plugin consumed it. One rig serves a whole script: bring it up in
## `before_all`, take it down in `after_all`, and have each test make its own
## level with `make_level()` and leave it with `leave_level()`.

const PluginStandIn = preload("res://tests/support/plugin_stand_in.gd")
const LevelRootScript = preload("res://addons/hammerforge/level_root.gd")
const HFKeymapScript = preload("res://addons/hammerforge/hf_keymap.gd")

var plugin: Node = null
var viewport: SubViewport = null
## The scene open in the editor. It starts empty, as a new 3D scene does.
var scene_root: Node3D = null
## A camera beside the edited scene, not in it, looking at the origin from
## above and in front.
var camera: Camera3D = null


## Build under `test`. With `with_undo` the plugin commits through the undo
## manager stand-in, `undo()`; without, every action commits directly. `plugin`
## stays null if the stand-in could not be built; `error()` says why.
func bring_up(test: Node, with_undo := false) -> void:
	viewport = SubViewport.new()
	viewport.name = "RigViewport"
	viewport.size = Vector2i(800, 600)
	test.add_child(viewport)
	camera = Camera3D.new()
	camera.name = "RigCamera"
	viewport.add_child(camera)
	camera.look_at_from_position(Vector3(0, 12, 16), Vector3.ZERO)
	camera.current = true
	scene_root = Node3D.new()
	scene_root.name = "EditedScene"
	viewport.add_child(scene_root)
	plugin = PluginStandIn.build(viewport, scene_root, with_undo)
	await test.get_tree().process_frame


## The undo manager stand-in, or null when the rig was brought up without one.
## Its `press_undo()` and `press_redo()` are the editor's Ctrl+Z and Ctrl+Shift+Z.
func undo() -> Object:
	return plugin.stand_in_undo if plugin else null


func error() -> String:
	return PluginStandIn.error()


## Teardown as the sweep does it: `_exit_tree`, then two frames so what it queued
## is freed before GUT counts orphans.
func take_down() -> void:
	var tree := viewport.get_tree() if viewport and viewport.is_inside_tree() else null
	PluginStandIn.teardown(plugin)
	plugin = null
	if viewport and is_instance_valid(viewport):
		if viewport.get_parent():
			viewport.get_parent().remove_child(viewport)
		viewport.free()
	viewport = null
	scene_root = null
	camera = null
	if tree:
		await tree.process_frame
		await tree.process_frame


func frame() -> void:
	await plugin.get_tree().process_frame


## A level in the edited scene, adopted by the plugin the way the editor adopts
## one, by selecting it, and by the dock on its next frame. Nothing is left
## selected.
func make_level() -> Node:
	var root = LevelRootScript.new()
	root.name = "LevelRoot"
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	scene_root.add_child(root)
	root.owner = scene_root
	select([root])
	select([])
	# The dock finds its level through the tree's edited scene root, which only
	# the editor sets, so it is pointed at this one the way it would find it.
	if plugin.dock:
		plugin.dock.level_root = root
	# Two frames: an await resumes as a frame begins, before that frame's
	# `_process` calls, so the dock has seen the level by the second.
	await frame()
	await frame()
	return root


## Close the level the way a scene tab closes: out of the selection, out of the
## scene, freed, with the frame's deferred work done first.
func leave_level(root: Node) -> void:
	await frame()
	# The steps name the level about to go, as a closed scene's history goes.
	if undo():
		undo().clear()
	for dialog in open_dialogs():
		if dialog is ConfirmationDialog:
			dialog.get_cancel_button().pressed.emit()
		else:
			dialog.hide()
	escape_to_idle(root)
	select([])
	clear_toasts()
	if root != null and is_instance_valid(root):
		if root.get_parent():
			root.get_parent().remove_child(root)
		root.free()
	for child in scene_root.get_children():
		scene_root.remove_child(child)
		child.free()
	await frame()


func box(root: Node, id: String, center: Vector3, size := Vector3(4, 4, 4)) -> Node:
	return root.create_brush_from_info({"size": size, "center": center, "brush_id": id})


## A plain Godot node in the edited scene, which the plugin does not own.
func native_node(node_name := "Lamp") -> Node3D:
	var node := Node3D.new()
	node.name = node_name
	scene_root.add_child(node)
	node.owner = scene_root
	return node


## Select through the editor's selection, as a click in the Scene tree does.
## A node no longer in the scene is left out, as the editor cannot select one.
func select(nodes: Array) -> void:
	var selection = plugin.stand_in_editor.selection
	selection.clear()
	for node in nodes:
		if is_instance_valid(node) and node.is_inside_tree():
			selection.add_node(node)


func level_roots() -> int:
	var count := 0
	for child in scene_root.get_children():
		if child.get_script() == LevelRootScript:
			count += 1
	return count


## The dock's toasts on screen, oldest first.
func toasts() -> Array:
	var out: Array = []
	var container: Node = plugin.dock._toast_container if plugin.dock else null
	if container == null:
		return out
	for panel in container.get_children():
		for child in panel.get_children():
			if child is Label:
				out.append(child.text)
	return out


func clear_toasts() -> void:
	var container: Node = plugin.dock._toast_container if plugin.dock else null
	if container == null:
		return
	for panel in container.get_children():
		container.remove_child(panel)
		panel.free()


## The confirmation dialogs on screen.
func open_dialogs() -> Array:
	var out: Array = []
	var host: Node = plugin.stand_in_editor.base_control
	for node in host.find_children("*", "AcceptDialog", true, false):
		if node.visible:
			out.append(node)
	return out


## Press OK on every dialog on screen, as a user who says yes, and let the frame
## free them. Returns how many.
func accept_dialogs() -> int:
	var dialogs := open_dialogs()
	for dialog in dialogs:
		dialog.get_ok_button().pressed.emit()
	if not dialogs.is_empty():
		await frame()
	return dialogs.size()


## Escape until nothing is left to cancel, the way a user clears the decks.
func escape_to_idle(root: Node) -> void:
	var live_root: Node = root if is_instance_valid(root) else null
	for _i in 12:
		if not plugin._cancel_escape_step(live_root):
			return


## Deliver a key the way the editor delivers a shortcut. True when the plugin
## consumed it, so Godot would not act on it as well.
func press_shortcut(event: InputEventKey) -> bool:
	viewport.push_input(event)
	return viewport.is_input_handled()


## Deliver an event to the 3D viewport's input hook, as the editor does for
## every event over the 3D view. Returns the plugin's answer.
func forward(event: InputEvent) -> int:
	return plugin._forward_3d_gui_input(camera, event)


## A mouse button event over the viewport, holding the button while pressed.
static func click(
	button: int, pressed: bool, position := Vector2(400, 300), canceled := false
) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.canceled = canceled
	event.position = position
	if pressed:
		event.button_mask = 1 << (button - 1)
	return event


static func motion(position: Vector2, button_mask := 0) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.button_mask = button_mask
	return event


static func key(keycode: int, ctrl := false, shift := false, alt := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	event.ctrl_pressed = ctrl
	event.shift_pressed = shift
	event.alt_pressed = alt
	return event


## The key bound to `action` in the default keymap.
static func key_for(action: String) -> InputEventKey:
	var binding: Dictionary = HFKeymapScript._default_bindings()[action]
	return key(
		int(binding["keycode"]),
		bool(binding.get("ctrl", false)),
		bool(binding.get("shift", false)),
		bool(binding.get("alt", false))
	)
