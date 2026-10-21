extends GutTest
## Merge Vertices, Split Edge and Clip to Convex through the real plugin (#1533).
## The key, the command palette and the context toolbar all run the same function
## for each, so each records one undo step whichever way it is run: undo puts the
## brush back and redo makes the edit again. Merge takes every brush with two or
## more vertices selected, in that one step. An edit makes a primitive CUSTOM, and
## its undo makes it the primitive again, with its resize handles (#1538).

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const BrushGizmoPlugin = preload("res://addons/hammerforge/brush_gizmo_plugin.gd")
const LevelRootScript = preload("res://addons/hammerforge/level_root.gd")
const HFPluginVertexOps = preload("res://addons/hammerforge/plugin_vertex_ops.gd")
const BrushShape = LevelRootScript.BrushShape

const STOP := EditorPlugin.AFTER_GUI_INPUT_STOP
const SURFACES := ["key", "palette", "toolbar"]

## The action each surface runs. The toolbar's Split button is "vertex_split",
## and Clip to Convex has no key.
const MERGE := {"key": "vertex_merge", "palette": "vertex_merge", "toolbar": "vertex_merge"}
const SPLIT := {
	"key": "vertex_split_edge", "palette": "vertex_split_edge", "toolbar": "vertex_split"
}
const CLIP := {"palette": "vertex_clip_convex", "toolbar": "vertex_clip_convex"}

var rig := PluginRig.new()


func before_all():
	await rig.bring_up(self, true)


func after_all():
	await rig.take_down()


func _level() -> Node:
	var level = await rig.make_level()
	rig.undo().clear()
	return level


func _leave(level: Node) -> void:
	if rig.plugin._vertex_mode:
		rig.plugin._toggle_vertex_mode(level)
	await rig.leave_level(level)


func _run(surface: String, actions: Dictionary) -> void:
	var action: String = actions[surface]
	match surface:
		"key":
			assert_eq(rig.forward(PluginRig.key_for(action)), STOP, "the key is taken")
		"palette":
			rig.plugin._on_hotkey_palette_action(action)
		"toolbar":
			rig.plugin._context_toolbar.action_requested.emit(action, [])


func _steps() -> int:
	return rig.undo().step_count()


func _step_name() -> String:
	return rig.undo().scene_history.get_current_action_name()


func _undo() -> void:
	rig.undo().press_undo()
	await rig.frame()


func _redo() -> void:
	rig.undo().press_redo()
	await rig.frame()


func _said(text: String) -> bool:
	for toast in rig.toasts():
		if str(toast).contains(text):
			return true
	return false


## Vertex mode on `brushes`, with the vertices `wanted` picks out of each one's
## local vertices selected.
func _select_vertices(level: Node, brushes: Array, wanted: Callable) -> void:
	rig.select(brushes)
	rig.forward(PluginRig.key_for("vertex_edit"))
	assert_true(rig.plugin._vertex_mode, "vertex mode is on")
	var vs = level.vertex_system
	for brush in brushes:
		var verts: PackedVector3Array = vs.get_brush_vertices(brush)
		for i in verts.size():
			if wanted.call(verts[i]):
				vs.select_vertex(str(brush.brush_id), i, true)


func _world_vertices(level: Node, brush_id: String) -> Array:
	var brush = level.find_brush_by_id(brush_id)
	var out: Array = []
	for v in level.vertex_system.get_brush_vertices(brush):
		out.append(brush.global_transform * v)
	return out


func _has_point(points: Array, wanted: Vector3) -> bool:
	for point in points:
		if (point as Vector3).is_equal_approx(wanted):
			return true
	return false


# ===========================================================================
# Merge Vertices
# ===========================================================================


