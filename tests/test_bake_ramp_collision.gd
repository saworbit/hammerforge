extends GutTest

## Stairs and Spiral Stairs with Collision set to Ramp (#1416).
##
## A game's own CharacterBody3D usually has no step up, so it walked into the
## first riser of every baked stair and stopped. With Ramp the steps still bake as
## they look, but their faces leave the collision and a slope the bake builds from
## the structure's record goes in their place, where the structure now stands.

const HFGeneratorSystemScript = preload("res://addons/hammerforge/systems/hf_generator_system.gd")
const HFBakeSystemScript = preload("res://addons/hammerforge/systems/hf_bake_system.gd")
const HFLog = preload("res://addons/hammerforge/hf_log.gd")

const EPS := 0.001
const KEPT := "kept the collision of its steps"

var root: LevelRoot


func before_each():
	HFLog.end_test_capture()
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	root.commit_freeze = false
	add_child_autoqfree(root)


func after_each():
	HFLog.end_test_capture()
	root = null


# ===========================================================================
# Fixtures
# ===========================================================================


## A structure of `type` built from its defaults with `changes`, at `placement`.
## Its pieces, in the order the builder made them.
func _structure(type: String, changes := {}, placement := Transform3D.IDENTITY) -> Array:
	var settings := HFGeneratorSystemScript.default_settings(type)
	settings.merge(changes, true)
	assert_true(root.generator_system.create(type, settings, placement).ok, "it builds")
	return _pieces()


func _pieces() -> Array:
	var out: Array = []
	for record in root.generator_system.generators.values():
		for brush_id in record.brush_ids:
			out.append(root.brush_system.find_brush_by_id(str(brush_id)))
	return out


func _record():
	for record in root.generator_system.generators.values():
		return record
	return null


func _floor() -> DraftBrush:
	var info := {
		"shape": LevelRoot.BrushShape.BOX,
		"size": Vector3(12, 0.4, 12),
		"center": Vector3(0, -1.0, 0),
	}
	return root.create_brush_from_info(info) as DraftBrush


func _bake() -> void:
	assert_true(await root.bake(true, false, 0), "the level bakes")
	assert_not_null(root.baked_container)


func _shapes_under(node: Node) -> Array:
	var out: Array = []
	for col in node.find_children("*", "CollisionShape3D", true, false):
		if (col as CollisionShape3D).shape != null:
			out.append(col)
	return out


func _ramp_bodies() -> Array:
	return root.baked_container.find_children(
		HFBakeSystemScript.RAMP_BODY_NAME, "StaticBody3D", true, false
	)


func _ramp_shapes() -> Array:
	var out: Array = []
	for body in _ramp_bodies():
		out.append_array(_shapes_under(body))
	return out


## A convex shape's corners in the level.
func _points(col: CollisionShape3D) -> PackedVector3Array:
	var convex := col.shape as ConvexPolygonShape3D
	var out := PackedVector3Array()
	if convex == null:
		return out
	for point in convex.points:
		out.append(col.global_transform * point)
	return out


## Every drawn triangle in the bake, in the level, as text sorted into one order.
func _drawn() -> PackedStringArray:
	var out := PackedStringArray()
	for node in root.baked_container.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for face in mi.mesh.get_faces():
			var at: Vector3 = mi.global_transform * face
			out.append("%.3f %.3f %.3f" % [at.x, at.y, at.z])
	out.sort()
	return out


func _settings_of_record() -> Dictionary:
	return (_record().settings as Dictionary).duplicate(true)


## Rebuild the one structure with `changes` on the settings it has.
func _update(changes: Dictionary) -> void:
	var settings := _settings_of_record()
	settings.merge(changes, true)
	assert_true(root.generator_system.regenerate(_record().generator_id, settings).ok)


func _warnings_saying(text: String) -> Array:
	var out: Array = []
	for warning in HFLog.get_captured_warnings():
		if str(warning).contains(text):
			out.append(warning)
	return out


