@tool
extends RefCounted
class_name MapIO

const LevelRoot = preload("level_root.gd")
const DraftBrush = preload("brush_instance.gd")
const DraftEntity = preload("draft_entity.gd")
const HFMapAdapterType = preload("map_adapters/hf_map_adapter.gd")
const HFMapQuakeType = preload("map_adapters/hf_map_quake.gd")

const DEFAULT_TEXTURE := "__default"
const AXIS_THRESHOLD := 0.98

## Vertex snapping tolerance for imported .map geometry.  Vertices closer than
## this distance are welded to their average position to eliminate floating-point
## drift from legacy editors.  Set to 0.0 to disable.
static var import_weld_tolerance: float = 0.01


static func load_map(path: String) -> Dictionary:
	if path == "" or not FileAccess.file_exists(path):
		return {}
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return {}
	var text = file.get_as_text()
	return parse_map_text(text)


static func parse_map_text(text: String) -> Dictionary:
	var lines = text.replace("\r", "").split("\n")
	var entities: Array = []
	var current_entity: Dictionary = {}
	var current_brush: Dictionary = {}
	var in_entity = false
	var in_brush = false
	var face_re = RegEx.new()
	face_re.compile("\\(([^\\)]+)\\)")
	for raw_line in lines:
		var line = raw_line.strip_edges()
		if line == "" or line.begins_with("//"):
			continue
		var comment_index = line.find("//")
		if comment_index >= 0:
			line = line.substr(0, comment_index).strip_edges()
		if line == "":
			continue
		if line == "{":
			if not in_entity:
				in_entity = true
				current_entity = {"properties": {}, "brushes": []}
				continue
			if in_entity and not in_brush:
				in_brush = true
				current_brush = {"faces": []}
				continue
		if line == "}":
			if in_brush:
				current_entity["brushes"].append(current_brush)
				current_brush = {}
				in_brush = false
				continue
			if in_entity:
				entities.append(current_entity)
				current_entity = {}
				in_entity = false
				continue
		if in_brush:
			var face = _parse_face_line(line, face_re)
			if not face.is_empty():
				current_brush["faces"].append(face)
			continue
		if in_entity:
			var kv = _parse_key_value(line)
			if kv.size() == 2:
				current_entity["properties"][kv[0]] = kv[1]
			continue
	# Weld near-coincident vertices across all parsed faces to close micro-gaps
	if import_weld_tolerance > 0.0:
		for entity in entities:
			for brush in entity.get("brushes", []):
				_snap_parsed_vertices(brush.get("faces", []), import_weld_tolerance)

	var brushes: Array = []
	var entity_points: Array = []
	for entity in entities:
		var props: Dictionary = entity.get("properties", {})
		var entity_class = str(props.get("classname", ""))
		var origin = _parse_origin(str(props.get("origin", "")))
		var has_brushes = entity.get("brushes", []).size() > 0
		if not has_brushes and entity_class != "":
			entity_points.append({"classname": entity_class, "origin": origin, "properties": props})
		for brush in entity.get("brushes", []):
			var info = _brush_from_faces(brush.get("faces", []))
			if not info.is_empty():
				brushes.append(info)
	return {"entities": entity_points, "brushes": brushes}


static func export_map_from_level(level_root: Node, adapter: HFMapAdapterType = null) -> String:
	if not level_root:
		return ""
	if adapter == null:
		adapter = HFMapQuakeType.new()
	var lines: Array[String] = []
	lines.append("{")
	lines.append('"classname" "worldspawn"')
	var brush_nodes: Array = []
	if level_root.has_method("_iter_pick_nodes"):
		brush_nodes.append_array(level_root.call("_iter_pick_nodes"))
	var committed = level_root.get_node_or_null("CommittedCuts")
	if committed:
		brush_nodes.append_array(committed.get_children())
	for node in brush_nodes:
		if not (node is DraftBrush):
			continue
		if level_root.has_method("is_entity_node") and level_root.is_entity_node(node):
			continue
		if node.get_parent() and node.get_parent().name == "PendingCuts":
			continue
		var brush_lines = _brush_to_map_lines(node, adapter)
		if brush_lines.is_empty():
			continue
		lines.append("{")
		lines.append_array(brush_lines)
		lines.append("}")
	lines.append("}")
	if level_root.has_method("_iter_pick_nodes"):
		for node in level_root.call("_iter_pick_nodes"):
			if not (node is DraftEntity):
				continue
			var ent_lines = _entity_to_map_lines(node, adapter)
			if ent_lines.is_empty():
				continue
			lines.append_array(ent_lines)
	return "\n".join(lines)


