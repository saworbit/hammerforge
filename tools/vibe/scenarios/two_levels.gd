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
## five minute timer. Both are per-node, so every level in a project started life
## pointing at the same file (#655). The stored default is still one string --
## `resolved_hflevel_path()` is what turns it into a file now, so that is the
## surface these read. This measures what a second level costs the first, and
## what else two roots in one tree share.


func id() -> String:
	return "two-levels"


func summary() -> String:
	return "what a second level in the same project does to the first"


func run() -> void:
	await _the_default_autosave_path()
	await _the_second_level_overwrites_the_first()
	await _two_roots_in_one_scene()
	await _what_scene_source_path_knows()


## A level that has been saved is named after its scene; one that has not is
## named after the id it minted for itself. Neither may share a file with
## another level, because autosave is on by default and nothing asks first.
func _the_default_autosave_path() -> void:
	note("-- the path each level starts with --")
	var a: Node3D = await _level_from_scene("LevelA", "res://vibe_levels/e1m1.tscn")
	var b: Node3D = await _level_from_scene("LevelB", "res://vibe_levels/e1m2.tscn")
	note("both still store the same default", a.hflevel_autosave_path)
	note("LevelA resolves to", a.resolved_hflevel_path())
	note("LevelB resolves to", b.resolved_hflevel_path())
	note("autosave enabled by default", a.hflevel_autosave_enabled)
	note("autosave interval, minutes", a.hflevel_autosave_minutes)
	if a.resolved_hflevel_path() == b.resolved_hflevel_path():
		flag(
			"two saved levels resolve to one autosave file",
			"both at '%s'" % a.resolved_hflevel_path()
		)

	# Same file name in two directories, which a project gets to have.
	var c: Node3D = await _level_from_scene("LevelC", "res://vibe_levels/test.tscn")
	var d: Node3D = await _level_from_scene("LevelD", "res://vibe_proto/test.tscn")
	note("LevelC resolves to", c.resolved_hflevel_path())
	note("LevelD resolves to", d.resolved_hflevel_path())
	if c.resolved_hflevel_path() == d.resolved_hflevel_path():
		flag(
			"two scenes with the same file name resolve to one autosave file",
			"both at '%s'" % c.resolved_hflevel_path()
		)

	# A scene that has never been saved is the case where the autosave is the
	# only copy, so it is the one that matters most.
	var e: Node3D = await fresh_root("LevelE")
	var f: Node3D = await fresh_root("LevelF")
	note("an unsaved level resolves to", e.resolved_hflevel_path())
	note("another unsaved level resolves to", f.resolved_hflevel_path())
	if e.resolved_hflevel_path() == f.resolved_hflevel_path():
		flag(
			"two unsaved levels resolve to one autosave file",
			"both at '%s', and an unsaved level has no other copy" % e.resolved_hflevel_path()
		)


## A root that answers `scene_source_path()` the way one opened from a scene
## does. `scene_source_path()` walks up to the topmost node with no owner, and a
## root parented straight to the tree is already that node.
func _level_from_scene(node_name: String, scene: String) -> Node3D:
	var root: Node3D = await fresh_root(node_name)
	root.scene_file_path = scene
	return root


## Not a theory about the path: two levels pointed at one file by hand, then the
## first one asked to load its own work back.
##
## Pointing two levels at one path is a thing a mapper is allowed to do, so the
## file's own record of the scene it came from is the guard: an autosave whose
## target names a different level is refused. A manual Save Level is not, because
## that one was asked for.
func _the_second_level_overwrites_the_first() -> void:
	note("-- two levels pointed at one file by hand, first one reloaded --")
	var shared := "user://vibe_two_levels_default.hflevel"

	var a: Node3D = await _level_from_scene("LevelA", "res://vibe_levels/e1m1.tscn")
	a.hflevel_autosave_path = shared
	for i in 4:
		box(a, Vector3(128, 128, 128), Vector3(i * 256, 0, 0))
		await frame()
	note("LevelA brushes", _count(a))
	a.save_hflevel(shared)
	if not await HFVibe.settle_save(_tree, a):
		flag("LevelA's save never finished")
		return

	var b: Node3D = await _level_from_scene("LevelB", "res://vibe_levels/e1m2.tscn")
	b.hflevel_autosave_path = shared
	box(b, Vector3(64, 64, 64), Vector3.ZERO)
	await frame()
	note("LevelB brushes", _count(b))
	var refused: int = b.save_hflevel(shared, true, true)
	note("LevelB's autosave onto LevelA's file returned", refused)
	if refused == OK:
		await HFVibe.settle_save(_tree, b)

	a.clear_brushes()
	await frame()
	var loaded = a.load_hflevel(shared)
	await frame()
	note("LevelA reloaded its own path", loaded)
	note("LevelA brushes after the reload", _count(a))
	if _count(a) == 1:
		flag(
			"a second level's autosave replaced the first level's saved work",
			(
				"LevelA saved four brushes and got one back: the one LevelB autosaved "
				+ "over the top, onto a file that records LevelA's scene"
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
