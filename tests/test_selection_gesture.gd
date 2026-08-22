extends GutTest
## Focused ownership tests for Select-tool click, marquee, and native gizmo gestures.

const SelectionGesture = preload("res://addons/hammerforge/hf_selection_gesture.gd")
const HammerForgePlugin = preload("res://addons/hammerforge/plugin.gd")
const DraftEntity = preload("res://addons/hammerforge/draft_entity.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")
const BrushChangeTracker = preload("res://addons/hammerforge/hf_brush_change_tracker.gd")
const FaceData = preload("res://addons/hammerforge/face_data.gd")
const DisplacementData = preload("res://addons/hammerforge/displacement_data.gd")
const THRESHOLD := 6.0


class SelectionScopeRoot:
	extends Node

	func is_brush_node(node: Node) -> bool:
		return node != null and str(node.get_meta("hf_kind", "")) == "brush"

	func is_entity_node(node: Node) -> bool:
		return node != null and str(node.get_meta("hf_kind", "")) == "entity"


class EntityOwnerRoot:
	extends Node3D
	var entities_node := Node3D.new()

	func _init() -> void:
		entities_node.name = "Entities"
		add_child(entities_node)

	func is_entity_node(node: Node) -> bool:
		var current := node
		while current:
			if current == entities_node:
				return true
			current = current.get_parent()
		return false


class ChangeTrackerRoot:
	extends Node3D

	@export var bake_visible_only := false
	@export var bake_chunk_size := 32.0
	@export var cordon_enabled := false
	@export var cordon_aabb := AABB(Vector3(-16, -16, -16), Vector3(32, 32, 32))
	var brushes: Array = []
	var entities: Array = []
	var dirty_ids := PackedStringArray()
	var full_reconcile_count := 0
	var structure_sync_count := 0
	var entity_name_reconciles: Array = []
	var next_brush_id := 0

	func _iter_pick_nodes() -> Array:
		return brushes + entities

	func _iter_managed_brush_nodes() -> Array:
		return brushes.duplicate()

	func is_brush_node(node: Node) -> bool:
		return node != null and str(node.get_meta("hf_kind", "")) == "brush"

	func is_entity_node(node: Node) -> bool:
		return node != null and str(node.get_meta("hf_kind", "")) == "entity"

	func tag_brush_dirty(brush_id: String) -> void:
		if not dirty_ids.has(brush_id):
			dirty_ids.append(brush_id)

	func tag_full_reconcile() -> void:
		full_reconcile_count += 1

	func reconcile_external_brush_structure() -> void:
		structure_sync_count += 1

	func reconcile_external_entity_names(previous: Dictionary, current: Dictionary) -> void:
		entity_name_reconciles.append({"previous": previous, "current": current})

	func _next_brush_id() -> String:
		next_brush_id += 1
		return "external_%d" % next_brush_id


class TrackedBrush:
	extends Node3D

	var brush_id := ""
	var size := Vector3.ONE
	var shape := 0
	var operation := 0
	var sides := 4
	var material_override: Material = null
	var faces: Array = []


func test_click_stays_below_threshold_and_marquee_starts_at_threshold() -> void:
	var gesture := _new_gesture()
	gesture.begin(Vector2(10, 20), false, false, false, true, true, false, [])

	assert_eq(
		gesture.update_motion(Vector2(15, 20), true, THRESHOLD),
		SelectionGesture.MotionDecision.WAITING,
	)
	var click := gesture.finish(Vector2(15, 20), THRESHOLD)
	assert_eq(click["decision"], SelectionGesture.ReleaseDecision.CLICK)
	assert_eq(click["distance"], 5.0)
	assert_false(gesture.is_active())

	gesture.begin(Vector2(10, 20), false, false, false, true, true, false, [])
	assert_eq(
		gesture.update_motion(Vector2(16, 20), true, THRESHOLD),
		SelectionGesture.MotionDecision.DRAW_MARQUEE,
		"The exact threshold belongs to marquee, not click",
	)
	assert_true(gesture.is_marquee_owned())
	var marquee := gesture.finish(Vector2(16, 20), THRESHOLD)
	assert_eq(marquee["decision"], SelectionGesture.ReleaseDecision.MARQUEE)
	assert_eq(marquee["origin"], Vector2(10, 20))
	assert_eq(marquee["position"], Vector2(16, 20))


func test_release_without_motion_still_classifies_threshold_as_marquee() -> void:
	var gesture := _new_gesture()
	gesture.begin(Vector2.ZERO, false, false, false, true, true, false, [])

	var result := gesture.finish(Vector2(THRESHOLD, 0), THRESHOLD)
	assert_eq(result["decision"], SelectionGesture.ReleaseDecision.MARQUEE)
	assert_eq(result["distance"], THRESHOLD)
	assert_false(gesture.is_active())


func test_native_widget_claim_overrides_pending_and_marquee_ownership() -> void:
	var gesture := _new_gesture()
	gesture.begin(Vector2.ZERO, false, false, false, true, true, true, [])
	gesture.claim_native_gizmo()

	assert_true(gesture.is_native_owned())
	assert_eq(
		gesture.update_motion(Vector2(40, 0), true, THRESHOLD),
		SelectionGesture.MotionDecision.NATIVE_GIZMO,
	)
	var pending_claim := gesture.finish(Vector2(40, 0), THRESHOLD)
	assert_eq(pending_claim["decision"], SelectionGesture.ReleaseDecision.NATIVE_GIZMO)

	# A late custom-gizmo signal must still win over a marquee already drawn for
	# this physical press; the gesture must never complete both operations.
	gesture.begin(Vector2.ZERO, false, false, false, true, true, false, [])
	assert_eq(
		gesture.update_motion(Vector2(40, 0), true, THRESHOLD),
		SelectionGesture.MotionDecision.DRAW_MARQUEE,
	)
	gesture.claim_native_gizmo()
	assert_true(gesture.is_native_owned())
	var marquee_claim := gesture.finish(Vector2(40, 0), THRESHOLD)
	assert_eq(marquee_claim["decision"], SelectionGesture.ReleaseDecision.NATIVE_GIZMO)


func test_native_candidates_yield_rmb_and_escape_before_any_value_moves() -> void:
	var gesture := _new_gesture()
	gesture.begin(Vector2.ZERO, false, false, false, false, false, true, [], true)

	assert_true(gesture.should_yield_cancel_to_native())
	assert_false(gesture.is_native_owned(), "A candidate need not have mutated a value yet")
	gesture.reset()
	assert_false(gesture.should_yield_cancel_to_native())

	gesture.begin(Vector2.ZERO, false, false, true, true, true, false, [], true)
	assert_true(
		gesture.should_yield_cancel_to_native(),
		"CUSTOM face selection must still yield cancel when an opaque gizmo may own LMB",
	)
	var release := gesture.finish(Vector2.ZERO, THRESHOLD)
	assert_true(
		release["native_cancel_candidate"],
		"Release routing must retain the press-time native-gizmo candidate",
	)


