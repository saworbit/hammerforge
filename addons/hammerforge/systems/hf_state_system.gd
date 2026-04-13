@tool
extends RefCounted
class_name HFStateSystem

const DraftBrush = preload("../brush_instance.gd")
const DraftEntity = preload("../draft_entity.gd")
const HFLevelIO = preload("../hflevel_io.gd")
const HFHeightmapIO = preload("../paint/hf_heightmap_io.gd")

var root: Node3D

## Transaction support — wraps multi-step operations (hollow, clip) so they
## appear as a single undo entry and can be rolled back on failure.
var _transaction_name := ""
var _transaction_snapshot: Dictionary = {}
var _transaction_active := false


func _init(level_root: Node3D) -> void:
	root = level_root


# ---------------------------------------------------------------------------
# Transactions
# ---------------------------------------------------------------------------


## Begin a transaction.  Captures a full state snapshot.  All mutations until
## commit_transaction() or rollback_transaction() will be grouped.
func begin_transaction(name: String) -> void:
	if _transaction_active:
		push_warning(
			"HFStateSystem: nested transaction '%s' while '%s' active" % [name, _transaction_name]
		)
		return
	_transaction_name = name
	_transaction_snapshot = capture_state()
	_transaction_active = true
	root.begin_signal_batch()


## Commit the current transaction.  Returns the before-snapshot so the caller
## can push a single undo entry covering all mutations since begin_transaction().
func commit_transaction() -> Dictionary:
	if not _transaction_active:
		push_warning("HFStateSystem: commit_transaction() called with no active transaction")
		return {}
	var snapshot := _transaction_snapshot
	_transaction_active = false
	_transaction_name = ""
	_transaction_snapshot = {}
	root.end_signal_batch()
	return snapshot


## Roll back — restores the state captured at begin_transaction().
func rollback_transaction() -> void:
	if not _transaction_active:
		push_warning("HFStateSystem: rollback_transaction() called with no active transaction")
		return
	root.discard_signal_batch()
	restore_state(_transaction_snapshot)
	_transaction_active = false
	_transaction_name = ""
	_transaction_snapshot = {}


## Returns true when a transaction is in progress.
func is_in_transaction() -> bool:
	return _transaction_active


func capture_state(include_transient: bool = true) -> Dictionary:
	var state: Dictionary = {}
	state["brushes"] = []
	state["pending"] = []
	state["committed"] = []
	state["entities"] = []
	state["floor"] = capture_floor_info()
	state["sun"] = capture_sun_info()
	state["id_counter"] = root._brush_id_counter
	state["csg_visible"] = root.draft_brushes_node.visible if root.draft_brushes_node else true
	state["pending_visible"] = root.pending_node.visible if root.pending_node else true
	state["baked_present"] = root.baked_container != null
	state["paint_layers"] = capture_paint_layers(true)
	state["paint_active_layer"] = root.paint_layers.active_layer_index if root.paint_layers else 0
	if include_transient:
		state["face_selection"] = root.face_selection.duplicate(true)
	if root.material_manager:
		state["materials"] = root.material_manager.materials
	for node in root._iter_pick_nodes():
		var info = root.get_brush_info_from_node(node)
		if info.is_empty():
			continue
		if info.get("pending", false):
			state["pending"].append(info)
		else:
			state["brushes"].append(info)
	if root.committed_node:
		for child in root.committed_node.get_children():
			if child is DraftBrush:
				var info = root.get_brush_info_from_node(child)
				if info.is_empty():
					continue
				info["committed"] = true
				state["committed"].append(info)
	if root.entities_node:
		for child in root.entities_node.get_children():
			if child is DraftEntity:
				var info = root.entity_system.capture_entity_info(child as DraftEntity)
				if not info.is_empty():
					var vgs: PackedStringArray = child.get_meta("visgroups", PackedStringArray())
					if not vgs.is_empty():
						info["visgroups"] = Array(vgs)
					var gid: String = str(child.get_meta("group_id", ""))
					if gid != "":
						info["group_id"] = gid
					state["entities"].append(info)
	if root.visgroup_system:
		state["visgroups"] = root.visgroup_system.capture_visgroups()
		state["groups"] = root.visgroup_system.capture_groups()
	var duplicators: Array = []
	for dup_id in root.brush_system._duplicators:
		duplicators.append(root.brush_system._duplicators[dup_id].to_dict())
	state["duplicators"] = duplicators
	if root.prefab_system:
		state["prefab_instances"] = root.prefab_system.capture_state()
	return state


