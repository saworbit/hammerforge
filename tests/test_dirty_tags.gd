extends GutTest

## Tests for the dirty-tag and signal-batching systems on LevelRoot.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")
const FaceDataType = preload("res://addons/hammerforge/face_data.gd")

# Use a lightweight shim to avoid full LevelRoot initialization
var root_script: GDScript
var root: Node3D


func before_each():
	root_script = GDScript.new()
	root_script.source_code = """
@tool
extends Node3D

var drag_size_default := Vector3(32, 32, 32)
var grid_snap := 16.0

# Dirty tags
var _dirty_brush_ids: Dictionary = {}
var _dirty_paint_chunks: Array[Vector2i] = []
var _full_reconcile_needed := false

func tag_brush_dirty(brush_id: String) -> void:
	_dirty_brush_ids[brush_id] = true

func tag_paint_dirty(chunk_coord: Vector2i) -> void:
	if not _dirty_paint_chunks.has(chunk_coord):
		_dirty_paint_chunks.append(chunk_coord)

func tag_full_reconcile() -> void:
	_full_reconcile_needed = true

func consume_dirty_tags() -> Dictionary:
	var result := {
		"brush_ids": _dirty_brush_ids.keys(),
		"paint_chunks": _dirty_paint_chunks.duplicate(),
		"full": _full_reconcile_needed,
	}
	_dirty_brush_ids.clear()
	_dirty_paint_chunks.clear()
	_full_reconcile_needed = false
	return result

# Signal batching
var _signal_batch_depth := 0
var _batched_signals: Array = []

signal brush_added(brush_id: String)
signal brush_removed(brush_id: String)
signal brush_changed(brush_id: String)
signal selection_changed(brush_ids: Array)

func begin_signal_batch() -> void:
	_signal_batch_depth += 1

func end_signal_batch() -> void:
	_signal_batch_depth -= 1
	if _signal_batch_depth <= 0:
		_signal_batch_depth = 0
		_flush_batched_signals()

func _emit_or_batch(signal_name: String, args: Array = []) -> void:
	if _signal_batch_depth > 0:
		_batched_signals.append({"name": signal_name, "args": args})
	else:
		_emit_signal_by_name(signal_name, args)

func _flush_batched_signals() -> void:
	var brush_ids_changed: Array = []
	var other_signals: Array = []
	for entry in _batched_signals:
		var sname: String = entry.get("name", "")
		if sname in ["brush_added", "brush_removed", "brush_changed"]:
			var bid = entry.get("args", [])
			if not bid.is_empty():
				brush_ids_changed.append(bid[0])
		else:
			other_signals.append(entry)
	_batched_signals.clear()
	if not brush_ids_changed.is_empty():
		selection_changed.emit(brush_ids_changed)
	for entry in other_signals:
		_emit_signal_by_name(entry.get("name", ""), entry.get("args", []))

func discard_signal_batch() -> void:
	_batched_signals.clear()
	_signal_batch_depth = 0

func _emit_signal_by_name(signal_name: String, args: Array) -> void:
	match args.size():
		0: emit_signal(signal_name)
		1: emit_signal(signal_name, args[0])
		2: emit_signal(signal_name, args[0], args[1])
		3: emit_signal(signal_name, args[0], args[1], args[2])
"""
	root_script.reload()
	root = Node3D.new()
	root.set_script(root_script)
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


func test_delete_brushes_by_id_coalesces_selection_changed():
	var production_root := _make_production_root()
	_make_production_brush(production_root, "batch_a")
	_make_production_brush(production_root, "batch_b")
	var selection_emits: Array = []
	production_root.selection_changed.connect(func(ids): selection_emits.append(ids))
	production_root.delete_brushes_by_id(["batch_a", "batch_b"])
	assert_eq(selection_emits.size(), 1, "Multi-brush delete must not storm the dock")
	assert_eq(production_root.get_live_brush_count(), 0)
	assert_eq(production_root.brush_system.get_cached_brush_count(), 0)


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
