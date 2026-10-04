extends GutTest

## The way a selection is facing, and what gets built on it.
##
## `resolve_pivot()` says where a structure lands. This is the other half of that
## sentence: an arch built on a wall standing at forty-five degrees should stand
## at forty-five degrees too. The answer has to be conservative — a selection that
## does not agree with itself has no single direction to give, and one that has
## been mirrored or scaled has a basis nothing should be built through.

const HFBrushSystem = preload("res://addons/hammerforge/systems/hf_brush_system.gd")
const HFTransformSystemScript = preload("res://addons/hammerforge/systems/hf_transform_system.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")
const DraftEntity = preload("res://addons/hammerforge/draft_entity.gd")

const EPS := 0.001

var root: LevelRoot
var brushes: HFBrushSystem
var sys


func before_each():
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	brushes = root.brush_system
	sys = root.transform_system


func after_each():
	root = null
	brushes = null
	sys = null


func _make_brush(brush_id: String, basis: Basis = Basis.IDENTITY) -> DraftBrush:
	var b = DraftBrush.new()
	b.shape = LevelRoot.BrushShape.BOX
	b.size = Vector3(32, 32, 32)
	b.brush_id = brush_id
	b.set_meta("brush_id", brush_id)
	root.draft_brushes_node.add_child(b)
	b.global_transform = Transform3D(basis, Vector3.ZERO)
	b.rebuild_preview()
	brushes._register_brush_id(brush_id, b)
	return b


func _turned(degrees: float) -> Basis:
	return Basis(Vector3.UP, deg_to_rad(degrees))


func _assert_basis(actual: Basis, expected: Basis, context: String) -> void:
	for axis in 3:
		assert_almost_eq(actual[axis], expected[axis], Vector3.ONE * EPS, context)


# ===========================================================================
# What counts as a turn and nothing else
# ===========================================================================


func test_the_world_axes_are_a_rotation():
	assert_true(HFTransformSystemScript.is_rotation_basis(Basis.IDENTITY))


func test_a_turn_is_a_rotation():
	assert_true(HFTransformSystemScript.is_rotation_basis(_turned(37.0)))


func test_a_mirror_is_not_a_rotation():
	# The one that matters most: a negative determinant inverts the winding of
	# every face built through it, and does not look wrong until the bake.
	assert_false(
		HFTransformSystemScript.is_rotation_basis(Basis.from_scale(Vector3(-1.0, 1.0, 1.0)))
	)


func test_a_squash_is_not_a_rotation():
	assert_false(
		HFTransformSystemScript.is_rotation_basis(Basis.from_scale(Vector3(1.0, 0.5, 1.0)))
	)


func test_a_uniform_scale_is_not_a_rotation():
	assert_false(HFTransformSystemScript.is_rotation_basis(Basis.from_scale(Vector3.ONE * 2.0)))


# ===========================================================================
# The way a selection is facing
# ===========================================================================


func test_nothing_selected_faces_the_world_axes():
	_assert_basis(sys.resolve_selection_basis([], []), Basis.IDENTITY, "an empty selection")


func test_one_turned_brush_gives_its_own_facing():
	_make_brush("b1", _turned(45.0))

	_assert_basis(sys.resolve_selection_basis(["b1"], []), _turned(45.0), "a single brush")


func test_brushes_facing_the_same_way_give_that_facing():
	_make_brush("b1", _turned(90.0))
	_make_brush("b2", _turned(90.0))

	_assert_basis(sys.resolve_selection_basis(["b1", "b2"], []), _turned(90.0), "an agreeing pair")


func test_brushes_facing_different_ways_give_the_world_axes():
	# There is no single direction to inherit, and guessing one would be worse
	# than not answering.
	_make_brush("b1", _turned(90.0))
	_make_brush("b2", _turned(30.0))

	_assert_basis(sys.resolve_selection_basis(["b1", "b2"], []), Basis.IDENTITY, "a disagreement")


func test_a_mirrored_brush_gives_the_world_axes():
	_make_brush("b1", _turned(45.0) * Basis.from_scale(Vector3(-1.0, 1.0, 1.0)))

	_assert_basis(sys.resolve_selection_basis(["b1"], []), Basis.IDENTITY, "a mirrored brush")


func test_a_scaled_brush_gives_the_world_axes():
	_make_brush("b1", Basis.from_scale(Vector3(2.0, 1.0, 1.0)))

	_assert_basis(sys.resolve_selection_basis(["b1"], []), Basis.IDENTITY, "a scaled brush")


func test_one_mirrored_brush_spoils_an_otherwise_agreeing_selection():
	_make_brush("b1", _turned(45.0))
	_make_brush("b2", _turned(45.0) * Basis.from_scale(Vector3(1.0, 1.0, -1.0)))

	_assert_basis(sys.resolve_selection_basis(["b1", "b2"], []), Basis.IDENTITY, "a spoiled pair")


func test_a_brush_that_is_gone_does_not_speak_for_the_selection():
	_make_brush("b1", _turned(45.0))

	_assert_basis(
		sys.resolve_selection_basis(["b1", "missing"], []),
		_turned(45.0),
		"a name with no brush behind it says nothing either way"
	)


func test_a_turned_entity_gives_its_facing_too():
	var e = DraftEntity.new()
	e.name = "Rotor"
	root.add_child(e)
	e.global_transform = Transform3D(_turned(60.0), Vector3.ZERO)

	_assert_basis(
		sys.resolve_selection_basis([], [str(root.get_path_to(e))]),
		_turned(60.0),
		"entities are part of a selection"
	)


func test_a_brush_and_an_entity_have_to_agree_with_each_other():
	_make_brush("b1", _turned(60.0))
	var e = DraftEntity.new()
	e.name = "Rotor"
	root.add_child(e)
	e.global_transform = Transform3D(_turned(15.0), Vector3.ZERO)

	_assert_basis(
		sys.resolve_selection_basis(["b1"], [str(root.get_path_to(e))]),
		Basis.IDENTITY,
		"a mixed selection is still one selection"
	)