func test_merge_from_each_surface_is_one_step_that_undo_reverts(surface = use_parameters(SURFACES)):
	assert_not_null(rig.plugin, rig.error())
	var level = await _level()
	var brush = rig.box(level, "m", Vector3.ZERO)
	_select_vertices(level, [brush], func(v: Vector3): return v.y > 0.0)
	var before := _world_vertices(level, "m")
	_run(surface, MERGE)
	var merged := _world_vertices(level, "m")
	assert_eq(merged.size(), 5, "%s: the top four went to one point" % surface)
	assert_true(_has_point(merged, Vector3(0, 2, 0)), "at their centroid: %s" % str(merged))
	assert_false(level.vertex_system.has_selection(), "the selection is cleared")
	assert_eq(_steps(), 1, "%s: one step" % surface)
	assert_eq(_step_name(), "Merge Vertices", "named for the command")
	await _undo()
	var undone := _world_vertices(level, "m")
	assert_eq(undone.size(), 8, "%s: undo puts the box back" % surface)
	for corner in before:
		assert_true(_has_point(undone, corner), "with its corner at %s" % corner)
	await _redo()
	assert_eq(_world_vertices(level, "m").size(), 5, "%s: redo merges again" % surface)
	await _leave(level)


func test_merge_takes_every_brush_with_two_vertices_selected_in_one_step():
	var level = await _level()
	var a = rig.box(level, "a", Vector3.ZERO)
	var b = rig.box(level, "b", Vector3(10, 0, 0))
	_select_vertices(level, [a, b], func(v: Vector3): return v.y > 0.0)
	_run("key", MERGE)
	assert_eq(_world_vertices(level, "a").size(), 5, "the first brush merged")
	assert_eq(_world_vertices(level, "b").size(), 5, "and the second, not only the first")
	assert_eq(_steps(), 1, "both in one step")
	await _undo()
	assert_eq(_world_vertices(level, "a").size(), 8, "one undo puts back the first")
	assert_eq(_world_vertices(level, "b").size(), 8, "and the second")
	await _leave(level)


func test_a_refused_merge_changes_nothing_and_adds_no_step():
	var level = await _level()
	var brush = rig.box(level, "r", Vector3.ZERO)
	# Every vertex of a box to one point leaves no closed solid.
	_select_vertices(level, [brush], func(_v: Vector3): return true)
	var before := _world_vertices(level, "r")
	rig.clear_toasts()
	_run("palette", MERGE)
	assert_eq(_world_vertices(level, "r"), before, "nothing moved")
	assert_eq(_steps(), 0, "no step")
	assert_true(_said("Merge rejected"), "and it said why: %s" % str(rig.toasts()))
	await _leave(level)


func test_with_one_vertex_selected_merge_says_so_and_adds_no_step():
	var level = await _level()
	var brush = rig.box(level, "o", Vector3.ZERO)
	_select_vertices(level, [brush], func(v: Vector3): return v.is_equal_approx(Vector3(2, 2, 2)))
	rig.clear_toasts()
	_run("toolbar", MERGE)
	assert_eq(_world_vertices(level, "o").size(), 8, "nothing merged")
	assert_eq(_steps(), 0, "no step")
	assert_true(_said("two or more vertices"), "and it said why: %s" % str(rig.toasts()))
	await _leave(level)


# ===========================================================================
# Split Edge
# ===========================================================================


## Edge mode on `brush` with its first edge selected. Returns the edge's midpoint
## in world space.
func _select_first_edge(level: Node, brush: Node) -> Vector3:
	_select_vertices(level, [brush], func(_v: Vector3): return false)
	rig.forward(PluginRig.key_for("vertex_edge_mode"))
	var vs = level.vertex_system
	assert_eq(vs.sub_mode, vs.VertexSubMode.EDGE, "edge mode is on")
	var edge: Array = vs.get_brush_edges(brush)[0]
	vs.select_edge(str(brush.brush_id), edge, false)
	var verts: PackedVector3Array = vs.get_brush_vertices(brush)
	return brush.global_transform * ((verts[edge[0]] + verts[edge[1]]) * 0.5)


