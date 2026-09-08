extends GutTest

## HFDomeBuilder: rings, because a patch of sphere is not a brush.
##
## The construction claim this file exists to check is that every panel is a
## genuine convex solid with planar faces. Four points on a sphere at two
## latitudes and two longitudes are not coplanar; four points on a conical frustum
## band are. If that claim is wrong the dome looks fine in the editor and bakes
## into folded rubbish, so it is measured rather than trusted.

const HFDomeBuilderScript = preload("res://addons/hammerforge/hf_dome_builder.gd")
const SolidChecks = preload("res://tests/solid_checks.gd")

const EPS := 0.001


func _settings(overrides: Dictionary = {}) -> Dictionary:
	var s: Dictionary = HFDomeBuilderScript.default_settings()
	for key in overrides:
		s[key] = overrides[key]
	return s


## The largest distance any of a face's vertices sits off the plane of its first
## three. A face that is not planar is not a face.
func _worst_planarity(faces: Array) -> float:
	var worst := 0.0
	for face in faces:
		var verts: PackedVector3Array = face.local_verts
		if verts.size() < 4:
			continue
		var a: Vector3 = verts[0]
		var normal: Vector3 = (verts[1] - a).cross(verts[2] - a)
		if normal.length() < 0.000001:
			continue
		normal = normal.normalized()
		for v in verts:
			worst = maxf(worst, absf(normal.dot(v - a)))
	return worst


# ===========================================================================
# The construction claim
# ===========================================================================


func test_every_face_of_every_panel_is_planar():
	# This is the whole reason the dome is built in rings rather than in patches.
	for panel in HFDomeBuilderScript.build(_settings({"rings": 5, "segments": 16})):
		assert_almost_eq(_worst_planarity(panel), 0.0, 0.01, "a panel face is warped")


func test_every_panel_is_a_closed_convex_solid_facing_outward():
	for panel in HFDomeBuilderScript.build(_settings()):
		assert_eq(SolidChecks.describe_problem(panel), "", "a panel would not bake")


func test_the_panel_count_is_rings_times_segments():
	assert_eq(HFDomeBuilderScript.build(_settings({"rings": 4, "segments": 12})).size(), 48)
	assert_eq(HFDomeBuilderScript.build(_settings({"rings": 1, "segments": 6})).size(), 6)


# ===========================================================================
# Where the shell pinches
# ===========================================================================


func test_the_crown_ring_is_a_wedge_rather_than_a_box():
	# At the pole the inner surface has closed onto the axis, so the top ring's
	# panels have an apex instead of a top face.
	var panels: Array = HFDomeBuilderScript.build(
		_settings({"rings": 3, "segments": 8, "sweep_degrees": 90.0})
	)
	var crown: Array = panels[panels.size() - 1]
	assert_eq(SolidChecks.describe_problem(crown), "", "the crown panel would not bake")
	assert_lt(crown.size(), 6, "a panel that pinches has fewer faces than a box")


func test_a_solid_dome_is_wedges_meeting_the_axis():
	var settings := _settings({"radius": 100.0, "wall_thickness": 100.0, "rings": 3})
	assert_true(HFDomeBuilderScript.validate(settings).ok, "a wall as thick as the radius is solid")
	var panels: Array = HFDomeBuilderScript.build(settings)
	assert_gt(panels.size(), 0)
	for panel in panels:
		assert_eq(SolidChecks.describe_problem(panel), "", "a solid dome panel would not bake")


func test_a_truncated_dome_leaves_its_crown_open():
	var panels: Array = HFDomeBuilderScript.build(
		_settings({"rings": 2, "segments": 8, "sweep_degrees": 45.0, "radius": 100.0})
	)
	var box: AABB = SolidChecks.structure_bounds(panels)
	# sin(45) of 100 is about 70.7, so a 45-degree sweep stops well short of a
	# hemisphere.
	assert_almost_eq(box.size.y, 70.71, 0.1)
	for panel in panels:
		assert_eq(SolidChecks.describe_problem(panel), "")


# ===========================================================================
# The dimensions it claims
# ===========================================================================


func test_the_dome_spans_its_own_diameter():
	var box: AABB = SolidChecks.structure_bounds(
		HFDomeBuilderScript.build(_settings({"radius": 150.0, "segments": 32, "rings": 6}))
	)
	assert_almost_eq(box.size.x, 300.0, 1.0)
	assert_almost_eq(box.size.z, 300.0, 1.0)
	assert_almost_eq(box.size.y, 150.0, 1.0, "a hemisphere is one radius tall")


func test_the_dome_is_centred_on_its_own_origin_vertically():
	var box: AABB = SolidChecks.structure_bounds(HFDomeBuilderScript.build(_settings()))
	assert_almost_eq(box.get_center().y, 0.0, EPS)


func test_a_shell_is_hollow_under_the_crown():
	# A point just inside the inner radius at the base is inside no panel.
	var radius := 128.0
	var thickness := 16.0
	var panels: Array = HFDomeBuilderScript.build(
		_settings({"radius": radius, "wall_thickness": thickness, "rings": 4, "segments": 16})
	)
	var probe := Vector3(
		radius - thickness - 8.0, SolidChecks.structure_bounds(panels).position.y + 1.0, 0.0
	)
	for panel in panels:
		assert_false(_contains(panel, probe), "the shell is filled where it should be hollow")


