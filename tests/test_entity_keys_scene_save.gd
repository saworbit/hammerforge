extends GutTest

## A point entity's properties saved with the scene, every one of them (#1855).
##
## The scene used to get an entity's properties only through the `data/` list
## `_get_property_list()` builds from the class's schema, so a key the class did
## not name, and every key of a class with no definition, was never written.
## `entity_data` is saved whole now, and the `data/` list is the inspector's.
##
## These write the scene to disk and load it with the cache ignored.

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")

const PATH := "user://test_entity_keys_scene_save.tscn"
const OLD_PATH := "user://test_entity_keys_old_scene.tscn"


func after_each():
	for path in [PATH, OLD_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _fresh_root() -> LevelRoot:
	var root := LevelRootType.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	root.owner = self
	return root


func _own(root: Node) -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			child.owner = root
			stack.append(child)


func _save_and_reopen(root: LevelRoot) -> LevelRoot:
	_own(root)
	var packed := PackedScene.new()
	assert_eq(packed.pack(root), OK, "the level packs")
	assert_eq(ResourceSaver.save(packed, PATH), OK, "the scene saves")
	var loaded := (
		ResourceLoader.load(PATH, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	)
	var copy := loaded.instantiate() as LevelRoot
	copy.hflevel_autosave_enabled = false
	add_child_autoqfree(copy)
	return copy


func _entity(root: LevelRoot, entity_type: String, data: Dictionary) -> DraftEntity:
	return (
		root
		. entity_system
		. restore_entity_from_info(
			{
				"name": entity_type,
				"entity_type": entity_type,
				"properties": data,
				"transform": Transform3D.IDENTITY,
			}
		)
	)


func _reopened(copy: LevelRoot, entity_name: String) -> DraftEntity:
	return copy.entities_node.get_node_or_null(entity_name) as DraftEntity


func test_a_class_with_no_definition_keeps_every_property():
	var root := _fresh_root()
	assert_true(root.get_entity_definition("lamp_post").is_empty(), "fixture: no such class")
	var lamp := _entity(root, "lamp_post", {"brightness": 300, "_color": "255 200 120"})

	var copy := _save_and_reopen(root)
	var reopened := _reopened(copy, lamp.name)
	assert_not_null(reopened, "the entity comes back")
	if reopened == null:
		return
	assert_eq(reopened.entity_data, {"brightness": 300, "_color": "255 200 120"}, "with both")
	assert_eq(typeof(reopened.entity_data.get("brightness")), TYPE_INT, "an int still")


func test_a_defined_class_keeps_a_key_it_does_not_name():
	var root := _fresh_root()
	var schema: Array = root.get_entity_definition("light_point").get("properties", [])
	assert_false(schema.is_empty(), "fixture: light_point has a schema")
	var light := _entity(root, "light_point", {"energy": 2.5, "style": "5"})

	var copy := _save_and_reopen(root)
	var reopened := _reopened(copy, light.name)
	if reopened == null:
		fail_test("the entity came back")
		return
	assert_eq(reopened.entity_data.get("style"), "5", "the key a .map import brought")
	assert_almost_eq(float(reopened.entity_data.get("energy", 0.0)), 2.5, 0.001, "and its own")


## Each property once: `entity_data` whole, not each key again as `data/`.
func test_the_scene_writes_each_property_once():
	var root := _fresh_root()
	_entity(root, "light_point", {"energy": 2.5})
	_own(root)
	var packed := PackedScene.new()
	assert_eq(packed.pack(root), OK)
	var state := packed.get_state()
	var names: PackedStringArray = []
	for node_index in state.get_node_count():
		if state.get_node_name(node_index).begins_with("light_point"):
			for i in state.get_node_property_count(node_index):
				names.append(state.get_node_property_name(node_index, i))
	assert_has(names, "entity_data", "the properties, whole")
	for property_name in names:
		assert_false(property_name.begins_with("data/"), "%s is written twice" % property_name)


## A scene saved before the change wrote the `data/` list. It still loads.
func test_a_scene_from_before_still_loads_its_data_properties():
	var text := (
		"[gd_scene format=3]\n\n"
		+ '[ext_resource type="Script" path="res://addons/hammerforge/draft_entity.gd" id="1"]\n\n'
		+ '[node name="Old" type="Node3D"]\n'
		+ 'script = ExtResource("1")\n'
		+ 'entity_type = "light_point"\n'
		+ "data/energy = 4.0\n"
	)
	var file := FileAccess.open(OLD_PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	var loaded := (
		ResourceLoader.load(OLD_PATH, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	)
	assert_not_null(loaded, "the old scene reads")
	if loaded == null:
		return
	var entity := loaded.instantiate() as DraftEntity
	assert_almost_eq(float(entity.entity_data.get("energy", 0.0)), 4.0, 0.001)
	entity.free()
