@tool
extends RefCounted
## What changed between two versions of a level (#1701): brushes added, removed
## and changed, face by face, entities, wires, visgroups, cordons and paint.
##
## Both sides are what a `.hflevel` holds: `{"settings", "state"}`, read from a
## file with `HFFileSystem.read_hflevel()` or captured from the open level with
## `HFStateSystem.capture_hflevel_payload()`. Nothing here touches a level, so a
## compare never changes the one that is open. The Console's Compare tab, the
## viewport outlines and `tools/compare_levels.gd` all read `compare()`.

## How far apart two corners may be and still be the same, in metres.
const NEAR := 0.01
## How far apart two brush origins may be for a brush whose id changed to be the
## same brush.
const SAME_PLACE := 0.01

## The kinds `compare()` counts, in the order its summary names them.
const KINDS := ["brushes", "faces", "entities", "wires", "visgroups", "cordons", "paint"]

# Preloaded under its global name so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const DraftBrush = preload("brush_instance.gd")
const HFBrushEntity = preload("hf_brush_entity.gd")
const HFVisgroupSystem = preload("systems/hf_visgroup_system.gd")
const HFDisplacementData = preload("displacement_data.gd")
@warning_ignore_restore("shadowed_global_identifier")


## What changed from `before` to `after`. `{brushes: {added, removed, changed,
## same}, entities: {added, removed, changed}, counts: {kind: n}, rows, lines}`: `added`
## and `same` hold the brush ids `after` has, `removed` the brush records of
## `before` it has not, `changed` `{id, changes: [text], faces: n}`, and `lines`
## every change as a sentence, the summary first, and `rows` the same sentences
## each with what it names, for the list to select.
static func compare(before: Dictionary, after: Dictionary) -> Dictionary:
	var old_state: Dictionary = before.get("state", {})
	var new_state: Dictionary = after.get("state", {})
	var counts := {}
	for kind in KINDS:
		counts[kind] = 0
	var brushes := _compare_brushes(old_state, new_state, counts)
	var entities := _compare_entities(old_state, new_state, counts)
	var rows: Array = brushes["rows"] + entities["rows"]
	var rest: PackedStringArray = []
	rest.append_array(_compare_visgroups(old_state, new_state, counts))
	rest.append_array(
		_compare_cordons(before.get("settings", {}), after.get("settings", {}), counts)
	)
	rest.append_array(_compare_paint(old_state, new_state, counts))
	for line in rest:
		rows.append(_row(line))
	rows.push_front(_row(summary(counts)))
	var lines: PackedStringArray = []
	for row in rows:
		lines.append(row["text"])
	return {
		"brushes": brushes["result"],
		"entities": entities["result"],
		"counts": counts,
		"rows": rows,
		"lines": lines,
	}


## A line of the list, and what it names in the open level: "brush:<id>",
## "entity:<name>", or "" for something that is not there to select.
static func _row(text: String, ref := "") -> Dictionary:
	return {"text": text, "ref": ref}


## "No changes", or "3 brushes, 5 faces, 1 entity changed".
static func summary(counts: Dictionary) -> String:
	var parts: PackedStringArray = []
	for kind in KINDS:
		var many := int(counts.get(kind, 0))
		if many > 0:
			parts.append("%d %s" % [many, _kind_word(kind, many)])
	if parts.is_empty():
		return "No changes"
	return "%s changed" % ", ".join(parts)


static func _kind_word(kind: String, many: int) -> String:
	match kind:
		"brushes":
			return "brush" if many == 1 else "brushes"
		"faces":
			return "face" if many == 1 else "faces"
		"entities":
			return "entity" if many == 1 else "entities"
		"wires":
			return "wire" if many == 1 else "wires"
		"visgroups":
			return "visgroup" if many == 1 else "visgroups"
		"cordons":
			return "cordon" if many == 1 else "cordons"
	return "paint layer" if many == 1 else "paint layers"


# ---------------------------------------------------------------------------
# Brushes
# ---------------------------------------------------------------------------