func restore_state(state: Dictionary) -> void:
	if state.is_empty():
		return
	root.clear_brushes()
	root.entity_system.clear_entities()
	var region_data = state.get("terrain_regions", {})
	if region_data is Dictionary and not region_data.is_empty():
		if root.paint_system:
			root.paint_system.region_streaming_enabled = true
			root.paint_system.load_region_index(region_data)
	root.paint_system.restore_paint_layers(
		state.get("paint_layers", []), int(state.get("paint_active_layer", 0))
	)
	if region_data is Dictionary and not region_data.is_empty():
		if root.paint_system:
			root.paint_system.load_initial_regions()
	if state.has("materials"):
		root.set_materials(state.get("materials", []))
	if state.has("face_selection"):
		root.face_selection = state.get("face_selection", {})
		root._apply_face_selection()
	else:
		root.face_selection.clear()
		root._apply_face_selection()
	root._brush_id_counter = int(state.get("id_counter", 0))
	var brushes: Array = state.get("brushes", [])
	for info in brushes:
		root.create_brush_from_info(info)
	var pending: Array = state.get("pending", [])
	for info in pending:
		info["pending"] = true
		root.create_brush_from_info(info)
	var committed: Array = state.get("committed", [])
	for info in committed:
		info["committed"] = true
		root.create_brush_from_info(info)
	var entities: Array = state.get("entities", [])
	for info in entities:
		var entity = root.entity_system.restore_entity_from_info(info)
		if entity:
			if info.has("visgroups"):
				var vgs = PackedStringArray()
				for v in info.get("visgroups", []):
					vgs.append(str(v))
				entity.set_meta("visgroups", vgs)
			if info.has("group_id") and str(info["group_id"]) != "":
				entity.set_meta("group_id", str(info["group_id"]))
	if root.visgroup_system:
		root.visgroup_system.restore_visgroups(state.get("visgroups", {}))
		root.visgroup_system.restore_groups(state.get("groups", {}))
	root.brush_system._duplicators.clear()
	for dup_dict in state.get("duplicators", []):
		var dup = HFDuplicator.from_dict(dup_dict)
		root.brush_system._duplicators[dup.duplicator_id] = dup
		# Reapply duplicator_id meta on source brushes so Remove Array can find them.
		for src_id in dup.source_brush_ids:
			var src_brush = root.brush_system._brush_cache.get(src_id)
			if is_instance_valid(src_brush):
				src_brush.set_meta("duplicator_id", dup.duplicator_id)
	restore_floor_info(state.get("floor", {}))
	restore_sun_info(state.get("sun", {}))
	if root.draft_brushes_node:
		root.draft_brushes_node.visible = bool(state.get("csg_visible", true))
	if root.pending_node:
		root.pending_node.visible = bool(state.get("pending_visible", true))
	if not bool(state.get("baked_present", false)) and root.baked_container:
		root.baked_container.queue_free()
		root.baked_container = null
	if root.prefab_system and state.has("prefab_instances"):
		root.prefab_system.restore_state(state["prefab_instances"])


func capture_full_state() -> Dictionary:
	return {"settings": capture_hflevel_settings(), "state": capture_state()}


func restore_full_state(bundle: Dictionary) -> void:
	if bundle.is_empty():
		return
	var settings = bundle.get("settings", {})
	var state = bundle.get("state", {})
	apply_hflevel_settings(settings if settings is Dictionary else {})
	restore_state(state if state is Dictionary else {})


