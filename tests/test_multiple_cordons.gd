extends GutTest

## Several cordons at once.
##
## A partial bake takes every brush that touches any of the level's cordons. The
## first is `cordon_aabb` and the rest are `cordon_extra_aabbs`. Two rooms at
## opposite ends of a level bake without the corridor between them, which one box
## cannot do: a box round both takes the corridor too.

const DockScene = preload("res://addons/hammerforge/dock.tscn")
const HFBrushChangeTrackerType = preload("res://addons/hammerforge/hf_brush_change_tracker.gd")

## The first cordon, round the origin.
const NEAR := AABB(Vector3(-16, -16, -16), Vector3(32, 32, 32))
## A second one, far along x.
const FAR := AABB(Vector3(184, -16, -16), Vector3(32, 32, 32))

var root: LevelRoot


func before_each():
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	root.cordon_aabb = NEAR


func after_each():
	root = null


func _box(brush_id: String, centre: Vector3) -> DraftBrush:
	return (
		(
			root
			. create_brush_from_info(
				{
					"shape": LevelRoot.BrushShape.BOX,
					"size": Vector3(8, 8, 8),
					"center": centre,
					"operation": CSGShape3D.OPERATION_UNION,
					"brush_id": brush_id,
				}
			)
		)
		as DraftBrush
	)


## Two rooms with a corridor between them, and a cordon round each room.
func _two_rooms() -> Dictionary:
	var rooms := {
		"near": _box("near_room", Vector3.ZERO),
		"far": _box("far_room", Vector3(200, 0, 0)),
		"corridor": _box("corridor", Vector3(100, 0, 0)),
	}
	var extra: Array[AABB] = [FAR]
	root.cordon_extra_aabbs = extra
	root.cordon_enabled = true
	return rooms


func _cordons(boxes: Array) -> Array[AABB]:
	var out: Array[AABB] = []
	for box in boxes:
		out.append(box)
	return out


# ===========================================================================
# What the bake takes
# ===========================================================================


func test_a_brush_in_any_cordon_bakes_and_the_space_between_does_not():
	var rooms := _two_rooms()
	assert_true(root.bake_system.brush_bakes(rooms["near"]), "the room in the first cordon")
	assert_true(root.bake_system.brush_bakes(rooms["far"]), "the room in the second")
	assert_false(
		root.bake_system.brush_bakes(rooms["corridor"]),
		"the corridor touches neither, so it stays out of the bake"
	)


func test_with_the_cordon_off_every_brush_bakes():
	var rooms := _two_rooms()
	root.cordon_enabled = false
	for key in rooms:
		assert_true(root.bake_system.brush_bakes(rooms[key]), "%s with the cordon off" % key)


func test_the_dry_run_counts_through_every_cordon():
	_two_rooms()
	var result: Dictionary = root.bake_system.bake_dry_run()
	assert_eq(int(result["draft"]), 2, "the dry run counts what the bake will take")


func test_the_bake_builds_both_rooms_and_not_the_corridor():
	_two_rooms()
	assert_true(await root.bake(), "fixture: the bake ran")
	var points := _baked_points()
	assert_false(points.is_empty(), "fixture: the bake built something")
	var near_room := false
	var far_room := false
	for point in points:
		near_room = near_room or absf(point.x) <= 4.01
		far_room = far_room or absf(point.x - 200.0) <= 4.01
		assert_false(
			absf(point.x - 100.0) <= 4.01, "the corridor at x=100 is not in the bake: %s" % point
		)
	assert_true(near_room, "the room in the first cordon is")
	assert_true(far_room, "and so is the room in the second")


## Every vertex the bake put into a mesh, in world space.
func _baked_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	if root.baked_container == null:
		return points
	var stack: Array[Node] = [root.baked_container]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		if not (node is MeshInstance3D) or (node as MeshInstance3D).mesh == null:
			continue
		var instance := node as MeshInstance3D
		for surface in range(instance.mesh.get_surface_count()):
			var arrays := instance.mesh.surface_get_arrays(surface)
			for vertex in arrays[Mesh.ARRAY_VERTEX]:
				points.append(instance.global_transform * vertex)
	return points


# ===========================================================================
# The cordons as a list
# ===========================================================================


