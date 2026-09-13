@tool
extends RefCounted
class_name MapIO

const LevelRoot = preload("level_root.gd")
const DraftBrush = preload("brush_instance.gd")
const DraftEntity = preload("draft_entity.gd")
const HFMapAdapterType = preload("map_adapters/hf_map_adapter.gd")
const HFMapQuakeType = preload("map_adapters/hf_map_quake.gd")
const HFConvexClip = preload("hf_convex_clip.gd")

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
	var errors: Array[String] = []
	var current_entity: Dictionary = {}
	var current_brush: Dictionary = {}
	var in_entity = false
	var in_brush = false
	var face_re = RegEx.new()
	face_re.compile("\\(([^\\)]+)\\)")
	var line_no = 0
	for raw_line in lines:
		line_no += 1
		var line = raw_line.strip_edges()
		if line == "" or line.begins_with("//"):
			continue
		line = strip_comment(line)
		if line == "":
			continue
		if line == "{":
			if not in_entity:
				in_entity = true
				# `pairs` keeps every key/value line in file order. `properties`
				# is a Dictionary, so a repeated key overwrites, and I/O outputs
				# are written one line per connection with the output name as the
				# key. Two outputs on the same event would collide there.
				current_entity = {"properties": {}, "brushes": [], "pairs": []}
				continue
			if in_entity and not in_brush:
				in_brush = true
				current_brush = {"faces": [], "usable": true}
				continue
			errors.append("Line %d: brush inside a brush" % line_no)
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
			errors.append("Line %d: closing brace with nothing open" % line_no)
			continue
		if in_brush:
			var face = _parse_face_line(line, face_re)
			if face.is_empty():
				# A .map brush is the intersection of all its half spaces, so a
				# plane that cannot be read does not leave a smaller brush. It
				# leaves a different one. Drop the whole brush instead.
				errors.append("Line %d: face is not three planar points" % line_no)
				current_brush["usable"] = false
			else:
				current_brush["faces"].append(face)
			continue
		if in_entity:
			var kv = _parse_key_value(line)
			if kv.size() == 2:
				current_entity["properties"][kv[0]] = kv[1]
				current_entity["pairs"].append([kv[0], kv[1]])
			else:
				errors.append("Line %d: not a key value pair" % line_no)
			continue
		errors.append("Line %d: text outside any block" % line_no)
	if in_brush or in_entity:
		errors.append("Unclosed block at end of file")
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
		var authored := str(props.get("targetname", ""))
		var unusable_connections := [0]
		var connections := _connections_from_pairs(entity.get("pairs", []), unusable_connections)
		if unusable_connections[0] > 0:
			(
				errors
				. append(
					(
						"%s: dropped %d I/O line(s) with a missing field or a delay that is not a number"
						% [
							entity_class if entity_class != "" else "entity",
							unusable_connections[0]
						]
					)
				)
			)
		if not has_brushes and entity_class != "":
			entity_points.append(
				{
					"classname": entity_class,
					"origin": origin,
					"properties": props,
					"entity_name": authored,
					"entity_io_outputs": connections
				}
			)
		for brush in entity.get("brushes", []):
			var info = (
				_brush_from_faces(brush.get("faces", [])) if bool(brush.get("usable", true)) else {}
			)
			if info.is_empty():
				errors.append("A brush in '%s' has no usable geometry" % entity_class)
				continue
			if entity_class != "" and entity_class != "worldspawn":
				info["brush_entity_class"] = entity_class
				if authored != "":
					info["entity_name"] = authored
				if not connections.is_empty():
					info["entity_io_outputs"] = connections
			brushes.append(info)
	if entities.is_empty() and text.strip_edges() != "":
		errors.append("No map blocks found")
	return {"entities": entity_points, "brushes": brushes, "errors": errors}


