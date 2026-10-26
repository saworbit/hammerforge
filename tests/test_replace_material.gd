extends GutTest

## Replace Material (#1726): the grey prototype wall swapped for the plaster on
## every face that wears it, in one pass, rather than face by face.

const HFUndoHelper = preload("res://addons/hammerforge/undo_helper.gd")
const UndoStandIn = preload("res://tests/mcp/mcp_undo_stand_in.gd")
const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")
const HFMaterialUse = preload("res://addons/hammerforge/hf_material_use.gd")
const HFReplaceMaterialDialog = preload("res://addons/hammerforge/ui/hf_replace_material_dialog.gd")

const GREY := 1
const PLASTER := 2
const TRIM := 3

var level: LevelRoot


func before_each() -> void:
	level = LevelRootType.new()
	level.auto_spawn_player = false
	level.commit_freeze = false
	level.hflevel_autosave_enabled = false
	add_child_autoqfree(level)
	level.add_prototype_materials()
	# a: all grey. b: three faces grey, three trim. c: all trim.
	_box("a", Vector3.ZERO, [GREY, GREY, GREY, GREY, GREY, GREY])
	_box("b", Vector3(5, 0, 0), [GREY, GREY, GREY, TRIM, TRIM, TRIM])
	_box("c", Vector3(10, 0, 0), [TRIM, TRIM, TRIM, TRIM, TRIM, TRIM])
	level.clear_face_selection()


func after_each() -> void:
	level = null


func _box(brush_id: String, at: Vector3, slots: Array) -> DraftBrush:
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
	for i in slots.size():
		brush.faces[i].material_idx = slots[i]
	return brush


func _slots(brush_id: String) -> Array:
	var out: Array = []
	for face in level.find_brush_by_id(brush_id).faces:
		out.append(face.material_idx)
	return out


func test_across_the_level_every_face_that_wears_it_changes_and_no_other():
	var changed := level.replace_material(GREY, PLASTER)
	assert_eq(_slots("a"), [PLASTER, PLASTER, PLASTER, PLASTER, PLASTER, PLASTER])
	assert_eq(_slots("b"), [PLASTER, PLASTER, PLASTER, TRIM, TRIM, TRIM], "trim stays trim")
	assert_eq(_slots("c"), [TRIM, TRIM, TRIM, TRIM, TRIM, TRIM])
	assert_eq(changed, {"a": [0, 1, 2, 3, 4, 5], "b": [0, 1, 2]})


func test_the_selection_scope_changes_only_the_selected_faces_and_brushes():
	level.replace_material(GREY, PLASTER, {"faces": {"a": [0, 4]}, "brush_ids": ["b"]})
	assert_eq(_slots("a"), [PLASTER, GREY, GREY, GREY, PLASTER, GREY], "the two picked faces")
	assert_eq(_slots("b"), [PLASTER, PLASTER, PLASTER, TRIM, TRIM, TRIM], "the whole brush")


func test_shown_only_leaves_a_hidden_brush_alone():
	level.add_selection_to_visgroup("hidden", [level.find_brush_by_id("b")])
	level.set_visgroup_visible("hidden", false)
	level.replace_material(GREY, PLASTER, {"visible_only": true})
	assert_eq(_slots("a")[0], PLASTER)
	assert_eq(_slots("b"), [GREY, GREY, GREY, TRIM, TRIM, TRIM], "hidden, so kept")


func test_the_faces_keep_their_uvs_unless_reset_is_asked_for():
	var face: FaceData = level.find_brush_by_id("a").faces[0]
	face.uv_scale = Vector2(2, 3)
	face.uv_offset = Vector2(0.5, 0.25)
	face.uv_rotation = 45.0
	level.replace_material(GREY, PLASTER)
	assert_eq(face.uv_scale, Vector2(2, 3), "kept")
	assert_eq(face.uv_offset, Vector2(0.5, 0.25))
	assert_eq(face.uv_rotation, 45.0)
	level.replace_material(PLASTER, TRIM, {}, true)
	assert_eq(face.material_idx, TRIM)
	assert_eq(face.uv_scale, Vector2.ONE, "reset")
	assert_eq(face.uv_offset, Vector2.ZERO)
	assert_eq(face.uv_rotation, 0.0)


