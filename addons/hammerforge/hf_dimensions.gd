@tool
extends RefCounted
## Dimensions that stay in the level and follow the brushes they measure (#1699).
##
## A dimension is a `dimension` entity, editor only as a note is: it saves with
## the level, sits in visgroups and never reaches a bake. Its two ends are kept in
## its `entity_data` as what they are attached to, a brush's vertex, an edge's
## middle or a face's centre, held by where that is in the brush's own space, or
## a point of its own, and are worked out from that whenever they are read. So a
## dimension follows a brush through a move, a turn and an undo with no step of
## its own. An end whose brush has gone, or whose corner a Clip or a resize has
## moved off that place, is detached: it reads where it was last seen.

# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const DraftEntity = preload("draft_entity.gd")
const DraftBrush = preload("brush_instance.gd")
const HFPlayerMetrics = preload("hf_player_metrics.gd")
@warning_ignore_restore("shadowed_global_identifier")

const CLASS := "dimension"
## The ends in `entity_data`.
const END_A := "end_a"
const END_B := "end_b"
## What a dimension can be held to, as its `check` property says.
const CHECKS := [
	"None",
	"At least player width",
	"At least player height",
	"At most jump height",
	"At most step height",
	"At least",
	"At most",
]
## How near a point must be to a vertex, an edge's middle or a face's centre to
## be attached to it.
const ATTACH_REACH := 0.001
## Where a detached end was last seen, by entity, for the session.
const LAST_SEEN_META := &"_hf_dimension_last_seen"


static func is_dimension(node: Variant) -> bool:
	return node is DraftEntity and (node as DraftEntity).entity_type == CLASS


## Every dimension in the level.
static func dimensions(root: Node) -> Array:
	var out: Array = []
	var holder = root.get("entities_node") if root else null
	if holder == null:
		return out
	for child in holder.get_children():
		if is_dimension(child):
			out.append(child)
	return out


# ---------------------------------------------------------------------------
# Ends
# ---------------------------------------------------------------------------


## What `point` (world) is on: the vertex, the edge's middle or the face's centre
## of a brush within ATTACH_REACH, nearest first in that order, held as
## `{brush_id, kind, local}` with `local` where it is in the brush's own space; or
## a point of its own in the space of `space`, the dimension's transform.
static func attach(root: Node, point: Vector3, space: Transform3D) -> Dictionary:
	var best := {}
	var best_rank := 99
	for brush in root._iter_managed_brush_nodes():
		if not (brush is DraftBrush) or str(brush.brush_id) == "":
			continue
		var xform: Transform3D = (brush as Node3D).global_transform
		for feature in _features(brush):
			var rank := int(RANKS[feature[0]])
			if (
				rank < best_rank
				and (xform * (feature[1] as Vector3)).distance_to(point) <= ATTACH_REACH
			):
				best = {
					"brush_id": str(brush.brush_id), "kind": feature[0], "local": _array(feature[1])
				}
				best_rank = rank
		if best_rank == 0:
			break
	if not best.is_empty():
		return best
	return {"point": _array(space.affine_inverse() * point)}


## The order an end is attached in when two lie on the point.
const RANKS := {"vertex": 0, "edge": 1, "face": 2}


## Every vertex, edge middle and face centre of `brush`, as `[kind, local]`.
static func _features(brush: Node) -> Array:
	var out: Array = []
	for face in brush.faces:
		if face == null:
			continue
		var verts: PackedVector3Array = face.local_verts
		if verts.is_empty():
			continue
		var middle := Vector3.ZERO
		for c in verts.size():
			middle += verts[c]
			out.append(["vertex", verts[c]])
			out.append(["edge", (verts[c] + verts[(c + 1) % verts.size()]) * 0.5])
		out.append(["face", middle / verts.size()])
	return out