## The I/O connections among an entity's key/value lines.
##
## Read from the ordered pairs rather than the properties dictionary, so two
## outputs on the same event both survive. A reserved key is never a connection,
## and everything else has to look like one to be taken as one.
## `dropped` is a one-element array the count of unusable lines is written into,
## so the importer can say what it lost rather than losing it in silence. A line
## only counts as lost when it has the five fields of a connection and fails on
## one of them; an ordinary entity property is not wiring and is not a loss.
static func _connections_from_pairs(pairs: Array, dropped: Array) -> Array:
	var out: Array = []
	for pair in pairs:
		if not (pair is Array) or pair.size() != 2:
			continue
		var key := str(pair[0])
		if key in RESERVED_ENTITY_KEYS:
			continue
		var value := str(pair[1])
		var connection := parse_connection(key, value)
		if not connection.is_empty():
			out.append(connection)
		elif value.split(",", true).size() == 5:
			dropped[0] = int(dropped[0]) + 1
	return out


## Write the level out as `.map` text.
##
## Cutters are left out. Every brush inside a `.map` worldspawn is an additive
## convex solid — the format has no negative brush — so a subtraction brush
## written here does not carve the hole it was made for, it fills it. A doorway
## exported as a solid block is worse than a doorway that is missing, and it is
## silent. Carved shapes therefore leave here uncut; `.map` is a blockout
## exchange format, not a bake.
static func export_map_from_level(level_root: Node, adapter: HFMapAdapterType = null) -> String:
	if not level_root:
		return ""
	if adapter == null:
		adapter = HFMapQuakeType.new()
	var material_names: Array = []
	if level_root.has_method("get_material_names"):
		material_names = level_root.call("get_material_names")
	var lines: Array[String] = []
	lines.append("{")
	lines.append('"classname" "worldspawn"')
	var brush_nodes: Array = []
	if level_root.has_method("_iter_pick_nodes"):
		brush_nodes.append_array(level_root.call("_iter_pick_nodes"))
	var entity_brush_blocks: Array = []
	for node in brush_nodes:
		if not (node is DraftBrush):
			continue
		if level_root.has_method("is_entity_node") and level_root.is_entity_node(node):
			continue
		if _is_cutter(node):
			continue
		var brush_lines = _brush_to_map_lines(node, adapter, material_names)
		if brush_lines.is_empty():
			continue
		var bec := str(node.get_meta("brush_entity_class", ""))
		if bec != "":
			entity_brush_blocks.append({"classname": bec, "lines": brush_lines, "node": node})
			continue
		lines.append("{")
		lines.append_array(brush_lines)
		lines.append("}")
	lines.append("}")
	for block in entity_brush_blocks:
		lines.append("{")
		lines.append('"classname" "%s"' % escape_property(str(block["classname"])))
		# The authored name is the address every connection targets, and the
		# outputs are the wiring itself. Both live in metadata rather than in
		# entity_data, so neither was reaching the file.
		lines.append_array(_entity_identity_lines(block.get("node", null), adapter))
		lines.append("{")
		lines.append_array(block["lines"])
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


## A palette material name as it can be written on a face line.
##
## The texture field of a `.map` face line is positional and whitespace
## delimited, so a name with a space in it would be read as the name plus the
## start of the UV numbers. Whitespace runs collapse to an underscore and quotes
## are dropped; a name that is empty once cleaned falls back to the default.
static func texture_token(material_name: String) -> String:
	var cleaned := material_name.strip_edges().replace('"', "")
	var out := ""
	var in_space := false
	for i in cleaned.length():
		var ch := cleaned[i]
		if ch == " " or ch == "	":
			in_space = true
			continue
		if in_space and out != "":
			out += "_"
		in_space = false
		out += ch
	return out if out != "" else DEFAULT_TEXTURE