static func _all_brushes(state: Dictionary) -> Array:
	var out: Array = []
	for key in ["brushes", "pending", "committed"]:
		for info in state.get(key, []):
			if info is Dictionary:
				out.append(info)
	return out


static func _compare_brushes(
	old_state: Dictionary, new_state: Dictionary, counts: Dictionary
) -> Dictionary:
	var old_by_id := {}
	for info in _all_brushes(old_state):
		old_by_id[str(info.get("brush_id", ""))] = info
	var new_by_id := {}
	for info in _all_brushes(new_state):
		new_by_id[str(info.get("brush_id", ""))] = info
	var pairs: Array = []
	var added: Array = []
	for brush_id in new_by_id:
		if old_by_id.has(brush_id):
			pairs.append([old_by_id[brush_id], new_by_id[brush_id]])
		else:
			added.append(new_by_id[brush_id])
	var removed: Array = []
	for brush_id in old_by_id:
		if not new_by_id.has(brush_id):
			removed.append(old_by_id[brush_id])
	# A brush whose id changed and whose shape and place did not is the same brush.
	for info in added.duplicate():
		for old in removed:
			if _same_solid(old, info):
				pairs.append([old, info])
				added.erase(info)
				removed.erase(old)
				break
	var palette_old: Array = old_state.get("materials", [])
	var palette_new: Array = new_state.get("materials", [])
	var rows: Array = []
	var changed: Array = []
	var unchanged: Array = []
	# A brush entity of several brushes holds its wires on every one of them, so
	# each entity's wires count once.
	var wired := {}
	for pair in pairs:
		var changes := _brush_changes(pair[0], pair[1], palette_old, palette_new)
		var brush_id := str(pair[1].get("brush_id", ""))
		if changes["lines"].is_empty():
			unchanged.append(brush_id)
			continue
		var entity := _brush_entity_of(pair[1])
		if int(changes["wires"]) > 0 and not wired.has(entity):
			wired[entity] = true
			counts["wires"] += int(changes["wires"])
		changed.append({"id": brush_id, "changes": changes["lines"], "faces": changes["faces"]})
		counts["faces"] += int(changes["faces"])
		for line in changes["lines"]:
			rows.append(_row("%s: %s" % [_brush_name(pair[1]), line], "brush:" + brush_id))
	for info in added:
		rows.append(_row("%s: added" % _brush_name(info), "brush:" + str(info.get("brush_id", ""))))
	for info in removed:
		rows.append(_row("%s: removed" % _brush_name(info)))
	for info in added + removed:
		var entity := _brush_entity_of(info)
		if not wired.has(entity):
			wired[entity] = true
			counts["wires"] += _wires_of(info).size()
	counts["brushes"] += changed.size() + added.size() + removed.size()
	return {
		"result":
		{
			"added": added.map(func(info): return str(info.get("brush_id", ""))),
			"removed": removed,
			"changed": changed,
			"same": unchanged,
		},
		"rows": rows,
	}


static func _brush_name(info: Dictionary) -> String:
	var brush_name := str(info.get("name", ""))
	var brush_id := str(info.get("brush_id", ""))
	if brush_name != "" and brush_name != brush_id:
		return "brush '%s'" % brush_name
	return "brush %s" % brush_id


static func _transform_of(info: Dictionary) -> Transform3D:
	var xform = info.get("transform")
	if xform is Transform3D:
		return xform
	var centre = info.get("center", Vector3.ZERO)
	return Transform3D(Basis.IDENTITY, centre if centre is Vector3 else Vector3.ZERO)


static func _size_of(info: Dictionary) -> Vector3:
	var size = info.get("size")
	return size if size is Vector3 else Vector3.ZERO


static func _same_solid(a: Dictionary, b: Dictionary) -> bool:
	if int(a.get("shape", -1)) != int(b.get("shape", -1)):
		return false
	if int(a.get("operation", 0)) != int(b.get("operation", 0)):
		return false
	if not _size_of(a).is_equal_approx(_size_of(b)):
		return false
	var ta := _transform_of(a)
	var tb := _transform_of(b)
	if ta.origin.distance_to(tb.origin) > SAME_PLACE or not ta.basis.is_equal_approx(tb.basis):
		return false
	return (a.get("faces", []) as Array).size() == (b.get("faces", []) as Array).size()


