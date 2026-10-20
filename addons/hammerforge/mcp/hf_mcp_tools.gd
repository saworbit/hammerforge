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
const HFBakeSystemType = preload("../systems/hf_bake_system.gd")
const HFBrushEntity = preload("../hf_brush_entity.gd")
const HFGeneratorSystem = preload("../systems/hf_generator_system.gd")
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
	# What the Scene dock and Validate call the brush, rather than Box_12 (#1086).
	var brush_name := ""
	if params.get("name") != null:
		var name_read := HFMcpProtocol.read_string(params, "name", true)
		if not name_read["ok"]:
			return name_read
		brush_name = str(name_read["value"]).strip_edges()
		if brush_name == "":
			return HFMcpProtocol.invalid("name", "name must not be blank")

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
		"name": brush_name,
	}
	if box["snapped"]:
		plan["requested"] = {
			"position": HFMcpProtocol.vec3_to_array(position_read["value"]),
			"size": HFMcpProtocol.vec3_to_array(size_read["value"]),
		}
	return {"ok": true, "scope_ids": [], "apply": _apply_place_brush.bind(root, plan)}


## Which shapes take `sides`, and from how many: a round shape below five is
## built from its default of 16 (`DraftBrush.round_sides()`), and a pyramid's base
## needs three. On a sphere, ellipsoid, capsule or torus it is the segments round.
const SIDED_SHAPES := {
	"cylinder": 5,
	"cone": 5,
	"sphere": 5,
	"ellipsoid": 5,
	"capsule": 5,
	"torus": 5,
	"pyramid": 3,
}
const MAX_SIDES := 64


