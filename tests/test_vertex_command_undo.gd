extends GutTest
## Merge Vertices, Split Edge and Clip to Convex through the real plugin (#1533).
## The key, the command palette and the context toolbar all run the same function
## for each, so each records one undo step whichever way it is run: undo puts the
## brush back and redo makes the edit again. Merge takes every brush with two or
## more vertices selected, in that one step.

const PluginRig = preload("res://tests/support/plugin_rig.gd")

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
