@tool
class_name HFMcpTools
extends RefCounted
## What each MCP bridge tool does, given a LevelRoot and its arguments.
##
## `HFMcpDispatcher` owns the contract around a call: the target, the revision,
## the operation cache, and the one wrapper that captures the level, runs a
## change, and records it as a single undo step or puts the level back. This owns
## the calls themselves:
##
## - `_check_<tool>(root, params)` reads and validates the arguments before
##   anything changes, and returns `{ok, scope_ids, apply}`, where `apply` is a
##   bound `_apply_<tool>` that makes the change through LevelRoot's facade and
##   records no undo of its own.
## - `_read_<tool>(root, params)` answers a read: `{ok, result}`.
## - A refusal is `{ok: false, error: {code, message, details}}`.
## - `brush_dict()` and the palette turn the level into plain data.
##
## Nothing here holds a node between calls; a tool finds what it needs by id.

# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFMcpProtocol = preload("hf_mcp_protocol.gd")
const DraftBrush = preload("../brush_instance.gd")
const LevelRoot = preload("../level_root.gd")
const DraftEntity = preload("../draft_entity.gd")
const HFEntityPropUtils = preload("../ui/hf_entity_prop_utils.gd")
@warning_ignore_restore("shadowed_global_identifier")

## World axes a face selector may name.
const SIDES := {
	"+x": Vector3.RIGHT,
	"-x": Vector3.LEFT,
	"+y": Vector3.UP,
	"-y": Vector3.DOWN,
	"+z": Vector3.BACK,
	"-z": Vector3.FORWARD,
}

## A side or normal must point at least this close to a face's normal (about 45
## degrees) to pick it, and two faces this close to equal are a tie.
const FACE_MATCH_MIN := 0.7
const FACE_TIE := 0.001

## Lower-case shape name -> BrushShape value, and back.
var _shape_by_name: Dictionary = {}
var _name_by_shape: Dictionary = {}


func _init() -> void:
	for key in LevelRoot.BrushShape.keys():
		var value: int = LevelRoot.BrushShape[key]
		_shape_by_name[str(key).to_lower()] = value
		_name_by_shape[value] = str(key).to_lower()


static func _fail(code: String, message: String, details := {}) -> Dictionary:
	return {"ok": false, "error": HFMcpProtocol.error_body(code, message, details)}


# ---------------------------------------------------------------------------
# hf_place_brush
# ---------------------------------------------------------------------------


func _check_place_brush(root: Node, params: Dictionary) -> Dictionary:
	var shape_read := HFMcpProtocol.read_string(params, "shape", false, "box")
	if not shape_read["ok"]:
		return shape_read
	var shape_name := str(shape_read["value"]).to_lower()
	if not _shape_by_name.has(shape_name) or shape_name == "custom":
		var names: Array = _shape_by_name.keys()
		names.erase("custom")
		return HFMcpProtocol.invalid("shape", "shape must be one of: %s" % ", ".join(names))
	var size_read := HFMcpProtocol.read_positive_vec3(params, "size", true)
	if not size_read["ok"]:
		return size_read
	var position_read := HFMcpProtocol.read_vec3(params, "position", true)
	if not position_read["ok"]:
		return position_read
	var operation_read := HFMcpProtocol.read_string(params, "operation", false, "union")
	if not operation_read["ok"]:
		return operation_read
	var operation_name := str(operation_read["value"])
	if operation_name != "union" and operation_name != "subtract":
		return HFMcpProtocol.invalid("operation", "operation must be union or subtract")
	var snap_read := HFMcpProtocol.read_bool(params, "snap", true)
	if not snap_read["ok"]:
		return snap_read
	# What the brush is placed with in the same step, rather than an op each after
	# it (#1039).
	var slot = null
	if params.get("material") != null:
		var material := _resolve_material(root, params["material"])
		if not material["ok"]:
			return material
		slot = material["slot"]
	var rotation = null
	var rotated := false
	if params.get("rotation_degrees") != null:
		var turn := HFMcpProtocol.read_vec3(params, "rotation_degrees", true)
		if not turn["ok"]:
			return turn
		rotation = turn["value"]
		rotated = _turns(rotation)
	var sides = null
	if params.get("sides") != null:
		var sides_read := _read_sides(params, shape_name)
		if not sides_read["ok"]:
			return sides_read
		sides = sides_read["value"]

	var box := _snap_box(
		root,
		_shape_by_name[shape_name],
		size_read["value"],
		position_read["value"],
		rotated,
		snap_read["value"]
	)
	var operation := (
		CSGShape3D.OPERATION_SUBTRACTION
		if operation_name == "subtract"
		else CSGShape3D.OPERATION_UNION
	)
	var plan := {
		"shape": _shape_by_name[shape_name],
		"size": box["size"],
		"center": box["center"],
		"operation": operation,
		"snapped": box["snapped"],
		"slot": slot,
		"rotation": rotation,
		"sides": sides,
	}
	if box["snapped"]:
		plan["requested"] = {
			"position": HFMcpProtocol.vec3_to_array(position_read["value"]),
			"size": HFMcpProtocol.vec3_to_array(size_read["value"]),
		}
	return {"ok": true, "scope_ids": [], "apply": _apply_place_brush.bind(root, plan)}


## Which shapes take `sides`, and from how many: a cylinder or cone below five is
## built from its default of 16 (`DraftBrush.round_sides()`), and a pyramid's base
## needs three.
const SIDED_SHAPES := {"cylinder": 5, "cone": 5, "pyramid": 3}
const MAX_SIDES := 64


func _read_sides(params: Dictionary, shape_name: String) -> Dictionary:
	if not SIDED_SHAPES.has(shape_name):
		return HFMcpProtocol.invalid(
			"sides", "sides is for a cylinder, a cone or a pyramid, not a %s" % shape_name
		)
	var raw = params["sides"]
	var low: int = SIDED_SHAPES[shape_name]
	if not (raw is int or raw is float) or float(raw) != floorf(float(raw)):
		return HFMcpProtocol.invalid("sides", "sides is a whole number")
	if int(raw) < low or int(raw) > MAX_SIDES:
		return HFMcpProtocol.invalid(
			"sides", "a %s takes %d to %d sides" % [shape_name, low, MAX_SIDES]
		)
	return {"ok": true, "value": int(raw)}


