extends GutTest
## Regression tests for bug fixes:
## 1. Vertex undo uses pre-drag snapshots (not post-move state)
## 2. Z-axis lock uses correct enum value (3, not 4)
## 3. Carve rejects face/edge-only contact (OR, not AND)
## 4. Vertex drags use view-aware projection and absolute start-relative updates

const HFVertexSystem = preload("res://addons/hammerforge/systems/hf_vertex_system.gd")
const HFInputState = preload("res://addons/hammerforge/input_state.gd")
const HammerForgePlugin = preload("res://addons/hammerforge/plugin.gd")
const HFPluginViewportInput = preload("res://addons/hammerforge/plugin_viewport_input.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")
const DraftEntity = preload("res://addons/hammerforge/draft_entity.gd")
const LevelRoot = preload("res://addons/hammerforge/level_root.gd")
const FaceData = preload("res://addons/hammerforge/face_data.gd")
const HFPaintTool = preload("res://addons/hammerforge/paint/hf_paint_tool.gd")
const ShortcutHUD = preload("res://addons/hammerforge/shortcut_hud.gd")
const HFHotkeyPalette = preload("res://addons/hammerforge/ui/hf_hotkey_palette.gd")

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const STOP := EditorPlugin.AFTER_GUI_INPUT_STOP
const PASS := EditorPlugin.AFTER_GUI_INPUT_PASS

var root: LevelRoot
var draft_node: Node3D
## The real plugin, for the tests below that check what it does with input.
var rig := PluginRig.new()


func before_all():
	await rig.bring_up(self)


func after_all():
	await rig.take_down()


func before_each():
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	draft_node = root.draft_brushes_node


func after_each():
	root = null
	draft_node = null


func _make_box_brush(pos: Vector3, sz: Vector3, id: String) -> DraftBrush:
	var b = DraftBrush.new()
	b.size = sz
	b.brush_id = id
	draft_node.add_child(b)
	b.global_position = pos
	var half = sz * 0.5
	# CW winding from outside (matches _build_box_faces in production code)
	var quads = [
		[
			Vector3(half.x, -half.y, half.z),
			Vector3(half.x, half.y, half.z),
			Vector3(half.x, half.y, -half.z),
			Vector3(half.x, -half.y, -half.z)
		],
		[
			Vector3(-half.x, -half.y, -half.z),
			Vector3(-half.x, half.y, -half.z),
			Vector3(-half.x, half.y, half.z),
			Vector3(-half.x, -half.y, half.z)
		],
		[
			Vector3(half.x, half.y, -half.z),
			Vector3(half.x, half.y, half.z),
			Vector3(-half.x, half.y, half.z),
			Vector3(-half.x, half.y, -half.z)
		],
		[
			Vector3(half.x, -half.y, half.z),
			Vector3(half.x, -half.y, -half.z),
			Vector3(-half.x, -half.y, -half.z),
			Vector3(-half.x, -half.y, half.z)
		],
		[
			Vector3(-half.x, half.y, half.z),
			Vector3(half.x, half.y, half.z),
			Vector3(half.x, -half.y, half.z),
			Vector3(-half.x, -half.y, half.z)
		],
		[
			Vector3(-half.x, -half.y, -half.z),
			Vector3(half.x, -half.y, -half.z),
			Vector3(half.x, half.y, -half.z),
			Vector3(-half.x, half.y, -half.z)
		]
	]
	var faces: Array[FaceData] = []
	for quad in quads:
		var face = FaceData.new()
		face.local_verts = PackedVector3Array(quad)
		face.ensure_geometry()
		faces.append(face)
	b.faces = faces
	return b


## The vertex indices on the face the box presents toward `local_dir`, selected
## together. A single corner move bows the quads that meet at it, which the
## validator refuses, so a fixture that needs a committed move slides a whole
## face along its own normal.
func _select_face_toward(vs, brush: DraftBrush, id: String, local_dir: Vector3) -> PackedInt32Array:
	var dir := local_dir.normalized()
	var verts: PackedVector3Array = vs.get_brush_vertices(brush)
	var furthest := -INF
	for v in verts:
		furthest = maxf(furthest, dir.dot(v))
	var indices := PackedInt32Array()
	for i in verts.size():
		if absf(dir.dot(verts[i]) - furthest) < 0.001:
			indices.append(i)
	for i in indices:
		vs.select_vertex(id, i, i != indices[0])
	return indices


# ===========================================================================
# Bug 1: Vertex undo captures pre-drag state, not post-move state
# ===========================================================================


func test_end_drag_returns_pre_drag_face_data():
	var vs = root.vertex_system
	var b = _make_box_brush(Vector3.ZERO, Vector3(32, 32, 32), "undo1")
	vs.set_selection([b])
	_select_face_toward(vs, b, "undo1", Vector3.RIGHT)

	# Capture expected pre-drag state
	var pre_drag_expected: Array = []
	for face in b.faces:
		if face:
			pre_drag_expected.append(face.to_dict())

	# Begin drag, move, then end
	vs.begin_drag(Vector3.ZERO)
	vs.move_vertices(Vector3(8, 0, 0))
	var snapshots = vs.end_drag()

	assert_true(snapshots.has("undo1"), "Snapshots should contain the dragged brush")
	var snap_faces: Array = snapshots["undo1"]
	assert_eq(snap_faces.size(), pre_drag_expected.size(), "Should have same face count")

	# Compare actual vertex coordinate values, not just counts.
	# local_verts is serialized as Array of [x, y, z] sub-arrays.
	for i in range(snap_faces.size()):
		var snap_verts: Array = snap_faces[i].get("local_verts", [])
		var pre_verts: Array = pre_drag_expected[i].get("local_verts", [])
		assert_eq(snap_verts.size(), pre_verts.size(), "Face %d vert count" % i)
		for j in range(snap_verts.size()):
			var sv: Array = snap_verts[j]
			var pv: Array = pre_verts[j]
			assert_almost_eq(sv[0], pv[0], 0.001, "Face %d vert %d X" % [i, j])
			assert_almost_eq(sv[1], pv[1], 0.001, "Face %d vert %d Y" % [i, j])
			assert_almost_eq(sv[2], pv[2], 0.001, "Face %d vert %d Z" % [i, j])


func test_pre_drag_snapshots_differ_from_post_move_faces():
	var vs = root.vertex_system
	var b = _make_box_brush(Vector3.ZERO, Vector3(32, 32, 32), "undo2")
	vs.set_selection([b])
	_select_face_toward(vs, b, "undo2", Vector3.RIGHT)

	vs.begin_drag(Vector3.ZERO)
	vs.move_vertices(Vector3(8, 0, 0))
	var snapshots = vs.end_drag()

	# Now capture post-move state
	var post_state: Array = []
	for face in b.faces:
		if face:
			post_state.append(face.to_dict())

	# The snapshots should NOT equal post-move state (that was the bug)
	var snap_faces: Array = snapshots["undo2"]
	var any_different := false
	for i in range(snap_faces.size()):
		var snap_verts = snap_faces[i].get("local_verts", PackedVector3Array())
		var post_verts = post_state[i].get("local_verts", PackedVector3Array())
		if snap_verts != post_verts:
			any_different = true
			break
	assert_true(any_different, "Pre-drag snapshot should differ from post-move faces")


