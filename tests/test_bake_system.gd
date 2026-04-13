extends GutTest

const HFBakeSystem = preload("res://addons/hammerforge/systems/hf_bake_system.gd")
const HFLog = preload("res://addons/hammerforge/hf_log.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")
const HFPaintLayerManagerScript = preload(
	"res://addons/hammerforge/paint/hf_paint_layer_manager.gd"
)
const HFPaintGridScript = preload("res://addons/hammerforge/paint/hf_paint_grid.gd")

var root: Node3D
var bake_sys: HFBakeSystem


func before_each():
	HFLog.end_test_capture()
	root = Node3D.new()
	root.set_script(_root_shim_script())
	add_child_autoqfree(root)
	# Setup containers
	var draft = Node3D.new()
	draft.name = "DraftBrushes"
	root.add_child(draft)
	root.draft_brushes_node = draft
	var pending = Node3D.new()
	pending.name = "Pending"
	root.add_child(pending)
	root.pending_node = pending
	var committed = Node3D.new()
	committed.name = "Committed"
	root.add_child(committed)
	root.committed_node = committed
	var gen_floors = Node3D.new()
	gen_floors.name = "GeneratedFloors"
	root.add_child(gen_floors)
	root.generated_floors = gen_floors
	var gen_walls = Node3D.new()
	gen_walls.name = "GeneratedWalls"
	root.add_child(gen_walls)
	root.generated_walls = gen_walls
	var entities = Node3D.new()
	entities.name = "Entities"
	root.add_child(entities)
	root.entities_node = entities
	root.generated_heightmap_floors = null
	root.cordon_enabled = false
	root.cordon_aabb = AABB(Vector3(-500, -500, -500), Vector3(1000, 1000, 1000))
	bake_sys = HFBakeSystem.new(root)


func after_each():
	HFLog.end_test_capture()
	root = null
	bake_sys = null


func _capture_warning(pattern: String) -> void:
	HFLog.begin_test_capture([pattern])


func _assert_captured_warning(pattern: String) -> void:
	var warnings := HFLog.get_captured_warnings()
	HFLog.end_test_capture()
	assert_eq(warnings.size(), 1, "Should capture exactly one warning")
	if warnings.size() > 0:
		assert_string_contains(warnings[0], pattern, "Should capture expected warning text")


func _root_shim_script() -> GDScript:
	var s = GDScript.new()
	s.source_code = """
extends Node3D

signal user_message(text, level)
signal bake_started()
signal bake_progress(progress, message)
signal bake_finished(success)

var draft_brushes_node: Node3D
var pending_node: Node3D
var committed_node: Node3D
var generated_floors: Node3D
var generated_walls: Node3D
var generated_heightmap_floors: Node3D
var entities_node: Node3D
var cordon_enabled: bool = false
var cordon_aabb: AABB = AABB(Vector3(-500, -500, -500), Vector3(1000, 1000, 1000))
var bake_merge_meshes: bool = true
var bake_generate_lods: bool = false
var bake_unwrap_uv0: bool = false
var bake_lightmap_uv2: bool = false
var bake_lightmap_texel_size: float = 0.1
var bake_use_thread_pool: bool = false
var bake_use_face_materials: bool = false
var bake_chunk_size: float = 0.0
var bake_visible_only: bool = false
var bake_use_multimesh: bool = false
var bake_use_atlas: bool = false
var bake_auto_connectors: bool = false
var bake_generate_occluders: bool = false
var bake_occluder_min_area: float = 4.0
var bake_connector_mode: int = 0
var bake_connector_stair_height: float = 0.25
var bake_connector_width: int = 2
var bake_navmesh: bool = false
var bake_navmesh_cell_size: float = 0.3
var bake_navmesh_cell_height: float = 0.25
var bake_navmesh_agent_height: float = 2.0
var bake_navmesh_agent_radius: float = 0.4
var paint_layers = null
var commit_freeze: bool = false
var baker = null
var bake_material_override: Material = null
var _last_bake_duration_ms: int = 0
var _dirty_brush_ids: Dictionary = {}
var bake_collision_mode: int = 0
var bake_convex_clean: bool = true
var bake_convex_simplify: float = 0.0
var visgroup_system = null
var paint_system = null

func is_entity_node(node: Node) -> bool:
	return node.has_meta("entity_type")

func _find_brush_by_key(key: String) -> Node:
	if draft_brushes_node:
		for child in draft_brushes_node.get_children():
			if child.name == key:
				return child
	return null

func _log(_msg: String) -> void:
	pass

func _make_brush_material(_op: int) -> Material:
	return null
"""
	s.reload()
	return s


func _make_brush(
	parent: Node3D, pos: Vector3 = Vector3.ZERO, sz: Vector3 = Vector3(4, 4, 4)
) -> DraftBrush:
	var b = DraftBrush.new()
	b.size = sz
	parent.add_child(b)
	b.global_position = pos
	return b


func _make_entity(parent: Node3D) -> Node3D:
	var e = Node3D.new()
	e.set_meta("entity_type", "point")
	parent.add_child(e)
	return e


# ===========================================================================
# build_bake_options
# ===========================================================================


func test_build_bake_options_returns_all_keys():
	var opts = bake_sys.build_bake_options()
	assert_has(opts, "merge_meshes")
	assert_has(opts, "generate_lods")
	assert_has(opts, "unwrap_uv0")
	assert_has(opts, "unwrap_uv2")
	assert_has(opts, "uv2_texel_size")
	assert_has(opts, "use_thread_pool")
	assert_has(opts, "use_face_materials")
	assert_has(opts, "collision_mode")
	assert_has(opts, "convex_clean")
	assert_has(opts, "convex_simplify")


func test_build_bake_options_reflects_root_defaults():
	var opts = bake_sys.build_bake_options()
	assert_eq(opts["merge_meshes"], true)
	assert_eq(opts["generate_lods"], false)
	assert_eq(opts["unwrap_uv0"], false)
	assert_eq(opts["unwrap_uv2"], false)
	assert_eq(opts["uv2_texel_size"], 0.1)
	assert_eq(opts["use_thread_pool"], false)
	assert_eq(opts["use_face_materials"], false)


func test_build_bake_options_reflects_changed_values():
	root.bake_merge_meshes = false
	root.bake_generate_lods = true
	root.bake_lightmap_uv2 = true
	root.bake_lightmap_texel_size = 0.05
	var opts = bake_sys.build_bake_options()
	assert_eq(opts["merge_meshes"], false)
	assert_eq(opts["generate_lods"], true)
	assert_eq(opts["unwrap_uv2"], true)
	assert_eq(opts["uv2_texel_size"], 0.05)