## Whether Euler degrees turn a brush at all, so a full turn counts as square.
static func _turns(degrees: Vector3) -> bool:
	var radians := Vector3(deg_to_rad(degrees.x), deg_to_rad(degrees.y), deg_to_rad(degrees.z))
	return not Basis.from_euler(radians, EULER_ORDER_XYZ).is_equal_approx(Basis.IDENTITY)


func _apply_place_brush(root: Node, plan: Dictionary) -> Dictionary:
	var operation: int = plan["operation"]
	var info := {
		"shape": plan["shape"],
		"size": plan["size"],
		"transform": Transform3D(Basis(), plan["center"]),
		"operation": operation,
		"pending": operation == CSGShape3D.OPERATION_SUBTRACTION and root.pending_node != null,
		# Minted here, not left to create_brush_from_info, so the id in the
		# answer is the one undo and redo bring back.
		"brush_id": root._next_brush_id(),
	}
	if plan["sides"] != null:
		info["sides"] = plan["sides"]
	var node = root.create_brush_from_info(info)
	if node == null or not (node is DraftBrush):
		return _fail(HFMcpProtocol.E_OPERATION_FAILED, "HammerForge could not create the brush")
	var brush_id: String = (node as DraftBrush).brush_id
	if plan["rotation"] != null:
		var turned: HFOpResult = root.set_brush_rotation_by_id(brush_id, plan["rotation"])
		if not turned.ok:
			return _fail(HFMcpProtocol.E_OPERATION_FAILED, turned.user_text())
	if plan["slot"] != null:
		root.assign_material_to_whole_brushes(plan["slot"], [brush_id])
	var placed := root.find_brush_by_id(brush_id) as DraftBrush
	return {"ok": true, "result": _snap_answer({"brush": brush_dict(root, placed)}, plan)}


## `snapped` says whether snapping moved what was asked for, and `requested` what
## that was, beside the brush as applied. It was true for every change made with
## snap on, moved or not, so it told an agent nothing (#1038).
static func _snap_answer(result: Dictionary, plan: Dictionary) -> Dictionary:
	result["snapped"] = plan["snapped"]
	if plan.has("requested"):
		result["requested"] = plan["requested"]
	return result


# ---------------------------------------------------------------------------
# Shared readers
# ---------------------------------------------------------------------------

## The Extrude tool's own limit on how far a face goes out.
const MAX_EXTRUDE := 256.0


## Size to whole grid steps, then the centre placed by `_snap_center()`.
##
## The size is the one the brush will really have: a sphere is as wide as it is
## tall, and a cylinder as deep as it is wide, whatever was asked for. Snapping
## the corner of the asked-for size would float a sphere asked for as [2, 4, 2] a
## metre off the floor.
func _snap_box(
	root: Node, shape: int, size: Vector3, center: Vector3, rotated: bool, snap: bool
) -> Dictionary:
	size = DraftBrush.normalized_size_for_shape(shape, size)
	var grid: float = root.grid_snap
	if not snap or grid <= 0.0:
		return {"size": size, "center": center, "snapped": false}
	var asked := size
	size = Vector3(
		maxf(grid, snappedf(size.x, grid)),
		maxf(grid, snappedf(size.y, grid)),
		maxf(grid, snappedf(size.z, grid))
	)
	size = DraftBrush.normalized_size_for_shape(shape, size)
	var placed := _snap_center(root, size, center, rotated, snap)
	var moved: bool = placed["snapped"] or not size.is_equal_approx(asked)
	return {"size": size, "center": placed["center"], "snapped": moved}


## An unrotated box's lowest corner goes on the grid, as a drawn brush's does, so
## its faces sit on grid lines whatever its size. A rotated one snaps its centre,
## since its corners are not on the grid's axes.
func _snap_center(
	root: Node, size: Vector3, center: Vector3, rotated: bool, snap: bool
) -> Dictionary:
	var grid: float = root.grid_snap
	if not snap or grid <= 0.0:
		return {"center": center, "snapped": false}
	var step := Vector3.ONE * grid
	var placed := center.snapped(step)
	if not rotated:
		placed = (center - size * 0.5).snapped(step) + size * 0.5
	return {"center": placed, "snapped": not placed.is_equal_approx(center)}


## The brush `params.brush_id` names, or a refusal.
func _read_brush(root: Node, params: Dictionary) -> Dictionary:
	var read := HFMcpProtocol.read_string(params, "brush_id", true)
	if not read["ok"]:
		return read
	var brush_id: String = read["value"]
	# Never look "" up: the brush system's slow path matches a brush with no id.
	if brush_id == "":
		return HFMcpProtocol.invalid("brush_id", "brush_id must not be empty")
	var node = root.find_brush_by_id(brush_id)
	# The brush cache can hand back a committed cut, which a scan would not find.
	# Either way it is frozen into the level, and the bridge leaves it alone.
	var committed: bool = node is DraftBrush and node.get_parent() == root.committed_node
	if committed or not (node is DraftBrush):
		if committed or _is_committed_cut(root, brush_id):
			return _fail(
				HFMcpProtocol.E_BRUSH_NOT_FOUND,
				(
					(
						"Brush '%s' is a committed cut. Committed cuts are frozen into the "
						+ "level and cannot be changed."
					)
					% brush_id
				),
				{"brush_id": brush_id, "committed": true}
			)
		return _fail(
			HFMcpProtocol.E_BRUSH_NOT_FOUND,
			"There is no brush '%s'. hf_get_brushes lists them." % brush_id,
			{"brush_id": brush_id}
		)
	return {"ok": true, "brush": node}


static func _is_committed_cut(root: Node, brush_id: String) -> bool:
	if root.committed_node == null:
		return false
	for child in root.committed_node.get_children():
		if child is DraftBrush and (child as DraftBrush).brush_id == brush_id:
			return true
	return false