func test_native_owned_selection_yields_all_keyboard_shortcuts_to_godot() -> void:
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin.gd")
	var start := source.find("func _handle_active_selection_input")
	var finish := source.find("func _handle_extrude_mouse", start)
	var block := source.substr(start, finish - start)
	var key_guard := block.find("event is InputEventKey")
	assert_gte(key_guard, 0)
	assert_true(block.contains("_selection_gesture.should_yield_cancel_to_native()"))
	assert_true(block.contains("event.keycode == KEY_ESCAPE"))
	assert_true(block.contains("_cancel_selection_gesture()"))
	assert_lt(key_guard, block.find("event is InputEventMouseMotion"))
	assert_lt(
		key_guard,
		block.find("SELECT_INPUT_CONTINUE", block.find("if not (event is InputEventMouseButton)")),
		"Native key ownership must return before HammerForge shortcut dispatch can continue",
	)


func test_selected_transform_mutation_claims_native_before_distance_threshold() -> void:
	var selected := Node3D.new()
	add_child_autoqfree(selected)
	var gesture := _new_gesture()
	gesture.begin(Vector2.ZERO, false, false, false, true, true, true, [selected])

	selected.global_position = Vector3(1, 2, 3)
	assert_eq(
		gesture.update_motion(Vector2.ONE, true, THRESHOLD),
		SelectionGesture.MotionDecision.NATIVE_GIZMO,
		"A selected-node transform change takes precedence over click/marquee distance",
	)
	assert_true(gesture.is_native_owned())
	var result := gesture.finish(Vector2.ONE, THRESHOLD)
	assert_eq(result["decision"], SelectionGesture.ReleaseDecision.NATIVE_GIZMO)


func test_release_detects_selected_transform_mutation_without_motion_event() -> void:
	var selected := Node3D.new()
	add_child_autoqfree(selected)
	var gesture := _new_gesture()
	gesture.begin(Vector2.ZERO, false, false, false, true, true, true, [selected])

	selected.global_rotation = Vector3(0, 0.25, 0)
	var result := gesture.finish(Vector2.ONE, THRESHOLD)
	assert_eq(result["decision"], SelectionGesture.ReleaseDecision.NATIVE_GIZMO)
	assert_false(gesture.is_active())


func test_selected_node_gets_one_native_probe_before_marquee_claim() -> void:
	var selected := Node3D.new()
	add_child_autoqfree(selected)
	var gesture := _new_gesture()
	gesture.begin(Vector2.ZERO, false, false, false, true, true, true, [selected])

	assert_eq(
		gesture.update_motion(Vector2(20, 0), true, THRESHOLD),
		SelectionGesture.MotionDecision.WAITING,
		"The first forwarded motion lets the native transform gizmo mutate selection",
	)
	assert_false(gesture.is_marquee_owned())
	assert_eq(
		gesture.update_motion(Vector2(20, 0), true, THRESHOLD),
		SelectionGesture.MotionDecision.DRAW_MARQUEE,
	)
	assert_true(gesture.is_marquee_owned())


func test_press_time_modifiers_are_returned_unchanged_at_release() -> void:
	var gesture := _new_gesture()
	gesture.begin(Vector2(3, 4), true, true, true, true, true, false, [])

	var result := gesture.finish(Vector2(4, 4), THRESHOLD)
	assert_eq(result["decision"], SelectionGesture.ReleaseDecision.CLICK)
	assert_true(result["additive"])
	assert_true(result["toggle"])
	assert_true(result["face_select"])
	assert_eq(result["origin"], Vector2(3, 4))

	# A new press resets captured modifiers instead of leaking the prior press.
	gesture.begin(Vector2.ZERO, false, false, false, true, true, false, [])
	var next_result := gesture.finish(Vector2.ZERO, THRESHOLD)
	assert_false(next_result["additive"])
	assert_false(next_result["toggle"])
	assert_false(next_result["face_select"])


func test_motion_without_left_button_recovers_from_a_missed_release() -> void:
	var gesture := _new_gesture()
	gesture.begin(Vector2(8, 9), true, true, false, true, true, false, [])

	assert_eq(
		gesture.update_motion(Vector2(30, 40), false, THRESHOLD),
		SelectionGesture.MotionDecision.RECOVERED,
	)
	assert_false(gesture.is_active())
	assert_eq(gesture.owner, SelectionGesture.Owner.NONE)
	assert_eq(gesture.origin, Vector2.ZERO)
	assert_eq(gesture.current, Vector2.ZERO)
	var stale_release := gesture.finish(Vector2(30, 40), THRESHOLD)
	assert_eq(stale_release["decision"], SelectionGesture.ReleaseDecision.PASS_THROUGH)


func test_no_marquee_selected_or_native_press_remains_pass_through() -> void:
	var selected := Node3D.new()
	add_child_autoqfree(selected)
	var gesture := _new_gesture()
	gesture.begin(Vector2.ZERO, false, false, false, false, false, true, [selected])

	assert_true(gesture.native_passthrough)
	assert_eq(
		gesture.update_motion(Vector2(40, 0), true, THRESHOLD),
		SelectionGesture.MotionDecision.WAITING,
	)
	assert_false(gesture.is_marquee_owned())
	var drag_result := gesture.finish(Vector2(40, 0), THRESHOLD)
	assert_eq(drag_result["decision"], SelectionGesture.ReleaseDecision.PASS_THROUGH)

	# The same ownership policy also leaves a short click to Godot/native tools.
	gesture.begin(Vector2.ZERO, false, false, false, false, false, true, [selected])
	var click_result := gesture.finish(Vector2.ONE, THRESHOLD)
	assert_eq(click_result["decision"], SelectionGesture.ReleaseDecision.PASS_THROUGH)
	assert_false(gesture.is_active())


func test_geometry_drag_without_marquee_resolves_to_pressed_object_click() -> void:
	var gesture := _new_gesture()
	gesture.begin(Vector2(12, 18), false, false, false, false, true, false, [])

	assert_eq(
		gesture.update_motion(Vector2(90, 18), true, THRESHOLD),
		SelectionGesture.MotionDecision.WAITING,
	)
	assert_false(gesture.is_marquee_owned())
	var result := gesture.finish(Vector2(90, 18), THRESHOLD)
	assert_eq(result["decision"], SelectionGesture.ReleaseDecision.CLICK)
	assert_eq(result["origin"], Vector2(12, 18), "Selection must use the pressed geometry")