func capture_hflevel_state() -> Dictionary:
	var state = capture_state(false)
	if root.paint_system and root.paint_system.region_streaming_enabled:
		state["terrain_regions"] = root.paint_system.capture_region_index()
		state["paint_layers"] = capture_paint_layers(false)
	var data: Dictionary = {
		"version": 1,
		"saved_at": Time.get_datetime_string_from_system(),
		"settings": capture_hflevel_settings(),
		"state": state
	}
	return HFLevelIO.encode_variant(data)


func capture_hflevel_settings() -> Dictionary:
	return {
		"grid_snap": root.grid_snap,
		"bake_chunk_size": root.bake_chunk_size,
		"bake_visible_only": root.bake_visible_only,
		"bake_use_multimesh": root.bake_use_multimesh,
		"bake_use_atlas": root.bake_use_atlas,
		"bake_collision_layer_index": root.bake_collision_layer_index,
		"bake_material_override": root.bake_material_override,
		"bake_use_face_materials": root.bake_use_face_materials,
		"commit_freeze": root.commit_freeze,
		"grid_visible": root.grid_visible,
		"grid_follow_brush": root.grid_follow_brush,
		"debug_logging": root.debug_logging,
		"auto_spawn_player": root.auto_spawn_player,
		"draft_pick_layer_index": root.draft_pick_layer_index,
		"bake_merge_meshes": root.bake_merge_meshes,
		"bake_generate_lods": root.bake_generate_lods,
		"bake_unwrap_uv0": root.bake_unwrap_uv0,
		"bake_lightmap_uv2": root.bake_lightmap_uv2,
		"bake_lightmap_texel_size": root.bake_lightmap_texel_size,
		"bake_navmesh": root.bake_navmesh,
		"bake_navmesh_cell_size": root.bake_navmesh_cell_size,
		"bake_navmesh_cell_height": root.bake_navmesh_cell_height,
		"bake_navmesh_agent_height": root.bake_navmesh_agent_height,
		"bake_navmesh_agent_radius": root.bake_navmesh_agent_radius,
		"bake_use_thread_pool": root.bake_use_thread_pool,
		"bake_collision_mode": root.bake_collision_mode,
		"bake_convex_clean": root.bake_convex_clean,
		"bake_convex_simplify": root.bake_convex_simplify,
		"bake_auto_connectors": root.bake_auto_connectors,
		"bake_connector_mode": root.bake_connector_mode,
		"bake_connector_stair_height": root.bake_connector_stair_height,
		"bake_connector_width": root.bake_connector_width,
		"hflevel_autosave_keep": root.hflevel_autosave_keep,
		"region_streaming_enabled":
		root.paint_system.region_streaming_enabled if root.paint_system else false,
		"region_size_cells":
		(
			root.paint_system.region_manager.region_size_cells
			if root.paint_system and root.paint_system.region_manager
			else 512
		),
		"region_streaming_radius":
		(
			root.paint_system.region_manager.streaming_radius
			if root.paint_system and root.paint_system.region_manager
			else 2
		),
		"region_memory_budget_mb":
		root.paint_system.region_memory_budget_mb if root.paint_system else 256,
		"region_show_grid": root.paint_system.region_show_grid if root.paint_system else false,
		"texture_lock": root.texture_lock,
		"show_subtract_preview": root.show_subtract_preview,
		"cordon_enabled": root.cordon_enabled,
		"cordon_aabb_pos":
		[root.cordon_aabb.position.x, root.cordon_aabb.position.y, root.cordon_aabb.position.z],
		"cordon_aabb_size":
		[root.cordon_aabb.size.x, root.cordon_aabb.size.y, root.cordon_aabb.size.z]
	}