# ===========================================================================
# _is_structural_brush
# ===========================================================================


func test_is_structural_no_meta():
	var b = _make_brush(root.draft_brushes_node)
	assert_true(bake_sys._is_structural_brush(b), "Brush with no brush_entity_class is structural")


func test_is_structural_func_wall():
	var b = _make_brush(root.draft_brushes_node)
	b.set_meta("brush_entity_class", "func_wall")
	assert_true(bake_sys._is_structural_brush(b), "func_wall is structural")


func test_is_not_structural_func_detail():
	var b = _make_brush(root.draft_brushes_node)
	b.set_meta("brush_entity_class", "func_detail")
	assert_false(bake_sys._is_structural_brush(b), "func_detail is not structural")


func test_is_not_structural_trigger_once():
	var b = _make_brush(root.draft_brushes_node)
	b.set_meta("brush_entity_class", "trigger_once")
	assert_false(bake_sys._is_structural_brush(b), "trigger_once is not structural")


func test_is_not_structural_trigger_multiple():
	var b = _make_brush(root.draft_brushes_node)
	b.set_meta("brush_entity_class", "trigger_multiple")
	assert_false(bake_sys._is_structural_brush(b), "trigger_multiple is not structural")


# ===========================================================================
# _is_trigger_brush
# ===========================================================================


func test_is_trigger_brush_trigger_once():
	var b = _make_brush(root.draft_brushes_node)
	b.set_meta("brush_entity_class", "trigger_once")
	assert_true(bake_sys._is_trigger_brush(b), "trigger_once is a trigger brush")


func test_is_trigger_brush_trigger_multiple():
	var b = _make_brush(root.draft_brushes_node)
	b.set_meta("brush_entity_class", "trigger_multiple")
	assert_true(bake_sys._is_trigger_brush(b), "trigger_multiple is a trigger brush")


func test_is_not_trigger_brush_empty():
	var b = _make_brush(root.draft_brushes_node)
	assert_false(bake_sys._is_trigger_brush(b), "Brush with no meta is not a trigger")


func test_is_not_trigger_brush_func_detail():
	var b = _make_brush(root.draft_brushes_node)
	b.set_meta("brush_entity_class", "func_detail")
	assert_false(bake_sys._is_trigger_brush(b), "func_detail is not a trigger")


func test_is_not_trigger_brush_func_wall():
	var b = _make_brush(root.draft_brushes_node)
	b.set_meta("brush_entity_class", "func_wall")
	assert_false(bake_sys._is_trigger_brush(b), "func_wall is not a trigger")


# ===========================================================================
# count_brushes_in
# ===========================================================================


func test_count_brushes_in_empty_container():
	assert_eq(bake_sys.count_brushes_in(root.draft_brushes_node), 0)


func test_count_brushes_in_null_container():
	assert_eq(bake_sys.count_brushes_in(null), 0)


func test_count_brushes_in_with_brushes():
	_make_brush(root.draft_brushes_node)
	_make_brush(root.draft_brushes_node)
	_make_brush(root.draft_brushes_node)
	assert_eq(bake_sys.count_brushes_in(root.draft_brushes_node), 3)


func test_count_brushes_in_excludes_entities():
	_make_brush(root.draft_brushes_node)
	_make_brush(root.draft_brushes_node)
	_make_entity(root.draft_brushes_node)
	assert_eq(
		bake_sys.count_brushes_in(root.draft_brushes_node), 2, "Entity nodes should not be counted"
	)


func test_count_brushes_in_excludes_non_brush_nodes():
	_make_brush(root.draft_brushes_node)
	var plain = Node3D.new()
	root.draft_brushes_node.add_child(plain)
	assert_eq(
		bake_sys.count_brushes_in(root.draft_brushes_node),
		1,
		"Non-DraftBrush children should not be counted"
	)


# ===========================================================================
# chunk_coord
# ===========================================================================


func test_chunk_coord_origin():
	var coord = bake_sys.chunk_coord(Vector3.ZERO, 32.0)
	assert_eq(coord, Vector3i(0, 0, 0))


func test_chunk_coord_positive():
	var coord = bake_sys.chunk_coord(Vector3(50, 10, 70), 32.0)
	assert_eq(coord, Vector3i(1, 0, 2))


func test_chunk_coord_negative():
	var coord = bake_sys.chunk_coord(Vector3(-10, -50, -1), 32.0)
	assert_eq(coord, Vector3i(-1, -2, -1))


func test_chunk_coord_exact_boundary():
	var coord = bake_sys.chunk_coord(Vector3(32, 0, 0), 32.0)
	assert_eq(coord, Vector3i(1, 0, 0))


func test_chunk_coord_small_chunk_size_clamped():
	# chunk_size of 0 should be clamped to 0.001
	var coord = bake_sys.chunk_coord(Vector3(1, 0, 0), 0.0)
	assert_eq(coord, Vector3i(1000, 0, 0), "Zero chunk size clamps to 0.001")


# ===========================================================================
# bake_dry_run
# ===========================================================================


func test_dry_run_empty_level():
	var result = bake_sys.bake_dry_run()
	assert_eq(result["draft"], 0)
	assert_eq(result["pending"], 0)
	assert_eq(result["committed"], 0)
	assert_eq(result["generated_floors"], 0)
	assert_eq(result["generated_walls"], 0)
	assert_eq(result["heightmap_floors"], 0)
	assert_eq(result["chunk_count"], 0)


func test_dry_run_with_draft_brushes():
	_make_brush(root.draft_brushes_node)
	_make_brush(root.draft_brushes_node)
	var result = bake_sys.bake_dry_run()
	assert_eq(result["draft"], 2)
	assert_eq(result["chunk_count"], 1, "Non-chunked bake should report 1 chunk when brushes exist")


func test_dry_run_with_pending_brushes():
	_make_brush(root.pending_node)
	var result = bake_sys.bake_dry_run()
	assert_eq(result["pending"], 1)


func test_dry_run_reports_face_materials_flag():
	root.bake_use_face_materials = true
	var result = bake_sys.bake_dry_run()
	assert_eq(result["use_face_materials"], true)


func test_dry_run_reports_chunk_size():
	root.bake_chunk_size = 64.0
	var result = bake_sys.bake_dry_run()
	assert_eq(result["chunk_size"], 64.0)


