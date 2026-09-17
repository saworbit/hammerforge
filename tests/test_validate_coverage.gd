extends GutTest

## Checks that existed and that Validate never ran (#657, #666, #669).
##
## Each of these was implemented, working, and reachable from somewhere other
## than the button a mapper presses before shipping. `validate_convexity()` gated
## the vertex tools, `validate_spawn()` sat 130 lines from the function that
## placed the spawn, and `check_missing_dependencies()` walked the material
## palette and nothing else.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")


func _fresh_root() -> LevelRoot:
	var root := LevelRootType.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	root.owner = self
	return root


func _box(root: LevelRoot, at: Vector3, size := Vector3(2, 2, 2)) -> Node:
	return (
		root
		. create_brush_from_info(
			{
				"shape": root.BrushShape.BOX,
				"size": size,
				"transform": Transform3D(Basis.IDENTITY, at),
				"operation": CSGShape3D.OPERATION_UNION,
			}
		)
	)


func _issue_mentioning(root: LevelRoot, needle: String) -> String:
	for issue in root.validate_level().get("issues", []):
		if str(issue).to_lower().contains(needle.to_lower()):
			return str(issue)
	return ""


# ===========================================================================
# Merge only joins brushes that touch (#666)
# ===========================================================================


func test_merge_refuses_brushes_that_do_not_touch():
	var root := _fresh_root()
	var a := _box(root, Vector3.ZERO)
	var b := _box(root, Vector3(8, 0, 0))
	var result = root.brush_system.can_merge_brushes(
		[str(a.get("brush_id")), str(b.get("brush_id"))]
	)
	assert_false(result.ok, "two cubes eight units apart are not one solid")
	assert_string_contains(str(result.user_text()), "touch")


func test_merge_still_joins_brushes_that_overlap():
	var root := _fresh_root()
	var a := _box(root, Vector3.ZERO)
	var b := _box(root, Vector3(1, 0, 0))
	assert_true(
		root.brush_system.can_merge_brushes([str(a.get("brush_id")), str(b.get("brush_id"))]).ok,
		"an overlapping pair is the ordinary case and must still merge"
	)


func test_merge_joins_a_chain_that_only_touches_end_to_end():
	# Connectivity is transitive: the first and last cube do not touch each
	# other, but the run of them is one solid.
	var root := _fresh_root()
	var ids: Array = []
	for i in 3:
		ids.append(str(_box(root, Vector3(i * 2.0, 0, 0)).get("brush_id")))
	assert_true(
		root.brush_system.can_merge_brushes(ids).ok, "a touching run is one lump, not three"
	)


func test_validate_reports_a_brush_that_is_not_convex():
	# The shape the old merge produced: one brush whose faces describe two lumps
	# with a gap between them. A `.map` import or a hand edited `.tscn` can
	# deliver the same thing, which is why Validate wants the check and not only
	# the merge guard.
	var root := _fresh_root()
	var brush := _box(root, Vector3.ZERO)
	var faces: Array = []
	faces.append_array(brush.get("faces"))
	for face in brush.get("faces"):
		var far: FaceData = face.duplicate()
		var moved := PackedVector3Array()
		for v in face.local_verts:
			moved.append(v + Vector3(8, 0, 0))
		far.local_verts = moved
		faces.append(far)
	var typed: Array[FaceData] = []
	for f in faces:
		typed.append(f)
	brush.faces = typed

	assert_false(
		root.vertex_system.validate_convexity(brush), "the brush really is two separate lumps"
	)
	assert_ne(
		_issue_mentioning(root, "convex"),
		"",
		"the check that gates the vertex tools is one Validate runs now"
	)


# ===========================================================================
# The spawn (#657)
# ===========================================================================


func test_a_created_spawn_stands_on_the_floor():
	var root := _fresh_root()
	_box(root, Vector3(0, 1.5, 0), Vector3(8, 3, 8))
	var spawn: Node3D = root.spawn_system.create_default_spawn()
	var bounds: AABB = root._compute_level_aabb()
	assert_almost_eq(
		spawn.global_position.y,
		bounds.position.y + 1.0,
		0.001,
		"one metre above the floor, not five above the centroid of the origins"
	)
	assert_true(bounds.has_point(spawn.global_position), "and inside the room, not above it")


func test_validate_reports_a_spawn_outside_the_level():
	var root := _fresh_root()
	_box(root, Vector3(0, 1.5, 0), Vector3(8, 3, 8))
	var spawn: Node3D = root.spawn_system.create_default_spawn()
	spawn.global_position = Vector3(0, 40, 0)
	assert_ne(_issue_mentioning(root, "spawn"), "", "a spawn above the ceiling is reported")


func test_validate_says_nothing_about_a_spawn_that_is_fine():
	var root := _fresh_root()
	_box(root, Vector3(0, 1.5, 0), Vector3(8, 3, 8))
	root.spawn_system.create_default_spawn()
	assert_eq(
		_issue_mentioning(root, "spawn"),
		"",
		"a check that cries wolf on an ordinary level is worse than the silence it replaced"
	)


func test_validate_says_nothing_about_a_level_that_has_no_spawn_yet():
	# A level with no spawn is a level being built. `create_default_spawn()` makes
	# one and the playtest export makes one, so saying so on every press is the
	# crying wolf this check exists to avoid.
	var root := _fresh_root()
	_box(root, Vector3(0, 1.5, 0), Vector3(8, 3, 8))
	assert_eq(_issue_mentioning(root, "spawn"), "", "nothing is wrong with it yet")


# ===========================================================================
# A prefab instance whose source has gone (#669)
# ===========================================================================


func test_validate_reports_a_prefab_instance_whose_source_is_missing():
	var root := _fresh_root()
	var record = root.prefab_system.PrefabInstanceRecord.new()
	record.instance_id = "pfx_1"
	record.source_path = "res://prefabs/hf_test_absent.hfprefab"
	root.prefab_system._instances["pfx_1"] = record
	var issue := _issue_mentioning(root, "not there")
	assert_ne(issue, "", "the operations behave; it was only the reporting that was missing")
	assert_string_contains(issue, "pfx_1", "and it names the instance")
