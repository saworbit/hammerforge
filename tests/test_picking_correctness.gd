extends GutTest
## Regression coverage for viewport picking order, transforms, and visibility.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")
const DraftEntity = preload("res://addons/hammerforge/draft_entity.gd")

var root: LevelRoot


func before_each() -> void:
	root = LevelRootType.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)


func after_each() -> void:
	root = null


func _make_brush(
	brush_id: String,
	position: Vector3,
	size: Vector3 = Vector3(2, 2, 2),
	scale: Vector3 = Vector3.ONE,
	shape: int = LevelRootType.BrushShape.BOX,
) -> DraftBrush:
	var brush := (
		(
			root
			. create_brush_from_info(
				{
					"shape": shape,
					"size": size,
					"center": position,
					"operation": CSGShape3D.OPERATION_UNION,
					"brush_id": brush_id,
				}
			)
		)
		as DraftBrush
	)
	assert_not_null(brush)
	if brush:
		brush.scale = scale
	return brush


func _make_nested_entity_visual(position: Vector3, size: Vector3 = Vector3(2, 2, 2)) -> Dictionary:
	var entity := DraftEntity.new()
	entity.name = "PickEntity"
	root.add_entity(entity)
	entity.global_position = position

	var preview_root := Node3D.new()
	preview_root.name = "_EditorPreview"
	entity.add_child(preview_root, false, Node.INTERNAL_MODE_BACK)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	preview_root.add_child(visual, false, Node.INTERNAL_MODE_BACK)
	return {"entity": entity, "visual": visual}


func test_entity_visual_gathering_recurses_internal_descendants() -> void:
	var fixture := _make_nested_entity_visual(Vector3(0, 0, -5))
	var visuals: Array = []

	root._gather_visual_instances(fixture.entity, visuals)

	assert_eq(visuals.size(), 1)
	assert_same(visuals[0], fixture.visual)


func test_nearest_entity_beats_brush_even_when_brush_is_present() -> void:
	_make_brush("far_brush", Vector3(0, 0, -10))
	var fixture := _make_nested_entity_visual(Vector3(0, 0, -5))

	var picked := root.brush_system.pick_node_from_ray(Vector3.ZERO, Vector3(0, 0, -1), true)

	assert_same(picked, fixture.entity)


func test_scaled_visual_distance_stays_in_world_ray_units() -> void:
	var fixture := _make_nested_entity_visual(Vector3(0, 0, -10))
	var visual := fixture.visual as MeshInstance3D
	visual.scale = Vector3(1, 1, 2)

	var distance := root._visual_pick_distance(visual, Vector3.ZERO, Vector3(0, 0, -1))

	assert_almost_eq(distance, 8.0, 0.001)


func test_scaled_brushes_are_compared_by_world_distance() -> void:
	var near_brush := _make_brush(
		"near_thin", Vector3(0, 0, -4), Vector3(2, 2, 2), Vector3(1, 1, 0.1)
	)
	_make_brush("far_deep", Vector3(0, 0, -10), Vector3(2, 2, 2), Vector3(1, 1, 2))

	var picked := root.brush_system.pick_node_from_ray(Vector3.ZERO, Vector3(0, 0, -1), false)

	assert_same(picked, near_brush)


func test_object_pick_uses_faces_not_empty_wedge_bounds() -> void:
	var wedge := _make_brush(
		"empty_bounds",
		Vector3(0, 0, -4),
		Vector3(2, 2, 2),
		Vector3.ONE,
		LevelRootType.BrushShape.WEDGE
	)
	var far_box := _make_brush("real_surface", Vector3(0, 0, -8), Vector3(4, 4, 2))
	var origin := Vector3(0.75, 0.75, 0)
	var direction := Vector3(0, 0, -1)

	assert_gte(
		root._visual_pick_distance(wedge.mesh_instance, origin, direction),
		0.0,
		"The regression ray deliberately passes through the wedge AABB",
	)
	var picked := root.brush_system.pick_node_from_ray(origin, direction, false)
	var face_hit := root.brush_system.pick_face_from_ray(origin, direction)

	assert_same(picked, far_box)
	assert_same(face_hit.get("brush"), far_box)


func test_entity_pick_uses_preview_triangles_not_empty_cone_bounds() -> void:
	var far_box := _make_brush("entity_surface_behind", Vector3(0, 0, -8), Vector3(4, 4, 2))
	var fixture := _make_nested_entity_visual(Vector3(0, 0, -4))
	var visual := fixture.visual as MeshInstance3D
	var cone := CylinderMesh.new()
	cone.height = 2.0
	cone.bottom_radius = 1.0
	cone.top_radius = 0.0
	visual.mesh = cone
	var origin := Vector3(0.75, 0.75, 0)
	var direction := Vector3(0, 0, -1)

	assert_gte(
		root._visual_pick_distance(visual, origin, direction),
		0.0,
		"The regression ray deliberately passes through empty cone AABB space",
	)
	assert_eq(root._entity_pick_distance(fixture.entity, origin, direction), -1.0)
	assert_same(root.brush_system.pick_node_from_ray(origin, direction, true), far_box)


