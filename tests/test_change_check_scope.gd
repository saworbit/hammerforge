extends GutTest

## The change check after every step walked every brush in the level, so the
## pause after an edit grew with the level: 296 ms at 3,000 brushes (#1619). It
## now looks at the brushes the step can have touched: the selection Godot's
## gizmo and Inspector edit, what HammerForge's own commands tagged, and what the
## undo or redo of a recorded step puts back. Anything else waits for the full
## walk a bake asks for, so nothing a bake needs is missed.

const BrushChangeTracker = preload("res://addons/hammerforge/hf_brush_change_tracker.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")
const LevelRootType = preload("res://addons/hammerforge/level_root.gd")

var level: LevelRoot
var tracker: HFBrushChangeTracker


func before_each() -> void:
	level = LevelRootType.new()
	level.auto_spawn_player = false
	level.commit_freeze = false
	level.hflevel_autosave_enabled = false
	add_child_autoqfree(level)
	tracker = BrushChangeTracker.new()


func after_each() -> void:
	tracker.reset()
	tracker = null
	level = null


func _brush(brush_id: String, at: Vector3) -> DraftBrush:
	var brush := (
		(
			level
			. create_brush_from_info(
				{
					"brush_id": brush_id,
					"shape": level.BrushShape.BOX,
					"size": Vector3(2, 2, 2),
					"transform": Transform3D(Basis.IDENTITY, at),
				}
			)
		)
		as DraftBrush
	)
	return brush


## Three brushes, the check watching them from version 0 of an empty history.
func _watched_level() -> Array:
	var brushes := [
		_brush("a", Vector3.ZERO), _brush("b", Vector3(5, 0, 0)), _brush("c", Vector3(10, 0, 0))
	]
	tracker.prime(level)
	tracker.note_step(0, false)
	tracker.reconcile_step(level, [])
	level.consume_dirty_tags()
	return brushes


## Moved straight on the node, as Godot's gizmo, its Inspector and their undo do.
func _native_move(brush: Node3D, by: Vector3) -> void:
	brush.global_position += by


func _dirty() -> Array:
	var ids: Array = level._dirty_brush_ids.keys()
	ids.sort()
	return ids


func test_a_step_on_the_selection_checks_the_selection_and_the_bake_sees_the_rest():
	var brushes := _watched_level()
	_native_move(brushes[0], Vector3.UP)
	_native_move(brushes[1], Vector3.UP)
	tracker.note_step(1, false)
	assert_eq(tracker.reconcile_step(level, [brushes[0]]), PackedStringArray(["a"]))
	assert_eq(_dirty(), ["a"], "the selected brush the gizmo moved")
	assert_true(tracker.owes_full_walk(), "and b waits for the full walk")
	level.brush_changes_wanted.emit()
	assert_eq(_dirty(), ["a", "b"], "which a bake asks for before it reads the changes")
	assert_false(tracker.owes_full_walk())


## Bake Changed with only c changed, outside every check since: without the full
## walk first it found no changed brush and baked nothing.
func test_bake_changed_reads_a_change_made_outside_the_selection():
	var brushes := _watched_level()
	_native_move(brushes[2], Vector3.UP)
	tracker.note_step(1, false)
	tracker.reconcile_step(level, [brushes[0]])
	assert_eq(_dirty(), [], "fixture: c is not in the check")
	await level.bake_dirty()
	assert_false(tracker.owes_full_walk(), "Bake Changed walked every brush first")
	assert_ne(
		level.bake_system.get_last_bake_status(),
		HFBakeSystem.BakeStatus.NOTHING_TO_DO,
		"and baked the change it found"
	)


func test_the_undo_of_a_step_checks_what_it_changed_after_the_selection_moved_on():
	var brushes := _watched_level()
	_native_move(brushes[0], Vector3.UP)
	tracker.note_step(1, false)
	assert_eq(tracker.reconcile_step(level, [brushes[0]]), PackedStringArray(["a"]))
	level.consume_dirty_tags()
	# Ctrl+Z with b selected: Godot puts a back, and nothing selected is a.
	_native_move(brushes[0], Vector3.DOWN)
	tracker.note_step(0, true)
	assert_eq(tracker.reconcile_step(level, [brushes[1]]), PackedStringArray(["a"]), "undo")
	level.consume_dirty_tags()
	_native_move(brushes[0], Vector3.UP)
	tracker.note_step(1, false)
	assert_eq(tracker.reconcile_step(level, [brushes[1]]), PackedStringArray(["a"]), "redo")