func test_the_first_cordon_leads_the_list():
	var extra: Array[AABB] = [FAR]
	root.cordon_extra_aabbs = extra
	assert_eq(root.get_cordon_regions(), _cordons([NEAR, FAR]))


func test_a_cordon_with_its_size_negative_is_the_same_region():
	var turned := AABB(FAR.end, -FAR.size)
	var extra: Array[AABB] = [turned]
	root.cordon_extra_aabbs = extra
	assert_eq(root.cordon_extra_aabbs, _cordons([FAR]), "stored the right way out")


func test_a_cordon_that_is_not_a_region_is_left_out_and_costs_the_others_nothing():
	var poisoned := AABB(Vector3(NAN, 0, 0), Vector3(8, 8, 8))
	var extra: Array[AABB] = [poisoned, FAR]
	root.cordon_extra_aabbs = extra
	assert_eq(root.cordon_extra_aabbs, _cordons([FAR]))
	assert_push_warning("not a region")


func test_a_cordon_appended_in_place_is_still_read_as_a_region():
	# Appending skips the setter. A size left negative made intersects() refuse
	# every brush, which bakes an empty level and calls it success.
	var rooms := _two_rooms()
	root.cordon_extra_aabbs.clear()
	root.cordon_extra_aabbs.append(AABB(FAR.end, -FAR.size))
	root.cordon_extra_aabbs.append(AABB(Vector3(INF, 0, 0), Vector3.ONE))
	assert_eq(root.get_cordon_regions(), _cordons([NEAR, FAR]), "the turned box reads right")
	assert_true(root.bake_system.brush_bakes(rooms["far"]), "and the room in it bakes")


func test_setting_a_cordon_by_index():
	assert_true(root.set_cordon_region(1, FAR), "the index one past the last adds a cordon")
	assert_eq(root.get_cordon_regions(), _cordons([NEAR, FAR]))
	var moved := FAR.grow(8.0)
	assert_true(root.set_cordon_region(1, moved))
	assert_eq(root.get_cordon_regions(), _cordons([NEAR, moved]), "an index in range moves it")
	assert_true(root.set_cordon_region(0, FAR))
	assert_eq(root.cordon_aabb, FAR, "index 0 is cordon_aabb")


func test_setting_a_cordon_out_of_range_or_not_a_region_changes_nothing():
	var before := root.get_cordon_regions()
	assert_false(root.set_cordon_region(-1, FAR))
	assert_false(root.set_cordon_region(2, FAR), "two past the last is not one past it")
	assert_false(root.set_cordon_region(0, AABB(Vector3.ZERO, Vector3(NAN, 1, 1))))
	assert_push_warning("not a region")
	assert_eq(root.get_cordon_regions(), before)


func test_setting_a_cordon_asks_for_a_rebake_and_redraws():
	root.cordon_enabled = true
	root._full_reconcile_needed = false
	root.set_cordon_region(1, FAR)
	assert_true(root._full_reconcile_needed, "the cordons decide what the bake takes")
	assert_eq(_wire_vertex_count(), 48, "two boxes of twelve edges")


func test_removing_a_cordon_moves_the_ones_after_it_up():
	var third := AABB(Vector3(-216, -16, -16), Vector3(32, 32, 32))
	var extra: Array[AABB] = [FAR, third]
	root.cordon_extra_aabbs = extra
	assert_true(root.remove_cordon_region(1))
	assert_eq(root.get_cordon_regions(), _cordons([NEAR, third]))
	assert_true(root.remove_cordon_region(0), "the first can go while another is left")
	assert_eq(root.cordon_aabb, third, "and the next one takes its place")
	assert_eq(root.cordon_extra_aabbs.size(), 0)


func test_the_last_cordon_cannot_be_removed():
	assert_false(root.remove_cordon_region(0), "cordon_aabb always holds one; turn it off instead")
	assert_eq(root.cordon_aabb, NEAR)
	assert_false(root.remove_cordon_region(3), "nor can one that is not there")


