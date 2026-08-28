@tool
extends RefCounted
class_name HFSnapSystem
## Centralized snap system with grid, vertex, center, edge, and perpendicular modes.

const DraftBrush = preload("brush_instance.gd")

enum SnapMode { GRID = 1, VERTEX = 2, CENTER = 4, EDGE = 8, PERPENDICULAR = 16 }

var root: Node3D
var enabled_modes: int = SnapMode.GRID
var snap_threshold: float = 2.0
var _custom_snap_origin: Vector3 = Vector3.ZERO
var _custom_snap_dir: Vector3 = Vector3.ZERO
var _has_custom_snap := false


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

	# Geometry snap candidates (vertex / center / edge / perpendicular)
	if (
		is_mode_on(SnapMode.VERTEX)
		or is_mode_on(SnapMode.CENTER)
		or is_mode_on(SnapMode.EDGE)
		or is_mode_on(SnapMode.PERPENDICULAR)
	):
		var candidates := _collect_candidates(exclude_ids, point)
		for c in candidates:
			var d := point.distance_to(c)
			if d < snap_threshold and d < best_dist:
				best = c
				best_dist = d

	# Custom snap line (from measure tool "Align to this")
	if _has_custom_snap:
		var projected := _project_onto_line(point, _custom_snap_origin, _custom_snap_dir)
		var d := point.distance_to(projected)
		if d < snap_threshold and d < best_dist:
			best = projected
			best_dist = d

	if best_dist == INF:
		return point
	return best


func set_custom_snap_line(origin: Vector3, direction: Vector3) -> void:
	_custom_snap_origin = origin
	_custom_snap_dir = direction.normalized()
	_has_custom_snap = true


func clear_custom_snap_line() -> void:
	_has_custom_snap = false
	_custom_snap_origin = Vector3.ZERO
	_custom_snap_dir = Vector3.ZERO


func _project_onto_line(point: Vector3, line_origin: Vector3, line_dir: Vector3) -> Vector3:
	var to_point: Vector3 = point - line_origin
	var t: float = to_point.dot(line_dir)
	return line_origin + line_dir * t


func _collect_candidates(exclude_ids: Array, point: Vector3 = Vector3.ZERO) -> PackedVector3Array:
	var out := PackedVector3Array()
	if not root or not root.has_method("_iter_pick_nodes"):
		return out
	var do_vertex := is_mode_on(SnapMode.VERTEX)
	var do_center := is_mode_on(SnapMode.CENTER)
	var do_edge := is_mode_on(SnapMode.EDGE)
	var do_perp := is_mode_on(SnapMode.PERPENDICULAR)
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
		var corners := PackedVector3Array(
			[
				pos + Vector3(-half.x, -half.y, -half.z),
				pos + Vector3(-half.x, -half.y, half.z),
				pos + Vector3(-half.x, half.y, -half.z),
				pos + Vector3(-half.x, half.y, half.z),
				pos + Vector3(half.x, -half.y, -half.z),
				pos + Vector3(half.x, -half.y, half.z),
				pos + Vector3(half.x, half.y, -half.z),
				pos + Vector3(half.x, half.y, half.z),
			]
		)
		if do_vertex:
			out.append_array(corners)
		if do_edge or do_perp:
			# 12 AABB edges, same corner order as vertex snap.
			var edges := [
				[0, 1],
				[0, 2],
				[0, 4],
				[1, 3],
				[1, 5],
				[2, 3],
				[2, 6],
				[3, 7],
				[4, 5],
				[4, 6],
				[5, 7],
				[6, 7],
			]
			for edge in edges:
				if do_edge:
					out.append((corners[edge[0]] + corners[edge[1]]) * 0.5)
				if do_perp:
					out.append(_closest_point_on_segment(point, corners[edge[0]], corners[edge[1]]))
	return out


func _closest_point_on_segment(point: Vector3, a: Vector3, b: Vector3) -> Vector3:
	var ab: Vector3 = b - a
	var len_sq: float = ab.length_squared()
	if len_sq < 0.000001:
		return a
	var t: float = clampf((point - a).dot(ab) / len_sq, 0.0, 1.0)
	return a + ab * t