func test_cancel_drag_restores_pre_drag_geometry():
	var vs = root.vertex_system
	var b = _make_box_brush(Vector3.ZERO, Vector3(32, 32, 32), "undo3")
	vs.set_selection([b])
	vs.select_vertex("undo3", 0, false)

	# Capture pre-drag verts
	var verts_before = vs.get_brush_vertices(b).duplicate()

	vs.begin_drag(Vector3.ZERO)
	vs.move_vertices(Vector3(100, 0, 0))
	vs.cancel_drag()

	var verts_after = vs.get_brush_vertices(b)
	# Verts should be restored to pre-drag
	for i in range(verts_before.size()):
		assert_true(
			verts_before[i].is_equal_approx(verts_after[i]),
			"Vertex %d should be restored after cancel" % i
		)


# ===========================================================================
# Bug 2: Z-axis lock constant matches AxisLock.Z = 3
# ===========================================================================


func test_axis_lock_z_equals_3():
	# The AxisLock enum on LevelRoot should define Z = 3
	# Vertex drag code must use 3, not 4
	var lr_script = LevelRoot
	# AxisLock is: { NONE=0, X=1, Y=2, Z=3 }
	assert_eq(lr_script.AxisLock.NONE, 0, "AxisLock.NONE should be 0")
	assert_eq(lr_script.AxisLock.X, 1, "AxisLock.X should be 1")
	assert_eq(lr_script.AxisLock.Y, 2, "AxisLock.Y should be 2")
	assert_eq(lr_script.AxisLock.Z, 3, "AxisLock.Z should be 3")


func test_axis_lock_shortcuts_are_available_during_select_vertex_editing():
	assert_false(
		HammerForgePlugin.axis_lock_shortcuts_available(1, false),
		"Plain Select should leave X/Y/Z available to the editor",
	)
	assert_true(
		HammerForgePlugin.axis_lock_shortcuts_available(1, true),
		"Select + Vertex Edit should expose X/Y/Z axis constraints",
	)
	assert_true(
		HammerForgePlugin.axis_lock_shortcuts_available(0, false),
		"Construction tools should retain their existing axis constraints",
	)


func test_hotkey_palette_exposes_axis_locks_in_select_vertex_context():
	var palette := HFHotkeyPalette.new()
	autofree(palette)

	var select_tool_context := HammerForgePlugin.hotkey_palette_tool_context(1, false)
	palette.update_state({"tool": select_tool_context, "vertex_mode": false})
	assert_false(palette._is_action_available("axis_x"))

	var vertex_tool_context := HammerForgePlugin.hotkey_palette_tool_context(1, true)
	palette.update_state({"tool": vertex_tool_context, "vertex_mode": true})
	for action in ["axis_x", "axis_y", "axis_z"]:
		assert_true(
			palette._is_action_available(action),
			"%s should be enabled in the Select + Vertex Edit palette" % action,
		)


func test_canceled_vertex_release_is_classified_separately_from_commit_release():
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.canceled = true
	assert_true(HammerForgePlugin.is_canceled_vertex_drag_release(release))

	release.canceled = false
	assert_false(HammerForgePlugin.is_canceled_vertex_drag_release(release))
	release.pressed = true
	assert_false(HammerForgePlugin.is_canceled_vertex_drag_release(release))
	release.pressed = false
	release.canceled = true
	release.button_index = MOUSE_BUTTON_RIGHT
	assert_false(HammerForgePlugin.is_canceled_vertex_drag_release(release))
	assert_false(HammerForgePlugin.is_canceled_vertex_drag_release(InputEventMouseMotion.new()))


## The dock's grid before a vertex test set it to 1.
var _grid_before := 0.0

## The middle of the box's top edge on its +X side, which the drags below pick
## up. An edge rather than a corner: a box with one corner pulled out is no
## longer a solid, and the vertex system refuses the move.
const EDGE_MIDDLE := Vector3(2, 2, 0)


## A 4-unit box at the origin, selected, in vertex mode picking edges, with the
## grid at 1 so a short drag shows. Leave it with `_leave_vertex_level()`.
func _vertex_level() -> Node:
	var level = await rig.make_level()
	rig.select([rig.box(level, "v", Vector3.ZERO)])
	_grid_before = rig.plugin.dock.get_grid_snap()
	rig.plugin.dock._apply_grid_snap(1.0)
	rig.plugin._hotkey_palette.action_invoked.emit("vertex_edit")
	assert_true(rig.plugin._vertex_mode, "vertex mode is on")
	rig.forward(PluginRig.key_for("vertex_edge_mode"))
	return level


func _leave_vertex_level(level: Node) -> void:
	await rig.leave_level(level)
	rig.plugin.dock._apply_grid_snap(_grid_before)


## Where the first vertex the drag picked up is now.
func _picked(level: Node) -> Vector3:
	var positions: PackedVector3Array = level.vertex_system.get_selected_world_positions()
	return positions[0] if positions.size() > 0 else Vector3.INF


func _drag_to(position: Vector2) -> int:
	return rig.forward(PluginRig.motion(position, MOUSE_BUTTON_MASK_LEFT))


## A release Godot reports as canceled, when it lost pointer capture, puts the
## edge back where the drag started instead of committing it; a normal release
## keeps the move.
func test_canceled_vertex_release_restores_before_the_normal_commit_path():
	assert_not_null(rig.plugin, rig.error())
	var level = await _vertex_level()
	var start := rig.camera.unproject_position(EDGE_MIDDLE)
	assert_eq(rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, true, start)), STOP, "picked up")
	var origin := _picked(level)
	_drag_to(start + Vector2(60, 0))
	assert_false(_picked(level).is_equal_approx(origin), "the drag moves it")
	var canceled := PluginRig.click(MOUSE_BUTTON_LEFT, false, start + Vector2(60, 0), true)
	assert_eq(rig.forward(canceled), STOP)
	assert_almost_eq(_picked(level), origin, Vector3.ONE * 0.001, "a canceled release restores it")

	rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, true, start))
	_drag_to(start + Vector2(60, 0))
	var moved := _picked(level)
	rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, false, start + Vector2(60, 0)))
	assert_almost_eq(_picked(level), moved, Vector3.ONE * 0.001, "a normal release keeps it")
	assert_false(moved.is_equal_approx(origin))
	await _leave_vertex_level(level)


# ===========================================================================
# Bug 3: Carve rejects face/edge-only contact
# ===========================================================================


func test_carve_face_contact_does_not_destroy():
	# Two brushes touching on one face (no volumetric overlap)
	# Brush A at origin, Brush B immediately adjacent on +X
	var a = _make_box_brush(Vector3.ZERO, Vector3(32, 32, 32), "face_a")
	var b = _make_box_brush(Vector3(32, 0, 0), Vector3(32, 32, 32), "face_b")

	var cs = root.carve_system
	var result = cs.carve_with_brush("face_a")

	# Should fail: brushes only touch on a face, no volume overlap
	assert_false(result.ok, "Face-only contact should not be carved")
	# The carver should NOT have been deleted (it's still in the tree)
	# Actually carver IS deleted at end of carve_with_brush even on success,
	# but since targets_carved == 0 AND targets is empty, it returns _op_fail
	# before reaching the delete. Let's verify the target survived:
	assert_true(is_instance_valid(b), "Target brush should survive face contact")