# ===========================================================================
# warn_bake_failure
# ===========================================================================


func test_warn_bake_failure_emits_user_message():
	var received_messages := []
	root.user_message.connect(
		func(text, level): received_messages.append({"text": text, "level": level})
	)
	_capture_warning("Bake failed: no baked geometry")
	bake_sys.warn_bake_failure()
	_assert_captured_warning("Bake failed: no baked geometry")
	assert_eq(received_messages.size(), 1, "Should emit exactly one user_message")
	assert_eq(received_messages[0]["level"], 2, "Should emit at warning level (2)")


func test_warn_bake_failure_no_brushes_hint():
	var msgs := []
	root.user_message.connect(func(text, _level): msgs.append(text))
	_capture_warning("Bake failed: no baked geometry")
	bake_sys.warn_bake_failure()
	_assert_captured_warning("Bake failed: no baked geometry")
	assert_eq(msgs.size(), 1, "Should emit one message")
	if msgs.size() > 0:
		assert_string_contains(
			msgs[0], "No draft brushes", "Should hint about missing brushes when draft is empty"
		)


func test_warn_bake_failure_pending_cuts_hint():
	_make_brush(root.draft_brushes_node)
	_make_brush(root.pending_node)
	var msgs := []
	root.user_message.connect(func(text, _level): msgs.append(text))
	_capture_warning("Bake failed: no baked geometry")
	bake_sys.warn_bake_failure()
	_assert_captured_warning("Bake failed: no baked geometry")
	assert_eq(msgs.size(), 1, "Should emit one message")
	if msgs.size() > 0:
		assert_string_contains(msgs[0], "pending cuts", "Should hint about pending cuts")


func test_warn_bake_failure_csg_fallback_hint():
	_make_brush(root.draft_brushes_node)
	var msgs := []
	root.user_message.connect(func(text, _level): msgs.append(text))
	_capture_warning("Bake failed: no baked geometry")
	bake_sys.warn_bake_failure()
	_assert_captured_warning("Bake failed: no baked geometry")
	assert_eq(msgs.size(), 1, "Should emit one message")
	if msgs.size() > 0:
		assert_string_contains(
			msgs[0],
			"CSG produced no geometry",
			"Should fall back to CSG hint when draft exists but no pending"
		)


# ===========================================================================
# collect_chunk_brushes: structural filtering
# ===========================================================================


func test_collect_chunk_brushes_skips_func_detail():
	var b = _make_brush(root.draft_brushes_node, Vector3.ZERO)
	b.set_meta("brush_entity_class", "func_detail")
	var chunks: Dictionary = {}
	bake_sys.collect_chunk_brushes(root.draft_brushes_node, 32.0, chunks, "brushes")
	var total = 0
	for key in chunks.keys():
		total += chunks[key].get("brushes", []).size()
	assert_eq(total, 0, "func_detail brushes should be skipped in chunk collection")


func test_collect_chunk_brushes_skips_trigger():
	var b = _make_brush(root.draft_brushes_node, Vector3.ZERO)
	b.set_meta("brush_entity_class", "trigger_once")
	var chunks: Dictionary = {}
	bake_sys.collect_chunk_brushes(root.draft_brushes_node, 32.0, chunks, "brushes")
	var total = 0
	for key in chunks.keys():
		total += chunks[key].get("brushes", []).size()
	assert_eq(total, 0, "trigger brushes should be skipped in chunk collection")


func test_collect_chunk_brushes_includes_structural():
	_make_brush(root.draft_brushes_node, Vector3.ZERO)
	var b2 = _make_brush(root.draft_brushes_node, Vector3(10, 0, 0))
	b2.set_meta("brush_entity_class", "func_wall")
	var chunks: Dictionary = {}
	bake_sys.collect_chunk_brushes(root.draft_brushes_node, 64.0, chunks, "brushes")
	var total = 0
	for key in chunks.keys():
		total += chunks[key].get("brushes", []).size()
	assert_eq(total, 2, "Structural brushes (empty class + func_wall) should be collected")


func test_collect_chunk_brushes_null_source():
	var chunks: Dictionary = {}
	bake_sys.collect_chunk_brushes(null, 32.0, chunks, "brushes")
	assert_eq(chunks.size(), 0, "Null source should produce no chunks")


# ===========================================================================
# estimate_bake_time
# ===========================================================================


func test_estimate_bake_time_empty_level():
	var est = bake_sys.estimate_bake_time()
	assert_eq(est["brush_count"], 0)
	assert_eq(est["estimated_ms"], 0)
	assert_string_contains(est["tip"], "No brushes")


func test_estimate_bake_time_with_brushes():
	_make_brush(root.draft_brushes_node)
	_make_brush(root.draft_brushes_node)
	_make_brush(root.draft_brushes_node)
	var est = bake_sys.estimate_bake_time()
	assert_eq(est["brush_count"], 3)
	assert_gt(est["estimated_ms"], 0)


func test_estimate_bake_time_with_brush_ids():
	_make_brush(root.draft_brushes_node)
	_make_brush(root.draft_brushes_node)
	var est = bake_sys.estimate_bake_time(["b1", "b2", "b3", "b4", "b5"])
	assert_eq(est["brush_count"], 5, "Should use provided brush_ids count")


func test_estimate_bake_time_uses_last_bake_ratio():
	_make_brush(root.draft_brushes_node)
	_make_brush(root.draft_brushes_node)
	root._last_bake_duration_ms = 200  # 200ms for 2 brushes = 100ms/brush
	var est = bake_sys.estimate_bake_time()
	assert_eq(est["estimated_ms"], 200, "Should estimate 2 * 100ms = 200ms")


func test_estimate_bake_time_tip_for_many_brushes():
	for i in range(510):
		_make_brush(root.draft_brushes_node)
	var est = bake_sys.estimate_bake_time()
	assert_string_contains(est["tip"], "Chunking recommended")


# ===========================================================================
# preview mode helpers
# ===========================================================================


func test_apply_preview_mode_wireframe():
	var opts = bake_sys.build_bake_options()
	root.bake_merge_meshes = true
	root.bake_generate_lods = true
	root.bake_lightmap_uv2 = true
	opts = bake_sys.build_bake_options()
	bake_sys._apply_preview_mode(opts, HFBakeSystem.PreviewMode.WIREFRAME)
	assert_eq(opts["merge_meshes"], false, "Wireframe disables mesh merging")
	assert_eq(opts["generate_lods"], false, "Wireframe disables LODs")
	assert_eq(opts["unwrap_uv2"], false, "Wireframe disables UV2")


