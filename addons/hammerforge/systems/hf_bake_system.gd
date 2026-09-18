@tool
extends RefCounted
class_name HFBakeSystem

const PrefabFactory = preload("../prefab_factory.gd")
const DraftBrush = preload("../brush_instance.gd")
const HFAutoConnector = preload("../paint/hf_auto_connector.gd")
const HFIORuntime = preload("../hf_io_runtime.gd")
const HFDoorRuntime = preload("../hf_door_runtime.gd")
const HFLog = preload("../hf_log.gd")

## What a baked static body detects: nothing.
##
## These never move, so a mask buys them nothing and only widens the broadphase.
## The mask used to be a copy of the layer, which meant changing the Physics
## Layer moved the mask with it - two controls' worth of behaviour from one
## dropdown, and not what either of them is for (#695).
const STATIC_BODY_MASK := 0

## Brush entity classes whose geometry moves, and so needs a node of its own to
## move with its collision.
const MOVER_CLASSES := ["func_door", "door_basic"]

const BAKED_CONTAINER_NAME := &"BakedGeometry"
const BAKED_CONTAINER_META := &"_hammerforge_baked_container"
const BAKED_CONTAINER_SCHEMA := 1
const BAKED_PREVIEW_MODE_META := &"_hammerforge_bake_preview_mode"

## Bake preview mode: FULL produces final geometry, WIREFRAME skips materials
## and generates unshaded wireframe, PROXY uses simplified box meshes.
enum PreviewMode { FULL, WIREFRAME, PROXY }

## Why the last bake call returned what it did.
##
## Every bake entry point returns a plain bool, and false alone is ambiguous:
## a refused bake, a bake with nothing to do, and a bake that genuinely failed
## all look identical. Callers that need the difference read
## get_last_bake_status() immediately after the call.
enum BakeStatus { NOT_RUN, SUCCESS, FAILED, BUSY, NOTHING_TO_DO }

var root: Node3D

## The bake settings the last successful bake ran with, and whether there has
## been one. Any other signature means the baked result no longer answers the
## settings that are set — but only once there is a result for them to go stale.
var _last_bake_settings_signature: int = 0
var _has_baked_once: bool = false
var _last_bake_success: bool = false
var _last_bake_status: int = BakeStatus.NOT_RUN
var _bake_in_flight := false
static var _wireframe_shader: Shader = null
static var _wireframe_material: ShaderMaterial = null

## Number of brushes to process per frame during face-based bake collection.
## Lower values yield more often (smoother editor), higher values bake faster.
const _FACE_BAKE_BATCH := 8


func _init(level_root: Node3D) -> void:
	root = level_root


# ---------------------------------------------------------------------------
# Baked container lifecycle
# ---------------------------------------------------------------------------


## Re-adopt baked geometry persisted in the scene and collapse legacy duplicate
## roots created by the old queue_free-then-replace flow. Legacy anonymous
## nodes are only considered when every direct child is a known bake artifact
## and at least one child has an unmistakable baked-mesh signature.
func reconcile_baked_containers() -> Node3D:
	var candidates := _managed_baked_containers()
	if candidates.is_empty():
		root.baked_container = null
		return null

	# Child order is persistence order. The last populated candidate is the
	# newest legacy bake, which matters when the canonical node is an older or
	# empty container left behind by the duplication bug.
	var survivor: Node3D = null
	for candidate: Node3D in candidates:
		if _has_baked_payload(candidate):
			survivor = candidate
	if not survivor:
		for candidate: Node3D in candidates:
			if candidate.has_meta(BAKED_CONTAINER_META):
				survivor = candidate
	if not survivor:
		survivor = candidates[0]

	var removed := 0
	for candidate: Node3D in candidates:
		if candidate == survivor:
			continue
		_destroy_baked_container(candidate)
		removed += 1

	if survivor.get_parent() and survivor.get_parent() != root:
		survivor.get_parent().remove_child(survivor)
	survivor.name = BAKED_CONTAINER_NAME
	survivor.set_meta(BAKED_CONTAINER_META, BAKED_CONTAINER_SCHEMA)
	if survivor.get_parent() != root:
		root.add_child(survivor)
	root.baked_container = survivor
	if removed > 0 and root.has_method("_log"):
		root.call("_log", "Removed %d duplicate baked container(s)" % removed)
	return survivor


## Install a complete bake as the only managed container. Existing containers
## are detached synchronously so the canonical name is available before the
## replacement enters the tree, then queued for safe editor-aware deletion.
func replace_baked_container(container: Node3D) -> Node3D:
	if not container or not is_instance_valid(container):
		return null
	for candidate: Node3D in _managed_baked_containers():
		if candidate != container:
			_destroy_baked_container(candidate)
	if container.get_parent() and container.get_parent() != root:
		container.get_parent().remove_child(container)
	container.name = BAKED_CONTAINER_NAME
	container.set_meta(BAKED_CONTAINER_META, BAKED_CONTAINER_SCHEMA)
	if container.get_parent() != root:
		root.add_child(container)
	root.baked_container = container
	return container


## Remove all HammerForge-owned baked roots immediately. This is also used by
## clear/restore flows so a scene saved in the same frame cannot retain ghosts.
func clear_baked_containers() -> void:
	for candidate: Node3D in _managed_baked_containers():
		_destroy_baked_container(candidate)
	root.baked_container = null
	root._last_bake_preview_mode = PreviewMode.FULL


## Capture derived bake output for the small number of actions (notably Commit
## Cuts) whose Undo/Redo must restore the exact prior visual/collision result.
## Ordinary edit snapshots intentionally remain source-only to avoid bloating
## every undo entry with baked meshes.
func capture_baked_geometry_snapshot() -> PackedScene:
	var container := reconcile_baked_containers()
	if not container:
		return null
	var copy := container.duplicate() as Node3D
	if not copy:
		return null
	_assign_packed_snapshot_owners(copy, copy)
	var snapshot := PackedScene.new()
	var result := snapshot.pack(copy)
	copy.free()
	if result != OK:
		push_warning("Could not capture baked geometry for Undo/Redo (error %d)" % result)
		return null
	var preview_mode := clampi(root._last_bake_preview_mode, PreviewMode.FULL, PreviewMode.PROXY)
	snapshot.set_meta(BAKED_PREVIEW_MODE_META, preview_mode)
	return snapshot


func restore_baked_geometry_snapshot(
	snapshot: PackedScene, fallback_preview_mode: int = PreviewMode.FULL
) -> void:
	var preview_mode := clampi(fallback_preview_mode, PreviewMode.FULL, PreviewMode.PROXY)
	if snapshot != null:
		preview_mode = clampi(
			int(snapshot.get_meta(BAKED_PREVIEW_MODE_META, preview_mode)),
			PreviewMode.FULL,
			PreviewMode.PROXY,
		)
	clear_baked_containers()
	# Even an intentionally empty snapshot represents exact derived state. Keep
	# its state-level preview choice instead of inheriting clear()'s FULL reset.
	root._last_bake_preview_mode = preview_mode
	if snapshot == null or not snapshot.can_instantiate():
		return
	var restored := snapshot.instantiate() as Node3D
	if not restored:
		push_warning("Could not restore baked geometry snapshot")
		return
	replace_baked_container(restored)
	root._assign_owner_recursive(restored)


static func _assign_packed_snapshot_owners(node: Node, snapshot_root: Node) -> void:
	for child in node.get_children():
		child.owner = snapshot_root
		_assign_packed_snapshot_owners(child, snapshot_root)


func _managed_baked_containers() -> Array[Node3D]:
	var candidates: Array[Node3D] = []
	for child in root.get_children():
		if not (child is Node3D):
			continue
		var node := child as Node3D
		if (
			node == root.baked_container
			or node.name == BAKED_CONTAINER_NAME
			or node.has_meta(BAKED_CONTAINER_META)
			or _is_legacy_anonymous_bake(node)
		):
			candidates.append(node)
	if (
		root.baked_container
		and is_instance_valid(root.baked_container)
		and not candidates.has(root.baked_container)
	):
		candidates.append(root.baked_container)
	return candidates


static func _is_legacy_anonymous_bake(node: Node3D) -> bool:
	if not str(node.name).begins_with("@Node3D@") or node.get_child_count() == 0:
		return false
	var has_payload_signature := false
	for child in node.get_children():
		var child_name := str(child.name)
		if not _is_known_bake_artifact_name(child_name):
			return false
		if (
			child_name.begins_with("BakedChunk_")
			or child_name.begins_with("BakedMesh_")
			or child_name.begins_with("BakedSelection_")
			or child_name.begins_with("HMFloor__")
		):
			has_payload_signature = true
	return has_payload_signature


static func _is_known_bake_artifact_name(node_name: String) -> bool:
	return (
		node_name == "FloorCollision"
		or node_name == "FaceCollision"
		or node_name == "BakedNavmesh"
		or node_name == "HFIODispatcher"
		or node_name == "Occluders"
		or node_name == "Nonstructural"
		or node_name.begins_with("BakedChunk_")
		or node_name.begins_with("BakedMesh_")
		or node_name.begins_with("BakedSelection_")
		or node_name.begins_with("AutoConnector_")
		or node_name.begins_with("Collision_")
		or node_name.begins_with("HeightmapFloor_")
		or node_name.begins_with("HMFloor__")
		or node_name.begins_with("MMI_")
	)


static func _has_baked_payload(container: Node3D) -> bool:
	for child in container.get_children():
		var child_name := str(child.name)
		if (
			child is MeshInstance3D
			or child is MultiMeshInstance3D
			or child_name.begins_with("BakedChunk_")
			or child_name.begins_with("BakedSelection_")
			or child_name.begins_with("HMFloor__")
			or child_name == "Nonstructural"
		):
			return true
	return false


static func _destroy_baked_container(container: Node3D) -> void:
	if not container or not is_instance_valid(container):
		return
	if container.get_parent():
		container.get_parent().remove_child(container)
	if not container.is_queued_for_deletion():
		container.queue_free()


# ---------------------------------------------------------------------------
# Bake time estimation
# ---------------------------------------------------------------------------


## Returns an estimate dict: {estimated_ms, brush_count, tip}.
## Uses the ratio from the last real bake if available.
func estimate_bake_time(brush_ids: Array = []) -> Dictionary:
	var count := 0
	if brush_ids.is_empty():
		count = _total_bakeable_brush_count()
	else:
		count = brush_ids.size()
	var ms_per_brush := 2.0  # default fallback
	var last_count := _total_bakeable_brush_count()
	if root._last_bake_duration_ms > 0 and last_count > 0:
		ms_per_brush = float(root._last_bake_duration_ms) / float(last_count)
	var estimated_ms: int = int(ceil(ms_per_brush * count))
	var tip := ""
	if count > 500:
		tip = "Chunking recommended for >500 brushes"
	elif count > 200 and not bool(root.get("bake_use_thread_pool")):
		tip = "Consider enabling thread pool for faster bakes"
	elif count == 0:
		tip = "No brushes to bake"
	return {"estimated_ms": estimated_ms, "brush_count": count, "tip": tip}


func _total_bakeable_brush_count() -> int:
	var total := count_brushes_in(root.draft_brushes_node)
	total += count_brushes_in(root.generated_floors)
	total += count_brushes_in(root.generated_walls)
	if root.commit_freeze:
		total += count_brushes_in(root.committed_node)
	return total


# ---------------------------------------------------------------------------
# Selection / incremental bake
# ---------------------------------------------------------------------------


## Why the most recent bake call returned what it did. Read it immediately
## after the call: it is overwritten by the next one.
func get_last_bake_status() -> int:
	return _last_bake_status


func is_bake_in_flight() -> bool:
	return _bake_in_flight


func _try_begin_bake() -> bool:
	if _bake_in_flight:
		_last_bake_status = BakeStatus.BUSY
		root.emit_signal("user_message", "A bake is already running", 1)
		return false
	_bake_in_flight = true
	_last_bake_success = false
	return true


