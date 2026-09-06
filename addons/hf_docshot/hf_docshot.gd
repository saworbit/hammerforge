@tool
extends EditorPlugin
## Dev-only documentation screenshot capture.
##
## Captures the WHOLE editor window (docks, viewport, inspector) by grabbing the
## viewport that owns the editor base control. This is what makes UI screenshots
## regenerable instead of hand-grabbed.
##
## Inert unless the HF_DOCSHOT environment variable is "1", so leaving the plugin
## enabled costs nothing during normal editing.
##
## Usage:
##   HF_DOCSHOT=1 godot --editor --path .
##
## The editor opens, captures, and quits on its own.

const OUT_DIR := "res://docs/images/"
const SCENE := "res://samples/hf_demo_showcase.tscn"

# Frames to wait for the editor to finish restoring its session. The editor
# reopens previously-open scenes well after _enter_tree, so opening ours before
# that finishes loses the active tab to whatever was restored last.
const SETTLE_FRAMES := 240
# Hard ceiling so a failed run never leaves the editor open forever.
const TIMEOUT_SECONDS := 240.0

# Dock tabs to capture, by title.
const DOCK_TABS := ["Build", "Paint", "Objects", "Test"]

# How-it-works strip: one level built up across stages, each paired with the
# dock tab a user would actually be on at that point.
const SEQUENCE_CROP := Rect2i(0, 90, 1660, 919)
const SEQUENCE := [
	["res://samples/hf_demo_step1.tscn", "Build", "seq_1_draw"],
	["res://samples/hf_demo_step2.tscn", "Build", "seq_2_walls"],
	["res://samples/hf_demo_step3.tscn", "Paint", "seq_3_detail"],
	["res://samples/hf_demo_showcase.tscn", "Test", "seq_4_test"],
]


func _enter_tree() -> void:
	var mode := OS.get_environment("HF_DOCSHOT")
	if mode == "probe":
		_probe_synthetic_input()
		return
	if mode != "1":
		return
	_run()


## Feasibility probe: can HammerForge be driven through its real editor input
## path with synthesised events? If so, an automated screen-recorded demo needs
## no OS-level mouse control at all.
func _probe_synthetic_input() -> void:
	for _i in range(240):
		await get_tree().process_frame
	EditorInterface.open_scene_from_path("res://samples/hf_demo_step1.tscn")
	for _i in range(120):
		await get_tree().process_frame
	await _show_main_screen("3D")
	_place_editor_camera(Vector3(-20, 26, 30), Vector3(7, 0, -1))
	await get_tree().process_frame

	var plugin: Node = _find_hammerforge_plugin()
	print("[probe] plugin=", plugin)
	if plugin == null:
		get_tree().quit(1)
		return
	var dock := _find_dock()
	print("[probe] dock=", dock)
	if dock == null:
		get_tree().quit(1)
		return

	# Arm the draw tool the same way clicking the dock button would.
	dock.tool_draw.button_pressed = true
	print("[probe] tool=", dock.get_tool(), " paint=", dock.is_paint_mode_enabled())

	var vp := EditorInterface.get_editor_viewport_3d(0)
	var cam := vp.get_camera_3d()
	print("[probe] viewport_size=", vp.size, " camera=", cam)

	var level: Node = EditorInterface.get_edited_scene_root()
	var draft: Node = level.draft_brushes_node
	var before: int = draft.get_child_count()
	print("[probe] brushes_before=", before)

	var a := Vector2(vp.size) * Vector2(0.40, 0.55)
	var b := Vector2(vp.size) * Vector2(0.62, 0.70)
	await _drag(plugin, cam, a, b)
	# Second stage of the two-click draw: move up, then click to set height.
	await _click(plugin, cam, b + Vector2(0, -60))

	for _i in range(30):
		await get_tree().process_frame
	var after: int = draft.get_child_count()
	print("[probe] brushes_after=", after)
	print("[probe] RESULT synthetic_input_creates_brush=", after > before)
	get_tree().quit(0)


func _find_hammerforge_plugin() -> Node:
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node != self and node.has_method("_forward_3d_gui_input") and node.get("dock") != null:
			return node
		for child in node.get_children():
			stack.append(child)
	return null


func _mouse_button(pos: Vector2, pressed: bool) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = pos
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	return ev


func _mouse_motion(pos: Vector2, relative: Vector2, dragging: bool) -> InputEventMouseMotion:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.relative = relative
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if dragging else 0
	return ev


func _drag(plugin: Node, cam: Camera3D, from: Vector2, to: Vector2) -> void:
	plugin._forward_3d_gui_input(cam, _mouse_motion(from, Vector2.ZERO, false))
	plugin._forward_3d_gui_input(cam, _mouse_button(from, true))
	await get_tree().process_frame
	var steps := 12
	var prev := from
	for i in range(1, steps + 1):
		var pos: Vector2 = from.lerp(to, float(i) / float(steps))
		plugin._forward_3d_gui_input(cam, _mouse_motion(pos, pos - prev, true))
		prev = pos
		await get_tree().process_frame
	plugin._forward_3d_gui_input(cam, _mouse_button(to, false))
	await get_tree().process_frame


