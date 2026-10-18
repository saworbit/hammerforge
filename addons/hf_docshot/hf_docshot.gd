@tool
extends EditorPlugin
## Dev-only documentation screenshot capture.
##
## Captures the WHOLE editor window (docks, viewport, inspector) by grabbing the
## viewport that owns the editor base control. This is what makes UI screenshots
## regenerable instead of hand-grabbed.
##
## Deliberately NOT enabled in project.godot. tools/capture_ui.py enables it for
## the duration of a capture run and removes it again afterwards. An
## EditorPlugin that reads an environment variable and can call
## get_tree().quit() should not load in a contributor's normal session, where a
## stray HF_DOCSHOT=1 would close their editor mid-work.
##
## The HF_DOCSHOT check below is a second gate, for anyone who enables the
## plugin by hand.
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
	if mode == "demo_live":
		_demo_live()
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
	# The editor opens the project's main scene beside it, which puts a second
	# scene tab in every shot.
	await _close_other_scenes(SCENE)

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

	# Bake and check the way Bake Now and Run Check do, so the board shows a
	# level that has been looked at rather than one that has not been touched.
	await _bake_and_check()

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
	shots += await _capture_workshop()

	# Last, so the Log holds what this run did: the bakes, the check, the
	# structures and the cut.
	if await _show_main_screen("HammerForge"):
		if _select_console_tab("Log"):
			for _i in range(20):
				await get_tree().process_frame
			if await _capture("ui_console_log"):
				shots += 1
			_select_console_tab("Status")

	if Time.get_ticks_msec() > deadline:
		push_warning("[docshot] timed out")
	print("[docshot] done shots=", shots)
	get_tree().quit(0 if shots > 0 else 1)


func _bake_and_check() -> void:
	var plugin := _find_hammerforge_plugin()
	var level := EditorInterface.get_edited_scene_root()
	if plugin == null or level == null or not level.has_method("is_bake_in_flight"):
		return
	plugin._on_console_action("bake")
	for _i in range(1200):
		await get_tree().process_frame
		if not level.is_bake_in_flight():
			break
	plugin._on_console_action("validate")
	for _i in range(30):
		await get_tree().process_frame


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


# ---------------------------------------------------------------------------
# Workshop: one staged level for the shots the showcase cannot give
#
# The showcase is plain brushes. The guides also need a structure, wired
# entities, painted terrain, vertex editing, a pending cut and the command
# palette, so those are built here, each in its own corner of the ground, and
# the camera is moved to each in turn. Everything is made through the same
# calls the dock and the plugin make, so a shot shows what a user would get.
#
# The level lives in hf_demo_empty.tscn, which capture_ui.py backs up and puts
# back, so nothing staged here outlives the run.
# ---------------------------------------------------------------------------

const WORKSHOP_SCENE := "res://samples/hf_demo_empty.tscn"
const PROTO := "res://addons/hammerforge/textures/prototypes/"

# Areas, in metres on the starter ground. The painted terrain sits on the paint
# grid's origin, so everything else keeps clear of it.
const STRUCTURES_AT := Vector3(-40, 0, 0)
const WIRING_AT := Vector3(40, 0, 0)
const BENCH_AT := Vector3(0, 0, -40)


func _capture_workshop() -> int:
	var captured := 0
	if not await _ensure_scene_open(WORKSHOP_SCENE):
		return 0
	await _show_main_screen("3D")
	var level: Node = EditorInterface.get_edited_scene_root()
	var plugin: Node = _find_hammerforge_plugin()
	var dock := _find_dock()
	if level == null or plugin == null or dock == null:
		push_warning("[docshot] workshop needs the level, the plugin and the dock")
		return 0
	level.create_new_level()
	for _i in range(20):
		await get_tree().process_frame

	var pieces := _build_structures(level)
	var wiring := _build_wiring(level)
	var bench := _build_bench(level)
	await _build_terrain(level)
	for _i in range(30):
		await get_tree().process_frame

	if await _shot_structure(level, dock, pieces):
		captured += 1
	if await _shot_wiring(level, dock, plugin, wiring):
		captured += 1
	if await _shot_terrain(dock):
		captured += 1
	if await _shot_material_browser(dock):
		captured += 1
	if await _shot_vertex_edit(level, dock, plugin, bench):
		captured += 1
	if await _shot_pending_cut(level, dock, plugin):
		captured += 1
	if await _shot_command_palette(plugin):
		captured += 1
	if await _shot_advanced_bake(dock):
		captured += 1
	return captured


