@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Things a level depends on, taken away while it is not looking.
##
## A level points at files it does not own: material `.tres` resources, the
## `.hfprefab` a linked instance was made from, `entities.json`, the heightmap
## a terrain layer was imported from, the `.hflevel` a `BAKE_ONLY` scene keeps
## its brushes in. Any of them can move: a mapper reorganises `res://`, a
## teammate pulls a branch that renames a folder, a prefab is deleted from the
## library panel while an instance of it is in the level.
##
## `check_missing_dependencies()` exists and `validate_level()` reports what it
## returns, so the question is which of these it notices, and what the level
## does about the ones it does not.
##
## `definitions` covers a malformed `entities.json`; this covers one that is not
## there at all, and the rest of the family.

const HFPrefabType = preload("res://addons/hammerforge/hf_prefab.gd")
const HFPrefabSystemType = preload("res://addons/hammerforge/systems/hf_prefab_system.gd")

var _written: Array[String] = []


func id() -> String:
	return "missing-files"


func summary() -> String:
	return "what a level does when a file it points at is taken away"


func run() -> void:
	await _a_material_that_is_gone()
	await _a_prefab_an_instance_points_at()
	await _no_entity_definitions_at_all()
	await _the_hflevel_a_bake_only_scene_needs()
	_clean_up()


func _clean_up() -> void:
	var removed := 0
	for path in _written:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
			removed += 1
	note("scenario files removed", removed)


## A material a level's palette points at, deleted from disk.
func _a_material_that_is_gone() -> void:
	note("-- a palette material deleted from under the level --")
	var root: Node3D = await fresh_root()
	root.auto_spawn_player = false
	var mat_path := "user://vibe_missing_material.tres"
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.2, 0.2)
	ResourceSaver.save(mat, mat_path)
	_written.append(mat_path)
	var loaded = ResourceLoader.load(mat_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	note("material saved and reloaded", loaded != null)
	root.add_material_to_palette(loaded)
	await frame()
	note("palette", root.get_material_names())

	var brush = box(root, Vector3(2, 2, 2), Vector3.ZERO)
	await frame()
	root.assign_material_to_whole_brushes(0, [str(brush.brush_id)])
	await frame()
	note("faces on slot 0", _faces_on(root, 0))

	# Save the level, take the material away, load the level back.
	var level_path := "user://vibe_missing_material.hflevel"
	root.hflevel_autosave_path = level_path
	root.save_hflevel(level_path)
	if not await HFVibe.settle_save(_tree, root):
		flag("the save never finished")
		return
	_written.append(level_path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(mat_path))
	note("material still on disk", FileAccess.file_exists(mat_path))

	var reopened: Node3D = await fresh_root("Reopened")
	reopened.auto_spawn_player = false
	reopened.hflevel_autosave_path = level_path
	var ok = reopened.load_hflevel(level_path)
	await frame()
	note("the level loaded", ok)
	note("palette after the load", reopened.get_material_names())
	note("palette slots", reopened.get_materials().size())
	note(
		"slot 0 resolves to a material",
		reopened.get_materials()[0] if reopened.get_materials().size() > 0 else null
	)
	note("faces still pointing at slot 0", _faces_on(reopened, 0))
	note("check_missing_dependencies()", reopened.check_missing_dependencies())
	var report: Dictionary = reopened.validate_level()
	note("validate_level()", report)
	var mentioned := false
	for entry in report.get("issues", []):
		if str(entry).to_lower().find("depend") >= 0 or str(entry).to_lower().find("material") >= 0:
			mentioned = true
	if not mentioned:
		flag(
			"a level whose material file is gone reports nothing",
			(
				(
					"the palette slot the faces point at is %s and `validate_level()` "
					+ "returns %s issues. `check_missing_dependencies()` returned %s. The "
					+ "brush renders with whatever the slot fell back to and nothing names "
					+ "the file that went"
				)
				% [
					(
						str(reopened.get_materials()[0])
						if reopened.get_materials().size() > 0
						else "gone"
					),
					(report.get("issues", []) as Array).size(),
					str(reopened.check_missing_dependencies()),
				]
			)
		)


## A linked prefab instance whose source file is deleted from the library.
func _a_prefab_an_instance_points_at() -> void:
	note("-- the .hfprefab a linked instance was made from, deleted --")
	var root: Node3D = await fresh_root()
	root.auto_spawn_player = false
	var brush = box(root, Vector3(1, 2, 1), Vector3.ZERO)
	await frame()
	var written: String = root.prefab_system.quick_save_prefab([brush], [], "vibe_gone", true)
	note("prefab written to", written)
	if written == "":
		note("the prefab could not be written, so there is nothing to delete")
		return
	_written.append(written)
	var instances: Dictionary = root.prefab_system.get_all_instances()
	note("instances registered", instances.size())
	for key in instances.keys():
		note(
			"  instance",
			(
				"%s -> %s"
				% [key, instances[key].source_path if "source_path" in instances[key] else "?"]
			)
		)

	DirAccess.remove_absolute(ProjectSettings.globalize_path(written))
	note("prefab still on disk", FileAccess.file_exists(written))

	note("check_missing_dependencies()", root.check_missing_dependencies())
	var report: Dictionary = root.validate_level()
	note("validate_level()", report)

	# The operations the dock offers on a linked instance, against a source that
	# is not there.
	var lied: Array[String] = []
	for key in instances.keys():
		var id := str(key)
		note("cycle_variant on the orphan", "'%s'" % root.prefab_system.cycle_variant(id))
		var pushed = root.prefab_system.push_instance_to_source(id)
		var recreated := FileAccess.file_exists(written)
		note(
			"push_instance_to_source on the orphan",
			"returned %s, source file exists afterwards: %s" % [pushed, recreated]
		)
		if pushed and not recreated:
			lied.append("push_instance_to_source")
		if recreated:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(written))
		note("compute_instance_diff on the orphan", root.prefab_system.compute_instance_diff(id))
	var propagated = root.prefab_system.propagate_from_source(written)
	note(
		"propagate_from_source for a file that is gone",
		"reported %s instance(s) updated" % propagated
	)
	if int(propagated) > 0:
		lied.append("propagate_from_source")
	if not lied.is_empty():
		flag(
			"prefab operations report success against a source file that is not there",
			(
				(
					"%s on an instance whose `.hfprefab` has been deleted return success "
					+ "without the file existing before or after. Push to Source is the "
					+ "operation a mapper uses to save changes back to the library, so a "
					+ "success it did not earn is the shape that loses work"
				)
				% str(lied)
			)
		)
	note("brushes still in the level", root.get_live_brush_count())
	var mentions := false
	for entry in report.get("issues", []):
		if str(entry).to_lower().find("prefab") >= 0:
			mentions = true
	if not mentions and instances.size() > 0:
		known(
			669,
			"a linked prefab instance whose source is gone is not reported",
			(
				(
					"%s instance(s) point at %s, the file is not there, and both "
					+ "`check_missing_dependencies()` and `validate_level()` are quiet. The "
					+ "dock still offers Cycle Variant, Push to Source and Propagate on it, "
					+ "and #615 already covers the ones that cannot be reached at all -- "
					+ "this is the ones that can, aimed at nothing"
				)
				% [instances.size(), written]
			)
		)