## Bake only the given brush nodes (selection bake).
func bake_selected(
	brush_nodes: Array, collision_layer_mask: int = 0, preview_mode: int = 0  # PreviewMode.FULL
) -> bool:
	if not _try_begin_bake():
		return false
	await _bake_selected_impl(brush_nodes, collision_layer_mask, preview_mode)
	_bake_in_flight = false
	_last_bake_status = BakeStatus.SUCCESS if _last_bake_success else BakeStatus.FAILED
	return _last_bake_success


func _bake_selected_impl(
	brush_nodes: Array, collision_layer_mask: int = 0, preview_mode: int = 0
) -> void:
	if not root.baker:
		push_warning("Bake skipped: baker not initialized")
		root.bake_finished.emit(false)
		root.emit_signal("user_message", "Bake failed — baker not initialized", 2)
		return
	if brush_nodes.is_empty():
		root.bake_finished.emit(false)
		root.emit_signal("user_message", "No brushes selected to bake", 1)
		return
	var started = Time.get_ticks_msec()
	var yield_overhead_ms := 0  # Idle time spent in frame yields — excluded from estimator
	root._log("Selection Bake Started (%d brushes)" % brush_nodes.size())
	root.bake_started.emit()
	root.bake_progress.emit(0.0, "Preparing selection")
	var layer = (
		collision_layer_mask
		if collision_layer_mask > 0
		else root._layer_from_index(root.bake_collision_layer_index)
	)
	var bake_options = build_bake_options()
	_apply_preview_mode(bake_options, preview_mode)
	var temp_csg = CSGCombiner3D.new()
	temp_csg.hide()
	temp_csg.use_collision = false
	root.add_child(temp_csg)
	append_brush_list_to_csg(brush_nodes, temp_csg)
	root.bake_progress.emit(0.5, "Baking selection")
	var yield_start_ms := Time.get_ticks_msec()
	await root.get_tree().process_frame
	await root.get_tree().process_frame
	yield_overhead_ms += Time.get_ticks_msec() - yield_start_ms
	var baked = root.baker.bake_from_csg(
		temp_csg, root.bake_material_override, layer, STATIC_BODY_MASK, bake_options
	)
	if baked:
		# Baker derives both the visual mesh and collision from this final boolean
		# result. Re-baking additive brushes alone would fill every doorway/cutout.
		_apply_preview_visuals(baked, preview_mode)
	temp_csg.queue_free()
	if baked:
		root._last_bake_duration_ms = max(0, Time.get_ticks_msec() - started - yield_overhead_ms)
		root.bake_progress.emit(1.0, "Finalizing")
		# Merge into existing baked container rather than replacing it
		var active_container := reconcile_baked_containers()
		if active_container:
			baked.name = "BakedSelection_%d" % Time.get_ticks_msec()
			active_container.add_child(baked)
		else:
			active_container = replace_baked_container(baked)
		postprocess_bake(baked, true, brush_nodes)
		root._assign_owner_recursive(active_container)
		root._last_bake_preview_mode = preview_mode
		_last_bake_success = true
		root._log("Selection bake finished (success=true)")
		root.bake_finished.emit(true)
	else:
		root._last_bake_duration_ms = max(0, Time.get_ticks_msec() - started - yield_overhead_ms)
		_last_bake_success = false
		root._log("Selection bake failed")
		root.bake_finished.emit(false)


## Every setting that decides what goes into the bake, or how it is built.
##
## Compared against the value the last successful bake ran with. A hash rather
## than a flag on each setter: most of these properties have no setter, and the
## hash covers the `.hflevel` load path for free, which a setter-set flag would
## not. The cordon is in here because it decides which brushes are in the bake at
## all, and `bake_material_override` by resource path because a Material has no
## stable hash across a reload.
## Every setting that decides what goes into the bake, or how it is built.
##
## Compared against the values the last successful bake ran with. A hash rather
## than a flag on each setter: most of these properties have no setter, and the
## hash covers the `.hflevel` load path for free, which a setter-set flag would
## not. The cordon is in here because it decides which brushes are in the bake at
## all.
const BAKE_SETTING_NAMES := [
	"bake_visible_only",
	"bake_use_face_materials",
	"bake_collision_mode",
	"bake_collision_layer_index",
	"bake_convex_clean",
	"bake_convex_simplify",
	"bake_lightmap_uv2",
	"bake_lightmap_texel_size",
	"bake_unwrap_uv0",
	"bake_generate_lods",
	"bake_chunk_size",
	"bake_merge_meshes",
	"bake_use_atlas",
	"bake_generate_occluders",
	"bake_occluder_min_area",
	"bake_navmesh",
	"bake_navmesh_cell_size",
	"bake_navmesh_cell_height",
	"bake_navmesh_agent_height",
	"bake_navmesh_agent_radius",
	"bake_auto_connectors",
	"bake_connector_mode",
	"bake_connector_stair_height",
	"bake_connector_width",
	"bake_connector_stair_threshold",
	"bake_wire_io",
	"cordon_enabled",
	"cordon_aabb",
]


func bake_settings_signature() -> int:
	# Read by name, because a test root shim carries only the properties its test
	# needs and a missing one should be "not set" rather than an error.
	var values: Array = []
	for name in BAKE_SETTING_NAMES:
		values.append(root.get(name))
	# A Material has no stable hash across a reload, so it goes in by path.
	var override_path := ""
	var override = root.get("bake_material_override")
	if override != null:
		override_path = str(override.resource_path)
		if override_path == "":
			override_path = str(override.get_instance_id())
	values.append(override_path)
	return values.hash()


## Rebuild from authoritative source when brush or structural dirty state exists.
## Missing dirty IDs represent deletions and therefore still require a bake.
func bake_dirty(collision_layer_mask: int = 0, preview_mode: int = 0) -> bool:
	if _bake_in_flight:
		_last_bake_status = BakeStatus.BUSY
		root.emit_signal("user_message", "A bake is already running", 1)
		return false
	var dirty_ids: Array = root._dirty_brush_ids.keys()
	var full_reconcile_started: bool = root._full_reconcile_needed
	# A changed setting is a change. Nothing marked the bake settings dirty, so a
	# rebake after one was flipped took the "no changed brushes" path and left the
	# previous result standing: hide a visgroup, bake to check something, turn
	# "bake visible only" off, bake again, and the level that ships is missing
	# every brush in that visgroup. Nothing about the result said it was stale.
	if _has_baked_once and bake_settings_signature() != _last_bake_settings_signature:
		root._log("Bake settings changed since the last bake, rebuilding in full")
		return await bake(true, false, collision_layer_mask, preview_mode)
	if dirty_ids.is_empty() and not full_reconcile_started:
		_last_bake_status = BakeStatus.NOTHING_TO_DO
		root.emit_signal("user_message", "No changed brushes since last bake", 1)
		return false
	var dirty_snapshot: Dictionary = root._dirty_brush_ids.duplicate()
	var brush_nodes: Array = []
	for bid in dirty_ids:
		var brush = root._find_brush_by_key(str(bid))
		if brush:
			brush_nodes.append(brush)
	root._log("Incremental bake: %d dirty brushes" % brush_nodes.size())
	# Full context needed for correct CSG — bake everything but track dirty set
	return await bake(true, false, collision_layer_mask, preview_mode)


func _has_bake_sources() -> bool:
	return (
		_has_positive_structural_sources()
		or _has_generated_heightmap_source()
		or _has_nonstructural_sources()
	)


func _has_positive_structural_sources() -> bool:
	for container in [root.draft_brushes_node, root.generated_floors, root.generated_walls]:
		if _has_positive_structural_brush(container):
			return true
	return false


func _has_generated_heightmap_source() -> bool:
	for heightmap in collect_generated_heightmap_meshes():
		if heightmap is MeshInstance3D and heightmap.mesh:
			return true
	return false


func _has_positive_structural_brush(container: Node3D) -> bool:
	if not container:
		return false
	for child in container.get_children():
		if not (child is DraftBrush) or root.is_entity_node(child):
			continue
		var brush := child as DraftBrush
		if brush.operation == CSGShape3D.OPERATION_SUBTRACTION:
			continue
		if not brush_bakes(brush):
			continue
		if not _is_structural_brush(brush):
			continue
		return true
	return false


## Whether any face of the level has been given its own material.
##
## Worth saying out loud before a bake drops them: the Materials panel, the face
## filters and "Apply to Selected Faces" all work on the preview whether or not
## the bake is going to carry the result.
func _faces_carry_materials() -> bool:
	for brush in collect_face_bake_brushes():
		if not (is_instance_valid(brush) and brush is DraftBrush):
			continue
		if _brush_carries_face_materials(brush as DraftBrush):
			return true
	return false


## The same question about one brush, which is what decides how it enters the
## CSG tree.
func _brush_carries_face_materials(brush: DraftBrush) -> bool:
	if not is_instance_valid(brush):
		return false
	for face in brush.faces:
		if face and face.material_idx >= 0:
			return true
	return false


## The mesh that puts a textured brush into the CSG tree with its texturing
## intact.
##
## Godot's CSG carries a material per face. `CSGMesh3D` takes one from each
## surface of its mesh and the boolean writes it through to the output, so a
## brush handed over as a mesh with one surface per material comes out the other
## side still wearing them. Assigning `CSGMesh3D.material` is the thing that
## collapses them all into one, and that is what this path did to every brush -
## so a single cutter anywhere in a level moved the whole level onto the CSG
## path and cost every brush in it its texturing (#693).
##
## The faces resolve exactly as the face-material bake resolves them, through the
## same `snapshot_brush_faces()`, so the two paths cannot disagree about what a
## face is painted with.
##
## Null for a brush with no face materials, which leaves every untextured brush
## on the prefab primitive it has always been cut with.
func _face_material_csg_mesh(draft: DraftBrush) -> Mesh:
	if not root.bake_use_face_materials or not root.baker:
		return null
	if not _brush_carries_face_materials(draft):
		return null
	var snapshot: Dictionary = root.baker.snapshot_brush_faces(
		draft, root.material_manager, root.bake_material_override, false
	)
	var records: Array = snapshot.get("records", [])
	if records.is_empty():
		return null
	# A boolean needs a closed solid. The face-material bake path draws whatever
	# triangles it is given and a hole costs it one invisible face, but a hole in
	# a CSG operand is a hole in the result, so a brush whose faces did not all
	# triangulate goes back on the primitive, which is always closed.
	var solid_faces := 0
	for face in draft.faces:
		if face:
			solid_faces += 1
	if records.size() != solid_faces:
		return null
	# Grouped by material, because a surface is a material and the whole point is
	# to hand CSG more than one of them.
	var groups: Dictionary = {}
	var order: Array = []
	for rec in records:
		var mat: Material = rec.get("material", null)
		var key: Variant = mat if mat != null else "_default"
		if not groups.has(key):
			groups[key] = {
				"material": mat,
				"verts": PackedVector3Array(),
				"uvs": PackedVector2Array(),
				"normals": PackedVector3Array(),
			}
			order.append(key)
		var group: Dictionary = groups[key]
		var verts: PackedVector3Array = rec.get("verts", PackedVector3Array())
		var uvs: PackedVector2Array = rec.get("uvs", PackedVector2Array())
		var normals: PackedVector3Array = rec.get("normals", PackedVector3Array())
		var face_normal: Vector3 = rec.get("face_normal", Vector3.UP)
		for i in range(verts.size()):
			group["verts"].append(verts[i])
			group["uvs"].append(uvs[i] if uvs.size() > i else Vector2.ZERO)
			group["normals"].append(normals[i] if normals.size() > i else face_normal)
	var mesh := ArrayMesh.new()
	for key in order:
		var group: Dictionary = groups[key]
		var verts: PackedVector3Array = group["verts"]
		if verts.is_empty():
			continue
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var mat: Material = group["material"]
		if mat:
			st.set_material(mat)
		var uvs: PackedVector2Array = group["uvs"]
		var normals: PackedVector3Array = group["normals"]
		for i in range(verts.size()):
			if normals.size() > i:
				st.set_normal(normals[i])
			if uvs.size() > i:
				st.set_uv(uvs[i])
			st.add_vertex(verts[i])
		st.commit(mesh)
	return mesh if mesh.get_surface_count() > 0 else null