func test_entity_pick_hits_the_real_cone_surface() -> void:
	var fixture := _make_nested_entity_visual(Vector3(0, 0, -4))
	var cone := CylinderMesh.new()
	cone.height = 2.0
	cone.bottom_radius = 1.0
	cone.top_radius = 0.0
	(fixture.visual as MeshInstance3D).mesh = cone

	assert_same(
		root.brush_system.pick_node_from_ray(Vector3.ZERO, Vector3(0, 0, -1), true),
		fixture.entity,
	)


func test_exact_wedge_surface_returns_actual_face_position() -> void:
	var wedge := _make_brush(
		"wedge_surface",
		Vector3(0, 0, -4),
		Vector3(2, 2, 2),
		Vector3.ONE,
		LevelRootType.BrushShape.WEDGE
	)
	var hit := root.brush_system.pick_face_from_ray(Vector3(-0.75, 0, 0), Vector3(0, 0, -1))
	var hit_position: Vector3 = hit.get("position", Vector3.ZERO)

	assert_same(hit.get("brush"), wedge)
	assert_almost_eq(hit_position.z, -3.0, 0.001)


func test_empty_level_construction_plane_intersection_uses_forward_ray() -> void:
	var hit = LevelRootType.construction_plane_intersection(Vector3(2, 10, 3), Vector3(2, -10, 3))
	var miss = LevelRootType.construction_plane_intersection(Vector3(2, 10, 3), Vector3(2, 20, 3))

	assert_eq(hit, Vector3(2, 0, 3))
	assert_null(miss)


func test_hidden_visgroup_brush_is_excluded_from_object_pick() -> void:
	var hidden_near := _make_brush("hidden_near", Vector3(0, 0, -4))
	var visible_far := _make_brush("visible_far", Vector3(0, 0, -8))
	root.create_visgroup("hidden_geometry")
	root.add_selection_to_visgroup("hidden_geometry", [hidden_near])
	root.set_visgroup_visible("hidden_geometry", false)
	assert_false(hidden_near.is_visible_in_tree())

	var picked := root.brush_system.pick_node_from_ray(Vector3.ZERO, Vector3(0, 0, -1), false)

	assert_same(picked, visible_far)


func test_hidden_entity_preview_does_not_leave_an_invisible_pick_sphere() -> void:
	var visible_brush := _make_brush("visible_brush", Vector3(0, 0, -8))
	var fixture := _make_nested_entity_visual(Vector3(0, 0, -4))
	var visual := fixture.visual as MeshInstance3D
	visual.visible = false
	assert_false(visual.is_visible_in_tree())

	var picked := root.brush_system.pick_node_from_ray(Vector3.ZERO, Vector3(0, 0, -1), true)

	assert_same(picked, visible_brush)
	assert_eq(
		root._entity_pick_distance(fixture.entity, Vector3.ZERO, Vector3(0, 0, -1)),
		-1.0,
	)


func test_visible_entity_with_missing_preview_asset_keeps_a_small_pick_target() -> void:
	var fixture := _make_nested_entity_visual(Vector3(0, 0, -4))
	(fixture.visual as MeshInstance3D).mesh = null
	assert_gte(
		root._entity_pick_distance(fixture.entity, Vector3.ZERO, Vector3(0, 0, -1)),
		0.0,
	)
	assert_same(
		root.brush_system.pick_node_from_ray(Vector3.ZERO, Vector3(0, 0, -1), true),
		fixture.entity,
	)


func test_hidden_visgroup_brush_is_excluded_from_face_pick() -> void:
	var hidden_near := _make_brush("hidden_face", Vector3(0, 0, -4))
	var visible_far := _make_brush("visible_face", Vector3(0, 0, -8))
	root.create_visgroup("hidden_faces")
	root.add_selection_to_visgroup("hidden_faces", [hidden_near])
	root.set_visgroup_visible("hidden_faces", false)

	var hit := root.brush_system.pick_face_from_ray(Vector3.ZERO, Vector3(0, 0, -1))

	assert_false(hit.is_empty())
	assert_same(hit.get("brush"), visible_far)