static func _is_rotated(brush: DraftBrush) -> bool:
	return not brush.global_transform.basis.orthonormalized().is_equal_approx(Basis.IDENTITY)


## A face of `brush` from a selector: an index, a side such as "+y", or
## `{"normal": [x, y, z]}`.
func _resolve_face(brush: DraftBrush, selector) -> Dictionary:
	if selector == null:
		return HFMcpProtocol.invalid("face", "face is required")
	if (selector is int or selector is float) and not (selector is bool):
		var number := float(selector)
		if number != floorf(number):
			return HFMcpProtocol.invalid("face", "a face index is a whole number")
		var index := int(number)
		if index < 0 or index >= brush.faces.size() or brush.faces[index] == null:
			return _fail(
				HFMcpProtocol.E_FACE_NOT_FOUND,
				(
					"Brush '%s' has no face %d; it has %d"
					% [brush.brush_id, index, brush.faces.size()]
				),
				{"face_count": brush.faces.size()}
			)
		return {"ok": true, "index": index}
	var direction := Vector3.ZERO
	if selector is String:
		if not SIDES.has(selector):
			return HFMcpProtocol.invalid("face", "a side is one of %s" % ", ".join(SIDES.keys()))
		direction = SIDES[selector]
	elif selector is Dictionary:
		var read := HFMcpProtocol.read_vec3(selector, "normal", true)
		if not read["ok"] or (read["value"] as Vector3).is_zero_approx():
			return HFMcpProtocol.invalid("face", 'a face normal is {"normal": [x, y, z]}, not zero')
		direction = (read["value"] as Vector3).normalized()
	else:
		return HFMcpProtocol.invalid(
			"face", 'a face is an index, a side such as "+y", or {"normal": [x, y, z]}'
		)
	return _face_toward(brush, direction)


## The face whose world normal points most nearly along `direction`. It has to
## be within about 45 degrees, and a tie is refused rather than guessed.
func _face_toward(brush: DraftBrush, direction: Vector3) -> Dictionary:
	var basis := brush.global_transform.basis
	var best := -1
	var best_dot := -2.0
	var dots: Array = []
	for i in brush.faces.size():
		var face = brush.faces[i]
		if face == null:
			continue
		face.ensure_geometry()
		var dot: float = face.normal_through(basis).dot(direction)
		dots.append([i, dot])
		if dot > best_dot:
			best_dot = dot
			best = i
	if best < 0 or best_dot < FACE_MATCH_MIN:
		return _fail(
			HFMcpProtocol.E_FACE_NOT_FOUND,
			"No face of brush '%s' points that way" % brush.brush_id,
			{"closest": best, "dot": best_dot}
		)
	var tied: Array = []
	for pair in dots:
		if best_dot - float(pair[1]) <= FACE_TIE:
			tied.append(pair[0])
	if tied.size() > 1:
		return _fail(
			HFMcpProtocol.E_AMBIGUOUS_FACE,
			(
				"%d faces of brush '%s' point that way equally; name one by index"
				% [tied.size(), brush.brush_id]
			),
			{"candidates": tied}
		)
	return {"ok": true, "index": best}


## A palette slot from a material id (a path, or "palette:N"), or a name in any
## case. Two materials with the name are refused, not guessed between.
func _resolve_material(root: Node, value) -> Dictionary:
	if not (value is String) or (value as String).is_empty():
		return HFMcpProtocol.invalid(
			"material", "material is an id or a name that hf_get_materials lists"
		)
	var palette := _palette(root)
	for slot in palette.size():
		if palette[slot]["id"] == value:
			return {"ok": true, "slot": slot}
	# A slot named outright, for any material, not only one without a file.
	var text := value as String
	if text.begins_with("palette:") and text.trim_prefix("palette:").is_valid_int():
		var named_slot := text.trim_prefix("palette:").to_int()
		if named_slot >= 0 and named_slot < palette.size():
			return {"ok": true, "slot": named_slot}
	var wanted := (value as String).to_lower()
	var named: Array = []
	for slot in palette.size():
		if str(palette[slot]["name"]).to_lower() == wanted:
			named.append(slot)
	if named.size() == 1:
		return {"ok": true, "slot": named[0]}
	if named.size() > 1:
		var ids: Array = []
		for slot in named:
			ids.append(palette[slot]["id"])
		return _fail(
			HFMcpProtocol.E_AMBIGUOUS_MATERIAL,
			"%d materials are called '%s'; use an id" % [named.size(), value],
			{"ids": ids}
		)
	return _fail(
		HFMcpProtocol.E_UNKNOWN_MATERIAL,
		"No material '%s' in this level's palette. hf_get_materials lists them." % value,
		{"material": value}
	)


# ---------------------------------------------------------------------------
# hf_get_brushes, hf_get_materials
# ---------------------------------------------------------------------------


func _read_brushes(root: Node, params: Dictionary) -> Dictionary:
	var ids_read := HFMcpProtocol.read_string_array(params, "brush_ids", false, [])
	if not ids_read["ok"]:
		return ids_read
	var faces_read := HFMcpProtocol.read_bool(params, "include_faces", true)
	if not faces_read["ok"]:
		return faces_read
	var limit_read := HFMcpProtocol.read_int(params, "limit", false, 200, 1, 2000)
	if not limit_read["ok"]:
		return limit_read
	var bounds := AABB()
	var use_bounds := false
	if params.get("bounds") != null:
		var raw = params["bounds"]
		var low := HFMcpProtocol.read_vec3(raw if raw is Dictionary else {}, "min", true)
		var high := HFMcpProtocol.read_vec3(raw if raw is Dictionary else {}, "max", true)
		if not low["ok"] or not high["ok"]:
			return HFMcpProtocol.invalid("bounds", 'bounds is {"min": [x, y, z], "max": [x, y, z]}')
		bounds = AABB(low["value"], high["value"] - low["value"]).abs()
		use_bounds = true
	var wanted: Array = ids_read["value"]
	var seen := {}
	var matches: Array = []
	for node in root._iter_managed_brush_nodes():
		var brush := node as DraftBrush
		if not wanted.is_empty():
			if not (brush.brush_id in wanted):
				continue
			seen[brush.brush_id] = true
		if use_bounds and not root.brush_system.world_bounds_of(brush).intersects(bounds):
			continue
		matches.append(brush)
	var limit: int = limit_read["value"]
	var listed: Array = []
	var palette := _palette(root)
	for brush in matches.slice(0, limit):
		listed.append(brush_dict(root, brush, faces_read["value"], palette))
	var missing: Array = []
	for brush_id in wanted:
		if not seen.has(brush_id):
			missing.append(brush_id)
	var result := {
		"brushes": listed,
		"total": matches.size(),
		"truncated": matches.size() > limit,
		"missing": missing,
	}
	return {"ok": true, "result": result}