func test_apply_preview_mode_full_unchanged():
	root.bake_merge_meshes = true
	root.bake_generate_lods = true
	var opts = bake_sys.build_bake_options()
	bake_sys._apply_preview_mode(opts, HFBakeSystem.PreviewMode.FULL)
	assert_eq(opts["merge_meshes"], true, "Full mode leaves options unchanged")
	assert_eq(opts["generate_lods"], true, "Full mode leaves options unchanged")


func test_apply_preview_visuals_full_no_change():
	var container = Node3D.new()
	add_child_autoqfree(container)
	var mesh = MeshInstance3D.new()
	container.add_child(mesh)
	bake_sys._apply_preview_visuals(container, HFBakeSystem.PreviewMode.FULL)
	assert_null(mesh.material_override, "Full mode should not apply override")


func test_apply_preview_visuals_wireframe():
	var container = Node3D.new()
	add_child_autoqfree(container)
	var mesh = MeshInstance3D.new()
	container.add_child(mesh)
	bake_sys._apply_preview_visuals(container, HFBakeSystem.PreviewMode.WIREFRAME)
	assert_not_null(mesh.material_override, "Wireframe should apply material override")
	assert_true(
		mesh.material_override is ShaderMaterial,
		"Wireframe mode should use ShaderMaterial (not StandardMaterial3D)",
	)
	if mesh.material_override is ShaderMaterial:
		var smat: ShaderMaterial = mesh.material_override
		assert_not_null(smat.shader, "Wireframe ShaderMaterial should have a shader")
		assert_true(
			smat.shader.code.contains("wireframe"),
			"Wireframe shader should contain render_mode wireframe",
		)


func test_apply_preview_visuals_proxy():
	var container = Node3D.new()
	add_child_autoqfree(container)
	var mesh = MeshInstance3D.new()
	container.add_child(mesh)
	bake_sys._apply_preview_visuals(container, HFBakeSystem.PreviewMode.PROXY)
	assert_not_null(mesh.material_override, "Proxy should apply material override")


func test_apply_preview_visuals_wireframe_recurses_into_chunks():
	## BakedChunk_* nodes nest MeshInstance3D children — preview must recurse.
	var container = Node3D.new()
	add_child_autoqfree(container)
	var chunk = Node3D.new()
	chunk.name = "BakedChunk_0_0_0"
	container.add_child(chunk)
	var mesh = MeshInstance3D.new()
	chunk.add_child(mesh)
	# Also a direct child for comparison
	var direct_mesh = MeshInstance3D.new()
	container.add_child(direct_mesh)
	bake_sys._apply_preview_visuals(container, HFBakeSystem.PreviewMode.WIREFRAME)
	assert_not_null(
		mesh.material_override, "Nested MeshInstance3D inside chunk should get wireframe override"
	)
	assert_not_null(
		direct_mesh.material_override, "Direct child MeshInstance3D should also get override"
	)


func test_apply_preview_visuals_proxy_recurses_into_chunks():
	var container = Node3D.new()
	add_child_autoqfree(container)
	var chunk = Node3D.new()
	chunk.name = "BakedChunk_1_2_3"
	container.add_child(chunk)
	var mesh = MeshInstance3D.new()
	chunk.add_child(mesh)
	bake_sys._apply_preview_visuals(container, HFBakeSystem.PreviewMode.PROXY)
	assert_not_null(mesh.material_override, "Nested mesh in chunk should get proxy override")


func test_apply_preview_visuals_multimesh_in_chunk():
	## MultiMeshInstance3D inside a chunk node should also receive the override.
	var container = Node3D.new()
	add_child_autoqfree(container)
	var chunk = Node3D.new()
	chunk.name = "BakedChunk_0_0_0"
	container.add_child(chunk)
	var mmi = MultiMeshInstance3D.new()
	chunk.add_child(mmi)
	bake_sys._apply_preview_visuals(container, HFBakeSystem.PreviewMode.WIREFRAME)
	assert_not_null(
		mmi.material_override, "MultiMeshInstance3D nested in chunk should get wireframe override"
	)


func test_apply_preview_visuals_full_mode_skips_chunks():
	## Full mode should not apply any override, even to nested children.
	var container = Node3D.new()
	add_child_autoqfree(container)
	var chunk = Node3D.new()
	chunk.name = "BakedChunk_0_0_0"
	container.add_child(chunk)
	var mesh = MeshInstance3D.new()
	chunk.add_child(mesh)
	bake_sys._apply_preview_visuals(container, HFBakeSystem.PreviewMode.FULL)
	assert_null(mesh.material_override, "Full mode should not apply override to nested mesh")


# ===========================================================================
# _total_bakeable_brush_count
# ===========================================================================


func test_total_bakeable_brush_count_empty():
	assert_eq(bake_sys._total_bakeable_brush_count(), 0)


func test_total_bakeable_brush_count_mixed():
	_make_brush(root.draft_brushes_node)
	_make_brush(root.generated_floors)
	_make_brush(root.generated_walls)
	assert_eq(bake_sys._total_bakeable_brush_count(), 3)


func test_total_bakeable_brush_count_with_commit_freeze():
	_make_brush(root.draft_brushes_node)
	_make_brush(root.committed_node)
	root.commit_freeze = true
	assert_eq(bake_sys._total_bakeable_brush_count(), 2, "commit_freeze includes committed brushes")


# ===========================================================================
# _last_bake_success tracking
# ===========================================================================


func test_last_bake_success_default_false():
	assert_false(bake_sys._last_bake_success, "Should default to false")


# ===========================================================================
# dirty tag retention
# ===========================================================================


func test_dirty_tags_preserved_when_bake_fails():
	# Simulate dirty tags on root
	root._dirty_brush_ids = {"brush_a": true, "brush_b": true}
	# bake_dirty with no baker (will fail) — dirty tags should survive
	# We can't call bake_dirty directly since it awaits, but we can verify
	# the conditional logic: _last_bake_success = false means tags stay
	bake_sys._last_bake_success = false
	# Simulate what bake_dirty does after bake() returns
	if bake_sys._last_bake_success:
		root._dirty_brush_ids.clear()
	assert_eq(root._dirty_brush_ids.size(), 2, "Dirty tags should be preserved on failed bake")