func _read_sides(params: Dictionary, shape_name: String) -> Dictionary:
	if not SIDED_SHAPES.has(shape_name):
		return HFMcpProtocol.invalid(
			"sides", "sides is for a round shape or a pyramid, not a %s" % shape_name
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
	return not HFMcpProtocol.basis_from_degrees(degrees).is_equal_approx(Basis.IDENTITY)


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
	# A name a sibling already has is numbered on by Godot, as Gate2.
	if plan["name"] != "":
		info["name"] = plan["name"].validate_node_name()
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
		return _with_view({"ok": true, "bounds": box}, focus)
	if focus.has("bounds"):
		var raw = focus["bounds"]
		var low := HFMcpProtocol.read_vec3(raw if raw is Dictionary else {}, "min", true)
		var high := HFMcpProtocol.read_vec3(raw if raw is Dictionary else {}, "max", true)
		if not low["ok"] or not high["ok"]:
			return HFMcpProtocol.invalid(
				"focus", 'focus.bounds is {"min": [x, y, z], "max": [x, y, z]}'
			)
		var box := AABB(low["value"], high["value"] - low["value"]).abs()
		return _with_view({"ok": true, "bounds": box}, focus)
	return HFMcpProtocol.invalid("focus", 'focus is {"brush_ids": [...]} or {"bounds": {min, max}}')


## A focus that says where to look from carries the direction to look in, so an
## agent can see the far side of something, or into a room from above (#1040).
## Without it the shot looks the way the editor's camera does.
static func _with_view(framing: Dictionary, focus: Dictionary) -> Dictionary:
	if focus.get("look_from") == null:
		return framing
	var view := view_direction(focus["look_from"])
	if not view["ok"]:
		return view
	framing["direction"] = view["direction"]
	return framing


const VIEW_SIDES := {
	"+x": Vector3.RIGHT,
	"-x": Vector3.LEFT,
	"+y": Vector3.UP,
	"top": Vector3.UP,
	"-y": Vector3.DOWN,
	"bottom": Vector3.DOWN,
	"+z": Vector3.BACK,
	"-z": Vector3.FORWARD,
}


## `{ok, direction}`: the way a camera on side `look_from` of something looks at
## it. A side such as "+x" or "top", or a vector from the thing to the camera.
static func view_direction(look_from) -> Dictionary:
	var from := Vector3.ZERO
	if look_from is String and VIEW_SIDES.has(look_from):
		from = VIEW_SIDES[look_from]
	elif look_from is Array and (look_from as Array).size() == 3:
		var numbers := true
		for value in look_from:
			numbers = numbers and (value is int or value is float) and not (value is bool)
		if numbers:
			from = Vector3(float(look_from[0]), float(look_from[1]), float(look_from[2]))
	if from.is_zero_approx() or not from.is_finite():
		return HFMcpProtocol.invalid(
			"look_from",
			"look_from is a side (+x, -x, +y or top, -y or bottom, +z, -z) or a direction [x, y, z]"
		)
	return {"ok": true, "direction": -from.normalized()}


## An explicit camera for a shot: `{position, look_at, fov}`, such as one at the
## player's eye inside a room, which no framing of a box can give (#1040).
static func read_shot_camera(camera) -> Dictionary:
	if not (camera is Dictionary):
		return HFMcpProtocol.invalid(
			"camera", 'camera is {"position": [x, y, z], "look_at": [x, y, z]}'
		)
	var spot := HFMcpProtocol.read_vec3(camera, "position", true)
	if not spot["ok"]:
		return spot
	var target := HFMcpProtocol.read_vec3(camera, "look_at", true)
	if not target["ok"]:
		return target
	if (target["value"] - spot["value"]).length() < 0.001:
		return HFMcpProtocol.invalid("camera", "look_at has to be somewhere other than position")
	var shot := {"ok": true, "position": spot["value"], "target": target["value"], "fov": null}
	if camera.get("fov") != null:
		var fov := HFMcpProtocol.read_number(camera, "fov", true)
		if not fov["ok"]:
			return fov
		if float(fov["value"]) < 1.0 or float(fov["value"]) > 179.0:
			return HFMcpProtocol.invalid("camera", "fov is 1 to 179 degrees")
		shot["fov"] = float(fov["value"])
	return shot


## Where a brush left out of a shot is drawn: render layer 20. The editor's camera
## still sees it there, and a shot's camera is told not to, so nothing in the level
## changes, not even a brush's visibility.
const SHOT_HIDDEN_LAYERS := 1 << 19
const SHOT_CULL_MASK := (1 << 19) - 1


## The brushes `hide` names, and with `hide_cuts` every cut too, for a shot to
## leave out: an applied cut still draws as a solid red block (#1040).
func read_hidden(root: Node, params: Dictionary) -> Dictionary:
	var brushes: Array = []
	if params.get("hide") != null:
		var ids := HFMcpProtocol.read_string_array(params, "hide", true)
		if not ids["ok"]:
			return ids
		for brush_id in ids["value"]:
			var found := _read_brush(root, {"brush_id": brush_id})
			if not found["ok"]:
				return found
			brushes.append(found["brush"])
	var cuts := HFMcpProtocol.read_bool(params, "hide_cuts", false)
	if not cuts["ok"]:
		return cuts
	if cuts["value"]:
		for node in root._iter_managed_brush_nodes():
			if (
				node is DraftBrush
				and (node as DraftBrush).operation == CSGShape3D.OPERATION_SUBTRACTION
			):
				if not brushes.has(node):
					brushes.append(node)
	return {"ok": true, "brushes": brushes}


## Move everything each brush draws onto the hidden layer: its mesh, and the
## overlays a cut or a brush entity draws over it, which are internal children.
## Returns what to put back.
static func hide_from_shot(brushes: Array) -> Array:
	var saved: Array = []
	for brush in brushes:
		if not (brush is Node) or not is_instance_valid(brush):
			continue
		var drawings: Array = []
		_drawings(brush, drawings)
		for drawing: VisualInstance3D in drawings:
			saved.append([drawing, drawing.layers])
			drawing.layers = SHOT_HIDDEN_LAYERS
	return saved


## Whether the level has baked geometry a shot can show.
static func has_bake(root: Node) -> bool:
	var baked: Node = root.baked_container
	return baked != null and is_instance_valid(baked) and baked.get_child_count() > 0


## The nodes every brush lives under: drafts, pending cuts and applied cuts. Left
## out of a shot together, they leave only the baked geometry and the entities.
static func brush_containers(root: Node) -> Array:
	var containers: Array = []
	for container in [root.draft_brushes_node, root.pending_node, root.committed_node]:
		if container != null and is_instance_valid(container):
			containers.append(container)
	return containers


static func _drawings(node: Node, out: Array) -> void:
	for child in node.get_children(true):
		if child is VisualInstance3D:
			out.append(child)
		_drawings(child, out)


static func unhide(saved: Array) -> void:
	for entry in saved:
		var drawing: VisualInstance3D = entry[0]
		if is_instance_valid(drawing):
			drawing.layers = entry[1]


## Where a camera looking along `direction` has to stand to see all of `bounds`,
## filling the frame: each corner is taken into the camera's own axes and the
## camera backs off until every one is inside the picture's rectangle, with a
## little room. It used to fit a sphere around the box into the narrower field
## of view, which left a wide box in the middle third of the frame (#1040).
## `{position, target}`.
static func frame_bounds(bounds: AABB, direction: Vector3, fov: float, aspect: float) -> Dictionary:
	var centre := bounds.get_center()
	var along := direction.normalized() if not direction.is_zero_approx() else Vector3.FORWARD
	var up_hint := Vector3.UP if absf(along.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	var to_camera := Basis.looking_at(along, up_hint).inverse()
	var tan_v := tan(deg_to_rad(clampf(fov, 1.0, 179.0)) * 0.5) * 0.95
	var tan_h := tan_v * maxf(aspect, 0.01)
	var distance := 0.5
	for i in 8:
		# Camera space with the camera at the centre: x across, y up, -z ahead.
		var corner: Vector3 = to_camera * (bounds.get_endpoint(i) - centre)
		var ahead := -corner.z
		distance = maxf(distance, absf(corner.x) / tan_h - ahead)
		distance = maxf(distance, absf(corner.y) / tan_v - ahead)
		distance = maxf(distance, 0.1 - ahead)
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
## has none, since it is set on brushes, and the spawn has hf_set_spawn. door_basic
## names one and is a brush entity all the same, which the palette leaves out too:
## placed on its own it is a marker with no door to move (#1232).
func placeable_classes(root: Node) -> Array:
	var names: Array = []
	var definitions: Dictionary = root.get_entity_definitions()
	for key in definitions:
		var definition = definitions[key]
		if key == "player_start" or not (definition is Dictionary):
			continue
		if bool((definition as Dictionary).get("is_brush_entity", false)):
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
		var preset := _read_preset(entity_class, definition, params)
		if not preset["ok"]:
			return preset
		data.merge(preset["value"], true)
	if params.get("properties") != null:
		var given := _read_properties(entity_class, definition, params["properties"])
		if not given["ok"]:
			return given
		data.merge(given["value"], true)
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
		basis = HFMcpProtocol.basis_from_degrees(plan["rotation"])
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


## A preset's values, or a refusal naming the presets the class has.
static func _read_preset(
	entity_class: String, definition: Dictionary, params: Dictionary
) -> Dictionary:
	var preset_read := HFMcpProtocol.read_string(params, "preset", true)
	if not preset_read["ok"]:
		return preset_read
	var presets := HFEntityPropUtils.preset_names(definition)
	if not presets.has(preset_read["value"]):
		var offered := ", ".join(presets) if not presets.is_empty() else "none"
		return HFMcpProtocol.invalid("preset", "%s has these presets: %s" % [entity_class, offered])
	return {"ok": true, "value": HFEntityPropUtils.preset_values(definition, preset_read["value"])}


## The agent's properties in the forms their types store, or a refusal: a name the
## class does not declare, or a value of the wrong type.
static func _read_properties(entity_class: String, definition: Dictionary, given) -> Dictionary:
	if not (given is Dictionary):
		return HFMcpProtocol.invalid("properties", "properties is an object of name: value")
	var types := _entity_property_types(definition)
	var values := {}
	for key in given:
		if not types.has(str(key)):
			var known: String = ", ".join(PackedStringArray(types.keys()))
			if types.is_empty():
				known = "none"
			return HFMcpProtocol.invalid(
				"properties", "%s has no property '%s'; it has: %s" % [entity_class, key, known]
			)
		var value := _entity_value(types[str(key)], given[key])
		if not value["ok"]:
			return HFMcpProtocol.invalid(
				"properties", "%s is a %s, not %s" % [key, types[str(key)], str(given[key])]
			)
		values[str(key)] = value["value"]
	return {"ok": true, "value": values}


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
	var degrees := HFMcpProtocol.degrees_from_basis(entity.global_transform.basis)
	return {
		"entity": str(root.get_path_to(entity)),
		"entity_class": entity.entity_class,
		"name": str(entity.get_meta("entity_name", "")),
		"position": HFMcpProtocol.vec3_to_array(entity.global_position),
		"rotation_degrees": HFMcpProtocol.vec3_to_array(degrees),
		"properties": properties,
		"outputs": outputs_of(root, entity),
		"prefab": prefab_of(root, entity),
	}


## An entity's wiring, in the words hf_add_entity_output takes.
func outputs_of(root: Node, entity: Node) -> Array:
	var listed: Array = []
	for connection in root.get_entity_outputs(entity):
		if connection is Dictionary:
			(
				listed
				. append(
					{
						"output_name": str(connection.get("output_name", "")),
						"target_name": str(connection.get("target_name", "")),
						"input_name": str(connection.get("input_name", "")),
						"parameter": str(connection.get("parameter", "")),
						"delay": float(connection.get("delay", 0.0)),
						"fire_once": bool(connection.get("fire_once", false)),
					}
				)
			)
	return listed


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
# hf_transform_entity, hf_set_entity_properties, hf_delete_entity,
# hf_add_entity_output, hf_remove_entity_output, hf_set_brush_entity
# ---------------------------------------------------------------------------


## The entity an `entity` path names, as hf_get_entities gives it. The spawn is
## left to hf_set_spawn, which keeps the player out of the walls (#1082).
func _read_entity(root: Node, params: Dictionary) -> Dictionary:
	var path_read := HFMcpProtocol.read_string(params, "entity", true)
	if not path_read["ok"]:
		return path_read
	var path: String = path_read["value"]
	var node: Node = null
	if root.entities_node and path != "":
		node = root.get_node_or_null(NodePath(path))
	# Only a child of the level's own entities: a path is free text, and "..",
	# or a brush's path, names something these tools do not edit.
	if not (node is DraftEntity) or node.get_parent() != root.entities_node:
		return _fail(
			HFMcpProtocol.E_ENTITY_NOT_FOUND,
			"No entity at '%s'; hf_get_entities lists each one's path" % path,
			{"entity": path}
		)
	if (node as DraftEntity).entity_class == "player_start":
		return HFMcpProtocol.invalid("entity", "the spawn is moved with hf_set_spawn")
	return {"ok": true, "entity": node}


func _check_transform_entity(root: Node, params: Dictionary) -> Dictionary:
	var found := _read_entity(root, params)
	if not found["ok"]:
		return found
	var plan := {"path": str(params["entity"]), "position": null, "rotation": null}
	if params.get("position") != null:
		var spot := HFMcpProtocol.read_vec3(params, "position", true)
		if not spot["ok"]:
			return spot
		plan["position"] = spot["value"]
	if params.get("rotation_degrees") != null:
		var turn := HFMcpProtocol.read_vec3(params, "rotation_degrees", true)
		if not turn["ok"]:
			return turn
		plan["rotation"] = turn["value"]
	if plan["position"] == null and plan["rotation"] == null:
		return HFMcpProtocol.invalid("position", "give position, rotation_degrees, or both")
	return {"ok": true, "scope_ids": [], "apply": _apply_transform_entity.bind(root, plan)}


func _apply_transform_entity(root: Node, plan: Dictionary) -> Dictionary:
	var entity := root.get_node_or_null(NodePath(plan["path"])) as DraftEntity
	if entity == null:
		return _fail(HFMcpProtocol.E_OPERATION_FAILED, "Entity '%s' went missing" % plan["path"])
	var xform := entity.global_transform
	if plan["rotation"] != null:
		# Turned, and kept at the size it has: a whole new basis set a scaled prop
		# back to one.
		var size := xform.basis.get_scale()
		xform.basis = HFMcpProtocol.basis_from_degrees(plan["rotation"]) * Basis.from_scale(size)
	if plan["position"] != null:
		xform.origin = plan["position"]
	entity.global_transform = xform
	return {"ok": true, "result": {"entity": entity_dict(root, entity)}}


## Properties checked as hf_place_entity checks them, and a preset applied
## first, so retuning a light takes the same words as placing one. The entity is
## a point entity's path or a brush entity's brush_id, as the wiring tools take
## it (#1105). A brush entity's go on every brush of that entity, so the two
## leaves of a door have one speed in the bake and in the `.map`.
func _check_set_entity_properties(root: Node, params: Dictionary) -> Dictionary:
	var found := _read_io_source(root, params)
	if not found["ok"]:
		return found
	var source: Node = found["node"]
	var entity_class := _io_class(source)
	var definition: Dictionary = root.get_entity_definition(entity_class)
	var values := {}
	if params.get("preset") != null:
		var preset := _read_preset(entity_class, definition, params)
		if not preset["ok"]:
			return preset
		values.merge(preset["value"], true)
	if params.get("properties") != null:
		var given := _read_properties(entity_class, definition, params["properties"])
		if not given["ok"]:
			return given
		values.merge(given["value"], true)
	if values.is_empty():
		return HFMcpProtocol.invalid("properties", "give properties, a preset, or both")
	var plan := {"key": found["key"], "value": found["value"], "values": values, "brush_ids": []}
	if source is DraftBrush:
		for node in root.entity_property_nodes(source):
			plan["brush_ids"].append((node as DraftBrush).brush_id)
	return {
		"ok": true,
		"scope_ids": plan["brush_ids"],
		"apply": _apply_set_entity_properties.bind(root, plan),
	}


func _apply_set_entity_properties(root: Node, plan: Dictionary) -> Dictionary:
	var source := _io_source_of(root, plan)
	if source == null:
		return _fail(HFMcpProtocol.E_OPERATION_FAILED, "'%s' went missing" % plan["value"])
	# On every brush of a brush entity, as `set_entity_properties()` does it.
	root.set_entity_properties(source, plan["values"])
	return {"ok": true, "result": _io_answer(root, source)}


func _check_delete_entity(root: Node, params: Dictionary) -> Dictionary:
	var found := _read_entity(root, params)
	if not found["ok"]:
		return found
	# The whole level: deleting an entity also takes the wires aimed at it out of
	# other entities, which a scope on the one entity would not put back.
	var path := str(params["entity"])
	return {"ok": true, "scope_ids": [], "apply": _apply_delete_entity.bind(root, path)}


func _apply_delete_entity(root: Node, path: String) -> Dictionary:
	root.delete_entities_by_paths([path])
	if root.get_node_or_null(NodePath(path)) != null:
		return _fail(HFMcpProtocol.E_OPERATION_FAILED, "Entity '%s' could not be deleted" % path)
	return {"ok": true, "result": {"deleted": path}}


## The source of a wire: the point entity `entity` names, or the brush entity
## `brush_id` names, and never both (#1098). `{ok, node, key, value}`, where
## `key` and `value` find it again when the change runs.
func _read_io_source(root: Node, params: Dictionary) -> Dictionary:
	var by_entity: bool = params.get("entity") != null
	if by_entity == (params.get("brush_id") != null):
		return HFMcpProtocol.invalid(
			"entity", "give entity, a point entity's path, or brush_id, a brush entity's, not both"
		)
	if by_entity:
		var found := _read_entity(root, params)
		if not found["ok"]:
			return found
		var path := str(params["entity"])
		return {"ok": true, "node": found["entity"], "key": "entity", "value": path}
	var read := _read_brush(root, params)
	if not read["ok"]:
		return read
	var brush: DraftBrush = read["brush"]
	if _io_class(brush) == "":
		var why := "Brush '%s' is not an entity; hf_set_brush_entity makes it a trigger or a door"
		return HFMcpProtocol.invalid("brush_id", why % brush.brush_id)
	return {"ok": true, "node": brush, "key": "brush_id", "value": brush.brush_id}


## The source a plan names, looked up again, or null.
func _io_source_of(root: Node, plan: Dictionary) -> Node:
	if plan["key"] == "entity":
		return root.get_node_or_null(NodePath(plan["value"])) as DraftEntity
	return root.find_brush_by_id(plan["value"]) as DraftBrush


## A wire's source as the tools report it: an entity, or a brush.
func _io_answer(root: Node, source: Node) -> Dictionary:
	if source is DraftEntity:
		return {"entity": entity_dict(root, source)}
	return {"brush": brush_dict(root, source, false)}


## A wire from this entity's output to every node that answers to `target_name`
## (#1083). The panel's form is free text on purpose; an agent's is checked, so
## a misspelt output is refused rather than wired to nothing. A target that is
## not there yet is allowed, as the panel allows it, and hf_validate reports it.
func _check_add_entity_output(root: Node, params: Dictionary) -> Dictionary:
	var found := _read_io_source(root, params)
	if not found["ok"]:
		return found
	var source_class := _io_class(found["node"])
	var texts := {}
	for key in ["output_name", "target_name", "input_name"]:
		var read := HFMcpProtocol.read_string(params, key, true)
		if not read["ok"]:
			return read
		texts[key] = str(read["value"]).strip_edges()
		if texts[key] == "":
			return HFMcpProtocol.invalid(key, "%s must not be blank" % key)
	var outputs := _declared(root, source_class, "outputs")
	if not outputs.has(texts["output_name"]):
		return HFMcpProtocol.invalid("output_name", _offer(source_class, "outputs", outputs))
	for target in root.find_entities_by_name(texts["target_name"]):
		var target_class := _io_class(target)
		var inputs := _declared(root, target_class, "inputs")
		if not inputs.has(texts["input_name"]):
			return HFMcpProtocol.invalid("input_name", _offer(target_class, "inputs", inputs))
	var parameter := HFMcpProtocol.read_string(params, "parameter", false, "")
	if not parameter["ok"]:
		return parameter
	var delay := HFMcpProtocol.read_number(params, "delay", false, 0.0)
	if not delay["ok"]:
		return delay
	if float(delay["value"]) < 0.0:
		return HFMcpProtocol.invalid("delay", "delay is zero or more seconds")
	var once := HFMcpProtocol.read_bool(params, "fire_once", false)
	if not once["ok"]:
		return once
	var plan := {
		"key": found["key"],
		"value": found["value"],
		"output_name": texts["output_name"],
		"target_name": texts["target_name"],
		"input_name": texts["input_name"],
		"parameter": parameter["value"],
		"delay": float(delay["value"]),
		"fire_once": once["value"],
	}
	return {"ok": true, "scope_ids": [], "apply": _apply_add_entity_output.bind(root, plan)}


func _apply_add_entity_output(root: Node, plan: Dictionary) -> Dictionary:
	var source := _io_source_of(root, plan)
	if source == null:
		return _fail(HFMcpProtocol.E_OPERATION_FAILED, "'%s' went missing" % plan["value"])
	var before: int = root.get_entity_outputs(source).size()
	root.add_entity_output(
		source,
		plan["output_name"],
		plan["target_name"],
		plan["input_name"],
		plan["parameter"],
		plan["delay"],
		plan["fire_once"]
	)
	# add_entity_output() warns and returns on a wire it will not keep.
	if root.get_entity_outputs(source).size() != before + 1:
		return _fail(HFMcpProtocol.E_OPERATION_FAILED, "HammerForge did not keep the wire")
	return {"ok": true, "result": _io_answer(root, source)}


## Take a wire back by its place in the source's outputs, as hf_get_entities and
## hf_get_brushes list them (#1096).
func _check_remove_entity_output(root: Node, params: Dictionary) -> Dictionary:
	var found := _read_io_source(root, params)
	if not found["ok"]:
		return found
	var count: int = root.get_entity_outputs(found["node"]).size()
	if count == 0:
		return HFMcpProtocol.invalid("index", "%s has no outputs" % found["value"])
	var index := HFMcpProtocol.read_int(params, "index", true, 0, 0, count - 1)
	if not index["ok"] and params.get("index") != null:
		var has := "1 output" if count == 1 else "%d outputs" % count
		index = HFMcpProtocol.invalid(
			"index",
			"%s has %s, so index is a whole number from 0 to %d" % [found["value"], has, count - 1]
		)
	if not index["ok"]:
		return index
	var plan := {"key": found["key"], "value": found["value"], "index": index["value"]}
	return {"ok": true, "scope_ids": [], "apply": _apply_remove_entity_output.bind(root, plan)}


func _apply_remove_entity_output(root: Node, plan: Dictionary) -> Dictionary:
	var source := _io_source_of(root, plan)
	if source == null:
		return _fail(HFMcpProtocol.E_OPERATION_FAILED, "'%s' went missing" % plan["value"])
	var before: int = root.get_entity_outputs(source).size()
	root.remove_entity_output(source, plan["index"])
	if root.get_entity_outputs(source).size() != before - 1:
		return _fail(HFMcpProtocol.E_OPERATION_FAILED, "HammerForge did not remove the wire")
	return {"ok": true, "result": _io_answer(root, source)}


## The classes hf_set_brush_entity makes a brush: those the definitions mark as
## brush entities, such as trigger_once, func_door and func_button.
func brush_classes(root: Node) -> Array:
	var names: Array = []
	var definitions: Dictionary = root.get_entity_definitions()
	for key in definitions:
		var definition = definitions[key]
		if definition is Dictionary and bool(definition.get("is_brush_entity", false)):
			names.append(str(key))
	names.sort()
	return names


## The entity_class that unties brushes, as the dock's Untie does (#1105).
const UNTIE := "none"


## Make brushes a trigger, a door, a button or a wall, as the dock's Tie to
## Entity does, named for wiring to aim at (#1098). The brushes given are one
## tie and so one entity, as a selection tied in the dock is: a two leaf door is
## one call (#1105). With no name they keep the one they have, so a trigger_once
## made a trigger_multiple still answers to its wires. An entity_class of "none"
## unties them.
func _check_set_brush_entity(root: Node, params: Dictionary) -> Dictionary:
	var found := _read_tie_brushes(root, params)
	if not found["ok"]:
		return found
	var ids: Array = found["brush_ids"]
	var class_read := HFMcpProtocol.read_string(params, "entity_class", true)
	if not class_read["ok"]:
		return class_read
	var entity_class := str(class_read["value"]).strip_edges()
	if entity_class == UNTIE:
		return _check_untie(root, params, found)
	var classes := brush_classes(root)
	if not classes.has(entity_class):
		return HFMcpProtocol.invalid(
			"entity_class",
			(
				"'%s' is not a brush entity class. These are: %s; none unties the brushes"
				% [entity_class, ", ".join(PackedStringArray(classes))]
			)
		)
	var name_read := HFMcpProtocol.read_string(params, "name", false, "")
	if not name_read["ok"]:
		return name_read
	var entity_name := str(name_read["value"]).strip_edges()
	if params.get("name") != null and entity_name == "":
		return HFMcpProtocol.invalid("name", "name must not be blank")
	if entity_name == "":
		# One tie is one name, so brushes that answer to two need to be told which.
		var names := {}
		for brush in found["brushes"]:
			var had := str(brush.get_meta("entity_name", ""))
			if had != "":
				names[had] = true
		if names.size() > 1:
			var listed := ", ".join(PackedStringArray(names.keys()))
			return HFMcpProtocol.invalid(
				"name", "These brushes answer to different names (%s); give the one name" % listed
			)
		if names.size() == 1:
			entity_name = str(names.keys()[0])
	var plan := {"brush_ids": ids, "entity_class": entity_class, "name": entity_name}
	return {"ok": true, "scope_ids": ids, "apply": _apply_set_brush_entity.bind(root, plan)}


## Untie: every brush has to be an entity, so a mistyped id is not a quiet no-op.
func _check_untie(root: Node, params: Dictionary, found: Dictionary) -> Dictionary:
	if params.get("name") != null:
		return HFMcpProtocol.invalid("name", "name is for a tie; entity_class none unties")
	for brush in found["brushes"]:
		if _io_class(brush) == "":
			return HFMcpProtocol.invalid(
				"brush_ids",
				"Brush '%s' is not an entity, so there is nothing to untie" % brush.brush_id
			)
	var ids: Array = found["brush_ids"]
	var plan := {"brush_ids": ids, "entity_class": "", "name": ""}
	return {"ok": true, "scope_ids": ids, "apply": _apply_set_brush_entity.bind(root, plan)}


## The brushes `brush_ids` names for a tie: one or more, each once, and none a cut.
func _read_tie_brushes(root: Node, params: Dictionary) -> Dictionary:
	var ids_read := HFMcpProtocol.read_string_array(params, "brush_ids", true)
	if not ids_read["ok"]:
		return ids_read
	var ids: Array = (ids_read["value"] as Array).duplicate()
	if ids.is_empty():
		return HFMcpProtocol.invalid("brush_ids", "brush_ids lists one brush or more")
	var brushes: Array = []
	var seen := {}
	for brush_id in ids:
		if brush_id == "":
			return HFMcpProtocol.invalid("brush_ids", "brush_ids must not hold an empty id")
		if seen.has(brush_id):
			return HFMcpProtocol.invalid("brush_ids", "Brush '%s' is listed twice" % brush_id)
		seen[brush_id] = true
		var found := _read_brush(root, {"brush_id": brush_id})
		if not found["ok"]:
			return found
		var brush: DraftBrush = found["brush"]
		if brush.operation == CSGShape3D.OPERATION_SUBTRACTION:
			return HFMcpProtocol.invalid(
				"brush_ids", "Brush '%s' is a cut, and only a solid brush is an entity" % brush_id
			)
		brushes.append(brush)
	return {"ok": true, "brush_ids": ids, "brushes": brushes}


func _apply_set_brush_entity(root: Node, plan: Dictionary) -> Dictionary:
	var entity_class: String = plan["entity_class"]
	if entity_class == "":
		root.untie_brushes_from_entity(plan["brush_ids"])
	else:
		root.tie_brushes_to_entity(plan["brush_ids"], entity_class, plan["name"])
	var listed: Array = []
	for brush_id in plan["brush_ids"]:
		var brush := root.find_brush_by_id(brush_id) as DraftBrush
		if brush == null or _io_class(brush) != entity_class:
			var what := "untie" if entity_class == "" else "tie"
			return _fail(
				HFMcpProtocol.E_OPERATION_FAILED,
				"HammerForge did not %s brush '%s'" % [what, brush_id]
			)
		listed.append(brush_dict(root, brush, false))
	return {"ok": true, "result": {"brushes": listed}}


## The output or input names a class's definition declares.
func _declared(root: Node, entity_class: String, key: String) -> Array:
	var names = root.get_entity_definition(entity_class).get(key, [])
	return names if names is Array else []


## The class a wire's target answers as: a point entity's own, or a brush
## entity's (a door or a button made from brushes).
static func _io_class(node: Node) -> String:
	if node is DraftEntity:
		return (node as DraftEntity).entity_class
	return str(node.get_meta("brush_entity_class", ""))


static func _offer(entity_class: String, key: String, names: Array) -> String:
	if names.is_empty():
		return "%s has no %s" % [entity_class, key]
	return "%s has these %s: %s" % [entity_class, key, ", ".join(PackedStringArray(names))]


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
# Cordons: hf_get_cordons, hf_set_cordon, hf_remove_cordon
# ---------------------------------------------------------------------------


func _read_cordons(root: Node, _params: Dictionary) -> Dictionary:
	return {"ok": true, "result": cordons_dict(root)}


## The cordons the way every cordon tool reports them, in the dock's order, the
## order `index` counts in. `partial_bake` is whether the dock's Bake takes only
## the brushes that touch a cordon: cordons on, and one of them switched on.
## `hf_bake` takes them only when asked for `cordons: true`.
static func cordons_dict(root: Node) -> Dictionary:
	var listed: Array = []
	var regions: Array = root.get_all_cordon_regions()
	for i in regions.size():
		listed.append(_cordon_dict(root, regions, i))
	var enabled := bool(root.cordon_enabled)
	return {
		"enabled": enabled,
		"partial_bake": enabled and not root.get_cordon_regions().is_empty(),
		"cordons": listed,
	}


static func _cordon_dict(root: Node, regions: Array, index: int) -> Dictionary:
	# Every way a cordon is stored turns its box the right way out first.
	var box: AABB = regions[index]
	return {
		"index": index,
		"name": root.get_cordon_name(index),
		"min": HFMcpProtocol.vec3_to_array(box.position),
		"max": HFMcpProtocol.vec3_to_array(box.end),
		"active": root.is_cordon_active(index),
	}


## `index` as a cordon the level holds, from 0 to `count` - 1, or a refusal that
## says which ones there are.
static func _read_cordon_index(params: Dictionary, count: int, hint := "") -> Dictionary:
	var read := HFMcpProtocol.read_int(params, "index", true, 0, 0, count - 1)
	if read["ok"]:
		return read
	var message := "index is a cordon from 0 to %d; hf_get_cordons lists them" % (count - 1)
	return HFMcpProtocol.invalid("index", message + hint)


## Where `hf_set_cordon` puts a cordon: round brushes, at a box, or nowhere new.
## `{ok, kind: "brushes" | "bounds" | "", nodes, box}` or a refusal.
func _read_cordon_place(root: Node, params: Dictionary) -> Dictionary:
	var has_ids: bool = params.get("brush_ids") != null
	var has_bounds: bool = params.get("bounds") != null
	if has_ids and has_bounds:
		return HFMcpProtocol.invalid("bounds", "Give brush_ids or bounds, not both")
	if has_ids:
		var ids_read := HFMcpProtocol.read_string_array(params, "brush_ids", true)
		if not ids_read["ok"]:
			return ids_read
		if (ids_read["value"] as Array).is_empty():
			return HFMcpProtocol.invalid("brush_ids", "brush_ids lists one brush or more")
		var nodes: Array = []
		for brush_id in ids_read["value"]:
			if brush_id == "":
				return HFMcpProtocol.invalid("brush_ids", "brush_ids must not hold an empty id")
			var found := _read_brush(root, {"brush_id": brush_id})
			if not found["ok"]:
				return found
			nodes.append(found["brush"])
		return {"ok": true, "kind": "brushes", "nodes": nodes}
	if has_bounds:
		var raw = params["bounds"]
		var low := HFMcpProtocol.read_vec3(raw if raw is Dictionary else {}, "min", true)
		var high := HFMcpProtocol.read_vec3(raw if raw is Dictionary else {}, "max", true)
		if not low["ok"] or not high["ok"]:
			return HFMcpProtocol.invalid("bounds", 'bounds is {"min": [x, y, z], "max": [x, y, z]}')
		var box := AABB(low["value"], high["value"] - low["value"]).abs()
		# The level keeps any finite box. A flat one takes only what crosses its
		# plane, which an agent giving the same height twice never means.
		if box.size.x <= 0.0 or box.size.y <= 0.0 or box.size.z <= 0.0:
			return HFMcpProtocol.invalid(
				"bounds", "A cordon is a box: bounds needs some size on every axis"
			)
		return {"ok": true, "kind": "bounds", "box": box}
	return {"ok": true, "kind": ""}


## Add a cordon, or change cordon `index`: its place, name and switch, and the
## switch for every cordon. Without `index`, a place adds one; with neither, only
## `enabled` means anything.
func _check_set_cordon(root: Node, params: Dictionary) -> Dictionary:
	var count: int = root.get_all_cordon_regions().size()
	var place := _read_cordon_place(root, params)
	if not place["ok"]:
		return place
	var index := -1
	if params.get("index") != null:
		var index_read := _read_cordon_index(params, count, "; leave it out to add one")
		if not index_read["ok"]:
			return index_read
		index = index_read["value"]
	elif place["kind"] != "":
		# One past the last, which is how the level is asked to add one.
		index = count
	var plan := {
		"index": index,
		"adding": index == count,
		"place": place,
		"name": null,
		"active": null,
		"enabled": null,
	}
	if params.get("name") != null:
		var name_read := HFMcpProtocol.read_string(params, "name", true)
		if not name_read["ok"]:
			return name_read
		plan["name"] = name_read["value"]
	for key in ["active", "enabled"]:
		if params.get(key) != null:
			var switch_read := HFMcpProtocol.read_bool(params, key, false)
			if not switch_read["ok"]:
				return switch_read
			plan[key] = switch_read["value"]
	var for_one: bool = place["kind"] != "" or plan["name"] != null or plan["active"] != null
	if index < 0 and for_one:
		return (
			HFMcpProtocol
			. invalid(
				"index",
				"name and active belong to one cordon: give its index, or brush_ids or bounds to add one"
			)
		)
	if not for_one and plan["enabled"] == null:
		return HFMcpProtocol.invalid(
			"index",
			"hf_set_cordon needs something to change: brush_ids or bounds, name, active or enabled"
		)
	return {"ok": true, "scope_ids": [], "apply": _apply_set_cordon.bind(root, plan)}


func _apply_set_cordon(root: Node, plan: Dictionary) -> Dictionary:
	var index: int = plan["index"]
	var place: Dictionary = plan["place"]
	var placed := false
	match str(place["kind"]):
		"brushes":
			# The dock's Set and Add from Selection: the box round them, grown by a
			# unit, and the cordon and cordons as a whole switched on.
			placed = root.set_cordon_from_selection(place["nodes"], index)
		"bounds":
			placed = root.set_cordon_region(index, place["box"])
			if placed:
				root.set_cordon_active(index, true)
				root.set_cordons_enabled(true)
		_:
			placed = true
	if not placed:
		return _fail(HFMcpProtocol.E_OPERATION_FAILED, "HammerForge could not place the cordon")
	if plan["name"] != null:
		root.set_cordon_name(index, plan["name"])
	if plan["active"] != null:
		root.set_cordon_active(index, plan["active"])
	if plan["enabled"] != null:
		root.set_cordons_enabled(plan["enabled"])
	# The dock reads the cordons only when told. Left showing the old ones, its
	# next spin nudge writes them all back over this (#968).
	root.settings_applied.emit()
	var answer := cordons_dict(root)
	answer["cordon"] = answer["cordons"][index] if index >= 0 else null
	answer["added"] = plan["adding"]
	return {"ok": true, "result": answer}


func _check_remove_cordon(root: Node, params: Dictionary) -> Dictionary:
	var count: int = root.get_all_cordon_regions().size()
	var index_read := _read_cordon_index(params, count)
	if not index_read["ok"]:
		return index_read
	if count <= 1:
		return _fail(
			HFMcpProtocol.E_OPERATION_FAILED,
			(
				"The level always keeps one cordon. Switch it off instead: hf_set_cordon "
				+ "with index 0 and active false, or enabled false for every cordon."
			),
			{"index": 0}
		)
	return {
		"ok": true, "scope_ids": [], "apply": _apply_remove_cordon.bind(root, index_read["value"])
	}


func _apply_remove_cordon(root: Node, index: int) -> Dictionary:
	var gone := _cordon_dict(root, root.get_all_cordon_regions(), index)
	if not root.remove_cordon_region(index):
		return _fail(HFMcpProtocol.E_OPERATION_FAILED, "HammerForge could not remove the cordon")
	root.settings_applied.emit()
	var answer := cordons_dict(root)
	answer["removed"] = gone
	return {"ok": true, "result": answer}


# ---------------------------------------------------------------------------
# Brushes as plain data
# ---------------------------------------------------------------------------


## A brush the way every tool reports one. World space throughout.
## `palette` saves listing it again for every brush when many are listed at once.
func brush_dict(
	root: Node, brush: DraftBrush, include_faces := true, palette: Array = []
) -> Dictionary:
	var xform := brush.global_transform
	var degrees := HFMcpProtocol.degrees_from_basis(xform.basis)
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
		"brush_entity": _brush_entity_dict(root, brush),
		"prefab": prefab_of(root, brush),
		"structure": structure_of(root, brush),
	}
	if include_faces:
		data["faces"] = faces
	return data


## The placed prefab a brush or entity is a piece of, or null: the copy's id, the
## prefab file, its variant and whether it is linked to the file. Name any piece
## to `hf_run_command` with cycle_variant or propagate_prefab.
func prefab_of(root: Node, node: Node) -> Variant:
	if root.prefab_system == null:
		return null
	var record = root.prefab_system.instance_of(node)
	if record == null:
		return null
	return {
		"instance_id": str(record.instance_id),
		"source": str(record.source_path),
		"variant": str(record.variant_name),
		"linked": bool(record.linked),
	}


## The structure a brush is a piece of, or null: its generator_id, its type, the
## piece's place in it from 0, and its settings. Name the generator_id to
## hf_run_command with update_structure or detach_structure. Read through the
## record, which says what a structure is made of; the tag on the brush only
## points at it.
func structure_of(root: Node, brush: DraftBrush) -> Variant:
	var generator_id := str(brush.get_meta(HFGeneratorSystem.GENERATOR_META, ""))
	if generator_id == "" or brush.brush_id == "":
		return null
	var record = root.generator_for_id(generator_id)
	if record == null:
		return null
	var piece: int = record.brush_ids.find(brush.brush_id)
	if piece < 0:
		return null
	return {
		"generator_id": generator_id,
		"type": str(record.type),
		"piece": piece,
		"settings": (record.settings as Dictionary).duplicate(true),
	}


## What a brush is as an entity, or null for plain geometry: its class, the name
## wiring aims at, its properties and its own wires, as hf_set_brush_entity,
## hf_set_entity_properties and hf_add_entity_output take them (#1098, #1105).
func _brush_entity_dict(root: Node, brush: DraftBrush) -> Variant:
	var entity_class := _io_class(brush)
	if entity_class == "":
		return null
	return {
		"entity_class": entity_class,
		"name": HFBakeSystemType.authored_entity_name(brush),
		"properties": _brush_entity_properties(root, brush, entity_class),
		"outputs": outputs_of(root, brush),
	}


## A brush entity's properties as the bake reads them, by the one rule both use:
## the class's defaults, with what was set on the brush over them.
func _brush_entity_properties(root: Node, brush: DraftBrush, entity_class: String) -> Dictionary:
	var values := HFBrushEntity.properties(root.get_entity_definition(entity_class), brush)
	var properties := {}
	for key in values:
		properties[str(key)] = _plain(values[key])
	return properties


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
