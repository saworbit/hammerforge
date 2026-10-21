extends GutTest
## The brush's size beside the cursor through both stages of a Draw drag and the
## depth of an Extrude (#1402). The size showed only in the dock's banner and the
## toolbar at the viewport's edge, to one decimal place, so a quarter-unit grid
## step read 0.3.

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const HFPluginHud = preload("res://addons/hammerforge/plugin_hud.gd")
const HFInputState = preload("res://addons/hammerforge/input_state.gd")
const HFNumberFormat = preload("res://addons/hammerforge/hf_number_format.gd")
const HFSizeLabels = preload("res://addons/hammerforge/hf_size_labels.gd")
const HFContextToolbarScript = preload("res://addons/hammerforge/ui/hf_context_toolbar.gd")

const STOP := EditorPlugin.AFTER_GUI_INPUT_STOP
## The middle of the rig's viewport, where the camera looks at the origin.
const AIM := Vector2(400, 300)

var rig := PluginRig.new()
var _grid_before := 0.0


func before_all():
	await rig.bring_up(self, true)


func after_all():
	await rig.take_down()


func _level(step: float) -> Node:
	var level = await rig.make_level()
	_grid_before = rig.plugin.dock.get_grid_snap()
	rig.plugin.dock._apply_grid_snap(step)
	rig.plugin._hotkey_palette.action_invoked.emit("tool_draw")
	return level


func _leave(level: Node) -> void:
	rig.plugin._hotkey_palette.action_invoked.emit("tool_draw")
	await rig.leave_level(level)
	rig.plugin.dock._apply_grid_snap(_grid_before)


func _left(pressed: bool, at: Vector2) -> int:
	return rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, pressed, at))


## What the label beside the cursor says now.
func _label(level: Node) -> String:
	return HFPluginHud.cursor_size_text(rig.plugin, level)


## What the plugin last drew there, which the overlay redraw follows.
func _drawn() -> String:
	return rig.plugin._cursor_size_text


func _banner() -> String:
	return rig.plugin.dock._mode_label.text


## The size the drag stands at, as the banner prints it.
func _drag_size(level: Node) -> String:
	return HFInputState.format_dimensions(level.input_state.get_drag_dimensions(), level.grid_snap)


## Every Label3D under [param node], internal children included.
func _label_nodes(node: Node) -> Array:
	var found: Array = []
	for child in node.get_children(true):
		if child is Label3D:
			found.append(child)
		found.append_array(_label_nodes(child))
	return found


func _top_face_point(brush: Node) -> Vector3:
	return brush.global_position + Vector3(0, brush.size.y * 0.5, 0)


# ---------------------------------------------------------------------------
# The number format
# ---------------------------------------------------------------------------


func test_a_quarter_step_reads_as_a_quarter():
	assert_eq(HFInputState.format_dimensions(Vector3(0.25, 2, 1)), "0.25 x 2 x 1")


func test_a_finer_grid_step_prints_more_places():
	assert_eq(HFNumberFormat.decimals(1.0), 2, "two places at least, for a size off the grid")
	assert_eq(HFNumberFormat.decimals(0.25), 2)
	assert_eq(HFNumberFormat.decimals(0.125), 3)
	assert_eq(HFNumberFormat.decimals(0.0625), 4)
	assert_eq(HFInputState.format_dimensions(Vector3(0.125, 2, 1), 0.125), "0.125 x 2 x 1")
	assert_eq(HFNumberFormat.number(1.0 / 3.0, 1.0), "0.33", "off the grid is not rounded onto it")


func test_trailing_zeros_and_a_negative_zero_are_dropped():
	assert_eq(HFNumberFormat.number(2.5000001, 0.5), "2.5")
	assert_eq(HFNumberFormat.number(64.0), "64")
	assert_eq(HFNumberFormat.number(-0.0001), "0")
	assert_eq(HFNumberFormat.point(Vector3(-1.5, 0, 0.25)), "-1.5, 0, 0.25")


# ---------------------------------------------------------------------------
# One size, three places
# ---------------------------------------------------------------------------


func test_the_banner_the_toolbar_and_the_label_read_the_same_size():
	assert_not_null(rig.plugin, rig.error())
	var level = await _level(0.25)
	assert_true(level.begin_drag(rig.camera, AIM, 0, Vector3.ONE, 0))
	level.input_state.drag_end = level.input_state.drag_origin + Vector3(0.25, 0, 1)
	level.input_state.drag_height = 2.0
	rig.plugin._update_hud_context()
	var expected := "0.25 x 2 x 1"
	assert_string_contains(_banner(), expected, "the banner")
	var dragging: Node = rig.plugin._context_toolbar._sections.get(
		HFContextToolbarScript.Context.DRAGGING
	)
	assert_not_null(dragging, "the toolbar has its drag section")
	if dragging:
		assert_eq(dragging.get_node("DimLabel").text, expected, "the toolbar")
	assert_eq(_label(level), expected, "and the label beside the cursor")
	level.cancel_drag()
	await _leave(level)