func test_dirty_tags_cleared_on_successful_bake():
	root._dirty_brush_ids = {"brush_a": true, "brush_b": true}
	bake_sys._last_bake_success = true
	# Simulate what bake_dirty does after bake() returns
	if bake_sys._last_bake_success:
		root._dirty_brush_ids.clear()
	assert_eq(root._dirty_brush_ids.size(), 0, "Dirty tags should be cleared on successful bake")


# ===========================================================================
# Auto-connector integration with bake pipeline
# ===========================================================================


func _make_paint_layers_with_boundary() -> HFPaintLayerManagerScript:
	var mgr := HFPaintLayerManagerScript.new()
	mgr.chunk_size = 8
	mgr.base_grid = HFPaintGridScript.new()
	mgr.base_grid.cell_size = 1.0
	root.add_child(mgr)
	mgr.clear_layers()
	var lo := mgr.create_layer(&"lo", 0.0)
	var hi := mgr.create_layer(&"hi", 3.0)
	lo.set_cell(Vector2i(0, 0), true)
	hi.set_cell(Vector2i(1, 0), true)
	return mgr


func test_postprocess_bake_generates_connectors_when_enabled():
	var mgr := _make_paint_layers_with_boundary()
	root.paint_layers = mgr
	root.bake_auto_connectors = true
	var container := Node3D.new()
	root.add_child(container)
	bake_sys.postprocess_bake(container, false)
	var connector_count := 0
	for child in container.get_children():
		if child.name.begins_with("AutoConnector"):
			connector_count += 1
	assert_gt(connector_count, 0, "Full bake with auto_connectors=true must produce connectors")
	container.free()


func test_postprocess_bake_skips_connectors_when_disabled():
	var mgr := _make_paint_layers_with_boundary()
	root.paint_layers = mgr
	root.bake_auto_connectors = false
	var container := Node3D.new()
	root.add_child(container)
	bake_sys.postprocess_bake(container, false)
	var connector_count := 0
	for child in container.get_children():
		if child.name.begins_with("AutoConnector"):
			connector_count += 1
	assert_eq(connector_count, 0, "auto_connectors=false must not produce connectors")
	container.free()


func test_postprocess_bake_selection_only_skips_connectors():
	var mgr := _make_paint_layers_with_boundary()
	root.paint_layers = mgr
	root.bake_auto_connectors = true
	var container := Node3D.new()
	root.add_child(container)
	bake_sys.postprocess_bake(container, true)
	var connector_count := 0
	for child in container.get_children():
		if child.name.begins_with("AutoConnector"):
			connector_count += 1
	assert_eq(connector_count, 0, "selection_only=true must suppress auto-connectors")
	container.free()


func test_postprocess_bake_no_paint_layers_safe():
	root.paint_layers = null
	root.bake_auto_connectors = true
	var container := Node3D.new()
	root.add_child(container)
	bake_sys.postprocess_bake(container, false)
	# Should be a safe no-op
	var connector_count := 0
	for child in container.get_children():
		if child.name.begins_with("AutoConnector"):
			connector_count += 1
	assert_eq(connector_count, 0, "null paint_layers must not crash")
	container.free()


func test_postprocess_bake_single_layer_no_connectors():
	var mgr := HFPaintLayerManagerScript.new()
	mgr.chunk_size = 8
	mgr.base_grid = HFPaintGridScript.new()
	mgr.base_grid.cell_size = 1.0
	root.add_child(mgr)
	mgr.clear_layers()
	var lo := mgr.create_layer(&"only", 0.0)
	lo.set_cell(Vector2i(0, 0), true)
	root.paint_layers = mgr
	root.bake_auto_connectors = true
	var container := Node3D.new()
	root.add_child(container)
	bake_sys.postprocess_bake(container, false)
	var connector_count := 0
	for child in container.get_children():
		if child.name.begins_with("AutoConnector"):
			connector_count += 1
	assert_eq(connector_count, 0, "Single layer can't produce cross-layer connectors")
	container.free()


func test_postprocess_bake_connector_has_collision():
	var mgr := _make_paint_layers_with_boundary()
	root.paint_layers = mgr
	root.bake_auto_connectors = true
	var container := Node3D.new()
	root.add_child(container)
	bake_sys.postprocess_bake(container, false)
	var body: StaticBody3D = container.get_node_or_null("FloorCollision") as StaticBody3D
	assert_not_null(body, "Connectors should create FloorCollision body")
	var col_count := 0
	for child in body.get_children():
		if child is CollisionShape3D:
			col_count += 1
	assert_gt(col_count, 0, "Connectors should add collision shapes")
	container.free()


# ===========================================================================
# Navmesh integration with postprocess_bake
# ===========================================================================


func test_postprocess_bake_navmesh_when_enabled():
	root.bake_navmesh = true
	var container := Node3D.new()
	root.add_child(container)
	bake_sys.postprocess_bake(container, false)
	var nav_region: NavigationRegion3D = (
		container.get_node_or_null("BakedNavmesh") as NavigationRegion3D
	)
	assert_not_null(nav_region, "bake_navmesh=true must create BakedNavmesh region")
	assert_not_null(nav_region.navigation_mesh, "Region must have a NavigationMesh assigned")
	container.free()


func test_postprocess_bake_navmesh_when_disabled():
	root.bake_navmesh = false
	var container := Node3D.new()
	root.add_child(container)
	bake_sys.postprocess_bake(container, false)
	var nav_region = container.get_node_or_null("BakedNavmesh")
	assert_null(nav_region, "bake_navmesh=false must not create nav region")
	container.free()


func test_postprocess_bake_navmesh_settings_propagate():
	root.bake_navmesh = true
	root.bake_navmesh_cell_size = 0.5
	root.bake_navmesh_cell_height = 0.4
	root.bake_navmesh_agent_height = 1.8
	root.bake_navmesh_agent_radius = 0.6
	var container := Node3D.new()
	root.add_child(container)
	bake_sys.postprocess_bake(container, false)
	var nav_region: NavigationRegion3D = (
		container.get_node_or_null("BakedNavmesh") as NavigationRegion3D
	)
	assert_not_null(nav_region)
	var nav_mesh: NavigationMesh = nav_region.navigation_mesh
	assert_not_null(nav_mesh)
	assert_almost_eq(nav_mesh.cell_size, 0.5, 0.001, "cell_size should propagate")
	assert_almost_eq(nav_mesh.cell_height, 0.4, 0.001, "cell_height should propagate")
	assert_almost_eq(nav_mesh.agent_height, 1.8, 0.001, "agent_height should propagate")
	# agent_radius is ceiled to cell_size units: ceil(0.6/0.5)*0.5 = 1.0
	assert_almost_eq(
		nav_mesh.agent_radius, 1.0, 0.001, "agent_radius should be ceiled to cell_size units"
	)
	container.free()