func _has_effective_structural_subtractors() -> bool:
	for container in [root.draft_brushes_node, root.generated_floors, root.generated_walls]:
		if _container_has_effective_subtractor(container):
			return true
	# Frozen committed cutters are forced to subtraction by the CSG path even
	# when their serialized operation still says union.
	return root.commit_freeze and _container_has_effective_subtractor(root.committed_node, true)


func _container_has_effective_subtractor(container: Node3D, force_subtract: bool = false) -> bool:
	return _count_effective_subtractors(container, force_subtract, true) > 0


## How many cutters are in the level. Same walk as the test above, counted rather
## than answered yes or no, so the message that says the face-material path was
## dropped can name how many brushes caused it (#694).
func _count_effective_structural_subtractors() -> int:
	var total := 0
	for container in [root.draft_brushes_node, root.generated_floors, root.generated_walls]:
		total += _count_effective_subtractors(container)
	if root.commit_freeze:
		total += _count_effective_subtractors(root.committed_node, true)
	return total


func _count_effective_subtractors(
	container: Node3D, force_subtract: bool = false, stop_at_first: bool = false
) -> int:
	if not container:
		return 0
	var total := 0
	for child in container.get_children():
		if not (child is DraftBrush) or root.is_entity_node(child):
			continue
		var brush := child as DraftBrush
		if not brush_bakes(brush):
			continue
		if not _is_structural_brush(brush):
			continue
		if force_subtract or brush.operation == CSGShape3D.OPERATION_SUBTRACTION:
			total += 1
			if stop_at_first:
				return total
	return total


## Remove the exact set of dirty tags represented by a started bake.
## Clearing before the first await gives later edits a distinct live entry,
## even though the public dirty-tag dictionary stores only boolean values.
func _claim_dirty_tags(dirty_snapshot: Dictionary, full_reconcile_started: bool = false) -> void:
	for brush_id in dirty_snapshot:
		root._dirty_brush_ids.erase(brush_id)
	if full_reconcile_started:
		root._full_reconcile_needed = false


## A successful bake leaves only tags created while it was running. On
## failure, merge the claimed snapshot back without replacing concurrent tags.
func _finish_dirty_tag_claim(
	dirty_snapshot: Dictionary, succeeded: bool, full_reconcile_started: bool = false
) -> void:
	if succeeded:
		return
	for brush_id in dirty_snapshot:
		if not root._dirty_brush_ids.has(brush_id):
			root._dirty_brush_ids[brush_id] = dirty_snapshot[brush_id]
	if full_reconcile_started:
		root._full_reconcile_needed = true


# ---------------------------------------------------------------------------
# Preview mode helpers
# ---------------------------------------------------------------------------


func _apply_preview_mode(options: Dictionary, mode: int) -> void:
	if mode == PreviewMode.WIREFRAME:
		options["merge_meshes"] = false
		options["generate_lods"] = false
		options["unwrap_uv2"] = false
	elif mode == PreviewMode.PROXY:
		options["merge_meshes"] = false
		options["generate_lods"] = false
		options["unwrap_uv2"] = false


func _apply_preview_visuals(container: Node3D, mode: int) -> void:
	if mode == PreviewMode.FULL:
		return
	var mat: Material = null
	if mode == PreviewMode.WIREFRAME:
		mat = _get_wireframe_material()
	elif mode == PreviewMode.PROXY:
		var std_mat := StandardMaterial3D.new()
		std_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		std_mat.albedo_color = Color(0.5, 0.5, 0.5, 0.4)
		std_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat = std_mat
	if mat:
		_apply_material_recursive(container, mat)


static func _get_wireframe_material() -> ShaderMaterial:
	if _wireframe_material and _wireframe_material.shader:
		return _wireframe_material
	if _wireframe_shader == null:
		_wireframe_shader = Shader.new()
		_wireframe_shader.code = (
			"shader_type spatial;\n"
			+ "render_mode unshaded, cull_disabled, wireframe, depth_draw_never;\n"
			+ "uniform vec4 color : source_color = vec4(0.2, 0.8, 1.0, 0.6);\n"
			+ "void fragment() { ALBEDO = color.rgb; ALPHA = color.a; }\n"
		)
	_wireframe_material = ShaderMaterial.new()
	_wireframe_material.shader = _wireframe_shader
	return _wireframe_material


func _apply_material_recursive(node: Node3D, mat: Material) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			child.material_override = mat
		elif child is MultiMeshInstance3D:
			child.material_override = mat
		elif child is Node3D:
			_apply_material_recursive(child, mat)


# ---------------------------------------------------------------------------
# Main bake
# ---------------------------------------------------------------------------


func bake(
	apply_cuts: bool = true,
	hide_live: bool = false,
	collision_layer_mask: int = 0,
	preview_mode: int = 0,  # PreviewMode.FULL
	force_csg: bool = false
) -> bool:
	if not _try_begin_bake():
		return false
	var signature := bake_settings_signature()
	await _bake_impl(apply_cuts, hide_live, collision_layer_mask, preview_mode, force_csg)
	_bake_in_flight = false
	_last_bake_status = BakeStatus.SUCCESS if _last_bake_success else BakeStatus.FAILED
	if _last_bake_success:
		# Taken before the bake ran, so a setting changed while it was in flight
		# is still a change the next bake has to answer for.
		_last_bake_settings_signature = signature
		_has_baked_once = true
	return _last_bake_success


func _bake_impl(
	apply_cuts: bool = true,
	hide_live: bool = false,
	collision_layer_mask: int = 0,
	preview_mode: int = 0,
	force_csg: bool = false
) -> void:
	var dirty_snapshot: Dictionary = root._dirty_brush_ids.duplicate()
	var full_reconcile_started: bool = root._full_reconcile_needed
	_claim_dirty_tags(dirty_snapshot, full_reconcile_started)
	_last_bake_success = false
	var started = Time.get_ticks_msec()
	var yield_overhead_ms := 0  # Idle time spent in frame yields — excluded from estimator
	if not _has_bake_sources():
		_complete_empty_bake(dirty_snapshot, full_reconcile_started, started)
		return
	if _has_positive_structural_sources() and not root.baker:
		_finish_dirty_tag_claim(dirty_snapshot, false, full_reconcile_started)
		push_warning("Bake skipped: baker not initialized")
		root.bake_finished.emit(false)
		root.emit_signal("user_message", "Bake failed — baker not initialized", 2)
		return
	if apply_cuts:
		root.apply_pending_cuts()
	if not _has_bake_sources():
		_complete_empty_bake(dirty_snapshot, full_reconcile_started, started)
		return
	root._log("Virtual Bake Started (apply_cuts=%s, hide_live=%s)" % [apply_cuts, hide_live])
	root.bake_started.emit()
	root.bake_progress.emit(0.0, "Preparing")
	var layer = (
		collision_layer_mask
		if collision_layer_mask > 0
		else root._layer_from_index(root.bake_collision_layer_index)
	)
	var baked: Node3D = null
	var bake_options = build_bake_options()
	_apply_preview_mode(bake_options, preview_mode)
	var use_face_material_path: bool = (
		bool(root.bake_use_face_materials)
		and not force_csg
		and not _has_effective_structural_subtractors()
	)
	if root.bake_use_face_materials and not use_face_material_path:
		# Independent face triangulation has no boolean subtraction stage.
		# Keep every effective cutter by switching this bake to CSG.
		#
		# The texturing no longer goes with it. A textured brush enters the CSG
		# tree as a mesh with one surface per material and comes out of the
		# boolean still wearing them, so the mapper keeps what they painted and
		# the cut still cuts (#693). Nothing to warn about, which is why the
		# user_message that used to fire here is gone: it said the materials were
		# dropped, and they are not.
		if force_csg:
			root._log("Face-material bake switched to CSG: this bake was asked for as CSG")
		else:
			var cutters := _count_effective_structural_subtractors()
			root._log(
				(
					"Face-material bake switched to CSG to preserve %d active cut%s"
					% [cutters, "" if cutters == 1 else "s"]
				)
			)
	elif not root.bake_use_face_materials and _faces_carry_materials():
		# The only log on this path used to fire the other way round, so the
		# silent case was a mapper texturing a level, pressing Bake and getting one
		# material over everything with nothing said about it.
		root.emit_signal(
			"user_message", "Per-face materials were not baked: Use Face Materials is off", 1
		)
		root._log("Per-face materials dropped: the CSG path resolves one material per brush")
	if not _has_positive_structural_sources():
		baked = _bake_heightmap_only(layer)
		if baked == null and _has_nonstructural_sources():
			baked = Node3D.new()
			baked.name = String(BAKED_CONTAINER_NAME)
	elif use_face_material_path:
		# --- Synchronous snapshot: triangulate + resolve materials before yields ---
		var face_brushes = collect_face_bake_brushes()
		var use_atlas: bool = bool(bake_options.get("use_atlas", false))
		var collision_mode: int = int(bake_options.get("collision_mode", 0))
		var snapshots: Array = []
		# Track per-brush visgroup assignments for partitioned collision (mode 2)
		var brush_visgroups: Array = []  # parallel to snapshots: PackedStringArray per brush
		for brush in face_brushes:
			if is_instance_valid(brush) and brush is DraftBrush:
				snapshots.append(
					root.baker.snapshot_brush_faces(
						brush, root.material_manager, root.bake_material_override, use_atlas
					)
				)
				if collision_mode >= 2 and root.visgroup_system:
					brush_visgroups.append(root.visgroup_system.get_visgroups_of(brush))
				else:
					brush_visgroups.append(PackedStringArray())
		# --- Yielding pass: world-space transform + grouping from frozen data ---
		# Grouped per chunk, not just per material. The chunked branch used to
		# live only on the CSG path, and `bake_use_face_materials` defaults to
		# true, so on every default level the bake took the branch that had never
		# heard of `bake_chunk_size` -- while the dock offered a Chunk Size spin,
		# the health badge said "Consider Chunking" and the dry run reported a
		# chunk count the bake did not produce (#656). Per-face baking has no
		# boolean interactions to preserve across a boundary, which is exactly why
		# `_chunking_has_cross_boundary_interactions()` guards the CSG path and is
		# not needed here.
		var chunk_members := _face_chunk_members(snapshots)
		var chunk_coords: Array = chunk_members.keys()
		chunk_coords.sort_custom(_compare_chunk_coords)
		var snap_total: int = snapshots.size()
		var collected := 0
		var chunk_groups: Dictionary = {}
		for coord in chunk_coords:
			var members: Array = chunk_members[coord]
			var groups: Dictionary = {}
			for index in members:
				root.baker.collect_snapshot_groups(snapshots[index], use_atlas, groups)
				collected += 1
				if collected % _FACE_BAKE_BATCH == 0 or collected == snap_total:
					root.bake_progress.emit(
						float(collected) / float(max(1, snap_total)) * 0.7,
						"Collecting faces %d/%d" % [collected, snap_total]
					)
					var yield_start_ms := Time.get_ticks_msec()
					await root.get_tree().process_frame
					yield_overhead_ms += Time.get_ticks_msec() - yield_start_ms
			chunk_groups[coord] = groups
		root.bake_progress.emit(0.75, "Building mesh")
		var build_yield_start_ms := Time.get_ticks_msec()
		await root.get_tree().process_frame
		yield_overhead_ms += Time.get_ticks_msec() - build_yield_start_ms
		baked = _build_face_chunks(
			chunk_coords,
			chunk_groups,
			chunk_members,
			snapshots,
			brush_visgroups,
			bake_options,
			layer
		)
		# Match the CSG path: append heightmaps after collision partitioning so
		# partition cleanup cannot remove the heightmap collision body.
		if baked:
			_append_heightmap_meshes_to_baked(baked, layer)
		elif _has_generated_heightmap_source():
			# A valid heightmap is still authoritative output when structural
			# face collection produces no mesh (for example, empty/invalid faces).
			baked = _bake_heightmap_only(layer)
	else:
		if root.bake_chunk_size > 0.0:
			baked = await bake_chunked(root.bake_chunk_size, layer, bake_options)
		else:
			root.bake_progress.emit(0.5, "Baking")
			baked = await bake_single(layer, bake_options)
	if baked:
		root._last_bake_duration_ms = max(0, Time.get_ticks_msec() - started - yield_overhead_ms)
		root.bake_progress.emit(1.0, "Finalizing")
		replace_baked_container(baked)
		postprocess_bake(root.baked_container)
		_apply_preview_visuals(root.baked_container, preview_mode)
		root._assign_owner_recursive(root.baked_container)
		if hide_live:
			if root.draft_brushes_node:
				root.draft_brushes_node.visible = false
			if root.pending_node:
				root.pending_node.visible = false
		root._log("Bake finished (success=true)")
		root._last_bake_preview_mode = preview_mode
		_last_bake_success = true
	else:
		root._last_bake_duration_ms = max(0, Time.get_ticks_msec() - started - yield_overhead_ms)
		root._log("Bake failed")
		_last_bake_success = false
		warn_bake_failure()
	_finish_dirty_tag_claim(dirty_snapshot, _last_bake_success, full_reconcile_started)
	root.bake_finished.emit(_last_bake_success)