func test_a_redo_with_more_waiting_checks_its_record():
	var brushes := _watched_level()
	_native_move(brushes[0], Vector3.UP)
	tracker.note_step(1, false)
	tracker.reconcile_step(level, [brushes[0]])
	_native_move(brushes[1], Vector3.UP)
	tracker.note_step(2, false)
	tracker.reconcile_step(level, [brushes[1]])
	level.consume_dirty_tags()
	_native_move(brushes[1], Vector3.DOWN)
	tracker.note_step(1, true)
	tracker.reconcile_step(level, [])
	_native_move(brushes[0], Vector3.DOWN)
	tracker.note_step(0, true)
	tracker.reconcile_step(level, [])
	assert_eq(_dirty(), ["a", "b"], "both undone")
	level.consume_dirty_tags()
	_native_move(brushes[0], Vector3.UP)
	tracker.note_step(1, true)
	assert_eq(tracker.reconcile_step(level, [brushes[2]]), PackedStringArray(["a"]))


func test_a_new_step_in_place_of_a_redo_drops_the_records_after_it():
	var brushes := _watched_level()
	_native_move(brushes[0], Vector3.UP)
	tracker.note_step(1, false)
	tracker.reconcile_step(level, [brushes[0]])
	_native_move(brushes[1], Vector3.UP)
	tracker.note_step(2, false)
	tracker.reconcile_step(level, [brushes[1]])
	_native_move(brushes[1], Vector3.DOWN)
	tracker.note_step(1, true)
	tracker.reconcile_step(level, [])
	_native_move(brushes[0], Vector3.DOWN)
	tracker.note_step(0, true)
	tracker.reconcile_step(level, [])
	level.consume_dirty_tags()
	# A new step on c, where the redo of a's step was waiting.
	_native_move(brushes[2], Vector3.UP)
	tracker.note_step(1, false)
	assert_eq(tracker.reconcile_step(level, [brushes[2]]), PackedStringArray(["c"]))
	assert_false(tracker._step_brushes.has(2), "the record of b's step went with its redo")


func test_a_step_with_no_record_checks_every_brush():
	var brushes := _watched_level()
	_native_move(brushes[1], Vector3.UP)
	tracker.note_step(5, false)
	assert_eq(tracker.reconcile_step(level, []), PackedStringArray(["b"]), "a jump of five")
	level.consume_dirty_tags()
	_native_move(brushes[2], Vector3.UP)
	tracker.note_step(4, true)
	assert_eq(
		tracker.reconcile_step(level, []),
		PackedStringArray(["c"]),
		"an undo of a step it never saw"
	)


func test_the_first_step_after_priming_checks_every_brush():
	_brush("a", Vector3.ZERO)
	var b := _brush("b", Vector3(5, 0, 0))
	tracker.prime(level)
	level.consume_dirty_tags()
	_native_move(b, Vector3.UP)
	tracker.note_step(3, false)
	assert_eq(tracker.reconcile_step(level, []), PackedStringArray(["b"]))


## Drawing a brush tags the brush it makes, so the check takes it in as the full
## walk would and walks nothing else; b, moved with no step, waits for the bake.
func test_a_brush_a_command_made_is_taken_in_without_walking_every_brush():
	var brushes := _watched_level()
	_brush("d", Vector3(15, 0, 0))
	_native_move(brushes[1], Vector3.UP)
	tracker.note_step(1, false)
	assert_false(tracker.reconcile_step(level, []).has("b"), "b is not walked")
	assert_true(tracker.owes_full_walk())
	assert_true(tracker._instances_by_id.has("d"), "d is tracked now")
	level.consume_dirty_tags()
	_native_move(level.find_brush_by_id("d"), Vector3.UP)
	tracker.note_step(2, false)
	assert_eq(
		tracker.reconcile_step(level, [level.find_brush_by_id("d")]), PackedStringArray(["d"])
	)
	level.brush_changes_wanted.emit()
	assert_true(level._dirty_brush_ids.has("b"), "and the walk before a bake finds b")


