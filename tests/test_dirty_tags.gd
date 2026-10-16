extends GutTest

## Tests for the dirty-tag and signal-batching systems on LevelRoot.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")
const FaceDataType = preload("res://addons/hammerforge/face_data.gd")
const DraftEntity = preload("res://addons/hammerforge/draft_entity.gd")

# The real class. A copy of its dirty tags and signal batching used to live
# here, so these tests checked the copy (#922).
var root: LevelRoot


func before_each():
	root = LevelRootType.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)


func after_each():
	root = null


# -- Dirty Tags Tests ----------------------------------------------------------


func test_tag_brush_dirty():
	root.tag_brush_dirty("brush_1")
	root.tag_brush_dirty("brush_2")
	var tags = root.consume_dirty_tags()
	assert_eq(tags["brush_ids"].size(), 2, "Should have 2 dirty brushes")
	assert_true("brush_1" in tags["brush_ids"])
	assert_true("brush_2" in tags["brush_ids"])
	assert_false(tags["full"], "Should not be full reconcile")


func test_tag_brush_dirty_dedup():
	root.tag_brush_dirty("brush_1")
	root.tag_brush_dirty("brush_1")
	var tags = root.consume_dirty_tags()
	assert_eq(tags["brush_ids"].size(), 1, "Duplicate tag should not add twice")


## A level of its own, not in the tree, for the two tests that watch a signal
## from the first tag on.
func _real_level_root() -> Node3D:
	var level_root = LevelRootType.new()
	level_root.name = "RealLevelRoot"
	return level_root


func test_tag_brush_dirty_emits_brush_changed():
	# brush_changed was declared and never emitted. HFSubtractPreview connects
	# to it, so the preview listened to a signal that could not fire.
	var level_root := _real_level_root()
	var seen: Array = []
	level_root.brush_changed.connect(func(brush_id: String): seen.append(brush_id))
	level_root.tag_brush_dirty("b1")
	assert_eq(seen, ["b1"], "Tagging a brush dirty announces that brush changed")
	level_root.free()


func test_repeat_tags_keep_announcing():
	# The dirty set is not cleared until a bake, so a drag tags the same id on
	# every step. Announcing only the first would freeze a live preview.
	var level_root := _real_level_root()
	var seen: Array = []
	level_root.brush_changed.connect(func(brush_id: String): seen.append(brush_id))
	level_root.tag_brush_dirty("b1")
	level_root.tag_brush_dirty("b1")
	level_root.tag_brush_dirty("b2")
	assert_eq(seen, ["b1", "b1", "b2"], "Every tag is announced, not just new ids")
	assert_eq(level_root._dirty_brush_ids.size(), 2, "The dirty set still dedupes")
	level_root.free()


func test_tag_paint_dirty():
	root.tag_paint_dirty(Vector2i(0, 0))
	root.tag_paint_dirty(Vector2i(1, 1))
	var tags = root.consume_dirty_tags()
	assert_eq(tags["paint_chunks"].size(), 2, "Should have 2 dirty chunks")


func test_tag_paint_dirty_dedup():
	root.tag_paint_dirty(Vector2i(0, 0))
	root.tag_paint_dirty(Vector2i(0, 0))
	var tags = root.consume_dirty_tags()
	assert_eq(tags["paint_chunks"].size(), 1, "Duplicate chunk should not add twice")


func test_tag_full_reconcile():
	root.tag_full_reconcile()
	var tags = root.consume_dirty_tags()
	assert_true(tags["full"], "Should be full reconcile")


func test_consume_clears_tags():
	root.tag_brush_dirty("brush_1")
	root.tag_paint_dirty(Vector2i(0, 0))
	root.tag_full_reconcile()
	root.consume_dirty_tags()
	var tags2 = root.consume_dirty_tags()
	assert_eq(tags2["brush_ids"].size(), 0, "Should be empty after consume")
	assert_eq(tags2["paint_chunks"].size(), 0, "Should be empty after consume")
	assert_false(tags2["full"], "Should not be full after consume")


# -- Production mutation boundaries ------------------------------------------