func _proto(pattern_color: String) -> StandardMaterial3D:
	var parts := pattern_color.rsplit("_", true, 1)
	return HFPrototypeTextures.create_material(parts[0], parts[1])


func _brush(level: Node, size: Vector3, center: Vector3, look: String) -> Node:
	return level.create_brush_from_info(
		{"shape": 0, "size": size, "center": center, "material": _proto(look)}
	)


## A spiral staircase beside a dome, both from the Structure section's builders.
func _build_structures(level: Node) -> Array:
	var before: Array = level.generator_system.generators.keys()
	var spiral := HFGeneratorSystem.default_settings("spiral_stairs")
	spiral["steps"] = 16
	level.create_generator(
		"spiral_stairs", spiral, Transform3D(Basis.IDENTITY, STRUCTURES_AT + Vector3(-3, 0, 0))
	)
	var dome := HFGeneratorSystem.default_settings("dome")
	level.create_generator(
		"dome", dome, Transform3D(Basis.IDENTITY, STRUCTURES_AT + Vector3(4, 0, 0))
	)
	var made: Array = []
	for id in level.generator_system.generators.keys():
		if not before.has(id):
			made.append(id)
	return made


## A trigger in front of a door in a wall, and a lamp, wired the way the
## reference map wires them.
func _build_wiring(level: Node) -> Dictionary:
	var at := WIRING_AT
	_brush(level, Vector3(3, 3, 0.3), at + Vector3(-2.5, 1.5, -3), "brick_grey")
	_brush(level, Vector3(3, 3, 0.3), at + Vector3(2.5, 1.5, -3), "brick_grey")
	_brush(level, Vector3(2, 0.6, 0.3), at + Vector3(0, 2.7, -3), "brick_grey")
	var door: Node = _brush(level, Vector3(2, 2.4, 0.2), at + Vector3(0, 1.2, -3), "solid_orange")
	level.tie_brushes_to_entity([door.brush_id], "func_door", "door_1")
	var trigger: Node = _brush(
		level, Vector3(3, 2.5, 1.5), at + Vector3(0, 1.25, 1.5), "stripes_diagonal_yellow"
	)
	level.tie_brushes_to_entity([trigger.brush_id], "trigger_once", "trigger_1")
	var lamp: Node = (
		level
		. _restore_entity_from_info(
			{
				"entity_type": "light_point",
				"name": "light_1",
				"entity_name": "light_1",
				"transform": Transform3D(Basis.IDENTITY, at + Vector3(3, 2.6, -2)),
				"properties": {},
			}
		)
	)
	level.add_entity_output(trigger, "OnStartTouch", "door_1", "Open")
	level.add_entity_output(trigger, "OnStartTouch", "light_1", "TurnOn", "", 0.5)
	return {"trigger": trigger, "door": door, "lamp": lamp}


## A plain block to edit vertices on, and a wall to cut a doorway through.
func _build_bench(level: Node) -> Dictionary:
	var block: Node = _brush(level, Vector3(3, 2, 3), BENCH_AT + Vector3(-4, 1, 0), "checker_blue")
	var wall: Node = _brush(
		level, Vector3(8, 3.5, 0.4), BENCH_AT + Vector3(5, 1.75, 0), "brick_grey"
	)
	return {"block": block, "wall": wall}


## Painted ground on a noise heightmap, with three ground textures blended in.
func _build_terrain(level: Node) -> void:
	var layer = level.paint_layers.get_active_layer() if level.paint_layers else null
	if layer == null:
		push_warning("[docshot] no paint layer for the terrain")
		return
	for z in range(-14, 14):
		for x in range(-18, 18):
			layer.set_cell(Vector2i(x, z), true)
	level.generate_heightmap_noise({})
	level.set_heightmap_scale(2.5)
	var slots := ["checker_green", "solid_brown", "hex_grey", "dots_yellow"]
	for i in range(slots.size()):
		layer.set_terrain_slot_texture(i, PROTO + slots[i] + ".svg")
	# A path of slot B across the middle, and a patch of slot C in one corner.
	for x in range(-18, 18):
		for dz in range(-2, 2):
			layer.set_cell_blend_slot(Vector2i(x, dz), 1, 0.9)
	for z in range(4, 12):
		for x in range(6, 16):
			layer.set_cell_blend_slot(Vector2i(x, z), 2, 0.8)
	level.paint_system.regenerate_paint_layers()
	for _i in range(10):
		await get_tree().process_frame


func _select_only(nodes: Array) -> void:
	var selection := EditorInterface.get_selection()
	selection.clear()
	for node in nodes:
		if node != null:
			selection.add_node(node)
	for _i in range(4):
		await get_tree().process_frame


