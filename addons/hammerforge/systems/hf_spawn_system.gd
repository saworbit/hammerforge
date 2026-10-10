@tool
extends RefCounted
class_name HFSpawnSystem

## Manages player spawn lookup, validation, debug visualisation, and auto-fix.
## Follows the coordinator+subsystem pattern: root is a LevelRoot reference
## injected via constructor.  All physics queries use PhysicsDirectSpaceState3D
## for sub-5 ms validation even on large levels.

# Preloaded under its global name so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const DraftEntity = preload("../draft_entity.gd")
const DraftBrush = preload("../brush_instance.gd")
@warning_ignore_restore("shadowed_global_identifier")
const HFBakeSystemType = preload("hf_bake_system.gd")

# --- Player capsule constants (MUST match playtest_fps.gd defaults) ---
const PLAYER_RADIUS := 0.35
const PLAYER_HEIGHT := 1.6
const FEET_OFFSET := 0.1
const DOWN_DISTANCE := 20.0
const FLOOR_RAY_LIFT := 2.0
const CEILING_MARGIN := 0.01
const UP_DISTANCE := 5.0
const MIN_CLEARANCE := 1.0
const BELOW_MAP_THRESHOLD := -100.0

# --- Severity levels ---
enum Severity { NONE, WARNING, ERROR }

var root: Node3D
var _debug_nodes: Array[Node3D] = []
var _debug_line_mesh_instance: MeshInstance3D = null
var _debug_line_immediate_mesh: ImmediateMesh = null
var _debug_line_material: StandardMaterial3D = null
var _debug_cleanup_timer_active: bool = false


func _init(level_root: Node3D) -> void:
	root = level_root


# ===========================================================================
# Spawn lookup
# ===========================================================================


## Return the active player_start entity for Quick Play.
## Priority: (1) primary flag, (2) first found.
func get_active_spawn() -> Node3D:
	var spawns := _get_all_spawns()
	if spawns.is_empty():
		return null
	for s in spawns:
		if _get_entity_bool(s, "primary"):
			return s
	return spawns[0]


## Return every player_start DraftEntity in the level.
func get_all_spawns() -> Array[Node3D]:
	return _get_all_spawns()


# ===========================================================================
# Validation
# ===========================================================================


## The layer this level bakes its world onto, or 1 if it cannot say.
func _level_bake_mask() -> int:
	if root and root.has_method("_layer_from_index"):
		var index: Variant = root.get("bake_collision_layer_index")
		if index is int or index is float:
			return int(root._layer_from_index(int(index)))
	return 1


## What `validate_spawn()` says of a spawn inside a brush.
const IN_BRUSH_ISSUE := "Spawn inside a brush"