func _make_production_root() -> LevelRoot:
	var production_root := LevelRootType.new()
	production_root.auto_spawn_player = false
	add_child_autoqfree(production_root)
	# A material slot has to name something in the palette, so the slot numbers
	# these tests use as markers need a palette deep enough to hold them.
	while production_root.get_materials().size() < 12:
		production_root.add_material_to_palette(StandardMaterial3D.new())
	return production_root


func _make_production_brush(production_root: LevelRoot, brush_id: String) -> DraftBrush:
	return (
		production_root.create_brush_from_info({"size": Vector3(8, 8, 8), "brush_id": brush_id})
		as DraftBrush
	)


func _consume_brush_ids(production_root: LevelRoot) -> Array:
	return production_root.consume_dirty_tags()["brush_ids"]


func test_serialized_brushes_bootstrap_unique_ids_live_index_and_committed_restore():
	var production_root := LevelRootType.new()
	production_root.auto_spawn_player = false
	production_root.hflevel_autosave_enabled = false
	var draft := Node3D.new()
	draft.name = "DraftBrushes"
	production_root.add_child(draft)
	var committed := Node3D.new()
	committed.name = "CommittedCuts"
	production_root.add_child(committed)

	var first := DraftBrush.new()
	first.shape = first.BrushShape.CUSTOM
	first.brush_id = "saved_7"
	first.set_meta("brush_id", "saved_7")
	var shared_face := FaceDataType.new()
	shared_face.local_verts = PackedVector3Array(
		[Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, 1)]
	)
	shared_face.ensure_geometry()
	first.faces = [shared_face]
	draft.add_child(first)
	var duplicate := DraftBrush.new()
	duplicate.shape = duplicate.BrushShape.CUSTOM
	duplicate.brush_id = "saved_7"
	duplicate.set_meta("brush_id", "saved_7")
	duplicate.faces = [shared_face]
	draft.add_child(duplicate)
	var frozen := DraftBrush.new()
	frozen.brush_id = "saved_7"
	frozen.set_meta("brush_id", "saved_7")
	committed.add_child(frozen)

	add_child_autoqfree(production_root)
	assert_eq(production_root.get_live_brush_count(), 2)
	assert_eq(production_root.brush_system.get_cached_brush_count(), 2)
	assert_eq(production_root.brush_manager.brushes.size(), 2)
	assert_ne(first.brush_id, duplicate.brush_id)
	assert_ne(first.brush_id, frozen.brush_id)
	assert_ne(duplicate.brush_id, frozen.brush_id)
	assert_not_same(first.faces[0], duplicate.faces[0])
	for brush in [first, duplicate, frozen]:
		assert_eq(str(brush.get_meta("brush_id", "")), brush.brush_id)
	assert_same(production_root.find_brush_by_id(first.brush_id), first)
	assert_same(production_root.find_brush_by_id(duplicate.brush_id), duplicate)
	assert_null(
		production_root.find_brush_by_id(frozen.brush_id),
		"Frozen committed cutters stay out of the editable live cache",
	)
	assert_true(production_root.consume_dirty_tags()["full"])

	production_root.restore_committed_cuts()
	assert_eq(production_root.get_live_brush_count(), 3)
	assert_eq(production_root.brush_system.get_cached_brush_count(), 3)
	assert_eq(production_root.brush_manager.brushes.size(), 3)
	assert_same(production_root.find_brush_by_id(frozen.brush_id), frozen)
	assert_eq(production_root.displacement_system._get_all_brushes().size(), 3)


func test_delete_brushes_by_id_emits_brush_removed_per_brush():
	var production_root := _make_production_root()
	_make_production_brush(production_root, "batch_a")
	_make_production_brush(production_root, "batch_b")
	var removed: Array = []
	production_root.brush_removed.connect(func(bid): removed.append(bid))
	production_root.delete_brushes_by_id(["batch_a", "batch_b"])
	assert_eq(removed, ["batch_a", "batch_b"], "Caches must be told which brushes went away")
	assert_eq(production_root.get_live_brush_count(), 0)
	assert_eq(production_root.brush_system.get_cached_brush_count(), 0)


func test_batched_flush_drops_exact_repeats():
	var production_root := _make_production_root()
	var changed: Array = []
	production_root.brush_changed.connect(func(bid): changed.append(bid))
	production_root.begin_signal_batch()
	production_root._emit_or_batch("brush_changed", ["a"])
	production_root._emit_or_batch("brush_changed", ["a"])
	production_root._emit_or_batch("brush_changed", ["b"])
	production_root.end_signal_batch()
	assert_eq(changed, ["a", "b"], "Repeat events for one brush collapse to one")


