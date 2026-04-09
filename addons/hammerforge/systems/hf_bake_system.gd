@tool
extends RefCounted
class_name HFBakeSystem

const PrefabFactory = preload("../prefab_factory.gd")
const DraftBrush = preload("../brush_instance.gd")
const HFAutoConnector = preload("../paint/hf_auto_connector.gd")

## Bake preview mode: FULL produces final geometry, WIREFRAME skips materials
## and generates unshaded wireframe, PROXY uses simplified box meshes.
enum PreviewMode { FULL, WIREFRAME, PROXY }

var root: Node3D
var _last_dirty_brush_ids: Dictionary = {}  # brush_id -> true; captured at bake start
var _last_bake_success: bool = false

## Number of brushes to process per frame during face-based bake collection.
## Lower values yield more often (smoother editor), higher values bake faster.
const _FACE_BAKE_BATCH := 8


func _init(level_root: Node3D) -> void:
	root = level_root


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
	elif count > 200:
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


## Bake only the given brush nodes (selection bake).
func bake_selected(
	brush_nodes: Array, collision_layer_mask: int = 0, preview_mode: int = 0  # PreviewMode.FULL
) -> void:
	if not root.baker:
		push_warning("Bake skipped: baker not initialized")
		root.emit_signal("user_message", "Bake failed — baker not initialized", 2)
		return
	if brush_nodes.is_empty():
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
	var collision_csg = CSGCombiner3D.new()
	collision_csg.hide()
	collision_csg.use_collision = false
	root.add_child(collision_csg)
	append_brush_list_to_csg(brush_nodes, temp_csg)
	append_brush_list_to_csg(brush_nodes, collision_csg, false, true)
	root.bake_progress.emit(0.5, "Baking selection")
	var yield_start_ms := Time.get_ticks_msec()
	await root.get_tree().process_frame
	await root.get_tree().process_frame
	yield_overhead_ms += Time.get_ticks_msec() - yield_start_ms
	var baked = root.baker.bake_from_csg(
		temp_csg, root.bake_material_override, layer, layer, bake_options
	)
	if baked:
		var collision_baked = root.baker.bake_from_csg(
			collision_csg, null, layer, layer, bake_options
		)
		apply_collision_from_bake(baked, collision_baked, layer)
		if collision_baked:
			collision_baked.free()
		_apply_preview_visuals(baked, preview_mode)
	temp_csg.queue_free()
	collision_csg.queue_free()
	if baked:
		root._last_bake_duration_ms = max(0, Time.get_ticks_msec() - started - yield_overhead_ms)
		root.bake_progress.emit(1.0, "Finalizing")
		# Merge into existing baked container rather than replacing it
		if root.baked_container and is_instance_valid(root.baked_container):
			baked.name = "BakedSelection_%d" % Time.get_ticks_msec()
			root.baked_container.add_child(baked)
		else:
			root.baked_container = baked
			root.add_child(root.baked_container)
		postprocess_bake(baked, true)
		root._assign_owner_recursive(root.baked_container)
		_last_bake_success = true
		root._log("Selection bake finished (success=true)")
		root.bake_finished.emit(true)
	else:
		root._last_bake_duration_ms = max(0, Time.get_ticks_msec() - started - yield_overhead_ms)
		_last_bake_success = false
		root._log("Selection bake failed")
		root.bake_finished.emit(false)