func apply_hflevel_settings(settings: Dictionary) -> void:
	if settings.is_empty():
		return
	if settings.has("grid_snap"):
		root.grid_snap = float(settings.get("grid_snap", root.grid_snap))
	if settings.has("bake_chunk_size"):
		root.bake_chunk_size = float(settings.get("bake_chunk_size", root.bake_chunk_size))
	if settings.has("bake_visible_only"):
		root.bake_visible_only = bool(settings.get("bake_visible_only", root.bake_visible_only))
	if settings.has("bake_use_multimesh"):
		root.bake_use_multimesh = bool(settings.get("bake_use_multimesh", root.bake_use_multimesh))
	if settings.has("bake_use_atlas"):
		root.bake_use_atlas = bool(settings.get("bake_use_atlas", root.bake_use_atlas))
	if settings.has("bake_auto_connectors"):
		root.bake_auto_connectors = bool(
			settings.get("bake_auto_connectors", root.bake_auto_connectors)
		)
	if settings.has("bake_connector_mode"):
		root.bake_connector_mode = int(
			settings.get("bake_connector_mode", root.bake_connector_mode)
		)
	if settings.has("bake_connector_stair_height"):
		root.bake_connector_stair_height = float(
			settings.get("bake_connector_stair_height", root.bake_connector_stair_height)
		)
	if settings.has("bake_connector_width"):
		root.bake_connector_width = int(
			settings.get("bake_connector_width", root.bake_connector_width)
		)
	if settings.has("bake_collision_layer_index"):
		root.bake_collision_layer_index = int(
			settings.get("bake_collision_layer_index", root.bake_collision_layer_index)
		)
	if settings.has("bake_material_override"):
		root.bake_material_override = settings.get(
			"bake_material_override", root.bake_material_override
		)
	if settings.has("bake_use_face_materials"):
		root.bake_use_face_materials = bool(
			settings.get("bake_use_face_materials", root.bake_use_face_materials)
		)
	if settings.has("commit_freeze"):
		root.commit_freeze = bool(settings.get("commit_freeze", root.commit_freeze))
	if settings.has("grid_visible"):
		root.grid_visible = bool(settings.get("grid_visible", root.grid_visible))
	if settings.has("grid_follow_brush"):
		root.grid_follow_brush = bool(settings.get("grid_follow_brush", root.grid_follow_brush))
	if settings.has("debug_logging"):
		root.debug_logging = bool(settings.get("debug_logging", root.debug_logging))
	if settings.has("auto_spawn_player"):
		root.auto_spawn_player = bool(settings.get("auto_spawn_player", root.auto_spawn_player))
	if settings.has("draft_pick_layer_index"):
		root.draft_pick_layer_index = int(
			settings.get("draft_pick_layer_index", root.draft_pick_layer_index)
		)
	if settings.has("bake_merge_meshes"):
		root.bake_merge_meshes = bool(settings.get("bake_merge_meshes", root.bake_merge_meshes))
	if settings.has("bake_generate_lods"):
		root.bake_generate_lods = bool(settings.get("bake_generate_lods", root.bake_generate_lods))
	if settings.has("bake_unwrap_uv0"):
		root.bake_unwrap_uv0 = bool(settings.get("bake_unwrap_uv0", root.bake_unwrap_uv0))
	if settings.has("bake_lightmap_uv2"):
		root.bake_lightmap_uv2 = bool(settings.get("bake_lightmap_uv2", root.bake_lightmap_uv2))
	if settings.has("bake_lightmap_texel_size"):
		root.bake_lightmap_texel_size = float(
			settings.get("bake_lightmap_texel_size", root.bake_lightmap_texel_size)
		)
	if settings.has("bake_navmesh"):
		root.bake_navmesh = bool(settings.get("bake_navmesh", root.bake_navmesh))
	if settings.has("bake_navmesh_cell_size"):
		root.bake_navmesh_cell_size = float(
			settings.get("bake_navmesh_cell_size", root.bake_navmesh_cell_size)
		)
	if settings.has("bake_navmesh_cell_height"):
		root.bake_navmesh_cell_height = float(
			settings.get("bake_navmesh_cell_height", root.bake_navmesh_cell_height)
		)
	if settings.has("bake_navmesh_agent_height"):
		root.bake_navmesh_agent_height = float(
			settings.get("bake_navmesh_agent_height", root.bake_navmesh_agent_height)
		)
	if settings.has("bake_navmesh_agent_radius"):
		root.bake_navmesh_agent_radius = float(
			settings.get("bake_navmesh_agent_radius", root.bake_navmesh_agent_radius)
		)
	if settings.has("bake_use_thread_pool"):
		root.bake_use_thread_pool = bool(
			settings.get("bake_use_thread_pool", root.bake_use_thread_pool)
		)
	if settings.has("bake_collision_mode"):
		root.bake_collision_mode = int(
			settings.get("bake_collision_mode", root.bake_collision_mode)
		)
	if settings.has("bake_convex_clean"):
		root.bake_convex_clean = bool(settings.get("bake_convex_clean", root.bake_convex_clean))
	if settings.has("bake_convex_simplify"):
		root.bake_convex_simplify = float(
			settings.get("bake_convex_simplify", root.bake_convex_simplify)
		)
	if settings.has("hflevel_autosave_keep"):
		root.hflevel_autosave_keep = int(
			settings.get("hflevel_autosave_keep", root.hflevel_autosave_keep)
		)
	if root.paint_system:
		if settings.has("region_streaming_enabled"):
			root.paint_system.region_streaming_enabled = bool(
				settings.get("region_streaming_enabled", root.paint_system.region_streaming_enabled)
			)
		if settings.has("region_size_cells"):
			root.paint_system.set_region_size_cells(
				int(
					settings.get(
						"region_size_cells", root.paint_system.region_manager.region_size_cells
					)
				)
			)
		if settings.has("region_streaming_radius"):
			root.paint_system.set_region_streaming_radius(
				int(
					settings.get(
						"region_streaming_radius", root.paint_system.region_manager.streaming_radius
					)
				)
			)
		if settings.has("region_memory_budget_mb"):
			root.paint_system.set_region_memory_budget_mb(
				int(
					settings.get(
						"region_memory_budget_mb", root.paint_system.region_memory_budget_mb
					)
				)
			)
		if settings.has("region_show_grid"):
			root.paint_system.set_region_show_grid(
				bool(settings.get("region_show_grid", root.paint_system.region_show_grid))
			)
	if settings.has("texture_lock"):
		root.texture_lock = bool(settings.get("texture_lock", true))
	if settings.has("show_subtract_preview"):
		root.show_subtract_preview = bool(settings.get("show_subtract_preview", false))
	if settings.has("cordon_enabled"):
		root.cordon_enabled = bool(settings.get("cordon_enabled", false))
	if settings.has("cordon_aabb_pos") and settings.has("cordon_aabb_size"):
		var pos_arr = settings.get("cordon_aabb_pos", [-128, -128, -128])
		var size_arr = settings.get("cordon_aabb_size", [256, 256, 256])
		if pos_arr is Array and size_arr is Array and pos_arr.size() >= 3 and size_arr.size() >= 3:
			root.cordon_aabb = AABB(
				Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2])),
				Vector3(float(size_arr[0]), float(size_arr[1]), float(size_arr[2]))
			)
	if root.has_method("update_cordon_visual"):
		root.update_cordon_visual()


