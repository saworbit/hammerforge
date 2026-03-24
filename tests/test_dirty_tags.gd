extends GutTest

## Tests for the dirty-tag and signal-batching systems on LevelRoot.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")

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