func _collapse_all_sections(dock: Node) -> void:
	for section in dock._all_sections.values():
		section.set_expanded(false)


func _expand(dock: Node, section_name: String) -> Control:
	var section: Control = dock._all_sections.get(section_name)
	if section == null:
		push_warning("[docshot] no dock section " + section_name)
		return null
	section.set_expanded(true)
	return section


## Scroll a dock tab so a section's header sits at the top.
func _scroll_to(dock: Node, section: Control) -> void:
	if section == null:
		return
	await get_tree().process_frame
	var scroll := dock.main_tabs.get_current_tab_control() as ScrollContainer
	if scroll:
		scroll.scroll_vertical = int(section.position.y)
	await get_tree().process_frame


func _shot_structure(level: Node, dock: Node, pieces: Array) -> bool:
	if pieces.is_empty():
		push_warning("[docshot] no structure was built")
		return false
	var record = level.generator_system.generators[pieces[0]]
	var piece: Node = level.find_brush_by_id(str(record.brush_ids[0]))
	_select_tab(dock, "Build")
	await _select_only([piece])
	_collapse_all_sections(dock)
	var section := _expand(dock, "Structure")
	HFDockBrushHandler.refresh_structure_preview(dock)
	await _scroll_to(dock, section)
	await _show_main_screen("3D")
	_place_editor_camera(STRUCTURES_AT + Vector3(-9, 7, 11), STRUCTURES_AT + Vector3(0.5, 1.5, 0))
	for _i in range(10):
		await get_tree().process_frame
	return await _capture("ui_structure")


func _shot_wiring(level: Node, dock: Node, plugin: Node, wiring: Dictionary) -> bool:
	dock._show_io_lines.button_pressed = true
	_select_tab(dock, "Objects")
	await _select_only([wiring["trigger"]])
	_collapse_all_sections(dock)
	_expand(dock, "Entity Properties")
	var section := _expand(dock, "I/O Wiring")
	await _scroll_to(dock, section)
	HFPluginCommands.execute(plugin, "highlight_connected", [true])
	await _show_main_screen("3D")
	_place_editor_camera(WIRING_AT + Vector3(-7, 5, 9), WIRING_AT + Vector3(0.5, 1.2, -1))
	for _i in range(20):
		await get_tree().process_frame
	var ok := await _capture("ui_entity_io")
	HFPluginCommands.execute(plugin, "highlight_connected", [false])
	return ok


func _shot_terrain(dock: Node) -> bool:
	await _select_only([])
	_select_tab(dock, "Paint")
	_collapse_all_sections(dock)
	_expand(dock, "Floor Paint")
	_expand(dock, "Heightmap")
	await _scroll_to(dock, dock._all_sections.get("Floor Paint"))
	await _show_main_screen("3D")
	_place_editor_camera(Vector3(-22, 16, 26), Vector3(0, 0, 0))
	for _i in range(10):
		await get_tree().process_frame
	return await _capture("ui_floor_paint")


func _shot_material_browser(dock: Node) -> bool:
	_select_tab(dock, "Paint")
	_collapse_all_sections(dock)
	var section := _expand(dock, "Materials")
	await _scroll_to(dock, section)
	for _i in range(10):
		await get_tree().process_frame
	return await _capture_control("ui_material_browser", dock as Control, 0)


func _shot_vertex_edit(level: Node, dock: Node, plugin: Node, bench: Dictionary) -> bool:
	var block: Node = bench["block"]
	_select_tab(dock, "Build")
	_collapse_all_sections(dock)
	dock.tool_select.button_pressed = true
	await _select_only([block])
	if not plugin._vertex_mode:
		plugin._toggle_vertex_mode(level)
	await get_tree().process_frame
	level.vertex_system.select_vertex(block.brush_id, 2, false)
	await _show_main_screen("3D")
	_place_editor_camera(BENCH_AT + Vector3(-9.5, 4.5, 5.5), BENCH_AT + Vector3(-4, 1, 0))
	var cam := EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
	plugin._update_vertex_overlay(level, cam)
	for _i in range(10):
		await get_tree().process_frame
	var ok := await _capture_control("ui_vertex_edit", _viewport_frame(), 0)
	if plugin._vertex_mode:
		plugin._toggle_vertex_mode(level)
	await _select_only([])
	return ok


