extends GutTest

const HFBrushSystem = preload("res://addons/hammerforge/systems/hf_brush_system.gd")
const HFBakeSystem = preload("res://addons/hammerforge/systems/hf_bake_system.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")

var root: BakeSpyRoot
var brush_sys: HFBrushSystem
var bake_sys: HFBakeSystem


## The real level with only its bake intercepted. Commit Cuts' tests need to see
## whether it asked for subtraction-aware CSG and to choose whether the bake
## succeeded, without running one.
class BakeSpyRoot:
	extends LevelRoot

	var last_force_csg := false

	func bake(
		_apply_cuts: bool = true,
		_hide_live: bool = false,
		_collision_layer_mask: int = 0,
		_preview_mode: int = 0,
		force_csg: bool = false
	) -> bool:
		last_force_csg = force_csg
		await get_tree().process_frame
		return bool(bake_system.get("_last_bake_success"))


func before_each():
	root = BakeSpyRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	brush_sys = root.brush_system
	bake_sys = root.bake_system


func after_each():
	root = null
	brush_sys = null
	bake_sys = null


func _make_brush(
	pos: Vector3 = Vector3.ZERO, sz: Vector3 = Vector3(32, 32, 32), brush_id: String = ""
) -> DraftBrush:
	var b = DraftBrush.new()
	b.size = sz
	if brush_id == "":
		root._brush_id_counter += 1
		brush_id = "test_%d" % root._brush_id_counter
	b.brush_id = brush_id
	b.set_meta("brush_id", brush_id)
	root.draft_brushes_node.add_child(b)
	b.global_position = pos
	brush_sys._register_brush_id(brush_id, b)
	return b


func test_commit_cuts_preserves_cutters_on_failure_and_stashes_only_after_success():
	root.commit_freeze = false

	var cutter := DraftBrush.new()
	cutter.brush_id = "commit_guard"
	cutter.set_meta("brush_id", "commit_guard")
	brush_sys._add_pending_cut(cutter)
	brush_sys._register_brush_id(cutter.brush_id, cutter)
	bake_sys._last_bake_success = false
	assert_false(await brush_sys.commit_cuts())
	assert_same(cutter.get_parent(), root.pending_node)
	assert_true(cutter.visible, "Failed commit must leave its cutter editable")
	assert_eq(brush_sys.get_live_brush_count(), 1)
	assert_same(brush_sys.find_brush_by_id(cutter.brush_id), cutter)

	root.commit_freeze = true
	bake_sys._last_bake_success = true
	assert_true(await brush_sys.commit_cuts())
	assert_true(root.last_force_csg, "Commit Cuts must force subtraction-aware CSG output")
	assert_same(cutter.get_parent(), root.committed_node)
	assert_false(cutter.visible)
	assert_eq(brush_sys.get_live_brush_count(), 0)
	assert_null(brush_sys.find_brush_by_id(cutter.brush_id))


func test_commit_cuts_without_freeze_detaches_cutters_before_returning():
	root.commit_freeze = false
	var cutter := DraftBrush.new()
	cutter.brush_id = "commit_remove_now"
	cutter.set_meta("brush_id", cutter.brush_id)
	brush_sys._add_pending_cut(cutter)
	brush_sys._register_brush_id(cutter.brush_id, cutter)
	bake_sys._last_bake_success = true

	assert_true(await brush_sys.commit_cuts())

	assert_null(cutter.get_parent(), "Committed cutter must leave source tree synchronously")
	assert_true(cutter.is_queued_for_deletion())
	assert_eq(root.draft_brushes_node.get_child_count(), 0)
	assert_eq(root.pending_node.get_child_count(), 0)


func test_commit_cuts_without_cutters_is_a_safe_noop():
	assert_false(await brush_sys.commit_cuts())

	assert_false(root.last_force_csg, "An empty commit must not start a bake")


# ===========================================================================
# Tie / Untie
# ===========================================================================


