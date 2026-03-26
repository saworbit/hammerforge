@tool
extends RefCounted
class_name HFSnapSystem
## Centralized snap system with grid, vertex (brush corners), and center snap modes.
## Replaces the simple grid-only snapping with geometry-aware snapping.

const DraftBrush = preload("brush_instance.gd")

enum SnapMode { GRID = 1, VERTEX = 2, CENTER = 4 }

var root: Node3D
var enabled_modes: int = SnapMode.GRID
var snap_threshold: float = 2.0


func _init(level_root: Node3D) -> void:
	root = level_root


func set_mode(mode: int, on: bool) -> void:
	if on:
		enabled_modes = enabled_modes | mode
	else:
		enabled_modes = enabled_modes & ~mode


func is_mode_on(mode: int) -> bool:
	return (enabled_modes & mode) != 0


func snap_point(point: Vector3, grid_snap: float, exclude_ids: Array = []) -> Vector3:
	var best := point
	var best_dist := INF

	# Grid snap candidate
	if is_mode_on(SnapMode.GRID) and grid_snap > 0.0:
		var grid_vec := Vector3(grid_snap, grid_snap, grid_snap)
		var grid_snapped := point.snapped(grid_vec)
		var d := point.distance_to(grid_snapped)
		if d < best_dist:
			best = grid_snapped
			best_dist = d

	# Geometry snap candidates (vertex / center)
	if is_mode_on(SnapMode.VERTEX) or is_mode_on(SnapMode.CENTER):
		var candidates := _collect_candidates(exclude_ids)
		for c in candidates:
			var d := point.distance_to(c)
			if d < snap_threshold and d < best_dist:
				best = c
				best_dist = d

	if best_dist == INF:
		return point
	return best


func _collect_candidates(exclude_ids: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	if not root or not root.has_method("_iter_pick_nodes"):
		return out
	var do_vertex := is_mode_on(SnapMode.VERTEX)
	var do_center := is_mode_on(SnapMode.CENTER)
	var preview = root.get("preview_brush")
	for node in root._iter_pick_nodes():
		if not (node is DraftBrush):
			continue
		if node == preview:
			continue
		var brush := node as DraftBrush
		if exclude_ids.has(str(brush.brush_id)):
			continue
		var pos := brush.global_position
		var half := brush.size * 0.5
		if do_center:
			out.append(pos)
		if do_vertex:
			out.append(pos + Vector3(-half.x, -half.y, -half.z))
			out.append(pos + Vector3(-half.x, -half.y, half.z))
			out.append(pos + Vector3(-half.x, half.y, -half.z))
			out.append(pos + Vector3(-half.x, half.y, half.z))
			out.append(pos + Vector3(half.x, -half.y, -half.z))
			out.append(pos + Vector3(half.x, -half.y, half.z))
			out.append(pos + Vector3(half.x, half.y, -half.z))
			out.append(pos + Vector3(half.x, half.y, half.z))
	return out