## Everything HammerForge would warn about before a bake, in one list: the bake
## checks, the spawn's layout, and Validate's own findings, without its fixes.
func _read_validate(root: Node, _params: Dictionary) -> Dictionary:
	var found: Array = []
	if root.validation_system:
		found.append_array(root.validation_system.check_bake_issues())
	if root.spawn_system:
		found.append_array(root.spawn_system.layout_issues())
	var report: Dictionary = root.validate_level(false)
	found.append_array(report.get("findings", []))
	var issues: Array = []
	var seen := {}
	var counts := {"error": 0, "warning": 0, "info": 0}
	for item in found:
		if not (item is Dictionary):
			continue
		var entry := _issue_dict(root, item)
		# What it is about too: two brushes with the same name and the same
		# problem are two findings.
		var about := str(entry.get("brush_id", entry.get("entity", "")))
		var key := (
			"%s|%s|%s|%s"
			% [entry["type"], entry["message"], about, entry.get("other_brush_id", "")]
		)
		if seen.has(key):
			continue
		seen[key] = true
		issues.append(entry)
		counts[entry["severity"]] += 1
	return {"ok": true, "result": {"issues": issues, "counts": counts}}


const _SEVERITIES := ["info", "warning", "error"]


## One finding as plain data. `node` is a live reference in HammerForge's own
## findings; here it becomes the brush id, or the entity's path in the level.
func _issue_dict(root: Node, item: Dictionary) -> Dictionary:
	var severity := clampi(int(item.get("severity", 1)), 0, 2)
	var entry := {
		"type": str(item.get("type", "")),
		"severity": _SEVERITIES[severity],
		"message": str(item.get("message", "")),
	}
	var node = item.get("node")
	if node is DraftBrush and is_instance_valid(node):
		var brush_id := (node as DraftBrush).brush_id
		entry["brush_id"] = null
		if brush_id != "":
			entry["brush_id"] = brush_id
	elif node is Node and is_instance_valid(node):
		entry["entity"] = str(root.get_path_to(node))
	# A finding about a pair names the second brush too (#1037).
	var other = item.get("other_node")
	if other is DraftBrush and is_instance_valid(other) and (other as DraftBrush).brush_id != "":
		entry["other_brush_id"] = (other as DraftBrush).brush_id
	if item.has("fix"):
		entry["fix"] = str(item["fix"])
	return entry


## The world box a screenshot frames: `{brush_ids: [...]}` (all of them) or
## `{bounds: {min, max}}`. `{ok, bounds}` or a refusal.
func focus_bounds(root: Node, focus) -> Dictionary:
	if not (focus is Dictionary):
		return HFMcpProtocol.invalid(
			"focus", 'focus is {"brush_ids": [...]} or {"bounds": {min, max}}'
		)
	if focus.has("brush_ids"):
		var ids := HFMcpProtocol.read_string_array(focus, "brush_ids", true)
		if not ids["ok"] or (ids["value"] as Array).is_empty():
			return HFMcpProtocol.invalid("focus", "focus.brush_ids is a list of brush ids")
		var box := AABB()
		var first := true
		for brush_id in ids["value"]:
			var found := _read_brush(root, {"brush_id": brush_id})
			if not found["ok"]:
				return found
			var bounds: AABB = root.brush_system.world_bounds_of(found["brush"])
			box = bounds if first else box.merge(bounds)
			first = false
		return {"ok": true, "bounds": box}
	if focus.has("bounds"):
		var raw = focus["bounds"]
		var low := HFMcpProtocol.read_vec3(raw if raw is Dictionary else {}, "min", true)
		var high := HFMcpProtocol.read_vec3(raw if raw is Dictionary else {}, "max", true)
		if not low["ok"] or not high["ok"]:
			return HFMcpProtocol.invalid(
				"focus", 'focus.bounds is {"min": [x, y, z], "max": [x, y, z]}'
			)
		return {"ok": true, "bounds": AABB(low["value"], high["value"] - low["value"]).abs()}
	return HFMcpProtocol.invalid("focus", 'focus is {"brush_ids": [...]} or {"bounds": {min, max}}')


## Where a camera looking along `direction` has to stand to see all of `bounds`:
## back from its middle by enough that the sphere around it fits the narrower of
## the two fields of view, with a little room. `{position, target}`.
static func frame_bounds(bounds: AABB, direction: Vector3, fov: float, aspect: float) -> Dictionary:
	var centre := bounds.get_center()
	var radius := maxf(bounds.size.length() * 0.5, 0.5)
	var half_v := deg_to_rad(clampf(fov, 1.0, 179.0)) * 0.5
	var half_h := atan(tan(half_v) * maxf(aspect, 0.01))
	var distance := radius / sin(minf(half_v, half_h)) * 1.05
	var along := direction.normalized() if not direction.is_zero_approx() else Vector3.FORWARD
	return {"position": centre - along * distance, "target": centre}


func _read_materials(root: Node, _params: Dictionary) -> Dictionary:
	var listed: Array = []
	var palette := _palette(root)
	for slot in palette.size():
		var entry: Dictionary = (palette[slot] as Dictionary).duplicate()
		entry["slot"] = slot
		listed.append(entry)
	return {"ok": true, "result": {"materials": listed}}


