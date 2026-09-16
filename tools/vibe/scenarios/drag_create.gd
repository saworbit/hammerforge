@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## What a drag in the viewport turns into.
##
## Every brush a mapper draws comes out of `_compute_brush_info()`: a rectangle
## dragged on the ground plane, a height dragged after it, plus Shift and an
## axis lock. The question is whether the brush that lands is the one the
## rectangle described -- a mapper drags to a wall he can see and expects the
## brush to stop there.


func id() -> String:
	return "drag-create"


func summary() -> String:
	return "whether the brush a drag produces is the size and place the drag rectangle described"


const BOX := 0
const CYLINDER := 1
const SPHERE := 2
const CONE := 3


func run() -> void:
	await _a_box_fills_its_rectangle()
	await _round_shapes_leave_the_rectangle()
	await _a_sphere_ignores_its_height_stage()
	await _degenerate_and_reversed_drags()
	await _shift_recentres_on_the_start_corner()
	await _height_floor()


func _drag(root: Node3D, a: Vector3, b: Vector3, h: float, shape: int, opts: Dictionary = {}) -> Dictionary:
	return root.drag_system._compute_brush_info(
		a,
		b,
		h,
		shape,
		opts.get("size_default", Vector3(64, 64, 64)),
		opts.get("lock", root.AxisLock.NONE),
		opts.get("equal_base", false),
		opts.get("equal_all", false)
	)


func _aabb(info: Dictionary) -> AABB:
	var s: Vector3 = info["size"]
	var c: Vector3 = info["center"]
	return AABB(c - s * 0.5, s)


## The plain case. A 128x96 rectangle dragged 64 high should be a 128x64x96 box
## sitting on the plane, spanning exactly the rectangle.
func _a_box_fills_its_rectangle() -> void:
	var root: Node3D = await fresh_root()
	var info := _drag(root, Vector3.ZERO, Vector3(128, 0, 96), 64.0, BOX)
	var box_aabb := _aabb(info)
	note("box size", info["size"])
	note("box centre", info["center"])
	note("box aabb", box_aabb)
	if info["size"] != Vector3(128, 64, 96):
		flag("a 128x96 drag 64 high did not make a 128x64x96 box", info["size"])
	if not is_equal_approx(box_aabb.position.y, 0.0):
		flag("a box drawn on the ground plane does not sit on it", box_aabb.position.y)


## `normalized_size_for_shape()` squares a round base off the *larger* of the
## two dragged sides. The brush that lands is therefore bigger than the
## rectangle on the short axis, and -- because the bounds are anchored at the
## drag origin rather than centred -- it grows out past where the drag stopped.
func _round_shapes_leave_the_rectangle() -> void:
	var root: Node3D = await fresh_root()
	var rect := AABB(Vector3.ZERO, Vector3(128, 0, 32))
	for shape in [CYLINDER, CONE, SPHERE]:
		var info := _drag(root, Vector3.ZERO, Vector3(128, 0, 32), 64.0, shape)
		var got := _aabb(info)
		note("shape %d size for a 128x32 drag" % shape, info["size"])
		note("shape %d footprint" % shape, "x %s..%s  z %s..%s" % [
			got.position.x, got.position.x + got.size.x,
			got.position.z, got.position.z + got.size.z
		])
		var overshoot_z: float = (got.position.z + got.size.z) - (rect.position.z + rect.size.z)
		if overshoot_z > 0.5:
			flag(
				"a %s drawn in a 128x32 rectangle overshoots it by %s units in Z" % [
					"cylinder" if shape == CYLINDER else ("cone" if shape == CONE else "sphere"),
					overshoot_z
				],
				(
					"the round shapes square their base off the *longer* dragged side and "
					+ "anchor at the drag origin, so the brush covers four times the ground "
					+ "the rectangle enclosed and grows out past where the drag stopped. The "
					+ "preview uses the same maths, so it is at least honest -- but there is "
					+ "no drag that produces a cylinder the size of a narrow rectangle"
				)
			)


## A sphere's height comes from the second stage of the drag, and then
## `normalized_size_for_shape()` throws it away.
func _a_sphere_ignores_its_height_stage() -> void:
	var root: Node3D = await fresh_root()
	var heights: Array = []
	for h in [16.0, 64.0, 256.0]:
		var info := _drag(root, Vector3.ZERO, Vector3(64, 0, 64), h, SPHERE)
		heights.append([h, info["size"].y])
	note("sphere: (height dragged, height produced)", heights)
	var produced: Array = []
	for pair in heights:
		if not produced.has(float(pair[1])):
			produced.append(float(pair[1]))
	if produced.size() == 1:
		flag(
			"the height stage of a sphere drag changes nothing",
			(
				("three different dragged heights all produced %s (the base diameter). " % produced[0])
				+ "The second stage of the drag still runs, the HUD still counts the height "
				+ "up and down, and a number typed into it is still accepted -- and none of "
				+ "it reaches the brush"
			)
		)

	# A cylinder keeps its dragged height; only the base is squared.
	var cyl := _drag(root, Vector3.ZERO, Vector3(64, 0, 64), 16.0, CYLINDER)
	note("cylinder at a 16-unit height", cyl["size"])