func test_reset_restores_all_defaults_and_cannot_create_native_ownership() -> void:
	var selected := Node3D.new()
	add_child_autoqfree(selected)
	var gesture := _new_gesture()
	gesture.begin(Vector2(5, 7), true, true, true, true, false, true, [selected])
	gesture.update_motion(Vector2(20, 7), true, THRESHOLD)
	gesture.reset()

	assert_eq(gesture.owner, SelectionGesture.Owner.NONE)
	assert_eq(gesture.origin, Vector2.ZERO)
	assert_eq(gesture.current, Vector2.ZERO)
	assert_false(gesture.additive)
	assert_false(gesture.toggle)
	assert_false(gesture.face_select)
	assert_false(gesture.marquee_allowed)
	assert_true(gesture.click_allowed)
	assert_false(gesture.native_passthrough)
	assert_false(gesture.native_cancel_candidate)
	assert_false(gesture._native_probe_complete)
	assert_true(gesture._transform_snapshots.is_empty())
	assert_eq(
		gesture.update_motion(Vector2.ONE, true, THRESHOLD),
		SelectionGesture.MotionDecision.IDLE,
	)

	gesture.claim_native_gizmo()
	assert_false(gesture.is_active(), "A stale native claim cannot resurrect a reset gesture")
	assert_false(gesture.is_native_owned())


func test_buttonless_motion_is_the_only_lmb_capture_recovery_signal() -> void:
	var idle_motion := InputEventMouseMotion.new()
	assert_true(HammerForgePlugin.is_lmb_release_recovery_motion(idle_motion))

	var dragging_motion := InputEventMouseMotion.new()
	dragging_motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	assert_false(HammerForgePlugin.is_lmb_release_recovery_motion(dragging_motion))

	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	assert_false(HammerForgePlugin.is_lmb_release_recovery_motion(release))


func test_plugin_routes_owned_selection_before_raycast_and_tool_dispatch() -> void:
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin.gd")
	var compact_source := source.replace("\r", "").replace("\n", "").replace("\t", "").replace(
		" ", ""
	)
	var start := source.find("func _forward_3d_gui_input")
	var finish := source.find("func _should_start_disp_paint", start)
	var forward := source.substr(start, finish - start)
	var select_route := forward.find("_handle_active_selection_input")
	assert_gte(select_route, 0)
	for competing_work in [
		"root.update_editor_grid",
		"_handle_disp_paint_input",
		"_handle_paint_input",
		"_tool_registry.dispatch_input",
		"root.update_hover",
	]:
		assert_lt(
			select_route,
			forward.find(competing_work),
			"Owned selection must route before %s" % competing_work,
		)
	assert_true(source.contains("EditorPlugin.AFTER_GUI_INPUT_CUSTOM"))
	assert_true(
		compact_source.contains("varpass_to_native:=notface_selectornative_selection_present"),
		"Every Object Select press and every native-node overlap must stay native",
	)
	assert_true(source.contains("_begin_native_selection_session"))
	assert_false(source.contains("SELECT_GIZMO_GUARD_RADIUS"))
	assert_false(source.contains("_pointer_near_selected_gizmo"))


func test_object_select_keeps_native_shift_and_leaves_ctrl_cmd_to_godot() -> void:
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin.gd")
	var start := source.find("func _handle_select_mouse")
	var finish := source.find("func custom_selection_release_result", start)
	var block := source.substr(start, finish - start)
	var compact := block.replace("\r", "").replace("\n", "").replace("\t", "").replace(" ", "")
	assert_true(
		compact.contains("varshift_selection:=event.shift_pressedorInput.is_key_pressed(KEY_SHIFT)")
	)
	assert_true(compact.contains("vartoggle:=(face_selectand("))
	assert_true(compact.contains("event.ctrl_pressedorevent.meta_pressed"))
	assert_true(compact.contains("varadditive:=shift_selectionortoggle"))
	assert_true(
		compact.contains("_begin_native_selection_session(selection_at_press,additive,toggle)")
	)


func test_face_selection_release_keeps_native_gizmo_cleanup_alive() -> void:
	assert_eq(
		HammerForgePlugin.custom_selection_release_result(true),
		EditorPlugin.AFTER_GUI_INPUT_CUSTOM,
	)
	assert_eq(
		HammerForgePlugin.custom_selection_release_result(false),
		EditorPlugin.AFTER_GUI_INPUT_PASS,
	)
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin.gd")
	var start := source.find("func _handle_active_selection_input")
	var finish := source.find("func _handle_extrude_mouse", start)
	var release_block := source.substr(start, finish - start)
	assert_true(release_block.contains("root.select_face_at_screen"))
	assert_true(release_block.contains("_select_faces_in_rect"))
	assert_eq(
		release_block.count("return custom_selection_release_result(true)"),
		2,
		"Face click and marquee releases must reach native gizmo commit/cleanup",
	)


func test_face_select_is_modal_and_hides_ambiguous_object_gizmos() -> void:
	var plugin_source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin.gd")
	var dock_source := FileAccess.get_file_as_string("res://addons/hammerforge/dock.gd")
	var builder_source := FileAccess.get_file_as_string(
		"res://addons/hammerforge/ui/paint_tab_builder.gd"
	)
	assert_true(dock_source.contains("signal face_select_mode_toggled(enabled: bool)"))
	assert_true(
		builder_source.contains(
			"dock.face_select_mode.toggled.connect(dock._on_face_select_mode_toggled)"
		)
	)

	var handler_start := plugin_source.find("func _on_face_select_mode_toggled")
	var handler_end := plugin_source.find("func _on_dock_selection_clear", handler_start)
	var handler := plugin_source.substr(handler_start, handler_end - handler_start)
	assert_true(handler.contains("_face_mode_saved_object_selection"))
	assert_true(handler.contains("hf_selection.clear()"))
	assert_true(handler.contains("_apply_hf_selection(selection)"))
	assert_true(handler.contains("dock.tool_select.set_pressed_no_signal(true)"))
	assert_true(handler.contains("dock.paint_mode.set_pressed_no_signal(false)"))
	assert_true(handler.contains("_deactivate_external_tool()"))

	var sync_start := plugin_source.find("func _on_editor_selection_changed")
	var sync_end := plugin_source.find("func should_handle_editor_object", sync_start)
	var sync_block := plugin_source.substr(sync_start, sync_end - sync_start)
	assert_true(sync_block.contains("dock.face_select_mode.set_pressed_no_signal(false)"))
	assert_true(sync_block.contains("Face Select closed for object editing"))
	assert_true(sync_block.contains("_prepare_tool_transition(root, false)"))
	assert_true(sync_block.contains("_expand_native_group_selection"))

	var forward_start := plugin_source.find("func _forward_3d_gui_input")
	var forward_end := plugin_source.find("func _should_start_disp_paint", forward_start)
	var forward := plugin_source.substr(forward_start, forward_end - forward_start)
	assert_true(forward.contains("var tool_id = 1 if face_select_mode else dock.get_tool()"))
	assert_true(
		forward.contains("var paint_mode = dock.is_paint_mode_enabled() and not face_select_mode")
	)
	assert_true(forward.contains("if _tool_registry and not face_select_mode:"))
	assert_true(
		forward.contains("if _vertex_mode and root.vertex_system and not face_select_mode:")
	)


