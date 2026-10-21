extends GutTest

## A cut waiting for Apply is drawn in the editor's orange pending look, and a
## brush that is not one draws as any brush of its operation does. The look used
## to be handed to a brush by whoever moved it, and nothing took it off again: an
## applied cut kept a solid red look of its own, through an operation change to a
## solid too (#1531). The brush now draws from what it is.

const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")
const CollationTests = preload("res://tests/test_undo_collation.gd")

var root: LevelRoot


func before_each():
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)


func _cut(pending: bool = true) -> DraftBrush:
	return (
		(
			root
			. create_brush_from_info(
				{
					"shape": LevelRoot.BrushShape.BOX,
					"size": Vector3(2, 2, 2),
					"center": Vector3.ZERO,
					"operation": CSGShape3D.OPERATION_SUBTRACTION,
					"pending": pending,
				}
			)
		)
		as DraftBrush
	)


## The colour `brush` is drawn in.
func _colour(brush: DraftBrush) -> Color:
	var drawn := brush.mesh_instance.get_active_material(0) as StandardMaterial3D
	assert_not_null(drawn, "fixture: %s is drawn with a material" % brush.name)
	return drawn.albedo_color if drawn else Color.BLACK


## What a brush of `operation` that is no pending cut is drawn in, asked of a
## brush made that way.
func _colour_of_a_brush(operation: int) -> Color:
	var reference := (
		(
			root
			. create_brush_from_info(
				{
					"shape": LevelRoot.BrushShape.BOX,
					"size": Vector3(2, 2, 2),
					"center": Vector3(40, 0, 0),
					"operation": operation,
				}
			)
		)
		as DraftBrush
	)
	var colour := _colour(reference)
	root.delete_brush(reference)
	return colour


func _pending_colour() -> Color:
	return DraftBrush.pending_cut_look().albedo_color


func _the_only_draft_brush() -> DraftBrush:
	var found: Array = root.draft_brushes_node.get_children().filter(
		func(child): return child is DraftBrush
	)
	assert_eq(found.size(), 1, "fixture: one brush in the draft container")
	return found[0] if not found.is_empty() else null


func _the_only_pending_cut() -> DraftBrush:
	var found: Array = root.pending_node.get_children().filter(
		func(child): return child is DraftBrush
	)
	assert_eq(found.size(), 1, "fixture: one pending cut")
	return found[0] if not found.is_empty() else null


func test_a_pending_cut_wears_the_pending_look():
	var cut := _cut()
	assert_true(cut.is_pending_cut(), "fixture: a pending cut")
	assert_eq(_colour(cut), _pending_colour())
	assert_true(
		DraftBrush.is_editor_look(cut.mesh_instance.get_active_material(0)),
		"a look the bake leaves behind"
	)


## The issue's own steps.
func test_an_applied_cut_turned_into_a_solid_draws_as_a_solid():
	var solid_colour := _colour_of_a_brush(CSGShape3D.OPERATION_UNION)
	var cut := _cut()
	root.apply_pending_cuts()
	cut.operation = CSGShape3D.OPERATION_UNION
	assert_eq(_colour(cut), solid_colour, "not the red of a cut")


func test_an_applied_cut_draws_as_any_cut_does():
	var cut_colour := _colour_of_a_brush(CSGShape3D.OPERATION_SUBTRACTION)
	var cut := _cut()
	root.apply_pending_cuts()
	assert_false(cut.is_pending_cut(), "fixture: applied")
	assert_eq(_colour(cut), cut_colour, "as a cut drawn as one, not a look of its own")


## The step the Apply button, a bake and the bridge all record.
func test_undo_of_an_apply_brings_the_pending_look_back_and_redo_takes_it_off():
	var cut_colour := _colour_of_a_brush(CSGShape3D.OPERATION_SUBTRACTION)
	_cut()
	var undo := CollationTests.FakeUndoRedo.new()
	assert_true(HFUndoHelper.apply_pending_cuts_step(undo, root), "fixture: a step")
	assert_eq(_colour(_the_only_draft_brush()), cut_colour, "applied")
	undo.undo()
	assert_eq(_colour(_the_only_pending_cut()), _pending_colour(), "undone: pending again")
	undo.redo()
	assert_eq(_colour(_the_only_draft_brush()), cut_colour, "redone: applied again")


## The Inspector's Operation, and its undo, which sets it back.
func test_an_operation_change_on_a_pending_cut_takes_the_look_off_and_back():
	var solid_colour := _colour_of_a_brush(CSGShape3D.OPERATION_UNION)
	var cut := _cut()
	cut.operation = CSGShape3D.OPERATION_UNION
	assert_false(cut.is_pending_cut(), "a solid is no pending cut")
	assert_eq(_colour(cut), solid_colour, "and draws as a solid")
	cut.operation = CSGShape3D.OPERATION_SUBTRACTION
	assert_eq(_colour(cut), _pending_colour(), "set back, it is a pending cut again")


## Commit Cuts applies the cuts before its bake, and puts the ones that were
## pending back when the bake fails.
func test_a_failed_commit_puts_the_pending_look_back():
	var cut := _cut()
	root.apply_pending_cuts()
	root.brush_system._restore_pending_after_failed_commit([cut])
	assert_eq(cut.get_parent(), root.pending_node, "fixture: back among the pending cuts")
	assert_eq(_colour(cut), _pending_colour())


func test_a_restored_committed_cut_draws_as_any_cut_does():
	var cut_colour := _colour_of_a_brush(CSGShape3D.OPERATION_SUBTRACTION)
	var solid_colour := _colour_of_a_brush(CSGShape3D.OPERATION_UNION)
	var cut := _cut()
	root.apply_pending_cuts()
	root.brush_system._stash_committed_cut(cut)
	root.restore_committed_cuts()
	assert_eq(cut.get_parent(), root.draft_brushes_node, "fixture: restored")
	assert_eq(_colour(cut), cut_colour)
	cut.operation = CSGShape3D.OPERATION_UNION
	assert_eq(_colour(cut), solid_colour, "and turned into a solid, as a solid")


## A pending cut dragged out of its container in the Scene dock.
func test_a_pending_cut_moved_among_the_brushes_draws_as_any_cut_does():
	var cut_colour := _colour_of_a_brush(CSGShape3D.OPERATION_SUBTRACTION)
	var cut := _cut()
	cut.reparent(root.draft_brushes_node)
	root.brush_system.reconcile_external_structure()
	assert_false(cut.is_pending_cut(), "fixture: no longer pending")
	assert_eq(_colour(cut), cut_colour)
	cut.reparent(root.pending_node)
	root.brush_system.reconcile_external_structure()
	assert_eq(_colour(cut), _pending_colour(), "and moved back, as a pending cut")


## The mark is the brush's own and is saved with it, so a copy Godot makes, as
## the Scene dock's Duplicate does, is drawn as what it is.
func test_a_copy_of_a_pending_cut_is_drawn_as_one():
	var cut := _cut()
	var copy := cut.duplicate() as DraftBrush
	root.pending_node.add_child(copy)
	assert_eq(_colour(copy), _pending_colour())
	root.pending_node.remove_child(copy)
	copy.free()