func test_batched_flush_keeps_signal_order():
	var production_root := _make_production_root()
	var seen: Array = []
	production_root.brush_added.connect(func(bid): seen.append("add:%s" % bid))
	production_root.brush_removed.connect(func(bid): seen.append("remove:%s" % bid))
	production_root.begin_signal_batch()
	production_root._emit_or_batch("brush_added", ["a"])
	production_root._emit_or_batch("brush_removed", ["a"])
	production_root._emit_or_batch("brush_added", ["b"])
	production_root.end_signal_batch()
	assert_eq(seen, ["add:a", "remove:a", "add:b"])


func test_nudge_and_override_material_tag_only_real_changes():
	var production_root := _make_production_root()
	var brush := _make_production_brush(production_root, "moving")
	_make_production_brush(production_root, "untouched")
	production_root.consume_dirty_tags()

	var start := brush.global_position
	var old_uv_offsets: Array[Vector2] = []
	for face in brush.faces:
		old_uv_offsets.append(face.uv_offset)
	production_root.nudge_brushes_by_id(["moving"], Vector3(2, 0, 0))
	assert_eq(brush.global_position, start + Vector3(2, 0, 0))
	assert_eq(_consume_brush_ids(production_root), ["moving"])
	var texture_lock_adjusted := false
	for index in range(brush.faces.size()):
		if not brush.faces[index].uv_offset.is_equal_approx(old_uv_offsets[index]):
			texture_lock_adjusted = true
			break
	assert_true(texture_lock_adjusted, "Nudge must flow through texture-lock adjustment")

	production_root.nudge_brushes_by_id(["moving"], Vector3.ZERO)
	assert_true(_consume_brush_ids(production_root).is_empty(), "Zero nudge is a no-op")

	var material := StandardMaterial3D.new()
	production_root.apply_material_to_brush_by_id("moving", material)
	assert_eq(_consume_brush_ids(production_root), ["moving"])
	production_root.apply_material_to_brush_by_id("moving", material)
	assert_true(
		_consume_brush_ids(production_root).is_empty(),
		"Reapplying the identical override must not dirty the brush",
	)


func test_face_material_entry_points_tag_exact_changed_brush():
	var production_root := _make_production_root()
	var first := _make_production_brush(production_root, "face_a")
	_make_production_brush(production_root, "face_b")
	production_root.consume_dirty_tags()

	production_root.assign_material_to_faces_by_id("face_a", [0], 4)
	assert_eq(_consume_brush_ids(production_root), ["face_a"])
	production_root.assign_material_to_faces_by_id("face_a", [0], 4)
	assert_true(_consume_brush_ids(production_root).is_empty())

	production_root.face_selection = {"face_a": [1]}
	assert_eq(production_root.assign_material_to_selected_faces(5), 1)
	assert_eq(_consume_brush_ids(production_root), ["face_a"])
	production_root.assign_material_to_selected_faces(5)
	assert_true(_consume_brush_ids(production_root).is_empty())

	production_root.assign_material_to_whole_brushes(6, ["face_b"])
	assert_eq(_consume_brush_ids(production_root), ["face_b"])
	assert_eq(first.faces[0].material_idx, 4, "Whole-brush assignment stayed scoped to face_b")

	production_root.face_selection = {"face_a": [2]}
	production_root.assign_material_and_reproject(7, FaceDataType.UVProjection.CYLINDRICAL)
	assert_eq(_consume_brush_ids(production_root), ["face_a"])


