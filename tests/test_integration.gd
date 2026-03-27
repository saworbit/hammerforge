extends GutTest
## Integration tests exercising end-to-end workflows that combine multiple
## HammerForge subsystems (brush, bake, entity, paint, snap, visgroup, state).

const HFBrushSystem = preload("res://addons/hammerforge/systems/hf_brush_system.gd")
const HFBakeSystem = preload("res://addons/hammerforge/systems/hf_bake_system.gd")
const HFEntitySystem = preload("res://addons/hammerforge/systems/hf_entity_system.gd")
const HFVisgroupSystem = preload("res://addons/hammerforge/systems/hf_visgroup_system.gd")
const HFSnapSystem = preload("res://addons/hammerforge/hf_snap_system.gd")
const HFPaintLayer = preload("res://addons/hammerforge/paint/hf_paint_layer.gd")
const HFPaintGrid = preload("res://addons/hammerforge/paint/hf_paint_grid.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")
const DraftEntity = preload("res://addons/hammerforge/draft_entity.gd")

var root: Node3D
var brush_sys: HFBrushSystem
var bake_sys: HFBakeSystem
var entity_sys: HFEntitySystem
var visgroup_sys: HFVisgroupSystem
var snap_sys: HFSnapSystem


func before_each():
	root = Node3D.new()
	root.set_script(_root_shim_script())
	add_child_autoqfree(root)

	# Draft brushes container
	var draft = Node3D.new()
	draft.name = "DraftBrushes"
	root.add_child(draft)
	root.draft_brushes_node = draft

	# Pending cuts container
	var pending = Node3D.new()
	pending.name = "Pending"
	root.add_child(pending)
	root.pending_node = pending

	# Committed cuts container
	var committed = Node3D.new()
	committed.name = "Committed"
	root.add_child(committed)
	root.committed_node = committed

	# Entities container
	var entities = Node3D.new()
	entities.name = "Entities"
	root.add_child(entities)
	root.entities_node = entities

	# Generated geometry containers (for bake system)
	var gen_floors = Node3D.new()
	gen_floors.name = "GeneratedFloors"
	root.add_child(gen_floors)
	root.generated_floors = gen_floors

	var gen_walls = Node3D.new()
	gen_walls.name = "GeneratedWalls"
	root.add_child(gen_walls)
	root.generated_walls = gen_walls

	root.generated_heightmap_floors = null
	root._brush_id_counter = 0
	root.grid_snap = 0.0
	root.face_selection = {}
	root.brush_manager = null
	root.cordon_enabled = false
	root.cordon_aabb = AABB(Vector3(-1000, -1000, -1000), Vector3(2000, 2000, 2000))
	root.entity_definitions = {}
	root.entity_definitions_path = ""

	# Instantiate subsystems in dependency order
	visgroup_sys = HFVisgroupSystem.new(root)
	root.visgroup_system = visgroup_sys
	entity_sys = HFEntitySystem.new(root)
	root.entity_system = entity_sys
	brush_sys = HFBrushSystem.new(root)
	bake_sys = HFBakeSystem.new(root)
	snap_sys = HFSnapSystem.new(root)


func after_each():
	root = null
	brush_sys = null
	bake_sys = null
	entity_sys = null
	visgroup_sys = null
	snap_sys = null


# ---------------------------------------------------------------------------
# Root shim — provides the minimal surface area required by all subsystems
# ---------------------------------------------------------------------------


