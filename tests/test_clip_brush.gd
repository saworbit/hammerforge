extends GutTest

## A `func_clip` brush: collision the player cannot see, with no mesh (#1409).
##
## The closest thing before it was a `func_detail` with a see-through material,
## which still baked a mesh and still drew. A clip bakes to its hull on a body of
## its own, the clips on one layer share that body, the editor tints it whatever
## it is painted with, and no bake path draws it or cuts it.

const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")
const HFBrushEntity = preload("res://addons/hammerforge/hf_brush_entity.gd")
const HFEntityDefType = preload("res://addons/hammerforge/hf_entity_def.gd")
const HFEntityPropUtils = preload("res://addons/hammerforge/ui/hf_entity_prop_utils.gd")
const HFLog = preload("res://addons/hammerforge/hf_log.gd")

const CLIP := "func_clip"
## Where every clip below stands unless a test says otherwise: clear of the floor,
## so a baked mesh that reached it would be a mesh made of the clip.
const CLIP_AT := Vector3(10, 1, 0)
const CLIP_SIZE := Vector3(2, 2, 2)

var root: LevelRoot


func before_each():
	HFLog.end_test_capture()
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)


func after_each():
	HFLog.end_test_capture()
	root = null


# ===========================================================================
# Fixtures
# ===========================================================================


func _box(center: Vector3, size: Vector3, subtract := false) -> DraftBrush:
	var op := CSGShape3D.OPERATION_SUBTRACTION if subtract else CSGShape3D.OPERATION_UNION
	var info := {"shape": LevelRoot.BrushShape.BOX, "size": size, "center": center, "operation": op}
	return root.create_brush_from_info(info) as DraftBrush


## A box tied as a clip, the way the Build tab's Entity Binding ties one.
func _clip(center := CLIP_AT, size := CLIP_SIZE, entity_name := "") -> DraftBrush:
	var brush := _box(center, size)
	root.tie_brushes_to_entity([str(brush.brush_id)], CLIP, entity_name)
	return brush


func _floor() -> DraftBrush:
	return _box(Vector3(0, -0.2, 0), Vector3(8, 0.4, 8))


func _bake() -> void:
	assert_true(await root.bake(true, false, 0), "the level bakes")
	assert_not_null(root.baked_container)


## Every body the bake made for a clip.
func _clip_bodies() -> Array:
	var out: Array = []
	if root.baked_container == null:
		return out
	for node in root.baked_container.find_children("*", "StaticBody3D", true, false):
		if HFBrushEntity.is_clip(node):
			out.append(node)
	return out


func _shapes(body: Node) -> Array:
	var out: Array = []
	for child in body.get_children():
		if child is CollisionShape3D:
			out.append(child)
	return out


## The bounds of a clip shape's hull in the level.
func _hull_bounds(col: CollisionShape3D) -> AABB:
	var convex := col.shape as ConvexPolygonShape3D
	if convex == null or convex.points.is_empty():
		return AABB()
	var xform := col.global_transform
	var bounds := AABB(xform * convex.points[0], Vector3.ZERO)
	for point in convex.points:
		bounds = bounds.expand(xform * point)
	return bounds


## Every baked mesh whose bounds in the level reach `box`.
func _meshes_reaching(box: AABB) -> Array:
	var out: Array = []
	for node in root.baked_container.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var bounds := mi.global_transform * mi.mesh.get_aabb()
		if bounds.intersects(box.grow(-0.05)):
			out.append(mi)
	return out


func _clip_box(center := CLIP_AT, size := CLIP_SIZE) -> AABB:
	return AABB(center - size * 0.5, size)


