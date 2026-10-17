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


# ---------------------------------------------------------------------------
# The plugin's own face pickers, through the real plugin
# ---------------------------------------------------------------------------

const PluginRig = preload("res://tests/support/plugin_rig.gd")
const STOP := EditorPlugin.AFTER_GUI_INPUT_STOP
## The middle of the rig's viewport, where the camera looks at the origin.
const AIM := Vector2(400, 300)

var rig := PluginRig.new()


func before_all() -> void:
	await rig.bring_up(self)


func after_all() -> void:
	await rig.take_down()


func _paint_all(brush: Node, material_idx: int) -> void:
	for face in brush.faces:
		face.material_idx = material_idx


## A box at the origin with material 2 on every face, and a smaller one with
## material 1 between it and the rig camera.
func _one_in_front_of_another(level: Node) -> Dictionary:
	level.set_materials(
		[StandardMaterial3D.new(), StandardMaterial3D.new(), StandardMaterial3D.new()]
	)
	var back = rig.box(level, "back", Vector3.ZERO, Vector3(8, 8, 8))
	var front = rig.box(level, "front", Vector3(0, 6, 8), Vector3(4, 4, 4))
	_paint_all(back, 2)
	_paint_all(front, 1)
	# The pointer over the viewport, so the plugin has the camera.
	rig.forward(PluginRig.motion(AIM))
	return {"back": back, "front": front}


## The texture picker samples the face the user can see: the box in front while
## it is shown, the one behind once it is hidden.
func test_the_texture_picker_samples_only_what_can_be_seen() -> void:
	var level = await rig.make_level()
	var boxes := _one_in_front_of_another(level)
	rig.plugin._hotkey_palette.action_invoked.emit("texture_picker")
	assert_eq(rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, true, AIM)), STOP, "a click picks")
	assert_has(rig.toasts(), "Picked material #1", "the box in front")
	boxes["front"].visible = false
	rig.clear_toasts()
	rig.plugin._hotkey_palette.action_invoked.emit("texture_picker")
	rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, true, AIM))
	assert_has(rig.toasts(), "Picked material #2", "and, hidden, the box behind it")
	await rig.leave_level(level)


## A material dropped where a hidden box is in front lands on the box behind it.
func test_a_material_drop_lands_on_what_can_be_seen() -> void:
	var level = await rig.make_level()
	var boxes := _one_in_front_of_another(level)
	boxes["front"].visible = false
	rig.plugin._drop_data(AIM, {"type": "hammerforge_material", "index": 0})
	var landed := false
	for face in boxes["back"].faces:
		landed = landed or face.material_idx == 0
	assert_true(landed, "the box behind took the material")
	for face in boxes["front"].faces:
		assert_eq(face.material_idx, 1, "and the hidden one did not")
	await rig.leave_level(level)


## A sculpt does not start on a face that cannot be seen, whether the brush or
## only its mesh is hidden, and a face hidden partway through a stroke stops
## taking it.
func test_a_hidden_face_takes_no_sculpt() -> void:
	var level = await rig.make_level()
	var box = rig.box(level, "d", Vector3.ZERO, Vector3(16, 16, 16))
	var top := -1
	for i in box.faces.size():
		if box.faces[i].normal.y > 0.99:
			top = i
	assert_true(level.create_displacement("d", top, 2), "the top face is sculptable")
	level.face_selection = {"d": [top]}
	rig.plugin._toggle_paint_mode()
	rig.plugin.dock._disp_section.set_expanded(true)
	var on_top := rig.camera.unproject_position(Vector3(0, 8, 0))
	var sculpt := func() -> String: return var_to_str(box.faces[top].displacement.to_dict())
	var untouched: String = sculpt.call()

	for hidden in [box, box.mesh_instance]:
		hidden.visible = false
		watch_signals(level)
		rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, true, on_top))
		rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, false, on_top))
		assert_eq(sculpt.call(), untouched, "no sculpt starts with %s hidden" % hidden.name)
		# The press goes on to the floor paint instead, which only runs in the
		# editor and says it could not reach the layer.
		var said = get_signal_parameters(level, "user_message")
		assert_eq(
			said[0] if said else "",
			"Floor Paint could not reach the active layer plane",
			"the sculpt left the press for what comes after it"
		)
		hidden.visible = true

	rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, true, on_top))
	var stroked: String = sculpt.call()
	assert_ne(stroked, untouched, "shown, the face takes the stroke")
	box.visible = false
	rig.forward(PluginRig.motion(on_top + Vector2(20, 0), MOUSE_BUTTON_MASK_LEFT))
	assert_eq(sculpt.call(), stroked, "and hidden partway through, no more of it")
	rig.forward(PluginRig.click(MOUSE_BUTTON_LEFT, false, on_top))
	box.visible = true
	rig.plugin.dock._disp_section.set_expanded(false)
	rig.plugin._toggle_paint_mode()
	await rig.leave_level(level)