func test_selection_runtime_state_self_heals_after_editor_hot_reload() -> void:
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin.gd")
	var ensure_start := source.find("func _ensure_selection_runtime_state")
	var ensure_end := source.find("func _begin_native_selection_session", ensure_start)
	var ensure_block := source.substr(ensure_start, ensure_end - ensure_start)
	assert_true(ensure_block.contains("_selection_gesture = HFSelectionGestureType.new()"))
	assert_true(ensure_block.contains("_native_selection_before = []"))

	var forward_start := source.find("func _forward_3d_gui_input")
	var forward_end := source.find("func _should_start_disp_paint", forward_start)
	var forward_block := source.substr(forward_start, forward_end - forward_start)
	var repair_pos := forward_block.find("_ensure_selection_runtime_state()")
	assert_gte(repair_pos, 0)
	assert_lt(
		repair_pos,
		forward_block.find("_brush_gizmo_action_active()"),
		"Hot-reload recovery must run before any gesture ownership checks",
	)


func test_native_selection_accepts_non_node3d_editor_nodes() -> void:
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin.gd")
	assert_false(
		source.contains("var first_node: Node3D = hf_selection[0]"),
		"The native Scene selection can contain CanvasItem and plain Node types",
	)
	assert_false(source.contains("var node: Node3D = hf_selection[0]"))


func test_nested_entity_children_normalize_to_the_managed_entity_owner() -> void:
	var fake_root := EntityOwnerRoot.new()
	add_child_autoqfree(fake_root)
	var entity := DraftEntity.new()
	entity.name = "Entity"
	fake_root.entities_node.add_child(entity)
	var preview_child := Node3D.new()
	preview_child.name = "PreviewChild"
	entity.add_child(preview_child)
	assert_same(
		HammerForgePlugin.normalize_managed_selection_owner(preview_child, fake_root),
		entity,
	)

	var legacy_entity := Node3D.new()
	legacy_entity.name = "LegacyEntity"
	fake_root.entities_node.add_child(legacy_entity)
	var legacy_child := Node3D.new()
	legacy_entity.add_child(legacy_child)
	assert_same(
		HammerForgePlugin.normalize_managed_selection_owner(legacy_child, fake_root),
		legacy_entity,
	)


func test_shortcut_scope_separates_native_hammerforge_and_mixed_selection() -> void:
	var fake_root := SelectionScopeRoot.new()
	add_child_autoqfree(fake_root)
	var brush := Node3D.new()
	brush.set_meta("hf_kind", "brush")
	add_child_autoqfree(brush)
	var entity := Node3D.new()
	entity.set_meta("hf_kind", "entity")
	add_child_autoqfree(entity)
	var camera := Camera3D.new()
	add_child_autoqfree(camera)

	assert_eq(
		HammerForgePlugin.classify_selection_scope([], fake_root),
		HammerForgePlugin.SelectionScope.EMPTY,
	)
	assert_eq(
		HammerForgePlugin.classify_selection_scope([camera], fake_root),
		HammerForgePlugin.SelectionScope.NATIVE_ONLY,
	)
	assert_eq(
		HammerForgePlugin.classify_selection_scope([brush, entity], fake_root),
		HammerForgePlugin.SelectionScope.HAMMERFORGE_ONLY,
	)
	assert_eq(
		HammerForgePlugin.classify_selection_scope([brush, camera], fake_root),
		HammerForgePlugin.SelectionScope.MIXED,
	)


func test_managed_shortcuts_share_the_native_and_mixed_selection_guard() -> void:
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin.gd")
	var keyboard := FileAccess.get_file_as_string("res://addons/hammerforge/plugin_input_router.gd")
	assert_true(source.contains("HFPluginInputRouter.handle_keyboard"))
	for action in [
		"delete_guard",
		"duplicate_guard",
		"group_guard",
		"hollow_guard",
		"floor_guard",
		"clip_guard",
		"carve_guard",
		"merge_guard",
		"nudge_guard",
		"texture_guard",
		"similar_guard",
		"vertex_guard",
		"save_prefab_guard",
	]:
		assert_true(keyboard.contains(action), "%s must be ownership-gated" % action)
	assert_true(source.contains("Edit HammerForge and Godot nodes separately"))

	var shortcut_start := source.find("func _shortcut_input")
	var shortcut_end := source.find("func _cancel_escape_step", shortcut_start)
	var shortcut := source.substr(shortcut_start, shortcut_end - shortcut_start)
	assert_true(shortcut.contains('_guard_hammerforge_shortcut(root, false, 1, "Nudge")'))
	assert_true(shortcut.contains("_brush_gizmo_action_active()"))
	assert_true(shortcut.contains("_selection_gesture.should_yield_cancel_to_native()"))
	assert_lt(
		shortcut.find("_brush_gizmo_action_active()"),
		shortcut.find("if event.keycode == KEY_ESCAPE:"),
		"Native gizmos must own shortcuts before HammerForge's Escape/nudge paths",
	)


func test_every_managed_action_surface_uses_the_shared_scope_guard() -> void:
	var delete_requirement := HammerForgePlugin.managed_surface_action_requirement("delete")
	assert_false(delete_requirement["brushes_only"])
	assert_eq(delete_requirement["minimum"], 1)
	var merge_requirement := HammerForgePlugin.managed_surface_action_requirement("merge")
	assert_true(merge_requirement["brushes_only"])
	assert_eq(merge_requirement["minimum"], 2)
	assert_true(
		HammerForgePlugin.managed_surface_action_requirement("apply_to_brush")["allow_faces"]
	)
	assert_true(HammerForgePlugin.managed_surface_action_requirement("toggle_grid").is_empty())

	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin.gd")
	for method_name in [
		"_on_context_toolbar_action",
		"_on_hotkey_palette_action",
		"_dispatch_viewport_action",
	]:
		var start := source.find("func %s" % method_name)
		var finish := source.find("\nfunc ", start + 1)
		var block := source.substr(start, finish - start)
		assert_true(
			block.contains("_managed_action_surface_allowed(root, action)"),
			"%s must reject mixed selection before dispatch" % method_name,
		)
	var material_start := source.find("func _on_context_material_apply")
	var material_end := source.find("\nfunc ", material_start + 1)
	var material_block := source.substr(material_start, material_end - material_start)
	assert_true(
		material_block.contains('_managed_action_surface_allowed(root, "apply_context_material")')
	)


