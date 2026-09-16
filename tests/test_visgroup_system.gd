extends GutTest

const HFVisgroupSystem = preload("res://addons/hammerforge/systems/hf_visgroup_system.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")

var root: Node3D
var sys: HFVisgroupSystem


func _make_root() -> Node3D:
	var r = Node3D.new()
	var draft = Node3D.new()
	draft.name = "DraftBrushes"
	r.add_child(draft)
	var entities = Node3D.new()
	entities.name = "Entities"
	r.add_child(entities)
	# Provide the methods the system expects
	r.set_meta("_entities_node", entities)
	return r


func _make_brush(parent: Node3D) -> Node3D:
	var b = Node3D.new()
	b.name = "TestBrush"
	parent.add_child(b)
	return b


func before_each():
	root = _make_root()
	add_child_autoqfree(root)
	# Attach _iter_pick_nodes and entities_node via script
	root.set_script(_root_shim_script())
	sys = HFVisgroupSystem.new(root)


func after_each():
	root = null
	sys = null


func _root_shim_script() -> GDScript:
	var s = GDScript.new()
	s.source_code = """
extends Node3D

var entities_node: Node3D:
	get:
		return get_node_or_null("Entities")

func _iter_pick_nodes() -> Array:
	var out: Array = []
	var draft = get_node_or_null("DraftBrushes")
	if draft:
		out.append_array(draft.get_children())
	return out
"""
	s.reload()
	return s


# ===========================================================================
# Visgroup CRUD tests
# ===========================================================================


func test_create_visgroup():
	sys.create_visgroup("walls")
	var names = sys.get_visgroup_names()
	assert_eq(names.size(), 1, "Should have 1 visgroup")
	assert_eq(names[0], "walls", "Name should be 'walls'")


func test_create_duplicate_visgroup_noop():
	sys.create_visgroup("walls")
	sys.create_visgroup("walls")
	assert_eq(sys.get_visgroup_names().size(), 1, "Duplicate create should not add second")


func test_create_empty_name_noop():
	sys.create_visgroup("")
	assert_eq(sys.get_visgroup_names().size(), 0, "Empty name should be rejected")


func test_remove_visgroup():
	sys.create_visgroup("walls")
	sys.remove_visgroup("walls")
	assert_eq(sys.get_visgroup_names().size(), 0, "Visgroup should be removed")


func test_remove_visgroup_clears_membership():
	var draft_parent = root.get_node("DraftBrushes")
	var b = _make_brush(draft_parent)
	sys.create_visgroup("walls")
	sys.add_to_visgroup(b, "walls")
	sys.remove_visgroup("walls")
	var vgs = b.get_meta("visgroups", PackedStringArray())
	assert_eq(vgs.size(), 0, "Membership should be cleared when visgroup deleted")


func test_rename_visgroup():
	sys.create_visgroup("walls")
	sys.rename_visgroup("walls", "detail")
	var names = sys.get_visgroup_names()
	assert_eq(names.size(), 1)
	assert_eq(names[0], "detail")


func test_rename_onto_an_existing_name_is_refused():
	var draft_parent = root.get_node("DraftBrushes")
	var b1 = _make_brush(draft_parent)
	var b2 = _make_brush(draft_parent)
	sys.create_visgroup("A", Color.RED)
	sys.create_visgroup("B", Color.BLUE)
	sys.add_to_visgroup(b1, "A")
	sys.add_to_visgroup(b2, "B")
	sys.set_visgroup_visible("B", false)

	assert_false(sys.rename_visgroup("A", "B"), "The name is taken, so the rename is refused")

	var names = sys.get_visgroup_names()
	assert_eq(names.size(), 2, "Both visgroups should survive")
	assert_true(names.has("A"), "A should still be there")
	assert_true(names.has("B"), "and so should B")
	assert_false(sys.is_visgroup_visible("B"), "B should still be hidden")
	assert_eq(sys.get_members_of("B").size(), 1, "and it should not have absorbed A's member")


func test_rename_reports_whether_it_happened():
	sys.create_visgroup("walls")

	assert_true(sys.rename_visgroup("walls", "detail"), "A rename that works says so")
	assert_false(sys.rename_visgroup("gone", "detail2"), "A missing source does not")
	assert_false(sys.rename_visgroup("detail", ""), "and nor does an empty name")


func test_rename_updates_membership():
	var draft_parent = root.get_node("DraftBrushes")
	var b = _make_brush(draft_parent)
	sys.create_visgroup("walls")
	sys.add_to_visgroup(b, "walls")
	sys.rename_visgroup("walls", "detail")
	var vgs: PackedStringArray = b.get_meta("visgroups", PackedStringArray())
	assert_true(vgs.has("detail"), "Membership should update to new name")
	assert_false(vgs.has("walls"), "Old name should be gone")


# ===========================================================================
# Visibility tests
# ===========================================================================


func test_default_visgroup_is_visible():
	sys.create_visgroup("walls")
	assert_true(sys.is_visgroup_visible("walls"))


func test_hide_visgroup_hides_members():
	var draft_parent = root.get_node("DraftBrushes")
	var b = _make_brush(draft_parent)
	sys.create_visgroup("walls")
	sys.add_to_visgroup(b, "walls")
	sys.set_visgroup_visible("walls", false)
	assert_false(b.visible, "Node should be hidden when its visgroup is hidden")