# ===========================================================================
# A straight flight
# ===========================================================================


func test_a_flight_bakes_one_convex_shape_and_the_mesh_it_had_on_every_path():
	_structure("stairs")
	var paths := {"face bake": true, "CSG bake": false}
	for path in paths:
		for mode in [0, 1, 2]:
			root.bake_use_face_materials = paths[path]
			root.bake_collision_mode = mode
			_update({"collision": 0})
			await _bake()
			var drawn_with_steps := _drawn()
			_update({"collision": 1})
			await _bake()
			var what := "%s, collision mode %d" % [path, mode]
			var shapes := _shapes_under(root.baked_container)
			assert_eq(shapes.size(), 1, "%s: one shape for the flight" % what)
			if shapes.size() == 1:
				assert_true(shapes[0].shape is ConvexPolygonShape3D, "%s: a convex one" % what)
			assert_eq(_drawn(), drawn_with_steps, "%s: drawn as it was" % what)
			assert_gt(drawn_with_steps.size(), 0, what)


func test_the_steps_leave_the_level_s_collision():
	var floor_brush := _floor()
	var floor_box := HFBakeSystemScript.brush_world_aabb(floor_brush, floor_brush.global_transform)
	_structure("stairs", {"collision": 1})
	for mode in [0, 1]:
		root.bake_collision_mode = mode
		await _bake()
		var ramps := _ramp_shapes()
		assert_eq(ramps.size(), 1, "mode %d: the ramp" % mode)
		for col in _shapes_under(root.baked_container):
			if ramps.has(col):
				continue
			var shape: Shape3D = col.shape
			var corners := PackedVector3Array()
			if shape is ConcavePolygonShape3D:
				corners = (shape as ConcavePolygonShape3D).get_faces()
			elif shape is ConvexPolygonShape3D:
				corners = (shape as ConvexPolygonShape3D).points
			for corner in corners:
				assert_true(
					floor_box.grow(EPS).has_point(col.global_transform * corner),
					"mode %d: %s collides beyond the floor" % [mode, corner]
				)


func test_the_ramp_runs_through_the_front_edge_of_every_tread():
	var steps := _structure("stairs", {"collision": 1})
	await _bake()
	var ramps := _ramp_shapes()
	assert_eq(ramps.size(), 1)
	if ramps.size() != 1:
		return
	var points := _points(ramps[0])
	# The default flight: 8 risers of 0.2 on treads of 0.3, climbing +Y as it runs +Z.
	var normal := Vector3(0, 0.3, -0.2).normalized()
	var first := HFBakeSystemScript.brush_world_aabb(steps[0], steps[0].global_transform)
	var through := Vector3(0, first.end.y, first.position.z)
	var top := -INF
	for point in points:
		assert_lte(normal.dot(point - through), EPS, "%s stands above the slope" % point)
		top = maxf(top, point.y)
	for step in steps:
		var box := HFBakeSystemScript.brush_world_aabb(step, step.global_transform)
		var front := Vector3(0, box.end.y, box.position.z)
		assert_almost_eq(normal.dot(front - through), 0.0, EPS, "the slope meets %s" % step.name)
		var on_the_slope := false
		for point in points:
			if absf(point.z - front.z) <= EPS and absf(point.y - front.y) <= EPS:
				on_the_slope = true
		var last: bool = step == steps[-1]
		assert_true(on_the_slope or not last, "the ramp has a corner at the top front edge")
	var highest := HFBakeSystemScript.brush_world_aabb(steps[-1], steps[-1].global_transform)
	assert_almost_eq(top, highest.end.y, EPS, "flat over the top tread, level with it")