func test_split_from_each_surface_is_one_step_that_undo_reverts(surface = use_parameters(SURFACES)):
	var level = await _level()
	var brush = rig.box(level, "s", Vector3.ZERO)
	var midpoint := _select_first_edge(level, brush)
	_run(surface, SPLIT)
	var split := _world_vertices(level, "s")
	assert_eq(split.size(), 9, "%s: the edge gained a vertex" % surface)
	assert_true(_has_point(split, midpoint), "at its middle: %s" % midpoint)
	assert_false(level.vertex_system.has_selection(), "the selection is cleared")
	assert_eq(_steps(), 1, "%s: one step" % surface)
	assert_eq(_step_name(), "Split Edge", "named for the command")
	await _undo()
	var undone := _world_vertices(level, "s")
	assert_eq(undone.size(), 8, "%s: undo takes the vertex out" % surface)
	assert_false(_has_point(undone, midpoint))
	await _redo()
	assert_true(_has_point(_world_vertices(level, "s"), midpoint), "%s: redo" % surface)
	await _leave(level)


func test_with_no_edge_selected_split_says_so_and_adds_no_step():
	var level = await _level()
	var brush = rig.box(level, "n", Vector3.ZERO)
	_select_vertices(level, [brush], func(_v: Vector3): return false)
	rig.clear_toasts()
	_run("palette", SPLIT)
	assert_eq(_world_vertices(level, "n").size(), 8, "nothing split")
	assert_eq(_steps(), 0, "no step")
	assert_true(_said("select one edge"), "and it said why: %s" % str(rig.toasts()))
	await _leave(level)


# ===========================================================================
# Clip to Convex
# ===========================================================================


## A 4 x 4 x 4 box with its top corner at +X +Z pushed into its middle, which a
## vertex edit could not leave behind but an import can.
func _dented_box(level: Node, id: String) -> Node:
	var brush = rig.box(level, id, Vector3.ZERO)
	for face in brush.faces:
		var updated := PackedVector3Array()
		for vertex in face.local_verts:
			updated.append(Vector3.ZERO if vertex.is_equal_approx(Vector3(2, 2, 2)) else vertex)
		face.local_verts = updated
		face.ensure_geometry()
	brush.mark_faces_authoritative()
	assert_false(level.vertex_system.validate_convexity(brush), "the fixture starts dented")
	return brush


func test_clip_to_convex_from_the_palette_and_toolbar_is_one_step(
	surface = use_parameters(CLIP.keys())
):
	var level = await _level()
	var brush := _dented_box(level, "c")
	_select_vertices(level, [brush], func(_v: Vector3): return true)
	assert_true(_has_point(_world_vertices(level, "c"), Vector3.ZERO), "the dent is a vertex")
	_run(surface, CLIP)
	var clipped := _world_vertices(level, "c")
	assert_eq(clipped.size(), 7, "%s: the dent went, the other corners stayed" % surface)
	assert_false(_has_point(clipped, Vector3.ZERO))
	assert_false(level.vertex_system.has_selection(), "the selection is cleared")
	assert_eq(_steps(), 1, "%s: one step" % surface)
	assert_eq(_step_name(), "Clip to Convex", "named for the command")
	await _undo()
	var undone := _world_vertices(level, "c")
	assert_eq(undone.size(), 8, "%s: undo puts the dent back" % surface)
	assert_true(_has_point(undone, Vector3.ZERO))
	await _redo()
	assert_eq(_world_vertices(level, "c").size(), 7, "%s: redo clips again" % surface)
	await _leave(level)


func test_clip_on_a_convex_brush_adds_no_step():
	var level = await _level()
	var brush = rig.box(level, "k", Vector3.ZERO)
	_select_vertices(level, [brush], func(_v: Vector3): return true)
	rig.clear_toasts()
	_run("toolbar", CLIP)
	assert_eq(_steps(), 0, "no step")
	assert_true(level.vertex_system.has_selection(), "the selection is kept")
	assert_true(_said("already convex"), "and it said so: %s" % str(rig.toasts()))
	await _leave(level)