func _complete_empty_bake(
	dirty_snapshot: Dictionary, full_reconcile_started: bool, started: int
) -> void:
	root._log("Virtual Bake Started (empty authoritative source)")
	root.bake_started.emit()
	root.bake_progress.emit(0.0, "Preparing")
	clear_baked_containers()
	root._last_bake_duration_ms = max(0, Time.get_ticks_msec() - started)
	root.bake_progress.emit(1.0, "Clearing baked geometry")
	root._log("Bake finished (success=true, scene is empty)")
	_last_bake_success = true
	_finish_dirty_tag_claim(dirty_snapshot, true, full_reconcile_started)
	root.bake_finished.emit(true)


func warn_bake_failure() -> void:
	var draft_count = count_brushes_in(root.draft_brushes_node)
	var pending_count = count_brushes_in(root.pending_node)
	var committed_count = count_brushes_in(root.committed_node)
	var entities_count = root.entities_node.get_child_count() if root.entities_node else 0
	var detail := (
		"Bake failed: no baked geometry (draft=%s, pending=%s, committed=%s, entities=%s)"
		% [draft_count, pending_count, committed_count, entities_count]
	)
	HFLog.warn(detail)
	var hint := ""
	if draft_count == 0:
		hint = "No draft brushes found — draw some brushes first"
	elif pending_count > 0:
		hint = "You have %d pending cuts — try 'Commit Cuts' before baking" % pending_count
	else:
		hint = "CSG produced no geometry — check brush operations and overlaps"
	root.emit_signal("user_message", hint, 2)


func build_bake_options() -> Dictionary:
	return {
		"merge_meshes": root.bake_merge_meshes,
		"generate_lods": root.bake_generate_lods,
		"unwrap_uv0": root.bake_unwrap_uv0,
		"unwrap_uv2": root.bake_lightmap_uv2,
		"uv2_texel_size": root.bake_lightmap_texel_size,
		"use_thread_pool": root.bake_use_thread_pool,
		"use_face_materials": root.bake_use_face_materials,
		"use_atlas": root.bake_use_atlas,
		"collision_mode": root.bake_collision_mode,
		"convex_clean": root.bake_convex_clean,
		"convex_simplify": root.bake_convex_simplify,
	}


func postprocess_bake(
	container: Node3D, selection_only: bool = false, selected_brushes: Array = []
) -> void:
	if not container:
		return
	if selection_only:
		_append_nonstructural_brushes(container, selected_brushes)
	else:
		_append_nonstructural_brushes(container)
	if _root_bool("bake_generate_occluders", false) and not selection_only:
		_generate_occluders(container)
	var paint_tool = root.get("paint_tool")
	var has_committed_connectors: bool = (
		paint_tool != null
		and paint_tool.get("connector_defs") is Array
		and not paint_tool.connector_defs.is_empty()
	)
	if (root.bake_auto_connectors or has_committed_connectors) and not selection_only:
		_append_auto_connectors(container)
	if root.bake_navmesh:
		bake_navmesh(container)
	var bake_wire_io := false
	if "bake_wire_io" in root:
		bake_wire_io = bool(root.get("bake_wire_io"))
	if bake_wire_io and not selection_only:
		_attach_io_dispatcher(container)


## Attach an HFIORuntime dispatcher to the baked container so that entity I/O
## connections are wired as live Godot signals at runtime.  The dispatcher is
## parented under the baked container but also scans entities_node (a sibling
## subtree) via extra_scan_roots.
func _direct_child_has_io(parent: Node) -> bool:
	if not parent:
		return false
	for child in parent.get_children():
		if not child.get_meta("entity_io_outputs", []).is_empty():
			return true
	return false


func _attach_io_dispatcher(container: Node3D) -> void:
	# Point entities and brush entities (triggers, buttons) both store outputs.
	var has_io := (
		_direct_child_has_io(root.entities_node) or _direct_child_has_io(root.draft_brushes_node)
	)
	if not has_io:
		return
	# Remove any existing dispatcher
	var existing: Node = container.get_node_or_null("HFIODispatcher")
	if existing:
		container.remove_child(existing)
		existing.free()
	var dispatcher := HFIORuntime.new()
	dispatcher.name = "HFIODispatcher"
	# The dispatcher lives under the baked container, but point entities live
	# under root.entities_node (a sibling). Tell it to scan that subtree too.
	if root.entities_node:
		dispatcher.extra_scan_roots.append(root.entities_node)
	container.add_child(dispatcher)
	if root.entities_node:
		var entities_path: NodePath = dispatcher.get_path_to(root.entities_node)
		dispatcher.extra_scan_root_paths.append(entities_path)
	root._assign_owner_recursive(dispatcher)


## Whether the bake will take this brush at all.
##
## The cordon and `bake_visible_only` are each checked in seven places along the
## bake path and in none of the counting. So the dry run, which is the preflight
## the user reads before committing to a bake, reported brushes the bake was
## going to skip. One predicate, so the two cannot drift apart again.
##
## Subtraction is deliberately not part of this. A subtractor is a brush the bake
## takes and uses, and the dry run reports pending cuts on their own line.
func brush_bakes(brush: DraftBrush) -> bool:
	if brush == null or not is_instance_valid(brush):
		return false
	if root.is_entity_node(brush):
		return false
	if root.bake_visible_only and not brush.visible:
		return false
	if root.cordon_enabled and not _brush_in_cordon(brush):
		return false
	return true


## How many brushes in this container the bake will take.
func count_brushes_in(container: Node3D) -> int:
	if not container:
		return 0
	var count := 0
	for child in container.get_children():
		if child is DraftBrush and brush_bakes(child as DraftBrush):
			count += 1
	return count


func bake_single(layer: int, options: Dictionary) -> Node3D:
	var temp_csg = CSGCombiner3D.new()
	temp_csg.hide()
	temp_csg.use_collision = false
	root.add_child(temp_csg)
	append_draft_brushes_to_csg(root.draft_brushes_node, temp_csg)
	if root.commit_freeze and root.committed_node:
		append_draft_brushes_to_csg(root.committed_node, temp_csg, true)
	append_generated_brushes_to_csg(temp_csg)
	await root.get_tree().process_frame
	await root.get_tree().process_frame
	var baked = root.baker.bake_from_csg(
		temp_csg, root.bake_material_override, layer, STATIC_BODY_MASK, options
	)
	temp_csg.queue_free()
	if baked:
		# FloorCollision already came from the same final CSG mesh as the visual.
		# A subtractor therefore carves collision instead of becoming a solid or
		# being omitted from a second, additive-only collision tree.
		# Visgroup-partitioned collision (mode 2) for CSG path.
		# Must run BEFORE heightmap append so that partitioning only removes
		# the brush-generated FloorCollision body, not heightmap collision.
		var collision_mode: int = int(options.get("collision_mode", 0))
		if collision_mode >= 2:
			var containers: Array = [
				root.draft_brushes_node, root.generated_floors, root.generated_walls
			]
			if root.commit_freeze and root.committed_node:
				containers.append(root.committed_node)
			var coll_data: Dictionary = _collect_brush_collision_data(containers)
			_partition_collision_by_visgroup(
				baked, coll_data["hull_verts"], coll_data["visgroups"], options
			)
		# Heightmap collision is appended after partitioning.  If FloorCollision
		# was removed by partitioning, _append_heightmap_meshes_to_baked creates
		# a fresh one for heightmap-only collision shapes.
		_append_heightmap_meshes_to_baked(baked, layer)
	return baked


func bake_chunked(chunk_size: float, layer: int, options: Dictionary) -> Node3D:
	var size = max(0.001, chunk_size)
	var chunks = _collect_all_chunks(size)
	if chunks.is_empty():
		return null
	# Independent CSG combiners cannot reproduce boolean interactions across
	# chunk boundaries. Preserve correctness by using one CSG tree whenever
	# brushes assigned to different chunks overlap (especially cutters).
	if _chunking_has_cross_boundary_interactions(chunks):
		return await bake_single(layer, options)
	var container = Node3D.new()
	container.name = BAKED_CONTAINER_NAME
	var chunk_count = 0
	var total_chunks = 0
	for coord in chunks:
		var entry: Dictionary = chunks[coord]
		var brushes: Array = entry.get("brushes", [])
		var committed: Array = entry.get("committed", [])
		var generated: Array = entry.get("generated", [])
		if brushes.is_empty() and committed.is_empty() and generated.is_empty():
			continue
		total_chunks += 1
	if total_chunks == 0:
		return null
	var processed = 0
	for coord in chunks:
		var entry: Dictionary = chunks[coord]
		var brushes: Array = entry.get("brushes", [])
		var committed: Array = entry.get("committed", [])
		var generated: Array = entry.get("generated", [])
		if brushes.is_empty() and committed.is_empty() and generated.is_empty():
			continue
		var temp_csg = CSGCombiner3D.new()
		temp_csg.hide()
		temp_csg.use_collision = false
		root.add_child(temp_csg)
		append_brush_list_to_csg(brushes, temp_csg)
		append_brush_list_to_csg(generated, temp_csg)
		if root.commit_freeze:
			append_brush_list_to_csg(committed, temp_csg, true)
		await root.get_tree().process_frame
		await root.get_tree().process_frame
		var baked_chunk = root.baker.bake_from_csg(
			temp_csg, root.bake_material_override, layer, STATIC_BODY_MASK, options
		)
		if baked_chunk:
			# Visgroup-partitioned collision (mode 2) for this chunk
			var chunk_collision_mode: int = int(options.get("collision_mode", 0))
			if chunk_collision_mode >= 2:
				var chunk_brushes: Array = []
				chunk_brushes.append_array(brushes)
				chunk_brushes.append_array(generated)
				if root.commit_freeze:
					chunk_brushes.append_array(committed)
				var coll_data: Dictionary = _collect_brush_collision_data(chunk_brushes)
				_partition_collision_by_visgroup(
					baked_chunk, coll_data["hull_verts"], coll_data["visgroups"], options
				)
			baked_chunk.name = "BakedChunk_%s_%s_%s" % [coord.x, coord.y, coord.z]
			container.add_child(baked_chunk)
			chunk_count += 1
		temp_csg.queue_free()
		processed += 1
		if total_chunks > 0:
			var progress = float(processed) / float(total_chunks)
			root.bake_progress.emit(progress, "Chunk %d/%d" % [processed, total_chunks])
	if container and chunk_count > 0:
		_append_heightmap_meshes_to_baked(container, layer)
	return container if chunk_count > 0 else null