func test_moving_the_structure_and_baking_again_moves_the_ramp():
	var steps := _structure("stairs", {"collision": 1})
	await _bake()
	var before := _points(_ramp_shapes()[0])
	var offset := Vector3(5, 1, -2)
	for step in steps:
		step.global_position += offset
	await _bake()
	var ramps := _ramp_shapes()
	assert_eq(ramps.size(), 1, "the structure was moved, not edited")
	if ramps.size() != 1:
		return
	var after := _points(ramps[0])
	assert_eq(after.size(), before.size())
	for i in after.size():
		assert_almost_eq(after[i], before[i] + offset, Vector3.ONE * EPS)


func test_a_turned_structure_turns_its_ramp():
	var turn := Transform3D(Basis(Vector3.UP, deg_to_rad(90.0)), Vector3(3, 0, 0))
	var steps := _structure("stairs", {"collision": 1}, turn)
	await _bake()
	var ramps := _ramp_shapes()
	assert_eq(ramps.size(), 1)
	var box := AABB(_points(ramps[0])[0], Vector3.ZERO)
	for point in _points(ramps[0]):
		box = box.expand(point)
	var flight := HFBakeSystemScript.brush_world_aabb(steps[0], steps[0].global_transform)
	for step in steps:
		flight = flight.merge(HFBakeSystemScript.brush_world_aabb(step, step.global_transform))
	assert_almost_eq(box.size.z, flight.size.z, EPS, "across the flight, now along Z")
	assert_almost_eq(box.size.x, flight.size.x + 0.3, EPS, "up its run and a tread in front")


# ===========================================================================
# When a ramp is not laid
# ===========================================================================


func test_a_hand_edited_flight_bakes_step_collision_and_the_log_says_so():
	HFLog.begin_test_capture([KEPT])
	var steps := _structure("stairs", {"collision": 1})
	steps[3].global_position += Vector3(0, 0.05, 0)
	root.bake_collision_mode = 1
	await _bake()
	assert_eq(_ramp_bodies().size(), 0, "no ramp over a flight it no longer fits")
	assert_eq(_shapes_under(root.baked_container).size(), 8, "a hull for every step")
	var said := _warnings_saying(KEPT)
	assert_eq(said.size(), 1, "the bake log names it")
	if said.size() == 1:
		assert_string_contains(str(said[0]), str(steps[0].name))
		assert_string_contains(str(said[0]), "edited by hand")


func test_a_ramp_steeper_than_the_player_walks_up_is_refused():
	HFLog.begin_test_capture([KEPT])
	_structure("stairs", {"collision": 1, "rise": 0.35, "tread": 0.3})
	root.bake_collision_mode = 1
	await _bake()
	assert_eq(_ramp_bodies().size(), 0, "a body slides down a slope that steep")
	assert_eq(_shapes_under(root.baked_container).size(), 8, "the steps keep theirs")
	var said := _warnings_saying(KEPT)
	assert_eq(said.size(), 1)
	if said.size() == 1:
		assert_string_contains(str(said[0]), "49.4 degrees")
		assert_string_contains(str(said[0]), "45.0")


func test_a_cut_reaching_the_flight_keeps_step_collision():
	HFLog.begin_test_capture([KEPT])
	_structure("stairs", {"collision": 1})
	var cut := {
		"shape": LevelRoot.BrushShape.BOX,
		"size": Vector3(0.5, 0.5, 0.5),
		"center": Vector3(0, 0, 0),
		"operation": CSGShape3D.OPERATION_SUBTRACTION,
	}
	root.create_brush_from_info(cut)
	await _bake()
	assert_eq(_ramp_bodies().size(), 0, "a ramp would fill the cut back in")
	assert_eq(_warnings_saying("a cut reaches it").size(), 1)


func test_a_flight_only_part_of_which_is_baked_keeps_step_collision():
	HFLog.begin_test_capture([KEPT])
	var steps := _structure("stairs", {"collision": 1})
	assert_true(await root.bake_selected(steps.slice(0, 4)))
	assert_eq(_ramp_bodies().size(), 0)
	assert_eq(_warnings_saying("only part of it").size(), 1)