# ===========================================================================
# Undo puts the primitive back (#1538)
# ===========================================================================

## Each edit on a primitive, and the primitive it starts from. Every one of them
## makes the brush CUSTOM, which takes its resize handles and stops `size` from
## reaching its faces. A torus is the primitive that is not convex, so it is the
## one Clip to Convex can be run on.
const PRIMITIVE_EDITS := [
	{"edit": "merge", "shape": "box"},
	{"edit": "drag", "shape": "box"},
	{"edit": "merge", "shape": "cylinder"},
	{"edit": "drag", "shape": "cylinder"},
	{"edit": "split", "shape": "box"},
	{"edit": "clip", "shape": "torus"},
]
const SHAPES := {"box": BrushShape.BOX, "cylinder": BrushShape.CYLINDER, "torus": BrushShape.TORUS}


## A 4 x 4 x 4 primitive at the origin, with eight sides when it is round.
func _primitive_brush(level: Node, shape_name: String) -> Node:
	var info := {
		"shape": SHAPES[shape_name],
		"size": Vector3(4, 4, 4),
		"sides": 8,
		"center": Vector3.ZERO,
		"brush_id": "p",
	}
	return level.create_brush_from_info(info)


## What a primitive is beyond its faces: what undo has to put back.
func _primitive_of(brush: Node) -> Dictionary:
	return {
		"shape": brush.shape,
		"size": brush.size,
		"sides": brush.sides,
		"handles": BrushGizmoPlugin.supports_resize_handles(brush),
	}


## The top of `brush` dragged up `rise`, as a release in the viewport commits it.
func _drag_top_up(level: Node, brush: Node, rise: float) -> void:
	_select_vertices(level, [brush], func(v: Vector3): return v.y > 0.0)
	var vs = level.vertex_system
	vs.begin_drag(brush.global_transform * Vector3(0, 2, 0))
	assert_true(vs.update_drag_absolute(Vector3(0, rise, 0)), "the drag is taken")
	var snapshots: Dictionary = vs.end_drag()
	assert_false(snapshots.is_empty(), "the drag changed the brush")
	rig.plugin._commit_vertex_move(level, snapshots)


func _edit(level: Node, brush: Node, edit: String) -> void:
	match edit:
		"merge":
			_select_vertices(level, [brush], func(v: Vector3): return v.y > 0.0)
			_run("key", MERGE)
		"drag":
			_drag_top_up(level, brush, 1.0)
		"split":
			_select_first_edge(level, brush)
			_run("key", SPLIT)
		"clip":
			_select_vertices(level, [brush], func(_v: Vector3): return true)
			_run("palette", CLIP)


func test_undo_of_a_vertex_edit_puts_the_primitive_back(case = use_parameters(PRIMITIVE_EDITS)):
	var label := "%s on a %s" % [case["edit"], case["shape"]]
	var level = await _level()
	var brush = _primitive_brush(level, case["shape"])
	var primitive := _primitive_of(brush)
	assert_true(primitive["handles"], "%s: the fixture starts with its handles" % label)
	var vertices_before := _world_vertices(level, "p")
	var bounds_before: AABB = level.brush_system.world_bounds_of(brush)
	_edit(level, brush, case["edit"])
	assert_eq(_steps(), 1, "%s: one step" % label)
	assert_eq(brush.shape, BrushShape.CUSTOM, "%s: the edit made the brush custom" % label)
	var edited := _world_vertices(level, "p")
	assert_ne(edited, vertices_before, "%s: and changed it" % label)

	await _undo()
	assert_eq(_primitive_of(brush), primitive, "%s: undo puts the primitive back" % label)
	assert_eq(_world_vertices(level, "p"), vertices_before, "%s: with its faces" % label)

	await _redo()
	assert_eq(brush.shape, BrushShape.CUSTOM, "%s: redo makes it custom again" % label)
	assert_false(BrushGizmoPlugin.supports_resize_handles(brush), "%s: no handles" % label)
	assert_eq(_world_vertices(level, "p"), edited, "%s: with the edit" % label)

	await _undo()
	brush.size = Vector3(6, 6, 6)
	var resized: AABB = level.brush_system.world_bounds_of(brush)
	assert_true(
		resized.size.is_equal_approx(bounds_before.size * 1.5),
		"%s: after undo the size reaches the faces: %s" % [label, resized]
	)
	await _leave(level)


