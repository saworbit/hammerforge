extends SceneTree

## Saves a release's level, with that release's build (#1640).
##
## Run in a checkout of the release tag, after `tools/build_reference_map.gd` has
## written the reference map with that build, with this file and
## `level_census.gd` copied into its `tests/levels/`:
##
##     godot --headless -s res://tests/levels/save_release_level.gd --path . -- --out=<folder>
##
## It loads the map the build just wrote, sets a cordon round it (and a second
## where the build keeps more than one), and leaves three files in the folder,
## all written by that build: `level.hflevel`, `level.tscn` (the scene with the
## level in it, as that build saves one) and `expected.json` (what
## `level_census.gd` counts in it). Copy the folder to
## `tests/levels/<version>/` in the current checkout.

const Census = preload("res://tests/levels/level_census.gd")
const MAP := "res://addons/hammerforge/data/reference_map.hflevel"


func _init() -> void:
	_run()


func _run() -> void:
	var out := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	if out == "":
		printerr("--out=<folder> is required")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out)
	var level: Node3D = load("res://addons/hammerforge/level_root.gd").new()
	level.name = "ReleaseLevel"
	level.set("auto_spawn_player", false)
	level.set("hflevel_autosave_enabled", false)
	set_edited_scene_root(level)
	get_root().add_child(level)
	await process_frame
	if not level.load_hflevel(MAP):
		printerr("the build could not load its own reference map")
		quit(1)
		return
	for _i in 3:
		await process_frame
	# A cordon round the map, and a second one where the build has room for more,
	# so a loader that drops them is caught: the map itself sets none.
	level.set("cordon_enabled", true)
	level.set("cordon_aabb", AABB(Vector3(-20, -2, -9), Vector3(40, 8, 18)))
	if level.get("cordon_extra_aabbs") is Array:
		var extra: Array[AABB] = [AABB(Vector3(30, 0, -2), Vector3(4, 4, 4))]
		level.set("cordon_extra_aabbs", extra)
	var saved_level: int = level.save_hflevel(out.path_join("level.hflevel"), true)
	if saved_level != OK or not await _settle_save(level):
		printerr("could not save the level: %s" % error_string(saved_level))
	var census := Census.of(level)
	var config := ConfigFile.new()
	config.load("res://addons/hammerforge/plugin.cfg")
	var record := {
		"release": str(config.get_value("plugin", "version", "?")),
		"godot": Engine.get_version_info().get("string", ""),
		"census": census,
	}
	var file := FileAccess.open(out.path_join("expected.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(record, "\t", true) + "\n")
	file.close()
	var packed := PackedScene.new()
	var packed_ok := packed.pack(level)
	if packed_ok == OK:
		var saved := ResourceSaver.save(packed, out.path_join("level.tscn"))
		if saved != OK:
			printerr("could not save the scene: %s" % error_string(saved))
	else:
		printerr("could not pack the scene: %s" % error_string(packed_ok))
	print("saved %s: %d brushes" % [record["release"], int(census.get("brushes", 0))])
	level.queue_free()
	await process_frame
	quit()


## Wait for the threaded write to finish, as the reference map builder does.
func _settle_save(level: Node) -> bool:
	var files = level.get("file_system")
	if files == null:
		return false
	for _i in range(600):
		if level.has_method("_process_hflevel_saves"):
			level._process_hflevel_saves()
		if not files.get("_hflevel_thread"):
			return true
		await process_frame
	return false