## What one clip at `CLIP_AT` bakes into, whatever path the bake took: one body
## carrying the clip's hull, on `layer`, with nothing drawn anywhere it stands.
func _assert_one_clip(what: String, layer: int) -> void:
	var bodies := _clip_bodies()
	assert_eq(bodies.size(), 1, "%s: one clip body" % what)
	if bodies.size() != 1:
		return
	var body := bodies[0] as StaticBody3D
	assert_eq(body.collision_layer, layer, "%s: on the layer it was given" % what)
	assert_eq(body.collision_mask, 0, "%s: it collides with nothing itself" % what)
	assert_eq(body.find_children("*", "MeshInstance3D", true, false).size(), 0, what)
	var shapes := _shapes(body)
	assert_eq(shapes.size(), 1, "%s: one shape for one brush" % what)
	if shapes.size() == 1:
		var col := shapes[0] as CollisionShape3D
		assert_true(col.shape is ConvexPolygonShape3D, "%s: the brush's convex hull" % what)
		var hull := _hull_bounds(col)
		var want := _clip_box()
		assert_true(hull.position.is_equal_approx(want.position), "%s: %s" % [what, hull])
		assert_true(hull.size.is_equal_approx(want.size), "%s: the whole brush" % what)
	assert_eq(_meshes_reaching(_clip_box()), [], "%s: no baked mesh draws the clip" % what)


# ===========================================================================
# The class
# ===========================================================================


func test_func_clip_is_offered_for_entity_binding():
	var shipped := HFEntityDefType.load_definitions("res://addons/hammerforge/entities.json")
	var offered: Array = []
	for def in HFEntityDefType.filter_brush_entities(shipped):
		offered.append(def.classname)
	assert_has(offered, CLIP, "the Build tab lists it from entities.json, with no dock code")
	var definition: Dictionary = root.get_entity_definition(CLIP)
	var layer: Dictionary = {}
	for prop in definition.get("properties", []):
		if str(prop.get("name", "")) == "layer":
			layer = prop
	assert_eq(str(layer.get("type", "")), "int", "a Physics Layer the Entity panel can set")
	assert_eq(int(layer.get("default", -1)), 0, "0 is the level's Physics Layer")
	assert_eq(definition.get("inputs", []), [], "nothing to wire to")


# ===========================================================================
# The bake
# ===========================================================================


func test_a_baked_clip_is_collision_on_the_level_layer_with_no_mesh():
	_floor()
	_clip()
	root.bake_collision_layer_index = 3
	await _bake()
	_assert_one_clip("face bake", 1 << 2)


func test_the_layer_property_puts_it_on_that_layer():
	_floor()
	var brush := _clip()
	# What the Entity panel's spin box writes.
	HFEntityPropUtils.set_entity_property(brush, "layer", 5.0)
	await _bake()
	_assert_one_clip("Layer 5", 1 << 4)


func test_a_layer_written_as_text_by_an_import_is_read():
	_floor()
	var brush := _clip()
	brush.set_meta(HFBrushEntity.DATA_META, {"layer": "4"})
	await _bake()
	_assert_one_clip("Layer '4'", 1 << 3)


func test_a_layer_out_of_range_goes_on_the_level_layer_and_says_so():
	_floor()
	var brush := _clip()
	brush.set_meta(HFBrushEntity.DATA_META, {"layer": 40})
	HFLog.begin_test_capture(["func_clip"])
	await _bake()
	var warnings := HFLog.get_captured_warnings()
	HFLog.end_test_capture()
	_assert_one_clip("Layer 40", 1)
	assert_eq(warnings.size(), 1, "the refused layer is said")
	if warnings.size() == 1:
		assert_string_contains(warnings[0], "40")


func test_twenty_clips_bake_into_one_body():
	_floor()
	for i in 20:
		_clip(Vector3(10 + (i % 5) * 3, 1, (i / 5) * 3))
	await _bake()
	var bodies := _clip_bodies()
	assert_eq(bodies.size(), 1, "twenty clips cost one body")
	if bodies.size() == 1:
		assert_eq(_shapes(bodies[0]).size(), 20, "and collide as the twenty solids they are")
	assert_eq(
		root.baked_container.find_children("*", "MeshInstance3D", true, false).size(),
		1,
		"the floor is the only thing drawn"
	)