func test_plugin_recovers_stale_gizmo_and_lmb_owners_before_tool_motion() -> void:
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin.gd")
	var start := source.find("func _forward_3d_gui_input")
	var finish := source.find("func _should_start_disp_paint", start)
	var forward := source.substr(start, finish - start)
	var gizmo_guard := forward.find("_brush_gizmo_action_active()")
	var recover := forward.find("_recover_stale_lmb_gestures(root)")
	assert_gte(gizmo_guard, 0)
	assert_gt(recover, gizmo_guard)
	assert_lt(recover, forward.find("_handle_disp_paint_input"))
	assert_lt(recover, forward.find("_tool_registry.dispatch_input"))

	var gizmo_source := FileAccess.get_file_as_string(
		"res://addons/hammerforge/brush_gizmo_plugin.gd"
	)
	assert_true(gizmo_source.contains("func cancel_active_handle_action() -> bool:"))
	assert_true(gizmo_source.contains("_active_handle_restore"))
	assert_true(
		gizmo_source.contains("apply_resize_transaction(brush, _active_handle_restore, true")
	)


func test_focus_loss_cancels_transient_pointer_ownership() -> void:
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin.gd")
	var notify_start := source.find("func _notification")
	var enter_start := source.find("func _enter_tree", notify_start)
	var focus_block := source.substr(notify_start, enter_start - notify_start)
	assert_true(focus_block.contains("NOTIFICATION_APPLICATION_FOCUS_OUT"))
	assert_true(focus_block.contains("NOTIFICATION_WM_WINDOW_FOCUS_OUT"))
	assert_true(focus_block.contains("_rmb_camera_navigation.active = false"))
	assert_false(
		focus_block.contains("cancel_active_handle_action"),
		"Godot must settle and clear its own gizmo during focus loss",
	)
	assert_true(focus_block.contains("_cancel_selection_gesture()"))
	assert_true(focus_block.contains("_tool_registry.cancel_active_pointer_capture()"))
	assert_true(focus_block.contains("_prepare_tool_transition(root, false, false)"))

	var recovery_start := source.find("func _recover_stale_lmb_gestures")
	var recovery_end := source.find("func _handle_rmb_cancel", recovery_start)
	var recovery_block := source.substr(recovery_start, recovery_end - recovery_start)
	assert_true(recovery_block.contains("_tool_registry.recover_active_pointer_capture()"))

	var active_start := source.find("func _handle_active_selection_input")
	var active_end := source.find("func _select_faces_in_rect", active_start)
	var active_block := source.substr(active_start, active_end - active_start)
	var recovered_start := active_block.find("HFSelectionGestureType.MotionDecision.RECOVERED:")
	var recovered_end := active_block.find(
		"HFSelectionGestureType.MotionDecision.NATIVE_GIZMO:", recovered_start
	)
	var recovered_block := active_block.substr(recovered_start, recovered_end - recovered_start)
	assert_true(recovered_block.contains("_cancel_selection_gesture()"))


func test_face_marquee_honors_toggle_and_visibility_contracts() -> void:
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin.gd")
	assert_false(
		source.contains("func _select_nodes_in_rect"),
		"Object marquee belongs wholly to Godot's native viewport selection",
	)

	var face_start := source.find("func _select_faces_in_rect")
	var face_end := source.find("func _face_screen_center", face_start)
	var face_block := source.substr(face_start, face_end - face_start)
	assert_true(face_block.contains("toggle: bool = false"))
	assert_true(face_block.contains("brush.is_visible_in_tree()"))
	assert_true(face_block.contains("root.is_brush_node(brush)"))
	assert_true(face_block.contains("root.pick_face(camera, center)"))
	assert_true(face_block.contains('visible_hit.get("brush") != brush'))
	assert_true(face_block.contains("indices.erase(i)"))


func test_idle_external_tool_rmb_starts_one_native_camera_session() -> void:
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin.gd")
	var forward_start := source.find("func _forward_3d_gui_input")
	var forward_end := source.find("func _should_start_disp_paint", forward_start)
	var forward := source.substr(forward_start, forward_end - forward_start)
	var dispatch_pos := forward.find("_tool_registry.dispatch_input")
	var vertex_pos := forward.find("# Vertex editing mode intercept", dispatch_pos)
	var external_block := forward.substr(dispatch_pos, vertex_pos - dispatch_pos)
	assert_true(external_block.contains("event.button_index == MOUSE_BUTTON_RIGHT"))
	assert_true(external_block.contains("_rmb_camera_navigation.begin()"))
	assert_lt(
		external_block.find("_rmb_camera_navigation.begin()"),
		external_block.find("return EditorPlugin.AFTER_GUI_INPUT_PASS"),
	)


func test_marquee_draws_in_the_native_3d_viewport_overlay() -> void:
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin.gd")
	assert_true(source.contains("set_force_draw_over_forwarding_enabled()"))
	assert_true(source.contains("func _forward_3d_force_draw_over_viewport"))
	assert_true(source.contains("viewport_control.draw_rect"))
	assert_true(source.contains("update_overlays()"))
	assert_false(
		source.contains(
			"add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _marquee_overlay)"
		),
		"A viewport marquee must not be laid out or clipped by the spatial toolbar",
	)


func test_native_marquee_expands_and_toggles_groups_as_units() -> void:
	var first := Node3D.new()
	var second := Node3D.new()
	add_child_autoqfree(first)
	add_child_autoqfree(second)
	var groups := {"pair": [first, second]}

	var added := HammerForgePlugin.expand_native_group_members([], [first], false, groups)
	assert_has(added, first)
	assert_has(added, second)

	var toggled_off := HammerForgePlugin.expand_native_group_members(
		[first, second], [second], true, groups
	)
	assert_true(toggled_off.is_empty(), "Native removal of one member removes the whole group")

	var plain_reselect := HammerForgePlugin.expand_native_group_members(
		[first, second], [first], false, groups
	)
	assert_has(plain_reselect, first)
	assert_has(plain_reselect, second)

	var replaced_member := HammerForgePlugin.expand_native_group_members(
		[first], [second], false, groups
	)
	assert_has(replaced_member, first)
	assert_has(replaced_member, second)

	var toggled_replacement := HammerForgePlugin.expand_native_group_members(
		[first], [second], true, groups
	)
	assert_true(
		toggled_replacement.is_empty(),
		"Equal member counts can still represent a native member replacement",
	)

	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin.gd")
	var finalize_start := source.find("func _finalize_native_selection")
	var finalize_end := source.find("func _normalize_editor_selection", finalize_start)
	var finalize_block := source.substr(finalize_start, finalize_end - finalize_start)
	assert_true(finalize_block.contains("toggle or additive"))
	var sync_start := source.find("func _on_editor_selection_changed")
	var sync_end := source.find("func should_handle_editor_object", sync_start)
	var sync_block := source.substr(sync_start, sync_end - sync_start)
	assert_true(sync_block.contains("_normalize_editor_selection(nodes, root)"))
	assert_true(sync_block.contains("_expand_native_group_selection"))