func test_carve_edge_contact_does_not_destroy():
	# Two brushes touching on one edge only (diagonal neighbor)
	var a = _make_box_brush(Vector3.ZERO, Vector3(32, 32, 32), "edge_a")
	var b = _make_box_brush(Vector3(32, 32, 0), Vector3(32, 32, 32), "edge_b")

	var cs = root.carve_system
	var result = cs.carve_with_brush("edge_a")

	assert_false(result.ok, "Edge-only contact should not be carved")
	assert_true(is_instance_valid(b), "Target brush should survive edge contact")


func test_carve_corner_contact_does_not_destroy():
	# Two brushes touching at a single corner point
	var a = _make_box_brush(Vector3.ZERO, Vector3(32, 32, 32), "corner_a")
	var b = _make_box_brush(Vector3(32, 32, 32), Vector3(32, 32, 32), "corner_b")

	var cs = root.carve_system
	var result = cs.carve_with_brush("corner_a")

	assert_false(result.ok, "Corner-only contact should not be carved")
	assert_true(is_instance_valid(b), "Target brush should survive corner contact")


func test_carve_volumetric_overlap_succeeds():
	# Two overlapping brushes (carver partially inside target)
	var a = _make_box_brush(Vector3.ZERO, Vector3(32, 32, 32), "vol_a")
	var b = _make_box_brush(Vector3(16, 0, 0), Vector3(32, 32, 32), "vol_b")

	var cs = root.carve_system
	var result = cs.carve_with_brush("vol_a")

	assert_true(result.ok, "Volumetric overlap should succeed")


func test_carve_thin_overlap_single_axis_produces_no_pieces():
	# Brushes overlap by a negligible amount on X (just touching + epsilon)
	# but fully overlap on Y and Z. The thin X overlap (< min_thickness) means
	# the target is skipped during slicing, so no pieces are created.
	var a = _make_box_brush(Vector3.ZERO, Vector3(32, 32, 32), "thin_a")
	# Place b so X overlap is exactly 0.005 (below min_thickness 0.01)
	var b = _make_box_brush(Vector3(31.995, 0, 0), Vector3(32, 32, 32), "thin_b")

	var child_count_before = draft_node.get_child_count()
	var cs = root.carve_system
	var result = cs.carve_with_brush("thin_a")

	# The target survives (thin overlap is rejected via OR guard)
	assert_true(is_instance_valid(b), "Target should survive thin overlap")
	# Nothing was cut, so the carver must not be eaten either.
	assert_false(result.ok, "Carving nothing should report failure")
	assert_true(is_instance_valid(a), "Carver should survive when nothing is carved")
	assert_eq(
		draft_node.get_child_count(), child_count_before, "No brushes should be added or removed"
	)


func _make_cylinder_brush(pos: Vector3, sz: Vector3, id: String) -> DraftBrush:
	var b = _make_box_brush(pos, sz, id)
	b.shape = DraftBrush.BrushShape.CYLINDER
	return b


func _record_user_messages() -> Array:
	var seen: Array = []
	root.user_message.connect(func(msg, _level): seen.append(str(msg)))
	return seen


func test_carve_accepts_a_non_box_carver():
	# Carve used to rebuild every target as axis-aligned boxes and so refused any
	# carver that was not one. It now cuts with the carver's real face planes.
	_make_cylinder_brush(Vector3.ZERO, Vector3(32, 32, 32), "cyl_carver")
	_make_box_brush(Vector3(16, 0, 0), Vector3(32, 32, 32), "box_target")

	var result = root.carve_system.carve_with_brush("cyl_carver")

	assert_true(result.ok, "A cylinder carver should cut: %s" % result.message)
	assert_null(
		root.brush_system.find_brush_by_id("cyl_carver"), "The carver is consumed by a carve"
	)
	assert_null(
		root.brush_system.find_brush_by_id("box_target"), "The target is replaced by its pieces"
	)


func test_carve_accepts_a_rotated_carver():
	var carver = _make_box_brush(Vector3.ZERO, Vector3(32, 32, 32), "rot_carver")
	carver.rotation = Vector3(0, deg_to_rad(45.0), 0)
	carver.rebuild_preview()
	_make_box_brush(Vector3(16, 0, 0), Vector3(32, 32, 32), "rot_target")

	var result = root.carve_system.carve_with_brush("rot_carver")

	assert_true(result.ok, "A turned carver should cut: %s" % result.message)
	assert_null(
		root.brush_system.find_brush_by_id("rot_target"), "The target is replaced by its pieces"
	)


func test_carve_accepts_a_non_box_target():
	_make_box_brush(Vector3.ZERO, Vector3(32, 32, 32), "box_carver")
	_make_cylinder_brush(Vector3(16, 0, 0), Vector3(32, 32, 32), "cyl_target")

	var result = root.carve_system.carve_with_brush("box_carver")

	assert_true(result.ok, "A cylinder target should be carved: %s" % result.message)
	assert_null(
		root.brush_system.find_brush_by_id("cyl_target"), "The cylinder is replaced by its pieces"
	)
	assert_null(root.brush_system.find_brush_by_id("box_carver"), "The carver is consumed")


func test_carve_accepts_a_rotated_target():
	var carver = _make_box_brush(Vector3.ZERO, Vector3(32, 32, 32), "rt_carver")
	var target = _make_box_brush(Vector3(16, 0, 0), Vector3(32, 32, 32), "rt_target")
	target.rotation = Vector3(0, deg_to_rad(45.0), 0)
	target.rebuild_preview()

	var result = root.carve_system.carve_with_brush("rt_carver")

	assert_true(result.ok, "A turned target should be carved: %s" % result.message)
	assert_null(
		root.brush_system.find_brush_by_id("rt_target"), "The rotated box is replaced by its pieces"
	)


func test_carve_cuts_every_target_in_a_mixed_set():
	# The old rule refused the whole carve if any target was not an unrotated box,
	# so that a partial cut could not leave the user guessing which brushes moved.
	# Every target is cuttable now, so the whole set is carved instead.
	_make_box_brush(Vector3.ZERO, Vector3(64, 32, 32), "mixed_carver")
	_make_box_brush(Vector3(24, 0, 0), Vector3(32, 32, 32), "mixed_box")
	_make_cylinder_brush(Vector3(-24, 0, 0), Vector3(32, 32, 32), "mixed_cyl")

	var result = root.carve_system.carve_with_brush("mixed_carver")

	assert_true(result.ok, "A mixed target set should carve: %s" % result.message)
	assert_null(root.brush_system.find_brush_by_id("mixed_box"), "The box target is carved")
	assert_null(
		root.brush_system.find_brush_by_id("mixed_cyl"), "The cylinder target is carved too"
	)
	assert_null(root.brush_system.find_brush_by_id("mixed_carver"), "The carver is consumed")