## Validate a spawn entity and return a result dictionary.
## Keys: valid (bool), issues (PackedStringArray), suggested_position (Vector3),
##        floor_hit (Variant), ceiling_hit (Variant), severity (int).
## [collision_mask]: bitmask for physics queries; 0 falls back to the layer the
## level bakes onto. Should match the bake collision layer used by Quick Play.
## A spawn inside a brush gets that one issue, and a suggested position beside
## the brush on the same floor, or its own position when there is none nearby.
func validate_spawn(spawn: Node3D, collision_mask: int = 0) -> Dictionary:
	if not spawn or not is_instance_valid(spawn) or not spawn.is_inside_tree():
		return {
			"valid": false,
			"issues": PackedStringArray(["No valid player_start entity found"]),
			"suggested_position": Vector3.ZERO,
			"floor_hit": null,
			"ceiling_hit": null,
			"severity": Severity.ERROR,
		}

	var world := spawn.get_world_3d()
	if not world:
		return {
			"valid": false,
			"issues": PackedStringArray(["Spawn has no World3D (not in scene tree?)"]),
			"suggested_position": spawn.global_position,
			"floor_hit": null,
			"ceiling_hit": null,
			"severity": Severity.ERROR,
		}

	var space := world.direct_space_state
	if not space:
		return {
			"valid": false,
			"issues": PackedStringArray(["No physics space available"]),
			"suggested_position": spawn.global_position,
			"floor_hit": null,
			"ceiling_hit": null,
			"severity": Severity.ERROR,
		}

	var pos := spawn.global_position
	var height_offset := _get_entity_float(spawn, "height_offset", 1.0)
	# The level's own bake layer when the caller did not say, rather than layer 1.
	# A level baked onto layer 2 was reported as floating in space, because the
	# ray was looking at a layer nothing had been baked onto (#695).
	var mask := collision_mask if collision_mask > 0 else _level_bake_mask()
	var result := {
		"valid": true,
		"issues": PackedStringArray(),
		"suggested_position": pos,
		"floor_hit": null,
		"ceiling_hit": null,
		"severity": Severity.NONE,
	}

	# 1. Floor detection — raycast down, from no higher than the ceiling over
	# the spawn. Started over a low ceiling, it landed on the ceiling's top.
	var from := pos + Vector3.UP * _floor_ray_lift(space, pos, mask)
	var to := pos + Vector3.DOWN * DOWN_DISTANCE
	var ray_query := PhysicsRayQueryParameters3D.create(from, to)
	ray_query.collision_mask = mask

	var floor_hit := space.intersect_ray(ray_query)
	if not floor_hit:
		result.issues.append("Floating in space — no floor below")
		result.severity = Severity.ERROR
		result.valid = false
	else:
		result.floor_hit = floor_hit
		# Concave trimesh collision represents only the brush surfaces.  A
		# capsule wholly enclosed by a thick solid can therefore miss every
		# surface in collide_shape below.  A downward ray whose first hit is
		# above the spawn's feet means the ray entered the enclosing solid from
		# above, so report the actual error instead of only a floor offset (#973).
		if floor_hit.position.y > pos.y:
			result.issues.append("Spawn inside solid geometry")
			result.severity = Severity.ERROR
			result.valid = false
		var floor_y: float = floor_hit.position.y + FEET_OFFSET + height_offset
		var height_diff := absf(pos.y - floor_y)
		if height_diff > 0.3:
			result.issues.append("Spawn not on floor (%.2f units above)" % height_diff)
			result.suggested_position.y = floor_y
			if result.severity < Severity.WARNING:
				result.severity = Severity.WARNING

	# 2. Capsule collision check — is spawn inside geometry?
	var shape := CapsuleShape3D.new()
	shape.radius = PLAYER_RADIUS
	shape.height = PLAYER_HEIGHT
	var shape_query := PhysicsShapeQueryParameters3D.new()
	shape_query.shape = shape
	shape_query.transform = Transform3D(Basis.IDENTITY, pos + Vector3(0, PLAYER_HEIGHT / 2.0, 0))
	shape_query.collision_mask = mask
	var collisions := space.collide_shape(shape_query, 1)
	if not collisions.is_empty() and not result.issues.has("Spawn inside solid geometry"):
		result.issues.append("Spawn inside solid geometry")
		result.severity = Severity.ERROR
		result.valid = false

	# 3. Ceiling / headroom check
	if floor_hit:
		var head_pos: Vector3 = floor_hit.position + Vector3.UP * (PLAYER_HEIGHT + 0.2)
		var ceiling_to: Vector3 = head_pos + Vector3.UP * UP_DISTANCE
		var ceiling_query := PhysicsRayQueryParameters3D.create(head_pos, ceiling_to)
		ceiling_query.collision_mask = mask
		var ceiling_hit := space.intersect_ray(ceiling_query)
		result.ceiling_hit = ceiling_hit
		if ceiling_hit:
			var headroom: float = ceiling_hit.position.y - head_pos.y
			if headroom < MIN_CLEARANCE:
				result.issues.append("Insufficient headroom (%.2f units)" % headroom)
				if result.severity < Severity.WARNING:
					result.severity = Severity.WARNING

	# 4. Below-map heuristic
	if floor_hit and floor_hit.position.y < BELOW_MAP_THRESHOLD:
		result.issues.append("Spawn appears to be under the map")
		result.severity = Severity.ERROR
		result.valid = false

	# 5. The brushes themselves. A trimesh is only surfaces, so a capsule wholly
	# inside a column touches none of them and the rays read the column's own
	# faces: a pillar's top was the floor, a column up to the ceiling was fine, and
	# with a cutter in the level there was no floor. Each of those is the brush, so
	# it is the one thing said, and the fix is the nearest clear place on the same
	# floor, which is what the Check Bake Issues list moves it to (#1002).
	if spawn_is_blocked(spawn):
		var place: Variant = clear_place_for(spawn)
		result.issues = PackedStringArray([IN_BRUSH_ISSUE])
		result.severity = Severity.ERROR
		result.valid = false
		result.suggested_position = place if place is Vector3 else pos
		return result

	# Suggest floor snap when position differs
	if result.suggested_position == pos and floor_hit:
		result.suggested_position.y = (floor_hit.position.y + FEET_OFFSET + height_offset)

	return result