func test_a_cordon_from_the_selection_can_be_added_beside_the_first():
	var far_room := _box("far_room", Vector3(200, 0, 0))
	root.set_cordon_from_selection([far_room], 1)
	assert_true(root.cordon_enabled, "fitting a cordon turns the cordon on")
	assert_eq(root.cordon_aabb, NEAR, "the first cordon stays where it was")
	assert_eq(root.cordon_extra_aabbs.size(), 1)
	assert_true(root.cordon_extra_aabbs[0].has_point(Vector3(200, 0, 0)), "round the selection")
	assert_true(root.bake_system.brush_bakes(far_room))


# ===========================================================================
# A change to the cordons is a change to the bake
# ===========================================================================


func test_the_extra_cordons_are_in_the_bake_signature():
	var before: int = root.bake_system.bake_settings_signature()
	var extra: Array[AABB] = [FAR]
	root.cordon_extra_aabbs = extra
	assert_ne(root.bake_system.bake_settings_signature(), before, "a cordon added")
	var added: int = root.bake_system.bake_settings_signature()
	root.cordon_extra_aabbs.append(NEAR)
	assert_ne(root.bake_system.bake_settings_signature(), added, "one appended in place too")


func test_a_rebake_after_adding_a_cordon_rebuilds():
	_two_rooms()
	assert_true(await root.bake())
	root._dirty_brush_ids = {}
	root._full_reconcile_needed = false
	assert_false(await root.bake_dirty(), "fixture: nothing changed is nothing to do")
	root.cordon_extra_aabbs.append(AABB(Vector3(84, -16, -16), Vector3(32, 32, 32)))
	assert_true(await root.bake_dirty(), "the corridor is in a cordon now, so the bake changes")


func test_the_change_tracker_sees_a_cordon_the_inspector_added():
	# The Inspector and native undo set the property without going through the
	# dock, so the tracker is what asks for the rebake.
	var tracker = HFBrushChangeTrackerType.new()
	tracker.prime(root)
	root._full_reconcile_needed = false
	var extra: Array[AABB] = [FAR]
	root.cordon_extra_aabbs = extra
	tracker.reconcile(root)
	assert_true(root._full_reconcile_needed)


# ===========================================================================
# The cordons travel with the level
# ===========================================================================


func _other_root() -> LevelRoot:
	var other := LevelRoot.new()
	other.auto_spawn_player = false
	other.hflevel_autosave_enabled = false
	add_child_autoqfree(other)
	return other


func test_every_cordon_travels_through_a_level_file():
	var third := AABB(Vector3(-216, -16, -16), Vector3(32, 32, 32))
	var extra: Array[AABB] = [FAR, third]
	root.cordon_extra_aabbs = extra
	root.cordon_enabled = true
	var path := "user://test_multiple_cordons.hflevel"
	var bundle := {
		"version": HFLevelIO.FORMAT_VERSION,
		"saved_at": "now",
		"settings": root._capture_hflevel_settings(),
		"state": root.capture_state(),
	}
	HFLevelIO.save_to_path(path, HFLevelIO.encode_variant(bundle), false)

	var other := _other_root()
	assert_true(other.file_system.load_hflevel(path), "fixture: the file loads")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	assert_eq(other.get_cordon_regions(), _cordons([NEAR, FAR, third]))
	assert_true(other.cordon_enabled)


func test_a_file_from_before_the_extra_cordons_leaves_them_alone():
	var extra: Array[AABB] = [FAR]
	root.cordon_extra_aabbs = extra
	root.state_system.apply_hflevel_settings({"cordon_enabled": true})
	assert_eq(root.cordon_extra_aabbs, _cordons([FAR]), "an absent key is not an empty list")


func test_cordons_a_file_cannot_describe_do_not_land():
	var extra: Array[AABB] = [FAR]
	root.cordon_extra_aabbs = extra
	root.state_system.apply_hflevel_settings({"cordon_extra_aabbs": "two rooms"})
	assert_eq(root.cordon_extra_aabbs, _cordons([FAR]), "a value that is not a list is refused")
	assert_push_warning("not a list")

	var entries := [
		{"pos": [0, 0, 0]},
		{"pos": ["0", 0, 0], "size": [8, 8, 8]},
		"a room",
		{"pos": [0, 0, 0], "size": [NAN, 8, 8]},
		{"pos": [184.0, -16.0, -16.0], "size": [32.0, 32.0, 32.0]},
	]
	root.state_system.apply_hflevel_settings({"cordon_extra_aabbs": entries})
	assert_eq(root.cordon_extra_aabbs, _cordons([FAR]), "only the entry that is a box lands")
	for i in range(3):
		assert_push_warning("could not read")
	assert_push_warning("not a region")