func test_carve_still_refuses_when_nothing_overlaps():
	var carver = _make_box_brush(Vector3.ZERO, Vector3(32, 32, 32), "lonely_carver")
	var target = _make_box_brush(Vector3(500, 0, 0), Vector3(32, 32, 32), "far_target")
	var child_count_before = draft_node.get_child_count()

	var warnings := _record_user_messages()
	var result = root.carve_system.carve_with_brush("lonely_carver")

	assert_false(result.ok, "A carver touching nothing has nothing to cut")
	assert_eq(warnings.size(), 1, "A refused carve has to say so, not look like a no-op")
	assert_true(is_instance_valid(carver), "The carver must survive a refused carve")
	assert_true(is_instance_valid(target), "The target must survive a refused carve")
	assert_eq(draft_node.get_child_count(), child_count_before, "Nothing should be replaced")


# ===========================================================================
# Bug 4: Vertex input uses the view-aware, start-relative drag contract
# ===========================================================================


## The edge follows the cursor from where the drag started, not from where it
## was last frame: the same cursor spot twice is the same place, and back at the
## start is back where it began. With X locked, a drag up the screen still moves
## it along X only, which only the vertex system's view-aware projection does.
func test_plugin_uses_vertex_system_projection_and_absolute_updates():
	var level = await _vertex_level()
	var start := rig.camera.unproject_position(EDGE_MIDDLE)
	rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, true, start))
	var origin := _picked(level)
	_drag_to(start + Vector2(60, 0))
	var there := _picked(level)
	assert_false(there.is_equal_approx(origin), "the drag moves it")
	_drag_to(start + Vector2(60, 0))
	assert_almost_eq(_picked(level), there, Vector3.ONE * 0.001, "the same spot twice adds nothing")
	_drag_to(start)
	assert_almost_eq(_picked(level), origin, Vector3.ONE * 0.001, "back at the start")

	assert_eq(rig.forward(PluginRig.key_for("axis_x")), STOP, "X locks mid-drag")
	_drag_to(start + Vector2(40, -80))
	var locked := _picked(level)
	assert_ne(locked.x, origin.x, "the locked drag moves it along X")
	assert_almost_eq(locked.y, origin.y, 0.001, "and not up")
	assert_almost_eq(locked.z, origin.z, 0.001, "or across")
	rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, false, start + Vector2(40, -80)))
	await _leave_vertex_level(level)


## Looking straight down at the edge, a Y lock gives the cursor nothing to move
## it along. The drag then goes back to where it started rather than keeping the
## move it had before the lock.
func test_plugin_resets_absolute_drag_when_projection_is_invalid():
	var level = await _vertex_level()
	var camera_before: Transform3D = rig.camera.global_transform
	rig.camera.look_at_from_position(EDGE_MIDDLE + Vector3(0, 18, 0), EDGE_MIDDLE, Vector3.FORWARD)
	var start := rig.camera.unproject_position(EDGE_MIDDLE)
	rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, true, start))
	var origin := _picked(level)
	_drag_to(start + Vector2(80, 0))
	assert_false(_picked(level).is_equal_approx(origin), "an unlocked drag moves it")
	rig.forward(PluginRig.key_for("axis_y"))
	_drag_to(start + Vector2(100, 0))
	assert_almost_eq(
		_picked(level), origin, Vector3.ONE * 0.001, "a head-on axis puts it back at the start"
	)
	rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, false, start + Vector2(100, 0)))
	rig.camera.global_transform = camera_before
	await _leave_vertex_level(level)


func _press_in_vertex_mode(sub_mode: int) -> Array:
	var vs := FakeAnchorVertexSystem.new()
	vs.sub_mode = sub_mode
	var fake_root := FakeAnchorRoot.new()
	fake_root.vertex_system = vs
	autofree(fake_root)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	HFPluginVertexInput.handle(FakeAnchorPlugin.new(), press, fake_root, null, Vector2(10, 10))
	return vs.anchors


func test_vertex_projection_uses_picked_world_anchor_for_vertices_and_edges():
	assert_eq(
		_press_in_vertex_mode(HFVertexSystem.VertexSubMode.VERTEX),
		[FakeAnchorVertexSystem.VERTEX_POS],
		"Vertex drags must capture the picked vertex as their projection anchor"
	)
	assert_eq(
		_press_in_vertex_mode(HFVertexSystem.VertexSubMode.EDGE),
		[FakeAnchorVertexSystem.EDGE_MIDPOINT],
		"Edge drags must capture the picked edge midpoint as their projection anchor"
	)
	# A grep on purpose: it keeps a removed field from coming back, and a field
	# that is not there has no behaviour to drive. The anchors above are behaviour.
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin_vertex_input.gd")
	assert_false(
		source.contains("_vertex_drag_ref_y"), "The obsolete Y-only anchor must be removed"
	)


func test_vertex_hud_shortcuts_override_select_tool_context():
	var shortcut_hud = ShortcutHUD.new()
	autofree(shortcut_hud)

	var shortcuts: String = shortcut_hud._build_shortcuts_text({"tool": 1, "mode": 5})

	assert_string_contains(shortcuts, "-- Vertex Edit --")
	assert_string_contains(shortcuts, "E: Toggle edge mode")
	assert_false(
		shortcuts.contains("Drag Empty Space: Box Select"),
		"Vertex mode must not be masked by the underlying Select tool",
	)


# ===========================================================================
# Viewport input ownership regressions
# ===========================================================================


func test_passive_viewport_input_does_not_request_a_level_root():
	var motion := InputEventMouseMotion.new()
	assert_false(HammerForgePlugin.should_create_root_for_viewport_input(motion, 0, false))

	var right_press := InputEventMouseButton.new()
	right_press.button_index = MOUSE_BUTTON_RIGHT
	right_press.pressed = true
	assert_false(HammerForgePlugin.should_create_root_for_viewport_input(right_press, 0, false))


func test_only_an_intentional_draw_press_requests_a_level_root():
	var left_event := InputEventMouseButton.new()
	left_event.button_index = MOUSE_BUTTON_LEFT
	left_event.pressed = true
	assert_true(HammerForgePlugin.should_create_root_for_viewport_input(left_event, 0, false))
	assert_false(
		HammerForgePlugin.should_create_root_for_viewport_input(left_event, 1, false),
		"Select clicks must not create a LevelRoot",
	)
	assert_false(
		HammerForgePlugin.should_create_root_for_viewport_input(left_event, 0, true),
		"Paint clicks must not create a LevelRoot through the Draw path",
	)
	left_event.pressed = false
	assert_false(
		HammerForgePlugin.should_create_root_for_viewport_input(left_event, 0, false),
		"A release without a matching HammerForge press is passive",
	)


func test_command_palette_ui_actions_do_not_require_or_create_a_level_root():
	for action in [
		"toggle_operation",
		"toggle_paint_mode",
		"tool_draw",
		"tool_select",
		"tool_extrude_up",
		"paint_bucket",
		"paint_fill",
		"selection_filter",
		"radial_menu",
		"unknown_action",
	]:
		assert_false(
			HammerForgePlugin.hotkey_palette_action_requires_existing_root(action),
			"%s should remain root-independent" % action,
		)