## How far over the spawn the floor ray starts. Up to FLOOR_RAY_LIFT, so a spawn
## sunk into its floor still finds the floor's top, but short of the first
## ceiling above it, so a spawn in a low room finds its floor and not the top of
## its ceiling. Back faces are skipped: from inside a solid this sees past the
## solid's own top, and the floor ray then lands on that top, which is how the
## spawn is found to be inside (#973).
func _floor_ray_lift(space: PhysicsDirectSpaceState3D, pos: Vector3, mask: int) -> float:
	var query := PhysicsRayQueryParameters3D.create(pos, pos + Vector3.UP * FLOOR_RAY_LIFT)
	query.collision_mask = mask
	query.hit_back_faces = false
	var overhead := space.intersect_ray(query)
	if overhead.is_empty():
		return FLOOR_RAY_LIFT
	return maxf(float(overhead.position.y) - pos.y - CEILING_MARGIN, 0.0)


## Apply the suggested fix from a validation result.
func auto_fix_spawn(spawn: Node3D, validation: Dictionary) -> void:
	if not spawn or not is_instance_valid(spawn):
		return
	var suggested: Vector3 = validation.get("suggested_position", spawn.global_position)
	if suggested != spawn.global_position:
		spawn.global_position = suggested


# ===========================================================================
# Auto-create fallback spawn
# ===========================================================================

## How far above the floor a created spawn starts, in metres. The same default
## `player_start.height_offset` carries in `entities.json`, so a spawn this makes
## is where `validate_spawn()` would put one.
const DEFAULT_SPAWN_HEIGHT_OFFSET := 1.0

## How many grid steps out from the middle a created spawn looks for room to
## stand, before it settles for the middle.
const SPAWN_SEARCH_RINGS := 24


## The spawn a level gets when it has none: over the middle of what is built,
## standing on the floor.
##
## It used to be the centroid of the brush origins plus five units, with a hard
## coded `Vector3(0, 5, 0)` for an empty level. Five units was a small step up
## when a room was 256 units tall; since #625 the player is 1.6 units and a room
## is 3, so it put the spawn above the ceiling of anything a mapper builds --
## and `validate_spawn()`, 130 lines further down the same file, rejected where
## it had just been put (#657).
##
## The level's own AABB rather than the centroid of the origins, because the
## centroid of a hollowed room's six walls is the middle of the room whatever
## size it is, and the floor is what the player stands on.
##
## The height is the one `validate_spawn()` asks for: the top of the floor under
## the centre, plus `FEET_OFFSET` and `height_offset`. It was the bottom of the
## level's bounds plus `height_offset`, which agreed only for a floor thinner
## than 0.2. A 0.3 slab got a warning about the spawn just made, and a 1.0 one
## stopped Test Level with the spawn inside the floor (#961).
##
## Something standing at the middle, a pillar or a crate, had the spawn inside
## it (#974). So the player's column over the floor is checked against what is
## built, and when it is not clear the spawn moves out from the middle a grid
## step at a time until it is.
func create_default_spawn() -> Node3D:
	var centroid := Vector3.ZERO
	var bounds := _level_bounds()
	if bounds.size != Vector3.ZERO or bounds.position != Vector3.ZERO:
		centroid = bounds.get_center()
		centroid.y = _floor_top_under(centroid)
		centroid = _clear_place_near(centroid, bounds)
	centroid.y += FEET_OFFSET + DEFAULT_SPAWN_HEIGHT_OFFSET

	var entity := DraftEntity.new()
	entity.name = "DraftEntity"
	entity.entity_type = "player_start"
	entity.entity_class = "player_start"
	if root.entity_system:
		root.entity_system.add_entity(entity)
	elif root.entities_node:
		root.entities_node.add_child(entity)
	entity.global_position = centroid
	return entity