func test_face_selection_distinguishes_shift_add_from_ctrl_toggle() -> void:
	var brush := _make_brush("face_modifiers", Vector3(0, 0, -4))
	root.toggle_face_selection(brush, 0, false, false)
	assert_eq(root.face_selection.get(brush.brush_id, []), [0])

	# Shift-add on an already-selected face is idempotent.
	root.toggle_face_selection(brush, 0, true, false)
	assert_eq(root.face_selection.get(brush.brush_id, []), [0])

	# Ctrl/Command toggle removes it and does not retain an empty brush key.
	root.toggle_face_selection(brush, 0, true, true)
	assert_false(root.face_selection.has(brush.brush_id))


func test_specialized_face_tools_use_the_canonical_visibility_aware_picker() -> void:
	var extrude_source := FileAccess.get_file_as_string(
		"res://addons/hammerforge/hf_extrude_tool.gd"
	)
	var paint_source := FileAccess.get_file_as_string(
		"res://addons/hammerforge/systems/hf_paint_system.gd"
	)
	var brush_system_source := FileAccess.get_file_as_string(
		"res://addons/hammerforge/systems/hf_brush_system.gd"
	)
	var plugin_source := FileAccess.get_file_as_string("res://addons/hammerforge/plugin.gd")
	var root_source := FileAccess.get_file_as_string("res://addons/hammerforge/level_root.gd")

	assert_true(extrude_source.contains("root.pick_face(camera, mouse_pos)"))
	assert_false(extrude_source.contains("FaceSelector.intersect_brushes"))
	assert_true(paint_source.contains("return root.pick_face(camera, mouse_pos)"))
	assert_false(paint_source.contains("FaceSelector.intersect_brushes"))

	var hover_start := root_source.find("func highlight_hovered_face")
	var hover_end := root_source.find("func clear_face_hover_highlight", hover_start)
	var hover_block := root_source.substr(hover_start, hover_end - hover_start)
	assert_true(hover_block.contains("brush_system.pick_face(camera, mouse_pos)"))
	assert_false(hover_block.contains("FaceSelector.intersect_brushes"))

	var object_hover_start := brush_system_source.find("func update_hover")
	var object_hover_end := brush_system_source.find(
		"static func should_suppress_hover", object_hover_start
	)
	var object_hover_block := brush_system_source.substr(
		object_hover_start, object_hover_end - object_hover_start
	)
	assert_true(object_hover_block.contains("brush.get_editor_outline_lines()"))
	assert_true(object_hover_block.contains("brush.global_transform"))
	assert_false(object_hover_block.contains("aabb_box_transform"))

	var picker_start := plugin_source.find("func _pick_face_material")
	var picker_end := plugin_source.find("func _apply_last_texture", picker_start)
	var picker_block := plugin_source.substr(picker_start, picker_end - picker_start)
	assert_true(picker_block.contains("root.pick_face(cam, pos)"))
	assert_false(picker_block.contains("FaceSelector.intersect_brushes"))

	var drop_start := plugin_source.find("func _handle_material_drop")
	var drop_end := plugin_source.find("func _on_context_toolbar_action", drop_start)
	var drop_block := plugin_source.substr(drop_start, drop_end - drop_start)
	assert_true(drop_block.contains("root.pick_face(camera, mouse_pos)"))
	assert_false(drop_block.contains("FaceSelector.intersect_brushes"))

	var paint_input_source := FileAccess.get_file_as_string(
		"res://addons/hammerforge/plugin_paint_input.gd"
	)
	var displacement_start := paint_input_source.find("static func should_start_displacement")
	var displacement_handle := paint_input_source.find(
		"static func handle_displacement", displacement_start
	)
	var displacement_start_block := paint_input_source.substr(
		displacement_start, displacement_handle - displacement_start
	)
	var displacement_stroke := paint_input_source.find(
		"static func do_displacement_stroke", displacement_handle
	)
	var displacement_stroke_end := paint_input_source.find(
		"static func point_near_polygon_3d", displacement_stroke
	)
	var displacement_stroke_block := paint_input_source.substr(
		displacement_stroke, displacement_stroke_end - displacement_stroke
	)
	assert_true(
		displacement_start_block.contains("_is_visible_pick(root, brush)"),
		"A hidden selected face must not start displacement painting",
	)
	assert_true(
		displacement_stroke_block.contains("_is_visible_pick(root, brush)"),
		"A face hidden during a displacement stroke must stop receiving updates",
	)
	var visibility_helper := paint_input_source.substr(
		paint_input_source.find("static func _is_visible_pick")
	)
	assert_eq(
		visibility_helper.count("root._is_pick_visible"),
		2,
		"The shared paint guard must check both the brush and its mesh visibility",
	)