func _root_shim_script() -> GDScript:
	var s = GDScript.new()
	s.source_code = """
extends Node3D

signal user_message(text: String, level: int)
signal brush_added(brush_id: String)
signal brush_removed(brush_id: String)
signal brush_changed(brush_id: String)
signal selection_changed()
signal paint_layer_changed(index: int)

var draft_brushes_node: Node3D
var pending_node: Node3D
var committed_node: Node3D
var entities_node: Node3D
var generated_floors: Node3D
var generated_walls: Node3D
var generated_heightmap_floors: Node3D
var _brush_id_counter: int = 0
var grid_snap: float = 0.0
var face_selection: Dictionary = {}
var brush_manager = null
var texture_lock: bool = false
var drag_size_default: Vector3 = Vector3(32, 32, 32)
var cordon_enabled: bool = false
var cordon_aabb: AABB = AABB(Vector3(-1000, -1000, -1000), Vector3(2000, 2000, 2000))
var entity_definitions: Dictionary = {}
var entity_definitions_path: String = ""
var visgroup_system = null
var entity_system = null
var preview_brush: Node3D = null
var bake_merge_meshes: bool = true
var bake_generate_lods: bool = false
var bake_lightmap_uv2: bool = false
var bake_lightmap_texel_size: float = 0.1
var bake_use_thread_pool: bool = false
var bake_use_face_materials: bool = false
var bake_chunk_size: float = 0.0
var commit_freeze: bool = false
var baker = null

enum BrushShape { BOX, CYLINDER, SPHERE, CONE, WEDGE, PYRAMID, PRISM_TRI, PRISM_PENT, ELLIPSOID, CAPSULE, TORUS, TETRAHEDRON, OCTAHEDRON, ICOSAHEDRON, DODECAHEDRON }

func _iter_pick_nodes() -> Array:
	var out: Array = []
	if draft_brushes_node:
		out.append_array(draft_brushes_node.get_children())
	return out

func is_entity_node(node: Node) -> bool:
	return node.has_meta(\"entity_type\") or node.has_meta(\"is_entity\")

func _log(_msg: String) -> void:
	pass

func _assign_owner(_node: Node) -> void:
	pass

func _record_last_brush(_pos: Vector3) -> void:
	pass

func tag_full_reconcile() -> void:
	pass

func tag_brush_dirty(_brush_id: String) -> void:
	pass

func begin_signal_batch() -> void:
	pass

func end_signal_batch() -> void:
	pass

func discard_signal_batch() -> void:
	pass

func _emit_or_batch(signal_name: String, args: Array) -> void:
	pass
"""
	s.reload()
	return s


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


func _make_brush(
	pos: Vector3 = Vector3.ZERO,
	sz: Vector3 = Vector3(32, 32, 32),
	brush_id: String = ""
) -> DraftBrush:
	var b = DraftBrush.new()
	b.size = sz
	if brush_id == "":
		root._brush_id_counter += 1
		brush_id = "integ_%d" % root._brush_id_counter
	b.brush_id = brush_id
	b.set_meta("brush_id", brush_id)
	root.draft_brushes_node.add_child(b)
	b.global_position = pos
	brush_sys._register_brush_id(brush_id, b)
	return b


func _make_entity(entity_name: String, entity_type: String = "point") -> DraftEntity:
	var e = DraftEntity.new()
	e.name = entity_name
	e.entity_type = entity_type
	e.entity_class = entity_type
	e.set_meta("entity_name", entity_name)
	e.set_meta("is_entity", true)
	root.entities_node.add_child(e)
	return e


# ===========================================================================
# 1. BRUSH LIFECYCLE
# ===========================================================================


func test_brush_create_find_delete():
	# Create a brush, verify it's findable, then delete and verify gone.
	var b = _make_brush(Vector3(10, 0, 0), Vector3(16, 16, 16), "life_1")
	assert_not_null(brush_sys.find_brush_by_id("life_1"), "Brush should be findable after creation")
	assert_eq(root.draft_brushes_node.get_child_count(), 1, "Draft container should have 1 child")

	brush_sys.delete_brush(b)
	assert_null(brush_sys.find_brush_by_id("life_1"), "Brush should be gone after deletion")
	assert_eq(root.draft_brushes_node.get_child_count(), 0, "Draft container should be empty")


func test_brush_create_hollow_delete_walls():
	# Create brush -> hollow -> verify 6 walls -> delete all walls -> verify empty.
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "hollow_src")
	brush_sys.hollow_brush_by_id("hollow_src", 2.0)

	var children = root.draft_brushes_node.get_children()
	assert_eq(children.size(), 6, "Hollow should produce 6 wall brushes")
	assert_null(brush_sys.find_brush_by_id("hollow_src"), "Original should be removed by hollow")

	# Delete all wall brushes
	for child in children.duplicate():
		if child is DraftBrush:
			brush_sys.delete_brush(child)
	assert_eq(root.draft_brushes_node.get_child_count(), 0, "All wall brushes should be deleted")