func test_stairs_with_steps_collision_say_nothing():
	HFLog.begin_test_capture()
	_structure("stairs", {"rise": 0.35})
	await _bake()
	assert_eq(_ramp_bodies().size(), 0)
	assert_eq(_warnings_saying(KEPT), [])


# ===========================================================================
# Other ways a ramp is laid
# ===========================================================================


func test_bake_selected_lays_the_ramp_too():
	var steps := _structure("stairs", {"collision": 1})
	assert_true(await root.bake_selected(steps))
	var ramps := _ramp_shapes()
	assert_eq(ramps.size(), 1)
	if ramps.size() == 1:
		assert_true(
			str(ramps[0].get_parent().get_parent().name).begins_with("BakedSelection_"),
			"in the selection's piece, so a later Bake Selected takes it out with it"
		)


func test_a_turned_stair_bakes_a_ramp_for_each_flight_and_a_box_for_its_landing():
	for turn in [1, 2, 3, 4]:
		for generator_id in root.generator_system.generators.keys():
			root.generator_system.remove(generator_id)
		_structure("stairs", {"collision": 1, "turn": turn})
		await _bake()
		assert_eq(_ramp_shapes().size(), 3, "turn %d" % turn)
		assert_eq(_shapes_under(root.baked_container).size(), 3, "turn %d: nothing else" % turn)


func test_spiral_stairs_bake_one_sloped_shape_per_tread():
	var pieces := _structure("spiral_stairs", {"collision": 1, "steps": 6})
	root.bake_collision_mode = 1
	await _bake()
	var ramps := _ramp_shapes()
	assert_eq(ramps.size(), 7, "a slope up to each tread, and the top tread flat")
	var post: DraftBrush = pieces[-1]
	var post_box := HFBakeSystemScript.brush_world_aabb(post, post.global_transform)
	var others: Array = []
	for col in _shapes_under(root.baked_container):
		if not ramps.has(col):
			others.append(col)
	assert_eq(others.size(), 1, "the newel post keeps its own collision")
	if others.size() == 1:
		for point in _points(others[0]):
			assert_true(post_box.grow(EPS).has_point(point), "and it is the post's")
	# Where each slope ends, the next begins, at the same height.
	var tops: Array = []
	for col in ramps:
		var highest := -INF
		for point in _points(col):
			highest = maxf(highest, point.y)
		tops.append(highest)
	tops.sort()
	for i in range(1, 6):
		assert_almost_eq(tops[i] - tops[i - 1], 0.2, EPS, "a riser between slopes %d" % i)


func test_mode_0_names_each_ramp_after_the_surface_it_lies_over():
	var oak := StandardMaterial3D.new()
	oak.resource_name = "Oak"
	var steps := _structure("stairs", {"collision": 1})
	for step in steps:
		step.material_override = oak
	root.bake_collision_mode = 0
	await _bake()
	var bodies := _ramp_bodies()
	assert_eq(bodies.size(), 1)
	if bodies.size() == 1:
		assert_eq(HFSurface.names_on(bodies[0]), PackedStringArray(["Oak"]), "a footstep on oak")
		assert_eq(HFSurface.material_at(bodies[0], 0), "Oak")


func test_mode_2_puts_the_ramp_with_its_visgroup():
	var steps := _structure("stairs", {"collision": 1})
	root.visgroup_system.create_visgroup("stairwell")
	for step in steps:
		root.visgroup_system.add_to_visgroup(step, "stairwell")
	root.bake_collision_mode = 2
	await _bake()
	var bodies := root.baked_container.find_children(
		"Collision_stairwell", "StaticBody3D", true, false
	)
	assert_eq(bodies.size(), 1, "the body a physics material goes on for that visgroup")
	if bodies.size() == 1:
		assert_eq(_shapes_under(bodies[0]).size(), 1, "the ramp, not the steps")
	assert_eq(_ramp_bodies().size(), 0)