## The texture name for one face, resolved through the palette names the level
## was exported with. An unset or out-of-range index is the default texture.
static func _texture_for_face(face_data: Variant, material_names: Array) -> String:
	if face_data == null:
		return DEFAULT_TEXTURE
	var idx: int = int(face_data.material_idx)
	if idx < 0 or idx >= material_names.size():
		return DEFAULT_TEXTURE
	return texture_token(str(material_names[idx]))


## The face whose outward normal is closest to [param world_normal].
##
## Curved primitives get their faces from the mesh, so a brush's face order is
## whatever the mesh generator produced rather than a layout the exporter can
## count on. Matching by normal asks the question the exporter actually has,
## which is "which face is this plane", and gets the same answer whatever order
## the faces are in.
static func _face_for_normal(brush: DraftBrush, world_normal: Vector3) -> Variant:
	var best: Variant = null
	var best_dot := -2.0
	var basis := brush.global_transform.basis
	for face in brush.faces:
		if face == null:
			continue
		var normal: Vector3 = (basis * face.normal).normalized()
		var dot := normal.dot(world_normal)
		if dot > best_dot:
			best_dot = dot
			best = face
	return best


## Keys HammerForge writes itself, which are never I/O outputs.
const RESERVED_ENTITY_KEYS := ["classname", "origin", "targetname"]


## One connection as a `.map` value.
##
## `.map` has no connections block. Its entity body is key/value lines and
## nothing else, and a nested brace inside an entity is read as a brush by every
## parser including this one, so a Source style block would not survive a round
## trip. Each connection is therefore a line of its own with the output name as
## the key, and the value in the order Hammer writes a VMF connection:
##
##     "OnOpen" "lamp,TurnOn,,0,0"
##
## Commas are stripped from the fields rather than escaped, because the format
## defines no escape for one and a reader splitting on the comma would get a
## different number of fields than the writer wrote.
static func format_connection(connection: Dictionary) -> String:
	return (
		"%s,%s,%s,%s,%s"
		% [
			_no_commas(str(connection.get("target_name", ""))),
			_no_commas(str(connection.get("input_name", ""))),
			_no_commas(str(connection.get("parameter", ""))),
			_snapped(float(connection.get("delay", 0.0))),
			"1" if bool(connection.get("fire_once", false)) else "0",
		]
	)


## A connection read back from a `.map` value, or an empty dictionary when the
## value is not one.
##
## Five comma separated fields with a numeric delay and a target and input that
## are actually there. An ordinary entity property does not look like that, so
## wiring is told apart from settings without a naming convention on the key.
static func parse_connection(output_name: String, value: String) -> Dictionary:
	var parts := value.split(",", true)
	if parts.size() != 5:
		return {}
	if not str(parts[3]).strip_edges().is_valid_float():
		return {}
	if str(parts[0]).strip_edges() == "" or str(parts[1]).strip_edges() == "":
		return {}
	return {
		"output_name": output_name,
		"target_name": str(parts[0]),
		"input_name": str(parts[1]),
		"parameter": str(parts[2]),
		"delay": float(parts[3]),
		"fire_once": str(parts[4]).strip_edges() == "1",
	}


static func _no_commas(text: String) -> String:
	return text.replace(",", " ")


## True when a brush cuts geometry away rather than adding it.
##
## Three ways to be a cutter, because a cutter is not one state. A pending cut is
## still being aimed, a committed cut has been frozen out of sight under
## `CommittedCuts` and keeps whatever operation it had when it was stashed, and a
## plain subtraction brush is neither. Reading only the operation misses the
## frozen one; reading only the container misses the other two.
static func _is_cutter(node: DraftBrush) -> bool:
	if node.operation == CSGShape3D.OPERATION_SUBTRACTION:
		return true
	if bool(node.get_meta("committed_cut", false)):
		return true
	var parent: Node = node.get_parent()
	return parent != null and parent.name in ["PendingCuts", "CommittedCuts"]