func test_brush_create_clip_produces_two():
	# Create brush -> clip along Y at center -> verify 2 pieces with correct total Y.
	_make_brush(Vector3(0, 0, 0), Vector3(32, 32, 32), "clip_src")
	brush_sys.clip_brush_by_id("clip_src", 1, 0.0)

	var children = root.draft_brushes_node.get_children()
	assert_eq(children.size(), 2, "Clip should produce 2 pieces")
	assert_null(brush_sys.find_brush_by_id("clip_src"), "Original should be removed by clip")

	var total_y := 0.0
	for child in children:
		if child is DraftBrush:
			total_y += (child as DraftBrush).size.y
	assert_almost_eq(total_y, 32.0, 0.01, "Clipped piece Y sizes should sum to original")


func test_brush_entity_class_excludes_from_bake():
	# Create brush -> tie to trigger_once -> verify bake system excludes it.
	var b = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "bake_excl")
	brush_sys.tie_brushes_to_entity(["bake_excl"], "trigger_once")

	assert_false(bake_sys._is_structural_brush(b), "trigger_once brush should not be structural")

	var chunks: Dictionary = {}
	bake_sys.collect_chunk_brushes(root.draft_brushes_node, 64.0, chunks, "brushes")
	var total := 0
	for key in chunks.keys():
		total += chunks[key].get("brushes", []).size()
	assert_eq(total, 0, "trigger brush should be excluded from chunk collection")


# ===========================================================================
# 2. PAINT + HEIGHTMAP WORKFLOW
# ===========================================================================


func test_paint_layer_cell_lifecycle():
	# Create a paint layer, paint cells, verify chunk data, remove layer.
	var layer = HFPaintLayer.new()
	layer.grid = HFPaintGrid.new()
	layer.chunk_size = 8
	add_child_autoqfree(layer)

	# Paint some cells
	layer.set_cell(Vector2i(3, 5), true)
	layer.set_cell(Vector2i(4, 5), true)
	layer.set_cell(Vector2i(3, 6), true)

	assert_true(layer.get_cell(Vector2i(3, 5)), "Cell (3,5) should be filled")
	assert_true(layer.get_cell(Vector2i(4, 5)), "Cell (4,5) should be filled")
	assert_true(layer.get_cell(Vector2i(3, 6)), "Cell (3,6) should be filled")

	var chunk_ids = layer.get_chunk_ids()
	assert_true(chunk_ids.size() > 0, "At least one chunk should exist after painting")

	# Verify raw chunk bits are populated
	var bits = layer.get_chunk_bits(chunk_ids[0])
	assert_true(bits.size() > 0, "Chunk bits should be populated")

	# Clear and verify
	layer.clear_chunks()
	assert_eq(layer.get_chunk_ids().size(), 0, "All chunks should be cleared")
	assert_false(layer.get_cell(Vector2i(3, 5)), "Cells should be empty after clear")


func test_heightmap_layer_paint_pixels():
	# Create a heightmap layer, verify Image exists, paint a pixel, verify changed.
	var layer = HFPaintLayer.new()
	layer.grid = HFPaintGrid.new()
	layer.chunk_size = 8
	add_child_autoqfree(layer)

	# Assign a heightmap image
	var img = Image.create(16, 16, false, Image.FORMAT_RF)
	img.fill(Color(0.0, 0, 0, 1))
	layer.heightmap = img
	layer.height_scale = 20.0

	assert_true(layer.has_heightmap(), "Layer should report having a heightmap")

	# Paint a pixel on the heightmap
	layer.heightmap.set_pixel(4, 4, Color(0.5, 0, 0, 1))
	var height = layer.get_height_at(Vector2i(4, 4))
	assert_almost_eq(height, 10.0, 0.5, "Height at painted pixel should be ~0.5 * 20.0 = 10.0")

	# Verify unpainted pixel is still zero
	var height_zero = layer.get_height_at(Vector2i(0, 0))
	assert_almost_eq(height_zero, 0.0, 0.1, "Unpainted pixel height should be ~0.0")


func test_paint_layer_material_and_blend():
	# Paint cells with material IDs and blend weights, verify they persist.
	var layer = HFPaintLayer.new()
	layer.grid = HFPaintGrid.new()
	layer.chunk_size = 8
	add_child_autoqfree(layer)

	layer.set_cell(Vector2i(2, 2), true)
	layer.set_cell_material(Vector2i(2, 2), 3)
	layer.set_cell_blend(Vector2i(2, 2), 0.8)

	assert_eq(layer.get_cell_material(Vector2i(2, 2)), 3, "Material ID should be 3")
	assert_almost_eq(layer.get_cell_blend(Vector2i(2, 2)), 0.8, 0.02, "Blend weight should be ~0.8")