## The brush entity a brush record is part of: its authored name, its tie, or
## the brush alone.
static func _brush_entity_of(info: Dictionary) -> String:
	for key in [HFBrushEntity.NAME_META, HFBrushEntity.TIE_META]:
		if str(info.get(key, "")) != "":
			return "%s:%s" % [key, info[key]]
	return "brush:%s" % info.get("brush_id", "")


## What changed on one brush, as sentences, how many of its faces changed and how
## many of its wires. Its brush entity too: its class, its settings and its wires
## (#1941).
static func _brush_changes(
	old: Dictionary, now: Dictionary, palette_old: Array, palette_new: Array
) -> Dictionary:
	var lines: PackedStringArray = []
	var told := _transform_of(old)
	var tnew := _transform_of(now)
	var delta := tnew.origin - told.origin
	if delta.length() > NEAR:
		lines.append("moved %s" % moved_text(delta))
	if not told.basis.orthonormalized().is_equal_approx(tnew.basis.orthonormalized()):
		lines.append("turned")
	if not _size_of(old).is_equal_approx(_size_of(now)):
		lines.append("resized to %s" % _size_text(_size_of(now)))
	if int(old.get("shape", 0)) != int(now.get("shape", 0)):
		lines.append(
			(
				"shape changed from %s to %s"
				% [_shape_name(old.get("shape")), _shape_name(now.get("shape"))]
			)
		)
	if int(old.get("operation", 0)) != int(now.get("operation", 0)):
		lines.append(
			(
				"now a cut"
				if int(now.get("operation", 0)) == CSGShape3D.OPERATION_SUBTRACTION
				else "now solid"
			)
		)
	var old_class := str(old.get(HFBrushEntity.CLASS_META, ""))
	var new_class := str(now.get(HFBrushEntity.CLASS_META, ""))
	if old_class != new_class:
		lines.append(
			(
				"brush entity changed from %s to %s"
				% [
					old_class if old_class != "" else "none",
					new_class if new_class != "" else "none"
				]
			)
		)
	var settings := _settings_changed(
		old.get(HFBrushEntity.DATA_META, {}), now.get(HFBrushEntity.DATA_META, {})
	)
	if settings != "":
		lines.append(settings)
	var wires := _wires_changed(_wires_of(old), _wires_of(now))
	if not wires.is_empty():
		lines.append(wires["line"])
	var old_faces: Array = old.get("faces", [])
	var new_faces: Array = now.get("faces", [])
	var faces_changed := 0
	if old_faces.size() != new_faces.size():
		lines.append("faces changed from %d to %d" % [old_faces.size(), new_faces.size()])
		faces_changed = maxi(old_faces.size(), new_faces.size())
	else:
		var basis := tnew.basis
		var paired := face_pairs(old_faces, new_faces)
		for index in new_faces.size():
			var said := _face_changes(
				old_faces[paired[index]], new_faces[index], palette_old, palette_new
			)
			if said.is_empty():
				continue
			faces_changed += 1
			var face_name := face_name_of(new_faces[index], basis, index)
			for line in said:
				lines.append("face %s: %s" % [face_name, line])
	return {"lines": lines, "faces": faces_changed, "wires": int(wires.get("count", 0))}


static func _face_changes(
	old: Variant, now: Variant, palette_old: Array, palette_new: Array
) -> PackedStringArray:
	var out: PackedStringArray = []
	if not (old is Dictionary and now is Dictionary):
		return out
	var old_material := material_name(palette_old, old)
	var new_material := material_name(palette_new, now)
	if old_material != new_material:
		out.append("material changed from %s to %s" % [old_material, new_material])
	old = _corners_turned_to(old, now)
	for key in ["uv_projection", "uv_scale", "uv_offset", "uv_rotation", "custom_uvs"]:
		if not same(old.get(key), now.get(key)):
			out.append("texture moved")
			break
	if not same(old.get("paint_layers", []), now.get("paint_layers", [])):
		out.append("paint changed")
	if not same(old.get("displacement"), now.get("displacement")):
		out.append("sculpt changed")
	if int(old.get("smoothing_group", 0)) != int(now.get("smoothing_group", 0)):
		out.append("smoothing changed")
	if int(old.get("face_type", 0)) != int(now.get("face_type", 0)):
		out.append("now Hidden" if int(now.get("face_type", 0)) != 0 else "no longer Hidden")
	return out