func _click(plugin: Node, cam: Camera3D, pos: Vector2) -> void:
	plugin._forward_3d_gui_input(cam, _mouse_motion(pos, Vector2.ZERO, false))
	await get_tree().process_frame
	plugin._forward_3d_gui_input(cam, _mouse_button(pos, true))
	plugin._forward_3d_gui_input(cam, _mouse_button(pos, false))
	await get_tree().process_frame


func _run() -> void:
	var deadline := Time.get_ticks_msec() + int(TIMEOUT_SECONDS * 1000.0)
	print("[docshot] starting; waiting for editor session restore")

	for _i in range(SETTLE_FRAMES):
		await get_tree().process_frame

	if not ResourceLoader.exists(SCENE):
		printerr("[docshot] missing ", SCENE)
		get_tree().quit(1)
		return

	# Opened after the session restore so it wins the active tab.
	await _ensure_scene_open(SCENE)

	EditorInterface.set_main_screen_editor("3D")
	for _i in range(30):
		await get_tree().process_frame

	var edited := EditorInterface.get_edited_scene_root()
	print("[docshot] edited scene root=", edited)
	if edited != null:
		EditorInterface.get_selection().clear()
		EditorInterface.get_selection().add_node(edited)
		for _i in range(20):
			await get_tree().process_frame

	var shots := 0
	_compose_editor(true)
	for _i in range(20):
		await get_tree().process_frame

	# The plugin steals the main screen when a level is opened, so each main
	# screen has to be re-selected immediately before its own capture.
	if await _show_main_screen("3D"):
		_frame_selection()
		for _i in range(30):
			await get_tree().process_frame
		_place_editor_camera(Vector3(-44, 40, 56), Vector3(2, 6, -2))
		EditorInterface.get_selection().clear()
		for _i in range(10):
			await get_tree().process_frame
		if await _capture("ui_editor_3d"):
			shots += 1

		var dock := _find_dock()
		if dock == null:
			push_warning("[docshot] HammerForge dock not found; skipping tab shots")
		else:
			for title in DOCK_TABS:
				if not _select_tab(dock, title):
					push_warning("[docshot] no dock tab titled " + title)
					continue
				for _i in range(30):
					await get_tree().process_frame
				if await _capture("ui_dock_" + title.to_lower()):
					shots += 1

	if await _show_main_screen("HammerForge"):
		if await _capture("ui_console"):
			shots += 1
		# The Controls tab is the settings surface: every switch, grouped and
		# captioned. Worth its own shot -- it answers "what can I configure".
		if _select_console_tab("Controls"):
			for _i in range(20):
				await get_tree().process_frame
			if await _capture("ui_console_controls"):
				shots += 1
			_select_console_tab("Status")

	shots += await _capture_sequence()

	if Time.get_ticks_msec() > deadline:
		push_warning("[docshot] timed out")
	print("[docshot] done shots=", shots)
	get_tree().quit(0 if shots > 0 else 1)


## Capture the how-it-works strip: open each staged scene, hold the camera
## steady so the progression reads, and select the matching dock tab.
func _capture_sequence() -> int:
	var captured := 0
	if not await _show_main_screen("3D"):
		return 0
	var dock := _find_dock()
	for step in SEQUENCE:
		var scene_path := str(step[0])
		if not ResourceLoader.exists(scene_path):
			push_warning("[docshot] missing sequence scene " + scene_path)
			continue
		if not await _ensure_scene_open(scene_path):
			continue
		if dock != null:
			_select_tab(dock, str(step[1]))
			for _i in range(20):
				await get_tree().process_frame
		# Opening a scene hands the main screen back to the plugin, so 3D has to
		# be re-selected for every step or the panels are inconsistent.
		await _show_main_screen("3D")
		_place_editor_camera(Vector3(-44, 40, 56), Vector3(2, 6, -2))
		EditorInterface.get_selection().clear()
		for _i in range(10):
			await get_tree().process_frame
		if await _capture(str(step[2]), SEQUENCE_CROP):
			captured += 1
	return captured


## Compose the editor for a product shot.
##
## Godot clamps dock splitter offsets written into editor_layout.cfg, so the
## layout is set live instead. The Inspector and FileSystem are Godot's own
## docks, not HammerForge's: they fill the frame with truncated bake property
## labels and repo files, so they are hidden and the space goes to the viewport.
func _compose_editor(hide_godot_docks: bool) -> void:
	var base: Control = EditorInterface.get_base_control()
	if base == null:
		return
	var wanted := ["Scene", "Inspector", "FileSystem", "Import", "History", "Signals", "Groups"]
	for node in base.find_children("*", "TabContainer", true, false):
		var tabs := node as TabContainer
		var titles: Array = []
		for i in range(tabs.get_tab_count()):
			titles.append(tabs.get_tab_title(i))
		if titles.is_empty():
			continue
		# A dock is Godot's own if every tab it carries is one of theirs.
		var is_godot_dock := true
		for t in titles:
			if not wanted.has(t):
				is_godot_dock = false
				break
		if is_godot_dock:
			tabs.visible = not hide_godot_docks
			print("[docshot] dock ", titles, " visible=", tabs.visible)


