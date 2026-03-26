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
	state.begin_drag(
		Vector3(0, 0, 0), 0, 0, 4, 32.0, Vector3(32, 32, 32), Vector2.ZERO
	)
	state.drag_end = Vector3(64, 0, 48)
	var dims = state.get_drag_dimensions()
	assert_eq(dims.x, 64.0)
	assert_eq(dims.y, 32.0)  # default height
	assert_eq(dims.z, 48.0)


func test_drag_height_returns_dimensions():
	state.begin_drag(
		Vector3(0, 0, 0), 0, 0, 4, 32.0, Vector3(32, 32, 32), Vector2.ZERO
	)
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