## Which snapshots belong to which chunk, as `coord -> [snapshot index]`.
##
## One entry at `Vector3i.ZERO` when chunking is off, so the caller's loop is the
## same shape either way and an unchunked bake produces exactly what it did
## before. The brush's world origin is already in the snapshot, taken before the
## yields, so this needs nothing off the live node.
func _face_chunk_members(snapshots: Array) -> Dictionary:
	var members: Dictionary = {}
	var chunk_size: float = root.bake_chunk_size
	for i in snapshots.size():
		var coord := Vector3i.ZERO
		if chunk_size > 0.0:
			var origin: Vector3 = (snapshots[i] as Dictionary).get("origin", Vector3.ZERO)
			coord = chunk_coord(origin, chunk_size)
		if not members.has(coord):
			members[coord] = []
		members[coord].append(i)
	return members


## A stable order for chunk containers, so two bakes of the same level produce
## the same scene rather than whatever order the dictionary happened to hold.
func _compare_chunk_coords(a: Vector3i, b: Vector3i) -> bool:
	if a.x != b.x:
		return a.x < b.x
	if a.y != b.y:
		return a.y < b.y
	return a.z < b.z


## One mesh per chunk, or one mesh when there is one chunk.
##
## A single chunk returns exactly what the unchunked path returned, with the same
## node shape, so nothing downstream has to learn about chunking to keep working.
## Several chunks are wrapped the way the CSG path wraps them, in `BakedChunk_`
## children of one container, which is what `postprocess_bake()`,
## `clear_baked_containers()` and the preview modes already walk.
func _build_face_chunks(
	chunk_coords: Array,
	chunk_groups: Dictionary,
	chunk_members: Dictionary,
	snapshots: Array,
	brush_visgroups: Array,
	bake_options: Dictionary,
	layer: int
) -> Node3D:
	var collision_mode: int = int(bake_options.get("collision_mode", 0))
	var built: Array = []
	for coord in chunk_coords:
		var members: Array = chunk_members[coord]
		var options := bake_options.duplicate()
		# Per-brush collision data is per chunk too, or a chunk's convex hulls
		# would be built from the whole level's brushes.
		var hull_verts: Array = []
		var visgroups: Array = []
		for index in members:
			hull_verts.append(
				(snapshots[index] as Dictionary).get("hull_verts", PackedVector3Array())
			)
			visgroups.append(
				brush_visgroups[index] if index < brush_visgroups.size() else PackedStringArray()
			)
		if collision_mode >= 1:
			options["per_brush_verts"] = hull_verts
		if collision_mode >= 2:
			options["brush_visgroups"] = visgroups
		var mesh: Node3D = root.baker.build_mesh_from_groups(
			chunk_groups[coord], layer, STATIC_BODY_MASK, options
		)
		if mesh == null:
			continue
		if collision_mode >= 2:
			_partition_collision_by_visgroup(mesh, hull_verts, visgroups, options)
		built.append({"coord": coord, "node": mesh})
	if built.is_empty():
		return null
	if built.size() == 1:
		return built[0]["node"]
	var container := Node3D.new()
	container.name = String(BAKED_CONTAINER_NAME)
	for entry in built:
		var coord: Vector3i = entry["coord"]
		var node: Node3D = entry["node"]
		node.name = "BakedChunk_%s_%s_%s" % [coord.x, coord.y, coord.z]
		container.add_child(node)
	return container


func get_bake_chunk_count() -> int:
	if root.bake_chunk_size <= 0.0:
		var total = count_brushes_in(root.draft_brushes_node)
		total += count_brushes_in(root.generated_floors)
		total += count_brushes_in(root.generated_walls)
		if root.commit_freeze:
			total += count_brushes_in(root.committed_node)
		return 1 if total > 0 else 0
	var size = max(0.001, root.bake_chunk_size)
	var chunks = _collect_all_chunks(size)
	# A boolean that reaches across a chunk boundary is a CSG problem: a cutter
	# in one chunk has to cut a solid in the next, and separate CSG trees cannot.
	# The per-face path has no booleans to preserve, so it chunks anyway -- and it
	# is the default, which is why this asks which path will run rather than
	# assuming the CSG one (#656).
	if not root.bake_use_face_materials and _chunking_has_cross_boundary_interactions(chunks):
		return 1
	var count := 0
	for coord in chunks:
		var entry: Dictionary = chunks[coord]
		var brushes: Array = entry.get("brushes", [])
		var committed: Array = entry.get("committed", [])
		var generated: Array = entry.get("generated", [])
		if brushes.is_empty() and committed.is_empty() and generated.is_empty():
			continue
		count += 1
	return count


func _collect_all_chunks(chunk_size: float) -> Dictionary:
	var chunks: Dictionary = {}
	collect_chunk_brushes(root.draft_brushes_node, chunk_size, chunks, "brushes")
	if root.commit_freeze and root.committed_node:
		collect_chunk_brushes(root.committed_node, chunk_size, chunks, "committed")
	collect_chunk_brushes(root.generated_floors, chunk_size, chunks, "generated")
	collect_chunk_brushes(root.generated_walls, chunk_size, chunks, "generated")
	return chunks


func _chunking_has_cross_boundary_interactions(chunks: Dictionary) -> bool:
	if chunks.size() < 2:
		return false
	var assigned: Array[Dictionary] = []
	for coord in chunks:
		var entry: Dictionary = chunks[coord]
		for key in [&"brushes", &"committed", &"generated"]:
			for candidate in entry.get(key, []):
				if not (candidate is DraftBrush) or not is_instance_valid(candidate):
					continue
				var brush := candidate as DraftBrush
				if root.bake_visible_only and not brush.visible:
					continue
				assigned.append({"coord": coord, "bounds": _brush_world_aabb(brush)})
	# Sweep on X so ordinary separated chunks remain close to O(n log n), while
	# still handling very large brushes that span many chunk coordinates.
	assigned.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			return (left["bounds"] as AABB).position.x < (right["bounds"] as AABB).position.x
	)
	for index in range(assigned.size()):
		var left: Dictionary = assigned[index]
		var left_bounds: AABB = left["bounds"]
		for other_index in range(index + 1, assigned.size()):
			var right: Dictionary = assigned[other_index]
			var right_bounds: AABB = right["bounds"]
			if right_bounds.position.x >= left_bounds.end.x:
				break
			if left["coord"] == right["coord"]:
				continue
			if left_bounds.intersects(right_bounds):
				return true
	return false


func bake_dry_run() -> Dictionary:
	var draft_count = count_brushes_in(root.draft_brushes_node)
	var pending_count = count_brushes_in(root.pending_node)
	var committed_count = count_brushes_in(root.committed_node)
	var generated_floors = count_brushes_in(root.generated_floors)
	var generated_walls = count_brushes_in(root.generated_walls)
	var heightmap_floors := 0
	if root.generated_heightmap_floors:
		heightmap_floors = root.generated_heightmap_floors.get_child_count()
	var chunk_count = get_bake_chunk_count()
	return {
		"draft": draft_count,
		"pending": pending_count,
		"committed": committed_count,
		"generated_floors": generated_floors,
		"generated_walls": generated_walls,
		"heightmap_floors": heightmap_floors,
		"chunk_count": chunk_count,
		"use_face_materials": root.bake_use_face_materials,
		"chunk_size": root.bake_chunk_size
	}


## Collect hull verts and visgroup assignments from live additive brushes.
## This is used only by the optional per-visgroup convex partitioner. Exact
## collision comes directly from the final CSG boolean mesh. Subtractive brushes
## are skipped here because they carve voids and must never become convex solids.
## Real mesh vertices replace AABB corners so non-box shapes get accurate hulls.
## [param brush_sources] is an Array of Node3D parents whose children are scanned,
## OR an Array of DraftBrush nodes directly (detected by first element type).
## Returns {"hull_verts": Array[PackedVector3Array], "visgroups": Array[PackedStringArray]}.
func _collect_brush_collision_data(brush_sources: Array) -> Dictionary:
	var hull_verts: Array = []
	var vis_groups: Array = []
	# Detect whether we were given containers (Node3D parents) or flat brush lists
	var flat_list: bool = false
	if not brush_sources.is_empty() and brush_sources[0] is DraftBrush:
		flat_list = true
	var brush_list: Array = []
	if flat_list:
		brush_list = brush_sources
	else:
		for container in brush_sources:
			if not container:
				continue
			for child in container.get_children():
				brush_list.append(child)
	for child in brush_list:
		if not (child is DraftBrush):
			continue
		var draft: DraftBrush = child
		# Skip subtractive brushes — they carve voids, not solid collision.
		# Exact collision handles the carved result before this optional partition.
		if draft.operation == CSGShape3D.OPERATION_SUBTRACTION:
			continue
		if root.is_entity_node(draft):
			continue
		if not _is_structural_brush(draft):
			continue
		if root.bake_visible_only and not draft.visible:
			continue
		if root.cordon_enabled and not _brush_in_cordon(draft):
			continue
		# Extract real mesh vertices for accurate hull geometry on all shapes.
		var mesh_verts := PackedVector3Array()
		if draft.mesh_instance and draft.mesh_instance.mesh:
			var local_scale: Vector3 = draft.mesh_instance.scale
			var mesh_xform: Transform3D = (
				draft.global_transform
				* Transform3D(Basis.IDENTITY.scaled(local_scale), Vector3.ZERO)
			)
			mesh_verts = Baker._extract_mesh_verts(draft.mesh_instance.mesh, mesh_xform)
		if mesh_verts.is_empty():
			continue
		hull_verts.append(mesh_verts)
		if root.visgroup_system:
			vis_groups.append(root.visgroup_system.get_visgroups_of(draft))
		else:
			vis_groups.append(PackedStringArray())
	return {"hull_verts": hull_verts, "visgroups": vis_groups}


func _is_trigger_brush(brush: DraftBrush) -> bool:
	var bec = str(brush.get_meta("brush_entity_class", ""))
	return bec.begins_with("trigger_")


func _is_structural_brush(brush: DraftBrush) -> bool:
	var bec = str(brush.get_meta("brush_entity_class", ""))
	return bec == "" or bec == "func_wall"


func _has_nonstructural_sources() -> bool:
	return not _collect_nonstructural_brushes().is_empty()


func _collect_nonstructural_brushes(filter: Variant = null) -> Array:
	var out: Array = []
	var sources: Array = []
	if filter != null:
		sources = filter
	else:
		# postprocess_bake is also called from test shims that omit LevelRoot
		# containers. Object.get() returns null for missing properties.
		for prop_name in ["draft_brushes_node", "generated_floors", "generated_walls"]:
			var container = root.get(prop_name) if root else null
			if container:
				sources.append_array(container.get_children())
	for child in sources:
		if not (child is DraftBrush):
			continue
		if root.has_method("is_entity_node") and root.is_entity_node(child):
			continue
		var draft := child as DraftBrush
		if draft.operation == CSGShape3D.OPERATION_SUBTRACTION:
			continue
		if _root_bool("bake_visible_only", false) and not draft.visible:
			continue
		if _root_bool("cordon_enabled", false) and not _brush_in_cordon(draft):
			continue
		if _is_structural_brush(draft):
			continue
		out.append(draft)
	return out


func _append_nonstructural_brushes(container: Node3D, filter: Variant = null) -> void:
	if not container:
		return
	var existing: Node = container.get_node_or_null("Nonstructural")
	if existing:
		container.remove_child(existing)
		existing.free()
	var brushes: Array = _collect_nonstructural_brushes(filter)
	if brushes.is_empty():
		return
	var holder := Node3D.new()
	holder.name = "Nonstructural"
	container.add_child(holder)
	# A brush the runtime has to find by name stays its own node; everything else
	# is grouped by material the way the structural path already groups. Trim and
	# clutter is most of a finished map, and `func_detail` reads like the cheap
	# option while costing one MeshInstance3D, one StaticBody3D and one
	# CollisionShape3D each - eighty crates in a room were eighty-one draw calls
	# where the structural path would have made one (#712).
	var grouped: Array = []
	var idx := 0
	for draft in brushes:
		if _is_trigger_brush(draft):
			_append_trigger_volume(holder, draft, idx)
		elif _needs_its_own_node(draft):
			_append_detail_mesh(holder, draft, idx)
		else:
			grouped.append(draft)
		idx += 1
	_append_grouped_detail(holder, grouped)