## What the level occupies, over the same nodes the spawn already walked.
##
## Over the pick nodes rather than `LevelRoot._compute_level_aabb()`, which reads
## the draft brushes only.
func _level_bounds() -> AABB:
	var bounds := AABB()
	var first := true
	for node in root._iter_pick_nodes():
		if not (node is Node3D) or node is DraftEntity:
			continue
		var box := _node_box(node)
		if first:
			bounds = box
			first = false
		else:
			bounds = bounds.merge(box)
	return bounds


## The top of what a player would stand on at `centre`: of the brushes whose
## footprint holds it, the lowest, so a room's floor and not its ceiling. With
## none under the centre, the top of the lowest brush. A subtraction is not
## something to stand on.
func _floor_top_under(centre: Vector3) -> float:
	var boxes := _solid_boxes()
	var under := _floor_in(boxes, centre)
	if under < INF:
		return under
	var lowest := INF
	for box in boxes:
		lowest = minf(lowest, box.end.y)
	return lowest if lowest < INF else 0.0


## The boxes of what is built and solid: no entities, no subtractions.
func _solid_boxes() -> Array[AABB]:
	var boxes: Array[AABB] = []
	for node in root._iter_pick_nodes():
		if not (node is Node3D) or node is DraftEntity:
			continue
		if node is DraftBrush and node.operation == CSGShape3D.OPERATION_SUBTRACTION:
			continue
		boxes.append(_node_box(node))
	return boxes


## The lowest top among `boxes` whose footprint holds `point`, or INF for none.
static func _floor_in(boxes: Array[AABB], point: Vector3) -> float:
	var under := INF
	for box in boxes:
		var holds_x := point.x >= box.position.x and point.x <= box.end.x
		var holds_z := point.z >= box.position.z and point.z <= box.end.z
		if holds_x and holds_z:
			under = minf(under, box.end.y)
	return under


## The spawn problems the brushes alone can show, for the Test tab's issue list
## (#992): no spawn at all, and a spawn standing inside a brush. Each names the
## fix the list offers, which is one undo step. An empty level has no spawn
## problem, as `HFValidationSystem._check_spawn()` says too.
func layout_issues() -> Array:
	var issues: Array = []
	if _solid_boxes().is_empty():
		return issues
	var spawn := get_active_spawn()
	if spawn == null:
		var missing := {
			"type": "missing_spawn",
			"severity": 1,
			"message": "No player spawn. Test Level makes one in the middle of the level",
			"node": null,
			"fix": "create_spawn",
		}
		issues.append(missing)
	elif spawn_is_blocked(spawn):
		var blocked := {
			"type": "spawn_in_brush",
			"severity": 2,
			"message": "Player spawn '%s' stands inside a brush" % spawn.name,
			"node": spawn,
			"fix": "clear_spawn",
		}
		issues.append(blocked)
	return issues


## The floor a spawn stands on: its height less the feet offset and its own
## height offset, as `validate_spawn()` places one.
func _floor_of(spawn: Node3D) -> Vector3:
	var height_offset := _get_entity_float(spawn, "height_offset", DEFAULT_SPAWN_HEIGHT_OFFSET)
	return spawn.global_position - Vector3.UP * (FEET_OFFSET + height_offset)


## How far a line has to run inside a brush to count, in metres, and how far a
## brush's faces are moved in, and a cutter's out, so that touching is not inside.
const LINE_HAIR := 0.01


## Whether the player at `spawn` would stand inside a solid brush: whether the
## line its capsule stands on runs through a brush, by the brush's own faces,
## where no cutter has cut it away. Needs no bake, unlike `validate_spawn()`.
##
## It asked whether the player's column met a brush's box. A box holds more than
## its brush, so a spawn in a room cut out of a block, on a ramp, or in a trigger
## read as buried, and Test Level could not go by that (#1002).
func spawn_is_blocked(spawn: Node3D) -> bool:
	var feet := spawn.global_position
	var head := feet + Vector3.UP * PLAYER_HEIGHT
	return _line_in_solid(_brush_solids(AABB(feet, head - feet).grow(LINE_HAIR)), feet, head)


