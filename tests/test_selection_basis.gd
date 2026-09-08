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

var root: Node3D
var brushes: HFBrushSystem
var sys


func before_each():
	root = Node3D.new()
	root.set_script(_root_shim_script())
	add_child_autoqfree(root)
	var draft = Node3D.new()
	draft.name = "DraftBrushes"
	root.add_child(draft)
	root.draft_brushes_node = draft
	root.pending_node = null
	root.committed_node = null
	root._brush_id_counter = 0
	root.grid_snap = 0.0
	root.face_selection = {}
	root.brush_manager = null
	root._material_palette = []
	root.texture_lock = false
	brushes = HFBrushSystem.new(root)
	root.brush_system = brushes
	sys = HFTransformSystemScript.new(root)
	root.transform_system = sys


func after_each():
	root = null
	brushes = null
	sys = null


func _make_brush(brush_id: String, basis: Basis = Basis.IDENTITY) -> DraftBrush:
	var b = DraftBrush.new()
	b.shape = 0
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


func _root_shim_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = """
extends Node3D

enum BrushShape { BOX, CYLINDER, CONE, SPHERE, WEDGE, ELLIPSOID, CAPSULE, TORUS, CUSTOM }

var draft_brushes_node: Node3D
var pending_node: Node3D
var committed_node: Node3D
var brush_system = null
var transform_system = null
var brush_manager = null
var texture_lock := false
var grid_snap := 0.0
var drag_size_default := Vector3(32, 32, 32)
var face_selection := {}
var _brush_id_counter := 0
var _material_palette := []


func _iter_pick_nodes() -> Array:
	var out: Array = []
	if draft_brushes_node:
		out.append_array(draft_brushes_node.get_children())
	return out


func is_entity_node(_node: Node) -> bool:
	return false


func _log(_msg): pass


func _assign_owner(_node: Node) -> void: pass


func tag_full_reconcile() -> void: pass


func tag_brush_dirty(_id: String) -> void: pass
"""
	script.reload()
	return script
