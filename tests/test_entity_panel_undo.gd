extends GutTest

## An edit in the Entity panel is one undo step (#931).
##
## The panel wrote the field straight onto the entity. Ctrl+Z after an edit then
## undid whatever came before it, and straight after creating an entity that was
## the creation, so the entity vanished and the edit stayed.
##
## An `EditorUndoRedoManager` cannot be built outside the editor, so the step is
## registered the way `HFUndoHelper.commit()` registers it, against the stand-in
## `test_undo_collation.gd` carries, and replayed against a real LevelRoot.

const CollationTests = preload("res://tests/test_undo_collation.gd")
const DraftEntity = preload("res://addons/hammerforge/draft_entity.gd")
const HFUndoHelper = preload("res://addons/hammerforge/undo_helper.gd")
const HFEntityPropUtils = preload("res://addons/hammerforge/ui/hf_entity_prop_utils.gd")

const HANDLER := "res://addons/hammerforge/dock_entity_handler.gd"

var root: LevelRoot


func before_each() -> void:
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)


func after_each() -> void:
	root = null


## What `commit_entity_property()` registers: a scoped snapshot before, and a
## redo made of the snapshot after.
func _commit_edit(fake, entity: Node3D, prop: String, value: Variant) -> void:
	var scope_ids: Array = []
	var scope_paths: Array = []
	if HFEntityPropUtils.is_brush_entity(entity):
		scope_ids = [str(entity.get("brush_id"))]
	else:
		scope_paths = [root.get_path_to(entity)]
	var before: Dictionary = root.capture_brush_scope(scope_ids, scope_paths)
	assert_false(before.is_empty(), "the entity can be a scope of its own")
	HFUndoHelper.register_action(
		fake,
		root,
		"Set %s" % prop,
		0,
		"set_entity_property",
		[entity, prop, value],
		before,
		false,
		true,
		scope_ids,
		scope_paths
	)


func _point_entity() -> DraftEntity:
	var entity := DraftEntity.new()
	entity.name = "Light"
	entity.entity_type = "light_point"
	entity.set_meta("is_entity", true)
	root.add_entity(entity)
	entity.entity_data["targetname"] = "lamp_a"
	return entity


func _only_entity() -> DraftEntity:
	var children := root.entities_node.get_children()
	return children[0] if children.size() == 1 else null


func test_undo_after_an_edit_puts_the_old_value_back_and_keeps_the_entity():
	var fake = CollationTests.FakeUndoRedo.new()
	var entity := _point_entity()

	_commit_edit(fake, entity, "targetname", "lamp_b")
	assert_eq(entity.entity_data["targetname"], "lamp_b", "the edit applied")

	fake.undo()
	var after_undo := _only_entity()
	assert_not_null(after_undo, "the entity is still there; before, Ctrl+Z took it away")
	if after_undo:
		assert_eq(after_undo.entity_data.get("targetname"), "lamp_a")

	fake.redo()
	var after_redo := _only_entity()
	assert_not_null(after_redo)
	if after_redo:
		assert_eq(after_redo.entity_data.get("targetname"), "lamp_b", "redo puts the edit back")


func test_a_brush_entity_field_undoes_too():
	var fake = CollationTests.FakeUndoRedo.new()
	var brush: Node3D = root.create_brush_from_info(
		{"size": Vector3(2, 4, 2), "center": Vector3.ZERO, "brush_id": "door_leaf"}
	)
	root.tie_brushes_to_entity(["door_leaf"], "func_door", "door_1")
	HFEntityPropUtils.set_entity_property(brush, "speed", 100)
	assert_true(HFEntityPropUtils.is_brush_entity(brush))

	_commit_edit(fake, brush, "speed", 250)
	assert_eq(HFEntityPropUtils.get_entity_data(brush).get("speed"), 250)

	fake.undo()
	var restored: Node3D = root.draft_brushes_node.get_child(0)
	assert_eq(HFEntityPropUtils.get_entity_data(restored).get("speed"), 100)


func test_every_panel_edit_goes_through_the_undo_step():
	var source := FileAccess.get_file_as_string(HANDLER)
	for function_name in [
		"on_entity_prop_changed", "on_entity_prop_enum_changed", "on_entity_prop_vec3_changed"
	]:
		var start := source.find("\nstatic func %s(" % function_name)
		assert_gt(start, 0, "%s exists" % function_name)
		var body := source.substr(start + 1)
		body = body.substr(0, body.find("\n\n\n"))
		assert_true(body.contains("commit_entity_property("), function_name)
		assert_false(
			body.contains("HFEntityPropUtils.set_entity_"),
			"%s must not write the field outside the undo step" % function_name
		)
	var commit_start := source.find("\nstatic func commit_entity_property(")
	var commit := source.substr(commit_start + 1)
	commit = commit.substr(0, commit.find("\n\n\n"))
	assert_true(commit.contains("HFUndoHelper.commit("))
	assert_true(commit.contains('"set_entity_property"'))