func test_group_removal_uses_the_owner_sessions_actual_modifier_intent() -> void:
	assert_false(
		HammerForgePlugin.group_removal_requested(false, false, false, false, false, false),
		"A plain Scene-tree reselect must expand the group instead of clearing it",
	)
	assert_true(
		HammerForgePlugin.group_removal_requested(false, false, false, true, false, false),
		"A modified Scene-tree removal should remove the complete group",
	)
	assert_true(HammerForgePlugin.group_removal_requested(true, true, false, false, false, false))
	assert_false(
		HammerForgePlugin.group_removal_requested(true, false, false, false, true, false),
		"Ambient Ctrl cannot reinterpret an already-captured native viewport press",
	)


func test_native_brush_change_tracker_is_exact_idempotent_and_undo_safe() -> void:
	var fake_root := ChangeTrackerRoot.new()
	add_child_autoqfree(fake_root)
	var brush_a := _new_tracked_brush(fake_root, "brush_a")
	var brush_b := _new_tracked_brush(fake_root, "brush_b")
	var tracker := BrushChangeTracker.new()
	tracker.prime(fake_root)

	brush_a.position = Vector3(4, 2, -1)
	assert_eq(tracker.reconcile(fake_root), PackedStringArray(["brush_a"]))
	assert_eq(fake_root.dirty_ids, PackedStringArray(["brush_a"]))
	assert_true(tracker.reconcile(fake_root).is_empty(), "A repeated release hook is a no-op")
	assert_eq(fake_root.dirty_ids, PackedStringArray(["brush_a"]))

	# Simulate a successful incremental bake, then native Undo and Redo. Both
	# transitions must become dirty again even though selection did not change.
	fake_root.dirty_ids.clear()
	brush_a.transform = Transform3D.IDENTITY
	assert_eq(tracker.reconcile(fake_root), PackedStringArray(["brush_a"]))
	fake_root.dirty_ids.clear()
	brush_a.position = Vector3(4, 2, -1)
	assert_eq(tracker.reconcile(fake_root), PackedStringArray(["brush_a"]))

	fake_root.dirty_ids.clear()
	brush_b.rotation = Vector3(0.2, 0.4, 0.1)
	brush_b.scale = Vector3(2, 1, 0.5)
	assert_eq(tracker.reconcile(fake_root), PackedStringArray(["brush_b"]))

	fake_root.dirty_ids.clear()
	brush_a.visible = false
	assert_eq(tracker.reconcile(fake_root), PackedStringArray(["brush_a"]))
	fake_root.dirty_ids.clear()
	brush_a.visible = true
	assert_eq(
		tracker.reconcile(fake_root),
		PackedStringArray(["brush_a"]),
		"Undoing Scene-tree visibility must invalidate visible-only bakes",
	)
	assert_true(tracker.reconcile(fake_root).is_empty())


func test_native_bake_configuration_edits_tag_one_full_reconcile_per_change() -> void:
	var fake_root := ChangeTrackerRoot.new()
	add_child_autoqfree(fake_root)
	_new_tracked_brush(fake_root, "stable_brush")
	var tracker := BrushChangeTracker.new()
	tracker.prime(fake_root)

	fake_root.bake_visible_only = true
	assert_true(tracker.reconcile(fake_root).is_empty())
	assert_eq(fake_root.full_reconcile_count, 1)
	assert_true(fake_root.dirty_ids.is_empty())
	assert_true(tracker.reconcile(fake_root).is_empty())
	assert_eq(fake_root.full_reconcile_count, 1, "A stable setting must not repeatedly retag")

	fake_root.cordon_enabled = true
	fake_root.cordon_aabb = AABB(Vector3(-8, -4, -2), Vector3(16, 8, 4))
	assert_true(tracker.reconcile(fake_root).is_empty())
	assert_eq(
		fake_root.full_reconcile_count,
		2,
		"Multiple Inspector properties changed before one reconcile need one full tag",
	)

	# Native Undo returns through the same version-change hook and is itself a
	# new bake configuration, so it must invalidate the current output once.
	fake_root.cordon_enabled = false
	fake_root.cordon_aabb = AABB(Vector3(-16, -16, -16), Vector3(32, 32, 32))
	assert_true(tracker.reconcile(fake_root).is_empty())
	assert_eq(fake_root.full_reconcile_count, 3)