func test_tie_sets_brush_entity_class():
	var b = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	var initial_material := b.mesh_instance.material_override as StandardMaterial3D
	assert_not_null(initial_material)
	brush_sys.tie_brushes_to_entity(["b1"], "func_detail")
	var bec = str(b.get_meta("brush_entity_class", ""))
	assert_eq(bec, "func_detail", "Tie should set brush_entity_class meta")
	var overlay := b.get_node_or_null("_BrushEntityOverlay") as MeshInstance3D
	assert_not_null(
		overlay,
		"Tie should show the entity cue immediately without waiting for a rebuild",
	)
	var tied_material := b.mesh_instance.material_override as StandardMaterial3D
	assert_not_null(tied_material, "Tie should keep the base brush visibly styled")
	if overlay:
		var overlay_id := overlay.get_instance_id()
		brush_sys.tie_brushes_to_entity(["b1"], "trigger_once")
		var retied := b.get_node_or_null("_BrushEntityOverlay") as MeshInstance3D
		assert_not_null(retied)
		if retied:
			assert_eq(
				retied.get_instance_id(),
				overlay_id,
				"Changing entity class should update the existing overlay in place",
			)


func test_tie_multiple_brushes():
	var b1 = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	var b2 = _make_brush(Vector3(10, 0, 0), Vector3(32, 32, 32), "b2")
	brush_sys.tie_brushes_to_entity(["b1", "b2"], "trigger_once")
	assert_eq(str(b1.get_meta("brush_entity_class", "")), "trigger_once")
	assert_eq(str(b2.get_meta("brush_entity_class", "")), "trigger_once")


func test_untie_removes_brush_entity_class():
	var b = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	brush_sys.tie_brushes_to_entity(["b1"], "func_detail")
	assert_not_null(b.get_node_or_null("_BrushEntityOverlay"))
	brush_sys.untie_brushes_from_entity(["b1"])
	assert_false(b.has_meta("brush_entity_class"), "Untie should remove brush_entity_class meta")
	assert_null(
		b.get_node_or_null("_BrushEntityOverlay"),
		"Untie should remove the entity cue synchronously",
	)
	var restored_material := b.mesh_instance.material_override as StandardMaterial3D
	assert_not_null(restored_material, "Untie should restore the normal additive styling")
	if restored_material:
		assert_eq(restored_material.albedo_color, Color(0.2, 0.8, 0.2, 0.35))


func test_untie_only_affects_specified_brushes():
	var b1 = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	var b2 = _make_brush(Vector3(10, 0, 0), Vector3(32, 32, 32), "b2")
	brush_sys.tie_brushes_to_entity(["b1", "b2"], "func_wall")
	brush_sys.untie_brushes_from_entity(["b1"])
	assert_false(b1.has_meta("brush_entity_class"), "b1 should be untied")
	assert_eq(str(b2.get_meta("brush_entity_class", "")), "func_wall", "b2 should remain tied")


func test_tie_all_entity_classes():
	var classes = ["func_detail", "func_wall", "trigger_once", "trigger_multiple"]
	for cls in classes:
		var b = _make_brush(Vector3.ZERO, Vector3(32, 32, 32))
		var bid = b.brush_id
		brush_sys.tie_brushes_to_entity([bid], cls)
		assert_eq(str(b.get_meta("brush_entity_class", "")), cls, "Should support class: " + cls)


func test_untie_nonexistent_brush_noop():
	# Should not crash
	brush_sys.untie_brushes_from_entity(["nonexistent_id"])
	assert_true(true, "Untie of nonexistent brush should not crash")


# ===========================================================================
# Structural brush filtering
# ===========================================================================


func test_structural_brush_no_entity_class():
	var b = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	assert_true(HFBakeSystem.is_structural_brush(b), "Brush without entity class is structural")


