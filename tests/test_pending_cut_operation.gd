extends GutTest

## A cut waiting for Apply stays a cut until it is applied (#1551).
##
## Its undo record, the `.hflevel`, Apply and the bake all read a brush in the
## pending container as a cut, and the bake leaves the container out. The
## Inspector could still set its Operation to Union, and since #1547 it then drew
## as a solid: the next undo step or `.hflevel` load brought it back as a cut,
## Apply applied it as one, and the bake built nothing for it. So the Inspector
## shows Operation read-only on a pending cut, and a scene saved with one set to
## Union opens with it a cut again.

const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")
const CollationTests = preload("res://tests/test_undo_collation.gd")

const SCENE_PATH := "user://test_pending_cut_operation.tscn"
const LEVEL_PATH := "user://test_pending_cut_operation.hflevel"

var root: LevelRoot


func before_each():
	root = _fresh_root()


func after_each():
	root = null
	for path in [SCENE_PATH, LEVEL_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _fresh_root() -> LevelRoot:
	var level := LevelRoot.new()
	level.auto_spawn_player = false
	level.hflevel_autosave_enabled = false
	add_child_autoqfree(level)
	return level


func _cut() -> DraftBrush:
	return (
		(
			root
			. create_brush_from_info(
				{
					"shape": LevelRoot.BrushShape.BOX,
					"size": Vector3(2, 2, 2),
					"center": Vector3.ZERO,
					"operation": CSGShape3D.OPERATION_SUBTRACTION,
					"pending": true,
				}
			)
		)
		as DraftBrush
	)


## Whether the Inspector shows `brush`'s Operation read-only.
func _operation_read_only(brush: DraftBrush) -> bool:
	for property in brush.get_property_list():
		if property.get("name", "") == "operation":
			return (int(property.get("usage", 0)) & PROPERTY_USAGE_READ_ONLY) != 0
	fail_test("DraftBrush exports no operation")
	return false


func _colour(brush: DraftBrush) -> Color:
	var drawn := brush.mesh_instance.get_active_material(0) as StandardMaterial3D
	assert_not_null(drawn, "fixture: %s is drawn with a material" % brush.name)
	return drawn.albedo_color if drawn else Color.BLACK


func _pending_colour() -> Color:
	return DraftBrush.pending_cut_look().albedo_color


func _only_child(container: Node) -> DraftBrush:
	var found: Array = container.get_children().filter(func(child): return child is DraftBrush)
	assert_eq(found.size(), 1, "fixture: one brush in %s" % container.name)
	return found[0] if not found.is_empty() else null


## Save the level the way Ctrl+S does, and open the file again.
func _save_and_reopen() -> LevelRoot:
	var stack: Array = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			child.owner = root
			stack.append(child)
	var packed := PackedScene.new()
	assert_eq(packed.pack(root), OK, "the level packs")
	assert_eq(ResourceSaver.save(packed, SCENE_PATH), OK, "the scene saves")
	var loaded := (
		ResourceLoader.load(SCENE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	)
	var copy := loaded.instantiate() as LevelRoot
	add_child_autoqfree(copy)
	return copy


## What the level would make of `brush` on the next undo step or load.
func _recorded_as_a_pending_cut(level: LevelRoot, brush: DraftBrush) -> bool:
	var info: Dictionary = level.get_brush_info_from_node(brush)
	return (
		bool(info.get("pending", false))
		and int(info.get("operation", -1)) == CSGShape3D.OPERATION_SUBTRACTION
	)


func test_the_inspector_shows_a_pending_cut_s_operation_read_only():
	var cut := _cut()
	assert_true(cut.is_pending_cut(), "fixture: a pending cut")
	assert_true(_operation_read_only(cut))


func test_a_solid_s_operation_and_an_applied_cut_s_stay_editable():
	var solid := (
		root.create_brush_from_info({"shape": LevelRoot.BrushShape.BOX, "size": Vector3(2, 2, 2)})
		as DraftBrush
	)
	assert_false(_operation_read_only(solid), "a solid")
	var cut := _cut()
	root.apply_pending_cuts()
	assert_false(_operation_read_only(cut), "a cut once applied")


## The Inspector reads the property list again only when told to.
func test_apply_tells_the_inspector_the_operation_is_editable_again():
	var cut := _cut()
	watch_signals(cut)
	root.apply_pending_cuts()
	assert_signal_emitted(cut, "property_list_changed")


## As the load below does, and an undo that puts an older operation back.
func test_an_operation_that_makes_a_brush_a_pending_cut_or_not_tells_the_inspector():
	var cut := _cut()
	watch_signals(cut)
	cut.operation = CSGShape3D.OPERATION_UNION
	assert_signal_emit_count(cut, "property_list_changed", 1, "no longer a pending cut")
	cut.operation = CSGShape3D.OPERATION_UNION
	assert_signal_emit_count(cut, "property_list_changed", 1, "the same operation again")
	cut.operation = CSGShape3D.OPERATION_SUBTRACTION
	assert_signal_emit_count(cut, "property_list_changed", 2, "a pending cut again")


## The step the Apply button, a bake and the bridge all record.
func test_undo_of_an_apply_makes_the_operation_read_only_again_and_redo_editable():
	_cut()
	var undo := CollationTests.FakeUndoRedo.new()
	assert_true(HFUndoHelper.apply_pending_cuts_step(undo, root), "fixture: a step")
	assert_false(_operation_read_only(_only_child(root.draft_brushes_node)), "applied")
	undo.undo()
	var pending := _only_child(root.pending_node)
	assert_true(pending.is_pending_cut(), "undone: pending again")
	assert_true(_operation_read_only(pending), "and read-only")
	undo.redo()
	assert_false(_operation_read_only(_only_child(root.draft_brushes_node)), "redone: editable")


## An applied cut turned into a solid is a solid in everything that reads it.
func test_an_applied_cut_turned_into_a_solid_is_saved_and_kept_as_one():
	var cut := _cut()
	root.apply_pending_cuts()
	cut.operation = CSGShape3D.OPERATION_UNION
	var info: Dictionary = root.get_brush_info_from_node(cut)
	assert_eq(int(info["operation"]), CSGShape3D.OPERATION_UNION, "recorded as a solid")
	assert_false(bool(info["pending"]), "not as a pending cut")
	assert_eq(HFLevelIO.save_to_path(LEVEL_PATH, root._capture_hflevel_state()), OK)
	assert_true(root.load_hflevel(LEVEL_PATH), "the level loads")
	var loaded := _only_child(root.draft_brushes_node)
	assert_eq(loaded.operation, CSGShape3D.OPERATION_UNION, "a solid after the load")
	assert_eq(root.pending_node.get_child_count(), 0, "nothing pending")


## A scene saved while the Inspector could still set a pending cut to Union: the
## issue's steps, as the file holds them.
func test_a_scene_saved_with_a_pending_cut_set_to_union_opens_with_a_cut():
	var cut := _cut()
	cut.operation = CSGShape3D.OPERATION_UNION
	var reopened := _save_and_reopen()
	var loaded := _only_child(reopened.pending_node)
	assert_eq(loaded.operation, CSGShape3D.OPERATION_SUBTRACTION, "a cut, as its container says")
	assert_true(loaded.is_pending_cut(), "waiting for Apply")
	assert_eq(_colour(loaded), _pending_colour(), "and drawn as one")
	assert_true(_operation_read_only(loaded), "with Operation read-only")
	assert_true(_recorded_as_a_pending_cut(reopened, loaded), "recorded as one for undo")
	reopened.apply_pending_cuts()
	assert_eq(loaded.get_parent(), reopened.draft_brushes_node, "applied")
	assert_eq(loaded.operation, CSGShape3D.OPERATION_SUBTRACTION, "as the cut it was drawn as")


func test_a_pending_cut_saved_in_a_scene_opens_as_one():
	_cut()
	var reopened := _save_and_reopen()
	var loaded := _only_child(reopened.pending_node)
	assert_true(loaded.is_pending_cut())
	assert_true(_operation_read_only(loaded))
	assert_eq(_colour(loaded), _pending_colour())


func test_a_pending_cut_loaded_from_an_hflevel_is_read_only():
	_cut()
	assert_eq(HFLevelIO.save_to_path(LEVEL_PATH, root._capture_hflevel_state()), OK)
	assert_true(root.load_hflevel(LEVEL_PATH), "the level loads")
	var loaded := _only_child(root.pending_node)
	assert_true(loaded.is_pending_cut())
	assert_true(_operation_read_only(loaded))
	assert_eq(_colour(loaded), _pending_colour())


## An undo of a later step puts the level back from a snapshot.
func test_a_pending_cut_put_back_by_an_undo_is_read_only():
	var cut := _cut()
	var snapshot: Dictionary = root.capture_state()
	assert_true(_recorded_as_a_pending_cut(root, cut), "fixture: recorded as a pending cut")
	root.delete_brush(cut)
	root.restore_state(snapshot)
	var restored := _only_child(root.pending_node)
	assert_true(restored.is_pending_cut())
	assert_true(_operation_read_only(restored))
	assert_eq(_colour(restored), _pending_colour())


# ===========================================================================
# Cutting, hollowing and merging a pending cut keep it pending (#1943)
# ===========================================================================


func _pending_cut_at(brush_id: String, center: Vector3) -> DraftBrush:
	return (
		(
			root
			. create_brush_from_info(
				{
					"shape": LevelRoot.BrushShape.BOX,
					"size": Vector3(2, 2, 2),
					"center": center,
					"operation": CSGShape3D.OPERATION_SUBTRACTION,
					"pending": true,
					"brush_id": brush_id,
				}
			)
		)
		as DraftBrush
	)


## Splitting a pending cut leaves both halves waiting for Apply. The pieces went
## into the level's brushes, applied without Apply being pressed.
func test_a_pending_cut_split_in_two_stays_pending():
	_pending_cut_at("cut", Vector3.ZERO)
	var result: HFOpResult = root.clip_brush_by_id("cut", 0, 0.0)
	assert_true(result.ok, result.message)
	var pieces: Array = root.pending_node.get_children()
	assert_eq(pieces.size(), 2, "both halves wait in Pending Cuts")
	for piece in pieces:
		assert_true(piece.is_pending_cut(), "as pending cuts")
	assert_eq(root.draft_brushes_node.get_child_count(), 0, "and none is applied")


func test_a_hollowed_pending_cut_stays_pending():
	_pending_cut_at("cut", Vector3.ZERO)
	var result: HFOpResult = root.hollow_brush_by_id("cut", 0.25)
	assert_true(result.ok, result.message)
	assert_gt(root.pending_node.get_child_count(), 1, "its walls wait in Pending Cuts")
	assert_eq(root.draft_brushes_node.get_child_count(), 0, "and none is applied")


## Two pending cuts merge into one pending cut, and a pending cut does not merge
## with an applied one.
func test_merged_pending_cuts_stay_pending_and_do_not_mix_with_applied_ones():
	_pending_cut_at("a", Vector3.ZERO)
	_pending_cut_at("b", Vector3(2, 0, 0))
	var merged: HFOpResult = root.merge_brushes_by_ids(["a", "b"])
	assert_true(merged.ok, merged.message)
	assert_eq(root.pending_node.get_child_count(), 1, "one cut")
	assert_true((root.pending_node.get_child(0) as DraftBrush).is_pending_cut(), "still pending")
	assert_eq(root.draft_brushes_node.get_child_count(), 0, "not applied")

	var applied: DraftBrush = (
		(
			root
			. create_brush_from_info(
				{
					"shape": LevelRoot.BrushShape.BOX,
					"size": Vector3(2, 2, 2),
					"center": Vector3(-2, 0, 0),
					"operation": CSGShape3D.OPERATION_SUBTRACTION,
					"brush_id": "applied",
				}
			)
		)
		as DraftBrush
	)
	assert_false(applied.is_pending_cut(), "fixture: an applied cut")
	var pending_id := str((root.pending_node.get_child(0) as DraftBrush).brush_id)
	var mixed: HFOpResult = root.can_merge_brushes([pending_id, "applied"])
	assert_false(mixed.ok, "a pending and an applied cut do not merge")
	assert_string_contains(mixed.message, "pending")