# ===========================================================================
# The wireframe
# ===========================================================================


func _wire_vertex_count() -> int:
	var mesh: Mesh = root.cordon_wireframe.mesh if root.cordon_wireframe else null
	if mesh == null or mesh.get_surface_count() == 0:
		return 0
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	return vertices.size()


func test_the_wireframe_draws_every_cordon():
	_two_rooms()
	root.update_cordon_visual()
	assert_eq(_wire_vertex_count(), 48, "two boxes of twelve edges")
	var drawn: AABB = root.cordon_wireframe.mesh.get_aabb()
	assert_true(drawn.has_point(Vector3(200, 0, 0)), "the far cordon is drawn")
	assert_true(drawn.has_point(Vector3.ZERO), "and the near one")


# ===========================================================================
# The dock
# ===========================================================================


func _dock() -> Node:
	var dock := DockScene.instantiate()
	add_child_autoqfree(dock)
	dock.level_root = root
	dock.connected_root = root
	dock._connect_root_signals()
	return dock


func _spins(dock: Node) -> AABB:
	var low := Vector3(dock.cordon_min_x.value, dock.cordon_min_y.value, dock.cordon_min_z.value)
	var high := Vector3(dock.cordon_max_x.value, dock.cordon_max_y.value, dock.cordon_max_z.value)
	return AABB(low, high - low)


func test_the_dock_lists_every_cordon_the_level_holds():
	var extra: Array[AABB] = [FAR]
	root.cordon_extra_aabbs = extra
	var dock := _dock()
	assert_eq(dock.cordon_region_opt.item_count, 2)
	assert_eq(_spins(dock), NEAR, "the first is shown")
	assert_false(dock.cordon_remove_btn.disabled, "one can go while another is left")


func test_choosing_a_cordon_shows_its_bounds():
	var extra: Array[AABB] = [FAR]
	root.cordon_extra_aabbs = extra
	var dock := _dock()
	dock.cordon_region_opt.select(1)
	dock._on_cordon_region_selected(1)
	assert_eq(_spins(dock), FAR)
	assert_eq(root.get_cordon_regions(), _cordons([NEAR, FAR]), "showing one changes nothing")


func test_the_spins_move_the_chosen_cordon_and_not_the_first():
	var extra: Array[AABB] = [FAR]
	root.cordon_extra_aabbs = extra
	var dock := _dock()
	dock.cordon_region_opt.select(1)
	dock._on_cordon_region_selected(1)
	dock.cordon_max_x.value = FAR.end.x + 40.0
	assert_eq(root.cordon_aabb, NEAR, "the first cordon stays")
	assert_almost_eq(root.cordon_extra_aabbs[0].end.x, FAR.end.x + 40.0, 0.01, "the second moves")


func test_add_from_selection_adds_a_cordon_and_shows_it():
	var dock := _dock()
	var far_room := _box("far_room", Vector3(200, 0, 0))
	dock._selection_nodes = [far_room]
	dock._on_cordon_add_from_selection()
	assert_eq(root.get_cordon_regions().size(), 2)
	assert_eq(root.cordon_aabb, NEAR, "the cordon already there is kept")
	assert_eq(dock.cordon_region_opt.item_count, 2)
	assert_eq(dock.cordon_region_opt.selected, 1, "the new cordon is the one shown")
	assert_eq(_spins(dock), root.cordon_extra_aabbs[0])
	assert_true(root.cordon_enabled)
	assert_true(dock.cordon_enabled_check.button_pressed)


func test_set_from_selection_fits_the_chosen_cordon():
	var extra: Array[AABB] = [FAR]
	root.cordon_extra_aabbs = extra
	var dock := _dock()
	dock.cordon_region_opt.select(1)
	var corridor := _box("corridor", Vector3(100, 0, 0))
	dock._selection_nodes = [corridor]
	dock._on_cordon_from_selection()
	assert_eq(root.cordon_aabb, NEAR, "the first cordon stays")
	assert_true(root.cordon_extra_aabbs[0].has_point(Vector3(100, 0, 0)), "the chosen one moved")
	assert_eq(root.get_cordon_regions().size(), 2, "and none was added")