# ---------------------------------------------------------------------------
# hf_transform_brush, hf_resize_brush, hf_delete_brush
# ---------------------------------------------------------------------------


func _check_transform_brush(root: Node, params: Dictionary) -> Dictionary:
	var found := _read_brush(root, params)
	if not found["ok"]:
		return found
	var brush: DraftBrush = found["brush"]
	var has_position: bool = params.get("position") != null
	var has_rotation: bool = params.get("rotation_degrees") != null
	if not has_position and not has_rotation:
		return HFMcpProtocol.invalid("position", "give position, rotation_degrees, or both")
	var plan := {"brush_id": brush.brush_id, "snapped": false}
	var rotated := _is_rotated(brush)
	if has_rotation:
		var turn := HFMcpProtocol.read_vec3(params, "rotation_degrees", true)
		if not turn["ok"]:
			return turn
		plan["rotation"] = turn["value"]
		var degrees: Vector3 = turn["value"]
		# By the turn it makes, so a full 360 counts as square.
		rotated = _turns(degrees)
	if has_position:
		var spot := HFMcpProtocol.read_vec3(params, "position", true)
		if not spot["ok"]:
			return spot
		var snap_read := HFMcpProtocol.read_bool(params, "snap", true)
		if not snap_read["ok"]:
			return snap_read
		var placed := _snap_center(root, brush.size, spot["value"], rotated, snap_read["value"])
		plan["position"] = placed["center"]
		plan["snapped"] = placed["snapped"]
		if placed["snapped"]:
			plan["requested"] = {"position": HFMcpProtocol.vec3_to_array(spot["value"])}
	return {
		"ok": true,
		"scope_ids": [brush.brush_id],
		"apply": _apply_transform_brush.bind(root, plan),
	}


func _apply_transform_brush(root: Node, plan: Dictionary) -> Dictionary:
	var brush_id: String = plan["brush_id"]
	if plan.has("rotation"):
		var turned: HFOpResult = root.set_brush_rotation_by_id(brush_id, plan["rotation"])
		if not turned.ok:
			return _fail(HFMcpProtocol.E_OPERATION_FAILED, turned.user_text())
	if plan.has("position"):
		var brush := root.find_brush_by_id(brush_id) as DraftBrush
		root.set_brush_transform_by_id(brush_id, brush.size, plan["position"])
	var moved := root.find_brush_by_id(brush_id) as DraftBrush
	if moved == null:
		return _fail(HFMcpProtocol.E_OPERATION_FAILED, "Brush '%s' went missing" % brush_id)
	return {"ok": true, "result": _snap_answer({"brush": brush_dict(root, moved)}, plan)}


func _check_resize_brush(root: Node, params: Dictionary) -> Dictionary:
	var found := _read_brush(root, params)
	if not found["ok"]:
		return found
	var brush: DraftBrush = found["brush"]
	if brush.shape == LevelRoot.BrushShape.CUSTOM:
		return _fail(
			HFMcpProtocol.E_UNSUPPORTED_SHAPE,
			(
				(
					"Brush '%s' is a custom shape (merged, clipped, bevelled or drawn as a polygon). "
					+ "It keeps its own faces, so a new size would change nothing."
				)
				% brush.brush_id
			),
			{"brush_id": brush.brush_id}
		)
	var size_read := HFMcpProtocol.read_positive_vec3(params, "size", true)
	if not size_read["ok"]:
		return size_read
	var snap_read := HFMcpProtocol.read_bool(params, "snap", true)
	if not snap_read["ok"]:
		return snap_read
	var box := _snap_box(
		root,
		brush.shape,
		size_read["value"],
		brush.global_position,
		_is_rotated(brush),
		snap_read["value"]
	)
	var plan := {
		"brush_id": brush.brush_id,
		"size": box["size"],
		"center": box["center"],
		"snapped": box["snapped"],
	}
	if box["snapped"]:
		plan["requested"] = {
			"position": HFMcpProtocol.vec3_to_array(brush.global_position),
			"size": HFMcpProtocol.vec3_to_array(size_read["value"]),
		}
	return {
		"ok": true, "scope_ids": [brush.brush_id], "apply": _apply_resize_brush.bind(root, plan)
	}


func _apply_resize_brush(root: Node, plan: Dictionary) -> Dictionary:
	root.set_brush_transform_by_id(plan["brush_id"], plan["size"], plan["center"])
	var brush := root.find_brush_by_id(plan["brush_id"]) as DraftBrush
	if brush == null:
		return _fail(HFMcpProtocol.E_OPERATION_FAILED, "Brush '%s' went missing" % plan["brush_id"])
	return {"ok": true, "result": _snap_answer({"brush": brush_dict(root, brush)}, plan)}


func _check_delete_brush(root: Node, params: Dictionary) -> Dictionary:
	var found := _read_brush(root, params)
	if not found["ok"]:
		return found
	var brush_id: String = (found["brush"] as DraftBrush).brush_id
	# The whole level: deleting a brush also takes the entity wires aimed at it
	# out of other objects, which a scope on the brush alone would not put back.
	return {"ok": true, "scope_ids": [], "apply": _apply_delete_brush.bind(root, brush_id)}


func _apply_delete_brush(root: Node, brush_id: String) -> Dictionary:
	var deleted: HFOpResult = root.delete_brush_by_id(brush_id)
	if not deleted.ok:
		return _fail(HFMcpProtocol.E_OPERATION_FAILED, deleted.user_text())
	return {"ok": true, "result": {"deleted": brush_id}}


# ---------------------------------------------------------------------------
# hf_extrude_face, hf_assign_material
# ---------------------------------------------------------------------------


