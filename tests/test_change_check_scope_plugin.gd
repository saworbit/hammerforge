extends GutTest

## The plugin's part in #1619: it notes each version the scene's undo history
## moves to and checks the selection after a step Godot's gizmo or Inspector
## commits, the step's own brushes after its undo, and every brush before a bake.

const PluginRig = preload("res://tests/support/plugin_rig.gd")

var rig := PluginRig.new()


func before_all() -> void:
	await rig.bring_up(self, true)


func after_all() -> void:
	await rig.take_down()


## Moved as Godot's gizmo commits a move: a property step in the scene history.
func _commit_native_move(brush: Node3D, by: Vector3) -> void:
	var undo = rig.undo()
	undo.create_action("Move")
	undo.add_do_property(brush, "position", brush.position + by)
	undo.add_undo_property(brush, "position", brush.position)
	undo.commit_action()


func test_a_gizmo_step_checks_the_selection_its_undo_the_step_and_a_bake_every_brush():
	var level = await rig.make_level()
	var a = rig.box(level, "a", Vector3.ZERO)
	var b = rig.box(level, "b", Vector3(8, 0, 0))
	var tracker = rig.plugin._ensure_brush_change_tracker()
	# A first step, which walks every brush, so the tracker knows where it stands.
	rig.select([a])
	_commit_native_move(a, Vector3.UP)
	await rig.frame()
	level.consume_dirty_tags()

	# b moved with no step of its own, a by the gizmo with a selected.
	b.position += Vector3.UP
	_commit_native_move(a, Vector3.UP)
	await rig.frame()
	assert_true(level._dirty_brush_ids.has("a"), "the selected brush the gizmo moved")
	assert_false(level._dirty_brush_ids.has("b"), "and not b, which no step names")
	assert_true(tracker.owes_full_walk(), "so the check owes a full walk")
	level.consume_dirty_tags()

	# Ctrl+Z with b selected puts a back.
	rig.select([b])
	assert_true(rig.undo().press_undo(), "fixture: there is a step to undo")
	await rig.frame()
	assert_true(level._dirty_brush_ids.has("a"), "the undo checks the brush its step moved")

	level.brush_changes_wanted.emit()
	assert_true(level._dirty_brush_ids.has("b"), "and the walk a bake asks for finds b")
	assert_false(tracker.owes_full_walk())
	rig.select([])
	await rig.leave_level(level)