## With no level open, nothing picked from the command palette makes one. An
## action that needs a level says so; one that only changes the editor's own
## state runs without one.
func test_the_command_palette_never_creates_a_level_root():
	assert_eq(rig.level_roots(), 0, "the scene starts empty")
	var guarded := 0
	for action in rig.plugin._keymap.get_actions():
		if not HammerForgePlugin.hotkey_palette_action_requires_existing_root(action):
			continue
		guarded += 1
		rig.clear_toasts()
		rig.plugin._hotkey_palette.action_invoked.emit(action)
		assert_eq(rig.level_roots(), 0, "%s made no level" % action)
		assert_has(rig.toasts(), "Create a HammerForge level first", "%s says why" % action)
	assert_gt(guarded, 20, "the palette's level actions were tried")
	# Each toggle twice and the Draw tool last, so the dock ends as it began.
	for action in [
		"toggle_operation",
		"toggle_operation",
		"toggle_paint_mode",
		"toggle_paint_mode",
		"tool_select",
		"tool_extrude_up",
		"tool_draw",
		"paint_bucket",
		"paint_fill",
		"selection_filter",
		"radial_menu",
		"unknown_action",
	]:
		rig.plugin._hotkey_palette.action_invoked.emit(action)
		assert_eq(rig.level_roots(), 0, "%s made no level" % action)
	rig.plugin._selection_filter.hide()
	rig.clear_toasts()


func test_command_palette_content_actions_require_an_existing_level_root():
	for action in [
		"quick_play",
		"validate_level",
		"select_all",
		"delete",
		"duplicate",
		"hollow",
		"grid_increase",
		"vertex_edit",
		"texture_picker",
		"axis_x",
		"select_similar",
		"apply_last_texture",
		"context_menu",
	]:
		assert_true(
			HammerForgePlugin.hotkey_palette_action_requires_existing_root(action),
			"%s must be guarded when no level exists" % action,
		)


func test_undoable_level_root_creation_registers_node_lifetime():
	# A grep, because the reference is held by the undo manager, and the plugin
	# stand-in has none: without one the level is added directly.
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin.gd")
	var create_start := source.find("func _create_level_root")
	var create_end := source.find("func _activate_created_level_root", create_start)
	assert_gte(create_start, 0)
	assert_gt(create_end, create_start)
	var create_body := source.substr(create_start, create_end - create_start)
	assert_true(
		create_body.contains("undo_redo_manager.add_do_reference(root)"),
		"UndoRedo must own a reference to a newly created LevelRoot",
	)


func test_idle_rmb_passes_but_transient_gestures_are_cancelable():
	var input_state := HFInputState.new()
	assert_false(
		HammerForgePlugin.has_cancelable_rmb_gesture(input_state, false),
		"Idle RMB must remain available for Godot camera navigation",
	)

	input_state.begin_drag(Vector3.ZERO, 0, 0, 4, 16.0, Vector3(16, 16, 16), Vector2.ZERO)
	assert_true(HammerForgePlugin.has_cancelable_rmb_gesture(input_state, false))
	input_state.cancel()
	input_state.begin_extrude()
	assert_true(HammerForgePlugin.has_cancelable_rmb_gesture(input_state, false))
	input_state.end_extrude()
	input_state.begin_vertex_edit()
	assert_false(
		HammerForgePlugin.has_cancelable_rmb_gesture(input_state, false),
		"Persistent vertex mode alone must not steal RMB",
	)
	assert_true(
		HammerForgePlugin.has_cancelable_rmb_gesture(null, true),
		"An active selection marquee remains cancelable",
	)


func test_native_rmb_camera_session_owns_all_input_until_release():
	var session := HFPluginViewportInput.RmbCameraNavigationSession.new()
	var motion := InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_RIGHT
	assert_false(session.handle_followup(motion))
	session.begin()
	assert_true(session.active)
	assert_true(session.handle_followup(motion))
	assert_true(session.active)

	var buttonless_motion := InputEventMouseMotion.new()
	assert_false(session.handle_followup(buttonless_motion))
	assert_false(session.active, "A missed release must clear the camera session")

	var right_release := InputEventMouseButton.new()
	right_release.button_index = MOUSE_BUTTON_RIGHT
	right_release.pressed = false
	session.begin()
	assert_true(session.handle_followup(right_release))
	assert_false(session.active, "RMB release must close the camera session")

	var right_press := InputEventMouseButton.new()
	right_press.button_index = MOUSE_BUTTON_RIGHT
	right_press.pressed = true
	session.begin()
	assert_false(session.handle_followup(right_press))
	assert_false(session.active, "A fresh press must replace stale session state")

	var left_release := InputEventMouseButton.new()
	left_release.button_index = MOUSE_BUTTON_LEFT
	left_release.pressed = false
	session.begin()
	assert_true(session.handle_followup(left_release))
	assert_true(session.active, "Mixed mouse buttons must remain inside RMB camera ownership")

	for keycode in [KEY_W, KEY_A, KEY_S, KEY_D]:
		var key := InputEventKey.new()
		key.keycode = keycode
		key.pressed = true
		assert_true(session.handle_followup(key), "RMB+%s must stay native" % keycode)
		assert_true(session.active)

	for button in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_WHEEL_UP]:
		var mixed_button := InputEventMouseButton.new()
		mixed_button.button_index = button
		mixed_button.pressed = true
		assert_true(
			session.handle_followup(mixed_button),
			"RMB camera ownership must contain button %s" % button,
		)
		assert_true(session.active)


## While Godot flies the camera on RMB, the keyboard is Godot's too: Escape
## cancels nothing of HammerForge's and Ctrl+Right nudges nothing, and neither
## is consumed. Once RMB is up, both are HammerForge's again.
func test_rmb_camera_flight_keeps_escape_and_nudge_native():
	var level = await rig.make_level()
	var box = rig.box(level, "a", Vector3.ZERO)
	rig.select([box])
	rig.plugin._hotkey_palette.action_invoked.emit("vertex_edit")
	assert_true(rig.plugin._vertex_mode, "vertex mode is on, which Escape would leave")
	assert_eq(rig.forward(PluginRig.click(MOUSE_BUTTON_RIGHT, true)), PASS, "idle RMB is Godot's")

	assert_false(rig.press_shortcut(PluginRig.key(KEY_ESCAPE)), "Escape is left for Godot")
	assert_true(rig.plugin._vertex_mode, "and cancels nothing")
	assert_false(rig.press_shortcut(PluginRig.key(KEY_RIGHT, true)), "Ctrl+Right is left too")
	assert_eq(box.global_position, Vector3.ZERO, "and nudges nothing")

	rig.forward(PluginRig.click(MOUSE_BUTTON_RIGHT, false))
	assert_true(rig.press_shortcut(PluginRig.key(KEY_RIGHT, true)), "after RMB, Ctrl+Right is ours")
	assert_gt(box.global_position.x, 0.0, "and nudges")
	assert_true(rig.press_shortcut(PluginRig.key(KEY_ESCAPE)), "as is Escape")
	assert_false(rig.plugin._vertex_mode, "which leaves vertex mode")
	await rig.leave_level(level)