func capture_floor_info() -> Dictionary:
	var floor = root.get_node_or_null("TempFloor") as CSGBox3D
	if not floor:
		return {"exists": false}
	return {
		"exists": true,
		"size": floor.size,
		"transform": floor.global_transform,
		"use_collision": floor.use_collision
	}


func restore_floor_info(info: Dictionary) -> void:
	if info.is_empty():
		return
	var should_exist = bool(info.get("exists", false))
	var floor = root.get_node_or_null("TempFloor") as CSGBox3D
	if not should_exist:
		if floor:
			floor.queue_free()
		return
	if not floor:
		floor = CSGBox3D.new()
		floor.name = "TempFloor"
		root.add_child(floor)
		root._assign_owner(floor)
	floor.size = info.get("size", Vector3(1024, 16, 1024))
	if info.has("transform"):
		floor.global_transform = info["transform"]
	floor.use_collision = bool(info.get("use_collision", true))


func capture_sun_info() -> Dictionary:
	var sun = root.get_node_or_null("DefaultSun") as DirectionalLight3D
	if not sun:
		return {"exists": false}
	return {
		"exists": true,
		"rotation_degrees": sun.rotation_degrees,
		"shadow_enabled": sun.shadow_enabled,
		"light_energy": sun.light_energy,
	}


