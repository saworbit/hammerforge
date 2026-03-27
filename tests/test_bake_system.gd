extends GutTest

const HFBakeSystem = preload("res://addons/hammerforge/systems/hf_bake_system.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")

var root: Node3D
var bake_sys: HFBakeSystem


func before_each():
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
	root = null
	bake_sys = null


func _root_shim_script() -> GDScript:
	var s = GDScript.new()
	s.source_code = """
extends Node3D

signal user_message(text, level)

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
var bake_lightmap_uv2: bool = false
var bake_lightmap_texel_size: float = 0.1
var bake_use_thread_pool: bool = false
var bake_use_face_materials: bool = false
var bake_chunk_size: float = 0.0
var commit_freeze: bool = false
var baker = null

func is_entity_node(node: Node) -> bool:
	return node.has_meta("entity_type")

func _log(_msg: String) -> void:
	pass
"""
	s.reload()
	return s


func _make_brush(parent: Node3D, pos: Vector3 = Vector3.ZERO, sz: Vector3 = Vector3(4, 4, 4)) -> DraftBrush:
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
	assert_has(opts, "unwrap_uv2")
	assert_has(opts, "uv2_texel_size")
	assert_has(opts, "use_thread_pool")
	assert_has(opts, "use_face_materials")


func test_build_bake_options_reflects_root_defaults():
	var opts = bake_sys.build_bake_options()
	assert_eq(opts["merge_meshes"], true)
	assert_eq(opts["generate_lods"], false)
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
	assert_eq(bake_sys.count_brushes_in(root.draft_brushes_node), 2, "Entity nodes should not be counted")


func test_count_brushes_in_excludes_non_brush_nodes():
	_make_brush(root.draft_brushes_node)
	var plain = Node3D.new()
	root.draft_brushes_node.add_child(plain)
	assert_eq(bake_sys.count_brushes_in(root.draft_brushes_node), 1, "Non-DraftBrush children should not be counted")


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
	root.user_message.connect(func(text, level): received_messages.append({"text": text, "level": level}))
	bake_sys.warn_bake_failure()
	assert_eq(received_messages.size(), 1, "Should emit exactly one user_message")
	assert_eq(received_messages[0]["level"], 2, "Should emit at warning level (2)")


func test_warn_bake_failure_no_brushes_hint():
	var msgs := []
	root.user_message.connect(func(text, _level): msgs.append(text))
	bake_sys.warn_bake_failure()
	assert_eq(msgs.size(), 1, "Should emit one message")
	if msgs.size() > 0:
		assert_string_contains(msgs[0], "No draft brushes", "Should hint about missing brushes when draft is empty")


func test_warn_bake_failure_pending_cuts_hint():
	_make_brush(root.draft_brushes_node)
	_make_brush(root.pending_node)
	var msgs := []
	root.user_message.connect(func(text, _level): msgs.append(text))
	bake_sys.warn_bake_failure()
	assert_eq(msgs.size(), 1, "Should emit one message")
	if msgs.size() > 0:
		assert_string_contains(msgs[0], "pending cuts", "Should hint about pending cuts")


func test_warn_bake_failure_csg_fallback_hint():
	_make_brush(root.draft_brushes_node)
	var msgs := []
	root.user_message.connect(func(text, _level): msgs.append(text))
	bake_sys.warn_bake_failure()
	assert_eq(msgs.size(), 1, "Should emit one message")
	if msgs.size() > 0:
		assert_string_contains(msgs[0], "CSG produced no geometry", "Should fall back to CSG hint when draft exists but no pending")


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