## Whether this brush has to survive the bake as a node of its own.
##
## A name is the address an I/O connection targets and outputs are what it
## dispatches, so a brush carrying either has to stay findable. `func_detail` has
## no inputs, no outputs and no name - it is excluded from the structural CSG and
## nothing else - so it does not need to be its own node at all.
func _needs_its_own_node(draft: DraftBrush) -> bool:
	if authored_entity_name(draft) != "":
		return true
	return not (draft.get_meta("entity_io_outputs", []) as Array).is_empty()


## One mesh per material and one collision body for every detail brush that does
## not need a node of its own. The same grouping the structural path uses, run a
## second time over the brushes that path skipped.
func _append_grouped_detail(holder: Node3D, brushes: Array) -> void:
	if brushes.is_empty():
		return
	if not root.baker:
		# Nothing to group with. Fall back to what this path did before, so a level
		# with only clutter in it still bakes rather than failing on the way in.
		var idx := 0
		for draft in brushes:
			_append_detail_mesh(holder, draft, idx)
			idx += 1
		return
	var options := build_bake_options()
	var use_atlas: bool = bool(options.get("use_atlas", false))
	var groups: Dictionary = {}
	var hull_verts: Array = []
	for draft in brushes:
		root.baker.collect_brush_face_groups(
			draft, root.material_manager, root.bake_material_override, use_atlas, groups
		)
		var snapshot: Dictionary = root.baker.snapshot_brush_faces(
			draft, root.material_manager, root.bake_material_override, use_atlas
		)
		hull_verts.append(snapshot.get("hull_verts", PackedVector3Array()))
	if groups.is_empty():
		return
	var layer := 1
	if root.has_method("_layer_from_index"):
		layer = root._layer_from_index(root.bake_collision_layer_index)
	# Per-brush convex hulls, so a merged pile of clutter still collides as the
	# separate solids it is rather than as one hull around all of them.
	var detail_options := options.duplicate(true)
	detail_options["collision_mode"] = maxi(1, int(options.get("collision_mode", 0)))
	detail_options["per_brush_verts"] = hull_verts
	var built: Node3D = root.baker.build_mesh_from_groups(
		groups, layer, STATIC_BODY_MASK, detail_options
	)
	if not built:
		return
	built.name = "DetailGeometry"
	holder.add_child(built)


## The authored name an entity is wired to. Brushes get a Godot generated node
## name unless the author renamed them, so fall back to the node name only when
## it is not one of those generated names.
static func authored_entity_name(draft: Node) -> String:
	if not draft:
		return ""
	var meta_name := str(draft.get_meta("entity_name", ""))
	if meta_name != "":
		return meta_name
	var node_name := str(draft.name)
	if node_name == "" or node_name.begins_with("@") or node_name == "DraftBrush":
		return ""
	return node_name


func _append_detail_mesh(holder: Node3D, draft: DraftBrush, idx: int) -> void:
	var mesh: Mesh = null
	var source: Node3D = draft
	if draft.mesh_instance and draft.mesh_instance.mesh:
		mesh = draft.mesh_instance.mesh
		source = draft.mesh_instance
	var authored := authored_entity_name(draft)
	var mi := MeshInstance3D.new()
	mi.name = authored if authored != "" else "FuncDetail_%d" % idx
	# A mover's identity belongs to the holder, so the holder takes the authored
	# name and the mesh under it becomes a leaf. `_cache_entities()` keys a node by
	# its name as well as by its `entity_name` meta, so a mesh still called `gate`
	# would answer to `gate` however its metadata read - and it is the one thing
	# under there that cannot act on an input (#687).
	var bec_early := str(draft.get_meta("brush_entity_class", ""))
	if bec_early in MOVER_CLASSES and authored != "":
		mi.name = "%s_Leaf_%d" % [authored, idx]
	mi.mesh = mesh
	if authored != "":
		mi.set_meta("entity_name", authored)
	# The same three the trigger volume below carries. A `func_door` went through
	# here rather than `_append_trigger_volume()` and kept only its name, so the
	# playtest scene had a node the runtime could find and nothing saying what it
	# was or what it was wired to -- `HFIORuntime` had nothing to dispatch `Open`
	# against (#668). `_cache_entity_under_key()` holds several nodes per name by
	# design, so a two leaf door is two meshes answering to one name and both
	# receive the input, which is what a two leaf door should do.
	var bec := str(draft.get_meta("brush_entity_class", ""))
	if bec != "":
		mi.set_meta("brush_entity_class", bec)
	var outputs: Array = draft.get_meta("entity_io_outputs", [])
	if not outputs.is_empty():
		mi.set_meta("entity_io_outputs", outputs.duplicate(true))
	# A class that moves gets a holder of its own, so its mesh and its collision
	# travel together. A door that slid its mesh and left its collision behind
	# would be worse than one that does not move at all (#687).
	var parent: Node3D = holder
	var mover: Node3D = null
	if bec in MOVER_CLASSES:
		mover = Node3D.new()
		mover.name = authored if authored != "" else "Door_%d" % idx
		holder.add_child(mover)
		parent = mover
	parent.add_child(mi)
	mi.transform = _source_transform_in_baked_container(source, holder.get_parent() as Node3D)
	var body := StaticBody3D.new()
	body.name = "FuncDetailCollision_%d" % idx
	# What a ray that hits this body has hit. A button is pressed by the player
	# looking at it, and what a ray returns is the collider, not the mesh beside it
	# that carries the wiring (#686).
	if authored != "":
		body.set_meta("entity_name", authored)
	if bec != "":
		body.set_meta("brush_entity_class", bec)
	var layer := 1
	if root.has_method("_layer_from_index"):
		layer = root._layer_from_index(root.bake_collision_layer_index)
	body.collision_layer = layer
	body.collision_mask = STATIC_BODY_MASK
	parent.add_child(body)
	body.transform = mi.transform
	var col := CollisionShape3D.new()
	col.shape = _shape_for_draft(draft, mesh)
	col.transform = body.transform.affine_inverse() * mi.transform
	body.add_child(col)
	if mover:
		_make_it_a_door(mover, mi, draft, authored, bec)


## Move the identity onto the holder and give it the script that moves it.
##
## The name and the wiring go to the holder rather than the mesh, because the
## holder is what has to receive `Open` - `_cache_entity_under_key()` holds every
## node answering to a name, so leaving them on the mesh as well would deliver
## the input twice, once to something that cannot act on it.
func _make_it_a_door(
	mover: Node3D, mi: MeshInstance3D, draft: DraftBrush, authored: String, entity_class: String
) -> void:
	mover.set_meta("brush_entity_class", entity_class)
	mi.remove_meta("brush_entity_class")
	if authored != "":
		mover.set_meta("entity_name", authored)
		mi.remove_meta("entity_name")
	var outputs: Array = draft.get_meta("entity_io_outputs", [])
	if not outputs.is_empty():
		mover.set_meta("entity_io_outputs", outputs.duplicate(true))
		mi.remove_meta("entity_io_outputs")
	# The authored values, or the class defaults where the mapper set none. A
	# brush entity's properties can only be set by a `.map` import today (#728),
	# so on a level drawn here this is the defaults every time.
	var authored_data: Dictionary = _brush_entity_properties(draft, entity_class)
	if not authored_data.is_empty():
		mover.set_meta("entity_data", authored_data.duplicate())
	mover.set_script(HFDoorRuntime)
	if mover.has_method("apply_entity_data"):
		mover.call("apply_entity_data", authored_data)


## What a brush entity's properties are, class defaults filled in underneath.
func _brush_entity_properties(draft: DraftBrush, entity_class: String) -> Dictionary:
	var out: Dictionary = {}
	# Asked for rather than assumed: `root` is a shim in a good many tests, and the
	# defaults are a nicety here - what matters is what the mapper authored.
	var definition: Dictionary = {}
	if root.has_method("get_entity_definition"):
		definition = root.get_entity_definition(entity_class)
	for prop in definition.get("properties", []):
		if not (prop is Dictionary):
			continue
		var prop_name := str(prop.get("name", ""))
		if prop_name != "" and prop.has("default"):
			out[prop_name] = prop["default"]
	var stored: Variant = draft.get_meta("brush_entity_data", {})
	if stored is Dictionary:
		for key in stored as Dictionary:
			out[str(key)] = stored[key]
	return out


func _append_trigger_volume(holder: Node3D, draft: DraftBrush, idx: int) -> void:
	var authored := authored_entity_name(draft)
	var area := Area3D.new()
	area.name = authored if authored != "" else "Trigger_%d" % idx
	area.monitoring = true
	area.monitorable = true
	if authored != "":
		area.set_meta("entity_name", authored)
	var bec := str(draft.get_meta("brush_entity_class", ""))
	if bec != "":
		area.set_meta("brush_entity_class", bec)
	var outputs: Array = draft.get_meta("entity_io_outputs", [])
	if not outputs.is_empty():
		area.set_meta("entity_io_outputs", outputs.duplicate(true))
	holder.add_child(area)
	var source: Node3D = draft.mesh_instance if draft.mesh_instance else draft
	area.transform = _source_transform_in_baked_container(source, holder.get_parent() as Node3D)
	var col := CollisionShape3D.new()
	var mesh: Mesh = draft.mesh_instance.mesh if draft.mesh_instance else null
	col.shape = _shape_for_draft(draft, mesh)
	area.add_child(col)


func _shape_for_draft(draft: DraftBrush, mesh: Mesh) -> Shape3D:
	if mesh:
		var convex: Shape3D = mesh.create_convex_shape(true, false)
		if convex:
			return convex
		var tri: Shape3D = mesh.create_trimesh_shape()
		if tri:
			return tri
	var box := BoxShape3D.new()
	box.size = draft.size if draft.size.length() > 0.001 else Vector3.ONE
	return box


func collect_chunk_brushes(
	source: Node3D, chunk_size: float, chunks: Dictionary, key: String
) -> void:
	if not source:
		return
	for child in source.get_children():
		if not (child is DraftBrush):
			continue
		if root.is_entity_node(child):
			continue
		if root.cordon_enabled and not _brush_in_cordon(child as DraftBrush):
			continue
		# func_detail and trigger brushes skip structural CSG
		if not _is_structural_brush(child as DraftBrush):
			continue
		var coord = chunk_coord((child as Node3D).global_position, chunk_size)
		if not chunks.has(coord):
			chunks[coord] = {"brushes": [], "committed": [], "generated": []}
		if not chunks[coord].has(key):
			chunks[coord][key] = []
		chunks[coord][key].append(child)


func chunk_coord(position: Vector3, chunk_size: float) -> Vector3i:
	var s = max(0.001, chunk_size)
	return Vector3i(
		int(floor(position.x / s)), int(floor(position.y / s)), int(floor(position.z / s))
	)


func append_draft_brushes_to_csg(
	source: Node3D, target: CSGCombiner3D, force_subtract: bool = false, only_additive: bool = false
) -> void:
	if not source or not target:
		return
	append_brush_list_to_csg(source.get_children(), target, force_subtract, only_additive)


func append_generated_brushes_to_csg(target: CSGCombiner3D, only_additive: bool = false) -> void:
	if not target:
		return
	if root.generated_floors:
		append_brush_list_to_csg(root.generated_floors.get_children(), target, false, only_additive)
	if root.generated_walls:
		append_brush_list_to_csg(root.generated_walls.get_children(), target, false, only_additive)


func collect_face_bake_brushes() -> Array:
	var out: Array = []
	_append_face_bake_container(root.draft_brushes_node, out)
	_append_face_bake_container(root.generated_floors, out)
	_append_face_bake_container(root.generated_walls, out)
	return out


func _append_face_bake_container(container: Node3D, out: Array) -> void:
	if not container:
		return
	for child in container.get_children():
		if child is DraftBrush and child.operation != CSGShape3D.OPERATION_SUBTRACTION:
			if root.bake_visible_only and not child.visible:
				continue
			if root.cordon_enabled and not _brush_in_cordon(child as DraftBrush):
				continue
			if not _is_structural_brush(child as DraftBrush):
				continue
			out.append(child)