func restore_sun_info(info: Dictionary) -> void:
	if info.is_empty():
		return
	var should_exist = bool(info.get("exists", false))
	var sun = root.get_node_or_null("DefaultSun") as DirectionalLight3D
	if not should_exist:
		if sun:
			sun.queue_free()
		return
	if not sun:
		sun = DirectionalLight3D.new()
		sun.name = "DefaultSun"
		root.add_child(sun)
		root._assign_owner(sun)
	sun.rotation_degrees = info.get("rotation_degrees", Vector3(-45, 30, 0))
	sun.shadow_enabled = bool(info.get("shadow_enabled", true))
	sun.light_energy = info.get("light_energy", 1.0)


func capture_paint_layers(include_chunks: bool = true) -> Array:
	var out: Array = []
	if not root.paint_layers:
		return out
	for layer in root.paint_layers.layers:
		if not layer:
			continue
		var grid = layer.grid
		var entry: Dictionary = {
			"id": str(layer.layer_id),
			"display_name": layer.display_name,
			"chunk_size": layer.chunk_size,
			"grid":
			{
				"cell_size": grid.cell_size if grid else 1.0,
				"origin": grid.origin if grid else Vector3.ZERO,
				"basis": grid.basis if grid else Basis.IDENTITY,
				"layer_y": grid.layer_y if grid else 0.0
			},
			"chunks": []
		}
		layer._ensure_terrain_slots()
		entry["terrain_slot_paths"] = layer.terrain_slot_paths.duplicate()
		entry["terrain_slot_uv_scales"] = layer.terrain_slot_uv_scales.duplicate()
		entry["terrain_slot_tints"] = layer.terrain_slot_tints.duplicate()
		if layer.has_heightmap():
			entry["heightmap_b64"] = HFHeightmapIO.encode_to_base64(layer.heightmap)
			entry["height_scale"] = layer.height_scale
		if include_chunks:
			for cid in layer.get_chunk_ids():
				var bits = layer.get_chunk_bits(cid)
				var bytes: Array = []
				for b in bits:
					bytes.append(int(b))
				var mat_ids = layer.get_chunk_material_ids(cid)
				var mat_bytes: Array = []
				for b in mat_ids:
					mat_bytes.append(int(b))
				var blends = layer.get_chunk_blend_weights(cid)
				var blend_bytes: Array = []
				for b in blends:
					blend_bytes.append(int(b))
				var blends_2 = layer.get_chunk_blend_weights_slot(cid, 2)
				var blend2_bytes: Array = []
				for b in blends_2:
					blend2_bytes.append(int(b))
				var blends_3 = layer.get_chunk_blend_weights_slot(cid, 3)
				var blend3_bytes: Array = []
				for b in blends_3:
					blend3_bytes.append(int(b))
				entry["chunks"].append(
					{
						"cx": cid.x,
						"cy": cid.y,
						"bits": bytes,
						"material_ids": mat_bytes,
						"blend_weights": blend_bytes,
						"blend_weights_2": blend2_bytes,
						"blend_weights_3": blend3_bytes
					}
				)
		out.append(entry)
	return out