# ===========================================================================
# 3. ENTITY WORKFLOW
# ===========================================================================


func test_entity_io_lifecycle():
	# Place entity -> add I/O -> verify -> delete target -> verify cleanup.
	var trigger = _make_entity("trigger_1")
	var door = _make_entity("door_1")

	entity_sys.add_entity_output(trigger, "OnTrigger", "door_1", "Open", "param1", 0.5, false)
	var outputs = entity_sys.get_entity_outputs(trigger)
	assert_eq(outputs.size(), 1, "Should have 1 output connection")
	assert_eq(outputs[0]["target_name"], "door_1")
	assert_eq(outputs[0]["input_name"], "Open")

	# Clean up dangling connections targeting "door_1"
	var removed = entity_sys.cleanup_dangling_connections("door_1")
	assert_eq(removed, 1, "Should remove 1 connection targeting door_1")
	assert_eq(entity_sys.get_entity_outputs(trigger).size(), 0, "Outputs should be empty after cleanup")


func test_entity_properties_persist_through_capture_restore():
	# Place entity -> set properties -> capture info -> restore -> verify.
	var ent = _make_entity("relay_1", "logic_relay")
	ent.entity_data["delay"] = 2.5
	ent.entity_data["fire_once"] = true
	ent.entity_data["filter_class"] = "npc_zombie"
	ent.global_position = Vector3(100, 50, 200)

	# Add I/O connection
	entity_sys.add_entity_output(ent, "OnTrigger", "light_1", "TurnOn", "", 0.0, false)

	# Capture
	var info = entity_sys.capture_entity_info(ent)
	assert_false(info.is_empty(), "Captured info should not be empty")
	assert_eq(info["entity_type"], "logic_relay")

	# Remove and restore from captured info
	root.entities_node.remove_child(ent)
	ent.queue_free()

	var restored = entity_sys.restore_entity_from_info(info)
	assert_not_null(restored, "Restored entity should not be null")
	assert_eq(restored.entity_type, "logic_relay", "Entity type should be preserved")
	assert_eq(restored.entity_data.get("delay"), 2.5, "Custom property 'delay' should be preserved")
	assert_eq(restored.entity_data.get("fire_once"), true, "Custom property 'fire_once' should be preserved")
	assert_eq(restored.entity_data.get("filter_class"), "npc_zombie", "Custom property 'filter_class' should be preserved")

	# Verify I/O outputs were restored
	var io = restored.get_meta("entity_io_outputs", [])
	assert_eq(io.size(), 1, "I/O outputs should be restored")
	assert_eq(io[0]["target_name"], "light_1")


func test_entity_multiple_io_connections():
	# Verify an entity can have multiple outputs targeting different entities.
	var button = _make_entity("button_1")
	_make_entity("door_1")
	_make_entity("light_1")
	_make_entity("alarm_1")

	entity_sys.add_entity_output(button, "OnPressed", "door_1", "Open")
	entity_sys.add_entity_output(button, "OnPressed", "light_1", "TurnOn")
	entity_sys.add_entity_output(button, "OnReset", "alarm_1", "Disable", "", 1.0, true)

	var all_conns = entity_sys.get_all_connections()
	assert_eq(all_conns.size(), 3, "Should have 3 total connections")

	# Clean up one target
	entity_sys.cleanup_dangling_connections("door_1")
	var remaining = entity_sys.get_entity_outputs(button)
	assert_eq(remaining.size(), 2, "Should have 2 remaining after door_1 cleanup")


# ===========================================================================
# 4. VISGROUP + BRUSH CROSS-SYSTEM
# ===========================================================================


func test_brush_visgroup_lifecycle():
	# Create brush -> assign visgroup -> verify membership -> delete brush -> verify cleaned up.
	var b = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "vg_brush")
	visgroup_sys.create_visgroup("lights")
	visgroup_sys.add_to_visgroup(b, "lights")

	var members = visgroup_sys.get_members_of("lights")
	assert_eq(members.size(), 1, "Visgroup should have 1 member")

	brush_sys.delete_brush(b)
	members = visgroup_sys.get_members_of("lights")
	assert_eq(members.size(), 0, "Visgroup should have 0 members after brush deletion")