func test_face_uv_and_surface_paint_mutators_tag_exact_brush():
	var production_root := _make_production_root()
	var brush := _make_production_brush(production_root, "surface")
	production_root.consume_dirty_tags()
	var face = brush.faces[0]
	face.custom_uvs = PackedVector2Array()
	for _vertex in face.local_verts:
		face.custom_uvs.append(Vector2(99, 99))
	production_root.reset_uv_on_face("surface", 0)
	assert_eq(_consume_brush_ids(production_root), ["surface"])

	production_root.reproject_face_uvs("surface", 0, FaceDataType.UVProjection.CYLINDRICAL)
	assert_eq(_consume_brush_ids(production_root), ["surface"])
	production_root.set_face_uv_params("surface", 0, Vector2(2, 3), Vector2(0.25, 0.5), 30.0)
	assert_eq(_consume_brush_ids(production_root), ["surface"])
	production_root.face_selection = {"surface": [0]}
	production_root.justify_selected_faces("left", false)
	assert_eq(_consume_brush_ids(production_root), ["surface"])

	production_root.add_surface_paint_layer("surface", 0)
	assert_eq(_consume_brush_ids(production_root), ["surface"])
	var texture := ImageTexture.create_from_image(
		Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
	)
	production_root.set_surface_paint_layer_texture("surface", Vector2i(0, 0), texture)
	assert_eq(_consume_brush_ids(production_root), ["surface"])
	production_root.set_surface_paint_layer_texture("surface", Vector2i(0, 0), texture)
	assert_true(
		_consume_brush_ids(production_root).is_empty(),
		"Setting the same paint-layer texture is a no-op",
	)
	production_root.remove_surface_paint_layer("surface", 0, 0)
	assert_eq(_consume_brush_ids(production_root), ["surface"])


## A brush entity's properties and its tie decide what the bake makes of it, so
## the commands that set them tag the brushes, as every other command that changes
## what a brush bakes into does. Bake Changed otherwise kept the old door (#1198).
func test_entity_property_and_tie_commands_tag_every_brush_they_change():
	var production_root := _make_production_root()
	var leaf_a := _make_production_brush(production_root, "leaf_a")
	_make_production_brush(production_root, "leaf_b")
	_make_production_brush(production_root, "wall")
	production_root.consume_dirty_tags()

	production_root.tie_brushes_to_entity(["leaf_a", "leaf_b"], "func_door")
	assert_eq(_sorted(_consume_brush_ids(production_root)), ["leaf_a", "leaf_b"], "the tie")

	production_root.set_entity_property(leaf_a, "speed", 9.0)
	assert_eq(
		_sorted(_consume_brush_ids(production_root)),
		["leaf_a", "leaf_b"],
		"a property is set on every leaf of the door, so every leaf is rebaked",
	)
	production_root.set_entity_properties(leaf_a, {"locked": true, "wait": 1.0})
	assert_eq(_sorted(_consume_brush_ids(production_root)), ["leaf_a", "leaf_b"], "a preset")

	production_root.untie_brushes_from_entity(["leaf_a"])
	assert_eq(_consume_brush_ids(production_root), ["leaf_a"], "the untie")

	var point := DraftEntity.new()
	production_root.entities_node.add_child(point)
	production_root.set_entity_property(point, "health", 5)
	assert_true(_consume_brush_ids(production_root).is_empty(), "a point entity is no brush")


## Painted ground is baked from the floors, walls and terrain the paint layers
## generate, so every path that rebuilds them tags what it rebuilt. Nothing called
## `tag_paint_dirty()`, and Bake Changed kept the ground of the last full bake
## (#1199).
func test_paint_strokes_and_regenerates_tag_the_ground_they_rebuild():
	var production_root := _make_production_root()
	production_root.consume_dirty_tags()

	assert_gt(production_root.paint_tool.stamp_room_from_last_rect(Vector2i(0, 0)), 0)
	var tags := production_root.consume_dirty_tags()
	assert_false((tags["paint_chunks"] as Array).is_empty(), "a stroke tags its chunks")
	assert_true((tags["brush_ids"] as Array).is_empty(), "and no brush")

	production_root.paint_system.regenerate_paint_layers()
	tags = production_root.consume_dirty_tags()
	assert_false((tags["paint_chunks"] as Array).is_empty(), "a regenerate tags them all")
	assert_true(tags["full"], "and says the ground was rebuilt whole")

	production_root.paint_system.set_heightmap_scale(12.0)
	assert_true(production_root.consume_dirty_tags()["full"], "a new height scale")


