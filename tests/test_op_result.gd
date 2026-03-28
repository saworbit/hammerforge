extends GutTest

const HFBrushSystem = preload("res://addons/hammerforge/systems/hf_brush_system.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")

var root: Node3D
var sys: HFBrushSystem


func before_each():
	root = Node3D.new()
	root.set_script(_root_shim_script())
	add_child_autoqfree(root)
	var draft = Node3D.new()
	draft.name = "DraftBrushes"
	root.add_child(draft)
	root.draft_brushes_node = draft
	root.pending_node = null
	root.committed_node = null
	root._brush_id_counter = 0
	root.grid_snap = 0.0
	root.face_selection = {}
	root.brush_manager = null
	sys = HFBrushSystem.new(root)


func after_each():
	root = null
	sys = null


func _root_shim_script() -> GDScript:
	var s = GDScript.new()
	s.source_code = """
extends Node3D

signal user_message(text: String, level: int)

var draft_brushes_node: Node3D
var pending_node: Node3D
var committed_node: Node3D
var _brush_id_counter: int = 0
var grid_snap: float = 0.0
var face_selection: Dictionary = {}
var brush_manager = null
var texture_lock: bool = false
var drag_size_default: Vector3 = Vector3(32, 32, 32)

enum BrushShape { BOX, CYLINDER, SPHERE, CONE, WEDGE, PYRAMID, PRISM_TRI, PRISM_PENT, ELLIPSOID, CAPSULE, TORUS, TETRAHEDRON, OCTAHEDRON, DODECAHEDRON, ICOSAHEDRON, CUSTOM }

func _iter_pick_nodes() -> Array:
	var out: Array = []
	if draft_brushes_node:
		out.append_array(draft_brushes_node.get_children())
	return out

func is_entity_node(_node: Node) -> bool:
	return false

func _log(msg: String) -> void:
	pass

func _assign_owner(node: Node) -> void:
	pass

func _record_last_brush(_pos: Vector3) -> void:
	pass

func tag_full_reconcile() -> void:
	pass
"""
	s.reload()
	return s


func _make_brush(
	pos: Vector3 = Vector3.ZERO, sz: Vector3 = Vector3(32, 32, 32), brush_id: String = ""
) -> DraftBrush:
	var b = DraftBrush.new()
	b.size = sz
	if brush_id == "":
		root._brush_id_counter += 1
		brush_id = "test_%d" % root._brush_id_counter
	b.brush_id = brush_id
	b.set_meta("brush_id", brush_id)
	root.draft_brushes_node.add_child(b)
	b.global_position = pos
	sys._register_brush_id(brush_id, b)
	return b


# ===========================================================================
# HFOpResult constructors
# ===========================================================================


func test_success_is_ok():
	var r = HFOpResult.success("done")
	assert_true(r.ok)
	assert_eq(r.message, "done")


func test_fail_is_not_ok():
	var r = HFOpResult.fail("bad", "try this")
	assert_false(r.ok)
	assert_eq(r.message, "bad")
	assert_eq(r.fix_hint, "try this")


func test_success_default_message():
	var r = HFOpResult.success()
	assert_true(r.ok)
	assert_eq(r.message, "")


# ===========================================================================
# Hollow returns HFOpResult
# ===========================================================================


func test_hollow_success_returns_ok():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	var r = sys.hollow_brush_by_id("b1", 2.0)
	assert_true(r.ok)
	assert_true(r.message.contains("6 walls"))


func test_hollow_bad_thickness_returns_fail():
	_make_brush(Vector3.ZERO, Vector3(10, 10, 10), "b2")
	var r = sys.hollow_brush_by_id("b2", 6.0)
	assert_false(r.ok)
	assert_true(r.fix_hint.length() > 0, "Should provide fix hint")


func test_hollow_missing_brush_returns_fail():
	var r = sys.hollow_brush_by_id("nonexistent", 2.0)
	assert_false(r.ok)


func test_hollow_empty_id_returns_fail():
	var r = sys.hollow_brush_by_id("", 2.0)
	assert_false(r.ok)