## The `targetname` and the I/O output lines for one entity, in that order.
##
## Empty for an entity with neither, so an unwired entity block is unchanged.
static func _entity_identity_lines(entity, adapter: HFMapAdapterType = null) -> Array[String]:
	var out: Array[String] = []
	if entity == null or not is_instance_valid(entity):
		return out
	# An ordered list rather than a Dictionary, because two outputs on the same
	# event share a key and a Dictionary would keep only the last of them.
	var pairs: Array = []
	var authored := str(entity.get_meta("entity_name", ""))
	if authored != "":
		pairs.append(["targetname", authored])
	var outputs = entity.get_meta("entity_io_outputs", [])
	if outputs is Array:
		for connection in outputs:
			if not (connection is Dictionary):
				continue
			var output_name := str(connection.get("output_name", ""))
			if output_name == "":
				continue
			pairs.append([output_name, format_connection(connection)])
	for pair in pairs:
		# One pair at a time keeps the order and the repeats while still going
		# through the adapter, which is what escapes the key and the value.
		var writer: HFMapAdapterType = adapter if adapter else HFMapAdapterType.new()
		out.append_array(writer.format_entity_properties({pair[0]: pair[1]}))
	return out


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
	var props: Dictionary = {}
	var data: Dictionary = entity.entity_data if entity.entity_data is Dictionary else {}
	for key in data.keys():
		var key_name := str(key)
		if key_name == "classname" or key_name == "origin":
			continue
		# The value keeps its type on the way to the adapter. The Objects tab
		# stores a Color for a colour and a Vector3 for a vector row, and `str()`
		# on either produces Godot's own notation, which nothing that reads a
		# `.map` can parse - so flattening here was what put it in the file.
		if str(data[key]) == "":
			continue
		props[key_name] = data[key]
	props["classname"] = entity_class
	props["origin"] = _format_vec3(entity.global_transform.origin)
	# A base adapter when none was given, rather than a second copy of the
	# formatting here: the fallback used to `str()` every value, which is the
	# notation this path exists to keep out of the file.
	var writer: HFMapAdapterType = adapter if adapter else HFMapAdapterType.new()
	lines.append_array(writer.format_entity_properties(props))
	# entity_data carries the authored keys. The name and the I/O outputs live in
	# metadata, so they come from there.
	lines.append_array(_entity_identity_lines(entity, adapter))
	lines.append("}")
	return lines