func test_clips_on_two_layers_are_two_bodies():
	_floor()
	_clip(Vector3(10, 1, 0))
	_clip(Vector3(14, 1, 0))
	var other := _clip(Vector3(18, 1, 0))
	HFEntityPropUtils.set_entity_property(other, "layer", 2)
	await _bake()
	var layers: Dictionary = {}
	for body in _clip_bodies():
		layers[(body as StaticBody3D).collision_layer] = _shapes(body).size()
	assert_eq(layers, {1: 2, 2: 1}, "one body per layer, holding the clips on it")


func test_a_named_clip_keeps_a_body_of_its_own():
	_floor()
	_clip(Vector3(10, 1, 0))
	_clip(Vector3(14, 1, 0), CLIP_SIZE, "ledge_clip")
	await _bake()
	var named: Array = root.baked_container.find_children("ledge_clip", "StaticBody3D", true, false)
	assert_eq(named.size(), 1, "a name is an address, so the runtime can still find it")
	if named.size() == 1:
		assert_eq(str(named[0].get_meta("entity_name", "")), "ledge_clip")
		assert_true(HFBrushEntity.is_clip(named[0]))
	assert_eq(_clip_bodies().size(), 2, "the unnamed one is grouped, not lost")


func test_every_bake_path_gives_the_same_clip():
	var floor_brush := _floor()
	# A second floor a chunk away, so a chunked bake makes more than one chunk.
	_box(Vector3(-10, -0.2, 0), Vector3(4, 0.4, 4))
	var brush := _clip()
	# Mode 2 splits the world's collision by visgroup. The clip is in one too.
	root.visgroup_system.create_visgroup("upper")
	root.visgroup_system.add_to_visgroup(floor_brush, "upper")
	root.visgroup_system.add_to_visgroup(brush, "upper")
	# Each path a full bake can take, with each collision mode.
	var paths := {
		"face bake": {},
		"CSG bake": {"bake_use_face_materials": false},
		"chunked face bake": {"bake_chunk_size": 4.0},
		"chunked CSG bake": {"bake_use_face_materials": false, "bake_chunk_size": 4.0},
	}
	for path in paths:
		for mode in [0, 1, 2]:
			root.bake_use_face_materials = true
			root.bake_chunk_size = 0.0
			root.bake_collision_mode = mode
			for setting in paths[path]:
				root.set(setting, paths[path][setting])
			await _bake()
			var what := "%s, collision mode %d" % [path, mode]
			_assert_one_clip(what, 1)
			if mode == 2:
				assert_eq(
					(
						root
						. baked_container
						. find_children("Collision_upper", "StaticBody3D", true, false)
						. size()
					),
					1,
					"%s: the world's collision was split by visgroup" % what
				)


func test_a_cut_through_a_clip_cuts_the_world_and_not_the_clip():
	_floor()
	_clip()
	# Through the end of the floor and through the clip, which stands at x 9 to 11.
	# Any active cut puts the bake on CSG.
	_box(Vector3(6.5, 0, 0), Vector3(7, 3, 2), true)
	for mode in [0, 1, 2]:
		root.bake_collision_mode = mode
		await _bake()
		_assert_one_clip("cut, collision mode %d" % mode, 1)


func test_bake_selected_of_clips_alone_gives_their_collision():
	_floor()
	var brush := _clip()
	assert_true(await root.bake_selected([brush]), "a clip bakes on its own")
	_assert_one_clip("Bake Selected", 1)


func test_bake_selected_of_a_clip_and_a_wall_gives_both():
	_floor()
	var brush := _clip()
	var wall := _box(Vector3(-10, 1, 0), Vector3(2, 2, 2))
	assert_true(await root.bake_selected([brush, wall]))
	_assert_one_clip("Bake Selected with a wall", 1)
	assert_eq(_meshes_reaching(_clip_box(Vector3(-10, 1, 0))).size(), 1, "the wall is drawn")