## The mesh a brush has to be cut with because the prefab factory cannot build it.
##
## `PrefabFactory.create_prefab()` knows the primitives and falls back to a box for
## anything else, and CUSTOM is the only shape that reaches that fallback. So a
## vertex-edited wedge, a polygon extrusion, a bevelled brush or a hull imported
## from a `.map` went into the CSG as a rectangular box and baked as one. Its own
## mesh is what it looks like on screen and what `HFSubtractPreview` already cuts
## with, so the bake now cuts with the same thing.
##
## Null for every shape the factory does build, and for a custom brush whose mesh
## has not been built yet: the box is wrong, but it is better than dropping the
## brush out of the bake without a word.
static func _authored_brush_mesh(draft: DraftBrush) -> Mesh:
	if draft.shape != DraftBrush.BrushShape.CUSTOM:
		return null
	if draft.mesh_instance == null:
		return null
	return draft.mesh_instance.mesh


func append_brush_list_to_csg(
	brushes: Array, target: CSGCombiner3D, force_subtract: bool = false, only_additive: bool = false
) -> void:
	if not target:
		return
	for child in brushes:
		if not (child is DraftBrush):
			continue
		if root.is_entity_node(child):
			continue
		if root.bake_visible_only and not child.visible:
			continue
		if root.cordon_enabled and not _brush_in_cordon(child as DraftBrush):
			continue
		if not _is_structural_brush(child as DraftBrush):
			continue
		var draft: DraftBrush = child
		if (
			only_additive
			and (force_subtract or draft.operation == CSGShape3D.OPERATION_SUBTRACTION)
		):
			continue
		var subtracts: bool = force_subtract or draft.operation == CSGShape3D.OPERATION_SUBTRACTION
		var csg_shape: CSGShape3D = null
		var placement := draft.global_transform
		# A cutter goes in as a mesh for the same reason a solid does: the
		# boolean writes the material of the face that cut through to the face it
		# carved, so the cutter's own texturing is what fills the interior it
		# exposes (#746).
		#
		# A mirrored cutter is the exception. Its negative determinant inverts
		# face winding, and the boolean reads an inverted mesh operand
		# differently from the primitive it regenerates from `size`: measured on
		# one wall and one cutter, 25.5000 against 25.6792. Both are wrong - a
		# mirrored brush bakes wrong whether or not it is textured - but a mapper
		# painting a cutter must not move the cut, so a mirrored one stays on the
		# primitive. Same shape as the closed-solid guard below, and for the same
		# reason: on this side a bad operand is a wrong cut.
		var face_mesh: Mesh = null
		if not (subtracts and draft.global_transform.basis.determinant() < 0.0):
			face_mesh = _face_material_csg_mesh(draft)
		if face_mesh != null:
			var csg_faces := CSGMesh3D.new()
			csg_faces.mesh = face_mesh
			csg_faces.use_collision = true
			csg_shape = csg_faces
			# The face records are in the brush's own space, which is where the
			# snapshot's basis and origin put them back from.
		else:
			var authored: Mesh = _authored_brush_mesh(draft)
			if authored != null:
				var csg_mesh := CSGMesh3D.new()
				csg_mesh.mesh = authored
				csg_mesh.use_collision = true
				csg_shape = csg_mesh
				# The mesh is in the mesh instance's own space, so that is where it goes.
				placement = draft.mesh_instance.global_transform
			else:
				csg_shape = PrefabFactory.create_prefab(
					draft.shape, draft.size, max(3, draft.sides)
				)
		csg_shape.operation = (
			CSGShape3D.OPERATION_SUBTRACTION if force_subtract else draft.operation
		)
		# Setting `material` on a CSGMesh3D overrides every surface of its mesh
		# with the one, which is the whole of #693. A brush that brought its own
		# materials keeps them.
		if face_mesh == null:
			var mat = draft.material_override
			# An untextured cutter leaves the interior bare, which is what it has
			# always done. The fallback below is the editor's translucent red
			# subtract preview and must never reach a bake.
			if not mat and not subtracts:
				mat = root._make_brush_material(csg_shape.operation)
			if mat:
				csg_shape.set("material", mat)
				csg_shape.set("material_override", mat)
		# The combiner is parented to LevelRoot, so it carries the root's
		# transform. Place the shape after it is in the tree, or the assignment
		# writes a local transform and the root lands on it a second time.
		target.add_child(csg_shape)
		csg_shape.global_transform = placement


## Replace existing collision bodies with per-visgroup StaticBody3D nodes.
## [param hull_verts] is an Array[PackedVector3Array], one per brush.
## [param brush_visgroups] is a parallel Array[PackedStringArray].
## Brushes with no visgroup go into a "_default" body.
func _partition_collision_by_visgroup(
	baked: Node3D, hull_verts: Array, brush_visgroups: Array, options: Dictionary
) -> void:
	var convex_clean: bool = bool(options.get("convex_clean", true))
	var convex_simplify: float = float(options.get("convex_simplify", 0.0))
	var layer: int = 0
	var mask: int = 0
	# Remove existing collision bodies (FaceCollision from face-bake, FloorCollision from CSG)
	for body_name in ["FaceCollision", "FloorCollision"]:
		var old_body: Node = baked.get_node_or_null(body_name)
		if old_body:
			if old_body is StaticBody3D:
				layer = old_body.collision_layer
				mask = old_body.collision_mask
			old_body.get_parent().remove_child(old_body)
			old_body.free()
	# Group per-brush hull verts by visgroup name
	var vg_buckets: Dictionary = {}  # visgroup_name -> Array[PackedVector3Array]
	for i in range(hull_verts.size()):
		var hull: PackedVector3Array = (
			hull_verts[i] if hull_verts[i] is PackedVector3Array else PackedVector3Array()
		)
		if hull.is_empty():
			continue
		var vgs: PackedStringArray = (
			brush_visgroups[i] if i < brush_visgroups.size() else PackedStringArray()
		)
		if vgs.is_empty():
			if not vg_buckets.has("_default"):
				vg_buckets["_default"] = []
			vg_buckets["_default"].append(hull)
		else:
			for vg_name in vgs:
				if not vg_buckets.has(vg_name):
					vg_buckets[vg_name] = []
				vg_buckets[vg_name].append(hull)
	# Create one StaticBody3D per visgroup
	for vg_name in vg_buckets:
		var verts_list: Array = vg_buckets[vg_name]
		var shapes: Array = Baker.build_convex_collision_shapes(
			verts_list, convex_clean, convex_simplify
		)
		if shapes.is_empty():
			continue
		var body := StaticBody3D.new()
		var safe_name: String = vg_name.replace(" ", "_").replace("/", "_")
		body.name = "Collision_%s" % safe_name
		body.collision_layer = layer
		body.collision_mask = mask
		for shape in shapes:
			var col := CollisionShape3D.new()
			col.shape = shape
			body.add_child(col)
		baked.add_child(body)


func collect_generated_heightmap_meshes() -> Array:
	var out: Array = []
	if not root.generated_heightmap_floors:
		return out
	for child in root.generated_heightmap_floors.get_children():
		if child is MeshInstance3D:
			out.append(child)
	return out


func _bake_heightmap_only(layer: int) -> Node3D:
	var container := Node3D.new()
	container.name = BAKED_CONTAINER_NAME
	_append_heightmap_meshes_to_baked(container, layer)
	if container.get_child_count() == 0:
		container.free()
		return null
	return container


func _append_heightmap_meshes_to_baked(container: Node3D, layer: int) -> void:
	var hm_meshes := collect_generated_heightmap_meshes()
	if hm_meshes.is_empty():
		return
	var body := container.get_node_or_null("FloorCollision") as StaticBody3D
	if not body:
		body = StaticBody3D.new()
		body.name = "FloorCollision"
		body.collision_layer = layer
		body.collision_mask = STATIC_BODY_MASK
		container.add_child(body)
	for hm in hm_meshes:
		var dup: MeshInstance3D = hm.duplicate()
		container.add_child(dup)
		dup.transform = _source_transform_in_baked_container(hm, container)
		if dup.mesh:
			var col := CollisionShape3D.new()
			col.shape = dup.mesh.create_trimesh_shape()
			col.transform = body.transform.affine_inverse() * dup.transform
			body.add_child(col)


func _source_transform_in_baked_container(source: Node3D, container: Node3D) -> Transform3D:
	# Unparented bake products are installed directly under LevelRoot.
	var eventual_container_world := root.global_transform * container.transform
	if container.is_inside_tree():
		eventual_container_world = container.global_transform
	return eventual_container_world.affine_inverse() * source.global_transform


func _append_auto_connectors(container: Node3D) -> void:
	if not root.paint_layers:
		return
	if root.paint_layers.layers.size() < 2:
		return
	var gen := HFAutoConnector.new()
	var settings := HFAutoConnector.Settings.new()
	settings.mode = root.bake_connector_mode
	settings.stair_step_height = root.bake_connector_stair_height
	settings.width_cells = root.bake_connector_width
	settings.stair_threshold = root.bake_connector_stair_threshold
	var definitions: Array = []
	var known_boundaries: Dictionary = {}
	var paint_tool = root.get("paint_tool")
	if (
		paint_tool != null
		and paint_tool.get("connector_defs") is Array
		and not paint_tool.connector_defs.is_empty()
	):
		for definition in paint_tool.connector_defs:
			definitions.append(definition)
			known_boundaries[definition.boundary_key()] = true
	if root.bake_auto_connectors:
		var segments := gen.detect_boundaries(root.paint_layers)
		for definition in gen.defs_from_groups(gen.group_segments(segments), settings):
			if known_boundaries.has(definition.boundary_key()):
				continue
			known_boundaries[definition.boundary_key()] = true
			definitions.append(definition)
	var results := gen.generate_definitions(definitions, root.paint_layers)
	if results.is_empty():
		return
	var body := container.get_node_or_null("FloorCollision") as StaticBody3D
	if not body:
		body = StaticBody3D.new()
		body.name = "FloorCollision"
		container.add_child(body)
	var idx := 0
	for entry: Dictionary in results:
		var mesh: ArrayMesh = entry.get("mesh")
		if not mesh:
			continue
		var xform: Transform3D = entry.get("transform", Transform3D.IDENTITY)
		var mi := MeshInstance3D.new()
		mi.name = "AutoConnector_%d" % idx
		mi.mesh = mesh
		mi.transform = xform
		container.add_child(mi)
		var col := CollisionShape3D.new()
		col.shape = mesh.create_trimesh_shape()
		col.transform = body.transform.affine_inverse() * mi.transform
		body.add_child(col)
		idx += 1
	if idx > 0:
		root._log("Auto-connectors: generated %d connector(s)" % idx)


func bake_navmesh(container: Node3D) -> void:
	if not container:
		return
	var nav_region = container.get_node_or_null("BakedNavmesh") as NavigationRegion3D
	if not nav_region:
		nav_region = NavigationRegion3D.new()
		nav_region.name = "BakedNavmesh"
		container.add_child(nav_region)
	var nav_mesh = nav_region.navigation_mesh
	if not nav_mesh:
		nav_mesh = NavigationMesh.new()
		nav_region.navigation_mesh = nav_mesh
	nav_mesh.cell_size = root.bake_navmesh_cell_size
	nav_mesh.cell_height = root.bake_navmesh_cell_height
	nav_mesh.agent_height = root.bake_navmesh_agent_height
	# Ceil agent_radius to cell_size units to avoid precision warning
	var cs: float = root.bake_navmesh_cell_size
	nav_mesh.agent_radius = ceil(root.bake_navmesh_agent_radius / cs) * cs
	# The two that decide whether an agent can use the stairs this plugin builds.
	# They were left at Godot's defaults while the four above them were set (#701).
	nav_mesh.agent_max_climb = root.bake_navmesh_agent_max_climb
	nav_mesh.agent_max_slope = root.bake_navmesh_agent_max_slope
	# Parse collision shapes instead of visual meshes (avoids GPU readback stall).
	_set_parsed_geometry_type(nav_mesh, NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS)
	if (
		ClassDB.class_has_method("NavigationServer3D", "parse_source_geometry_data")
		and ClassDB.class_has_method("NavigationServer3D", "bake_from_source_geometry_data")
		and ClassDB.class_exists("NavigationMeshSourceGeometryData3D")
	):
		var source = NavigationMeshSourceGeometryData3D.new()
		NavigationServer3D.parse_source_geometry_data(nav_mesh, source, container)
		NavigationServer3D.bake_from_source_geometry_data(nav_mesh, source)
	elif nav_region.has_method("bake_navigation_mesh"):
		nav_region.call("bake_navigation_mesh")