static func _entity_to_map_lines(
	entity: DraftEntity, adapter: HFMapAdapterType = null
) -> Array[String]:
	if not entity:
		return []
	var entity_class = entity.entity_class if entity.entity_class != "" else entity.entity_type
	if entity_class == "":
		return []
	var lines: Array[String] = []
	lines.append("{")
	var props := {"classname": entity_class, "origin": _format_vec3(entity.global_transform.origin)}
	if adapter:
		lines.append_array(adapter.format_entity_properties(props))
	else:
		lines.append('"classname" "%s"' % entity_class)
		lines.append('"origin" "%s"' % _format_vec3(entity.global_transform.origin))
	lines.append("}")
	return lines


static func _brush_from_faces(faces: Array) -> Dictionary:
	if faces.is_empty():
		return {}
	var points: Array = []
	var axis_aligned = true
	for face in faces:
		var face_points: Array = face.get("points", [])
		if face_points.size() < 3:
			continue

		points.append_array(face_points)
		var normal = _face_normal(face_points)
		if _axis_from_normal(normal) == Vector3.ZERO:
			axis_aligned = false
	if points.is_empty():
		return {}
	var min_pt = Vector3(INF, INF, INF)
	var max_pt = Vector3(-INF, -INF, -INF)
	for p in points:
		min_pt.x = min(min_pt.x, p.x)
		min_pt.y = min(min_pt.y, p.y)
		min_pt.z = min(min_pt.z, p.z)
		max_pt.x = max(max_pt.x, p.x)
		max_pt.y = max(max_pt.y, p.y)
		max_pt.z = max(max_pt.z, p.z)
	var size = max_pt - min_pt
	if size.length() <= 0.001:
		return {}
	var center = (min_pt + max_pt) * 0.5
	if axis_aligned and faces.size() <= 8:
		return {
			"shape": LevelRoot.BrushShape.BOX,
			"size": size,
			"center": center,
			"operation": CSGShape3D.OPERATION_UNION
		}
	return {
		"shape": LevelRoot.BrushShape.CYLINDER,
		"size": Vector3(max(size.x, size.z), size.y, max(size.x, size.z)),
		"center": center,
		"operation": CSGShape3D.OPERATION_UNION
	}


static func _face_normal(face_points: Array) -> Vector3:
	if face_points.size() < 3:
		return Vector3.ZERO
	var a: Vector3 = face_points[0]
	var b: Vector3 = face_points[1]
	var c: Vector3 = face_points[2]
	var n = (b - a).cross(c - a)
	return n.normalized() if n.length() > 0.0001 else Vector3.ZERO


static func _axis_from_normal(normal: Vector3) -> Vector3:
	var nx = abs(normal.x)
	var ny = abs(normal.y)
	var nz = abs(normal.z)
	if nx > AXIS_THRESHOLD and ny < 0.1 and nz < 0.1:
		return Vector3(sign(normal.x), 0, 0)
	if ny > AXIS_THRESHOLD and nx < 0.1 and nz < 0.1:
		return Vector3(0, sign(normal.y), 0)
	if nz > AXIS_THRESHOLD and nx < 0.1 and ny < 0.1:
		return Vector3(0, 0, sign(normal.z))
	return Vector3.ZERO


static func _parse_origin(text: String) -> Vector3:
	if text == "":
		return Vector3.ZERO
	var parts = text.strip_edges().split(" ")
	if parts.size() < 3:
		return Vector3.ZERO
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))


static func _parse_key_value(line: String) -> Array:
	var first = line.find('"')
	if first < 0:
		return []
	var second = line.find('"', first + 1)
	if second < 0:
		return []
	var third = line.find('"', second + 1)
	if third < 0:
		return []
	var fourth = line.find('"', third + 1)
	if fourth < 0:
		return []
	return [line.substr(first + 1, second - first - 1), line.substr(third + 1, fourth - third - 1)]