func test_the_replaced_faces_become_the_face_selection():
	watch_signals(level)
	level.replace_material(GREY, PLASTER)
	assert_eq(level.face_selection, {"a": [0, 1, 2, 3, 4, 5], "b": [0, 1, 2]})
	assert_signal_emitted(level, "face_selection_changed")


func test_replacing_with_the_same_material_or_a_missing_slot_does_nothing():
	assert_eq(level.replace_material(GREY, GREY), {})
	assert_eq(level.replace_material(GREY, 9999), {}, "no such slot")
	assert_eq(_slots("a")[0], GREY)


func test_one_undo_step_puts_every_face_back():
	var undo := UndoStandIn.new()
	var scope_ids: Array = level.faces_wearing_material(GREY).keys()
	var changed := HFUndoHelper.commit_if_changed(
		undo,
		level,
		"Replace Material",
		"replace_material",
		[GREY, PLASTER, {}, false],
		Callable(),
		scope_ids
	)
	assert_true(changed, "a step")
	assert_eq(undo.scene_history.get_history_count(), 1, "one step")
	assert_eq(_slots("a")[0], PLASTER)
	undo.scene_history.undo()
	assert_eq(_slots("a"), [GREY, GREY, GREY, GREY, GREY, GREY], "a back")
	assert_eq(_slots("b"), [GREY, GREY, GREY, TRIM, TRIM, TRIM], "and b")
	undo.scene_history.redo()
	assert_eq(_slots("b")[0], PLASTER, "and redone")
	undo.free_histories()


func test_a_committed_cut_s_faces_change_but_are_not_picked():
	var cut := _box("cut", Vector3(0, 0, 5), [GREY, GREY, GREY, GREY, GREY, GREY])
	cut.operation = CSGShape3D.OPERATION_SUBTRACTION
	level.brush_system._stash_committed_cut(cut)
	assert_eq(cut.get_parent(), level.committed_node, "fixture: a committed cut")
	level.replace_material(GREY, PLASTER)
	assert_eq(cut.faces[0].material_idx, PLASTER, "the cut's interior takes it too")
	assert_false(level.face_selection.has("cut"), "but a hidden cut's faces are not picked")


## What Replace Material finds is what it changes: a brush a locked visgroup
## holds is left out of both, so the count and the highlight the dialog shows
## match the faces Replace changes (#1936).
func test_a_locked_brush_is_neither_found_nor_changed():
	level.visgroup_system.create_visgroup("Locked")
	level.visgroup_system.add_to_visgroup(level.find_brush_by_id("a"), "Locked")
	level.visgroup_system.set_visgroup_locked("Locked", true)
	var found: Dictionary = level.faces_wearing_material(GREY, {})
	assert_false(found.has("a"), "the locked brush is not found")
	assert_eq(found.get("b", []), [0, 1, 2], "the others are")
	level.replace_material(GREY, PLASTER)
	assert_eq(_slots("a"), [GREY, GREY, GREY, GREY, GREY, GREY], "and it is not changed")


## The counts beside each material, in the browser and in the Replace dialog
## alike, take in a committed cut's faces, which Replace changes and Remove Unused
## keeps a material for (#1936).
func test_the_counts_take_in_a_committed_cut_as_replace_does():
	var cut := _box("cut", Vector3(0, 0, 5), [GREY, GREY, GREY, GREY, GREY, GREY])
	cut.operation = CSGShape3D.OPERATION_SUBTRACTION
	level.brush_system._stash_committed_cut(cut)
	var counts: Dictionary = HFMaterialUse.counts(level)
	assert_eq(int(counts.get(GREY, 0)), 6 + 3 + 6, "a's, b's and the cut's grey faces")
	assert_eq(HFReplaceMaterialDialog.use_counts(level), counts, "the dialog counts the same")