## A click with no movement, and a drag pulled back through the start point.
func _degenerate_and_reversed_drags() -> void:
	var root: Node3D = await fresh_root()
	var click := _drag(root, Vector3(32, 0, 32), Vector3(32, 0, 32), 64.0, BOX)
	note("a click with no drag", click)
	note("  -- falls back to the default footprint", click["size"])

	var reversed := _drag(root, Vector3(128, 0, 96), Vector3.ZERO, 64.0, BOX)
	var forward := _drag(root, Vector3.ZERO, Vector3(128, 0, 96), 64.0, BOX)
	note("dragged forward", _aabb(forward))
	note("dragged backward over the same rectangle", _aabb(reversed))
	if _aabb(forward).size != _aabb(reversed).size:
		flag("dragging the same rectangle backwards makes a different brush", [
			_aabb(forward), _aabb(reversed)
		])
	if not is_equal_approx(_aabb(reversed).position.y, 96.0) and not is_equal_approx(
		_aabb(reversed).position.y, 0.0
	):
		note("backward drag sits at y", _aabb(reversed).position.y)

	# A sub-grid drag: smaller than half a grid step falls back to the default.
	note("grid snap", root.grid_snap)
	var tiny := _drag(root, Vector3.ZERO, Vector3(0.05, 0, 0.05), 64.0, BOX)
	note("a 0.05-unit drag", tiny["size"])


## Shift squares the base -- about the drag origin, not about the rectangle.
func _shift_recentres_on_the_start_corner() -> void:
	var root: Node3D = await fresh_root()
	var plain := _drag(root, Vector3.ZERO, Vector3(128, 0, 32), 64.0, BOX)
	var shifted := _drag(
		root, Vector3.ZERO, Vector3(128, 0, 32), 64.0, BOX, {"equal_base": true}
	)
	note("plain 128x32 drag", _aabb(plain))
	note("same drag with Shift held", _aabb(shifted))
	note(
		"Shift moves the brush from the rectangle to a square centred on the start corner",
		"%s -> %s" % [_aabb(plain), _aabb(shifted)]
	)
	var shifted_aabb := _aabb(shifted)
	if shifted_aabb.position.x < -0.5:
		note(
			"with Shift the brush reaches behind the drag origin",
			"x starts at %s, and the drag never went below 0" % shifted_aabb.position.x
		)

	var all := _drag(root, Vector3.ZERO, Vector3(128, 0, 32), 16.0, BOX, {"equal_all": true})
	note("Shift+Alt (equal_all) at a dragged height of 16", all["size"])
	if not is_equal_approx(float(all["size"].y), 16.0):
		note("equal_all overrides the dragged height too", all["size"].y)


## How thin a brush a drag can make at all.
func _height_floor() -> void:
	var root: Node3D = await fresh_root()
	note("grid snap", root.grid_snap)
	note("height_pixels_per_unit", root.height_pixels_per_unit)
	var mouse_heights: Array = []
	for px in [0.0, 8.0, 40.0, 100.0, 200.0, 400.0, 1000.0]:
		var h: float = root.drag_system._height_from_mouse(Vector2(0, -px), Vector2.ZERO, 0.0)
		mouse_heights.append([px, h])
	note("(pixels dragged up, height produced)", mouse_heights)
	var first_change := -1.0
	for pair in mouse_heights:
		if float(pair[1]) > root.grid_snap and first_change < 0.0:
			first_change = float(pair[0])
	note("pixels of vertical drag before the height moves off its floor", first_change)
	var floor_h: float = root.drag_system._height_from_mouse(Vector2.ZERO, Vector2.ZERO, 0.0)
	note("height for no vertical movement at all", floor_h)
	if floor_h >= root.grid_snap and root.grid_snap > 0.0:
		note(
			"a drag cannot make a brush thinner than one grid step",
			(
				"height clamps up to grid_snap (%s); a %s-unit trim panel has to be made "
				+ "by drawing thick and resizing"
			) % [root.grid_snap, root.grid_snap * 0.25]
		)
