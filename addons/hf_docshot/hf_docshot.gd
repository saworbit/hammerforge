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
	if OS.get_environment("HF_DOCSHOT") != "1":
		return
	_run()


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
	EditorInterface.open_scene_from_path(SCENE)
	for _i in range(120):
		await get_tree().process_frame

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

	# The plugin steals the main screen when a level is opened, so each main
	# screen has to be re-selected immediately before its own capture.
	if await _show_main_screen("3D"):
		_frame_selection()
		for _i in range(30):
			await get_tree().process_frame
		_place_editor_camera(Vector3(-20, 26, 30), Vector3(7, 0, -1))
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
		EditorInterface.open_scene_from_path(scene_path)
		for _i in range(60):
			await get_tree().process_frame
		if dock != null:
			_select_tab(dock, str(step[1]))
			for _i in range(20):
				await get_tree().process_frame
		# Opening a scene hands the main screen back to the plugin, so 3D has to
		# be re-selected for every step or the panels are inconsistent.
		await _show_main_screen("3D")
		_place_editor_camera(Vector3(-20, 26, 30), Vector3(7, 0, -1))
		await get_tree().process_frame
		if await _capture(str(step[2]), SEQUENCE_CROP):
			captured += 1
	return captured


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
	print("[docshot] editor camera placed at ", cam.global_position)


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