## No edit to an entity tags anything. Bake Changed compares the props the navmesh
## is cut around with the last bake's instead (#1239), and a reopened level has no
## last bake to compare with, so a prop moved before its first bake is covered by
## the full reconcile the level tags as it opens. That has to hold for a level
## whose only sources are its props and their bake.
func test_a_reopened_level_with_only_props_and_a_bake_is_tagged_in_full():
	var reopened := LevelRootType.new()
	reopened.auto_spawn_player = false
	reopened.hflevel_autosave_enabled = false
	var entities := Node3D.new()
	entities.name = "Entities"
	reopened.add_child(entities)
	var prop := DraftEntity.new()
	prop.entity_type = "prop_static"
	entities.add_child(prop)
	var baked := Node3D.new()
	baked.name = "BakedGeometry"
	reopened.add_child(baked)

	add_child_autoqfree(reopened)

	assert_true(reopened.consume_dirty_tags()["full"])


func _sorted(values: Array) -> Array:
	var out := values.duplicate()
	out.sort()
	return out


func test_vertex_face_replay_tags_only_existing_brushes():
	var production_root := _make_production_root()
	var brush := _make_production_brush(production_root, "vertex")
	production_root.consume_dirty_tags()

	production_root._apply_vertex_faces(
		{"vertex": brush.serialize_faces(), "missing": brush.serialize_faces()}
	)
	assert_eq(_consume_brush_ids(production_root), ["vertex"])


func test_move_to_floor_updates_position_and_tags_exact_brush():
	var production_root := _make_production_root()
	production_root.grid_snap = 0.0
	(
		production_root
		. create_brush_from_info(
			{
				"size": Vector3(20, 2, 20),
				"center": Vector3.ZERO,
				"brush_id": "floor_target",
			}
		)
	)
	var moving := (
		(
			production_root
			. create_brush_from_info(
				{
					"size": Vector3(2, 2, 2),
					"center": Vector3(0, 10, 0),
					"brush_id": "floor_moving",
				}
			)
		)
		as DraftBrush
	)
	production_root.consume_dirty_tags()

	production_root.move_brushes_to_floor(["floor_moving"])
	assert_almost_eq(moving.global_position.y, 2.0, 0.001)
	assert_eq(_consume_brush_ids(production_root), ["floor_moving"])


func test_vertical_move_routes_through_transform_boundary():
	var source := FileAccess.get_file_as_string(
		"res://addons/hammerforge/systems/hf_brush_system.gd"
	)
	var start := source.find("func _move_brushes_vertical")
	var finish := source.find("func clip_brush_by_id", start)
	var method_source := source.substr(start, finish - start)
	assert_true(method_source.contains("set_brush_transform_by_id"))
	assert_false(
		method_source.contains("draft.global_position.y ="),
		"Floor/ceiling moves must preserve texture lock and dirty-tag handling",
	)


# -- Signal Batching Tests -----------------------------------------------------
# These test the batch queue and flush logic without relying on signal connections
# (lambdas in dynamic scripts can fail to capture outer variables).


func test_batch_queues_signals():
	root.begin_signal_batch()
	root._emit_or_batch("brush_removed", ["b1"])
	root._emit_or_batch("brush_removed", ["b2"])
	root._emit_or_batch("brush_removed", ["b3"])
	assert_eq(root._batched_signals.size(), 3, "Should have 3 queued signals during batch")


func test_batch_flushes_on_end():
	root.begin_signal_batch()
	root._emit_or_batch("brush_removed", ["b1"])
	root._emit_or_batch("brush_removed", ["b2"])
	root.end_signal_batch()
	assert_eq(root._batched_signals.size(), 0, "Should be empty after flush")
	assert_eq(root._signal_batch_depth, 0, "Depth should return to 0")


func test_no_batch_does_not_queue():
	# Outside of batch, signals should not be queued
	root._emit_or_batch("brush_added", ["b1"])
	assert_eq(root._batched_signals.size(), 0, "Should not queue outside batch")


func test_discard_batch():
	root.begin_signal_batch()
	root._emit_or_batch("brush_removed", ["b1"])
	root.discard_signal_batch()
	assert_eq(root._batched_signals.size(), 0, "Should be empty after discard")
	assert_eq(root._signal_batch_depth, 0, "Depth should be 0 after discard")