## Bake only brushes that have been modified since the last bake.
func bake_dirty(collision_layer_mask: int = 0, preview_mode: int = 0) -> void:
	var dirty_ids: Array = root._dirty_brush_ids.keys()
	if dirty_ids.is_empty():
		root.emit_signal("user_message", "No changed brushes since last bake", 1)
		return
	_last_dirty_brush_ids = root._dirty_brush_ids.duplicate()
	var brush_nodes: Array = []
	for bid in dirty_ids:
		var brush = root._find_brush_by_key(str(bid))
		if brush:
			brush_nodes.append(brush)
	if brush_nodes.is_empty():
		root.emit_signal("user_message", "Dirty brushes no longer in scene", 1)
		return
	root._log("Incremental bake: %d dirty brushes" % brush_nodes.size())
	# Full context needed for correct CSG — bake everything but track dirty set
	await bake(true, false, collision_layer_mask, preview_mode)
	# Only clear dirty tags if the bake actually succeeded
	if _last_bake_success:
		root._dirty_brush_ids.clear()


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
		# Godot 4 has no StandardMaterial3D.wireframe property.
		# Use a ShaderMaterial with render_mode wireframe instead.
		var shader := Shader.new()
		shader.code = (
			"shader_type spatial;\n"
			+ "render_mode unshaded, cull_disabled, wireframe, depth_draw_never;\n"
			+ "uniform vec4 color : source_color = vec4(0.2, 0.8, 1.0, 0.6);\n"
			+ "void fragment() { ALBEDO = color.rgb; ALPHA = color.a; }\n"
		)
		var smat := ShaderMaterial.new()
		smat.shader = shader
		mat = smat
	elif mode == PreviewMode.PROXY:
		var std_mat := StandardMaterial3D.new()
		std_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		std_mat.albedo_color = Color(0.5, 0.5, 0.5, 0.4)
		std_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat = std_mat
	if mat:
		_apply_material_recursive(container, mat)


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
	preview_mode: int = 0  # PreviewMode.FULL
) -> void:
	if not root.baker:
		push_warning("Bake skipped: baker not initialized")
		root.emit_signal("user_message", "Bake failed — baker not initialized", 2)
		return
	var started = Time.get_ticks_msec()
	var yield_overhead_ms := 0  # Idle time spent in frame yields — excluded from estimator
	if apply_cuts:
		root.apply_pending_cuts()
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
	if root.bake_use_face_materials:
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
		var groups: Dictionary = {}
		var snap_total: int = snapshots.size()
		for _bi in range(snap_total):
			root.baker.collect_snapshot_groups(snapshots[_bi], use_atlas, groups)
			if (_bi + 1) % _FACE_BAKE_BATCH == 0 or _bi == snap_total - 1:
				root.bake_progress.emit(
					float(_bi + 1) / float(max(1, snap_total)) * 0.7,
					"Collecting faces %d/%d" % [_bi + 1, snap_total]
				)
				var yield_start_ms := Time.get_ticks_msec()
				await root.get_tree().process_frame
				yield_overhead_ms += Time.get_ticks_msec() - yield_start_ms
		root.bake_progress.emit(0.75, "Building mesh")
		var build_yield_start_ms := Time.get_ticks_msec()
		await root.get_tree().process_frame
		yield_overhead_ms += Time.get_ticks_msec() - build_yield_start_ms
		# Collect per-brush world-space hull verts for convex collision (mode >= 1)
		if collision_mode >= 1:
			var per_brush_verts: Array = []
			for snap in snapshots:
				per_brush_verts.append(snap.get("hull_verts", PackedVector3Array()))
			bake_options["per_brush_verts"] = per_brush_verts
		# Visgroup partitioning (mode 2): separate collision bodies per visgroup
		if collision_mode >= 2:
			bake_options["brush_visgroups"] = brush_visgroups
		baked = root.baker.build_mesh_from_groups(groups, layer, layer, bake_options)
		# Apply visgroup-partitioned collision bodies after initial build
		if baked and collision_mode >= 2:
			var face_hull_verts: Array = []
			for snap in snapshots:
				face_hull_verts.append(snap.get("hull_verts", PackedVector3Array()))
			_partition_collision_by_visgroup(baked, face_hull_verts, brush_visgroups, bake_options)
	else:
		if root.bake_chunk_size > 0.0:
			baked = await bake_chunked(root.bake_chunk_size, layer, bake_options)
		else:
			root.bake_progress.emit(0.5, "Baking")
			baked = await bake_single(layer, bake_options)
	if baked:
		root._last_bake_duration_ms = max(0, Time.get_ticks_msec() - started - yield_overhead_ms)
		root.bake_progress.emit(1.0, "Finalizing")
		if root.baked_container and is_instance_valid(root.baked_container):
			root.baked_container.queue_free()
		root.baked_container = baked
		root.add_child(root.baked_container)
		postprocess_bake(root.baked_container)
		if root.bake_use_multimesh:
			_consolidate_to_multimesh(root.baked_container)
		_apply_preview_visuals(root.baked_container, preview_mode)
		root._assign_owner_recursive(root.baked_container)
		if hide_live:
			if root.draft_brushes_node:
				root.draft_brushes_node.visible = false
			if root.pending_node:
				root.pending_node.visible = false
		root._log("Bake finished (success=true)")
		_last_bake_success = true
		root.bake_finished.emit(true)
	else:
		root._last_bake_duration_ms = max(0, Time.get_ticks_msec() - started - yield_overhead_ms)
		root._log("Bake failed")
		_last_bake_success = false
		warn_bake_failure()
		root.bake_finished.emit(false)


