extends GutTest
## X-ray face marquee (#1432): with X-ray on, the Face Select box takes every
## face of a visible brush whose centre is inside it and in front of the camera,
## covered or facing away; with it off, only the faces a pick at their centre
## lands on. Alt+X flips the checkbox, and the HUD and the box's colour follow.

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const HFPluginOverlays = preload("res://addons/hammerforge/plugin_overlays.gd")
const STOP := EditorPlugin.AFTER_GUI_INPUT_STOP

var rig := PluginRig.new()


func before_all() -> void:
	await rig.bring_up(self)


func after_all() -> void:
	await rig.take_down()


## The rig's camera sits at (0, 12, 16) looking at the origin. `front` stands
## between it and `back`, hiding back's front face; both show their tops.
func _two_boxes(level: Node) -> Array:
	var front = rig.box(level, "front", Vector3(0, 0, 4), Vector3(6, 6, 6))
	var back = rig.box(level, "back", Vector3(0, 0, -6), Vector3(6, 6, 6))
	return [front, back]


func _face_toward(brush: Node, direction: Vector3) -> int:
	for i in brush.faces.size():
		if brush.faces[i].normal.dot(direction) > 0.99:
			return i
	return -1


func _sorted(indices: Array) -> Array:
	var out := indices.duplicate()
	out.sort()
	return out


func _all_faces(brush: Node) -> Array:
	return range(brush.faces.size())


## A box over the whole viewport, from empty space, with Face Select on.
func _marquee_everything() -> void:
	rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, true, Vector2(5, 5)))
	rig.forward(PluginRig.motion(Vector2(795, 595), MOUSE_BUTTON_MASK_LEFT))
	rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, false, Vector2(795, 595)))


func _face_select(on: bool) -> void:
	rig.plugin._hotkey_palette.action_invoked.emit("tool_select")
	rig.plugin.dock.face_select_mode.button_pressed = on


func _leave(level: Node) -> void:
	rig.plugin.dock.face_select_xray.button_pressed = false
	rig.plugin.dock.face_select_mode.button_pressed = false
	rig.plugin._hotkey_palette.action_invoked.emit("tool_draw")
	await rig.leave_level(level)


func test_without_xray_the_box_takes_only_the_faces_in_view() -> void:
	var level = await rig.make_level()
	var boxes := _two_boxes(level)
	var front = boxes[0]
	var back = boxes[1]
	_face_select(true)
	_marquee_everything()
	assert_eq(
		_sorted(level.face_selection.get("front", [])),
		_sorted([_face_toward(front, Vector3.UP), _face_toward(front, Vector3.BACK)]),
		"the front box gives its top and the face looking at the camera"
	)
	assert_eq(
		level.face_selection.get("back", []),
		[_face_toward(back, Vector3.UP)],
		"the back box gives its top: its front face is behind the front box"
	)
	await _leave(level)


func test_with_xray_the_box_takes_covered_and_back_faces_too() -> void:
	var level = await rig.make_level()
	var boxes := _two_boxes(level)
	_face_select(true)
	rig.plugin.dock.face_select_xray.button_pressed = true
	_marquee_everything()
	for brush in boxes:
		assert_eq(
			_sorted(level.face_selection.get(brush.brush_id, [])),
			_all_faces(brush),
			"%s gives every face, the covered and the inward facing ones" % brush.brush_id
		)
	await _leave(level)


func test_ctrl_toggles_under_xray_as_it_does_without() -> void:
	var level = await rig.make_level()
	var boxes := _two_boxes(level)
	var back = boxes[1]
	_face_select(true)
	var covered := _face_toward(back, Vector3.BACK)
	level.toggle_face_selection(back, covered, false)
	rig.plugin.dock.face_select_xray.button_pressed = true
	# Ctrl toggles: the covered face picked before goes, the rest come.
	var press := PluginRig.click(MOUSE_BUTTON_LEFT, true, Vector2(5, 5))
	press.ctrl_pressed = true
	rig.forward(press)
	rig.forward(PluginRig.motion(Vector2(795, 595), MOUSE_BUTTON_MASK_LEFT))
	var release := PluginRig.click(MOUSE_BUTTON_LEFT, false, Vector2(795, 595))
	release.ctrl_pressed = true
	rig.forward(release)
	var picked: Array = level.face_selection.get("back", [])
	assert_false(picked.has(covered), "Ctrl drops the covered face it held")
	assert_eq(picked.size(), back.faces.size() - 1, "and takes the other five")
	await _leave(level)


func test_xray_never_takes_a_face_of_a_brush_a_visgroup_hides() -> void:
	var level = await rig.make_level()
	var boxes := _two_boxes(level)
	var hidden = boxes[1]
	level.visgroup_system.create_visgroup("behind")
	level.visgroup_system.add_to_visgroup(hidden, "behind")
	level.visgroup_system.set_visgroup_visible("behind", false)
	assert_false(hidden.is_visible_in_tree(), "the visgroup hides the back box")
	_face_select(true)
	rig.plugin.dock.face_select_xray.button_pressed = true
	_marquee_everything()
	assert_eq(level.face_selection.keys(), ["front"], "only the shown brush gives faces")
	await _leave(level)


func test_alt_x_flips_the_checkbox_and_the_hud_line_together() -> void:
	var level = await rig.make_level()
	_two_boxes(level)
	_face_select(true)
	var dock = rig.plugin.dock
	assert_false(rig.plugin.hud.label.text.contains("X-ray"), "no X-ray line to start with")
	assert_eq(rig.forward(PluginRig.key_for("toggle_face_xray")), STOP, "Alt+X is taken")
	assert_true(dock.face_select_xray.button_pressed, "Alt+X ticks the checkbox")
	assert_true(rig.plugin.hud.label.text.contains("X-ray"), "and the HUD says X-ray")
	assert_eq(rig.forward(PluginRig.key_for("toggle_face_xray")), STOP)
	assert_false(dock.face_select_xray.button_pressed, "a second Alt+X clears it")
	assert_false(rig.plugin.hud.label.text.contains("X-ray"), "and the HUD line goes with it")
	dock.face_select_xray.button_pressed = true
	assert_true(rig.plugin.hud.label.text.contains("X-ray"), "a click on the checkbox shows it too")
	dock.face_select_mode.button_pressed = false
	assert_false(
		rig.plugin.hud.label.text.contains("X-ray"), "out of Face Select the box is Godot's"
	)
	dock.face_select_mode.button_pressed = true
	assert_true(rig.plugin.hud.label.text.contains("X-ray"), "and back in it, X-ray shows again")
	await _leave(level)


func test_the_xray_box_is_drawn_in_another_colour() -> void:
	var dock = rig.plugin.dock
	var plain := HFPluginOverlays.marquee_color(rig.plugin)
	dock.face_select_xray.button_pressed = true
	assert_ne(
		HFPluginOverlays.marquee_color(rig.plugin), plain, "an X-ray box is not the ordinary blue"
	)
	dock.face_select_xray.button_pressed = false
	assert_eq(HFPluginOverlays.marquee_color(rig.plugin), plain, "and the blue comes back")