## Read one parsed brush into a brush record.
##
## A `.map` face line names three points on an infinite plane, not the corners of
## a face. The solid is the intersection of the half spaces behind those planes,
## and each face is the part of its own plane left over once every other plane has
## cut it. So the corners are worked out here rather than read off the line.
##
## Ill-formed brushes still import. Two planes do not bound anything, and neither
## does a set left open on one side, but a file can hold either and the old
## reading of the plane points as corners is the only thing left to fall back on.
## It gives the wrong hull; it gives one, and the brush is still there to fix.
static func _brush_from_faces(faces: Array) -> Dictionary:
	if faces.is_empty():
		return {}
	var points: Array = []
	var planes: Array = []
	# Which parsed face each usable plane came from. Degenerate faces are skipped,
	# so the plane index is not the face index, and the hull hands its polygons
	# back keyed on the plane index.
	var plane_sources: Array = []
	var axis_aligned = true
	var planes_usable = true
	for face_index in faces.size():
		var face: Dictionary = faces[face_index]
		var face_points: Array = face.get("points", [])
		if face_points.size() < 3:
			continue
		# .map files come from other tools, so a plane point can be NaN or a
		# blown-out magnitude. The degenerate case is already caught below by
		# the zero normal, but the cross product of NaN points is NaN, not zero,
		# and a 1e30 point is finite. Both slip past that check and land in the
		# level as a brush with NaN vertices, which then poisons every bound
		# computed from it. Refuse the whole brush, the way a degenerate one is
		# refused.
		if not _points_usable(face_points):
			return {}

		points.append_array(face_points)
		var normal = _face_normal(face_points)
		if not normal.is_finite():
			return {}
		if _axis_from_normal(normal) == Vector3.ZERO:
			axis_aligned = false
		if normal == Vector3.ZERO:
			planes_usable = false
		else:
			planes.append(Plane(normal, normal.dot(face_points[0])))
			plane_sources.append(face_index)
	if points.is_empty():
		return {}
	var bounds := _bounds_of(points)
	var hull: Array = _hull_polygons(planes, bounds) if planes_usable else []
	if not hull.is_empty():
		var corners: Array = []
		for entry in hull:
			for vertex in entry["verts"]:
				corners.append(vertex)
		bounds = _bounds_of(corners)
	var size = bounds.size
	if size.length() <= 0.001:
		return {}
	var center = bounds.get_center()
	if axis_aligned and faces.size() <= 8:
		# A box builds its own six faces, so there is no face list to line the
		# textures up against. They travel keyed on the plane normal instead and
		# the importer matches them to the faces the box makes.
		return {
			"shape": LevelRoot.BrushShape.BOX,
			"size": size,
			"center": center,
			"operation": CSGShape3D.OPERATION_UNION,
			"map_textures_by_normal": _textures_by_normal(faces)
		}
	var rings: Array = []
	var ring_textures: Array = []
	if hull.is_empty():
		for face in faces:
			var face_points: Array = face.get("points", [])
			if face_points.size() < 3:
				continue
			ring_textures.append(str(face.get("texture", "")))
			# Mirror of the export: undo the .map plane order so the stored face
			# keeps FaceData's clockwise-from-outside winding.
			var wound: Array = face_points.duplicate()
			wound.reverse()
			rings.append(wound)
	else:
		for entry in hull:
			rings.append(entry["verts"])
			var source_index := int(entry.get("index", -1))
			if source_index >= 0 and source_index < plane_sources.size():
				ring_textures.append(str(faces[plane_sources[source_index]].get("texture", "")))
			else:
				ring_textures.append("")
	var serialized_faces: Array = []
	var map_textures: Array = []
	for ring_index in rings.size():
		var local_verts: Array = []
		for p in rings[ring_index]:
			var pt: Vector3 = p
			local_verts.append([pt.x - center.x, pt.y - center.y, pt.z - center.z])
		serialized_faces.append({"local_verts": local_verts, "winding_version": 1})
		map_textures.append(ring_textures[ring_index] if ring_index < ring_textures.size() else "")
	return {
		"shape": LevelRoot.BrushShape.CUSTOM,
		"size": size,
		"center": center,
		"faces": serialized_faces,
		"operation": CSGShape3D.OPERATION_UNION,
		"map_textures": map_textures
	}


## Texture names from the parsed faces, keyed by the direction each plane faces.
##
## Used for the box path, where the brush builds its own faces and there is no
## parsed face to pair each one with. The key is quantised so a normal written
## out and read back still matches.
static func _textures_by_normal(faces: Array) -> Dictionary:
	var out: Dictionary = {}
	for face in faces:
		var face_points: Array = face.get("points", [])
		if face_points.size() < 3:
			continue
		var texture := str(face.get("texture", ""))
		if texture == "":
			continue
		var normal := _face_normal(face_points)
		if normal == Vector3.ZERO:
			continue
		out[normal_key(normal)] = texture
	return out


## A rounded direction, so two normals that agree to three decimals share a key.
##
## Adding zero folds negative zero onto positive zero. Without it an axis-aligned
## normal formats as "-0.000" on one side of a round trip and "0.000" on the
## other, and four of a box's six faces miss each other.
static func normal_key(normal: Vector3) -> String:
	var n := normal.normalized()
	return (
		"%.3f,%.3f,%.3f"
		% [snappedf(n.x, 0.001) + 0.0, snappedf(n.y, 0.001) + 0.0, snappedf(n.z, 0.001) + 0.0]
	)


