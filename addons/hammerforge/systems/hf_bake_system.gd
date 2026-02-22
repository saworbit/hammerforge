@tool
extends RefCounted
class_name HFBakeSystem

const PrefabFactory = preload("../prefab_factory.gd")
const DraftBrush = preload("../brush_instance.gd")

var root: Node3D


func _init(level_root: Node3D) -> void:
	root = level_root


func bake(apply_cuts: bool = true, hide_live: bool = false, collision_layer_mask: int = 0) -> void:
	if not root.baker:
		return
	var started = Time.get_ticks_msec()
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
	if root.bake_use_face_materials:
		root.bake_progress.emit(0.5, "Baking faces")
		var face_brushes = collect_face_bake_brushes()
		baked = root.baker.bake_from_faces(
			face_brushes,
			root.material_manager,
			root.bake_material_override,
			layer,
			layer,
			bake_options
		)
	else:
		if root.bake_chunk_size > 0.0:
			baked = await bake_chunked(root.bake_chunk_size, layer, bake_options)
		else:
			root.bake_progress.emit(0.5, "Baking")
			baked = await bake_single(layer, bake_options)
	if baked:
		root._last_bake_duration_ms = max(0, Time.get_ticks_msec() - started)
		root.bake_progress.emit(1.0, "Finalizing")
		if root.baked_container and is_instance_valid(root.baked_container):
			root.baked_container.queue_free()
		root.baked_container = baked
		root.add_child(root.baked_container)
		postprocess_bake(root.baked_container)
		root._assign_owner_recursive(root.baked_container)
		if hide_live:
			if root.draft_brushes_node:
				root.draft_brushes_node.visible = false
			if root.pending_node:
				root.pending_node.visible = false
		root._log("Bake finished (success=true)")
		root.bake_finished.emit(true)
	else:
		root._last_bake_duration_ms = max(0, Time.get_ticks_msec() - started)
		root._log("Bake failed")
		warn_bake_failure()
		root.bake_finished.emit(false)


func warn_bake_failure() -> void:
	var draft_count = count_brushes_in(root.draft_brushes_node)
	var pending_count = count_brushes_in(root.pending_node)
	var committed_count = count_brushes_in(root.committed_node)
	var entities_count = root.entities_node.get_child_count() if root.entities_node else 0
	push_warning(
		(
			"Bake failed: no baked geometry (draft=%s, pending=%s, committed=%s, entities=%s)"
			% [draft_count, pending_count, committed_count, entities_count]
		)
	)


func build_bake_options() -> Dictionary:
	return {
		"merge_meshes": root.bake_merge_meshes,
		"generate_lods": root.bake_generate_lods,
		"unwrap_uv2": root.bake_lightmap_uv2,
		"uv2_texel_size": root.bake_lightmap_texel_size,
		"use_thread_pool": root.bake_use_thread_pool,
		"use_face_materials": root.bake_use_face_materials
	}


func postprocess_bake(container: Node3D) -> void:
	if not container:
		return
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
		_append_heightmap_meshes_to_baked(baked, layer)
	return baked


func bake_chunked(chunk_size: float, layer: int, options: Dictionary) -> Node3D:
	var size = max(0.001, chunk_size)
	var chunks: Dictionary = {}
	collect_chunk_brushes(root.draft_brushes_node, size, chunks, "brushes")
	if root.commit_freeze and root.committed_node:
		collect_chunk_brushes(root.committed_node, size, chunks, "committed")
	collect_chunk_brushes(root.generated_floors, size, chunks, "generated")
	collect_chunk_brushes(root.generated_walls, size, chunks, "generated")
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
	var chunks: Dictionary = {}
	collect_chunk_brushes(root.draft_brushes_node, size, chunks, "brushes")
	if root.commit_freeze and root.committed_node:
		collect_chunk_brushes(root.committed_node, size, chunks, "committed")
	collect_chunk_brushes(root.generated_floors, size, chunks, "generated")
	collect_chunk_brushes(root.generated_walls, size, chunks, "generated")
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
			if root.cordon_enabled and not _brush_in_cordon(child as DraftBrush):
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
		if root.cordon_enabled and not _brush_in_cordon(child as DraftBrush):
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
	# Parse collision shapes instead of visual meshes (avoids GPU readback stall)
	nav_mesh.parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
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


func _brush_in_cordon(brush: DraftBrush) -> bool:
	var half = brush.size * 0.5
	var brush_aabb = AABB(brush.global_position - half, brush.size)
	return root.cordon_aabb.intersects(brush_aabb)