func test_brush_group_cleanup_on_delete():
	# Create brushes -> group them -> delete one -> verify group adjusts.
	var b1 = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "grp_1")
	var b2 = _make_brush(Vector3(50, 0, 0), Vector3(32, 32, 32), "grp_2")
	visgroup_sys.group_selection("test_group", [b1, b2])

	assert_eq(visgroup_sys.get_group_members("test_group").size(), 2, "Group should have 2 members")

	brush_sys.delete_brush(b1)
	assert_eq(visgroup_sys.get_group_members("test_group").size(), 1, "Group should have 1 member after deletion")


func test_hollow_preserves_visgroups_and_group():
	# Create brush with visgroup + group -> hollow -> verify walls inherit metadata.
	var b = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "meta_brush")
	b.set_meta("visgroups", PackedStringArray(["detail", "interior"]))
	b.set_meta("group_id", "room_group")
	b.set_meta("brush_entity_class", "func_wall")

	brush_sys.hollow_brush_by_id("meta_brush", 2.0)

	var children = root.draft_brushes_node.get_children()
	assert_eq(children.size(), 6, "Hollow should create 6 walls")

	for child in children:
		if child is DraftBrush:
			var vgs = child.get_meta("visgroups", PackedStringArray())
			assert_true(vgs.has("detail"), "Wall should inherit 'detail' visgroup")
			assert_true(vgs.has("interior"), "Wall should inherit 'interior' visgroup")


# ===========================================================================
# 5. SNAP SYSTEM
# ===========================================================================


func test_snap_grid_basic():
	# Set grid snap mode and verify snapping works.
	assert_true(snap_sys.is_mode_on(HFSnapSystem.SnapMode.GRID), "Grid mode should be on by default")
	var result = snap_sys.snap_point(Vector3(17, 5, 23), 16.0)
	assert_eq(result, Vector3(16, 0, 16), "Should snap to nearest grid point")


func test_snap_vertex_from_brush():
	# Place a brush, enable vertex snap, verify nearby point snaps to brush corner.
	snap_sys.set_mode(HFSnapSystem.SnapMode.VERTEX, true)
	snap_sys.set_mode(HFSnapSystem.SnapMode.GRID, false)

	# Brush at origin, size 32 -> corners at +/-16 on each axis.
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "snap_b1")
	var result = snap_sys.snap_point(Vector3(15.5, 15.5, 15.5), 0.0)
	assert_eq(result, Vector3(16, 16, 16), "Should snap to nearest brush corner")


func test_snap_vertex_beats_grid_when_closer():
	# Enable both grid and vertex, place a non-grid-aligned brush, verify vertex wins.
	snap_sys.set_mode(HFSnapSystem.SnapMode.GRID, true)
	snap_sys.set_mode(HFSnapSystem.SnapMode.VERTEX, true)

	# Brush at (3,3,3) size 10 -> corner at (8,8,8) which is not on 16-grid.
	_make_brush(Vector3(3, 3, 3), Vector3(10, 10, 10), "snap_b2")
	var result = snap_sys.snap_point(Vector3(7.5, 7.5, 7.5), 16.0)
	# Vertex (8,8,8) is ~0.87 away; grid (0,0,0) is ~13 away. Vertex should win.
	assert_eq(result, Vector3(8, 8, 8), "Vertex snap should beat grid when closer")


# ===========================================================================
# 6. BRUSH + BAKE CROSS-SYSTEM
# ===========================================================================


func test_bake_dry_run_counts_mixed_brushes():
	# Create structural + non-structural brushes, verify bake dry run counts correctly.
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "struct_1")
	var b2 = _make_brush(Vector3(50, 0, 0), Vector3(16, 16, 16), "detail_1")
	b2.set_meta("brush_entity_class", "func_detail")
	_make_brush(Vector3(100, 0, 0), Vector3(8, 8, 8), "struct_2")

	var result = bake_sys.bake_dry_run()
	assert_eq(result["draft"], 3, "Should count all 3 draft brushes")
	assert_eq(result["chunk_count"], 1, "Non-chunked bake should report 1 chunk when brushes exist")


func test_collect_chunks_separates_structural():
	# Verify collect_chunk_brushes filters non-structural brushes.
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "cs_1")
	var trigger = _make_brush(Vector3(10, 0, 0), Vector3(16, 16, 16), "cs_2")
	trigger.set_meta("brush_entity_class", "trigger_multiple")
	var wall = _make_brush(Vector3(20, 0, 0), Vector3(32, 32, 32), "cs_3")
	wall.set_meta("brush_entity_class", "func_wall")

	var chunks: Dictionary = {}
	bake_sys.collect_chunk_brushes(root.draft_brushes_node, 64.0, chunks, "brushes")
	var total := 0
	for key in chunks.keys():
		total += chunks[key].get("brushes", []).size()
	assert_eq(total, 2, "Only structural brushes (plain + func_wall) should be collected")