func test_remove_takes_the_chosen_cordon_out():
	var extra: Array[AABB] = [FAR]
	root.cordon_extra_aabbs = extra
	var dock := _dock()
	dock.cordon_region_opt.select(0)
	dock._on_cordon_remove()
	assert_eq(root.get_cordon_regions(), _cordons([FAR]))
	assert_eq(dock.cordon_region_opt.item_count, 1)
	assert_eq(_spins(dock), FAR, "the cordon that moved up is shown")
	assert_true(dock.cordon_remove_btn.disabled, "the last one cannot go")


func test_a_cordon_list_left_over_from_another_level_does_not_add_one():
	var extra: Array[AABB] = [FAR]
	root.cordon_extra_aabbs = extra
	var dock := _dock()
	dock.cordon_region_opt.select(1)
	# A level loaded since holds one cordon, and the dock has not looked again.
	var none: Array[AABB] = []
	root.cordon_extra_aabbs = none
	dock.cordon_max_x.value = 999.0
	assert_eq(root.get_cordon_regions(), _cordons([NEAR]), "editing the spins added no cordon")
	assert_eq(dock.cordon_region_opt.item_count, 1, "the dock looked again instead")


# ===========================================================================
# A name and a switch for each cordon (#967)
# ===========================================================================


func _flags(flags: Array) -> Array[bool]:
	var out: Array[bool] = []
	for flag in flags:
		out.append(flag)
	return out


func test_a_cordon_that_is_off_does_not_bake_and_the_dry_run_agrees():
	var rooms := _two_rooms()
	assert_true(root.set_cordon_active(1, false))
	assert_true(root.bake_system.brush_bakes(rooms["near"]), "the room in the cordon still on")
	assert_false(root.bake_system.brush_bakes(rooms["far"]), "the room in the one switched off")
	assert_eq(int(root.bake_system.bake_dry_run()["draft"]), 1, "the dry run counts the same")
	assert_eq(root.get_cordon_regions(), _cordons([NEAR]), "the bake reads the one still on")
	assert_eq(root.get_all_cordon_regions(), _cordons([NEAR, FAR]), "and both are kept")


func test_with_every_cordon_off_the_whole_level_bakes():
	# An empty list of cordons refused every brush, which bakes an empty level
	# and calls it success. Every cordon off cuts nothing, as the master switch.
	var rooms := _two_rooms()
	root.cordon_active = _flags([false, false])
	for key in rooms:
		assert_true(root.bake_system.brush_bakes(rooms[key]), "%s with every cordon off" % key)


func test_switching_a_cordon_asks_for_a_rebake_and_changes_the_signature():
	_two_rooms()
	var before: int = root.bake_system.bake_settings_signature()
	root._full_reconcile_needed = false
	root.set_cordon_active(1, false)
	assert_true(root._full_reconcile_needed, "the cordon decides what the bake takes")
	assert_ne(root.bake_system.bake_settings_signature(), before, "off")
	root.set_cordon_active(1, true)
	assert_eq(root.bake_system.bake_settings_signature(), before, "and on again is as it was")
	assert_eq(root.cordon_active, _flags([]), "a level with every cordon on keeps an empty list")


func test_a_rebake_after_switching_a_cordon_off_rebuilds():
	_two_rooms()
	assert_true(await root.bake())
	root._dirty_brush_ids = {}
	root._full_reconcile_needed = false
	root.cordon_active = _flags([true, false])
	assert_true(await root.bake_dirty(), "the far room leaves the bake, so the bake changes")


func test_the_change_tracker_sees_a_switch_set_outside_the_dock():
	# The Inspector no longer shows the switches, but a script or Godot's own
	# undo still sets them, and the next bake has to notice.
	var tracker = HFBrushChangeTrackerType.new()
	tracker.prime(root)
	root._full_reconcile_needed = false
	root.cordon_active = _flags([false])
	tracker.reconcile(root)
	assert_true(root._full_reconcile_needed)