static func _parse_face_line(line: String, face_re: RegEx) -> Dictionary:
	var matches = face_re.search_all(line)
	if matches.size() < 3:
		return {}
	var points: Array = []
	for i in range(3):
		var group = matches[i].get_string(1)
		var parts = group.strip_edges().split(" ", false)
		if parts.size() < 3:
			return {}
		points.append(Vector3(float(parts[0]), float(parts[1]), float(parts[2])))
	return {"points": points}


static func _brush_to_map_lines(
	brush: DraftBrush, adapter: HFMapAdapterType = null
) -> Array[String]:
	if not brush:
		return []
	if adapter == null:
		adapter = HFMapQuakeType.new()
	var lines: Array[String] = []
	var shape = brush.shape
	match shape:
		LevelRoot.BrushShape.BOX:
			lines.append_array(_box_to_map_lines(brush, adapter))
		LevelRoot.BrushShape.CYLINDER:
			lines.append_array(_cylinder_to_map_lines(brush, adapter))
		_:
			lines.append_array(_box_to_map_lines(brush, adapter))
	return lines


static func _box_to_map_lines(brush: DraftBrush, adapter: HFMapAdapterType = null) -> Array[String]:
	if adapter == null:
		adapter = HFMapQuakeType.new()
	var lines: Array[String] = []
	var half = brush.size * 0.5
	var corners = [
		Vector3(-half.x, -half.y, -half.z),
		Vector3(half.x, -half.y, -half.z),
		Vector3(half.x, half.y, -half.z),
		Vector3(-half.x, half.y, -half.z),
		Vector3(-half.x, -half.y, half.z),
		Vector3(half.x, -half.y, half.z),
		Vector3(half.x, half.y, half.z),
		Vector3(-half.x, half.y, half.z)
	]
	for i in range(corners.size()):
		corners[i] = brush.global_transform * corners[i]
	var face_indices = [[0, 3, 2], [5, 6, 7], [1, 2, 6], [0, 4, 7], [3, 7, 6], [0, 1, 5]]
	var brush_faces = brush.faces
	for fi in range(face_indices.size()):
		var face = face_indices[fi]
		var a = corners[face[0]]
		var b = corners[face[1]]
		var c = corners[face[2]]
		var fd: Variant = brush_faces[fi] if fi < brush_faces.size() else null
		lines.append(adapter.format_face_line(a, b, c, DEFAULT_TEXTURE, fd))
	return lines


static func _cylinder_to_map_lines(
	brush: DraftBrush, adapter: HFMapAdapterType = null
) -> Array[String]:
	if adapter == null:
		adapter = HFMapQuakeType.new()
	var lines: Array[String] = []
	var sides = max(6, brush.sides)
	var radius = max(brush.size.x, brush.size.z) * 0.5
	var half_y = brush.size.y * 0.5
	var points_top: Array = []
	var points_bottom: Array = []
	for i in range(sides):
		var angle = TAU * float(i) / float(sides)
		var x = cos(angle) * radius
		var z = sin(angle) * radius
		points_top.append(brush.global_transform * Vector3(x, half_y, z))
		points_bottom.append(brush.global_transform * Vector3(x, -half_y, z))
	var brush_faces = brush.faces
	var face_idx := 0
	for i in range(sides):
		var a = points_bottom[i]
		var b = points_bottom[(i + 1) % sides]
		var c = points_top[(i + 1) % sides]
		var fd: Variant = brush_faces[face_idx] if face_idx < brush_faces.size() else null
		lines.append(adapter.format_face_line(a, b, c, DEFAULT_TEXTURE, fd))
		face_idx += 1
	var top_center = brush.global_transform.origin + brush.global_transform.basis.y * half_y
	var bottom_center = brush.global_transform.origin - brush.global_transform.basis.y * half_y
	for i in range(sides):
		var a_top = points_top[i]
		var b_top = points_top[(i + 1) % sides]
		var fd_top: Variant = brush_faces[face_idx] if face_idx < brush_faces.size() else null
		lines.append(adapter.format_face_line(a_top, b_top, top_center, DEFAULT_TEXTURE, fd_top))
		face_idx += 1
		var a_bot = points_bottom[(i + 1) % sides]
		var b_bot = points_bottom[i]
		var fd_bot: Variant = brush_faces[face_idx] if face_idx < brush_faces.size() else null
		lines.append(adapter.format_face_line(a_bot, b_bot, bottom_center, DEFAULT_TEXTURE, fd_bot))
		face_idx += 1
	return lines