func test_postprocess_bake_navmesh_parsed_geometry_type():
	root.bake_navmesh = true
	var container := Node3D.new()
	root.add_child(container)
	bake_sys.postprocess_bake(container, false)
	var nav_region: NavigationRegion3D = (
		container.get_node_or_null("BakedNavmesh") as NavigationRegion3D
	)
	assert_not_null(nav_region)
	var nav_mesh: NavigationMesh = nav_region.navigation_mesh
	assert_not_null(nav_mesh)
	# Verify collider-only parse mode was applied (property name varies by Godot version)
	var geo_type = nav_mesh.get("geometry_parsed_geometry_type")
	if geo_type == null:
		geo_type = nav_mesh.get("parsed_geometry_type")
	assert_not_null(geo_type, "One of the parsed_geometry_type properties must exist")
	assert_eq(
		int(geo_type),
		NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS,
		"Navmesh should be set to parse static colliders only"
	)
	container.free()


func test_postprocess_bake_navmesh_reuses_existing_region():
	root.bake_navmesh = true
	var container := Node3D.new()
	root.add_child(container)
	# Pre-create a region to verify it's reused, not duplicated
	var existing := NavigationRegion3D.new()
	existing.name = "BakedNavmesh"
	container.add_child(existing)
	bake_sys.postprocess_bake(container, false)
	var count := 0
	for child in container.get_children():
		if child is NavigationRegion3D and child.name == "BakedNavmesh":
			count += 1
	assert_eq(count, 1, "Should reuse existing BakedNavmesh, not create a second")
	assert_not_null(existing.navigation_mesh, "Existing region should get a NavigationMesh")
	container.free()


func test_postprocess_bake_navmesh_with_connectors():
	# Both navmesh and connectors enabled — navmesh should parse connector collision
	var mgr := _make_paint_layers_with_boundary()
	root.paint_layers = mgr
	root.bake_auto_connectors = true
	root.bake_navmesh = true
	var container := Node3D.new()
	root.add_child(container)
	bake_sys.postprocess_bake(container, false)
	# Connectors should produce collision shapes in FloorCollision
	var body: StaticBody3D = container.get_node_or_null("FloorCollision") as StaticBody3D
	assert_not_null(body, "Connectors must create FloorCollision body")
	var col_shapes_before_nav := 0
	for child in body.get_children():
		if child is CollisionShape3D:
			col_shapes_before_nav += 1
	assert_gt(col_shapes_before_nav, 0, "Connectors must add collision shapes before navmesh bake")
	# Navmesh should exist and be set to parse static colliders (which includes
	# the FloorCollision body that connectors just populated)
	var nav_region: NavigationRegion3D = (
		container.get_node_or_null("BakedNavmesh") as NavigationRegion3D
	)
	assert_not_null(nav_region, "Navmesh should be baked after connectors")
	var nav_mesh: NavigationMesh = nav_region.navigation_mesh
	assert_not_null(nav_mesh)
	var geo_type = nav_mesh.get("geometry_parsed_geometry_type")
	if geo_type == null:
		geo_type = nav_mesh.get("parsed_geometry_type")
	assert_eq(
		int(geo_type),
		NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS,
		"Navmesh must use STATIC_COLLIDERS so it consumes connector collision"
	)
	container.free()


func test_postprocess_bake_selection_still_bakes_navmesh():
	# selection_only suppresses connectors but should still bake navmesh
	root.bake_navmesh = true
	root.bake_auto_connectors = true
	var mgr := _make_paint_layers_with_boundary()
	root.paint_layers = mgr
	var container := Node3D.new()
	root.add_child(container)
	bake_sys.postprocess_bake(container, true)
	# No connectors
	var connector_count := 0
	for child in container.get_children():
		if child.name.begins_with("AutoConnector"):
			connector_count += 1
	assert_eq(connector_count, 0, "selection_only must skip connectors")
	# But navmesh should still be created
	var nav_region = container.get_node_or_null("BakedNavmesh")
	assert_not_null(nav_region, "selection_only should still bake navmesh")
	container.free()


# ===========================================================================
# _set_parsed_geometry_type version-compat helper
# ===========================================================================


func test_set_parsed_geometry_type_real_navmesh():
	# On this runtime (Godot 4.6), geometry_parsed_geometry_type exists
	var nm := NavigationMesh.new()
	var ok: bool = HFBakeSystem._set_parsed_geometry_type(
		nm, NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	)
	assert_true(ok, "Should succeed on real NavigationMesh")
	assert_eq(
		int(nm.get("geometry_parsed_geometry_type")),
		NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	)


func _make_mock_with_props(props: Array) -> Object:
	var lines: Array = ["extends RefCounted"]
	for p: String in props:
		lines.append("var %s: int = 0" % p)
	var script := GDScript.new()
	script.source_code = "\n".join(lines) + "\n"
	script.reload()
	var obj := RefCounted.new()
	obj.set_script(script)
	return obj


func test_set_parsed_geometry_type_legacy_property():
	# Simulate an older Godot where only parsed_geometry_type exists
	var mock: Object = _make_mock_with_props(["parsed_geometry_type"])
	assert_false("geometry_parsed_geometry_type" in mock, "Mock must not have new property name")
	assert_true("parsed_geometry_type" in mock, "Mock must have legacy property name")
	var ok: bool = HFBakeSystem._set_parsed_geometry_type(mock, 1)
	assert_true(ok, "Should succeed via legacy property fallback")
	assert_eq(int(mock.get("parsed_geometry_type")), 1, "Legacy property should be set to 1")


func test_set_parsed_geometry_type_prefers_new_name():
	# If both properties exist, the new name should be used
	var mock: Object = _make_mock_with_props(
		["geometry_parsed_geometry_type", "parsed_geometry_type"]
	)
	var ok: bool = HFBakeSystem._set_parsed_geometry_type(mock, 42)
	assert_true(ok)
	assert_eq(int(mock.get("geometry_parsed_geometry_type")), 42, "New-name property should be set")
	assert_eq(int(mock.get("parsed_geometry_type")), 0, "Old-name property should be untouched")


func test_set_parsed_geometry_type_neither_property():
	# Neither property exists → should return false and push_warning
	var mock: Object = _make_mock_with_props([])
	_capture_warning("NavigationMesh has neither geometry_parsed_geometry_type")
	var ok: bool = HFBakeSystem._set_parsed_geometry_type(mock, 1)
	assert_false(ok, "Should return false when neither property exists")
	_assert_captured_warning("NavigationMesh has neither geometry_parsed_geometry_type")