## The brushes whose boxes reach into `near`, as `_line_in_solid()` reads them, in
## the order the bake adds them: `solids`, each `{planes, order, cut}`, and
## `cutters`, each `{planes, order}`. A cutter carves the structural solids before it, as a CSG combiner
## does, and a committed cutter carves them all. A brush with a class is not cut,
## since only structural brushes go into the boolean. A trigger bakes to an
## Area3D, and a pending cutter is not baked, so neither is either.
func _brush_solids(near: AABB) -> Dictionary:
	var solids: Array[Dictionary] = []
	var cutters: Array[Dictionary] = []
	var nodes: Array = root._iter_pick_nodes()
	var first_committed := nodes.size()
	var committed: Variant = root.get("committed_node")
	if root.get("commit_freeze") and committed is Node:
		nodes.append_array((committed as Node).get_children())
	for order in nodes.size():
		var node := nodes[order] as Node3D
		if node == null or node is DraftEntity or not _node_box(node).intersects(near):
			continue
		var bec := str(node.get_meta("brush_entity_class", ""))
		if bec.begins_with("trigger_"):
			continue
		var cuts := order >= first_committed
		var brush := node as DraftBrush
		if brush and brush.operation == CSGShape3D.OPERATION_SUBTRACTION:
			if brush.get_parent() == root.get("pending_node") or bec != "":
				continue
			cuts = true
		var entry := {"planes": _planes_of(node), "order": order}
		if cuts:
			cutters.append(entry)
		else:
			entry["cut"] = bec == ""
			solids.append(entry)
	return {"solids": solids, "cutters": cutters}


## The planes of a brush's faces in the level, each facing out. A brush with no
## faces, or a node that is not a brush, is its box.
func _planes_of(node: Node3D) -> Array[Plane]:
	var planes: Array[Plane] = []
	if node is DraftBrush:
		var xform := node.global_transform
		var loops: Array[PackedVector3Array] = []
		var middle := Vector3.ZERO
		var count := 0
		for face in (node as DraftBrush).faces:
			if face == null or face.local_verts.size() < 3:
				continue
			var loop := PackedVector3Array()
			for point in face.local_verts:
				loop.append(xform * point)
				middle += xform * point
				count += 1
			loops.append(loop)
		for loop in loops:
			var plane := _outward_plane(loop, middle / maxi(count, 1))
			if plane.normal != Vector3.ZERO:
				planes.append(plane)
	if planes.is_empty():
		var box := _node_box(node)
		planes = [
			Plane(Vector3.RIGHT, box.end.x),
			Plane(Vector3.LEFT, -box.position.x),
			Plane(Vector3.UP, box.end.y),
			Plane(Vector3.DOWN, -box.position.y),
			Plane(Vector3.BACK, box.end.z),
			Plane(Vector3.FORWARD, -box.position.z),
		]
	return planes


## The plane of a face's corners, turned to face away from `inside`, or a plane
## with no normal for a face with no area. Newell's normal, so a face with more
## than three corners uses them all.
static func _outward_plane(loop: PackedVector3Array, inside: Vector3) -> Plane:
	var normal := Vector3.ZERO
	var centre := Vector3.ZERO
	for i in loop.size():
		var a := loop[i]
		var b := loop[(i + 1) % loop.size()]
		normal.x += (a.y - b.y) * (a.z + b.z)
		normal.y += (a.z - b.z) * (a.x + b.x)
		normal.z += (a.x - b.x) * (a.y + b.y)
		centre += a
	if normal.length_squared() < 1e-12:
		return Plane()
	var plane := Plane(normal.normalized(), centre / loop.size())
	return -plane if plane.distance_to(inside) > 0.0 else plane


## Whether the line from `from` to `to` runs through a solid in `brushes`, from
## `_brush_solids()`, for more than `LINE_HAIR`, where no cutter after it has cut
## it away. Exact for a convex brush, which a brush of one shape is. A concave one
## counts only where it is inside every face, so it is missed, never imagined.
static func _line_in_solid(brushes: Dictionary, from: Vector3, to: Vector3) -> bool:
	var hair := LINE_HAIR / maxf(from.distance_to(to), LINE_HAIR)
	for solid in brushes["solids"]:
		var span := _clip(solid["planes"], from, to, -LINE_HAIR)
		if span.y - span.x <= hair:
			continue
		var cuts: Array[Vector2] = []
		if solid["cut"]:
			for cutter in brushes["cutters"]:
				if cutter["order"] > solid["order"]:
					var cut := _clip(cutter["planes"], from, to, LINE_HAIR)
					if cut.y > cut.x:
						cuts.append(cut)
		if _uncut(span, cuts) > hair:
			return true
	return false