## The box that contains every point.
static func _bounds_of(points: Array) -> AABB:
	var min_pt = Vector3(INF, INF, INF)
	var max_pt = Vector3(-INF, -INF, -INF)
	for p in points:
		min_pt.x = min(min_pt.x, p.x)
		min_pt.y = min(min_pt.y, p.y)
		min_pt.z = min(min_pt.z, p.z)
		max_pt.x = max(max_pt.x, p.x)
		max_pt.y = max(max_pt.y, p.y)
		max_pt.z = max(max_pt.z, p.z)
	return AABB(min_pt, max_pt - min_pt)


## The corner ring each plane contributes to the solid its planes bound, or an
## empty array when they bound nothing.
##
## Returns `{"index": int, "verts": PackedVector3Array}` per plane that reaches
## the surface, in plane order, wound clockwise from outside like every other
## face in the codebase.
##
## Two things are tried before giving up. A face starts as a square that has to
## be wider than the solid, and a solid can reach well past the points that
## defined its planes, so a pass whose faces still touch the rim of their square
## is retried wider before it is believed. And the whole set is retried flipped,
## because the order of the three points on a face line settles which side is
## solid and editors do not agree on it; the intersection of the outside half
## spaces of a closed solid is empty, so the wrong orientation cannot pass.
static func _hull_polygons(planes: Array, bounds: AABB) -> Array:
	if planes.size() < HFConvexClip.MIN_SOLID_FACES:
		return []
	var radius := maxf(bounds.size.length() * 0.5, 1.0)
	var flipped: Array = []
	for plane in planes:
		flipped.append(Plane(-plane.normal, -plane.d))
	for candidate in [planes, flipped]:
		for half in [radius * 4.0, radius * 64.0]:
			var rings := _clip_planes(candidate, bounds.get_center(), half)
			if not rings.is_empty():
				return rings
	return []


## One clipping pass at a given starting square size.
##
## Empty when a face still reaches the rim of its square, which means the planes
## leave the solid open on that side, or that the square started too small to
## tell the difference.
static func _clip_planes(planes: Array, centre: Vector3, half: float) -> Array:
	var out: Array = []
	var rim := half - HFConvexClip.DEFAULT_EPSILON
	for i in range(planes.size()):
		var plane: Plane = planes[i]
		var origin: Vector3 = centre - plane.normal * plane.distance_to(centre)
		var axes := _plane_axes(plane)
		var u: Vector3 = axes[0]
		var v: Vector3 = axes[1]
		var poly := PackedVector3Array(
			[
				origin - u * half - v * half,
				origin + u * half - v * half,
				origin + u * half + v * half,
				origin - u * half + v * half,
			]
		)
		for j in range(planes.size()):
			if j == i:
				continue
			poly = HFConvexClip.clip_polygon(poly, PackedVector2Array(), planes[j], false)["verts"]
			if poly.size() < 3:
				break
		if poly.size() < 3:
			continue
		for point in poly:
			var offset: Vector3 = point - origin
			if absf(offset.dot(u)) >= rim or absf(offset.dot(v)) >= rim:
				return []
		var ring := HFConvexClip.cap_polygon(poly, plane.normal)
		if ring.size() >= 3:
			out.append({"index": i, "verts": ring})
	return out if out.size() >= HFConvexClip.MIN_SOLID_FACES else []


## Two unit vectors spanning a plane, for laying a square on it.
static func _plane_axes(plane: Plane) -> Array:
	var normal := plane.normal.normalized()
	var reference := Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var u := normal.cross(reference).normalized()
	return [u, normal.cross(u)]


## The largest plane coordinate a brush is allowed to carry. Quake-lineage
## compilers put the world at +/-4096 and the Source-era ones at +/-16384, so a
## coordinate past this is a precision blowout in the file, not a level.
const MAX_PLANE_COORD := 65536.0