func test_a_name_is_kept_and_an_empty_one_shows_the_number():
	_two_rooms()
	assert_eq(root.get_cordon_name(1), "Cordon 2", "unnamed, as the dock always showed it")
	assert_true(root.set_cordon_name(1, "  Arena "))
	assert_eq(root.get_cordon_name(1), "Arena", "trimmed")
	assert_true(root.set_cordon_name(1, ""))
	assert_eq(root.get_cordon_name(1), "Cordon 2")
	assert_eq(root.cordon_names, PackedStringArray(), "nothing named keeps an empty list")
	assert_false(root.set_cordon_name(2, "Corridor"), "a cordon that is not there")
	assert_false(root.set_cordon_active(-1, false))


func test_names_and_switches_move_with_their_cordons():
	var third := AABB(Vector3(-216, -16, -16), Vector3(32, 32, 32))
	var extra: Array[AABB] = [FAR, third]
	root.cordon_extra_aabbs = extra
	root.set_cordon_name(0, "Spawn")
	root.set_cordon_name(1, "Arena")
	root.set_cordon_name(2, "Vault")
	root.set_cordon_active(1, false)
	assert_true(root.remove_cordon_region(0))
	assert_eq(root.get_cordon_name(0), "Arena", "the arena moved up with its name")
	assert_false(root.is_cordon_active(0), "and its switch")
	assert_eq(root.get_cordon_name(1), "Vault")
	assert_true(root.is_cordon_active(1))
	assert_true(root.set_cordon_region(2, NEAR), "one added")
	assert_eq(root.get_cordon_name(2), "Cordon 3", "comes unnamed")
	assert_true(root.is_cordon_active(2), "and on")


func test_parallel_cordon_properties_cannot_be_split_in_the_inspector():
	var properties := {}
	for property in root.get_property_list():
		properties[property.get("name", "")] = property

	assert_true(
		(int(properties["cordon_extra_aabbs"].usage) & PROPERTY_USAGE_READ_ONLY) != 0,
		"the Inspector cannot remove a box without its name and switch",
	)
	for hidden_name in ["cordon_names", "cordon_active"]:
		var usage := int(properties[hidden_name].usage)
		assert_true((usage & PROPERTY_USAGE_STORAGE) != 0, "%s is still saved" % hidden_name)
		var shown := (usage & PROPERTY_USAGE_EDITOR) != 0
		assert_false(shown, "%s is hidden from the Inspector" % hidden_name)


func test_fitting_a_cordon_to_the_selection_switches_it_on():
	var far_room := _box("far_room", Vector3(200, 0, 0))
	var extra: Array[AABB] = [FAR]
	root.cordon_extra_aabbs = extra
	root.cordon_active = _flags([true, false])
	root.set_cordon_from_selection([far_room], 1)
	assert_true(root.is_cordon_active(1), "a cordon fitted to brushes is one meant to bake")
	assert_true(root.bake_system.brush_bakes(far_room))


func test_names_and_switches_travel_through_a_level_file():
	var extra: Array[AABB] = [FAR]
	root.cordon_extra_aabbs = extra
	root.cordon_enabled = true
	root.set_cordon_name(0, "Spawn")
	root.set_cordon_name(1, "Arena")
	root.set_cordon_active(0, false)
	var path := "user://test_cordon_names.hflevel"
	var bundle := {
		"version": HFLevelIO.FORMAT_VERSION,
		"saved_at": "now",
		"settings": root._capture_hflevel_settings(),
		"state": root.capture_state(),
	}
	HFLevelIO.save_to_path(path, HFLevelIO.encode_variant(bundle), false)

	var other := _other_root()
	assert_true(other.file_system.load_hflevel(path), "fixture: the file loads")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	assert_eq(other.get_all_cordon_regions(), _cordons([NEAR, FAR]))
	assert_eq(other.get_cordon_name(0), "Spawn")
	assert_eq(other.get_cordon_name(1), "Arena")
	assert_false(other.is_cordon_active(0), "the first stays off")
	assert_true(other.is_cordon_active(1))