# ===========================================================================
# 7. ENTITY I/O + REFERENCE CLEANUP CROSS-SYSTEM
# ===========================================================================


func test_entity_io_cleanup_across_multiple_sources():
	# Multiple entities connect to same target -> cleanup removes all.
	var src1 = _make_entity("src_1")
	var src2 = _make_entity("src_2")
	_make_entity("shared_target")

	entity_sys.add_entity_output(src1, "OnUse", "shared_target", "Open")
	entity_sys.add_entity_output(src2, "OnTouch", "shared_target", "Close")

	var removed = entity_sys.cleanup_dangling_connections("shared_target")
	assert_eq(removed, 2, "Should clean 2 connections from different sources")
	assert_eq(entity_sys.get_entity_outputs(src1).size(), 0)
	assert_eq(entity_sys.get_entity_outputs(src2).size(), 0)


func test_cleanup_preserves_unrelated_io():
	# Delete one target but connections to other targets survive.
	var src = _make_entity("multi_src")
	_make_entity("target_a")
	_make_entity("target_b")

	entity_sys.add_entity_output(src, "OnTrigger", "target_a", "Open")
	entity_sys.add_entity_output(src, "OnTrigger", "target_b", "Close")

	entity_sys.cleanup_dangling_connections("target_a")
	var outputs = entity_sys.get_entity_outputs(src)
	assert_eq(outputs.size(), 1, "Connection to target_b should survive")
	assert_eq(outputs[0]["target_name"], "target_b")


# ===========================================================================
# 8. BRUSH INFO ROUND-TRIP WITH METADATA
# ===========================================================================


func test_brush_info_roundtrip_with_metadata():
	# Create brush with all metadata -> capture info -> recreate -> verify.
	var b = _make_brush(Vector3(10, 20, 30), Vector3(48, 24, 64), "rt_brush")
	b.set_meta("brush_entity_class", "func_detail")
	b.set_meta("visgroups", PackedStringArray(["exterior", "props"]))
	b.set_meta("group_id", "building_1")

	var info = brush_sys.get_brush_info_from_node(b)
	assert_false(info.is_empty(), "Brush info should not be empty")

	# Delete original and recreate from info
	brush_sys.delete_brush(b)
	assert_null(brush_sys.find_brush_by_id("rt_brush"), "Original should be gone")

	var restored = brush_sys.create_brush_from_info(info)
	assert_not_null(restored, "Restored brush should not be null")
	assert_eq(
		str(restored.get_meta("brush_entity_class", "")),
		"func_detail",
		"brush_entity_class should be preserved"
	)
	var vgs = restored.get_meta("visgroups", PackedStringArray())
	assert_true(vgs.has("exterior"), "'exterior' visgroup should be preserved")
	assert_true(vgs.has("props"), "'props' visgroup should be preserved")
	assert_eq(str(restored.get_meta("group_id", "")), "building_1", "group_id should be preserved")


func test_clip_preserves_all_metadata():
	# Create brush with visgroups + group_id + entity class -> clip -> verify pieces have metadata.
	var b = _make_brush(Vector3(0, 0, 0), Vector3(32, 32, 32), "clip_meta")
	b.set_meta("brush_entity_class", "func_wall")
	b.set_meta("visgroups", PackedStringArray(["walls"]))
	b.set_meta("group_id", "corridor_1")

	brush_sys.clip_brush_by_id("clip_meta", 1, 0.0)

	var children = root.draft_brushes_node.get_children()
	assert_eq(children.size(), 2, "Clip should produce 2 pieces")

	for child in children:
		if child is DraftBrush:
			assert_eq(
				str(child.get_meta("brush_entity_class", "")), "func_wall",
				"Clipped piece should preserve brush_entity_class"
			)
			var vgs = child.get_meta("visgroups", PackedStringArray())
			assert_true(vgs.has("walls"), "Clipped piece should preserve visgroups")
			assert_eq(
				str(child.get_meta("group_id", "")), "corridor_1",
				"Clipped piece should preserve group_id"
			)