func _shot_pending_cut(level: Node, dock: Node, plugin: Node) -> bool:
	_select_tab(dock, "Build")
	_collapse_all_sections(dock)
	dock.tool_draw.button_pressed = true
	dock.mode_subtract.button_pressed = true
	var cut := {
		"shape": 0,
		"size": Vector3(1.4, 2.4, 1.2),
		"center": BENCH_AT + Vector3(5, 1.2, 0),
		"operation": CSGShape3D.OPERATION_SUBTRACTION,
		"pending": true,
	}
	plugin._commit_brush_placement(level, cut)
	plugin._update_hud_context()
	await _show_main_screen("3D")
	_place_editor_camera(BENCH_AT + Vector3(1, 4, 9), BENCH_AT + Vector3(5, 1.4, 0))
	for _i in range(10):
		await get_tree().process_frame
	var ok := await _capture("ui_pending_cut")
	dock.mode_add.button_pressed = true
	return ok


func _shot_command_palette(plugin: Node) -> bool:
	await _show_main_screen("3D")
	_place_editor_camera(STRUCTURES_AT + Vector3(-9, 7, 11), STRUCTURES_AT + Vector3(0.5, 1.5, 0))
	if plugin._viewport_overlay_host == null:
		push_warning("[docshot] the palette has no viewport to sit in yet")
	var palette: Control = plugin._hotkey_palette
	if not palette.visible:
		plugin._on_toggle_hotkey_palette()
	await get_tree().process_frame
	palette._search_field.text = "bake"
	palette._search_field.caret_column = 4
	palette._on_search_changed("bake")
	plugin._update_hud_context()
	plugin.update_overlays()
	for _i in range(10):
		await get_tree().process_frame
	var ok := await _capture_control("ui_command_palette", _viewport_frame(), 0)
	plugin._on_toggle_hotkey_palette()
	return ok


func _shot_advanced_bake(dock: Node) -> bool:
	await _select_only([])
	_select_tab(dock, "Test")
	_collapse_all_sections(dock)
	_expand(dock, "Bake")
	var section := _expand(dock, "Advanced Bake")
	await _scroll_to(dock, section)
	for _i in range(10):
		await get_tree().process_frame
	return await _capture_control("ui_test_advanced_bake", dock as Control, 0)


## The 3D main screen's area: the viewport and its toolbar.
func _viewport_frame() -> Control:
	var vp := EditorInterface.get_editor_viewport_3d(0)
	var node: Node = vp
	# SubViewport -> SubViewportContainer -> the per-viewport control.
	while node != null and not (node is Control):
		node = node.get_parent()
	return node as Control


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


## Close every open scene but one. EditorInterface can only close the edited
## scene, so each is made current first. None of them has been edited, so no
## save prompt comes up.
func _close_other_scenes(keep: String) -> void:
	for path in EditorInterface.get_open_scenes():
		if path == keep:
			continue
		EditorInterface.open_scene_from_path(path)
		for _i in range(20):
			await get_tree().process_frame
		var edited := EditorInterface.get_edited_scene_root()
		if edited != null and edited.scene_file_path == path:
			EditorInterface.close_scene()
			for _i in range(20):
				await get_tree().process_frame
	await _ensure_scene_open(keep)


## Drop the dock's toasts. Switching tabs and tools raises "Paint mode
## enabled" and the like, which stack over the bottom of the dock for seconds.
func _clear_toasts() -> void:
	var dock := _find_dock()
	if dock == null:
		return
	var toasts = dock.get("_toast_container")
	if toasts is Control:
		for toast in (toasts as Control).get_children():
			toasts.remove_child(toast)
			toast.queue_free()


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


## Capture just the area a control covers, grown by a margin, for a shot about
## one panel rather than the whole editor.
func _capture_control(shot_name: String, control: Control, margin: int = 8) -> bool:
	if control == null or not control.is_visible_in_tree():
		push_warning("[docshot] nothing visible to frame for " + shot_name)
		return false
	var rect := Rect2i(control.get_global_rect()).grow(margin)
	return await _capture(shot_name, rect)


func _capture(shot_name: String, crop: Rect2i = Rect2i()) -> bool:
	var base: Control = EditorInterface.get_base_control()
	if base == null:
		printerr("[docshot] no base control")
		return false
	var viewport: Viewport = base.get_viewport()
	if viewport == null:
		printerr("[docshot] base control has no viewport")
		return false

	_clear_toasts()
	await get_tree().process_frame
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


# ---------------------------------------------------------------------------
# Demo video support
#
# This mode is passive on purpose. It composes the editor, reports where the 3D
# viewport is in screen coordinates, and waits. The harness drives the real OS
# mouse from outside.
#
# Synthetic input forwarded to _forward_3d_gui_input cannot be combined with
# cursor movement: Input.warp_mouse emits a genuine motion event with no button
# held, which cancels the drag in progress. So the demo sends nothing synthetic
# at all, and a viewer sees exactly what happened.
# ---------------------------------------------------------------------------