func test_non_structural_func_wall():
	var b = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	b.set_meta("brush_entity_class", "func_wall")
	assert_false(HFBakeSystem.is_structural_brush(b), "func_wall is NOT structural (#827)")


func test_non_structural_func_detail():
	var b = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	b.set_meta("brush_entity_class", "func_detail")
	assert_false(HFBakeSystem.is_structural_brush(b), "func_detail is NOT structural")


func test_non_structural_trigger_once():
	var b = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	b.set_meta("brush_entity_class", "trigger_once")
	assert_false(HFBakeSystem.is_structural_brush(b), "trigger_once is NOT structural")


func test_non_structural_trigger_multiple():
	var b = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	b.set_meta("brush_entity_class", "trigger_multiple")
	assert_false(HFBakeSystem.is_structural_brush(b), "trigger_multiple is NOT structural")


func test_non_structural_func_clip():
	var b = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	b.set_meta("brush_entity_class", "func_clip")
	assert_false(HFBakeSystem.is_structural_brush(b), "func_clip takes no part in the CSG (#1409)")


# ===========================================================================
# Collect chunk brushes filters non-structural
# ===========================================================================


func test_collect_excludes_func_detail():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	var b2 = _make_brush(Vector3(10, 0, 0), Vector3(32, 32, 32), "b2")
	b2.set_meta("brush_entity_class", "func_detail")
	var chunks: Dictionary = {}
	bake_sys.collect_chunk_brushes(root.draft_brushes_node, 64.0, chunks, "brushes")
	var total = 0
	for key in chunks.keys():
		total += chunks[key].get("brushes", []).size()
	assert_eq(total, 1, "func_detail brush should be excluded from structural collection")


func test_collect_excludes_func_wall():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	var b2 = _make_brush(Vector3(10, 0, 0), Vector3(32, 32, 32), "b2")
	b2.set_meta("brush_entity_class", "func_wall")
	var chunks: Dictionary = {}
	bake_sys.collect_chunk_brushes(root.draft_brushes_node, 64.0, chunks, "brushes")
	var total = 0
	for key in chunks.keys():
		total += chunks[key].get("brushes", []).size()
	assert_eq(total, 1, "func_wall brushes stay out of the structural collection")


func test_collect_excludes_triggers():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	var b2 = _make_brush(Vector3(10, 0, 0), Vector3(32, 32, 32), "b2")
	b2.set_meta("brush_entity_class", "trigger_once")
	var b3 = _make_brush(Vector3(20, 0, 0), Vector3(32, 32, 32), "b3")
	b3.set_meta("brush_entity_class", "trigger_multiple")
	var chunks: Dictionary = {}
	bake_sys.collect_chunk_brushes(root.draft_brushes_node, 64.0, chunks, "brushes")
	var total = 0
	for key in chunks.keys():
		total += chunks[key].get("brushes", []).size()
	assert_eq(total, 1, "Trigger brushes should be excluded from structural collection")


func test_collect_excludes_func_clip():
	var world := _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	var clip := _make_brush(Vector3(10, 0, 0), Vector3(32, 32, 32), "b2")
	clip.set_meta("brush_entity_class", "func_clip")
	var chunks: Dictionary = {}
	bake_sys.collect_chunk_brushes(root.draft_brushes_node, 64.0, chunks, "brushes")
	var total = 0
	for key in chunks.keys():
		total += chunks[key].get("brushes", []).size()
	assert_eq(total, 1, "a clip is in no chunk's CSG")
	assert_eq(bake_sys.collect_face_bake_brushes(), [world], "nor in the face bake's mesh")


# ===========================================================================
# Brush info round-trip with entity class
# ===========================================================================


func test_get_brush_info_includes_entity_class():
	var b = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "b1")
	b.set_meta("brush_entity_class", "func_detail")
	var info = brush_sys.get_brush_info_from_node(b)
	assert_eq(str(info.get("brush_entity_class", "")), "func_detail")


