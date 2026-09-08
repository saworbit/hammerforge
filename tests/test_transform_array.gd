extends GutTest

## Radial and grid array layouts in HFDuplicator, and the brush-system entry
## points that create them.

const HFBrushSystem = preload("res://addons/hammerforge/systems/hf_brush_system.gd")
const HFDuplicatorScript = preload("res://addons/hammerforge/hf_duplicator.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")

var root: Node3D
var brushes: HFBrushSystem


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
	brushes = HFBrushSystem.new(root)
	root.brush_system = brushes


func after_each():
	root = null
	brushes = null


func _root_shim_script() -> GDScript:
	var s = GDScript.new()
	s.source_code = """
extends Node3D

var draft_brushes_node: Node3D
var pending_node: Node3D
var committed_node: Node3D
var _brush_id_counter: int = 0
var grid_snap: float = 0.0
var face_selection: Dictionary = {}
var brush_manager = null
var brush_system = null
var texture_lock: bool = false
var drag_size_default: Vector3 = Vector3(32, 32, 32)
var _material_palette: Array = []

enum BrushShape { BOX, CYLINDER, SPHERE, CONE, WEDGE, PYRAMID, PRISM_TRI, PRISM_PENT, ELLIPSOID, CAPSULE, TORUS, TETRAHEDRON, OCTAHEDRON, DODECAHEDRON, ICOSAHEDRON, CUSTOM }

func _iter_pick_nodes() -> Array:
	var out: Array = []
	if draft_brushes_node:
		out.append_array(draft_brushes_node.get_children())
	return out

func is_entity_node(_node: Node) -> bool:
	return false

func _log(msg: String) -> void:
	pass

func _assign_owner(node: Node) -> void:
	pass

func _record_last_brush(_pos: Vector3) -> void:
	pass

func tag_full_reconcile() -> void:
	pass

func tag_brush_dirty(_id: String) -> void:
	pass

func add_material_to_palette(material: Material) -> int:
	_material_palette.append(material)
	return _material_palette.size() - 1
"""
	s.reload()
	return s


func _make_brush(
	pos: Vector3 = Vector3.ZERO, sz: Vector3 = Vector3(32, 32, 32), brush_id: String = ""
) -> DraftBrush:
	var b = DraftBrush.new()
	b.size = sz
	if brush_id == "":
		root._brush_id_counter += 1
		brush_id = "test_%d" % root._brush_id_counter
	b.brush_id = brush_id
	b.set_meta("brush_id", brush_id)
	root.draft_brushes_node.add_child(b)
	b.global_position = pos
	brushes._register_brush_id(brush_id, b)
	return b


func _instance_positions(dup) -> Array:
	var out: Array = []
	for brush_id in dup.get_all_instance_ids():
		var node = brushes.find_brush_by_id(brush_id)
		if is_instance_valid(node):
			out.append(node.global_position)
	return out


# ===========================================================================
# Radial
# ===========================================================================


func test_radial_array_creates_the_requested_number_of_copies():
	_make_brush(Vector3(100, 0, 0), Vector3(32, 32, 32), "src")
	var dup = brushes.create_radial_array(PackedStringArray(["src"]), 3, 1, 90.0, Vector3.ZERO)
	assert_not_null(dup)
	assert_eq(dup.get_all_instance_ids().size(), 3)


func test_radial_array_places_copies_at_the_step_angle():
	_make_brush(Vector3(100, 0, 0), Vector3(32, 32, 32), "src")
	var dup = brushes.create_radial_array(PackedStringArray(["src"]), 3, 1, 90.0, Vector3.ZERO)
	var positions := _instance_positions(dup)
	assert_eq(positions.size(), 3)
	# 90, 180 and 270 degrees about +Y from +X.
	assert_true(positions[0].is_equal_approx(Vector3(0, 0, -100)), str(positions[0]))
	assert_true(positions[1].is_equal_approx(Vector3(-100, 0, 0)), str(positions[1]))
	assert_true(positions[2].is_equal_approx(Vector3(0, 0, 100)), str(positions[2]))


func test_radial_array_turns_each_copy_as_well_as_moving_it():
	_make_brush(Vector3(100, 0, 0), Vector3(32, 32, 32), "src")
	var dup = brushes.create_radial_array(PackedStringArray(["src"]), 1, 1, 90.0, Vector3.ZERO)
	var copy = brushes.find_brush_by_id(dup.get_all_instance_ids()[0])
	var expected := Basis(Vector3.UP, deg_to_rad(90.0))
	assert_true(
		copy.global_transform.basis.is_equal_approx(expected),
		"a ring of copies should face outward, not all the same way"
	)


func test_radial_array_rotates_about_the_given_pivot():
	_make_brush(Vector3(100, 0, 0), Vector3(32, 32, 32), "src")
	var dup = brushes.create_radial_array(
		PackedStringArray(["src"]), 1, 1, 180.0, Vector3(50, 0, 0)
	)
	var positions := _instance_positions(dup)
	assert_true(positions[0].is_equal_approx(Vector3(0, 0, 0)), str(positions[0]))


func test_radial_array_about_x_moves_in_the_yz_plane():
	_make_brush(Vector3(0, 100, 0), Vector3(32, 32, 32), "src")
	var dup = brushes.create_radial_array(PackedStringArray(["src"]), 1, 0, 90.0, Vector3.ZERO)
	var positions := _instance_positions(dup)
	assert_almost_eq(positions[0].x, 0.0, 0.001)
	assert_almost_eq(positions[0].y, 0.0, 0.001)
	assert_almost_eq(absf(positions[0].z), 100.0, 0.001)