func _check_extrude_face(root: Node, params: Dictionary) -> Dictionary:
	var found := _read_brush(root, params)
	if not found["ok"]:
		return found
	var brush: DraftBrush = found["brush"]
	var face := _resolve_face(brush, params.get("face"))
	if not face["ok"]:
		return face
	var distance_read := HFMcpProtocol.read_number(params, "distance", true)
	if not distance_read["ok"]:
		return distance_read
	var distance: float = distance_read["value"]
	if distance <= 0.0 or distance > MAX_EXTRUDE:
		return HFMcpProtocol.invalid(
			"distance", "distance must be above 0 and at most %d" % int(MAX_EXTRUDE)
		)
	var snap_read := HFMcpProtocol.read_bool(params, "snap", true)
	if not snap_read["ok"]:
		return snap_read
	var grid: float = root.grid_snap
	var asked := distance
	if snap_read["value"] and grid > 0.0:
		distance = minf(MAX_EXTRUDE, maxf(grid, snappedf(distance, grid)))
	var snapping := not is_equal_approx(distance, asked)
	var plan := {
		"brush_id": brush.brush_id,
		"face_index": face["index"],
		"distance": distance,
		"snapped": snapping,
	}
	return {"ok": true, "scope_ids": [], "apply": _apply_extrude_face.bind(root, plan)}


func _apply_extrude_face(root: Node, plan: Dictionary) -> Dictionary:
	var info: Dictionary = root.extrude_face_info(
		plan["brush_id"], plan["face_index"], plan["distance"]
	)
	if info.is_empty():
		return _fail(HFMcpProtocol.E_OPERATION_FAILED, "That face cannot be extruded")
	var made = root.create_brush_from_info(info)
	if not (made is DraftBrush):
		return _fail(HFMcpProtocol.E_OPERATION_FAILED, "HammerForge could not create the brush")
	var result := {
		"brush": brush_dict(root, made),
		"source_brush_id": plan["brush_id"],
		"face_index": plan["face_index"],
		"distance": plan["distance"],
		"snapped": plan["snapped"],
	}
	return {"ok": true, "result": result}


func _check_assign_material(root: Node, params: Dictionary) -> Dictionary:
	var found := _read_brush(root, params)
	if not found["ok"]:
		return found
	var brush: DraftBrush = found["brush"]
	var material := _resolve_material(root, params.get("material"))
	if not material["ok"]:
		return material
	var faces = null
	if params.get("faces") != null:
		if not (params["faces"] is Array) or (params["faces"] as Array).is_empty():
			return HFMcpProtocol.invalid("faces", "faces is a list of face selectors")
		var indices: Array = []
		for selector in params["faces"]:
			var face := _resolve_face(brush, selector)
			if not face["ok"]:
				return face
			if not (face["index"] in indices):
				indices.append(face["index"])
		faces = indices
	var plan := {"brush_id": brush.brush_id, "slot": material["slot"], "faces": faces}
	return {
		"ok": true,
		"scope_ids": [brush.brush_id],
		"apply": _apply_assign_material.bind(root, plan),
	}


func _apply_assign_material(root: Node, plan: Dictionary) -> Dictionary:
	var brush_id: String = plan["brush_id"]
	if plan["faces"] == null:
		root.assign_material_to_whole_brushes(plan["slot"], [brush_id])
	else:
		root.assign_material_to_faces_by_id(brush_id, plan["faces"], plan["slot"])
	var brush := root.find_brush_by_id(brush_id) as DraftBrush
	if brush == null:
		return _fail(HFMcpProtocol.E_OPERATION_FAILED, "Brush '%s' went missing" % brush_id)
	return {"ok": true, "result": {"brush": brush_dict(root, brush)}}


# ---------------------------------------------------------------------------
# hf_place_entity, hf_get_entities
# ---------------------------------------------------------------------------


## The classes hf_place_entity places: those whose definition names the node a
## game gets, such as an OmniLight3D. A brush entity class (func_wall, trigger_once)
## has none, since it is set on brushes, and the spawn has hf_set_spawn.
func placeable_classes(root: Node) -> Array:
	var names: Array = []
	var definitions: Dictionary = root.get_entity_definitions()
	for key in definitions:
		var definition = definitions[key]
		if key == "player_start" or not (definition is Dictionary):
			continue
		if str((definition as Dictionary).get("class", "")) != "":
			names.append(str(key))
	names.sort()
	return names


func _check_place_entity(root: Node, params: Dictionary) -> Dictionary:
	var class_read := HFMcpProtocol.read_string(params, "entity_class", true)
	if not class_read["ok"]:
		return class_read
	var entity_class: String = class_read["value"]
	var classes := placeable_classes(root)
	if not (entity_class in classes):
		return HFMcpProtocol.invalid(
			"entity_class", "entity_class is one of: %s" % ", ".join(PackedStringArray(classes))
		)
	var spot := HFMcpProtocol.read_vec3(params, "position", true)
	if not spot["ok"]:
		return spot
	var plan := {"class": entity_class, "position": spot["value"], "rotation": null, "name": ""}
	if params.get("rotation_degrees") != null:
		var turn := HFMcpProtocol.read_vec3(params, "rotation_degrees", true)
		if not turn["ok"]:
			return turn
		plan["rotation"] = turn["value"]
	if params.get("name") != null:
		var name_read := HFMcpProtocol.read_string(params, "name", true)
		if not name_read["ok"]:
			return name_read
		plan["name"] = name_read["value"]
	var definition: Dictionary = root.get_entity_definition(entity_class)
	var data := _entity_defaults(definition)
	if params.get("preset") != null:
		var preset_read := HFMcpProtocol.read_string(params, "preset", true)
		if not preset_read["ok"]:
			return preset_read
		var presets := HFEntityPropUtils.preset_names(definition)
		if not presets.has(preset_read["value"]):
			var offered := ", ".join(presets) if not presets.is_empty() else "none"
			return HFMcpProtocol.invalid(
				"preset", "%s has these presets: %s" % [entity_class, offered]
			)
		data.merge(HFEntityPropUtils.preset_values(definition, preset_read["value"]), true)
	if params.get("properties") != null:
		var given = params["properties"]
		if not (given is Dictionary):
			return HFMcpProtocol.invalid("properties", "properties is an object of name: value")
		var types := _entity_property_types(definition)
		for key in given:
			if not types.has(str(key)):
				var known := ", ".join(PackedStringArray(types.keys()))
				return HFMcpProtocol.invalid(
					"properties", "%s has no property '%s'; it has: %s" % [entity_class, key, known]
				)
			var value := _entity_value(types[str(key)], given[key])
			if not value["ok"]:
				return HFMcpProtocol.invalid(
					"properties", "%s is a %s, not %s" % [key, types[str(key)], str(given[key])]
				)
			data[str(key)] = value["value"]
	plan["data"] = data
	return {"ok": true, "scope_ids": [], "apply": _apply_place_entity.bind(root, plan)}