# ===========================================================================
# Clip returns HFOpResult
# ===========================================================================


func test_clip_success_returns_ok():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "c1")
	var r = sys.clip_brush_by_id("c1", 1, 0.0)
	assert_true(r.ok)
	assert_true(r.message.contains("2 pieces"))


func test_clip_outside_bounds_returns_fail():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "c2")
	var r = sys.clip_brush_by_id("c2", 1, 100.0)
	assert_false(r.ok)
	assert_true(r.fix_hint.length() > 0, "Should provide fix hint")


func test_clip_missing_brush_returns_fail():
	var r = sys.clip_brush_by_id("nonexistent", 0, 0.0)
	assert_false(r.ok)


# ===========================================================================
# Delete returns HFOpResult
# ===========================================================================


func test_delete_success_returns_ok():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "d1")
	var r = sys.delete_brush_by_id("d1")
	assert_true(r.ok)


func test_delete_missing_returns_fail():
	var r = sys.delete_brush_by_id("nonexistent")
	assert_false(r.ok)


func test_delete_empty_id_returns_fail():
	var r = sys.delete_brush_by_id("")
	assert_false(r.ok)


# ===========================================================================
# Failure emits user_message signal
# ===========================================================================


func test_fail_emits_user_message():
	var received := []
	root.user_message.connect(func(text, level): received.append({"text": text, "level": level}))
	sys.hollow_brush_by_id("nonexistent", 2.0)
	assert_eq(received.size(), 1, "Should emit one user_message")
	assert_eq(received[0]["level"], 1, "Should be WARNING level")


# ===========================================================================
# Pre-validation: can_hollow_brush / can_clip_brush
# ===========================================================================


func test_can_hollow_valid_returns_ok():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "vh1")
	var r = sys.can_hollow_brush("vh1", 2.0)
	assert_true(r.ok)


func test_can_hollow_bad_thickness_returns_fail():
	_make_brush(Vector3.ZERO, Vector3(10, 10, 10), "vh2")
	var r = sys.can_hollow_brush("vh2", 6.0)
	assert_false(r.ok)
	assert_true(r.fix_hint.length() > 0, "Should provide fix hint")


func test_can_hollow_missing_brush_returns_fail():
	var r = sys.can_hollow_brush("nonexistent", 2.0)
	assert_false(r.ok)


func test_can_hollow_does_not_mutate():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "vh3")
	sys.can_hollow_brush("vh3", 2.0)
	# Brush should still exist (not deleted by validation)
	var r = sys.delete_brush_by_id("vh3")
	assert_true(r.ok, "Brush should still exist after can_hollow check")


func test_can_clip_valid_returns_ok():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "vc1")
	var r = sys.can_clip_brush("vc1", 1, 0.0)
	assert_true(r.ok)


func test_can_clip_outside_bounds_returns_fail():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "vc2")
	var r = sys.can_clip_brush("vc2", 1, 100.0)
	assert_false(r.ok)
	assert_true(r.fix_hint.length() > 0, "Should provide fix hint")


func test_can_clip_missing_brush_returns_fail():
	var r = sys.can_clip_brush("nonexistent", 0, 0.0)
	assert_false(r.ok)


func test_can_clip_does_not_mutate():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "vc3")
	sys.can_clip_brush("vc3", 1, 0.0)
	# Brush should still exist
	var r = sys.delete_brush_by_id("vc3")
	assert_true(r.ok, "Brush should still exist after can_clip check")


# ===========================================================================
# Validator + user_text() contract tests
# These verify that can_*_brush() correctly gates invalid operations and
# that user_text() formats fix_hint for display.  They do NOT exercise the
# actual plugin.gd / dock.gd handler methods (which require a running
# editor), so regressions in the real handler wiring (e.g. skipping
# user_text() or reaching HFUndoHelper.commit() on failure) would not be
# caught here.  Manual testing checklist in HammerForge_MVP_GUIDE.md
# covers that integration path.
# ===========================================================================