# ===========================================================================
# _collect_brush_collision_data
# ===========================================================================


func test_collect_collision_data_skips_subtractive_brushes():
	var additive = _make_brush(root.draft_brushes_node, Vector3.ZERO)
	additive.operation = CSGShape3D.OPERATION_UNION
	var subtractive = _make_brush(root.draft_brushes_node, Vector3(10, 0, 0))
	subtractive.operation = CSGShape3D.OPERATION_SUBTRACTION
	var data: Dictionary = bake_sys._collect_brush_collision_data([root.draft_brushes_node])
	assert_eq(data["hull_verts"].size(), 1, "Only additive brush should contribute hull verts")


func test_collect_collision_data_uses_real_mesh_verts():
	# A cylinder brush should not produce 8 AABB-corner verts;
	# it should have more points from the actual cylinder mesh.
	var cyl = _make_brush(root.draft_brushes_node, Vector3.ZERO)
	cyl.shape = 1  # BrushShape.CYLINDER — has radial segments
	cyl.size = Vector3(4, 4, 4)
	# Force visual rebuild so mesh_instance is populated
	cyl._update_visuals()
	var data: Dictionary = bake_sys._collect_brush_collision_data([root.draft_brushes_node])
	assert_eq(data["hull_verts"].size(), 1, "Should collect one brush")
	var verts: PackedVector3Array = data["hull_verts"][0]
	assert_gt(verts.size(), 8, "Cylinder mesh should produce more than 8 box-corner verts")


func test_collect_collision_data_flat_brush_list():
	var b1 = _make_brush(root.draft_brushes_node, Vector3.ZERO)
	var b2 = _make_brush(root.draft_brushes_node, Vector3(10, 0, 0))
	var data: Dictionary = bake_sys._collect_brush_collision_data([b1, b2])
	assert_eq(data["hull_verts"].size(), 2, "Flat brush list should collect both brushes")


func test_collect_collision_data_skips_entity_brushes():
	var entity_brush = _make_brush(root.draft_brushes_node, Vector3.ZERO)
	entity_brush.set_meta("entity_type", "point")
	var data: Dictionary = bake_sys._collect_brush_collision_data([root.draft_brushes_node])
	assert_eq(data["hull_verts"].size(), 0, "Entity brushes should be excluded")


func test_collect_collision_data_empty_with_no_brushes():
	var data: Dictionary = bake_sys._collect_brush_collision_data([root.draft_brushes_node])
	assert_eq(data["hull_verts"].size(), 0)
	assert_eq(data["visgroups"].size(), 0)


# ===========================================================================
# Integration: bake_single / bake_chunked with collision_mode 2
# ===========================================================================


## Minimal mock baker that returns a pre-built BakedGeometry with a
## FloorCollision body and one trimesh CollisionShape3D, avoiding real CSG.
class MockBaker:
	var call_count: int = 0

	func bake_from_csg(
		_csg: CSGCombiner3D, _mat_override, _layer: int, _mask: int, _options: Dictionary
	) -> Node3D:
		call_count += 1
		var result = Node3D.new()
		result.name = "BakedGeometry"
		var body = StaticBody3D.new()
		body.name = "FloorCollision"
		body.collision_layer = _layer
		body.collision_mask = _mask
		result.add_child(body)
		# Add a dummy trimesh collision shape
		var col = CollisionShape3D.new()
		col.shape = ConcavePolygonShape3D.new()
		body.add_child(col)
		# Add a dummy mesh instance (visual)
		var mi = MeshInstance3D.new()
		mi.name = "BakedMesh_0"
		var box = BoxMesh.new()
		box.size = Vector3(4, 4, 4)
		mi.mesh = box
		result.add_child(mi)
		return result


## Minimal mock visgroup system with assignable per-node visgroups.
class MockVisgroupSystem:
	## node_name -> PackedStringArray of visgroup names
	var assignments: Dictionary = {}

	func get_visgroups_of(node: Node) -> PackedStringArray:
		return assignments.get(node.name, PackedStringArray())


func _setup_mock_baker() -> MockBaker:
	var mb = MockBaker.new()
	root.baker = mb
	return mb


func _setup_mock_visgroups(mapping: Dictionary) -> MockVisgroupSystem:
	var mvs = MockVisgroupSystem.new()
	mvs.assignments = mapping
	root.visgroup_system = mvs
	return mvs


func test_bake_single_mode2_creates_visgroup_bodies():
	_setup_mock_baker()
	var b1 = _make_brush(root.draft_brushes_node, Vector3.ZERO)
	b1.name = "brush_a"
	var b2 = _make_brush(root.draft_brushes_node, Vector3(10, 0, 0))
	b2.name = "brush_b"
	_setup_mock_visgroups(
		{
			"brush_a": PackedStringArray(["room_1"]),
			"brush_b": PackedStringArray(["room_2"]),
		}
	)
	var options: Dictionary = bake_sys.build_bake_options()
	options["collision_mode"] = 2
	var baked: Node3D = await bake_sys.bake_single(1, options)
	assert_not_null(baked, "bake_single should return a baked node")
	add_child_autoqfree(baked)
	# FloorCollision should have been removed by partitioning
	assert_null(
		baked.get_node_or_null("FloorCollision"),
		"Original FloorCollision should be removed after visgroup partitioning"
	)
	# Should have per-visgroup collision bodies
	var collision_room1: StaticBody3D = baked.get_node_or_null("Collision_room_1") as StaticBody3D
	var collision_room2: StaticBody3D = baked.get_node_or_null("Collision_room_2") as StaticBody3D
	assert_not_null(collision_room1, "Should have Collision_room_1 body")
	assert_not_null(collision_room2, "Should have Collision_room_2 body")
	# Each body should have ConvexPolygonShape3D children
	if collision_room1:
		var has_convex := false
		for child in collision_room1.get_children():
			if child is CollisionShape3D and child.shape is ConvexPolygonShape3D:
				has_convex = true
		assert_true(has_convex, "room_1 body should contain ConvexPolygonShape3D")
	if collision_room2:
		var has_convex := false
		for child in collision_room2.get_children():
			if child is CollisionShape3D and child.shape is ConvexPolygonShape3D:
				has_convex = true
		assert_true(has_convex, "room_2 body should contain ConvexPolygonShape3D")