func warn_bake_failure() -> void:
	var draft_count = count_brushes_in(root.draft_brushes_node)
	var pending_count = count_brushes_in(root.pending_node)
	var committed_count = count_brushes_in(root.committed_node)
	var entities_count = root.entities_node.get_child_count() if root.entities_node else 0
	var detail := (
		"Bake failed: no baked geometry (draft=%s, pending=%s, committed=%s, entities=%s)"
		% [draft_count, pending_count, committed_count, entities_count]
	)
	push_warning(detail)
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


func postprocess_bake(container: Node3D, selection_only: bool = false) -> void:
	if not container:
		return
	if root.bake_auto_connectors and not selection_only:
		_append_auto_connectors(container)
	if root.bake_navmesh:
		bake_navmesh(container)


func count_brushes_in(container: Node3D) -> int:
	if not container:
		return 0
	var count := 0
	for child in container.get_children():
		if child is DraftBrush and not root.is_entity_node(child):
			count += 1
	return count


func bake_single(layer: int, options: Dictionary) -> Node3D:
	var temp_csg = CSGCombiner3D.new()
	temp_csg.hide()
	temp_csg.use_collision = false
	root.add_child(temp_csg)
	var collision_csg = CSGCombiner3D.new()
	collision_csg.hide()
	collision_csg.use_collision = false
	root.add_child(collision_csg)
	append_draft_brushes_to_csg(root.draft_brushes_node, temp_csg)
	if root.commit_freeze and root.committed_node:
		append_draft_brushes_to_csg(root.committed_node, temp_csg, true)
	append_draft_brushes_to_csg(root.draft_brushes_node, collision_csg, false, true)
	append_generated_brushes_to_csg(temp_csg)
	append_generated_brushes_to_csg(collision_csg, true)
	await root.get_tree().process_frame
	await root.get_tree().process_frame
	var baked = root.baker.bake_from_csg(
		temp_csg, root.bake_material_override, layer, layer, options
	)
	var collision_baked: Node3D = null
	if baked:
		collision_baked = root.baker.bake_from_csg(collision_csg, null, layer, layer, options)
		apply_collision_from_bake(baked, collision_baked, layer)
	temp_csg.queue_free()
	collision_csg.queue_free()
	if collision_baked:
		collision_baked.free()
	if baked:
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
	var container = Node3D.new()
	container.name = "BakedGeometry"
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
		var collision_csg = CSGCombiner3D.new()
		collision_csg.hide()
		collision_csg.use_collision = false
		root.add_child(collision_csg)
		append_brush_list_to_csg(brushes, temp_csg)
		append_brush_list_to_csg(generated, temp_csg)
		if root.commit_freeze:
			append_brush_list_to_csg(committed, temp_csg, true)
		append_brush_list_to_csg(brushes, collision_csg, false, true)
		append_brush_list_to_csg(generated, collision_csg, false, true)
		await root.get_tree().process_frame
		await root.get_tree().process_frame
		var baked_chunk = root.baker.bake_from_csg(
			temp_csg, root.bake_material_override, layer, layer, options
		)
		if baked_chunk:
			var collision_baked = root.baker.bake_from_csg(
				collision_csg, null, layer, layer, options
			)
			apply_collision_from_bake(baked_chunk, collision_baked, layer)
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
			if collision_baked:
				collision_baked.free()
		temp_csg.queue_free()
		collision_csg.queue_free()
		processed += 1
		if total_chunks > 0:
			var progress = float(processed) / float(total_chunks)
			root.bake_progress.emit(progress, "Chunk %d/%d" % [processed, total_chunks])
	if container and chunk_count > 0:
		_append_heightmap_meshes_to_baked(container, layer)
	return container if chunk_count > 0 else null


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
## Skips subtractive brushes (matching the only_additive filter used by the
## collision CSG path) and extracts real mesh vertices instead of AABB corners
## so that non-box shapes (cylinders, spheres, etc.) get accurate hulls.
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
		# This matches the only_additive filter in append_brush_list_to_csg().
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
		var csg_shape = PrefabFactory.create_prefab(draft.shape, draft.size, max(3, draft.sides))
		csg_shape.operation = (
			CSGShape3D.OPERATION_SUBTRACTION if force_subtract else draft.operation
		)
		csg_shape.global_transform = draft.global_transform
		if csg_shape.operation != CSGShape3D.OPERATION_SUBTRACTION:
			var mat = draft.material_override
			if not mat:
				mat = root._make_brush_material(csg_shape.operation)
			if mat:
				csg_shape.set("material", mat)
				csg_shape.set("material_override", mat)
		target.add_child(csg_shape)


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