func test_a_slice_of_a_dome_is_a_slice():
	var whole: Array = HFDomeBuilderScript.build(_settings({"arc_degrees": 360.0, "segments": 12}))
	var half: Array = HFDomeBuilderScript.build(_settings({"arc_degrees": 180.0, "segments": 12}))
	assert_eq(whole.size(), half.size(), "the segment count is what it is asked for either way")
	assert_lt(
		SolidChecks.structure_bounds(half).get_volume(),
		SolidChecks.structure_bounds(whole).get_volume(),
		"a slice occupies less than the whole"
	)
	for panel in half:
		assert_eq(SolidChecks.describe_problem(panel), "")


func _contains(faces: Array, point: Vector3) -> bool:
	var centre: Vector3 = SolidChecks.centroid(faces)
	for face in faces:
		var verts: PackedVector3Array = face.local_verts
		if verts.size() < 3:
			continue
		var a: Vector3 = verts[0]
		var normal: Vector3 = (verts[2] - a).cross(verts[1] - a)
		if normal.length() < 0.000001:
			continue
		normal = normal.normalized()
		if normal.dot(centre - a) > 0.0:
			normal = -normal
		if normal.dot(point - a) > 0.01:
			return false
	return true


# ===========================================================================
# Refusals
# ===========================================================================


func test_a_dome_bigger_than_the_panel_cap_is_refused_and_says_the_number():
	var result = HFDomeBuilderScript.validate(_settings({"rings": 32, "segments": 32}))
	assert_false(result.ok)
	assert_true(str(result.message).contains("1024"), str(result.message))
	assert_true(
		str(result.fix_hint).contains(str(HFDomeBuilderScript.MAX_PANELS)),
		"the hint must name the cap"
	)


func test_the_cap_itself_is_allowed():
	var cap: int = HFDomeBuilderScript.MAX_PANELS
	assert_true(HFDomeBuilderScript.validate(_settings({"rings": 8, "segments": cap / 8})).ok)


func test_a_wall_thicker_than_the_radius_is_refused():
	assert_true(
		HFDomeBuilderScript.validate(_settings({"radius": 64.0, "wall_thickness": 64.0})).ok
	)
	assert_false(
		HFDomeBuilderScript.validate(_settings({"radius": 64.0, "wall_thickness": 65.0})).ok
	)


func test_too_few_segments_to_close_a_ring_is_refused():
	assert_false(HFDomeBuilderScript.validate(_settings({"segments": 2})).ok)
	assert_true(HFDomeBuilderScript.validate(_settings({"segments": 3})).ok)


func test_a_sweep_outside_the_quarter_turn_is_refused():
	assert_false(HFDomeBuilderScript.validate(_settings({"sweep_degrees": 0.0})).ok)
	assert_false(HFDomeBuilderScript.validate(_settings({"sweep_degrees": 91.0})).ok)
	assert_true(HFDomeBuilderScript.validate(_settings({"sweep_degrees": 90.0})).ok)


func test_a_refused_dome_builds_nothing():
	assert_eq(HFDomeBuilderScript.build(_settings({"segments": 1})).size(), 0)


# ===========================================================================
# Schema
# ===========================================================================


func test_the_schema_describes_exactly_the_settings_the_builder_uses():
	var schema: Array = HFDomeBuilderScript.settings_schema()
	var defaults: Dictionary = HFDomeBuilderScript.default_settings()
	assert_eq(schema.size(), defaults.size())
	for field in schema:
		assert_true(defaults.has(field["key"]), "%s is described but never used" % field["key"])
		assert_true(str(field.get("tooltip", "")) != "", "%s has no tooltip" % field["key"])


func test_the_defaults_build_a_dome():
	assert_true(HFDomeBuilderScript.validate({}).ok)
	assert_eq(HFDomeBuilderScript.build({}).size(), 48)


func test_a_single_ring_reaching_the_pole_is_still_solids():
	# One ring from the equator to the crown is the most degenerate dome there is:
	# every panel pinches at the top and there is no ring below to hide it.
	var panels: Array = HFDomeBuilderScript.build(
		_settings({"rings": 1, "segments": 8, "sweep_degrees": 90.0})
	)
	assert_eq(panels.size(), 8)
	for panel in panels:
		assert_eq(SolidChecks.describe_problem(panel), "", "a one-ring dome panel would not bake")


func test_a_dome_sweeping_the_other_way_round_is_still_solids():
	var panels: Array = HFDomeBuilderScript.build(
		_settings({"arc_degrees": -180.0, "segments": 8, "rings": 3})
	)
	assert_eq(panels.size(), 24)
	for panel in panels:
		assert_eq(SolidChecks.describe_problem(panel), "", "a reversed arc broke a panel")


func test_a_thin_shell_on_a_big_dome_is_still_solids():
	# The narrowest wall the ranges allow, where the inner and outer surfaces are
	# closest to being the same plane.
	var panels: Array = HFDomeBuilderScript.build(
		_settings({"radius": 4096.0, "wall_thickness": 1.0, "rings": 3, "segments": 8})
	)
	for panel in panels:
		assert_eq(SolidChecks.describe_problem(panel), "", "a thin shell folded")