func test_a_file_from_before_the_names_opens_with_every_cordon_on_and_numbered():
	# What a file written before #967 holds: boxes, no names, no switches. The
	# names and switches of the level open before it stay behind.
	root.set_cordon_name(0, "Old room")
	root.cordon_active = _flags([false, false])
	var settings := {
		"cordon_aabb_pos": [-16.0, -16.0, -16.0],
		"cordon_aabb_size": [32.0, 32.0, 32.0],
		"cordon_extra_aabbs": [{"pos": [184.0, -16.0, -16.0], "size": [32.0, 32.0, 32.0]}],
	}
	root.state_system.apply_hflevel_settings(settings)
	assert_eq(root.get_all_cordon_regions(), _cordons([NEAR, FAR]))
	assert_eq(root.get_cordon_name(0), "Cordon 1")
	assert_eq(root.get_cordon_name(1), "Cordon 2")
	assert_true(root.is_cordon_active(0))
	assert_true(root.is_cordon_active(1))


func test_names_and_switches_survive_a_scene_save():
	var extra: Array[AABB] = [FAR]
	root.cordon_extra_aabbs = extra
	root.set_cordon_name(1, "Arena")
	root.set_cordon_active(1, false)
	var scene := PackedScene.new()
	assert_eq(scene.pack(root), OK, "fixture: the level packs")
	var copy := scene.instantiate() as LevelRoot
	copy.auto_spawn_player = false
	copy.hflevel_autosave_enabled = false
	add_child_autoqfree(copy)
	assert_eq(copy.get_all_cordon_regions(), _cordons([NEAR, FAR]))
	assert_eq(copy.get_cordon_name(1), "Arena")
	assert_false(copy.is_cordon_active(1))
	assert_true(copy.is_cordon_active(0))


func test_a_cordon_that_is_off_is_drawn_dimmer():
	_two_rooms()
	root.set_cordon_active(1, false)
	assert_eq(_wire_vertex_count(), 48, "both boxes are still drawn")
	var arrays: Array = root.cordon_wireframe.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	assert_eq(colors.size(), vertices.size(), "every vertex carries its colour")
	var wrong := 0
	for i in range(mini(colors.size(), vertices.size())):
		var far: bool = vertices[i].x > 100.0
		var expected: Color = LevelRoot.CORDON_OFF_COLOR if far else LevelRoot.CORDON_COLOR
		# Vertex colours are stored eight bits a channel.
		var off: Color = colors[i] - expected
		if maxf(maxf(absf(off.r), absf(off.g)), maxf(absf(off.b), absf(off.a))) > 1.0 / 255.0:
			wrong += 1
	assert_eq(wrong, 0, "the far box is dimmer and the near one is not")


func test_the_dock_shows_names_and_which_cordons_are_off():
	var extra: Array[AABB] = [FAR]
	root.cordon_extra_aabbs = extra
	root.set_cordon_name(0, "Spawn")
	root.set_cordon_active(1, false)
	var dock := _dock()
	assert_eq(dock.cordon_region_opt.get_item_text(0), "Spawn")
	assert_eq(dock.cordon_region_opt.get_item_text(1), "Cordon 2 (off)")
	assert_true(dock.cordon_active_check.button_pressed, "the first is shown, and it is on")
	assert_eq(dock.cordon_name_edit.text, "Spawn")
	dock.cordon_region_opt.select(1)
	dock._on_cordon_region_selected(1)
	assert_false(dock.cordon_active_check.button_pressed, "the second is off")
	assert_eq(dock.cordon_name_edit.text, "", "and unnamed")
	assert_eq(dock.cordon_name_edit.placeholder_text, "Cordon 2")


func test_the_dock_switches_and_names_the_chosen_cordon():
	var extra: Array[AABB] = [FAR]
	root.cordon_extra_aabbs = extra
	var dock := _dock()
	dock.cordon_region_opt.select(1)
	dock._on_cordon_region_selected(1)
	dock.cordon_active_check.button_pressed = false
	assert_false(root.is_cordon_active(1), "the check switched the second cordon off")
	assert_true(root.is_cordon_active(0), "and left the first on")
	assert_eq(dock.cordon_region_opt.get_item_text(1), "Cordon 2 (off)")
	dock.cordon_name_edit.text = "Arena"
	dock.cordon_name_edit.text_submitted.emit("Arena")
	assert_eq(root.get_cordon_name(1), "Arena")
	assert_eq(root.get_cordon_name(0), "Cordon 1", "the first keeps its number")
	assert_eq(dock.cordon_region_opt.get_item_text(1), "Arena (off)")