func _apply_place_entity(root: Node, plan: Dictionary) -> Dictionary:
	if root.entities_node == null:
		return _fail(HFMcpProtocol.E_OPERATION_FAILED, "This level has no entities node")
	var entity := DraftEntity.new()
	var authored: String = plan["name"]
	var base := authored if authored != "" else str(plan["class"])
	entity.name = _free_child_name(root.entities_node, base.validate_node_name())
	entity.entity_type = plan["class"]
	entity.entity_class = plan["class"]
	entity.entity_data = plan["data"]
	if authored != "":
		entity.set_meta("entity_name", authored)
	root.add_entity(entity)
	var basis := Basis()
	if plan["rotation"] != null:
		var degrees: Vector3 = plan["rotation"]
		var radians := Vector3(deg_to_rad(degrees.x), deg_to_rad(degrees.y), deg_to_rad(degrees.z))
		basis = Basis.from_euler(radians, EULER_ORDER_XYZ)
	entity.global_transform = Transform3D(basis, plan["position"])
	return {"ok": true, "result": {"entity": entity_dict(root, entity)}}


## `base`, or `base_2`, `base_3` and so on: the first name no sibling has, so an
## entity is never Godot's `@light_point@412`.
static func _free_child_name(parent: Node, base: String) -> String:
	var candidate := base
	var number := 1
	while parent.has_node(NodePath(candidate)):
		number += 1
		candidate = "%s_%d" % [base, number]
	return candidate


## Every property a class declares, at its default, in the form its type takes.
static func _entity_defaults(definition: Dictionary) -> Dictionary:
	var data := {}
	for prop in definition.get("properties", []):
		if prop is Dictionary:
			var type_name := str(prop.get("type", "string"))
			data[str(prop.get("name", ""))] = HFEntityPropUtils.coerce_default(
				type_name, prop.get("default")
			)
	return data


static func _entity_property_types(definition: Dictionary) -> Dictionary:
	var types := {}
	for prop in definition.get("properties", []):
		if prop is Dictionary:
			types[str(prop.get("name", ""))] = str(prop.get("type", "string"))
	return types


## A value from the agent in the form a property of `type_name` stores, or a
## refusal: a word for a number is not quietly read as 0.
static func _entity_value(type_name: String, value) -> Dictionary:
	var number: bool = (value is int or value is float) and not (value is bool)
	match type_name:
		"float":
			if number:
				return {"ok": true, "value": float(value)}
		"int":
			if number and float(value) == floorf(float(value)):
				return {"ok": true, "value": int(value)}
		"bool":
			if value is bool:
				return {"ok": true, "value": value}
		"color":
			if value is String and Color.html_is_valid(value):
				return {"ok": true, "value": Color.html(value)}
		"vector3":
			if value is Array and (value as Array).size() == 3:
				return {"ok": true, "value": HFEntityPropUtils.coerce_default("vector3", value)}
		_:
			if value is String:
				return {"ok": true, "value": value}
	return {"ok": false}


## Every entity in the level, with what an agent can read back.
func _read_entities(root: Node, _params: Dictionary) -> Dictionary:
	var listed: Array = []
	if root.entities_node:
		for node in root.entities_node.get_children():
			if node is DraftEntity:
				listed.append(entity_dict(root, node))
	return {"ok": true, "result": {"entities": listed}}


## An entity the way the entity tools report one. `entity` is its path in the
## level, as hf_validate names one.
func entity_dict(root: Node, entity: DraftEntity) -> Dictionary:
	var properties := {}
	for key in entity.entity_data:
		properties[str(key)] = _plain(entity.entity_data[key])
	var turn := entity.global_transform.basis.get_euler(EULER_ORDER_XYZ)
	return {
		"entity": str(root.get_path_to(entity)),
		"entity_class": entity.entity_class,
		"name": str(entity.get_meta("entity_name", "")),
		"position": HFMcpProtocol.vec3_to_array(entity.global_position),
		"rotation_degrees":
		HFMcpProtocol.vec3_to_array(
			Vector3(rad_to_deg(turn.x), rad_to_deg(turn.y), rad_to_deg(turn.z))
		),
		"properties": properties,
	}


## A property value as JSON: a colour as the "#rrggbb" the tool takes, a vector as
## [x, y, z], a resource as its path.
static func _plain(value) -> Variant:
	if value is Color:
		var colour := value as Color
		return "#" + colour.to_html(colour.a < 1.0)
	if value is Vector3:
		return HFMcpProtocol.vec3_to_array(value)
	if value is Resource:
		return (value as Resource).resource_path
	return value


# ---------------------------------------------------------------------------
# hf_set_spawn
# ---------------------------------------------------------------------------


func _check_set_spawn(root: Node, params: Dictionary) -> Dictionary:
	if root.spawn_system == null:
		return _fail(HFMcpProtocol.E_OPERATION_FAILED, "This level has no spawn system")
	var spot := HFMcpProtocol.read_vec3(params, "position", true)
	if not spot["ok"]:
		return spot
	var plan := {"feet": spot["value"], "yaw": null}
	if params.get("yaw_degrees") != null:
		var yaw := HFMcpProtocol.read_number(params, "yaw_degrees", true)
		if not yaw["ok"]:
			return yaw
		plan["yaw"] = yaw["value"]
	return {"ok": true, "scope_ids": [], "apply": _apply_set_spawn.bind(root, plan)}