## `old` with its corners in the order `now` keeps them, when the two are the
## same corners begun at another one, and as it is otherwise. A box an older
## build saved begins its faces at another corner, and loading it turns each
## face's corner data with its corners (`FaceData.relabel_corner_data()`), so
## the same texture read corner by corner is not a change (#1870).
static func _corners_turned_to(old: Dictionary, now: Dictionary) -> Dictionary:
	var was: Array = Array(old.get("local_verts", []))
	var is_now: Array = Array(now.get("local_verts", []))
	var count := was.size()
	if count < 3 or count != is_now.size():
		return old
	for shift in range(1, count):
		var turned := true
		for i in count:
			if not corner(was[(i + shift) % count]).is_equal_approx(corner(is_now[i])):
				turned = false
				break
		if not turned:
			continue
		var out := old.duplicate()
		out["local_verts"] = is_now
		var uvs: Array = Array(old.get("custom_uvs", []))
		if uvs.size() == count:
			var moved: Array = []
			for i in count:
				moved.append(uvs[(i + shift) % count])
			out["custom_uvs"] = moved
		var sculpt: Variant = old.get("displacement")
		if count == 4 and sculpt is Dictionary:
			var corner_from := PackedInt32Array()
			for i in 4:
				corner_from.append((i + shift) % 4)
			var remapped = HFDisplacementData.from_dict(sculpt).remapped(corner_from)
			if remapped != null:
				out["displacement"] = remapped.to_dict()
		return out
	return old


## A face's material by name: the palette slot's file name or resource name, the
## `.map` texture a face with no slot carries, or "none".
static func material_name(palette: Array, face: Dictionary) -> String:
	var index := int(face.get("material_idx", -1))
	if index >= 0 and index < palette.size():
		var entry = palette[index]
		if entry is Resource:
			var resource := entry as Resource
			if resource.resource_name != "":
				return resource.resource_name
			if resource.resource_path != "":
				return resource.resource_path.get_file().get_basename()
		elif entry is Dictionary:
			var path := str((entry as Dictionary).get("path", ""))
			if path != "":
				return path.get_file().get_basename()
			return str((entry as Dictionary).get("name", "slot %d" % index))
		elif entry is String and str(entry) != "":
			return str(entry).get_file().get_basename()
		return "slot %d" % index
	var texture := str(face.get("map_texture", ""))
	return texture if texture != "" else "none"


## A face by the way it faces: "+x", "top", "bottom", or its number when it
## faces no axis.
static func face_name_of(face: Dictionary, basis: Basis, index: int) -> String:
	var normal = face.get("normal", Vector3.ZERO)
	if not (normal is Vector3) or (normal as Vector3).is_zero_approx():
		normal = _normal_from_corners(face.get("local_verts", []))
	if (normal as Vector3).is_zero_approx():
		return "#%d" % index
	var world := (basis * (normal as Vector3)).normalized()
	var axes := {
		"top": Vector3.UP,
		"bottom": Vector3.DOWN,
		"+x": Vector3.RIGHT,
		"-x": Vector3.LEFT,
		"+z": Vector3.BACK,
		"-z": Vector3.FORWARD,
	}
	for label in axes:
		if world.dot(axes[label]) > 0.999:
			return label
	return "#%d" % index