static func _points_usable(face_points: Array) -> bool:
	for point in face_points:
		if not (point is Vector3):
			return false
		var p: Vector3 = point
		if not p.is_finite():
			return false
		if absf(p.x) > MAX_PLANE_COORD or absf(p.y) > MAX_PLANE_COORD:
			return false
		if absf(p.z) > MAX_PLANE_COORD:
			return false
	return true


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


## The two quoted tokens on a key/value line, unescaped, or an empty array when
## the line is not one.
##
## Scanned as quoted strings rather than by counting quote positions, so a value
## may contain a quote of its own. Without that, `"message" "he said "hi""` read
## back as `he said ` — silently, because four quotes is exactly what a valid
## line has.
static func _parse_key_value(line: String) -> Array:
	var key := _read_quoted(line, 0)
	if key.is_empty():
		return []
	var value := _read_quoted(line, int(key[1]))
	if value.is_empty():
		return []
	return [str(key[0]), str(value[0])]


## Read one quoted token starting at or after `from`.
##
## Returns `[text, index_after_the_closing_quote]`, or an empty array when there
## is no complete token. `\"` and `\\` are unescaped; a backslash before
## anything else is left exactly as it is, so a Windows path written by a tool
## that does not escape — `textures\wall` — survives being read.
static func _read_quoted(line: String, from: int) -> Array:
	var open_index := line.find('"', from)
	if open_index < 0:
		return []
	var out := ""
	var i := open_index + 1
	while i < line.length():
		var c := line[i]
		if c == "\\" and i + 1 < line.length() and line[i + 1] in ['"', "\\"]:
			out += line[i + 1]
			i += 2
			continue
		if c == '"':
			return [out, i + 1]
		out += c
		i += 1
	return []


## Drop a `//` comment, ignoring one that sits inside a quoted string.
##
## A property value is allowed to contain `//` — a URL is the obvious case — and
## cutting the line there left it with an odd number of quotes and no way to
## parse.
static func strip_comment(line: String) -> String:
	var in_quotes := false
	var i := 0
	while i < line.length():
		var c := line[i]
		if in_quotes and c == "\\" and i + 1 < line.length():
			i += 2
			continue
		if c == '"':
			in_quotes = not in_quotes
			i += 1
			continue
		if not in_quotes and c == "/" and i + 1 < line.length() and line[i + 1] == "/":
			return line.substr(0, i).strip_edges()
		i += 1
	return line.strip_edges()


## Escape a key or value for writing between quotes. The inverse of the
## unescaping in `_read_quoted()`.
static func escape_property(text: String) -> String:
	return text.replace("\\", "\\\\").replace('"', '\\"')


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
		# float() answers 0.0 for any token it cannot read, so `nan`, `inf` and
		# a typo all arrive as the origin and the face reads as a real plane
		# through it. A coordinate that is not a number is a broken line.
		for i2 in range(3):
			if not parts[i2].is_valid_float():
				return {}
		points.append(Vector3(float(parts[0]), float(parts[1]), float(parts[2])))
	# The texture is the first token after the third plane point, in both Classic
	# Quake and Valve 220. Everything after it is UV numbers, which differ between
	# the two formats and are not read back.
	var texture := ""
	var tail := line.substr(matches[2].get_end()).strip_edges()
	if tail != "":
		var tail_parts := tail.split(" ", false)
		if tail_parts.size() > 0:
			texture = str(tail_parts[0])
	return {"points": points, "texture": texture}


static func _brush_to_map_lines(
	brush: DraftBrush, adapter: HFMapAdapterType = null, material_names: Array = []
) -> Array[String]:
	if not brush:
		return []
	if adapter == null:
		adapter = HFMapQuakeType.new()
	var lines: Array[String] = []
	var shape = brush.shape
	match shape:
		LevelRoot.BrushShape.BOX:
			lines.append_array(_box_to_map_lines(brush, adapter, material_names))
		LevelRoot.BrushShape.CYLINDER:
			lines.append_array(_cylinder_to_map_lines(brush, adapter, material_names))
		_:
			if not brush.faces.is_empty():
				lines.append_array(_faces_to_map_lines(brush, adapter, material_names))
			else:
				lines.append_array(_box_to_map_lines(brush, adapter, material_names))
	return lines