## The stretch of the line from `from` to `to` that is behind every plane, as the
## fractions along it where it goes in and comes out, or nothing. `grow` moves
## every plane out by that much, or in when it is less than zero.
static func _clip(planes: Array, from: Vector3, to: Vector3, grow: float) -> Vector2:
	var enter := 0.0
	var leave := 1.0
	var along := to - from
	for plane: Plane in planes:
		var start := plane.distance_to(from) - grow
		var rate := plane.normal.dot(along)
		if is_zero_approx(rate):
			if start > 0.0:
				return Vector2.ZERO
			continue
		if rate > 0.0:
			leave = minf(leave, -start / rate)
		else:
			enter = maxf(enter, -start / rate)
		if leave <= enter:
			return Vector2.ZERO
	return Vector2(enter, leave)


## How much of `span` is left out of every one of `cuts`, all of them fractions
## along the same line.
static func _uncut(span: Vector2, cuts: Array[Vector2]) -> float:
	cuts.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var left := 0.0
	var at := span.x
	for cut in cuts:
		if cut.x > at:
			left += minf(cut.x, span.y) - at
		at = maxf(at, cut.y)
		if at >= span.y:
			return left
	return left + span.y - at


## Where `spawn` could stand clear on the floor it is on, the nearest place a grid
## step at a time, or null when there is none nearby.
func clear_place_for(spawn: Node3D) -> Variant:
	var stand := _floor_of(spawn)
	var place := _clear_place_near(stand, _level_bounds(), true)
	if not _column_is_clear(_solid_boxes(), place):
		return null
	return spawn.global_position + (place - stand)


## `stand` if a player standing there has room, or else the nearest place in
## rings of grid steps round it, over a floor and inside `bounds`, that has. With
## none, `stand` as it was. `same_floor` keeps the search on the floor `stand` is
## on, for moving a spawn sideways; without it each place stands on the lowest
## floor under it, as a new spawn does.
func _clear_place_near(stand: Vector3, bounds: AABB, same_floor: bool = false) -> Vector3:
	var boxes := _solid_boxes()
	if _column_is_clear(boxes, stand):
		return stand
	var snap: Variant = root.get("grid_snap")
	var step := clampf(float(snap) if snap is float or snap is int else 0.5, 0.25, 4.0)
	var rings := mini(ceili(maxf(bounds.size.x, bounds.size.z) / step), SPAWN_SEARCH_RINGS)
	# Only what reaches into the square the rings cover, so a big level with a
	# crowded middle is not walked whole for every place tried.
	var half := rings * step + PLAYER_RADIUS
	var square := Rect2(stand.x - half, stand.z - half, half * 2.0, half * 2.0)
	var near: Array[AABB] = []
	for box in boxes:
		if Rect2(box.position.x, box.position.z, box.size.x, box.size.z).intersects(square, true):
			near.append(box)
	boxes = near
	for ring in range(1, rings + 1):
		var places: Array[Vector3] = []
		for i in range(-ring, ring + 1):
			for j in range(-ring, ring + 1):
				if maxi(absi(i), absi(j)) != ring:
					continue
				var place := Vector3(stand.x + i * step, 0.0, stand.z + j * step)
				if place.x < bounds.position.x or place.x > bounds.end.x:
					continue
				if place.z < bounds.position.z or place.z > bounds.end.z:
					continue
				if same_floor:
					place.y = _floor_at(boxes, place, stand.y)
				else:
					place.y = _floor_in(boxes, place)
				if place.y < INF:
					places.append(place)
		places.sort_custom(
			func(a: Vector3, b: Vector3) -> bool:
				return (
					Vector2(a.x - stand.x, a.z - stand.z).length_squared()
					< Vector2(b.x - stand.x, b.z - stand.z).length_squared()
				)
		)
		for place in places:
			if _column_is_clear(boxes, place):
				return place
	return stand