func test_editor_object_ownership_is_narrow_and_selection_safe():
	# This predicate says which nodes HammerForge owns. It no longer answers
	# _handles() — see test_main_screen_plugin_never_handles_editor_objects — but
	# it still decides which selections may retarget active_root.
	var level_root = LevelRoot.new()
	var brush = DraftBrush.new()
	var entity = DraftEntity.new()
	var unrelated = Node3D.new()
	var camera = Camera3D.new()
	var light = DirectionalLight3D.new()
	assert_true(HammerForgePlugin.should_handle_editor_object(level_root))
	assert_true(HammerForgePlugin.should_handle_editor_object(brush))
	assert_true(HammerForgePlugin.should_handle_editor_object(entity))
	assert_false(HammerForgePlugin.should_handle_editor_object(unrelated))
	assert_false(HammerForgePlugin.should_handle_editor_object(camera))
	assert_false(HammerForgePlugin.should_handle_editor_object(light))
	level_root.free()
	brush.free()
	entity.free()
	unrelated.free()
	camera.free()
	light.free()


func test_main_screen_plugin_never_handles_editor_objects():
	# Godot switches to a plugin that both has a main screen and handles the
	# selected object, so declaring both put the Console in front of the 3D view
	# on every brush click (#592). The plugin has the main screen, so it handles
	# nothing: not a level, a brush, an entity, or a Godot node.
	assert_true(rig.plugin._has_main_screen(), "the switcher place is the reason for this rule")
	var level = await rig.make_level()
	var entity = DraftEntity.new()
	entity.entity_type = "light_point"
	level.add_entity(entity)
	for object in [level, rig.box(level, "a", Vector3.ZERO), entity, rig.native_node()]:
		assert_false(rig.plugin._handles(object), "the plugin does not handle %s" % object)
	await rig.leave_level(level)


func test_selection_retargets_active_root_without_handling_the_object():
	# _edit() used to set active_root and only fired because _handles() was true.
	# The same job now runs off the selection, so a brush still points the plugin
	# at its own LevelRoot.
	var level_root = LevelRoot.new()
	var brush = DraftBrush.new()
	level_root.add_child(brush)
	var camera = Camera3D.new()
	assert_eq(
		HammerForgePlugin.resolve_active_root_for_selection([brush]),
		level_root,
		"A selected brush must make its own LevelRoot active"
	)
	assert_eq(
		HammerForgePlugin.resolve_active_root_for_selection([level_root]),
		level_root,
		"Selecting the LevelRoot itself must make it active"
	)
	assert_null(
		HammerForgePlugin.resolve_active_root_for_selection([camera]),
		"A camera must not retarget active_root, so the sticky root survives"
	)
	assert_null(
		HammerForgePlugin.resolve_active_root_for_selection([]),
		"An empty selection must not retarget active_root"
	)
	camera.free()
	level_root.free()


func test_quick_property_dismiss_preserves_native_navigation_buttons():
	var right_event := InputEventMouseButton.new()
	right_event.button_index = MOUSE_BUTTON_RIGHT
	assert_eq(
		HammerForgePlugin.classify_quick_property_dismiss(right_event),
		HammerForgePlugin.QUICK_PROPERTY_DISMISS_CONTINUE,
		"RMB must continue to the current gesture owner before native navigation",
	)
	for button in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_WHEEL_UP]:
		var event := InputEventMouseButton.new()
		event.button_index = button
		assert_eq(
			HammerForgePlugin.classify_quick_property_dismiss(event),
			EditorPlugin.AFTER_GUI_INPUT_PASS,
			"Navigation button %d must dismiss and pass through" % button,
		)
	var left_event := InputEventMouseButton.new()
	left_event.button_index = MOUSE_BUTTON_LEFT
	assert_eq(
		HammerForgePlugin.classify_quick_property_dismiss(left_event),
		EditorPlugin.AFTER_GUI_INPUT_STOP,
		"LMB dismiss must be consumed to prevent editing through the popup",
	)


func test_active_paint_stroke_keeps_pointer_capture_until_lmb_release():
	assert_false(HammerForgePlugin.should_block_rmb_during_paint_stroke(false, false, false, true))
	assert_true(HammerForgePlugin.should_block_rmb_during_paint_stroke(true, false, false, true))
	assert_true(HammerForgePlugin.should_block_rmb_during_paint_stroke(false, true, false, true))
	assert_true(HammerForgePlugin.should_block_rmb_during_paint_stroke(false, false, true, true))
	assert_false(
		HammerForgePlugin.should_block_rmb_during_paint_stroke(true, true, true, false),
		"A stale paint flag must not permanently block RMB after LMB is no longer held",
	)
	var floor_paint := HFPaintTool.new()
	floor_paint._painting = true
	floor_paint.finish_stroke_if_active()
	assert_false(floor_paint.is_stroke_active(), "Stale floor-paint capture must be recoverable")
	floor_paint.free()


## An external tool that writes down every event it is handed.
class RecordingTool:
	extends HFEditorTool
	const ID := 190
	var events: Array = []

	func tool_id() -> int:
		return ID

	func tool_name() -> String:
		return "Recording Tool"

	func handle_input(event: InputEvent, _camera: Camera3D, _mouse_pos: Vector2) -> int:
		events.append(event)
		return EditorPlugin.AFTER_GUI_INPUT_PASS


func test_viewport_forwarding_is_selection_independent():
	# A grep, because forwarding is a registration with the editor, which the
	# plugin stand-in takes and does nothing with.
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin.gd")
	var enter_start := source.find("func _enter_tree")
	var exit_start := source.find("func _exit_tree", enter_start)
	var enter_body := source.substr(enter_start, exit_start - enter_start)
	assert_true(
		enter_body.contains("set_input_event_forwarding_always_enabled()"),
		"Viewport forwarding must not depend on whichever editor object is selected",
	)


## The editor hands every 3D viewport event to `_forward_3d_gui_input`. With no
## level open, RMB there starts Godot's camera look, and the drag that follows
## stays Godot's and makes no level.
func test_rootless_rmb_owns_the_whole_native_camera_session():
	assert_eq(rig.level_roots(), 0, "the scene starts empty")
	assert_eq(rig.forward(PluginRig.click(MOUSE_BUTTON_RIGHT, true)), PASS)
	assert_true(rig.plugin._rmb_camera_navigation.active, "the camera session began")
	var flight := PluginRig.motion(Vector2(500, 320), MOUSE_BUTTON_MASK_RIGHT)
	assert_eq(rig.forward(flight), PASS, "the drag is Godot's")
	assert_eq(rig.forward(PluginRig.click(MOUSE_BUTTON_RIGHT, false)), PASS)
	assert_false(rig.plugin._rmb_camera_navigation.active, "and RMB up ends it")
	assert_eq(rig.level_roots(), 0, "no level was made")