func test_brush_change_tracker_covers_inspector_geometry_and_root_switches() -> void:
	var first_root := ChangeTrackerRoot.new()
	add_child_autoqfree(first_root)
	var brush := _new_tracked_brush(first_root, "inspector_brush")
	var tracker := BrushChangeTracker.new()
	tracker.prime(first_root)
	brush.size = Vector3(2, 3, 4)
	assert_eq(tracker.reconcile(first_root), PackedStringArray(["inspector_brush"]))
	first_root.dirty_ids.clear()
	brush.shape = 3
	brush.operation = 2
	brush.sides = 12
	brush.material_override = StandardMaterial3D.new()
	assert_eq(tracker.reconcile(first_root), PackedStringArray(["inspector_brush"]))
	assert_eq(first_root.dirty_ids, PackedStringArray(["inspector_brush"]))

	var second_root := ChangeTrackerRoot.new()
	add_child_autoqfree(second_root)
	var second := _new_tracked_brush(second_root, "second_brush")
	second.position = Vector3.UP
	assert_true(tracker.reconcile(second_root).is_empty(), "A new scene seeds without false dirt")
	second.position = Vector3.UP * 2.0
	assert_eq(tracker.reconcile(second_root), PackedStringArray(["second_brush"]))

	first_root.brushes.erase(brush)
	assert_true(tracker.reconcile(first_root).is_empty(), "Returning to a root re-seeds safely")
	first_root.brushes.append(brush)
	tracker.prime(first_root)

	var duplicate := _new_tracked_brush(first_root, "inspector_brush")
	assert_true(tracker.reconcile(first_root).is_empty(), "New structure is not a property edit")
	assert_ne(
		duplicate.brush_id, brush.brush_id, "A native duplicate must receive a stable unique ID"
	)
	assert_eq(str(duplicate.get_meta("brush_id")), duplicate.brush_id)
	assert_eq(first_root.full_reconcile_count, 1)
	assert_eq(first_root.structure_sync_count, 1)
	first_root.brushes.erase(duplicate)
	first_root.remove_child(duplicate)
	duplicate.queue_free()
	assert_true(tracker.reconcile(first_root).is_empty())
	assert_eq(first_root.full_reconcile_count, 2, "A native deletion requires authoritative bake")
	assert_eq(first_root.structure_sync_count, 2)

	var pending := Node3D.new()
	pending.name = "PendingCuts"
	first_root.add_child(pending)
	brush.reparent(pending)
	assert_true(tracker.reconcile(first_root).is_empty())
	assert_same(brush.get_parent(), first_root)
	assert_eq(
		first_root.full_reconcile_count,
		2,
		"An unsynchronized Scene-tree move must be repaired before it corrupts structure",
	)
	brush.reparent(pending)
	brush.set_meta("hf_container_role", "pending")
	assert_true(tracker.reconcile(first_root).is_empty())
	brush.reparent(first_root)
	brush.set_meta("hf_container_role", "draft")
	assert_true(tracker.reconcile(first_root).is_empty())
	assert_eq(
		first_root.full_reconcile_count,
		2,
		"A managed container move with a synchronized role must only re-seed",
	)

	var entity := Node3D.new()
	entity.name = "Door"
	entity.set_meta("hf_kind", "entity")
	first_root.add_child(entity)
	first_root.entities.append(entity)
	tracker.prime(first_root)
	entity.name = "MainDoor"
	assert_true(tracker.reconcile(first_root).is_empty())
	assert_eq(first_root.entity_name_reconciles.size(), 1)
	assert_eq(first_root.entity_name_reconciles[0]["previous"][entity.get_instance_id()], "Door")
	assert_eq(first_root.entity_name_reconciles[0]["current"][entity.get_instance_id()], "MainDoor")
	brush.name = "Door"
	tracker.prime(first_root)
	brush.name = "RenamedStructuralBrush"
	assert_true(tracker.reconcile(first_root).is_empty())
	assert_eq(
		first_root.entity_name_reconciles.size(),
		1,
		"Renaming an ordinary brush must not hijack a same-named entity I/O target",
	)


func test_change_tracker_recovers_only_live_illegally_reparented_brushes() -> void:
	var fake_root := ChangeTrackerRoot.new()
	add_child_autoqfree(fake_root)
	var drafts := Node3D.new()
	drafts.name = "DraftBrushes"
	fake_root.add_child(drafts)
	var pending := Node3D.new()
	pending.name = "PendingCuts"
	fake_root.add_child(pending)
	var entities := Node3D.new()
	entities.name = "Entities"
	fake_root.add_child(entities)

	var brush := TrackedBrush.new()
	brush.brush_id = "reparented_brush"
	brush.set_meta("brush_id", brush.brush_id)
	brush.set_meta("hf_kind", "brush")
	brush.set_meta("hf_container_role", "draft")
	drafts.add_child(brush)
	fake_root.brushes.append(brush)
	var tracker := BrushChangeTracker.new()
	tracker.prime(fake_root)

	brush.reparent(entities)
	assert_true(tracker.reconcile(fake_root).is_empty())
	assert_same(
		brush.get_parent(),
		drafts,
		"A Scene-tree drag into a non-brush container must return to its managed parent",
	)
	assert_eq(fake_root.full_reconcile_count, 0)

	# A synchronized managed move is intentional, and an Undo-like restoration
	# back to DraftBrushes must update the cached parent in both directions.
	brush.reparent(pending)
	brush.set_meta("hf_container_role", "pending")
	assert_true(tracker.reconcile(fake_root).is_empty())
	assert_same(brush.get_parent(), pending)
	brush.reparent(drafts)
	brush.set_meta("hf_container_role", "draft")
	assert_true(tracker.reconcile(fake_root).is_empty())
	assert_same(brush.get_parent(), drafts)

	# Native deletion detaches before the authoritative index catches up. Never
	# re-add that node: soft entity I/O references must remain Undo-restorable.
	drafts.remove_child(brush)
	fake_root.brushes.erase(brush)
	assert_true(tracker.reconcile(fake_root).is_empty())
	assert_null(brush.get_parent())
	assert_eq(fake_root.full_reconcile_count, 1)
	brush.free()


func test_native_entity_duplicate_unlinks_prefab_metadata_without_touching_source() -> void:
	var fake_root := ChangeTrackerRoot.new()
	add_child_autoqfree(fake_root)
	var source_entity := Node3D.new()
	source_entity.name = "LinkedDoor"
	source_entity.set_meta("hf_kind", "entity")
	var prefab_meta := {
		"hf_prefab_entity_id": "door_uid",
		"hf_prefab_instance": "instance_7",
		"hf_prefab_source": "res://prefabs/door.hfprefab",
		"hf_prefab_variant": "locked",
	}
	for meta_name in prefab_meta:
		source_entity.set_meta(meta_name, prefab_meta[meta_name])
	fake_root.add_child(source_entity)
	fake_root.entities.append(source_entity)
	var tracker := BrushChangeTracker.new()
	tracker.prime(fake_root)

	var native_copy := source_entity.duplicate() as Node3D
	fake_root.add_child(native_copy)
	fake_root.entities.append(native_copy)
	assert_true(tracker.reconcile(fake_root).is_empty())
	for meta_name in prefab_meta:
		assert_eq(source_entity.get_meta(meta_name), prefab_meta[meta_name])
		assert_false(
			native_copy.has_meta(meta_name),
			"A native entity copy must be independent from its source prefab instance",
		)