## `height` if a box in `boxes` whose footprint holds `point` has its top there,
## or INF: a place on the same floor.
static func _floor_at(boxes: Array[AABB], point: Vector3, height: float) -> float:
	for box in boxes:
		var holds_x := point.x >= box.position.x and point.x <= box.end.x
		var holds_z := point.z >= box.position.z and point.z <= box.end.z
		if holds_x and holds_z and absf(box.end.y - height) < 0.05:
			return height
	return INF


## Whether a player standing on `stand` is clear of `boxes`: a column the
## player's width, from just over the floor to the top of the capsule
## `validate_spawn()` checks.
static func _column_is_clear(boxes: Array[AABB], stand: Vector3) -> bool:
	var top := FEET_OFFSET + DEFAULT_SPAWN_HEIGHT_OFFSET + PLAYER_HEIGHT
	var column := AABB(
		Vector3(stand.x - PLAYER_RADIUS, stand.y + 0.01, stand.z - PLAYER_RADIUS),
		Vector3(PLAYER_RADIUS * 2.0, top - 0.01, PLAYER_RADIUS * 2.0)
	)
	for box in boxes:
		if box.intersects(column):
			return false
	return true


## A pick node's box in the level: a brush's own bounds, turn included, or a box
## of its `size` round its position for anything else.
func _node_box(node: Node3D) -> AABB:
	if node is DraftBrush:
		return HFBakeSystemType.brush_world_aabb(node, node.global_transform)
	var size: Variant = node.get("size")
	var extent: Vector3 = size if size is Vector3 else Vector3.ONE
	return AABB(node.global_position - extent * 0.5, extent)


# ===========================================================================
# Debug visualisation
# ===========================================================================


## Show validation debug overlays (capsule, floor ray, ceiling ray, markers).
## Cleans up automatically after `duration` seconds.
func show_validation_debug(spawn: Node3D, validation: Dictionary, duration: float = 8.0) -> void:
	cleanup_debug()
	if not spawn or not is_instance_valid(spawn) or not spawn.is_inside_tree():
		return

	var pos := spawn.global_position
	var is_valid: bool = validation.get("valid", true)

	# 1. Player capsule preview (green / red)
	var capsule_mi := MeshInstance3D.new()
	var capsule_mesh := CapsuleMesh.new()
	capsule_mesh.radius = PLAYER_RADIUS
	capsule_mesh.height = PLAYER_HEIGHT
	capsule_mi.mesh = capsule_mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color.GREEN if is_valid else Color.RED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.4
	mat.no_depth_test = true
	capsule_mi.material_override = mat
	capsule_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	capsule_mi.name = "_SpawnDebugCapsule"
	root.add_child(capsule_mi)
	capsule_mi.global_position = pos + Vector3(0, PLAYER_HEIGHT / 2.0, 0)
	_debug_nodes.append(capsule_mi)

	# 2. Floor ray
	var floor_hit: Variant = validation.get("floor_hit", null)
	if floor_hit is Dictionary and floor_hit.has("position"):
		var hit_pos: Vector3 = floor_hit.position
		_draw_debug_line(
			pos + Vector3.UP * 2.0,
			hit_pos,
			Color.GREEN if is_valid else Color.ORANGE,
		)
		# Floor disc marker
		var disc := _create_debug_disc(hit_pos, Color.LIME)
		_debug_nodes.append(disc)
	else:
		_draw_debug_line(
			pos + Vector3.UP * 2.0,
			pos + Vector3.DOWN * DOWN_DISTANCE,
			Color.RED,
		)

	# 3. Ceiling ray
	var ceiling_hit: Variant = validation.get("ceiling_hit", null)
	if (
		ceiling_hit is Dictionary
		and ceiling_hit.has("position")
		and floor_hit is Dictionary
		and floor_hit.has("position")
	):
		var head_pos: Vector3 = floor_hit.position + Vector3.UP * PLAYER_HEIGHT
		_draw_debug_line(head_pos, ceiling_hit.position, Color.YELLOW)

	# 4. Issue markers — red sphere for collision issues
	var issues: PackedStringArray = validation.get("issues", PackedStringArray())
	for issue in issues:
		if "inside" in issue.to_lower():
			var sphere := _create_debug_sphere(pos, Color.RED, 0.7)
			_debug_nodes.append(sphere)

	# Auto-clean after duration (0 = persistent until manual cleanup)
	if duration > 0.0:
		_schedule_debug_cleanup(duration)