# ---------------------------------------------------------------------------
# How long the label lives
# ---------------------------------------------------------------------------


func test_the_label_follows_both_stages_and_goes_when_the_brush_is_placed():
	var level = await _level(1.0)
	assert_eq(_label(level), "", "nothing is shown before a drag")
	assert_eq(_left(true, AIM), STOP)
	assert_eq(_label(level), _drag_size(level), "the label comes up as the drag starts")
	var corner := AIM + Vector2(80, 30)
	rig.forward(PluginRig.motion(corner, MOUSE_BUTTON_MASK_LEFT))
	var base := _label(level)
	assert_eq(base, _drag_size(level), "it reads the base being dragged")
	assert_eq(_drawn(), base, "and that is what is drawn")
	assert_string_contains(_banner(), base, "as the banner reads it")
	assert_eq(rig.plugin.last_3d_mouse_pos, corner, "beside the pointer")
	_left(false, corner)
	assert_true(level.input_state.is_drag_height(), "the release sets the base")
	var raised := corner + Vector2(0, -40)
	rig.forward(PluginRig.motion(raised))
	assert_eq(_label(level), _drag_size(level), "the height stage shows its size too")
	assert_eq(_drawn(), _label(level))
	assert_eq(rig.plugin.last_3d_mouse_pos, raised, "and the label went with the pointer")
	_left(true, raised)
	_left(false, raised)
	await rig.frame()
	assert_eq(level.draft_brushes_node.get_child_count(), 1, "the brush is placed")
	assert_eq(_label(level), "", "and the label goes with the drag")
	assert_eq(_drawn(), "", "with nothing left to draw")
	assert_eq(_label_nodes(rig.scene_root), [], "and no label node anywhere in the scene")
	await _leave(level)


func test_escape_takes_the_label_away_in_either_stage():
	var level = await _level(1.0)
	for height_stage in [false, true]:
		_left(true, AIM)
		rig.forward(PluginRig.motion(AIM + Vector2(60, 20), MOUSE_BUTTON_MASK_LEFT))
		if height_stage:
			_left(false, AIM + Vector2(60, 20))
			assert_true(level.input_state.is_drag_height())
		assert_ne(_drawn(), "", "the label is up")
		assert_eq(rig.forward(PluginRig.key(KEY_ESCAPE)), STOP, "Esc cancels the drag")
		assert_true(level.input_state.is_idle())
		assert_eq(_label(level), "", "and the label goes")
		assert_eq(_drawn(), "")
		if not height_stage:
			_left(false, AIM + Vector2(60, 20))
	assert_eq(level.draft_brushes_node.get_child_count(), 0, "nothing was placed")
	await _leave(level)


func test_a_right_click_takes_the_label_away_in_either_stage():
	var level = await _level(1.0)
	for height_stage in [false, true]:
		_left(true, AIM)
		rig.forward(PluginRig.motion(AIM + Vector2(60, 20), MOUSE_BUTTON_MASK_LEFT))
		if height_stage:
			_left(false, AIM + Vector2(60, 20))
		assert_ne(_drawn(), "", "the label is up")
		assert_eq(rig.forward(PluginRig.click(MOUSE_BUTTON_RIGHT, true)), STOP, "RMB cancels")
		rig.forward(PluginRig.click(MOUSE_BUTTON_RIGHT, false))
		assert_true(level.input_state.is_idle())
		assert_eq(_label(level), "", "and the label goes")
		assert_eq(_drawn(), "")
		if not height_stage:
			_left(false, AIM + Vector2(60, 20))
	await _leave(level)


func test_a_typed_number_shows_in_brackets_as_the_banner_shows_it():
	var level = await _level(1.0)
	_left(true, AIM)
	rig.forward(PluginRig.motion(AIM + Vector2(60, 20), MOUSE_BUTTON_MASK_LEFT))
	rig.forward(PluginRig.key(KEY_3))
	rig.forward(PluginRig.key(KEY_PERIOD))
	rig.forward(PluginRig.key(KEY_5))
	assert_eq(rig.plugin.numeric_buffer, "3.5")
	assert_string_ends_with(_label(level), "  [3.5]", "the typed number in brackets")
	assert_string_contains(_banner(), "[3.5]", "as the banner has it")
	assert_eq(_drawn(), _label(level))
	rig.forward(PluginRig.key(KEY_ESCAPE))
	_left(false, AIM + Vector2(60, 20))
	await _leave(level)