func test_radial_array_rejects_a_zero_count():
	_make_brush(Vector3(100, 0, 0), Vector3(32, 32, 32), "src")
	assert_null(brushes.create_radial_array(PackedStringArray(["src"]), 0, 1, 90.0, Vector3.ZERO))


func test_radial_array_rejects_an_empty_source():
	assert_null(brushes.create_radial_array(PackedStringArray([]), 3, 1, 90.0, Vector3.ZERO))


func test_radial_array_clears_its_instances():
	_make_brush(Vector3(100, 0, 0), Vector3(32, 32, 32), "src")
	var dup = brushes.create_radial_array(PackedStringArray(["src"]), 3, 1, 90.0, Vector3.ZERO)
	dup.clear_instances(brushes)
	assert_eq(dup.get_all_instance_ids().size(), 0)
	assert_eq(root.draft_brushes_node.get_child_count(), 1, "only the source should remain")


# ===========================================================================
# Grid
# ===========================================================================


func test_grid_array_creates_every_cell_but_the_source():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "src")
	var dup = brushes.create_grid_array(
		PackedStringArray(["src"]), Vector3i(2, 2, 2), Vector3(64, 64, 64)
	)
	assert_not_null(dup)
	assert_eq(dup.get_all_instance_ids().size(), 7, "2x2x2 is eight cells, one of them the source")


func test_grid_array_spaces_copies_by_the_given_gap():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "src")
	var dup = brushes.create_grid_array(
		PackedStringArray(["src"]), Vector3i(3, 1, 1), Vector3(64, 0, 0)
	)
	var positions := _instance_positions(dup)
	assert_eq(positions.size(), 2)
	assert_true(positions[0].is_equal_approx(Vector3(64, 0, 0)), str(positions[0]))
	assert_true(positions[1].is_equal_approx(Vector3(128, 0, 0)), str(positions[1]))


func test_grid_array_rejects_a_single_cell():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "src")
	assert_null(
		brushes.create_grid_array(
			PackedStringArray(["src"]), Vector3i(1, 1, 1), Vector3(64, 64, 64)
		)
	)


func test_grid_array_clamps_a_zero_count_to_one():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "src")
	var dup = brushes.create_grid_array(
		PackedStringArray(["src"]), Vector3i(0, 2, 0), Vector3(64, 64, 64)
	)
	assert_not_null(dup)
	assert_eq(dup.get_all_instance_ids().size(), 1)


# ===========================================================================
# One array per source
# ===========================================================================


func test_a_new_array_replaces_the_previous_one():
	_make_brush(Vector3(100, 0, 0), Vector3(32, 32, 32), "src")
	brushes.create_radial_array(PackedStringArray(["src"]), 3, 1, 90.0, Vector3.ZERO)
	brushes.create_grid_array(PackedStringArray(["src"]), Vector3i(2, 1, 1), Vector3(64, 0, 0))
	# The source plus exactly the one copy the grid array made.
	assert_eq(root.draft_brushes_node.get_child_count(), 2)


# ===========================================================================
# Serialization
# ===========================================================================


func test_radial_settings_round_trip():
	var dup = HFDuplicatorScript.new()
	dup.source_brush_ids = PackedStringArray(["a", "b"])
	dup.mode = HFDuplicatorScript.ArrayMode.RADIAL
	dup.axis_index = 2
	dup.step_degrees = 45.0
	dup.pivot = Vector3(1, 2, 3)
	var restored = HFDuplicatorScript.from_dict(dup.to_dict())
	assert_eq(restored.mode, HFDuplicatorScript.ArrayMode.RADIAL)
	assert_eq(restored.axis_index, 2)
	assert_almost_eq(restored.step_degrees, 45.0, 0.001)
	assert_true(restored.pivot.is_equal_approx(Vector3(1, 2, 3)))


func test_grid_settings_round_trip():
	var dup = HFDuplicatorScript.new()
	dup.mode = HFDuplicatorScript.ArrayMode.GRID
	dup.grid_counts = Vector3i(4, 2, 3)
	dup.grid_spacing = Vector3(8, 16, 24)
	var restored = HFDuplicatorScript.from_dict(dup.to_dict())
	assert_eq(restored.grid_counts, Vector3i(4, 2, 3))
	assert_true(restored.grid_spacing.is_equal_approx(Vector3(8, 16, 24)))


func test_a_dictionary_without_a_mode_loads_as_linear():
	var restored = (
		HFDuplicatorScript
		. from_dict(
			{
				"duplicator_id": "dup_old",
				"source_brush_ids": ["a"],
				"count": 3,
				"offset": [8.0, 0.0, 0.0],
				"instance_groups": [],
			}
		)
	)
	assert_eq(restored.mode, HFDuplicatorScript.ArrayMode.LINEAR)
	assert_eq(restored.count, 3)
	assert_true(restored.offset.is_equal_approx(Vector3(8, 0, 0)))


func test_linear_array_still_works():
	_make_brush(Vector3.ZERO, Vector3(32, 32, 32), "src")
	var dup = brushes.create_duplicate_array(PackedStringArray(["src"]), 2, Vector3(64, 0, 0))
	assert_not_null(dup)
	assert_eq(dup.mode, HFDuplicatorScript.ArrayMode.LINEAR)
	var positions := _instance_positions(dup)
	assert_true(positions[0].is_equal_approx(Vector3(64, 0, 0)))
	assert_true(positions[1].is_equal_approx(Vector3(128, 0, 0)))