func test_brush_change_tracker_covers_nested_face_resource_inspector_edits() -> void:
	var fake_root := ChangeTrackerRoot.new()
	add_child_autoqfree(fake_root)
	var brush := _new_tracked_brush(fake_root, "face_resource_brush")
	var face := FaceData.new()
	face.local_verts = PackedVector3Array(
		[Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, 1)]
	)
	face.ensure_geometry()
	var layer := FaceData.PaintLayer.new()
	layer.weight_image = Image.create(2, 2, false, Image.FORMAT_RGBA8)
	layer.weight_image.fill(Color.BLACK)
	face.paint_layers = [layer]
	var displacement := DisplacementData.new()
	displacement.init_flat(2)
	face.displacement = displacement
	brush.faces = [face]
	var tracker := BrushChangeTracker.new()
	tracker.prime(fake_root)

	face.uv_offset = Vector2(3, -2)
	assert_eq(tracker.reconcile(fake_root), PackedStringArray(["face_resource_brush"]))
	fake_root.dirty_ids.clear()
	face.local_verts[0] = Vector3(-2, 0, -1)
	assert_eq(tracker.reconcile(fake_root), PackedStringArray(["face_resource_brush"]))
	fake_root.dirty_ids.clear()
	layer.opacity = 0.4
	assert_eq(tracker.reconcile(fake_root), PackedStringArray(["face_resource_brush"]))
	fake_root.dirty_ids.clear()
	layer.weight_image.set_pixel(0, 0, Color.WHITE)
	assert_eq(tracker.reconcile(fake_root), PackedStringArray(["face_resource_brush"]))
	fake_root.dirty_ids.clear()
	displacement.distances[0] = 2.5
	assert_eq(tracker.reconcile(fake_root), PackedStringArray(["face_resource_brush"]))
	assert_eq(fake_root.dirty_ids, PackedStringArray(["face_resource_brush"]))

	var preview_brush := DraftBrush.new()
	preview_brush.shape = preview_brush.BrushShape.CUSTOM
	preview_brush.brush_id = "preview_brush"
	preview_brush.set_meta("brush_id", "preview_brush")
	preview_brush.set_meta("hf_kind", "brush")
	var preview_face := FaceData.new()
	preview_face.local_verts = PackedVector3Array(
		[Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, 1)]
	)
	preview_face.ensure_geometry()
	var preview_layer := FaceData.PaintLayer.new()
	preview_layer.weight_image = Image.create(2, 2, false, Image.FORMAT_RGBA8)
	preview_layer.weight_image.fill(Color.BLACK)
	preview_face.paint_layers = [preview_layer]
	var preview_displacement := DisplacementData.new()
	preview_displacement.init_flat(2)
	preview_face.displacement = preview_displacement
	preview_brush.faces = [preview_face]
	preview_brush.operation = CSGShape3D.OPERATION_SUBTRACTION
	var prefab_meta := {
		"hf_prefab_entity_id": "brush_uid",
		"hf_prefab_instance": "instance_3",
		"hf_prefab_source": "res://prefabs/room.hfprefab",
		"hf_prefab_variant": "damaged",
	}
	for meta_name in prefab_meta:
		preview_brush.set_meta(meta_name, prefab_meta[meta_name])
	fake_root.add_child(preview_brush)
	fake_root.brushes.append(preview_brush)
	tracker.prime(fake_root)
	assert_almost_eq(preview_brush.mesh_instance.mesh.get_aabb().end.x, 1.0, 0.001)
	preview_face.local_verts[1] = Vector3(3, 0, -1)
	assert_eq(tracker.reconcile(fake_root), PackedStringArray(["preview_brush"]))
	assert_almost_eq(
		preview_brush.mesh_instance.mesh.get_aabb().end.x,
		3.0,
		0.001,
		"Nested Inspector geometry must refresh the live preview in the same reconcile",
	)
	assert_true(tracker.reconcile(fake_root).is_empty(), "Preview refresh must not phantom-dirty")

	var native_copy := preview_brush.duplicate() as DraftBrush
	var stale_base := MeshInstance3D.new()
	stale_base.name = "MeshCopy"
	stale_base.set_meta("_hammerforge_base_mesh", true)
	native_copy.add_child(stale_base)
	var stale_overlay := MeshInstance3D.new()
	stale_overlay.name = "_SubtractWireOverlayCopy"
	stale_overlay.set_meta("_hammerforge_visual_overlay", "subtract")
	native_copy.add_child(stale_overlay)
	fake_root.add_child(native_copy)
	fake_root.brushes.append(native_copy)
	assert_true(tracker.reconcile(fake_root).is_empty())
	assert_ne(native_copy.brush_id, preview_brush.brush_id)
	assert_same(native_copy.mesh_instance.get_parent(), native_copy)
	var base_mesh_count := 0
	var overlay_count := 0
	for child in native_copy.get_children(true):
		if not child is MeshInstance3D:
			continue
		if bool(child.get_meta("_hammerforge_base_mesh", false)):
			base_mesh_count += 1
		if child.has_meta("_hammerforge_visual_overlay"):
			overlay_count += 1
	assert_eq(base_mesh_count, 1, "A native copy must adopt exactly one private base mesh")
	assert_eq(overlay_count, 1, "Stale copied overlays must collapse to the one required cue")
	for meta_name in prefab_meta:
		assert_eq(preview_brush.get_meta(meta_name), prefab_meta[meta_name])
		assert_false(native_copy.has_meta(meta_name))
	assert_not_same(native_copy.faces[0], preview_brush.faces[0])
	assert_not_same(native_copy.faces[0].paint_layers[0], preview_brush.faces[0].paint_layers[0])
	assert_not_same(
		native_copy.faces[0].paint_layers[0].weight_image,
		preview_brush.faces[0].paint_layers[0].weight_image,
	)
	assert_not_same(native_copy.faces[0].displacement, preview_brush.faces[0].displacement)
	var original_vertex := preview_brush.faces[0].local_verts[0]
	native_copy.faces[0].local_verts[0] += Vector3.LEFT
	assert_eq(preview_brush.faces[0].local_verts[0], original_vertex)


func test_plugin_defers_one_shared_native_and_inspector_brush_reconcile() -> void:
	var source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin.gd")
	assert_true(source.contains("func _queue_managed_brush_reconcile"))
	assert_true(source.contains("func _reconcile_managed_brush_changes"))
	assert_true(source.contains("_ensure_brush_change_tracker().reconcile(root)"))
	var version_start := source.find("func _on_undo_redo_version_changed")
	var version_end := source.find("func _on_replay_requested", version_start)
	assert_true(
		source.substr(version_start, version_end - version_start).contains(
			"_queue_managed_brush_reconcile()"
		)
	)
	var release_start := source.find("func _handle_active_selection_input")
	var release_end := source.find("func _handle_extrude_mouse", release_start)
	assert_true(
		source.substr(release_start, release_end - release_start).contains(
			"_queue_managed_brush_reconcile()"
		)
	)


func _new_gesture() -> SelectionGesture:
	var gesture := SelectionGesture.new()
	autofree(gesture)
	return gesture


func _new_tracked_brush(fake_root: ChangeTrackerRoot, brush_id: String) -> TrackedBrush:
	var brush := TrackedBrush.new()
	brush.brush_id = brush_id
	brush.set_meta("brush_id", brush_id)
	brush.set_meta("hf_kind", "brush")
	brush.set_meta("hf_container_role", "draft")
	fake_root.add_child(brush)
	fake_root.brushes.append(brush)
	return brush
