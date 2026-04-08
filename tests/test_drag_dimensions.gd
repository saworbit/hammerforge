extends GutTest

const HFInputState = preload("res://addons/hammerforge/input_state.gd")

var state: HFInputState


func before_each():
	state = HFInputState.new()


func after_each():
	state = null


# ===========================================================================
# get_drag_dimensions
# ===========================================================================


func test_idle_returns_zero():
	assert_eq(state.get_drag_dimensions(), Vector3.ZERO)


func test_drag_base_returns_dimensions():
	state.begin_drag(Vector3(0, 0, 0), 0, 0, 4, 32.0, Vector3(32, 32, 32), Vector2.ZERO)
	state.drag_end = Vector3(64, 0, 48)
	var dims = state.get_drag_dimensions()
	assert_eq(dims.x, 64.0)
	assert_eq(dims.y, 32.0)  # default height
	assert_eq(dims.z, 48.0)


func test_drag_height_returns_dimensions():
	state.begin_drag(Vector3(0, 0, 0), 0, 0, 4, 32.0, Vector3(32, 32, 32), Vector2.ZERO)
	state.drag_end = Vector3(64, 0, 48)
	state.advance_to_height(Vector2.ZERO)
	state.drag_height = 96.0
	var dims = state.get_drag_dimensions()
	assert_eq(dims.x, 64.0)
	assert_eq(dims.y, 96.0)
	assert_eq(dims.z, 48.0)


func test_surface_paint_returns_zero():
	state.begin_surface_paint()
	assert_eq(state.get_drag_dimensions(), Vector3.ZERO)


func test_extrude_returns_zero():
	state.begin_extrude()
	assert_eq(state.get_drag_dimensions(), Vector3.ZERO)


# ===========================================================================
# format_dimensions
# ===========================================================================


func test_format_whole_numbers():
	var s = HFInputState.format_dimensions(Vector3(64, 32, 48))
	assert_eq(s, "64 x 32 x 48")


func test_format_fractional():
	var s = HFInputState.format_dimensions(Vector3(64.5, 32.0, 48.0))
	assert_eq(s, "64.5 x 32 x 48")


func test_format_zero_returns_empty():
	var s = HFInputState.format_dimensions(Vector3.ZERO)
	assert_eq(s, "")


# ===========================================================================
# version_changed reset predicate — mirrors plugin.gd
# _on_undo_redo_version_changed() which must reset transient preview modes
# but NOT vertex edit (a persistent mode whose commit_action fires
# version_changed after every merge/split/move).
# ===========================================================================


func test_version_changed_resets_drag_base():
	state.begin_drag(Vector3.ZERO, 0, 0, 4, 32.0, Vector3(32, 32, 32), Vector2.ZERO)
	assert_true(
		HFInputState.is_transient_preview_mode(state.mode),
		"DRAG_BASE is transient — should be reset",
	)
	state._force_reset()
	assert_true(state.is_idle(), "After reset, mode should be IDLE")


func test_version_changed_resets_drag_height():
	state.begin_drag(Vector3.ZERO, 0, 0, 4, 32.0, Vector3(32, 32, 32), Vector2.ZERO)
	state.advance_to_height(Vector2.ZERO)
	assert_true(
		HFInputState.is_transient_preview_mode(state.mode),
		"DRAG_HEIGHT is transient — should be reset",
	)
	state._force_reset()
	assert_true(state.is_idle())


func test_version_changed_resets_extrude():
	state.begin_extrude()
	assert_true(
		HFInputState.is_transient_preview_mode(state.mode),
		"EXTRUDE is transient — should be reset",
	)
	state._force_reset()
	assert_true(state.is_idle())


func test_version_changed_resets_surface_paint():
	state.begin_surface_paint()
	assert_true(
		HFInputState.is_transient_preview_mode(state.mode),
		"SURFACE_PAINT is transient — should be reset",
	)
	state._force_reset()
	assert_true(state.is_idle())


func test_version_changed_preserves_vertex_edit():
	state.begin_vertex_edit()
	assert_false(
		HFInputState.is_transient_preview_mode(state.mode),
		"VERTEX_EDIT is persistent — must NOT be reset by version_changed",
	)
	assert_true(state.is_vertex_editing(), "Mode should still be VERTEX_EDIT")


func test_version_changed_ignores_idle():
	assert_false(
		HFInputState.is_transient_preview_mode(state.mode),
		"IDLE should not trigger a reset",
	)
	assert_true(state.is_idle())
