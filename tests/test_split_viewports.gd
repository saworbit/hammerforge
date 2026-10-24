extends GutTest
## Every viewport of a split layout takes drops, and the overlays go to the one
## the mapper clicks in or to one still shown (#1627). They sat on the first
## viewport only, so a drop on another did nothing.

const PluginRig = preload("res://tests/support/plugin_rig.gd")

## The middle of a viewport, where each camera sees the box.
const AIM := Vector2(400, 300)

var rig: PluginRig


func before_each() -> void:
	rig = PluginRig.new()
	await rig.bring_up(self)
	var first := Control.new()
	first.name = "FirstHost"
	first.size = Vector2(800, 600)
	rig.viewport.add_child(first)
	rig.plugin._forward_3d_force_draw_over_viewport(first)


func after_each() -> void:
	await rig.take_down()


## A second viewport on the same world, its camera looking from the side.
func _second() -> Dictionary:
	var viewport := SubViewport.new()
	viewport.name = "SecondViewport"
	viewport.size = Vector2i(800, 600)
	viewport.world_3d = rig.viewport.world_3d
	add_child_autoqfree(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.look_at_from_position(Vector3(16, 0, 0), Vector3.ZERO)
	camera.current = true
	var host := Control.new()
	host.name = "SecondHost"
	host.size = Vector2(800, 600)
	viewport.add_child(host)
	rig.plugin._forward_3d_force_draw_over_viewport(host)
	return {"camera": camera, "host": host}


static func _target_on(host: Control) -> Control:
	for child in host.get_children():
		if child.name.begins_with("HFViewportDropTarget"):
			return child
	return null


func test_each_viewport_gets_a_drop_target_and_the_overlays_stay_put():
	var first: Control = rig.plugin._viewport_overlay_host
	var second := _second()
	assert_not_null(_target_on(first))
	assert_not_null(_target_on(second["host"]), "the second viewport takes drops too")
	assert_eq(rig.plugin._hotkey_palette.get_parent(), first, "drawing does not move the overlays")


func test_a_material_dropped_on_the_second_viewport_lands_on_the_face_it_sees():
	var second := _second()
	var level = await rig.make_level()
	level.set_materials([StandardMaterial3D.new(), StandardMaterial3D.new()])
	var brush = rig.box(level, "target", Vector3.ZERO, Vector3(4, 4, 4))
	var target := _target_on(second["host"])
	var data := {"type": "hammerforge_material", "index": 1}
	target.notification(Node.NOTIFICATION_DRAG_BEGIN)
	assert_true(target._can_drop_data(AIM, data))
	target._drop_data(AIM, data)
	target.notification(Node.NOTIFICATION_DRAG_END)
	var seen := int(level.pick_face(second["camera"], AIM).get("face_idx", -1))
	assert_ne(seen, -1, "fixture: the side camera sees the box")
	assert_gt(brush.faces[seen].normal.x, 0.9, "the face toward the side camera")
	assert_eq(brush.faces[seen].material_idx, 1, "the drop lands where the second viewport looks")
	var above := int(level.pick_face(rig.camera, AIM).get("face_idx", -1))
	if above != seen:
		assert_ne(brush.faces[above].material_idx, 1, "not where the first one looks")
	await rig.leave_level(level)


func test_a_click_in_the_second_viewport_brings_the_overlays():
	var second := _second()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = AIM
	rig.plugin._forward_3d_gui_input(second["camera"], press)
	var release := press.duplicate() as InputEventMouseButton
	release.pressed = false
	rig.plugin._forward_3d_gui_input(second["camera"], release)
	assert_eq(rig.plugin._viewport_overlay_host, second["host"])
	assert_eq(rig.plugin._hotkey_palette.get_parent(), second["host"])
	assert_eq(rig.plugin._viewport_drop_target, _target_on(second["host"]))


func test_a_viewport_the_layout_hides_gives_its_overlays_to_one_shown():
	var first: Control = rig.plugin._viewport_overlay_host
	var second := _second()
	first.visible = false
	rig.plugin._forward_3d_force_draw_over_viewport(second["host"])
	assert_eq(rig.plugin._hotkey_palette.get_parent(), second["host"])
