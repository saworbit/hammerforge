@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Export Settings and Import Settings, against each other and against the level.
##
## The Test tab writes a `.hfsettings` file of the dock's own numbers and reads
## one back. It is the file a mapper mails to somebody else, or keeps between
## projects, so it is also the file that arrives hand-edited, truncated, or
## written by an older build. Nothing on the way in checks a single value --
## `_apply_editor_settings()` takes the dictionary as it comes -- which is the
## exposure `hf_user_prefs.gd` was given a validator for in #423.
##
## Two questions: does a value survive the round trip onto the level, and what
## does a value the dock would never have written do when it arrives.

const DockScene = preload("res://addons/hammerforge/dock.tscn")


func id() -> String:
	return "dock-settings"


func summary() -> String:
	return "what an exported settings file carries back onto the level, and what a hand-edited one does"


func run() -> void:
	await _the_round_trip()
	await _values_the_dock_would_never_write()


func _dock(root: Node3D) -> Node:
	var dock = DockScene.instantiate()
	_tree.get_root().add_child(dock)
	await frame()
	dock.level_root = root
	return dock


func _the_round_trip() -> void:
	var root: Node3D = await fresh_root("SettingsLevel")
	var dock = await _dock(root)
	await frame()

	# A mapper sets up their bake the way they like it and exports.
	dock.bake_navmesh.button_pressed = true
	dock.bake_lightmap_texel.value = 0.25
	if dock.bake_connector_mode_opt:
		dock.bake_connector_mode_opt.select(2)  # Auto
		dock.bake_connector_mode_opt.item_selected.emit(2)
	await frame()
	var exported: Dictionary = dock._collect_editor_settings()
	note("exported keys", exported.keys())
	note("exported connector mode", exported.get("bake", {}).get("connector_mode", null))
	note("root bake_connector_mode before import", root.get("bake_connector_mode"))

	# The same file opened on a second level, which is what Import Settings is
	# for. Everything starts at the defaults.
	var other: Node3D = await fresh_root("SettingsLevelB")
	var other_dock = await _dock(other)
	await frame()
	note("second level bake_connector_mode at rest", other.get("bake_connector_mode"))
	note("second level bake_navmesh at rest", other.get("bake_navmesh"))
	other_dock._apply_editor_settings(exported)
	await frame()
	note("after import: dropdown shows", other_dock.bake_connector_mode_opt.get_selected_id())
	note("after import: level holds", other.get("bake_connector_mode"))
	note("after import: level bake_navmesh", other.get("bake_navmesh"))
	note("after import: level lightmap texel", other.get("bake_lightmap_texel_size"))
	if (
		int(other_dock.bake_connector_mode_opt.get_selected_id())
		!= int(other.get("bake_connector_mode"))
	):
		known(
			477,
			"Import Settings leaves the connector mode on the dropdown only",
			(
				"_apply_editor_settings() calls OptionButton.select(), which by design does not"
				+ " emit item_selected, and the level is only written from that signal"
				+ " (HFDockConnections.connect_settings). Every check box and spin in the same"
				+ " block does reach the level, because setting those does emit. So the bake"
				+ " runs with the old connector mode while the dock shows the imported one, and"
				+ " nothing says which is in force."
			)
		)

	other_dock.queue_free()
	dock.queue_free()
	await frame()


func _values_the_dock_would_never_write() -> void:
	var root: Node3D = await fresh_root("MalformedSettingsLevel")
	var dock = await _dock(root)
	await frame()
	note("grid snap spin range", [dock.grid_snap.min_value, dock.grid_snap.max_value])
	note("level grid_snap at rest", root.get("grid_snap"))

	# A file from a project that works in bigger units, or one typo away from it.
	dock._apply_editor_settings({"grid_snap": 4096.0})
	await frame()
	note("after grid_snap 4096: spin shows", dock.grid_snap.value)
	note("after grid_snap 4096: level holds", root.get("grid_snap"))
	if not is_equal_approx(float(dock.grid_snap.value), float(root.get("grid_snap"))):
		known(
			478,
			"Import Settings puts a grid snap on the level that the dock refuses to show",
			(
				(
					"_apply_grid_snap() assigns the value to the SpinBox -- which clamps it to the"
					+ " 0..128 the scene declares -- and then writes the *argument* to"
					+ " level_root.grid_snap, unclamped. The dock reads %s and the level snaps to"
					+ " %s, and _save_user_pref() writes the out-of-range number into the prefs"
					+ " file so it comes back next session."
				)
				% [dock.grid_snap.value, root.get("grid_snap")]
			)
		)

	# What the level does with the snap it was given, at the point the editor
	# snaps everything through.
	var snapped_point: Vector3 = root._snap_point(Vector3(37.0, 5.0, -12.0))
	note("a position snapped with the imported grid", snapped_point)

	# Text where a number belongs, which is what a hand edit or a JSON writer
	# that quotes everything produces.
	dock._apply_editor_settings({"grid_snap": "sixteen"})
	await frame()
	note('after grid_snap "sixteen": level holds', root.get("grid_snap"))
	if is_zero_approx(float(root.get("grid_snap"))):
		known(
			478,
			"A non-numeric grid snap silently becomes zero",
			(
				'float("sixteen") is 0.0 in GDScript, and nothing between the file and the'
				+ " level checks. The dock shows 0, the level snaps to 0, and the mapper is"
				+ " told nothing about the file being unreadable. hf_user_prefs.gd validates"
				+ " every value it loads for exactly this reason (#423); the settings file has"
				+ " no such pass."
			)
		)

	dock.queue_free()
	await frame()