## Invalid hollow: validation gates undo, user_text() surfaces fix_hint.
func test_hollow_handler_gates_undo_and_surfaces_hint():
	_make_brush(Vector3.ZERO, Vector3(10, 10, 10), "ih1")
	var received := []
	root.user_message.connect(func(text, level): received.append({"text": text, "level": level}))

	var check: HFOpResult = sys.can_hollow_brush("ih1", 6.0)  # too thick
	var undo_committed := false
	if not check.ok:
		root.user_message.emit(check.user_text(), 1)
	else:
		undo_committed = true

	assert_false(undo_committed, "Failed validation must not reach undo commit")
	assert_eq(received.size(), 1, "Should emit exactly one user_message")
	assert_eq(received[0]["level"], 1, "Should be WARNING level")
	assert_true(
		received[0]["text"].find("thickness") >= 0,
		"Message should mention the problem"
	)
	assert_true(
		received[0]["text"].find("less than") >= 0,
		"Message should include the fix_hint guidance"
	)
	# Brush still exists (no mutation)
	var still_exists = sys.delete_brush_by_id("ih1")
	assert_true(still_exists.ok, "Brush should still exist after gated handler")


## Invalid clip: validation gates undo, user_text() surfaces fix_hint.
func test_clip_handler_gates_undo_and_surfaces_hint():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "ic1")
	var received := []
	root.user_message.connect(func(text, level): received.append({"text": text, "level": level}))

	var check: HFOpResult = sys.can_clip_brush("ic1", 1, 100.0)  # outside bounds
	var undo_committed := false
	if not check.ok:
		root.user_message.emit(check.user_text(), 1)
	else:
		undo_committed = true

	assert_false(undo_committed, "Failed validation must not reach undo commit")
	assert_eq(received.size(), 1, "Should emit exactly one user_message")
	assert_true(
		received[0]["text"].find("outside") >= 0,
		"Message should mention the problem"
	)
	assert_true(
		received[0]["text"].find("Click inside") >= 0,
		"Message should include the fix_hint guidance"
	)
	var still_exists = sys.delete_brush_by_id("ic1")
	assert_true(still_exists.ok, "Brush should still exist after gated handler")


## Valid hollow passes validation and proceeds to undo commit path.
func test_hollow_handler_proceeds_when_valid():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "ih2")
	var received := []
	root.user_message.connect(func(text, level): received.append({"text": text, "level": level}))

	var check: HFOpResult = sys.can_hollow_brush("ih2", 2.0)
	var undo_committed := false
	if not check.ok:
		root.user_message.emit(check.user_text(), 1)
	else:
		undo_committed = true

	assert_true(undo_committed, "Valid operation should reach undo commit")
	assert_eq(received.size(), 0, "No warning should fire for valid operation")


## Valid clip passes validation and proceeds to undo commit path.
func test_clip_handler_proceeds_when_valid():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "ic2")
	var received := []
	root.user_message.connect(func(text, level): received.append({"text": text, "level": level}))

	var check: HFOpResult = sys.can_clip_brush("ic2", 1, 0.0)
	var undo_committed := false
	if not check.ok:
		root.user_message.emit(check.user_text(), 1)
	else:
		undo_committed = true

	assert_true(undo_committed, "Valid operation should reach undo commit")
	assert_eq(received.size(), 0, "No warning should fire for valid operation")


## user_text() omits " — " suffix when fix_hint is empty.
func test_handler_no_hint_suffix_when_hint_empty():
	var check: HFOpResult = sys.can_hollow_brush("nonexistent", 2.0)
	assert_false(check.ok)
	assert_eq(check.fix_hint, "")
	assert_true(
		check.user_text().find(" — ") < 0,
		"No hint suffix when fix_hint is empty"
	)


## user_text() unit test: message + hint.
func test_user_text_with_hint():
	var r = HFOpResult.fail("something broke", "try doing X")
	assert_eq(r.user_text(), "something broke — try doing X")


## user_text() unit test: message only.
func test_user_text_without_hint():
	var r = HFOpResult.fail("something broke")
	assert_eq(r.user_text(), "something broke")


## user_text() on success returns message.
func test_user_text_success():
	var r = HFOpResult.success("done")
	assert_eq(r.user_text(), "done")
