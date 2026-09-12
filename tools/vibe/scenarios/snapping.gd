@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## `HFSnapSystem`: where a point actually lands.
##
## Snapping is the one subsystem that runs on every mouse motion event and whose
## output nobody checks -- a brush placed 3 units off is a brush the mapper
## placed, as far as the level is concerned. Two things are worth asking of it:
## which candidate wins when several are in range, and whether the geometry it
## measures is still the geometry that is there, given that it caches per brush.


func id() -> String:
	return "snapping"


func summary() -> String:
	return "which snap candidate wins, and whether the cached face geometry keeps up with the brush"


func run() -> void:
	await _grid_against_vertex()
	await _the_face_geometry_cache_after_an_edit()
	await _a_snap_line_with_no_direction()


func _bid(node: Node) -> String:
	return str(node.get_meta("brush_id", ""))


## Both modes on, a brush corner within the snap threshold, and a grid node
## slightly nearer. Vertex snap is the explicit one -- it is on because the
## mapper wants to meet existing geometry exactly.
func _grid_against_vertex() -> void:
	var root: Node3D = await fresh_root()
	var b := box(root, Vector3(64, 64, 64), Vector3(96, 32, 0))
	await frame()

	var snap = root.snap_system
	snap.enabled_modes = snap.SnapMode.GRID | snap.SnapMode.VERTEX
	snap.snap_threshold = 2.0

	# The brush's near-top corner, and a probe 1.5 units from it that also sits
	# 0.5 from a 64-grid node.
	var corner := Vector3(64, 64, -32)
	var probe := Vector3(64.5, 64.0, -30.5)
	note("corner", corner)
	note("probe distance to the corner", probe.distance_to(corner))
	note("probe distance to its grid node", probe.distance_to(probe.snapped(Vector3(64, 64, 64))))
	var landed: Vector3 = snap.snap_point(probe, 64.0)
	note("snap_point landed on", landed)
	if not landed.is_equal_approx(corner):
		flag(
			"grid snap beats vertex snap whenever the grid node is nearer",
			(
				"snap_point() picks by raw distance, so with the grid on there is no way to"
				+ " meet a corner that is further away than the grid node under the cursor:"
				+ (
					" the corner at %s is %.2f away and within the 2.0 threshold, the point"
					% [corner, probe.distance_to(corner)]
				)
				+ (
					" still landed on %s. Vertex, centre and edge snap are the explicit ones;"
					% landed
				)
				+ " they should outrank the grid rather than compete with it on distance."
			)
		)

	# The same probe with the grid off, to show the corner was reachable.
	snap.enabled_modes = snap.SnapMode.VERTEX
	note("with grid snap off, the same probe lands on", snap.snap_point(probe, 64.0))


## Face snap geometry is cached per brush id and re-used until the brush says it
## changed. The stamp is (instance id, face count, size), plus the two signals.
func _the_face_geometry_cache_after_an_edit() -> void:
	var root: Node3D = await fresh_root()
	var b := box(root, Vector3(64, 64, 64))
	await frame()
	var brush_id := _bid(b)

	var snap = root.snap_system
	snap.enabled_modes = snap.SnapMode.VERTEX
	snap.snap_threshold = 4.0

	var before = snap._collect_candidates([])
	note("vertex candidates for one box", before.size())

	# Move one corner 32 units out, the way the vertex tool does.
	var vs = root.vertex_system
	vs.select_vertex(brush_id, 0)
	var corner_before: Vector3 = vs.get_brush_vertices(b)[0]
	var moved: bool = vs.move_vertices(Vector3(32, 0, 0))
	await frame()
	var corner_after: Vector3 = vs.get_brush_vertices(b)[0]
	note("vertex 0 before / after", "%s -> %s" % [corner_before, corner_after])
	note("move_vertices returned", moved)

	var after = snap._collect_candidates([])
	var has_new := false
	var has_old := false
	for c in after:
		if c.is_equal_approx(corner_after):
			has_new = true
		if c.is_equal_approx(corner_before):
			has_old = true
	note("the old corner is still offered", has_old)
	note("candidates after the move", after.size())
	note("the moved corner is offered as a snap target", has_new)
	if moved and not has_new:
		flag(
			"the snap system keeps offering a corner the brush no longer has",
			(
				"_cached_face_geometry() re-uses its entry while the instance id, the face"
				+ " count and the brush size all match -- a vertex move changes none of those."
				+ " The cursor snaps to where the corner used to be."
			)
		)

	# Removing the brush entirely: the cache is keyed by brush id.
	root.brush_system.delete_brush(b)
	await frame()
	var after_delete = snap._collect_candidates([])
	note("candidates after deleting the brush", after_delete.size())
	note("cache entries still held", snap._face_geometry_cache.size())


## `set_custom_snap_line()` normalises whatever direction it is handed and sets
## the flag either way.
func _a_snap_line_with_no_direction() -> void:
	var root: Node3D = await fresh_root()
	box(root, Vector3(64, 64, 64))
	await frame()
	var snap = root.snap_system
	snap.enabled_modes = 0
	snap.snap_threshold = 1000.0
	snap.set_custom_snap_line(Vector3(10, 20, 30), Vector3.ZERO)
	var landed: Vector3 = snap.snap_point(Vector3(0, 0, 0), 0.0)
	note("snap_point with a zero-direction custom line", landed)
	if landed.is_equal_approx(Vector3(10, 20, 30)):
		known(
			411,
			"a custom snap line with no direction collapses every point onto its origin",
			(
				"set_custom_snap_line() normalises the direction to (0,0,0) and still sets"
				+ " _has_custom_snap, so _project_onto_line() returns the origin for every"
				+ " input. Inside the snap threshold that is where everything lands. The one"
				+ " caller guards the length itself; the system does not."
			)
		)
	snap.clear_custom_snap_line()

	# A negative threshold: nothing rejects it.
	snap.enabled_modes = snap.SnapMode.VERTEX
	snap.snap_threshold = -10.0
	note("snap_point with a negative threshold", snap.snap_point(Vector3(1, 1, 1), 0.0))