static func _format_face_line(a: Vector3, b: Vector3, c: Vector3) -> String:
	return (
		"( %s ) ( %s ) ( %s ) %s 0 0 0 1 1"
		% [_format_vec3(a), _format_vec3(b), _format_vec3(c), DEFAULT_TEXTURE]
	)


static func _format_vec3(v: Vector3) -> String:
	return "%s %s %s" % [_snapped(v.x), _snapped(v.y), _snapped(v.z)]


static func _snapped(value: float) -> String:
	return String.num(value, 3)


## Snap near-coincident vertices within a single parsed brush's face list.
## Uses BFS over a spatial hash with 27-cell neighbor lookup so pairs straddling
## a bucket boundary are never missed.  Averages each cluster and writes
## the canonical position back.
static func _snap_parsed_vertices(faces: Array, tolerance: float) -> void:
	if tolerance <= 0.0:
		return
	# Collect all vertex references into a flat list + spatial hash
	var entries: Array = []  # Array of {fi: int, pi: int, pos: Vector3}
	var cells: Dictionary = {}  # cell_key -> Array[int]
	for fi in range(faces.size()):
		var points: Array = faces[fi].get("points", [])
		for pi in range(points.size()):
			var idx: int = entries.size()
			var pos: Vector3 = points[pi]
			entries.append({"fi": fi, "pi": pi, "pos": pos})
			var key: String = _snap_cell_key(pos, tolerance)
			if not cells.has(key):
				cells[key] = []
			(cells[key] as Array).append(idx)
	# BFS grouping
	var group_of: PackedInt32Array = PackedInt32Array()
	group_of.resize(entries.size())
	group_of.fill(-1)
	var groups: Array = []  # Array of Array[int]
	for seed_idx in range(entries.size()):
		if group_of[seed_idx] >= 0:
			continue
		var gid: int = groups.size()
		var members: Array = [seed_idx]
		group_of[seed_idx] = gid
		var queue: Array = [seed_idx]
		while not queue.is_empty():
			var cur: int = queue.pop_front()
			var cur_pos: Vector3 = entries[cur]["pos"]
			for cell_key: String in _snap_cell_keys(cur_pos, tolerance):
				for neighbor_idx: int in cells.get(cell_key, []):
					if group_of[neighbor_idx] >= 0:
						continue
					if cur_pos.distance_to(entries[neighbor_idx]["pos"]) <= tolerance:
						group_of[neighbor_idx] = gid
						members.append(neighbor_idx)
						queue.append(neighbor_idx)
		groups.append(members)
	# Average each group and write back
	for members: Array in groups:
		if members.size() < 2:
			continue
		var avg := Vector3.ZERO
		for idx: int in members:
			avg += entries[idx]["pos"]
		avg /= float(members.size())
		var any_moved := false
		for idx: int in members:
			if (entries[idx]["pos"] as Vector3).distance_to(avg) > 0.0:
				any_moved = true
				break
		if not any_moved:
			continue
		for idx: int in members:
			var fi: int = entries[idx]["fi"]
			var pi: int = entries[idx]["pi"]
			faces[fi]["points"][pi] = avg


static func _snap_cell_key(v: Vector3, tol: float) -> String:
	return "%s,%s,%s" % [snapped(v.x, tol), snapped(v.y, tol), snapped(v.z, tol)]


## Return all 27 cell keys (self + 26 neighbors) for spatial hash lookup.
static func _snap_cell_keys(v: Vector3, cell_size: float) -> Array:
	var cx: float = snapped(v.x, cell_size)
	var cy: float = snapped(v.y, cell_size)
	var cz: float = snapped(v.z, cell_size)
	var keys: Array = []
	for dx in [-cell_size, 0.0, cell_size]:
		for dy in [-cell_size, 0.0, cell_size]:
			for dz in [-cell_size, 0.0, cell_size]:
				keys.append("%s,%s,%s" % [cx + dx, cy + dy, cz + dz])
	return keys