func test_a_brush_that_went_or_a_copy_godot_made_makes_it_a_full_walk():
	var brushes := _watched_level()
	# Godot's Delete: the brush goes with no tag and no record that names it.
	var gone: DraftBrush = brushes[2]
	gone.get_parent().remove_child(gone)
	gone.queue_free()
	_native_move(brushes[1], Vector3.UP)
	tracker.note_step(1, false)
	assert_eq(tracker.reconcile_step(level, []), PackedStringArray(["b"]), "a brush Godot deleted")
	level.consume_dirty_tags()
	# Ctrl+D in the Scene dock: a copy under its original's id, and no tag.
	var copy: DraftBrush = brushes[0].duplicate()
	level.draft_brushes_node.add_child(copy)
	_native_move(brushes[1], Vector3.UP)
	tracker.note_step(2, false)
	assert_true(tracker.reconcile_step(level, []).has("b"), "a copy Godot made")
	assert_ne(copy.brush_id, "a", "and the walk gave the copy an id of its own")


## A brush a command took away, which tagged it, is let go without walking every
## brush, as the undo of a placement takes away the brush its step's record names
## (#1866). What else changed is the step's to name.
func test_a_brush_a_command_took_away_is_let_go_without_a_full_walk():
	var brushes := _watched_level()
	level.delete_brush_by_id("c")
	_native_move(brushes[1], Vector3.UP)
	tracker.note_step(1, false)
	assert_eq(
		tracker.reconcile_step(level, [brushes[1]]),
		PackedStringArray(["b"]),
		"the selection's own change"
	)
	assert_true(tracker.owes_full_walk(), "found without walking every brush")
	assert_false(tracker._instances_by_id.has("c"), "and the deleted brush is let go")
	level.brush_changes_wanted.emit()
	assert_false(tracker.owes_full_walk(), "the walk before a bake agrees")


func test_a_selected_folder_moves_every_brush_in_it():
	_watched_level()
	level.draft_brushes_node.position += Vector3.UP
	tracker.note_step(1, false)
	assert_eq(tracker.reconcile_step(level, [level.draft_brushes_node]).size(), 3)
	level.draft_brushes_node.position -= Vector3.UP
	level.consume_dirty_tags()
	level.position += Vector3(0, 0, 3)
	tracker.note_step(2, false)
	assert_eq(tracker.reconcile_step(level, [level]).size(), 3, "and the level moves them all")


func test_a_brush_a_command_tagged_is_the_record_of_its_step():
	var brushes := _watched_level()
	level.rotate_managed_nodes(["b"], [], 1, 90.0, brushes[1].global_position)
	tracker.note_step(1, false)
	tracker.reconcile_step(level, [])
	assert_eq(tracker._step_brushes.get(1, PackedStringArray()), PackedStringArray(["b"]))
	assert_true(tracker.owes_full_walk(), "a check of b alone")


func test_a_door_a_command_turned_is_not_turned_again():
	var brushes := _watched_level()
	level.tie_brushes_to_entity(["b"], "func_door", "gate")
	brushes[1].set_meta("brush_entity_data", {"angle": 0.0})
	tracker.note_step(1, false)
	tracker.reconcile_step(level, [])
	level.rotate_managed_nodes(["b"], [], 1, 90.0, brushes[1].global_position)
	tracker.note_step(2, false)
	tracker.reconcile_step(level, [])
	assert_eq(brushes[1].get_meta("brush_entity_data", {}).get("angle"), 90.0, "turned once")


func test_a_door_the_gizmo_turned_turns_its_angle():
	var brushes := _watched_level()
	level.tie_brushes_to_entity(["b"], "func_door", "gate")
	brushes[1].set_meta("brush_entity_data", {"angle": 0.0})
	tracker.note_step(1, false)
	tracker.reconcile_step(level, [])
	var door: DraftBrush = brushes[1]
	door.global_transform = HFTransformSystem.rotated_transform(
		door.global_transform, Basis(Vector3.UP, deg_to_rad(90.0)), door.global_position
	)
	tracker.note_step(2, false)
	assert_eq(tracker.reconcile_step(level, [door]), PackedStringArray(["b"]))
	assert_eq(door.get_meta("brush_entity_data", {}).get("angle"), 90.0)