func test_undo_puts_back_a_face_the_edit_reshaped_exactly_and_quietly():
	# A side face with UVs of its own: the merge makes it a triangle, and nothing
	# of the box it goes back to has its corners. The faces go on before the box
	# is built again, so the rebuild never has to match the triangle and warn
	# that its UVs had nowhere to go, and they come back as they were taken.
	var level = await _level()
	var brush = rig.box(level, "u", Vector3.ZERO)
	for face in brush.faces:
		if face.normal.x > 0.9:
			face.uv_scale = Vector2(2, 2)
			face.custom_uvs = PackedVector2Array(
				[Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
			)
	var faces_before: Array = brush.serialize_faces()
	_select_vertices(level, [brush], func(v: Vector3): return v.y > 0.0)
	_run("key", MERGE)
	assert_eq(brush.shape, BrushShape.CUSTOM, "the merge made the box custom")
	HFLog.begin_test_capture(["went from"])
	await _undo()
	var warned := HFLog.get_captured_warnings()
	HFLog.end_test_capture()
	assert_eq(brush.shape, BrushShape.BOX, "undo makes it a box again")
	assert_eq(brush.serialize_faces(), faces_before, "with the faces it had, UVs and all")
	assert_eq(warned, [], "and says nothing was lost")
	await _leave(level)


# ===========================================================================
# The selection goes with the faces through undo (#1561)
# ===========================================================================

## How a corner is moved: typed into Selection Info, or dragged and let go.
const MOVES := ["typed", "drag"]


## The one selected vertex of `brush`, where it stands now.
func _selected_vertex(level: Node, brush: Node) -> Vector3:
	var vs = level.vertex_system
	var indices: PackedInt32Array = vs.selected_vertices.get(
		str(brush.brush_id), PackedInt32Array()
	)
	if indices.size() != 1:
		return Vector3(INF, INF, INF)
	return vs.get_brush_vertices(brush)[indices[0]]


func test_undo_and_redo_keep_a_moved_corner_selected(move = use_parameters(MOVES)):
	# Out along X this corner bends an X side of the box, and the cut renumbers
	# the box's vertices: the selection after the edit is a different index from
	# the one before it, and each names its own side of the step.
	var level = await _level()
	var brush = rig.box(level, "s", Vector3.ZERO)
	var corner := Vector3(2, -2, -2)
	var goal := Vector3(3, -2, -2)
	_select_vertices(level, [brush], func(v: Vector3): return v.is_equal_approx(corner))
	if move == "typed":
		assert_true(HFPluginVertexOps.move_selected_vertex_to(rig.plugin, level, goal, true))
	else:
		var vs = level.vertex_system
		vs.begin_drag(brush.global_transform * corner)
		assert_true(vs.update_drag_absolute(goal - corner), "the drag is taken")
		rig.plugin._commit_vertex_move(level, vs.end_drag())
	assert_eq(_steps(), 1, "%s: one step" % move)
	assert_eq(_selected_vertex(level, brush), goal, "%s: the moved corner is selected" % move)
	await _undo()
	assert_eq(_selected_vertex(level, brush), corner, "%s: undo selects it where it was" % move)
	await _redo()
	assert_eq(_selected_vertex(level, brush), goal, "%s: and redo where it went" % move)
	await _leave(level)