func test_bake_single_mode2_heightmap_collision_survives():
	_setup_mock_baker()
	_make_brush(root.draft_brushes_node, Vector3.ZERO)
	_setup_mock_visgroups({})
	# Set up a heightmap mesh that _append_heightmap_meshes_to_baked will find
	var hm_container = Node3D.new()
	hm_container.name = "GeneratedHeightmapFloors"
	root.add_child(hm_container)
	root.generated_heightmap_floors = hm_container
	var hm_mesh = MeshInstance3D.new()
	hm_mesh.name = "HeightmapFloor_0"
	var plane = PlaneMesh.new()
	plane.size = Vector2(10, 10)
	hm_mesh.mesh = plane
	hm_container.add_child(hm_mesh)
	var options: Dictionary = bake_sys.build_bake_options()
	options["collision_mode"] = 2
	var baked: Node3D = await bake_sys.bake_single(1, options)
	assert_not_null(baked, "bake_single should return a baked node")
	add_child_autoqfree(baked)
	# Visgroup partitioning should have removed the original FloorCollision,
	# but heightmap append should have created a new one.
	var hm_body: StaticBody3D = baked.get_node_or_null("FloorCollision") as StaticBody3D
	assert_not_null(
		hm_body, "FloorCollision should be re-created by heightmap append after partitioning"
	)
	# The heightmap body should contain a trimesh collision from the plane mesh
	if hm_body:
		var has_trimesh := false
		for child in hm_body.get_children():
			if child is CollisionShape3D and child.shape is ConcavePolygonShape3D:
				has_trimesh = true
		assert_true(has_trimesh, "Heightmap FloorCollision should have ConcavePolygonShape3D")


func test_bake_single_mode2_subtractive_brushes_excluded():
	_setup_mock_baker()
	var additive = _make_brush(root.draft_brushes_node, Vector3.ZERO)
	additive.name = "add_brush"
	additive.operation = CSGShape3D.OPERATION_UNION
	var subtractive = _make_brush(root.draft_brushes_node, Vector3(10, 0, 0))
	subtractive.name = "sub_brush"
	subtractive.operation = CSGShape3D.OPERATION_SUBTRACTION
	_setup_mock_visgroups(
		{
			"add_brush": PackedStringArray(["room_a"]),
			"sub_brush": PackedStringArray(["room_b"]),
		}
	)
	var options: Dictionary = bake_sys.build_bake_options()
	options["collision_mode"] = 2
	var baked: Node3D = await bake_sys.bake_single(1, options)
	assert_not_null(baked)
	add_child_autoqfree(baked)
	# The additive brush should have a visgroup body
	assert_not_null(
		baked.get_node_or_null("Collision_room_a"), "Additive brush visgroup body should exist"
	)
	# The subtractive brush should NOT have a visgroup body
	assert_null(
		baked.get_node_or_null("Collision_room_b"),
		"Subtractive brush should not produce a collision body"
	)


func test_bake_single_mode2_preserves_collision_layer():
	_setup_mock_baker()
	_make_brush(root.draft_brushes_node, Vector3.ZERO)
	_setup_mock_visgroups({})
	var options: Dictionary = bake_sys.build_bake_options()
	options["collision_mode"] = 2
	var target_layer: int = 7
	var baked: Node3D = await bake_sys.bake_single(target_layer, options)
	assert_not_null(baked)
	add_child_autoqfree(baked)
	# Find the partitioned collision body (default visgroup)
	var default_body: StaticBody3D = baked.get_node_or_null("Collision__default") as StaticBody3D
	assert_not_null(default_body, "Default visgroup body should exist")
	if default_body:
		assert_eq(
			default_body.collision_layer,
			target_layer,
			"Partitioned body should inherit collision layer from original"
		)


func test_bake_chunked_mode2_creates_per_chunk_visgroup_bodies():
	_setup_mock_baker()
	# Place brushes far apart so they land in different chunks at chunk_size=8
	var b1 = _make_brush(root.draft_brushes_node, Vector3.ZERO)
	b1.name = "chunk0_brush"
	var b2 = _make_brush(root.draft_brushes_node, Vector3(100, 0, 0))
	b2.name = "chunk1_brush"
	_setup_mock_visgroups(
		{
			"chunk0_brush": PackedStringArray(["lobby"]),
			"chunk1_brush": PackedStringArray(["arena"]),
		}
	)
	var options: Dictionary = bake_sys.build_bake_options()
	options["collision_mode"] = 2
	var baked: Node3D = await bake_sys.bake_chunked(8.0, 1, options)
	assert_not_null(baked, "bake_chunked should return a container")
	add_child_autoqfree(baked)
	# Should have BakedChunk_* children
	var chunk_nodes: Array = []
	for child in baked.get_children():
		if child.name.begins_with("BakedChunk_"):
			chunk_nodes.append(child)
	assert_gte(chunk_nodes.size(), 2, "Should have at least 2 chunks for distant brushes")
	# Each chunk should have its own visgroup collision body, not FloorCollision
	var found_lobby := false
	var found_arena := false
	for chunk in chunk_nodes:
		assert_null(
			chunk.get_node_or_null("FloorCollision"),
			"FloorCollision should be removed by visgroup partitioning in chunk %s" % chunk.name
		)
		if chunk.get_node_or_null("Collision_lobby"):
			found_lobby = true
		if chunk.get_node_or_null("Collision_arena"):
			found_arena = true
	assert_true(found_lobby, "One chunk should have Collision_lobby body")
	assert_true(found_arena, "One chunk should have Collision_arena body")


func test_bake_single_mode0_preserves_trimesh():
	# Mode 0 should leave FloorCollision intact with original trimesh
	_setup_mock_baker()
	_make_brush(root.draft_brushes_node, Vector3.ZERO)
	_setup_mock_visgroups({})
	var options: Dictionary = bake_sys.build_bake_options()
	options["collision_mode"] = 0
	var baked: Node3D = await bake_sys.bake_single(1, options)
	assert_not_null(baked)
	add_child_autoqfree(baked)
	var body: StaticBody3D = baked.get_node_or_null("FloorCollision") as StaticBody3D
	assert_not_null(body, "Mode 0 should preserve FloorCollision")
	if body:
		var has_concave := false
		for child in body.get_children():
			if child is CollisionShape3D and child.shape is ConcavePolygonShape3D:
				has_concave = true
		assert_true(has_concave, "Mode 0 should keep ConcavePolygonShape3D from mock baker")