func test_show_visgroup_shows_members():
	var draft_parent = root.get_node("DraftBrushes")
	var b = _make_brush(draft_parent)
	sys.create_visgroup("walls")
	sys.add_to_visgroup(b, "walls")
	sys.set_visgroup_visible("walls", false)
	sys.set_visgroup_visible("walls", true)
	assert_true(b.visible, "Node should be visible when visgroup shown")


func test_any_hidden_visgroup_hides_node():
	var draft_parent = root.get_node("DraftBrushes")
	var b = _make_brush(draft_parent)
	sys.create_visgroup("walls")
	sys.create_visgroup("detail")
	sys.add_to_visgroup(b, "walls")
	sys.add_to_visgroup(b, "detail")
	sys.set_visgroup_visible("walls", true)
	sys.set_visgroup_visible("detail", false)
	assert_false(b.visible, "Node hidden if ANY visgroup is hidden")


func test_node_without_visgroup_stays_visible():
	var draft_parent = root.get_node("DraftBrushes")
	var b = _make_brush(draft_parent)
	sys.create_visgroup("walls")
	sys.set_visgroup_visible("walls", false)
	sys.refresh_visibility()
	assert_true(b.visible, "Node not in any visgroup should remain visible")


# ===========================================================================
# Membership tests
# ===========================================================================


func test_add_to_visgroup():
	var draft_parent = root.get_node("DraftBrushes")
	var b = _make_brush(draft_parent)
	sys.add_to_visgroup(b, "walls")
	var vgs = sys.get_visgroups_of(b)
	assert_eq(vgs.size(), 1)
	assert_eq(vgs[0], "walls")


func test_add_same_twice_no_duplicate():
	var draft_parent = root.get_node("DraftBrushes")
	var b = _make_brush(draft_parent)
	sys.add_to_visgroup(b, "walls")
	sys.add_to_visgroup(b, "walls")
	assert_eq(sys.get_visgroups_of(b).size(), 1, "Should not have duplicate membership")


func test_multiple_visgroup_membership():
	var draft_parent = root.get_node("DraftBrushes")
	var b = _make_brush(draft_parent)
	sys.add_to_visgroup(b, "walls")
	sys.add_to_visgroup(b, "detail")
	assert_eq(sys.get_visgroups_of(b).size(), 2)


func test_remove_from_visgroup():
	var draft_parent = root.get_node("DraftBrushes")
	var b = _make_brush(draft_parent)
	sys.add_to_visgroup(b, "walls")
	sys.remove_from_visgroup(b, "walls")
	assert_eq(sys.get_visgroups_of(b).size(), 0)


func test_get_members_of():
	var draft_parent = root.get_node("DraftBrushes")
	var b1 = _make_brush(draft_parent)
	var b2 = _make_brush(draft_parent)
	sys.add_to_visgroup(b1, "walls")
	sys.add_to_visgroup(b2, "walls")
	var members = sys.get_members_of("walls")
	assert_eq(members.size(), 2, "Both brushes should be members")


# ===========================================================================
# Serialization tests
# ===========================================================================


func test_capture_restore_visgroups_round_trip():
	sys.create_visgroup("walls", Color.RED)
	sys.create_visgroup("detail", Color.BLUE)
	sys.set_visgroup_visible("detail", false)
	var captured = sys.capture_visgroups()
	var sys2 = HFVisgroupSystem.new(root)
	sys2.restore_visgroups(captured)
	assert_eq(sys2.get_visgroup_names().size(), 2)
	assert_true(sys2.is_visgroup_visible("walls"))
	assert_false(sys2.is_visgroup_visible("detail"))


# ---------------------------------------------------------------------------
# Deleting a hidden visgroup must not strand its members (#316)
# ---------------------------------------------------------------------------


func test_deleting_a_hidden_visgroup_shows_its_members_again():
	var brush = _make_brush(root.get_node("DraftBrushes"))
	sys.create_visgroup("V1")
	sys.add_to_visgroup(brush, "V1")
	sys.set_visgroup_visible("V1", false)
	assert_false(brush.visible, "Hiding the visgroup should hide the member")
	sys.remove_visgroup("V1")
	assert_true(brush.visible, "Deleting the visgroup should give the member back")


func test_removing_a_node_from_a_hidden_visgroup_shows_it_again():
	var brush = _make_brush(root.get_node("DraftBrushes"))
	sys.create_visgroup("V1")
	sys.add_to_visgroup(brush, "V1")
	sys.set_visgroup_visible("V1", false)
	assert_false(brush.visible, "Hiding the visgroup should hide the member")
	sys.remove_from_visgroup(brush, "V1")
	sys.refresh_visibility()
	assert_true(brush.visible, "A node in no visgroup is a node nothing is hiding")


func test_a_node_still_in_a_hidden_visgroup_stays_hidden():
	# The guard that the fix does not simply show everything.
	var brush = _make_brush(root.get_node("DraftBrushes"))
	sys.create_visgroup("V1")
	sys.create_visgroup("V2")
	sys.add_to_visgroup(brush, "V1")
	sys.add_to_visgroup(brush, "V2")
	sys.set_visgroup_visible("V1", false)
	assert_false(brush.visible, "Hidden by V1")
	sys.remove_visgroup("V2")
	assert_false(brush.visible, "V1 is still hiding it")