func test_create_brush_from_info_restores_entity_class():
	var info = {
		"shape": 0,  # BOX
		"size": Vector3(32, 32, 32),
		"center": Vector3.ZERO,
		"operation": CSGShape3D.OPERATION_UNION,
		"brush_id": "restored_1",
		"brush_entity_class": "trigger_once",
	}
	var brush = brush_sys.create_brush_from_info(info)
	assert_not_null(brush, "Should create brush from info")
	assert_eq(
		str(brush.get_meta("brush_entity_class", "")),
		"trigger_once",
		"Restored brush should have brush_entity_class"
	)
	assert_not_null(
		brush.get_node_or_null("_BrushEntityOverlay"),
		"Restored entity brushes should render their semantic cue immediately",
	)


# ===========================================================================
# A brush entity's own properties (#728)
# ===========================================================================

const HFEntityPropUtils = preload("res://addons/hammerforge/ui/hf_entity_prop_utils.gd")


func _tied_brush(entity_class: String = "func_door") -> DraftBrush:
	var brush := DraftBrush.new()
	root.draft_brushes_node.add_child(brush)
	brush.set_meta("brush_entity_class", entity_class)
	return brush


func test_a_tied_brush_is_recognised_as_a_brush_entity():
	var brush := _tied_brush()
	assert_true(HFEntityPropUtils.is_brush_entity(brush))
	assert_eq(HFEntityPropUtils.get_entity_type(brush), "func_door", "and names its class")


func test_a_property_set_on_a_brush_entity_is_kept():
	# The setter used to require an `entity_data` meta a brush does not have, so
	# the call was accepted and dropped with no error anywhere.
	var brush := _tied_brush()
	HFEntityPropUtils.set_entity_property(brush, "speed", 4.0)
	HFEntityPropUtils.set_entity_property(brush, "angle", 0.0)
	var data := HFEntityPropUtils.get_entity_data(brush)
	assert_almost_eq(float(data.get("speed", -1.0)), 4.0, 0.001)
	assert_almost_eq(float(data.get("angle", -1.0)), 0.0, 0.001)


func test_it_is_kept_under_the_key_that_already_round_trips():
	# `brush_entity_data` is what the brush capture and the .map writer read, so
	# writing anywhere else would have been a value that never left the session.
	var brush := _tied_brush()
	HFEntityPropUtils.set_entity_property(brush, "speed", 4.0)
	assert_true(brush.has_meta("brush_entity_data"), "the key the format already carries")
	assert_almost_eq(
		float((brush.get_meta("brush_entity_data") as Dictionary).get("speed", -1.0)), 4.0, 0.001
	)


func test_a_plain_brush_is_not_a_brush_entity():
	var brush := DraftBrush.new()
	root.draft_brushes_node.add_child(brush)
	assert_false(HFEntityPropUtils.is_brush_entity(brush), "untied is not tied")
	HFEntityPropUtils.set_entity_property(brush, "speed", 4.0)
	assert_false(brush.has_meta("brush_entity_data"), "and gets no properties invented for it")


func test_a_brush_entity_property_survives_the_brush_capture():
	var brush := _tied_brush()
	HFEntityPropUtils.set_entity_property(brush, "speed", 4.0)
	var info: Dictionary = brush_sys.get_brush_info_from_node(brush)
	assert_true(info.has("brush_entity_data"), "the capture carries it: %s" % str(info.keys()))
	assert_almost_eq(
		float((info["brush_entity_data"] as Dictionary).get("speed", -1.0)), 4.0, 0.001
	)


# ===========================================================================
# What a brush keeps when it is untied or tied as another class (#1112)
# ===========================================================================


## A box tied as a trigger_once, wired OnStartTouch to a lamp and aimed at "x".
func _wired_trigger(brush_id: String) -> DraftBrush:
	var brush: DraftBrush = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), brush_id)
	brush_sys.tie_brushes_to_entity([brush_id], "trigger_once", "trig_" + brush_id)
	root.add_entity_output(brush, "OnStartTouch", "lamp_1", "TurnOn")
	HFEntityPropUtils.set_entity_property(brush, "target", "x")
	return brush