func test_a_rename_of_a_selected_entity_is_the_full_walk_s():
	var brushes := _watched_level()
	level.tie_brushes_to_entity(["b"], "func_door", "gate")
	tracker.note_step(1, false)
	tracker.reconcile_step(level, [])
	brushes[1].name = "Renamed"
	_native_move(brushes[2], Vector3.UP)
	tracker.note_step(2, false)
	tracker.reconcile_step(level, [brushes[1]])
	assert_true(_dirty().has("c"), "a rename walks every brush, as the names need")


## Undo a placement, then move a brush: the move is a new step where the redo of
## the placement waited. Its name says it is not that redo, so it checks the
## selection, not every brush, as the first edit after every undo did.
func test_a_new_step_where_a_redo_waited_is_told_from_the_redo_by_its_name():
	var brushes := _watched_level()
	_brush("d", Vector3(15, 0, 0))
	tracker.note_step(1, false, "Place Brush")
	tracker.reconcile_step(level, [])
	level.delete_brush_by_id("d")
	tracker.note_step(0, true, "")
	tracker.reconcile_step(level, [])
	level.consume_dirty_tags()
	_native_move(brushes[0], Vector3.UP)
	tracker.note_step(1, false, "Move")
	assert_eq(tracker.reconcile_step(level, [brushes[0]]), PackedStringArray(["a"]))
	assert_true(tracker.owes_full_walk(), "a check of the selection alone")


## Ctrl+D in the Scene dock is a step no tag narrows, so it keeps no record. Its
## redo, under the same name, walks every brush.
func test_a_redo_under_the_name_it_was_done_by_still_walks_when_it_has_no_record():
	var brushes := _watched_level()
	var copy: DraftBrush = brushes[0].duplicate()
	level.draft_brushes_node.add_child(copy)
	tracker.note_step(1, false, "Duplicate Node(s)")
	tracker.reconcile_step(level, [])
	assert_false(tracker._step_brushes.has(1), "fixture: no record of the copy")
	level.draft_brushes_node.remove_child(copy)
	tracker.note_step(0, true, "")
	tracker.reconcile_step(level, [])
	level.consume_dirty_tags()
	level.draft_brushes_node.add_child(copy)
	_native_move(brushes[2], Vector3.UP)
	tracker.note_step(1, false, "Duplicate Node(s)")
	assert_true(tracker.reconcile_step(level, []).has("c"), "every brush")
	assert_false(tracker.owes_full_walk())


## Godot moved b from DraftBrushes to PendingCuts with nothing selected: as many
## brushes as before, but two folders changed, so every brush is walked, and the
## walk puts b back where it was, as it does a brush dragged out of its folder.
func test_a_brush_moved_between_folders_unselected_is_the_full_walk_s():
	var brushes := _watched_level()
	brushes[1].reparent(level.pending_node)
	tracker.note_step(1, false)
	tracker.reconcile_step(level, [])
	assert_false(tracker.owes_full_walk(), "every brush walked")
	assert_eq(brushes[1].get_parent(), level.draft_brushes_node, "and b is back")


## Place a brush, undo it, place another: the redo the second placement replaced
## named the first brush, which its undo took away. A name no brush has is passed
## over, so the second placement is taken in without walking every brush.
func test_a_record_naming_a_brush_that_is_gone_does_not_force_a_full_walk():
	_watched_level()
	_brush("d", Vector3(15, 0, 0))
	tracker.note_step(1, false, "Place Brush")
	tracker.reconcile_step(level, [])
	level.delete_brush_by_id("d")
	tracker.note_step(0, true, "")
	tracker.reconcile_step(level, [])
	_brush("e", Vector3(20, 0, 0))
	tracker.note_step(1, false, "Place Brush")
	tracker.reconcile_step(level, [])
	assert_true(tracker.owes_full_walk(), "e taken in, nothing else walked")
	assert_true(tracker._instances_by_id.has("e"))