static func _faces_to_map_lines(
	brush: DraftBrush, adapter: HFMapAdapterType = null, material_names: Array = []
) -> Array[String]:
	if adapter == null:
		adapter = HFMapQuakeType.new()
	var lines: Array[String] = []
	for face in brush.faces:
		if face == null or face.local_verts.size() < 3:
			continue
		var a: Vector3 = brush.global_transform * face.local_verts[0]
		var b: Vector3 = brush.global_transform * face.local_verts[1]
		var c: Vector3 = brush.global_transform * face.local_verts[2]
		# FaceData winds clockwise seen from outside. A .map plane is read as
		# (b - a) x (c - a), so the points go out in the reverse order or every
		# hull comes out inside out.
		lines.append(
			adapter.format_face_line(a, c, b, _texture_for_face(face, material_names), face)
		)
	return lines


static func _box_to_map_lines(
	brush: DraftBrush, adapter: HFMapAdapterType = null, material_names: Array = []
) -> Array[String]:
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
	# Same order as DraftBrush._build_box_faces: Right, Left, Top, Bottom, Front, Back.
	# brush.faces is indexed with the same counter below, so the two must agree or
	# every plane is written with another face's texture and UV settings.
	var face_indices = [[1, 2, 6], [0, 4, 7], [3, 7, 6], [0, 1, 5], [5, 6, 7], [0, 3, 2]]
	var brush_faces = brush.faces
	for fi in range(face_indices.size()):
		var face = face_indices[fi]
		var a = corners[face[0]]
		var b = corners[face[1]]
		var c = corners[face[2]]
		var fd: Variant = brush_faces[fi] if fi < brush_faces.size() else null
		lines.append(adapter.format_face_line(a, b, c, _texture_for_face(fd, material_names), fd))
	return lines


static func _cylinder_to_map_lines(
	brush: DraftBrush, adapter: HFMapAdapterType = null, material_names: Array = []
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
	# One plane per wall, and one per cap. A .map brush is an intersection of half
	# spaces, so the whole flat top is the single plane y = +half_y; walking the
	# cap as a triangle fan wrote that same plane once per wedge, which is 3 * sides
	# planes for a prism that needs sides + 2, most of them exact duplicates.
	#
	# The points also go out in the order that makes each plane normal point away
	# from the brush, which is what the box and custom-face writers already do and
	# what the format notes promise. The fan wrote its planes facing inward.
	var up := brush.global_transform.basis.y.normalized()
	for i in range(sides):
		var a: Vector3 = points_bottom[i]
		var b: Vector3 = points_top[(i + 1) % sides]
		var c: Vector3 = points_bottom[(i + 1) % sides]
		var wall_normal: Vector3 = (b - a).cross(c - a).normalized()
		var fd: Variant = _face_for_normal(brush, wall_normal)
		lines.append(adapter.format_face_line(a, b, c, _texture_for_face(fd, material_names), fd))
	# Three distinct points on each ring name the cap plane. Taking them from the
	# ring rather than from the centre keeps them non-collinear for any side count
	# the brush allows.
	var fd_top: Variant = _face_for_normal(brush, up)
	lines.append(
		adapter.format_face_line(
			points_top[2],
			points_top[1],
			points_top[0],
			_texture_for_face(fd_top, material_names),
			fd_top
		)
	)
	var fd_bottom: Variant = _face_for_normal(brush, -up)
	lines.append(
		adapter.format_face_line(
			points_bottom[0],
			points_bottom[1],
			points_bottom[2],
			_texture_for_face(fd_bottom, material_names),
			fd_bottom
		)
	)
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