func apply_collision_from_bake(target: Node3D, source: Node3D, layer: int) -> void:
	if not target:
		return
	var target_body = target.get_node_or_null("FloorCollision") as StaticBody3D
	if not target_body:
		target_body = StaticBody3D.new()
		target_body.name = "FloorCollision"
		target.add_child(target_body)
	target_body.collision_layer = layer
	target_body.collision_mask = layer
	for child in target_body.get_children():
		child.queue_free()
	if not source:
		return
	var source_body = source.get_node_or_null("FloorCollision") as StaticBody3D
	if not source_body:
		return
	for child in source_body.get_children():
		if child is CollisionShape3D:
			var dup = child.duplicate()
			target_body.add_child(dup)


func collect_generated_heightmap_meshes() -> Array:
	var out: Array = []
	if not root.generated_heightmap_floors:
		return out
	for child in root.generated_heightmap_floors.get_children():
		if child is MeshInstance3D:
			out.append(child)
	return out


func _append_heightmap_meshes_to_baked(container: Node3D, layer: int) -> void:
	var hm_meshes := collect_generated_heightmap_meshes()
	if hm_meshes.is_empty():
		return
	var body := container.get_node_or_null("FloorCollision") as StaticBody3D
	if not body:
		body = StaticBody3D.new()
		body.name = "FloorCollision"
		body.collision_layer = layer
		body.collision_mask = layer
		container.add_child(body)
	for hm in hm_meshes:
		var dup: MeshInstance3D = hm.duplicate()
		container.add_child(dup)
		if dup.mesh:
			var col := CollisionShape3D.new()
			col.shape = dup.mesh.create_trimesh_shape()
			body.add_child(col)


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
	var results: Array = gen.generate_connectors(root.paint_layers, settings)
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
	push_warning(
		"NavigationMesh has neither geometry_parsed_geometry_type nor parsed_geometry_type"
	)
	return false


func _brush_in_cordon(brush: DraftBrush) -> bool:
	var half = brush.size * 0.5
	var brush_aabb = AABB(brush.global_position - half, brush.size)
	return root.cordon_aabb.intersects(brush_aabb)


## Consolidate identical meshes in the baked container into MultiMeshInstance3D nodes.
## Groups MeshInstance3D children by mesh resource identity (same Mesh = same group).
## Groups with 2+ instances are replaced with a single MultiMeshInstance3D.
func _consolidate_to_multimesh(container: Node3D) -> void:
	if not container:
		return
	# Group MeshInstance3D children by mesh resource
	var mesh_groups: Dictionary = {}  # Mesh -> Array[MeshInstance3D]
	for child in container.get_children():
		if not (child is MeshInstance3D):
			continue
		var mi: MeshInstance3D = child
		if not mi.mesh:
			continue
		var key: Mesh = mi.mesh
		if not mesh_groups.has(key):
			mesh_groups[key] = []
		mesh_groups[key].append(mi)
	var consolidated := 0
	for mesh_key: Mesh in mesh_groups:
		var instances: Array = mesh_groups[mesh_key]
		if instances.size() < 2:
			continue
		# Build MultiMesh
		var mm = MultiMesh.new()
		mm.mesh = mesh_key
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.instance_count = instances.size()
		for i in range(instances.size()):
			var mi: MeshInstance3D = instances[i]
			mm.set_instance_transform(i, mi.global_transform)
		# Carry material from first instance
		var mmi = MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.name = (
			"MMI_%s" % mesh_key.resource_name if mesh_key.resource_name else "MMI_%d" % consolidated
		)
		var first_mi: MeshInstance3D = instances[0]
		if first_mi.get_surface_override_material(0):
			mmi.material_override = first_mi.get_surface_override_material(0)
		elif first_mi.material_override:
			mmi.material_override = first_mi.material_override
		container.add_child(mmi)
		# Remove originals
		for mi: MeshInstance3D in instances:
			mi.get_parent().remove_child(mi)
			mi.queue_free()
		consolidated += 1
	if consolidated > 0:
		root._log("MultiMesh: consolidated %d groups" % consolidated)