func _wires(brush: DraftBrush) -> Array:
	var names: Array = []
	for wire in brush.get_meta("entity_io_outputs", []):
		names.append(str(wire.get("output_name", "")))
	return names


func test_untie_drops_the_brush_s_wires_and_properties():
	var brush := _wired_trigger("u1")
	assert_eq(_wires(brush), ["OnStartTouch"], "wired before")
	brush_sys.untie_brushes_from_entity(["u1"])
	assert_false(brush.has_meta("entity_io_outputs"), "no wires left on plain geometry")
	assert_false(brush.has_meta("brush_entity_data"), "and no properties")
	brush_sys.tie_brushes_to_entity(["u1"], "func_door")
	assert_eq(HFEntityPropUtils.get_entity_data(brush), {}, "so a door made of it starts clean")
	assert_eq(_wires(brush), [])


func test_a_brush_tied_as_another_class_keeps_only_what_that_class_declares():
	var brush := _wired_trigger("u2")
	brush_sys.tie_brushes_to_entity(["u2"], "trigger_multiple")
	assert_eq(_wires(brush), ["OnStartTouch"], "a trigger_multiple has OnStartTouch too")
	assert_eq(HFEntityPropUtils.get_entity_data(brush).get("target"), "x", "and a target")
	brush_sys.tie_brushes_to_entity(["u2"], "func_door")
	assert_eq(_wires(brush), [], "a door has no OnStartTouch")
	assert_false(HFEntityPropUtils.get_entity_data(brush).has("target"), "and no target")


func test_a_tie_as_the_same_class_keeps_everything():
	var brush := _wired_trigger("u3")
	brush_sys.tie_brushes_to_entity(["u3"], "trigger_once", "renamed")
	assert_eq(_wires(brush), ["OnStartTouch"])
	assert_eq(HFEntityPropUtils.get_entity_data(brush).get("target"), "x")


func test_undo_of_an_untie_brings_the_wires_and_properties_back():
	var brush := _wired_trigger("u4")
	var before: Dictionary = root.capture_brush_scope(["u4"], [])
	brush_sys.untie_brushes_from_entity(["u4"])
	root.restore_brush_scope(before)
	var back := root.find_brush_by_id("u4") as DraftBrush
	assert_not_null(back)
	if back != null:
		assert_eq(_wires(back), ["OnStartTouch"])
		assert_eq(HFEntityPropUtils.get_entity_data(back).get("target"), "x")


# ===========================================================================
# Properties go on every brush of the entity (#1113)
# ===========================================================================


func test_a_property_set_through_one_leaf_goes_on_every_leaf_of_the_door():
	var a: DraftBrush = _make_brush(Vector3.ZERO, Vector3(32, 32, 32), "l1")
	var b: DraftBrush = _make_brush(Vector3(40, 0, 0), Vector3(32, 32, 32), "l2")
	var other: DraftBrush = _make_brush(Vector3(80, 0, 0), Vector3(32, 32, 32), "l3")
	brush_sys.tie_brushes_to_entity(["l1", "l2"], "func_door")
	brush_sys.tie_brushes_to_entity(["l3"], "func_door")
	assert_eq(root.entity_property_nodes(a), [a, b], "one tie is one door")
	root.set_entity_property(a, "speed", 300.0)
	assert_eq(HFEntityPropUtils.get_entity_data(b).get("speed"), 300.0, "the other leaf too")
	assert_false(
		HFEntityPropUtils.get_entity_data(other).has("speed"), "a door tied on its own is apart"
	)
	root.set_entity_properties(b, {"wait": 2.0})
	assert_eq(HFEntityPropUtils.get_entity_data(a).get("wait"), 2.0, "and through either leaf")