func test_an_extrude_shows_its_depth_and_takes_it_away_when_placed():
	var level = await _level(1.0)
	var box = rig.box(level, "a", Vector3.ZERO, Vector3(8, 8, 8))
	rig.plugin._hotkey_palette.action_invoked.emit("tool_extrude_up")
	var on_top := rig.camera.unproject_position(_top_face_point(box))
	assert_eq(_left(true, on_top), STOP, "a press on the top face starts the extrude")
	var pulled := on_top + Vector2(0, -60)
	rig.forward(PluginRig.motion(pulled, MOUSE_BUTTON_MASK_LEFT))
	var depth: float = level.extrude_tool.get_height()
	assert_gt(depth, 0.0, "the drag pulled the face out")
	assert_eq(_label(level), "Depth %s" % HFNumberFormat.number(depth, 1.0), "the depth shows")
	assert_eq(_drawn(), _label(level))
	_left(false, pulled)
	await rig.frame()
	assert_eq(level.draft_brushes_node.get_child_count(), 2, "the block is placed")
	assert_eq(_label(level), "", "and the label goes")
	assert_eq(_drawn(), "")
	await _leave(level)


func test_the_switch_turns_the_label_off_and_is_kept():
	var level = await _level(1.0)
	var prefs = rig.plugin._user_prefs
	assert_true(bool(prefs.get_pref("size_at_cursor", false)), "on by default")
	assert_true(rig.plugin.dock.size_at_cursor.button_pressed, "and the switch says so")
	rig.plugin.dock.size_at_cursor.button_pressed = false
	assert_false(bool(prefs.get_pref("size_at_cursor", true)), "off is kept as a preference")
	_left(true, AIM)
	rig.forward(PluginRig.motion(AIM + Vector2(60, 20), MOUSE_BUTTON_MASK_LEFT))
	assert_eq(_label(level), "", "and nothing shows beside the cursor")
	assert_eq(_drawn(), "")
	assert_ne(_banner().find("Step 1/2"), -1, "while the banner still reads the drag")
	rig.forward(PluginRig.key(KEY_ESCAPE))
	_left(false, AIM + Vector2(60, 20))
	rig.plugin.dock.size_at_cursor.button_pressed = true
	await _leave(level)


func test_the_console_lists_the_switch_in_its_viewport_group():
	var found := {}
	for group in HFConsoleControls.GROUPS:
		for spec in group["rows"]:
			if str(spec.get("pref", "")) == "size_at_cursor":
				found = {"group": group["title"], "dock": spec.get("dock", "")}
	assert_eq(found.get("group", ""), "Viewport")
	assert_eq(found.get("dock", ""), "size_at_cursor", "written through the dock's switch")


# ---------------------------------------------------------------------------
# Never in the scene
# ---------------------------------------------------------------------------


func test_the_label_puts_no_node_in_the_scene_and_nothing_is_saved():
	var level = await _level(1.0)
	_left(true, AIM)
	rig.forward(PluginRig.motion(AIM + Vector2(60, 20), MOUSE_BUTTON_MASK_LEFT))
	assert_ne(_drawn(), "", "the label is up")
	assert_eq(_label_nodes(rig.scene_root), [], "drawn over the viewport, not as a node")
	var packed := PackedScene.new()
	assert_eq(packed.pack(rig.scene_root), OK)
	var state := packed.get_state()
	for i in state.get_node_count():
		assert_ne(str(state.get_node_type(i)), "Label3D", "and no label is saved with the scene")
	rig.forward(PluginRig.key(KEY_ESCAPE))
	_left(false, AIM + Vector2(60, 20))
	await _leave(level)


func test_the_label_sits_beside_the_pointer_and_inside_the_viewport():
	var area := Vector2(800, 600)
	var text := Vector2(90, 16)
	assert_eq(
		HFSizeLabels.place_2d(area, Vector2(100, 100), text),
		Vector2(100, 100) + HFSizeLabels.POINTER_OFFSET,
		"below and to the right, clear of the corner being dragged"
	)
	var corner := HFSizeLabels.place_2d(area, Vector2(790, 590), text)
	assert_lte(corner.x + text.x, area.x, "kept inside on the right")
	assert_lte(corner.y + text.y, area.y, "and at the bottom")