## RMB-held motion during camera flight goes back to Godot before any tool work:
## the active external tool never sees it. Once RMB is up, it sees motion again.
func test_rmb_followups_bypass_tool_work():
	var level = await rig.make_level()
	var tool := RecordingTool.new()
	rig.plugin._tool_registry.register_tool(tool)
	rig.plugin._activate_external_tool(RecordingTool.ID, level)
	assert_true(tool.is_active, "the tool is active")
	assert_eq(rig.forward(PluginRig.click(MOUSE_BUTTON_RIGHT, true)), PASS)
	tool.events.clear()
	var flight := PluginRig.motion(Vector2(500, 320), MOUSE_BUTTON_MASK_RIGHT)
	assert_eq(rig.forward(flight), PASS)
	assert_eq(tool.events.size(), 0, "camera motion never reaches the tool")
	rig.forward(PluginRig.click(MOUSE_BUTTON_RIGHT, false))
	rig.forward(PluginRig.motion(Vector2(510, 320)))
	assert_eq(tool.events.size(), 1, "plain motion does")
	rig.plugin._tool_registry.unregister_tool(RecordingTool.ID)
	await rig.leave_level(level)


## Quick Bake from the palette runs the dock's own bake.
func test_quick_bake_dispatch_calls_the_real_dock_callback():
	var level = await rig.make_level()
	rig.box(level, "a", Vector3.ZERO)
	watch_signals(level)
	rig.plugin._hotkey_palette.action_invoked.emit("quick_bake")
	await wait_for_signal(level.bake_finished, 10)
	assert_signal_emitted(level, "bake_started", "Quick Bake started a bake")
	assert_signal_emitted(level, "bake_finished", "and it finished")
	await rig.leave_level(level)


## A nudge key asks who owns the selection before it moves anything, by either
## road a key arrives: the arrow keys over the 3D viewport, and Ctrl+Arrow
## through the editor's shortcuts. A HammerForge selection moves and the key is
## consumed; a Godot selection is left to Godot; a mixed one is refused, and the
## key is consumed anyway so Godot does not act on the same nodes.
func test_nudge_keys_respect_selection_ownership_before_being_consumed():
	var level = await rig.make_level()
	var box = rig.box(level, "a", Vector3.ZERO)
	var lamp = rig.native_node()

	rig.select([lamp])
	assert_eq(rig.forward(PluginRig.key(KEY_RIGHT)), PASS, "a Godot selection is Godot's")
	assert_false(rig.press_shortcut(PluginRig.key(KEY_RIGHT, true)), "by either road")
	assert_eq(box.global_position, Vector3.ZERO)
	assert_eq(lamp.global_position, Vector3.ZERO, "and HammerForge moves nothing")

	rig.select([box, lamp])
	assert_eq(rig.forward(PluginRig.key(KEY_RIGHT)), STOP, "a mixed selection is refused")
	assert_true(rig.press_shortcut(PluginRig.key(KEY_RIGHT, true)), "and the key consumed")
	assert_eq(box.global_position, Vector3.ZERO, "without moving anything")
	assert_has(rig.toasts(), "Edit HammerForge and Godot nodes separately")

	rig.select([box])
	assert_eq(rig.forward(PluginRig.key(KEY_RIGHT)), STOP)
	assert_eq(box.global_position, Vector3(level.grid_snap, 0, 0), "the arrow key nudges")
	assert_true(rig.press_shortcut(PluginRig.key(KEY_RIGHT, true)), "Ctrl+Right is consumed")
	assert_eq(box.global_position, Vector3(level.grid_snap * 2, 0, 0), "and nudges")
	await rig.leave_level(level)


## Delete and Duplicate arrive through the editor's shortcuts even with focus in
## the Scene tree. On a HammerForge selection they run HammerForge's own command
## and are consumed, so Godot does not run its own as well.
func test_global_delete_and_duplicate_claim_a_managed_selection():
	var level = await rig.make_level()
	rig.select([rig.box(level, "a", Vector3.ZERO)])
	assert_true(rig.press_shortcut(PluginRig.key_for("duplicate")), "Ctrl+D is consumed")
	assert_eq(level.draft_brushes_node.get_child_count(), 2, "and duplicates")
	rig.select([level.find_brush_by_id("a")])
	assert_true(rig.press_shortcut(PluginRig.key_for("delete")), "Delete is consumed")
	assert_null(level.find_brush_by_id("a"), "and deletes")
	await rig.leave_level(level)


## A focused text box keeps its keys: Ctrl+D typed into one duplicates nothing,
## and is left for the text box.
func test_a_focused_text_box_keeps_the_shortcut_keys():
	var level = await rig.make_level()
	rig.select([rig.box(level, "a", Vector3.ZERO)])
	var field := LineEdit.new()
	rig.viewport.add_child(field)
	field.grab_focus()
	assert_true(field.has_focus(), "the text box has the keyboard")
	assert_false(rig.press_shortcut(PluginRig.key_for("duplicate")), "Ctrl+D is not taken")
	assert_eq(level.draft_brushes_node.get_child_count(), 1, "and duplicates nothing")
	rig.viewport.remove_child(field)
	field.free()
	await rig.leave_level(level)


## Which focused controls keep the shortcut keys for themselves.
func test_shortcut_focus_rules():
	var line_edit := LineEdit.new()
	add_child_autoqfree(line_edit)
	assert_true(HammerForgePlugin.should_yield_global_shortcut_to_focus(line_edit))
	var text_edit := TextEdit.new()
	add_child_autoqfree(text_edit)
	assert_true(HammerForgePlugin.should_yield_global_shortcut_to_focus(text_edit))
	var spin_box := SpinBox.new()
	add_child_autoqfree(spin_box)
	assert_true(
		HammerForgePlugin.should_yield_global_shortcut_to_focus(spin_box.get_line_edit()),
		"A SpinBox's internal LineEdit keeps editor shortcut ownership",
	)
	var generic_tree := Tree.new()
	add_child_autoqfree(generic_tree)
	assert_true(
		HammerForgePlugin.should_yield_global_shortcut_to_focus(generic_tree),
		"An unrelated editor Tree must keep Delete/Duplicate ownership",
	)
	var item_list := ItemList.new()
	add_child_autoqfree(item_list)
	assert_true(HammerForgePlugin.should_yield_global_shortcut_to_focus(item_list))
	var graph_edit := GraphEdit.new()
	add_child_autoqfree(graph_edit)
	assert_true(HammerForgePlugin.should_yield_global_shortcut_to_focus(graph_edit))
	var scene_tree := Tree.new()
	scene_tree.name = "SceneTree"
	add_child_autoqfree(scene_tree)
	assert_false(
		HammerForgePlugin.should_yield_global_shortcut_to_focus(scene_tree),
		"Scene-tree focus must still route managed Delete/Duplicate",
	)
	var hf_surface := Control.new()
	hf_surface.set_meta("_hammerforge_managed_shortcut_surface", true)
	add_child_autoqfree(hf_surface)
	assert_false(HammerForgePlugin.should_yield_global_shortcut_to_focus(hf_surface))
	assert_false(HammerForgePlugin.should_yield_global_shortcut_to_focus(null))


