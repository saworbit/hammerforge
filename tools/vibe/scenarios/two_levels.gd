@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## What a project with more than one level does to itself.
##
## Every map after the first one is a second `LevelRoot`, in a second scene or
## beside the first. A mapper who has built `e1m1.tscn` opens a new scene and
## builds `e1m2.tscn`, and has every right to assume the two do not touch.
##
## `hflevel_autosave_path` is an `@export String` with a literal default, and
## `hflevel_autosave_enabled` is an `@export bool` that defaults to true on a
## five minute timer. Both are per-node, so every level in a project starts life
## pointing at the same file. This measures what that costs, and what else two
## roots in one tree share.


func id() -> String:
	return "two-levels"


func summary() -> String:
	return "what a second level in the same project does to the first"


func run() -> void:
	await _the_default_autosave_path()
	await _the_second_level_overwrites_the_first()
	await _two_roots_in_one_scene()
	await _what_scene_source_path_knows()


func _the_default_autosave_path() -> void:
	note("-- the path each level starts with --")
	var a: Node3D = await fresh_root("LevelA")
	var b: Node3D = await fresh_root("LevelB")
	note("LevelA autosave path", a.hflevel_autosave_path)
	note("LevelB autosave path", b.hflevel_autosave_path)
	note("autosave enabled by default", a.hflevel_autosave_enabled)
	note("autosave interval, minutes", a.hflevel_autosave_minutes)
	if str(a.hflevel_autosave_path) == str(b.hflevel_autosave_path):
		known(
			655,
			"every level in a project autosaves to the same file",
			(
				(
					"`hflevel_autosave_path` defaults to the literal '%s' and the only thing "
					+ "that ever changes it is a mapper picking a file by hand "
					+ "(dock_file_handler.on_autosave_path_selected). Autosave is on by "
					+ "default on a %s minute timer, so the second level a project has "
					+ "silently takes the first one's file"
				)
				% [a.hflevel_autosave_path, a.hflevel_autosave_minutes]
			)
		)


## Not a theory about the path: two levels, both saved, then the first one asked
## to load its own file back.
func _the_second_level_overwrites_the_first() -> void:
	note("-- two levels, both saved to the default path, first one reloaded --")
	var shared := "user://vibe_two_levels_default.hflevel"

	var a: Node3D = await fresh_root("LevelA")
	a.hflevel_autosave_path = shared
	for i in 4:
		box(a, Vector3(128, 128, 128), Vector3(i * 256, 0, 0))
		await frame()
	note("LevelA brushes", _count(a))
	a.save_hflevel(shared)
	if not await HFVibe.settle_save(_tree, a):
		flag("LevelA's save never finished")
		return

	var b: Node3D = await fresh_root("LevelB")
	b.hflevel_autosave_path = shared
	box(b, Vector3(64, 64, 64), Vector3.ZERO)
	await frame()
	note("LevelB brushes", _count(b))
	b.save_hflevel(shared, true, true)
	if not await HFVibe.settle_save(_tree, b):
		flag("LevelB's save never finished")
		return

	a.clear_brushes()
	await frame()
	var loaded = a.load_hflevel(shared)
	await frame()
	note("LevelA reloaded its own path", loaded)
	note("LevelA brushes after the reload", _count(a))
	if _count(a) == 1:
		known(
			655,
			"a second level's autosave replaces the first level's saved work",
			(
				"LevelA saved four brushes to its default path and got one back: the "
				+ "one LevelB autosaved over the top. No prompt, no backup of the "
				+ "displaced file under a different name, and nothing in the dock "
				+ "shows which level a path belongs to"
			)
		)
	elif _count(a) != 4:
		flag("LevelA came back with %s brushes, having saved 4" % _count(a))


## Two roots in one scene, which is how a mapper builds a level in sections or
## keeps a scratch area beside the real one.
func _two_roots_in_one_scene() -> void:
	note("-- two roots side by side in one tree --")
	var a: Node3D = await fresh_root("SectionA")
	var b: Node3D = await fresh_root("SectionB")
	var a_brush = box(a, Vector3(128, 128, 128), Vector3.ZERO)
	await frame()
	var b_brush = box(b, Vector3(128, 128, 128), Vector3(512, 0, 0))
	await frame()
	note("A holds %s, B holds %s" % [_count(a), _count(b)])

	note("A's brush id", a_brush.brush_id)
	note("B's brush id", b_brush.brush_id)
	if str(a_brush.brush_id) == str(b_brush.brush_id):
		flag("two roots mint the same brush id", a_brush.brush_id)

	# Does one root's lookup reach the other's brush?
	var crossed = a.find_brush_by_id(b_brush.brush_id)
	note("A.find_brush_by_id(B's id)", "found" if crossed else "null")
	if crossed:
		flag("one level resolves the other level's brush id", str(b_brush.brush_id))

	# And does one root's validation count the other's level?
	var report_a: Dictionary = a.validate_level()
	note("A.validate_level()", report_a.get("summary", report_a))
	note("A health", a.get_level_health())
	note("B health", b.get_level_health())

	# Clearing one must not touch the other.
	a.clear_brushes()
	await frame()
	note("after A.clear_brushes(): A %s, B %s" % [_count(a), _count(b)])
	if _count(b) != 1:
		flag("clearing one level emptied the other", "B holds %s" % _count(b))

	# Deleting a whole root must not take the other's subsystems with it.
	a.get_parent().remove_child(a)
	a.queue_free()
	await frame()
	await frame()
	var still = box(b, Vector3(64, 64, 64), Vector3(1024, 0, 0))
	await frame()
	note("B still builds after A was freed", still != null and _count(b) == 2)
	if still == null or _count(b) != 2:
		flag("freeing one level root breaks the other", "B holds %s" % _count(b))


## The level already knows which scene it is in. Nothing uses it to name a file.
func _what_scene_source_path_knows() -> void:
	note("-- what the level can already work out about where it lives --")
	var root: Node3D = await fresh_root("Named")
	note("scene_source_path()", "'%s'" % root.scene_source_path())
	note("has_hflevel_path()", root.has_hflevel_path())
	note("scene_contents_description()", root.scene_contents_description())
	var freshness: Dictionary = root.check_hflevel_freshness()
	note("check_hflevel_freshness()", freshness)
	var uses := FileAccess.get_file_as_string("res://addons/hammerforge/level_root.gd").count(
		"scene_source_path()"
	)
	note("call sites of scene_source_path() in level_root.gd", uses)


func _count(root: Node3D) -> int:
	var out: Array = []
	_collect(root, root, out)
	return out.size()


func _collect(root: Node3D, node: Node, out: Array) -> void:
	for child in node.get_children():
		if root.is_brush_node(child):
			out.append(child)
		_collect(root, child, out)