const GO_MARKER := "user://docshot_go"
const READY_MARKER := "user://docshot_ready"
## World points the harness wants in viewport pixels, one "x,y,z" per line.
## Beats written against screen fractions cannot say where a brush lands in the
## level, so a room drawn that way is only ever as good as the guess. The
## editor camera is the one thing that can answer it exactly, so it does.
const PROJECT_REQUEST := "user://docshot_project"


func _demo_live() -> void:
	for _i in range(240):
		await get_tree().process_frame
	_compose_editor(true)
	for _i in range(20):
		await get_tree().process_frame
	if not await _ensure_scene_open("res://samples/hf_demo_empty.tscn"):
		get_tree().quit(1)
		return
	await _show_main_screen("3D")

	# Start from what HammerForge's own New Level gives you: ground plane, sun
	# and player start. The ground matters for more than lighting -- cuts
	# extrude from the grid plane upward, so a doorway cut through a wall also
	# cuts any floor brush beneath it, leaving a pit at the threshold. Walls
	# standing on this ground have their doorways flush with it.
	var level: Node = EditorInterface.get_edited_scene_root()
	level.create_new_level()
	for _i in range(20):
		await get_tree().process_frame

	# Steep three-quarter view, about 50 degrees down.
	#
	# The angle is not taste, it is a constraint. The draw tool raycasts against
	# existing brush faces before falling back to the grid plane, so any ground
	# a wall hides cannot be clicked -- the click lands on the wall instead.
	# A camera only a little taller than the walls casts a very long shadow
	# behind each one; at this height and distance the shadow behind the 48-unit
	# far wall ends about 60 units back, which the cut brush can reach past.
	_place_editor_camera(Vector3(-36, 156, 84), Vector3(0, 8, -24))
	EditorInterface.get_selection().clear()
	for _i in range(30):
		await get_tree().process_frame

	var dock := _find_dock()
	if dock == null:
		printerr("[live] dock missing")
		get_tree().quit(1)
		return
	dock.tool_draw.button_pressed = true

	# Report the viewport RELATIVE to the window. Absolute screen position is the
	# harness's job via Win32: Godot's window_get_position and window_set_position
	# are relative to the current screen, so on a second monitor they disagree
	# with the desktop coordinates the mouse actually uses.
	var vp := EditorInterface.get_editor_viewport_3d(0)
	# The viewport's own screen transform, not its container's position: the
	# container sits a little above the rendered viewport, and that gap put
	# every projected point 14px out.
	var origin: Vector2 = vp.get_screen_transform().origin
	var lines := PackedStringArray(["%d,%d,%d,%d" % [origin.x, origin.y, vp.size.x, vp.size.y]])

	# The drag tool derives height from mouse pixels, not from the grid plane:
	# height = grid_snap + pixels_up / height_pixels_per_unit, snapped. The
	# harness needs both numbers to turn "a wall 48 units tall" into a gesture.
	lines.append("%f,%f" % [level.grid_snap, level.height_pixels_per_unit])
	lines.append_array(_project_requested_points(vp.get_camera_3d()))

	DirAccess.remove_absolute(ProjectSettings.globalize_path(GO_MARKER))
	var marker := FileAccess.open(READY_MARKER, FileAccess.WRITE)
	marker.store_string("\n".join(lines))
	marker.close()
	print("[live] ready; viewport rect=", lines[0])

	var waited := 0
	while not FileAccess.file_exists(GO_MARKER):
		await get_tree().process_frame
		waited += 1
		if waited > 7200:
			printerr("[live] never told to finish")
			get_tree().quit(1)
			return
	print("[live] done")
	get_tree().quit(0)


## Project each world point the harness asked about into viewport pixels.
##
## unproject_position is used rather than reimplementing the projection in the
## harness: it is the same call the editor's own gizmos use, so the answer
## matches what the drag tool will see for that pixel exactly, including any
## projection setting the editor camera happens to be on.
func _project_requested_points(camera: Camera3D) -> PackedStringArray:
	var out := PackedStringArray()
	if camera == null or not FileAccess.file_exists(PROJECT_REQUEST):
		return out
	var text := FileAccess.get_file_as_string(PROJECT_REQUEST)
	for line in text.split("\n", false):
		var parts := line.strip_edges().split(",")
		if parts.size() != 3:
			continue
		var world := Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
		var screen := camera.unproject_position(world)
		out.append("%d,%d" % [roundi(screen.x), roundi(screen.y)])
	return out
