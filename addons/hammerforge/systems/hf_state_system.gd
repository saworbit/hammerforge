@tool
extends RefCounted
class_name HFStateSystem

const DraftBrush = preload("../brush_instance.gd")
const DraftEntity = preload("../draft_entity.gd")
const HFLevelIO = preload("../hflevel_io.gd")

var root: Node3D


func _init(level_root: Node3D) -> void:
	root = level_root


func capture_state() -> Dictionary:
	var state: Dictionary = {}
	state["brushes"] = []
	state["pending"] = []
	state["committed"] = []
	state["entities"] = []
	state["floor"] = capture_floor_info()
	state["id_counter"] = root._brush_id_counter
	state["csg_visible"] = root.draft_brushes_node.visible if root.draft_brushes_node else true
	state["pending_visible"] = root.pending_node.visible if root.pending_node else true
	state["baked_present"] = root.baked_container != null
	state["paint_layers"] = capture_paint_layers()
	state["paint_active_layer"] = root.paint_layers.active_layer_index if root.paint_layers else 0
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
					state["entities"].append(info)
	return state


func restore_state(state: Dictionary) -> void:
	if state.is_empty():
		return
	root.clear_brushes()
	root.entity_system.clear_entities()
	root.paint_system.restore_paint_layers(
		state.get("paint_layers", []), int(state.get("paint_active_layer", 0))
	)
	if state.has("materials"):
		root.set_materials(state.get("materials", []))
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
		root.entity_system.restore_entity_from_info(info)
	restore_floor_info(state.get("floor", {}))
	if root.draft_brushes_node:
		root.draft_brushes_node.visible = bool(state.get("csg_visible", true))
	if root.pending_node:
		root.pending_node.visible = bool(state.get("pending_visible", true))
	if not bool(state.get("baked_present", false)) and root.baked_container:
		root.baked_container.queue_free()
		root.baked_container = null


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
	var state = capture_state()
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
		"bake_lightmap_uv2": root.bake_lightmap_uv2,
		"bake_lightmap_texel_size": root.bake_lightmap_texel_size,
		"bake_navmesh": root.bake_navmesh,
		"bake_navmesh_cell_size": root.bake_navmesh_cell_size,
		"bake_navmesh_cell_height": root.bake_navmesh_cell_height,
		"bake_navmesh_agent_height": root.bake_navmesh_agent_height,
		"bake_navmesh_agent_radius": root.bake_navmesh_agent_radius,
		"bake_use_thread_pool": root.bake_use_thread_pool
	}


func apply_hflevel_settings(settings: Dictionary) -> void:
	if settings.is_empty():
		return
	if settings.has("grid_snap"):
		root.grid_snap = float(settings.get("grid_snap", root.grid_snap))
	if settings.has("bake_chunk_size"):
		root.bake_chunk_size = float(settings.get("bake_chunk_size", root.bake_chunk_size))
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


func capture_paint_layers() -> Array:
	var out: Array = []
	if not root.paint_layers:
		return out
	for layer in root.paint_layers.layers:
		if not layer:
			continue
		var grid = layer.grid
		var entry: Dictionary = {
			"id": str(layer.layer_id),
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
		for cid in layer.get_chunk_ids():
			var bits = layer.get_chunk_bits(cid)
			var bytes: Array = []
			for b in bits:
				bytes.append(int(b))
			entry["chunks"].append({"cx": cid.x, "cy": cid.y, "bits": bytes})
		out.append(entry)
	return out