func test_nested_batch_depth():
	root.begin_signal_batch()
	root.begin_signal_batch()
	root._emit_or_batch("brush_added", ["b1"])
	root.end_signal_batch()
	# Inner end should not flush yet
	assert_eq(root._signal_batch_depth, 1, "Depth should be 1 after inner end")
	assert_eq(root._batched_signals.size(), 1, "Should still have queued signal")
	root.end_signal_batch()
	assert_eq(root._signal_batch_depth, 0, "Depth should be 0 after outer end")
	assert_eq(root._batched_signals.size(), 0, "Should be flushed after outer end")


# ===========================================================================
# Entity lifecycle signals (#150)
# ===========================================================================


func test_add_entity_emits_entity_added():
	var production_root := _make_production_root()
	var added: Array = []
	production_root.entity_added.connect(func(node): added.append(node))
	var entity := DraftEntity.new()
	production_root.entity_system.add_entity(entity)
	assert_eq(added.size(), 1, "Placing an entity has to announce it")
	assert_same(added[0], entity)


func test_restore_entity_from_info_emits_entity_added():
	var production_root := _make_production_root()
	var added: Array = []
	production_root.entity_added.connect(func(node): added.append(node))
	var restored := production_root.entity_system.restore_entity_from_info(
		{"name": "Light", "entity_type": "light_point"}
	)
	assert_not_null(restored)
	assert_eq(added.size(), 1, "Undo and load restore entities through the same contract")


func test_delete_entities_by_paths_emits_entity_removed():
	var production_root := _make_production_root()
	var entity := DraftEntity.new()
	entity.name = "Doomed"
	production_root.entity_system.add_entity(entity)
	var removed: Array = []
	production_root.entity_removed.connect(func(node): removed.append(node))
	production_root.entity_system.delete_entities_by_paths([entity.get_path()])
	assert_eq(removed.size(), 1, "Deleting an entity has to announce it")
	assert_same(removed[0], entity)


func test_clear_entities_emits_entity_removed_for_each():
	var production_root := _make_production_root()
	var first := DraftEntity.new()
	var second := DraftEntity.new()
	production_root.entity_system.add_entity(first)
	production_root.entity_system.add_entity(second)
	var removed: Array = []
	production_root.entity_removed.connect(func(node): removed.append(node))
	production_root.entity_system.clear_entities()
	assert_eq(removed.size(), 2)


func test_entity_removed_fires_while_the_node_is_still_valid():
	var production_root := _make_production_root()
	var entity := DraftEntity.new()
	entity.name = "StillHere"
	production_root.entity_system.add_entity(entity)
	var names: Array = []
	production_root.entity_removed.connect(
		func(node): names.append(str(node.name) if is_instance_valid(node) else "<freed>")
	)
	production_root.entity_system.delete_entities_by_paths([entity.get_path()])
	assert_eq(names, ["StillHere"], "Listeners need a live node to clean up against")


func test_batched_entity_signals_flush_on_batch_end():
	var production_root := _make_production_root()
	var added: Array = []
	production_root.entity_added.connect(func(node): added.append(node))
	production_root.begin_signal_batch()
	production_root.entity_system.add_entity(DraftEntity.new())
	production_root.entity_system.add_entity(DraftEntity.new())
	assert_eq(added.size(), 0, "Batched adds wait for the flush")
	production_root.end_signal_batch()
	assert_eq(added.size(), 2, "Two distinct entities are two events")


func test_deleting_a_brush_with_a_selected_face_reports_face_selection_changed():
	var production_root := _make_production_root()
	var brush := _make_production_brush(production_root, "faced")
	production_root.face_selection[production_root.brush_system.face_key(brush)] = [0]
	var face_emits: Array = []
	production_root.face_selection_changed.connect(func(): face_emits.append(true))
	production_root.delete_brushes_by_id(["faced"])
	assert_eq(
		face_emits.size(), 1, "The surface panel is still pointed at a face that just went away"
	)


func test_deleting_a_brush_with_no_selected_face_stays_quiet():
	var production_root := _make_production_root()
	_make_production_brush(production_root, "plain")
	var face_emits: Array = []
	production_root.face_selection_changed.connect(func(): face_emits.append(true))
	production_root.delete_brushes_by_id(["plain"])
	assert_eq(face_emits.size(), 0, "Nothing the surface panel cares about changed")
