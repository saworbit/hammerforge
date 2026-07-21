extends GutTest

const HFInputState = preload("res://addons/hammerforge/input_state.gd")
const HFDragSystem = preload("res://addons/hammerforge/systems/hf_drag_system.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")


class DragRoot:
	extends Node3D

	enum AxisLock { NONE, X, Y, Z }

	var grid_snap := 1.0


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
# Primitive draw bounds
# ===========================================================================


func test_radial_draw_expands_the_short_axis_without_moving_the_drag_origin():
	var drag := _new_drag_system()
	var cone := (
		drag
		. _compute_brush_info(
			Vector3.ZERO,
			Vector3(6, 0, 8),
			4.0,
			DraftBrush.BrushShape.CONE,
			Vector3(32, 32, 32),
			DragRoot.AxisLock.NONE,
			false,
			false,
		)
	)
	assert_eq(cone["size"], Vector3(8, 4, 8))
	assert_eq(cone["center"], Vector3(4, 2, 4))

	var negative := (
		drag
		. _compute_brush_info(
			Vector3.ZERO,
			Vector3(-6, 0, -8),
			4.0,
			DraftBrush.BrushShape.CYLINDER,
			Vector3(32, 32, 32),
			DragRoot.AxisLock.NONE,
			false,
			false,
		)
	)
	assert_eq(negative["size"], Vector3(8, 4, 8))
	assert_eq(negative["center"], Vector3(-4, 2, -4))


func test_capsule_and_sphere_draw_normalization_stays_on_the_construction_plane():
	var drag := _new_drag_system()
	var capsule := (
		drag
		. _compute_brush_info(
			Vector3.ZERO,
			Vector3(6, 0, 8),
			4.0,
			DraftBrush.BrushShape.CAPSULE,
			Vector3(32, 32, 32),
			DragRoot.AxisLock.NONE,
			false,
			false,
		)
	)
	assert_eq(capsule["size"], Vector3(8, 8, 8))
	assert_eq(capsule["center"], Vector3(4, 4, 4))

	var sphere := (
		drag
		. _compute_brush_info(
			Vector3.ZERO,
			Vector3(6, 0, 8),
			32.0,
			DraftBrush.BrushShape.SPHERE,
			Vector3(32, 32, 32),
			DragRoot.AxisLock.NONE,
			false,
			false,
		)
	)
	assert_eq(sphere["size"], Vector3(8, 8, 8))
	assert_eq(sphere["center"], Vector3(4, 4, 4))


func _new_drag_system() -> HFDragSystem:
	var fake_root := DragRoot.new()
	add_child_autoqfree(fake_root)
	return HFDragSystem.new(fake_root)


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