func test_the_playtest_player_meets_a_clip():
	_floor()
	_clip(Vector3(0, 1, 0), Vector3(4, 2, 0.5))
	await _bake()
	var player := root._make_playtest_player()
	var mask := player.collision_mask
	var capsule := CapsuleShape3D.new()
	capsule.radius = float(player.get("capsule_radius"))
	capsule.height = float(player.get("capsule_height"))
	player.free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var exclude: Array[RID] = []
	for node in root.find_children("*", "CollisionObject3D", true, false):
		if not root.baked_container.is_ancestor_of(node):
			exclude.append((node as CollisionObject3D).get_rid())
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = mask
	query.exclude = exclude
	query.transform = Transform3D(Basis.IDENTITY, Vector3(0, 1.2, 0))
	var met := false
	for hit in root.get_world_3d().direct_space_state.intersect_shape(query):
		met = met or HFBrushEntity.is_clip(hit["collider"])
	assert_true(met, "the player's capsule, on the player's mask, is stopped by the clip")


# ===========================================================================
# The editor
# ===========================================================================


## The material each surface of `brush`'s preview is drawn with.
func _drawn_with(brush: DraftBrush) -> Array:
	var out: Array = []
	var mi := brush.mesh_instance
	for i in mi.mesh.get_surface_count():
		out.append(mi.get_active_material(i))
	return out


func _assert_clip_tint(brush: DraftBrush, what: String) -> void:
	var drawn := _drawn_with(brush)
	assert_gt(drawn.size(), 0, "%s: fixture draws something" % what)
	for mat in drawn:
		assert_true(DraftBrush.is_editor_look(mat), "%s: the clip's own tint, not %s" % [what, mat])
		if mat is BaseMaterial3D:
			var color := (mat as BaseMaterial3D).albedo_color
			assert_lt(color.a, 1.0, "%s: see-through" % what)
			assert_true(color.r > color.g and color.b > color.g, "%s: violet, %s" % [what, color])


func test_the_clip_tint_shows_even_with_a_material():
	var brush := _clip()
	_assert_clip_tint(brush, "unpainted")
	var red := StandardMaterial3D.new()
	red.albedo_color = Color.RED
	brush.set_material_override(red)
	_assert_clip_tint(brush, "a brush material")
	var slot: int = root.material_manager.add_material(red)
	for face in brush.get_faces():
		face.material_idx = slot
	brush.rebuild_preview()
	_assert_clip_tint(brush, "a material on every face")


func test_the_clip_tint_is_its_own():
	var brush := _clip()
	var clip_look: Material = _drawn_with(brush)[0]
	root.untie_brushes_from_entity([str(brush.brush_id)])
	root.tie_brushes_to_entity([str(brush.brush_id)], "func_detail")
	var detail_look: Material = _drawn_with(brush)[0]
	assert_ne(
		(clip_look as BaseMaterial3D).albedo_color,
		(detail_look as BaseMaterial3D).albedo_color,
		"a clip never reads as detail"
	)


func test_untied_the_brush_draws_its_material_again():
	var brush := _clip()
	var red := StandardMaterial3D.new()
	brush.set_material_override(red)
	root.untie_brushes_from_entity([str(brush.brush_id)])
	assert_eq(_drawn_with(brush), [red], "the tint was the clip's, not the brush's")


# ===========================================================================
# What should not see it
# ===========================================================================


func test_a_flight_of_clip_boxes_is_not_stairs():
	# Five steps with half-metre risers, over the player's step: a flight of world
	# brushes is reported. Collision the player cannot see is not a staircase.
	for i in 5:
		var top := 0.5 * (i + 1)
		var step := _box(Vector3(0, top * 0.5, 0.7 * (i + 0.5)), Vector3(2, top, 0.7))
		root.tie_brushes_to_entity([str(step.brush_id)], CLIP)
	var stairs: Array = []
	for finding in root.validate_level(false).get("findings", []):
		if str(finding.get("type", "")) == "steep_stairs":
			stairs.append(finding)
	assert_eq(stairs, [], "no flight of stairs")