static func _array(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


static func _vector(value: Variant) -> Variant:
	if value is Array and (value as Array).size() == 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return null


## Where `end` is now in world space, `{point, attached}`: `attached` false, and
## `point` null, when its brush has gone or no longer has that kind of feature at
## that place.
static func resolve(root: Node, end: Dictionary, holder: Node3D) -> Dictionary:
	if end.has("point"):
		var own = _vector(end["point"])
		if own is Vector3:
			return {"point": holder.global_transform * own if holder else own, "attached": true}
		return {"point": null, "attached": false}
	var brush = root.find_brush_by_id(str(end.get("brush_id", ""))) if root else null
	var local = _vector(end.get("local"))
	if not (brush is DraftBrush) or not is_instance_valid(brush) or not (local is Vector3):
		return {"point": null, "attached": false}
	var kind := str(end.get("kind", "vertex"))
	for feature in _features(brush):
		if feature[0] == kind and (feature[1] as Vector3).distance_to(local) <= ATTACH_REACH:
			return {
				"point": (brush as Node3D).global_transform * (local as Vector3), "attached": true
			}
	return {"point": null, "attached": false}


## A dimension now: `{a, b, length, detached, check, needs, passes}`. A detached
## end reads where it was last seen; `passes` is false when the check fails.
static func measure(root: Node, dimension: Node) -> Dictionary:
	var data: Dictionary = dimension.get("entity_data")
	var holder := dimension as Node3D
	var seen: Dictionary = dimension.get_meta(LAST_SEEN_META, {})
	var ends := {}
	var detached := false
	for key in [END_A, END_B]:
		var end = data.get(key)
		var where := resolve(root, end if end is Dictionary else {}, holder)
		if where["point"] is Vector3:
			seen[key] = where["point"]
			ends[key] = where["point"]
		else:
			detached = true
			ends[key] = seen.get(key, holder.global_position if holder else Vector3.ZERO)
	dimension.set_meta(LAST_SEEN_META, seen)
	var length: float = (ends[END_A] as Vector3).distance_to(ends[END_B])
	var check := str(data.get("check", "None"))
	var needs := needed(check, float(data.get("value", 0.0)))
	return {
		"a": ends[END_A],
		"b": ends[END_B],
		"length": length,
		"detached": detached,
		"check": check,
		"needs": needs,
		"passes": passes(check, length, needs),
	}


## The length `check` holds a dimension to: the player's width or height, the
## jump or the step it can climb, or `value`. 0 for None.
static func needed(check: String, value: float) -> float:
	var player := HFPlayerMetrics.standing()
	match check:
		"At least player width":
			return float(player["radius"]) * 2.0
		"At least player height":
			return float(player["height"])
		"At most jump height":
			return float(player["jump_height"])
		"At most step height":
			return float(player["step_height"])
		"At least", "At most":
			return value
	return 0.0


static func passes(check: String, length: float, needs: float) -> bool:
	if check.begins_with("At least"):
		return length + 0.0001 >= needs
	if check.begins_with("At most"):
		return length <= needs + 0.0001
	return true


## "the doorway, 1.10 m, needs at least 1.20 m (player width)", for Validate.
static func failure_text(dimension: Node, measured: Dictionary) -> String:
	var title := str(dimension.get("entity_data").get("title", dimension.name))
	var check: String = measured["check"]
	var how := "at least" if check.begins_with("At least") else "at most"
	var what := ""
	if check.contains("player") or check.contains("jump") or check.contains("step"):
		what = " (%s)" % check.trim_prefix("At least ").trim_prefix("At most ")
	return (
		"Dimension %s is %s m and needs %s %s m%s"
		% [
			title,
			String.num(float(measured["length"]), 2),
			how,
			String.num(float(measured["needs"]), 2),
			what
		]
	)


## The info `restore_entity_from_info()` takes for a dimension from `a` to `b`,
## both world points, each attached to what it lies on.
static func info_between(root: Node, a: Vector3, b: Vector3, title: String) -> Dictionary:
	var space := Transform3D(Basis.IDENTITY, a)
	return {
		"name": title,
		"entity_type": CLASS,
		"transform": space,
		"properties":
		{
			"title": title,
			"check": "None",
			"value": 0.0,
			END_A: attach(root, a, space),
			END_B: attach(root, b, space),
		},
	}


## `{count, failing, detached}` over the level's dimensions, for the bridge and the
## status board.
static func summary(root: Node) -> Dictionary:
	var count := 0
	var failing := 0
	var detached := 0
	for dimension in dimensions(root):
		var measured := measure(root, dimension)
		count += 1
		if not bool(measured["passes"]):
			failing += 1
		if bool(measured["detached"]):
			detached += 1
	return {"count": count, "failing": failing, "detached": detached}