## Nudge, Rotate and Flip do nothing and say so (false) when nothing of
## HammerForge's is selected, and move a selected entity as well as a brush.
func test_transform_commands_bail_out_without_a_managed_selection():
	var level = await rig.make_level()
	var box = rig.box(level, "a", Vector3.ZERO)
	var lamp = rig.native_node()
	for selection in [[], [lamp]]:
		rig.select(selection)
		var label := "with %s selected" % ("nothing" if selection.is_empty() else "a Godot node")
		assert_false(rig.plugin._nudge_selected(level, Vector3.RIGHT), "Nudge %s" % label)
		assert_false(rig.plugin._rotate_selected(level, 1), "Rotate %s" % label)
		assert_false(rig.plugin._flip_selected(level), "Flip %s" % label)
	assert_eq(box.global_position, Vector3.ZERO, "nothing moved")
	assert_eq(lamp.global_position, Vector3.ZERO)
	var entity = DraftEntity.new()
	entity.entity_type = "light_point"
	level.add_entity(entity)
	rig.select([entity])
	assert_true(rig.plugin._nudge_selected(level, Vector3.RIGHT), "an entity is HammerForge's")
	assert_gt(entity.global_position.x, 0.0, "and moves")
	await rig.leave_level(level)


func test_async_preview_bake_never_goes_through_undo():
	# A grep, because what would go wrong shows only to an undo manager, which the
	# plugin stand-in does not have.
	var bake_preview_source := FileAccess.get_file_as_string(
		"res://addons/hammerforge/plugin_bake_preview.gd"
	)
	var preview_start := bake_preview_source.find("static func toggle")
	var preview_end := bake_preview_source.find("static func sync_after_undo", preview_start)
	var preview_branch := bake_preview_source.substr(preview_start, preview_end - preview_start)
	assert_true(preview_branch.contains("await root.bake"))
	assert_false(
		preview_branch.contains("_commit_state_action"),
		"Async preview bake must never be dispatched through UndoRedo",
	)


func test_entity_alias_change_refreshes_preview_once_and_detaches_old_preview():
	var script := GDScript.new()
	script.source_code = """
extends \"res://addons/hammerforge/draft_entity.gd\"
var preview_update_count := 0
func _update_preview() -> void:
	preview_update_count += 1
func _get_entity_type_hints() -> PackedStringArray:
	return PackedStringArray(["light_point", "player_start"])
func _get_entity_schema() -> Array:
	return [{"name": "intensity", "type": "float", "default": 1.0}]
"""
	assert_eq(script.reload(), OK)
	var entity = script.new()
	add_child_autoqfree(entity)
	var ready_updates: int = entity.preview_update_count

	entity.entity_type = "light_point"
	assert_eq(entity.entity_class, "light_point")
	assert_eq(
		entity.preview_update_count,
		ready_updates + 1,
		"Mirroring type to class should rebuild the preview only once",
	)
	entity.entity_class = "player_start"
	assert_eq(entity.entity_type, "player_start")
	assert_eq(entity.preview_update_count, ready_updates + 2)
	var visible_type_properties := 0
	var entity_class_usage := -1
	for property in entity.get_property_list():
		if str(property.get("name", "")) == "entity_type":
			visible_type_properties += 1
			assert_eq(int(property.get("hint", PROPERTY_HINT_NONE)), PROPERTY_HINT_ENUM)
		if str(property.get("name", "")) == "entity_class":
			entity_class_usage = int(property.get("usage", PROPERTY_USAGE_DEFAULT))
	assert_eq(visible_type_properties, 1, "Inspector must expose one canonical Entity Type")
	if entity_class_usage >= 0:
		assert_eq(entity_class_usage, PROPERTY_USAGE_NONE, "Legacy class alias stays hidden")
	var dynamic_names: Array[String] = []
	for property in entity._get_property_list():
		dynamic_names.append(str(property.get("name", "")))
	assert_true("data/intensity" in dynamic_names)
	assert_false("entity_data/intensity" in dynamic_names, "Legacy data alias must not duplicate")
	assert_true(entity._set(&"entity_data/intensity", 2.5), "Old scenes still migrate on load")
	assert_eq(entity._get(&"data/intensity"), 2.5)

	for index in range(20):
		var preview := MeshInstance3D.new()
		entity._assign_preview(preview)
		assert_eq(str(preview.name), "_EditorPreview")
		entity._clear_preview()
		assert_null(preview.get_parent(), "Preview %d should detach immediately" % index)
		assert_true(preview.is_queued_for_deletion())
		assert_eq(entity.get_children(true).size(), 0)

	var current := MeshInstance3D.new()
	entity._assign_preview(current)
	assert_eq(entity.get_children(true).size(), 1)
	assert_same(entity.preview_node, current)


func test_floor_and_sun_restore_can_toggle_twice_in_the_same_frame():
	var state = root.state_system
	var floor_info := {
		"exists": true,
		"size": Vector3(128, 8, 128),
		"transform": Transform3D(Basis.IDENTITY, Vector3(0, -4, 0)),
		"use_collision": true,
	}
	state.restore_floor_info(floor_info)
	var old_floor := root.get_node("TempFloor") as CSGBox3D
	state.restore_floor_info({"exists": false})
	assert_null(old_floor.get_parent())
	assert_true(old_floor.is_queued_for_deletion())
	state.restore_floor_info(floor_info)
	var new_floor := root.get_node("TempFloor") as CSGBox3D
	assert_ne(new_floor.get_instance_id(), old_floor.get_instance_id())
	assert_false(new_floor.is_queued_for_deletion())

	var sun_info := {
		"exists": true,
		"rotation_degrees": Vector3(-45, 30, 0),
		"shadow_enabled": true,
		"light_energy": 1.0,
	}
	state.restore_sun_info(sun_info)
	var old_sun := root.get_node("DefaultSun") as DirectionalLight3D
	state.restore_sun_info({"exists": false})
	assert_null(old_sun.get_parent())
	assert_true(old_sun.is_queued_for_deletion())
	state.restore_sun_info(sun_info)
	var new_sun := root.get_node("DefaultSun") as DirectionalLight3D
	assert_ne(new_sun.get_instance_id(), old_sun.get_instance_id())
	assert_false(new_sun.is_queued_for_deletion())


# ===========================================================================
# Fake brush system for carve tests
# ===========================================================================


class FakeAnchorVertexSystem:
	extends RefCounted
	const VERTEX_POS := Vector3(1, 2, 3)
	const EDGE_MIDPOINT := Vector3(4, 5, 6)
	enum VertexSubMode { VERTEX, EDGE }
	var sub_mode: int = VertexSubMode.VERTEX
	var anchors: Array = []

	func pick_vertex(_camera, _pos) -> Dictionary:
		return {"brush_id": "b1", "vertex_index": 2, "world_pos": VERTEX_POS}

	func pick_edge(_camera, _pos) -> Dictionary:
		return {"brush_id": "b1", "edge": Vector2i(0, 1), "world_midpoint": EDGE_MIDPOINT}

	func select_vertex(_brush_id, _index, _additive) -> void:
		pass

	func select_edge(_brush_id, _edge, _additive) -> void:
		pass

	func begin_drag(anchor: Vector3) -> void:
		anchors.append(anchor)


class FakeAnchorPlugin:
	extends RefCounted
	var _keymap = null
	var _vertex_drag_active := false
	var _vertex_drag_start := Vector2.ZERO

	func _update_vertex_overlay(_root, _camera) -> void:
		pass


class FakeAnchorRoot:
	extends Node
	var vertex_system = null