## `entity_definitions_path` pointed at a file that is not there.
func _no_entity_definitions_at_all() -> void:
	note("-- entities.json missing --")
	var root: Node3D = await fresh_root()
	root.auto_spawn_player = false
	root.entity_definitions_path = "user://vibe_no_such_entities.json"
	root._load_entity_definitions()
	await frame()
	var defs: Dictionary = root.get_entity_definitions()
	note("definitions loaded from a path with no file", defs.keys())
	note("get_entity_definition('light_point')", root.get_entity_definition("light_point"))
	note("check_missing_dependencies()", root.check_missing_dependencies())
	note("validate_level()", root.validate_level())
	if defs.is_empty():
		note(
			"an empty definition set",
			(
				"placing an entity, the Objects tab and the brush-entity dropdown all "
				+ "have nothing to offer; the dropdown has documented built-in fallbacks"
			)
		)


## `SceneContents.BAKE_ONLY` keeps the brushes in the `.hflevel` only (#645), so
## losing that file loses the level. `_load_hflevel_for_bake_only_scene()` says
## so out loud -- this checks it still does when the path is simply wrong.
func _the_hflevel_a_bake_only_scene_needs() -> void:
	note("-- a BAKE_ONLY level whose .hflevel is not there --")
	var root: Node3D = await fresh_root()
	root.auto_spawn_player = false
	box(root, Vector3(2, 2, 2), Vector3.ZERO)
	await frame()
	note("scene_keeps_brushes() with the default contents", root.scene_keeps_brushes())
	root.hflevel_autosave_path = "user://vibe_absent.hflevel"
	if "scene_contents" in root:
		root.scene_contents = 1  # BAKE_ONLY
	note("scene_contents set to BAKE_ONLY", root.get("scene_contents"))
	note("scene_keeps_brushes() now", root.scene_keeps_brushes())
	note("scene_contents_description()", root.scene_contents_description())
	var messages: Array = []
	if root.has_signal("user_message"):
		root.user_message.connect(func(text, level): messages.append("%s (%s)" % [text, level]))
	root.clear_brushes()
	await frame()
	root._load_hflevel_for_bake_only_scene()
	await frame()
	note("messages emitted", messages)
	note("brushes after the attempted load", root.get_live_brush_count())
	if messages.is_empty():
		flag(
			"a BAKE_ONLY level whose .hflevel is missing says nothing",
			(
				"`_load_hflevel_for_bake_only_scene()` is the one place that can tell a "
				+ "mapper their brushes are in a file that is not there, and the level "
				+ "came up empty with no `user_message`"
			)
		)
	note("check_missing_dependencies()", root.check_missing_dependencies())
	note("check_hflevel_freshness()", root.check_hflevel_freshness())


func _faces_on(root: Node3D, slot: int) -> int:
	var n := 0
	for child in root.draft_brushes_node.get_children():
		if not root.is_brush_node(child):
			continue
		for face in child.get("faces"):
			if face and int(face.material_idx) == slot:
				n += 1
	return n
