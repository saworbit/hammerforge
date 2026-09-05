extends SceneTree
## Renders the HammerForge Console to a PNG so its layout can be judged without
## opening the editor. Dev tool: run it, look at the image, delete nothing.
##
##   godot --path . -s res://tools/hf_console_preview.gd --resolution 1280x420
##
## Writes user://hf_console_<tab>.png for each tab.

const HFConsolePanelType = preload("res://addons/hammerforge/ui/hf_console_panel.gd")
const HFConsoleLogType = preload("res://addons/hammerforge/hf_console_log.gd")

const OUT_DIR := "user://console_preview"


class PreviewRoot:
	extends Node3D

	var grid_visible := true
	var grid_follow_brush := false
	var show_subtract_preview := false
	var texture_lock := true
	var cordon_enabled := false
	var bake_merge_meshes := true
	var bake_generate_lods := false
	var bake_unwrap_uv0 := false
	var bake_lightmap_uv2 := false
	var bake_use_face_materials := true
	var bake_navmesh := false
	var bake_visible_only := false
	var bake_use_multimesh := false
	var bake_use_atlas := false
	var bake_auto_connectors := false
	var bake_wire_io := true
	var bake_generate_occluders := false
	var bake_use_thread_pool := true
	var commit_freeze := true
	var hflevel_autosave_enabled := true
	var hflevel_autosave_minutes := 5
	var hflevel_autosave_keep := 5
	var hflevel_autosave_path := "res://.hammerforge/autosave.hflevel"
	var hflevel_compress := true
	var auto_spawn_player := true
	var debug_logging := false
	var bake_chunk_size := 32.0

	func get_live_brush_count() -> int:
		return 74

	func get_entity_count() -> int:
		return 9

	func get_total_vertex_estimate() -> int:
		return 3120

	func get_paint_memory_bytes() -> int:
		return 262144

	func get_bake_chunk_count() -> int:
		return 4

	func get_last_bake_duration_ms() -> int:
		return 412

	func get_recommended_chunk_size() -> float:
		return 64.0

	func get_level_health() -> Dictionary:
		return {"label": "Consider Chunking", "severity": 1}


class PreviewDock:
	extends Node

	var level_root: Node3D = null

	func _init() -> void:
		level_root = PreviewRoot.new()
		add_child(level_root)


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.14, 0.15, 0.18)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(backdrop)

	var panel = HFConsolePanelType.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(panel)

	var buffer = HFConsoleLogType.new()
	panel.set_log(buffer)
	var dock := PreviewDock.new()
	root.add_child(dock)
	panel.set_dock(dock)

	buffer.info("HammerForge v0.3.0 ready.", "plugin")
	buffer.info("Loaded 6 materials from res://materials/proto.tres", "materials")
	buffer.warn("Brush Wall_04 is non-planar by 0.031 units", "check")
	buffer.info("Bake finished in 412 ms across 4 chunks", "bake")
	buffer.warn("Subtract brush Cut_11 removes nothing", "check")
	buffer.error("Navmesh bake failed: no floor surfaces found", "bake")
	buffer.info("Autosave written to res://.hammerforge/autosave.hflevel", "autosave")

	panel.record_validation(
		["Brush Wall_04 is non-planar", "Subtract Cut_11 intersects nothing"]
	)
	_shoot(panel)


func _shoot(panel) -> void:
	for tab in [0, 1, 2]:
		panel.show_tab(tab)
		panel.refresh(true)
		for _i in range(6):
			await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var path := "%s/tab_%d.png" % [OUT_DIR, tab]
		image.save_png(path)
		print("wrote ", ProjectSettings.globalize_path(path))
	quit()