func _apply_set_spawn(root: Node, plan: Dictionary) -> Dictionary:
	var spawns = root.spawn_system
	var spawn: Node3D = spawns.get_active_spawn()
	var created := false
	if spawn == null:
		spawn = spawns.create_default_spawn()
		created = true
	if spawn == null:
		return _fail(HFMcpProtocol.E_OPERATION_FAILED, "HammerForge could not make a spawn")
	# The spawn's own height over the floor it stands on, the one validation and
	# the playtest read back, so a position is the floor point the feet are on.
	var height: float = spawns._get_entity_float(
		spawn, "height_offset", float(spawns.DEFAULT_SPAWN_HEIGHT_OFFSET)
	)
	var lift: float = float(spawns.FEET_OFFSET) + height
	var feet: Vector3 = plan["feet"]
	spawn.global_position = feet + Vector3(0, lift, 0)
	if plan["yaw"] != null and "entity_data" in spawn:
		spawn.entity_data["angle"] = plan["yaw"]
	var check: Dictionary = spawns.validate_spawn(spawn)
	var yaw = spawn.entity_data.get("angle", null) if "entity_data" in spawn else null
	var issues: Array = []
	for issue in check.get("issues", []):
		issues.append(str(issue))
	# Both are places for the spawn node; the answer gives them as feet, the terms
	# the tool takes, so either one passed back puts the spawn there (#1034).
	var clear = spawns.clear_place_for(spawn)
	if clear is Vector3:
		clear = (clear as Vector3) - Vector3(0, lift, 0)
	var suggested = check.get("suggested_position", null)
	if suggested is Vector3:
		suggested = (suggested as Vector3) - Vector3(0, lift, 0)
	var result := {
		"spawn":
		{
			"position": HFMcpProtocol.vec3_to_array(spawn.global_position),
			"feet": HFMcpProtocol.vec3_to_array(feet),
			"yaw_degrees": yaw,
			# Yaw 0 faces -Z, and a positive yaw turns toward -X (#1041).
			"facing": HFMcpProtocol.vec3_to_array(_facing(yaw)),
			"created": created,
		},
		"inside_brush": spawns.spawn_is_blocked(spawn),
		"clear_place": HFMcpProtocol.vec3_or_null(clear),
		"validation":
		{
			"valid": check.get("valid", false) == true,
			"issues": issues,
			"suggested_position": HFMcpProtocol.vec3_or_null(suggested),
		},
	}
	return {"ok": true, "result": result}


static func _facing(yaw) -> Vector3:
	var turn := deg_to_rad(float(yaw)) if yaw != null else 0.0
	return Vector3(-sin(turn), 0.0, -cos(turn))


# ---------------------------------------------------------------------------
# Brushes as plain data
# ---------------------------------------------------------------------------


## A brush the way every tool reports one. World space throughout.
## `palette` saves listing it again for every brush when many are listed at once.
func brush_dict(
	root: Node, brush: DraftBrush, include_faces := true, palette: Array = []
) -> Dictionary:
	var xform := brush.global_transform
	var euler := xform.basis.orthonormalized().get_euler(EULER_ORDER_XYZ)
	var degrees := Vector3(rad_to_deg(euler.x), rad_to_deg(euler.y), rad_to_deg(euler.z))
	var bounds: AABB = root.brush_system.world_bounds_of(brush)
	if palette.is_empty() and include_faces:
		palette = _palette(root)
	var faces: Array = []
	for i in brush.faces.size() if include_faces else 0:
		var face = brush.faces[i]
		if face == null:
			continue
		var centre := Vector3.ZERO
		var verts: PackedVector3Array = face.local_verts
		for vert in verts:
			centre += vert
		if not verts.is_empty():
			centre /= float(verts.size())
		var slot := int(face.material_idx)
		var material: Dictionary = palette[slot] if slot >= 0 and slot < palette.size() else {}
		var entry := {
			"index": i,
			"normal": HFMcpProtocol.vec3_to_array(face.normal_through(xform.basis)),
			"center": HFMcpProtocol.vec3_to_array(xform * centre),
			"material_id": material.get("id", null),
			"material_name": material.get("name", null),
		}
		faces.append(entry)
	var node_name := str(brush.name)
	var brush_id: Variant = null
	if brush.brush_id != "":
		brush_id = brush.brush_id
	var data := {
		"brush_id": brush_id,
		"name": "" if node_name.begins_with("@") else node_name,
		"shape": _name_by_shape.get(brush.shape, "custom"),
		"operation": "subtract" if brush.operation == CSGShape3D.OPERATION_SUBTRACTION else "union",
		"pending": brush.get_parent() == root.pending_node,
		"committed": brush.get_parent() == root.committed_node,
		"position": HFMcpProtocol.vec3_to_array(xform.origin),
		"rotation_degrees": HFMcpProtocol.vec3_to_array(degrees),
		"size": HFMcpProtocol.vec3_to_array(brush.size),
		"bounds":
		{
			"min": HFMcpProtocol.vec3_to_array(bounds.position),
			"max": HFMcpProtocol.vec3_to_array(bounds.end),
		},
		"material_id": material_id_of(brush.material_override, -1),
	}
	if include_faces:
		data["faces"] = faces
	return data


## The palette as `[{id, name}]`, one entry per slot.
func _palette(root: Node) -> Array:
	var entries: Array = []
	var materials: Array = root.get_materials()
	var names: Array = root.get_material_names()
	for slot in materials.size():
		var material: Material = materials[slot]
		var entry := {
			"id": material_id_of(material, slot),
			"name": str(names[slot]) if slot < names.size() else "",
		}
		entries.append(entry)
	return entries


## A material's id: its file path when it has its own file, else its palette
## slot. A material saved inside a scene has a path like `scene.tscn::1`, which
## names nothing an agent could pass back.
static func material_id_of(material: Material, slot: int) -> Variant:
	if material == null:
		return null
	var path := material.resource_path
	if path != "" and not path.contains("::"):
		return path
	if slot < 0:
		return null
	return "palette:%d" % slot