## Remove all temporary debug visualisation nodes.
func cleanup_debug() -> void:
	for n in _debug_nodes:
		if is_instance_valid(n) and n.is_inside_tree():
			n.get_parent().remove_child(n)
			n.queue_free()
	_debug_nodes.clear()
	if _debug_line_mesh_instance and is_instance_valid(_debug_line_mesh_instance):
		if _debug_line_mesh_instance.is_inside_tree():
			_debug_line_mesh_instance.get_parent().remove_child(_debug_line_mesh_instance)
		_debug_line_mesh_instance.queue_free()
		_debug_line_mesh_instance = null
	_debug_line_immediate_mesh = null


func is_debug_visible() -> bool:
	return not _debug_nodes.is_empty()


# ===========================================================================
# Internals
# ===========================================================================


func _get_all_spawns() -> Array[Node3D]:
	var result: Array[Node3D] = []
	if not root:
		return result
	var entities: Node3D = root.entities_node if root.get("entities_node") else null
	if not entities:
		return result
	for child in entities.get_children():
		if child is DraftEntity:
			var ec: String = child.entity_class
			if ec == "":
				ec = child.entity_type
			if ec == "player_start":
				result.append(child)
	return result


func _get_entity_bool(entity: Node3D, key: String, fallback: bool = false) -> bool:
	if entity is DraftEntity and entity.entity_data.has(key):
		return bool(entity.entity_data[key])
	return entity.get_meta(key, fallback)


func _get_entity_float(entity: Node3D, key: String, fallback: float = 0.0) -> float:
	if entity is DraftEntity and entity.entity_data.has(key):
		return float(entity.entity_data[key])
	return float(entity.get_meta(key, fallback))


func _ensure_debug_line_mesh() -> void:
	if _debug_line_mesh_instance and is_instance_valid(_debug_line_mesh_instance):
		return
	_debug_line_mesh_instance = MeshInstance3D.new()
	_debug_line_mesh_instance.name = "_SpawnDebugLines"
	_debug_line_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not _debug_line_material:
		_debug_line_material = StandardMaterial3D.new()
		_debug_line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_debug_line_material.vertex_color_use_as_albedo = true
		_debug_line_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_debug_line_material.no_depth_test = true
	_debug_line_mesh_instance.material_override = _debug_line_material
	_debug_line_immediate_mesh = ImmediateMesh.new()
	_debug_line_mesh_instance.mesh = _debug_line_immediate_mesh
	root.add_child(_debug_line_mesh_instance)


func _draw_debug_line(from_pos: Vector3, to_pos: Vector3, color: Color) -> void:
	_ensure_debug_line_mesh()
	if not _debug_line_immediate_mesh:
		return
	_debug_line_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_debug_line_immediate_mesh.surface_set_color(color)
	_debug_line_immediate_mesh.surface_add_vertex(from_pos)
	_debug_line_immediate_mesh.surface_set_color(color)
	_debug_line_immediate_mesh.surface_add_vertex(to_pos)
	_debug_line_immediate_mesh.surface_end()


func _create_debug_disc(pos: Vector3, color: Color, radius: float = 0.6) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 0.02
	mi.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.albedo_color.a = 0.5
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = "_SpawnDebugDisc"
	root.add_child(mi)
	mi.global_position = pos
	return mi


func _create_debug_sphere(pos: Vector3, color: Color, radius: float = 0.5) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	mi.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.albedo_color.a = 0.35
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = "_SpawnDebugSphere"
	root.add_child(mi)
	mi.global_position = pos
	return mi


func _schedule_debug_cleanup(duration: float) -> void:
	if _debug_cleanup_timer_active:
		return
	if not root or not root.is_inside_tree():
		return
	_debug_cleanup_timer_active = true
	var tree := root.get_tree()
	if not tree:
		_debug_cleanup_timer_active = false
		return
	var timer := tree.create_timer(duration)
	timer.timeout.connect(
		func():
			if is_instance_valid(self):
				_debug_cleanup_timer_active = false
				cleanup_debug()
	)