## Set the parsed-geometry-type on a NavigationMesh (or any Object with the
## expected property), handling the property rename between Godot versions
## (parsed_geometry_type → geometry_parsed_geometry_type).
## Returns true if the property was set, false if neither name was found.
static func _set_parsed_geometry_type(target: Object, value: int) -> bool:
	if "geometry_parsed_geometry_type" in target:
		target.set("geometry_parsed_geometry_type", value)
		return true
	if "parsed_geometry_type" in target:
		target.set("parsed_geometry_type", value)
		return true
	HFLog.warn("NavigationMesh has neither geometry_parsed_geometry_type nor parsed_geometry_type")
	return false


func _brush_in_cordon(brush: DraftBrush) -> bool:
	return root.cordon_aabb.intersects(_brush_world_aabb(brush))


func _brush_world_aabb(brush: DraftBrush) -> AABB:
	if brush.mesh_instance and brush.mesh_instance.mesh:
		return _transform_aabb(
			brush.mesh_instance.mesh.get_aabb(), brush.mesh_instance.global_transform
		)
	if not brush.faces.is_empty():
		var has_vertex := false
		var face_bounds := AABB()
		for face in brush.faces:
			if not face:
				continue
			for local_vertex in face.local_verts:
				var world_vertex: Vector3 = brush.global_transform * local_vertex
				if has_vertex:
					face_bounds = face_bounds.expand(world_vertex)
				else:
					face_bounds = AABB(world_vertex, Vector3.ZERO)
					has_vertex = true
		if has_vertex:
			return face_bounds
	return _transform_aabb(AABB(-brush.size * 0.5, brush.size), brush.global_transform)


static func _transform_aabb(local_bounds: AABB, world_transform: Transform3D) -> AABB:
	var minimum := local_bounds.position
	var maximum := local_bounds.end
	var first: Vector3 = world_transform * minimum
	var result := AABB(first, Vector3.ZERO)
	for x in [minimum.x, maximum.x]:
		for y in [minimum.y, maximum.y]:
			for z in [minimum.z, maximum.z]:
				result = result.expand(world_transform * Vector3(x, y, z))
	return result


# ---------------------------------------------------------------------------
# Automated occluder generation
# ---------------------------------------------------------------------------

## Angle threshold (radians) for grouping coplanar triangles.
const _OCCLUDER_NORMAL_THRESHOLD := 0.087  # ~5 degrees
## Distance threshold for plane membership.
const _OCCLUDER_PLANE_DIST_THRESHOLD := 0.1
## Vertex positions are rounded to this before they are compared, so two
## triangles that meet at a corner are recognised as meeting there. It is the
## same order as the validator's weld tolerance, and small enough that two
## surfaces a mapper drew apart never round together.
const _OCCLUDER_WELD := 0.001


## Scan baked MeshInstance3D children, group their triangles into flat surfaces,
## and create one OccluderInstance3D per surface.
##
## A surface is triangles that are coplanar **and touching**. The coplanarity
## test on its own is what #614 was: two triangles facing the same way and lying
## in the same infinite plane were put in the same occluder whether they shared
## an edge or were a level apart, so every floor at y = 0 became one occluder and
## every wall on a shared line joined it. Godot gives an OccluderInstance3D a
## single bounding volume, so one of those is never itself culled and stands for
## a surface that is mostly holes. Forty boxes in a row produced an occluder
## spanning all 10,113 units between the first and the last.
##
## Touching is tested on welded vertex positions, which is what "shares an edge
## with it" comes to for baked geometry: the triangles of one wall come from one
## brush face and hold its corners exactly, and two walls a room apart hold none
## in common. Two brushes that abut without sharing vertices give two occluders
## rather than one, which is the right answer either way round.
##
## The grouping is transitive, so a run of triangles that turns gently stays one
## occluder shaped like the run. That is what an occluder should be. It is a
## single pass keyed on vertex position rather than the old scan of every plane
## found so far for every triangle, which was quadratic in the triangle count.
func _generate_occluders(container: Node3D) -> void:
	# Remove previously generated occluders so re-bake is idempotent.
	var existing: Node = container.find_child("Occluders", false, false)
	if existing:
		container.remove_child(existing)
		existing.free()

	var min_area: float = _root_float("bake_occluder_min_area", 4.0)
	var tris: Array = _collect_occluder_triangles(container)
	var surfaces: Array = _group_touching_coplanar(tris)

	# Filter by minimum area and build occluder nodes.
	var occluder_container := Node3D.new()
	occluder_container.name = "Occluders"
	var count := 0
	for surface in surfaces:
		var members: Array = surface
		var area := 0.0
		for i in members:
			area += float(tris[i]["area"])
		if area < min_area:
			continue
		var verts := PackedVector3Array()
		var indices := PackedInt32Array()
		for i in members:
			var tri: Dictionary = tris[i]
			var base := verts.size()
			verts.append(tri["a"])
			verts.append(tri["b"])
			verts.append(tri["c"])
			indices.append(base)
			indices.append(base + 1)
			indices.append(base + 2)
		var occ := ArrayOccluder3D.new()
		occ.vertices = verts
		occ.indices = indices
		var inst := OccluderInstance3D.new()
		inst.occluder = occ
		inst.name = "Occluder_%d" % count
		occluder_container.add_child(inst)
		count += 1

	if count > 0:
		container.add_child(occluder_container)
		root._assign_owner_recursive(occluder_container)
		root._log(
			(
				"Occluders: generated %d from %d flat surfaces in %d triangles"
				% [count, surfaces.size(), tris.size()]
			)
		)
	else:
		occluder_container.free()


## Every triangle of every baked mesh, in container space, with the plane it lies
## on. One Dictionary per triangle: `a`, `b`, `c`, `normal`, `dist`, `area`.
##
## Triangles too small to have a reliable normal are dropped here rather than
## carried, because a degenerate one has no plane to be grouped by.
func _collect_occluder_triangles(container: Node3D) -> Array:
	var out: Array = []
	for mi: MeshInstance3D in _collect_mesh_instances(container):
		var mesh: Mesh = mi.mesh
		if not mesh:
			continue
		# Transform relative to container so occluders are in container-local space.
		var xform: Transform3D = container.global_transform.affine_inverse() * mi.global_transform
		for surf_idx in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(surf_idx)
			if arrays.is_empty():
				continue
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			if verts.is_empty():
				continue
			var normals_arr: PackedVector3Array = (
				arrays[Mesh.ARRAY_NORMAL]
				if (
					arrays.size() > Mesh.ARRAY_NORMAL
					and arrays[Mesh.ARRAY_NORMAL] is PackedVector3Array
				)
				else PackedVector3Array()
			)
			var indices: PackedInt32Array = (
				arrays[Mesh.ARRAY_INDEX]
				if (
					arrays.size() > Mesh.ARRAY_INDEX
					and arrays[Mesh.ARRAY_INDEX] is PackedInt32Array
				)
				else PackedInt32Array()
			)
			var corners: PackedInt32Array = indices
			if corners.size() < 3:
				corners = PackedInt32Array()
				for i in verts.size():
					corners.append(i)
			var i := 0
			while i + 2 < corners.size():
				var first: int = corners[i]
				var a: Vector3 = xform * verts[first]
				var b: Vector3 = xform * verts[corners[i + 1]]
				var c: Vector3 = xform * verts[corners[i + 2]]
				i += 3
				var n: Vector3 = (c - a).cross(b - a)
				var area: float = n.length() * 0.5
				if area < 0.001:
					continue
				n = n.normalized()
				# Use normal from mesh data if available.
				if normals_arr.size() > first:
					var mesh_n: Vector3 = (xform.basis * normals_arr[first]).normalized()
					if mesh_n.length_squared() > 0.5:
						n = mesh_n
				out.append({"a": a, "b": b, "c": c, "normal": n, "dist": n.dot(a), "area": area})
	return out


## The triangles grouped into flat surfaces: coplanar and touching. Returns one
## `PackedInt32Array` of indices into `tris` per surface.
##
## Two triangles are joined when they hold a vertex in common and lie on the same
## plane within the angle and distance thresholds. Holding a vertex in common is
## what makes this one pass: each vertex names the handful of triangles that meet
## there, and only those are ever compared. Nothing walks the list of surfaces
## found so far.
## `Array[int]` rather than `PackedInt32Array` for `parent`: the union-find writes
## to it from inside a call, and an Array is unambiguously the caller's array
## rather than a copy-on-write view of it. Typed, so `parent[i]` still has a type
## to infer from and `resize()` fills with zeros rather than nulls.
static func _group_touching_coplanar(tris: Array) -> Array:
	var parent: Array[int] = []
	parent.resize(tris.size())
	for i in tris.size():
		parent[i] = i

	# vertex position -> the triangles that touch it
	var at_vertex: Dictionary = {}
	for i in tris.size():
		var tri: Dictionary = tris[i]
		for corner in ["a", "b", "c"]:
			var key := _weld_key(tri[corner])
			if not at_vertex.has(key):
				at_vertex[key] = []
			at_vertex[key].append(i)

	for key in at_vertex:
		var here: Array = at_vertex[key]
		for x in range(here.size()):
			for y in range(x + 1, here.size()):
				if _same_plane(tris[here[x]], tris[here[y]]):
					_union(parent, here[x], here[y])

	var by_root: Dictionary = {}
	for i in tris.size():
		var r := _find(parent, i)
		if not by_root.has(r):
			by_root[r] = []
		by_root[r].append(i)
	return by_root.values()


## A vertex position rounded to the weld tolerance, so two triangles that meet
## at a corner agree on where that corner is.
static func _weld_key(v: Vector3) -> Vector3i:
	return Vector3i(
		roundi(v.x / _OCCLUDER_WELD), roundi(v.y / _OCCLUDER_WELD), roundi(v.z / _OCCLUDER_WELD)
	)


static func _same_plane(one: Dictionary, other: Dictionary) -> bool:
	return (
		(one["normal"] as Vector3).dot(other["normal"]) >= cos(_OCCLUDER_NORMAL_THRESHOLD)
		and absf(float(one["dist"]) - float(other["dist"])) < _OCCLUDER_PLANE_DIST_THRESHOLD
	)


static func _find(parent: Array[int], i: int) -> int:
	var root := i
	while parent[root] != root:
		root = parent[root]
	# Path compression, so a long chain is walked once rather than once per query.
	while parent[i] != root:
		var next := parent[i]
		parent[i] = root
		i = next
	return root


static func _union(parent: Array[int], a: int, b: int) -> void:
	var ra := _find(parent, a)
	var rb := _find(parent, b)
	if ra != rb:
		parent[rb] = ra


## Recursively collect all MeshInstance3D nodes under a container, walking into
## intermediary nodes like BakedChunk_* without picking up non-mesh children.
static func _collect_mesh_instances(node: Node) -> Array:
	var result: Array = []
	for child in node.get_children():
		if child is MeshInstance3D:
			result.append(child)
		elif child is Node3D and child.name != "Occluders":
			result.append_array(_collect_mesh_instances(child))
	return result


func _root_bool(property_name: String, default_value: bool) -> bool:
	if not root or not _root_has_property(property_name):
		return default_value
	return bool(root.get(property_name))


func _root_float(property_name: String, default_value: float) -> float:
	if not root or not _root_has_property(property_name):
		return default_value
	return float(root.get(property_name))


func _root_has_property(property_name: String) -> bool:
	if not root or property_name == "":
		return false
	for prop in root.get_property_list():
		if prop.get("name", "") == property_name:
			return true
	return false