## For each face of `new_faces`, the index of the face of `old_faces` it is.
##
## The same index, unless the faces there point different ways and another old
## face points the way the new one does: a box an older build saved keeps its
## faces in another order, and loading it puts them in this build's, each with
## its own material (#1870). Paired by index, every face of it read as changed.
static func face_pairs(old_faces: Array, new_faces: Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(new_faces.size())
	var old_normals: Array[Vector3] = []
	for face in old_faces:
		old_normals.append(_face_normal(face))
	var new_normals: Array[Vector3] = []
	var taken := {}
	var astray: Array[int] = []
	for index in new_faces.size():
		out[index] = index
		new_normals.append(_face_normal(new_faces[index]))
		if index < old_normals.size() and new_normals[index].dot(old_normals[index]) > 0.999:
			taken[index] = true
		else:
			astray.append(index)
	for index in astray:
		if new_normals[index].is_zero_approx():
			continue
		for other in old_normals.size():
			if not taken.has(other) and new_normals[index].dot(old_normals[other]) > 0.999:
				out[index] = other
				taken[other] = true
				break
	return out


## A face's outward normal in its brush's own space, from its record.
static func _face_normal(face: Variant) -> Vector3:
	if not (face is Dictionary):
		return Vector3.ZERO
	var normal := corner((face as Dictionary).get("normal"))
	if normal.is_zero_approx():
		normal = _normal_from_corners((face as Dictionary).get("local_verts", []))
	return normal.normalized()


## The outward normal of a face's corners, which wind clockwise seen from
## outside, or zero for too few.
static func _normal_from_corners(corners: Variant) -> Vector3:
	if not (corners is Array or corners is PackedVector3Array) or corners.size() < 3:
		return Vector3.ZERO
	var a := corner(corners[0])
	var b := corner(corners[1])
	var c := corner(corners[2])
	return (c - a).cross(b - a).normalized()


## A corner as a record keeps it: a Vector3, or `[x, y, z]`.
static func corner(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and (value as Array).size() == 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO


## "0.5 m up", "2 m along -x", or "1.41 m by (1, 0, 1)" for a move off one axis.
static func moved_text(delta: Vector3) -> String:
	var axis := delta.abs().max_axis_index()
	var along := delta[axis]
	var rest := delta
	rest[axis] = 0.0
	if rest.length() > NEAR:
		return "%s m by (%s)" % [_number(delta.length()), _vec_text(delta)]
	if axis == Vector3.AXIS_Y:
		return "%s m %s" % [_number(absf(along)), "up" if along > 0.0 else "down"]
	return (
		"%s m along %s%s"
		% [_number(absf(along)), "+" if along > 0.0 else "-", "x" if axis == 0 else "z"]
	)


static func _shape_name(shape: Variant) -> String:
	var key = DraftBrush.BrushShape.find_key(int(shape))
	return str(key).to_lower().replace("_", " ") if key != null else "shape %d" % int(shape)


## Two values the same once a number is a number however it was stored: an int
## in the open level is the float a file's JSON gives back, and a packed array
## the plain one.
static func same(a: Variant, b: Variant) -> bool:
	return str(canonical(a)) == str(canonical(b))


static func canonical(value: Variant) -> Variant:
	match typeof(value):
		TYPE_INT:
			return float(value)
		TYPE_STRING_NAME:
			return str(value)
		TYPE_DICTIONARY:
			var keys: Array = (value as Dictionary).keys()
			keys.sort_custom(func(x, y): return str(x) < str(y))
			var out: Array = []
			for key in keys:
				out.append([str(key), canonical(value[key])])
			return out
		TYPE_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_COLOR_ARRAY:
			var out: Array = []
			for item in value:
				out.append(canonical(item))
			return out
	return value


static func _size_text(size: Vector3) -> String:
	return "%s x %s x %s" % [_number(size.x), _number(size.y), _number(size.z)]


static func _vec_text(v: Vector3) -> String:
	return "%s, %s, %s" % [_number(v.x), _number(v.y), _number(v.z)]


static func _number(value: float) -> String:
	var rounded := snappedf(value, 0.01)
	if is_equal_approx(rounded, roundf(rounded)):
		return str(int(rounded))
	return str(rounded)


# ---------------------------------------------------------------------------
# Entities, wires, visgroups, cordons, paint
# ---------------------------------------------------------------------------


static func _entity_name(info: Dictionary) -> String:
	return str(info.get("name", ""))


static func _compare_entities(
	old_state: Dictionary, new_state: Dictionary, counts: Dictionary
) -> Dictionary:
	var old_list: Array = (old_state.get("entities", []) as Array).filter(
		func(e): return e is Dictionary
	)
	var new_list: Array = (new_state.get("entities", []) as Array).filter(
		func(e): return e is Dictionary
	)
	var old_by_name := {}
	for info in old_list:
		old_by_name[_entity_name(info)] = info
	var pairs: Array = []
	var added: Array = []
	var matched := {}
	for info in new_list:
		var key := _entity_name(info)
		if key != "" and old_by_name.has(key) and not matched.has(key):
			pairs.append([old_by_name[key], info])
			matched[key] = true
		else:
			added.append(info)
	var removed: Array = old_list.filter(func(info): return not matched.has(_entity_name(info)))
	# Renamed but the same class in the same place: the same entity.
	for info in added.duplicate():
		for old in removed:
			if (
				_entity_class(old) == _entity_class(info)
				and _entity_place(old).distance_to(_entity_place(info)) <= SAME_PLACE
			):
				pairs.append([old, info])
				added.erase(info)
				removed.erase(old)
				break
	var rows: Array = []
	var changed: Array = []
	for pair in pairs:
		var said := _entity_changes(pair[0], pair[1], counts)
		if said.is_empty():
			continue
		changed.append({"name": _entity_name(pair[1]), "changes": said})
		for line in said:
			rows.append(
				_row(
					"entity '%s': %s" % [_entity_name(pair[1]), line],
					"entity:" + _entity_name(pair[1])
				)
			)
	for info in added:
		rows.append(
			_row(
				"entity '%s' (%s): added" % [_entity_name(info), _entity_class(info)],
				"entity:" + _entity_name(info)
			)
		)
		counts["wires"] += _wires_of(info).size()
	for info in removed:
		rows.append(_row("entity '%s' (%s): removed" % [_entity_name(info), _entity_class(info)]))
		counts["wires"] += _wires_of(info).size()
	counts["entities"] += changed.size() + added.size() + removed.size()
	return {
		"result":
		{
			"added": added.map(func(info): return _entity_name(info)),
			"removed": removed,
			"changed": changed,
		},
		"rows": rows,
	}


static func _entity_class(info: Dictionary) -> String:
	return str(info.get("entity_class", info.get("entity_type", "")))


static func _entity_place(info: Dictionary) -> Vector3:
	return _transform_of(info).origin


## A record's wires: a point entity keeps them under `io_outputs`, a brush under
## `entity_io_outputs` (#1941).
static func _wires_of(info: Dictionary) -> Array:
	var wires = info.get("io_outputs", info.get(HFBrushEntity.OUTPUTS_META, []))
	return wires if wires is Array else []


## "wires: N added, M removed" and how many that is, or empty when the two lists
## hold the same wires.
static func _wires_changed(old_wires: Array, new_wires: Array) -> Dictionary:
	if same(old_wires, new_wires):
		return {}
	var old_text := old_wires.map(func(w): return str(canonical(w)))
	var new_text := new_wires.map(func(w): return str(canonical(w)))
	var gained := new_text.filter(func(w): return not old_text.has(w)).size()
	var lost := old_text.filter(func(w): return not new_text.has(w)).size()
	return {"line": "wires: %d added, %d removed" % [gained, lost], "count": gained + lost}


## "a, b changed" for the settings that differ, or "".
static func _settings_changed(old_settings: Variant, new_settings: Variant) -> String:
	var old_props: Dictionary = old_settings if old_settings is Dictionary else {}
	var new_props: Dictionary = new_settings if new_settings is Dictionary else {}
	var keys: PackedStringArray = []
	for key in old_props.keys() + new_props.keys():
		if not same(old_props.get(key), new_props.get(key)) and not keys.has(str(key)):
			keys.append(str(key))
	return "%s changed" % ", ".join(keys) if not keys.is_empty() else ""


static func _entity_changes(
	old: Dictionary, now: Dictionary, counts: Dictionary
) -> PackedStringArray:
	var out: PackedStringArray = []
	var delta := _entity_place(now) - _entity_place(old)
	if delta.length() > NEAR:
		out.append("moved %s" % moved_text(delta))
	# Its turn, not its scale (#1941).
	var old_turn := _transform_of(old).basis.orthonormalized()
	if not old_turn.is_equal_approx(_transform_of(now).basis.orthonormalized()):
		out.append("turned")
	if _entity_class(old) != _entity_class(now):
		out.append("class changed from %s to %s" % [_entity_class(old), _entity_class(now)])
	var settings := _settings_changed(old.get("properties", {}), now.get("properties", {}))
	if settings != "":
		out.append(settings)
	var wires := _wires_changed(_wires_of(old), _wires_of(now))
	if not wires.is_empty():
		counts["wires"] += int(wires["count"])
		out.append(wires["line"])
	return out


static func _compare_visgroups(
	old_state: Dictionary, new_state: Dictionary, counts: Dictionary
) -> PackedStringArray:
	var lines: PackedStringArray = []
	var old_groups: Dictionary = (
		old_state.get("visgroups", {}) if old_state.get("visgroups") is Dictionary else {}
	)
	var new_groups: Dictionary = (
		new_state.get("visgroups", {}) if new_state.get("visgroups") is Dictionary else {}
	)
	for vg_name in new_groups:
		if not old_groups.has(vg_name):
			lines.append("visgroup '%s': added" % vg_name)
			counts["visgroups"] += 1
		elif not same(_visgroup(old_groups[vg_name]), _visgroup(new_groups[vg_name])):
			lines.append("visgroup '%s': changed" % vg_name)
			counts["visgroups"] += 1
	for vg_name in old_groups:
		if not new_groups.has(vg_name):
			lines.append("visgroup '%s': removed" % vg_name)
			counts["visgroups"] += 1
	return lines


static func _visgroup(entry: Variant) -> Variant:
	return HFVisgroupSystem.record_from(entry) if entry is Dictionary else entry


const CORDON_KEYS := [
	"cordon_enabled",
	"cordon_aabb_pos",
	"cordon_aabb_size",
	"cordon_aabb_active",
	"cordon_extra_aabbs"
]

## What a load reads for a cordon key a file older than it leaves out
## (`HFStateSystem.apply_hflevel_settings()`): the first cordon on, and no others.
const CORDON_DEFAULTS := {"cordon_aabb_active": true, "cordon_extra_aabbs": []}


static func _compare_cordons(
	old_settings: Dictionary, new_settings: Dictionary, counts: Dictionary
) -> PackedStringArray:
	for key in CORDON_KEYS:
		var fallback: Variant = CORDON_DEFAULTS.get(key)
		if not same(old_settings.get(key, fallback), new_settings.get(key, fallback)):
			counts["cordons"] += 1
			return PackedStringArray(["cordons: changed"])
	return PackedStringArray()


static func _compare_paint(
	old_state: Dictionary, new_state: Dictionary, counts: Dictionary
) -> PackedStringArray:
	var lines: PackedStringArray = []
	var old_layers := {}
	for entry in old_state.get("paint_layers", []):
		if entry is Dictionary:
			old_layers[str(entry.get("id", ""))] = entry
	var seen := {}
	for entry in new_state.get("paint_layers", []):
		if not (entry is Dictionary):
			continue
		var layer_id := str(entry.get("id", ""))
		seen[layer_id] = true
		var label := _layer_label(entry)
		if not old_layers.has(layer_id):
			lines.append("paint layer '%s': added" % label)
			counts["paint"] += 1
		elif not same(old_layers[layer_id], entry):
			lines.append("paint layer '%s': painted" % label)
			counts["paint"] += 1
	for layer_id in old_layers:
		if not seen.has(layer_id):
			# By the name it had, as an added one is named (#1992).
			lines.append("paint layer '%s': removed" % _layer_label(old_layers[layer_id]))
			counts["paint"] += 1
	return lines


## A paint layer by the name the mapper gave it, or its id when it has none.
static func _layer_label(entry: Dictionary) -> String:
	var shown := str(entry.get("display_name", ""))
	return shown if shown != "" else str(entry.get("id", ""))
