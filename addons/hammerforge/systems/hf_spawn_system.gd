@tool
extends RefCounted
class_name HFSpawnSystem

## Manages player spawn lookup, validation, debug visualisation, and auto-fix.
## Follows the coordinator+subsystem pattern: root is a LevelRoot reference
## injected via constructor.  All physics queries use PhysicsDirectSpaceState3D
## for sub-5 ms validation even on large levels.

const DraftEntity = preload("../draft_entity.gd")

# --- Player capsule constants (MUST match playtest_fps.gd defaults) ---
const PLAYER_RADIUS := 0.35
const PLAYER_HEIGHT := 1.6
const FEET_OFFSET := 0.1
const DOWN_DISTANCE := 20.0
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


## Validate a spawn entity and return a result dictionary.
## Keys: valid (bool), issues (PackedStringArray), suggested_position (Vector3),
##        floor_hit (Variant), ceiling_hit (Variant), severity (int).
## [collision_mask]: bitmask for physics queries; 0 falls back to layer 1.
## Should match the bake collision layer used by Quick Play.
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
	var mask := collision_mask if collision_mask > 0 else 1
	var result := {
		"valid": true,
		"issues": PackedStringArray(),
		"suggested_position": pos,
		"floor_hit": null,
		"ceiling_hit": null,
		"severity": Severity.NONE,
	}

	# 1. Floor detection — raycast down
	var from := pos + Vector3.UP * 2.0
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
	if not collisions.is_empty():
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

	# Suggest floor snap when position differs
	if result.suggested_position == pos and floor_hit:
		result.suggested_position.y = (floor_hit.position.y + FEET_OFFSET + height_offset)

	return result


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


## Create a safe default player_start from brush centroids + height offset.
func create_default_spawn() -> Node3D:
	var centroid := Vector3(0, 5, 0)
	if root.has_method("_iter_pick_nodes"):
		var pick_nodes: Array = root._iter_pick_nodes()
		var count := 0
		var sum := Vector3.ZERO
		for node in pick_nodes:
			if node is Node3D and not (node is DraftEntity):
				sum += node.global_position
				count += 1
		if count > 0:
			centroid = sum / float(count)
			centroid.y += 5.0

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