## Widen the scene tree column so brush names are not clipped.
func _set_tree_column_width(width: int) -> void:
	var base: Control = EditorInterface.get_base_control()
	if base == null:
		return
	for node in base.find_children("*", "HSplitContainer", true, false):
		var split := node as HSplitContainer
		if split.split_offset > 100 and split.split_offset < 900:
			split.split_offset = width


## Open a scene and confirm it actually became the edited one. The editor
## restores its previous session asynchronously and the project main scene can
## reclaim the active tab, so a single open_scene_from_path is not enough.
func _ensure_scene_open(path: String) -> bool:
	for attempt in range(4):
		EditorInterface.open_scene_from_path(path)
		for _i in range(90):
			await get_tree().process_frame
			var edited := EditorInterface.get_edited_scene_root()
			if edited != null and edited.scene_file_path == path:
				print("[docshot] active scene=", path, " (attempt ", attempt + 1, ")")
				return true
	printerr("[docshot] could not make ", path, " the active scene")
	return false


## Select a tab on the HammerForge Console by title. The console is found by
## its tab set rather than by type, so this does not depend on the panel script.
func _select_console_tab(title: String) -> bool:
	var base: Control = EditorInterface.get_base_control()
	if base == null:
		return false
	for node in base.find_children("*", "TabContainer", true, false):
		var tabs := node as TabContainer
		var titles: Array = []
		for i in range(tabs.get_tab_count()):
			titles.append(tabs.get_tab_title(i))
		if titles.has("Status") and titles.has("Controls") and titles.has("Log"):
			for i in range(tabs.get_tab_count()):
				if tabs.get_tab_title(i) == title:
					tabs.current_tab = i
					print("[docshot] console tab -> ", title)
					return true
	push_warning("[docshot] console tab not found: " + title)
	return false


## Select an editor main screen and give it time to lay out.
func _show_main_screen(screen: String) -> bool:
	EditorInterface.set_main_screen_editor(screen)
	for _i in range(40):
		await get_tree().process_frame
	return true


## Drive the editor's own 3D camera so the level is framed instead of whatever
## position the viewport happened to restore. Applied immediately before the
## grab: the editor camera controller owns this transform and may reclaim it.
func _place_editor_camera(from: Vector3, target: Vector3) -> void:
	var vp := EditorInterface.get_editor_viewport_3d(0)
	if vp == null:
		push_warning("[docshot] no editor 3D viewport")
		return
	var cam := vp.get_camera_3d()
	if cam == null:
		push_warning("[docshot] editor 3D viewport has no camera")
		return
	cam.global_position = from
	cam.look_at(target, Vector3.UP)


## Ask the 3D viewport to frame the current selection (the editor's "F" action).
## Best effort: if the viewport does not have focus the key is simply ignored.
func _frame_selection() -> void:
	var press := InputEventKey.new()
	press.keycode = KEY_F
	press.pressed = true
	Input.parse_input_event(press)
	var release := InputEventKey.new()
	release.keycode = KEY_F
	release.pressed = false
	Input.parse_input_event(release)


func _find_dock() -> Node:
	var base: Control = EditorInterface.get_base_control()
	if base == null:
		return null
	var found := base.find_children("*", "HammerForgeDock", true, false)
	if found.is_empty():
		return null
	return found[0]


func _select_tab(dock: Node, title: String) -> bool:
	var tabs = dock.get("main_tabs")
	if tabs == null or not (tabs is TabContainer):
		return false
	var container := tabs as TabContainer
	for i in range(container.get_tab_count()):
		if container.get_tab_title(i) == title:
			container.current_tab = i
			return true
	return false


func _capture(shot_name: String, crop: Rect2i = Rect2i()) -> bool:
	var base: Control = EditorInterface.get_base_control()
	if base == null:
		printerr("[docshot] no base control")
		return false
	var viewport: Viewport = base.get_viewport()
	if viewport == null:
		printerr("[docshot] base control has no viewport")
		return false

	await RenderingServer.frame_post_draw

	var texture: ViewportTexture = viewport.get_texture()
	if texture == null:
		printerr("[docshot] no viewport texture")
		return false
	var image: Image = texture.get_image()
	if image == null:
		printerr("[docshot] no image")
		return false

	if crop.size.x > 0 and crop.size.y > 0:
		var bounds := Rect2i(Vector2i.ZERO, image.get_size())
		var clipped := crop.intersection(bounds)
		if clipped.size.x > 0 and clipped.size.y > 0:
			image = image.get_region(clipped)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path := OUT_DIR + shot_name + ".png"
	var err := image.save_png(path)
	if err != OK:
		printerr("[docshot] save failed ", path, " error ", err)
		return false
	print("[docshot] wrote ", path, " ", image.get_width(), "x", image.get_height())
	return true
