extends GutTest

const HFVisgroupSystem = preload("res://addons/hammerforge/systems/hf_visgroup_system.gd")

var root: LevelRoot
var sys: HFVisgroupSystem


func _make_brush(parent: Node3D, brush_name: String = "TestBrush") -> Node3D:
	var b = Node3D.new()
	b.name = brush_name
	parent.add_child(b)
	return b


func before_each():
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	sys = root.visgroup_system


func after_each():
	root = null
	sys = null


# ===========================================================================
# Group CRUD
# ===========================================================================


func test_group_selection_creates_group():
	var draft_parent = root.get_node("DraftBrushes")
	var b1 = _make_brush(draft_parent, "A")
	var b2 = _make_brush(draft_parent, "B")
	sys.group_selection("grp1", [b1, b2])
	var names = sys.get_group_names()
	assert_eq(names.size(), 1)
	assert_eq(names[0], "grp1")


func test_group_sets_meta_on_nodes():
	var draft_parent = root.get_node("DraftBrushes")
	var b1 = _make_brush(draft_parent, "A")
	var b2 = _make_brush(draft_parent, "B")
	sys.group_selection("grp1", [b1, b2])
	assert_eq(sys.get_group_of(b1), "grp1")
	assert_eq(sys.get_group_of(b2), "grp1")


func test_get_group_members():
	var draft_parent = root.get_node("DraftBrushes")
	var b1 = _make_brush(draft_parent, "A")
	var b2 = _make_brush(draft_parent, "B")
	var b3 = _make_brush(draft_parent, "C")
	sys.group_selection("grp1", [b1, b2])
	var members = sys.get_group_members("grp1")
	assert_eq(members.size(), 2)
	assert_true(members.has(b1))
	assert_true(members.has(b2))
	assert_false(members.has(b3))


func test_ungroup_clears_meta():
	var draft_parent = root.get_node("DraftBrushes")
	var b1 = _make_brush(draft_parent, "A")
	var b2 = _make_brush(draft_parent, "B")
	sys.group_selection("grp1", [b1, b2])
	sys.ungroup_nodes([b1, b2])
	assert_eq(sys.get_group_of(b1), "")
	assert_eq(sys.get_group_of(b2), "")


func test_ungroup_removes_empty_group():
	var draft_parent = root.get_node("DraftBrushes")
	var b1 = _make_brush(draft_parent, "A")
	sys.group_selection("grp1", [b1])
	sys.ungroup_nodes([b1])
	assert_eq(sys.get_group_names().size(), 0, "Empty group should be cleaned up")


func test_regroup_moves_to_new_group():
	var draft_parent = root.get_node("DraftBrushes")
	var b1 = _make_brush(draft_parent, "A")
	sys.group_selection("grp1", [b1])
	sys.group_selection("grp2", [b1])
	assert_eq(sys.get_group_of(b1), "grp2", "Node should be in new group")
	assert_eq(sys.get_group_members("grp1").size(), 0, "Old group should be empty")


func test_remove_group_clears_all_members():
	var draft_parent = root.get_node("DraftBrushes")
	var b1 = _make_brush(draft_parent, "A")
	var b2 = _make_brush(draft_parent, "B")
	sys.group_selection("grp1", [b1, b2])
	sys.remove_group("grp1")
	assert_eq(sys.get_group_of(b1), "")
	assert_eq(sys.get_group_of(b2), "")
	assert_eq(sys.get_group_names().size(), 0)


func test_node_not_in_group_returns_empty():
	var draft_parent = root.get_node("DraftBrushes")
	var b1 = _make_brush(draft_parent, "A")
	assert_eq(sys.get_group_of(b1), "")


# ===========================================================================
# Group serialization
# ===========================================================================


func test_capture_restore_groups_round_trip():
	var draft_parent = root.get_node("DraftBrushes")
	var b1 = _make_brush(draft_parent, "A")
	sys.group_selection("grp1", [b1])
	var captured = sys.capture_groups()
	# A second system, so the restore lands in a registry that has never seen grp1.
	var sys2 = HFVisgroupSystem.new(root)
	sys2.restore_groups(captured)
	assert_eq(sys2.get_group_names().size(), 1)
	assert_eq(sys2.get_group_names()[0], "grp1")
