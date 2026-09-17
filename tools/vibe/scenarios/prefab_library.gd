@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## The prefab library panel, driven the way a mapper drives it.
##
## `prefabs` covers capture and placement, `prefab-links` covers variants and
## `prefab-materials` covers what a prefab carries between levels. This is the
## panel in front of all of it: the list, the search box, the tag filter, the
## Save and Delete buttons, the right-click menu and the drag onto the viewport.
##
## It is the one surface in the plugin that reads a directory rather than the
## level, so the questions are about the directory: what it does with a prefab
## that is not one, with a name a filesystem will not take, with two prefabs of
## the same name, and whether what the list says matches what is on disk.

const LibraryScene = preload("res://addons/hammerforge/ui/hf_prefab_library.gd")
const HFPrefabType = preload("res://addons/hammerforge/hf_prefab.gd")
const HFPrefabSystemType = preload("res://addons/hammerforge/systems/hf_prefab_system.gd")

## Every file this scenario puts on disk, so `_clean_up()` can take them away.
var _written_paths: Array[String] = []


func id() -> String:
	return "prefab-library"


func summary() -> String:
	return "the prefab library panel: its list, filters, names and what it does with a bad file"


func run() -> void:
	await _what_the_list_shows()
	await _names_the_panel_accepts()
	await _files_that_are_not_prefabs()
	await _the_drag_payload()
	_clean_up()


## The panel reads a real directory in the repo, so the scenario has to put it
## back. Anything left behind turns up in the next run's counts and in `git status`.
func _clean_up() -> void:
	var removed := 0
	for path in _written_paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
			removed += 1
	note("test files removed", removed)
	for leftover in _written_paths:
		if FileAccess.file_exists(leftover):
			flag("a scenario file could not be removed", leftover)


func _library() -> Control:
	var panel = LibraryScene.new()
	_tree.get_root().add_child(panel)
	await frame()
	return panel


## A prefab on disk, written the way `quick_save_prefab()` writes one.
func _write_prefab(root: Node3D, prefab_name: String, tags: PackedStringArray) -> String:
	var brush = box(root, Vector3(1, 2, 1), Vector3.ZERO)
	await frame()
	var prefab = HFPrefabType.new()
	prefab.prefab_name = prefab_name
	prefab.brush_infos = [root.get_brush_info_from_node(brush)]
	prefab.entity_infos = []
	if "tags" in prefab:
		prefab.tags = tags
	var dir := HFPrefabSystemType.PREFAB_DIR
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var path := "%s/%s.hfprefab" % [dir, prefab_name]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify(prefab.to_dict()))
	f.close()
	_written_paths.append(path)
	return path


func _what_the_list_shows() -> void:
	note("-- the list against the directory --")
	var root: Node3D = await fresh_root()
	root.auto_spawn_player = false
	note("prefab directory", HFPrefabSystemType.PREFAB_DIR)
	var made: Array[String] = []
	for entry in [["vibe_pillar", PackedStringArray(["structure", "stone"])],
			["vibe_doorframe", PackedStringArray(["structure"])],
			["vibe_lamp", PackedStringArray(["prop"])]]:
		var path: String = await _write_prefab(root, str(entry[0]), entry[1])
		if path != "":
			made.append(path)
	note("prefabs written", made.size())

	var panel = await _library()
	panel.refresh()
	await frame()
	var listed: int = panel._file_list.item_count if panel._file_list else -1
	note("rows in the list", listed)
	note("paths the panel holds", panel._file_paths.size())
	var on_disk := _count_on_disk()
	note("`.hfprefab` files on disk", on_disk)
	if listed != on_disk:
		flag(
			"the list and the directory disagree",
			"%s rows against %s files in %s" % [listed, on_disk, HFPrefabSystemType.PREFAB_DIR]
		)
	note("tags the filter offers", _tag_items(panel))

	# The search box. `_apply_filters()` cannot hide a row -- its own comment says
	# "ItemList doesn't support per-item visibility, so we use modulate" -- so it
	# dims and disables instead. The row count is therefore the wrong measure;
	# what matters is how many rows are still readable.
	for term in ["pillar", "PILLAR", "  pillar  ", "stone", "nothingmatchesthis"]:
		panel._search_bar.text = term
		panel._apply_filters()
		await frame()
		note(
			"searching '%s'" % term,
			"%s rows, %s still enabled" % [panel._file_list.item_count, _enabled(panel)]
		)
	panel._search_bar.text = "nothingmatchesthis"
	panel._apply_filters()
	await frame()
	if panel._file_list.item_count > 0 and _enabled(panel) == 0:
		flag(
			"a search that matches nothing leaves every row in the list, greyed out",
			(
				"the panel dims non-matching rows to 15%% alpha and disables them "
				+ "rather than removing them, so a search in a directory of fifty "
				+ "prefabs still shows fifty rows and the mapper scrolls a list of "
				+ "unreadable text looking for the two that lit up. The material "
				+ "browser, which has the same problem to solve, rebuilds its grid"
			)
		)
	panel._search_bar.text = ""
	panel._apply_filters()
	await frame()

	# Selecting nothing, which is the state the panel opens in.
	panel._file_list.deselect_all()
	note("get_selected_path() with nothing selected", "'%s'" % panel.get_selected_path())
	var deleted := []
	panel.delete_requested.connect(func(p): deleted.append(p))
	panel._on_delete_pressed()
	await frame()
	note("pressing Delete with nothing selected emitted", deleted)
	if deleted.size() > 0 and str(deleted[0]) == "":
		flag(
			"Delete with nothing selected asks to delete the empty path",
			(
				"`_on_delete_pressed()` emits `delete_requested('')` rather than "
				+ "refusing, so whatever is on the other end is handed a path that is "
				+ "not a file"
			)
		)


## The Save box takes a free-text name and puts it straight into a filename.
func _names_the_panel_accepts() -> void:
	note("-- what the name box accepts --")
	var panel = await _library()
	var asked: Array = []
	panel.save_requested.connect(func(n): asked.append(n))
	var cases := [
		["", "empty"],
		["   ", "spaces"],
		["../escape", "a path traversal"],
		["a/b", "a slash"],
		["con", "a reserved Windows device name"],
		["name.with.dots", "dots"],
		["名前", "non-ASCII"],
		["x".repeat(300), "300 characters"],
	]
	for entry in cases:
		asked.clear()
		panel._name_input.text = str(entry[0])
		panel._on_save_pressed()
		await frame()
		note("%s -> save_requested %s" % [entry[1], asked])
	# An empty name becomes "untitled", which is the right answer. The question is
	# what the save side does with the rest, so ask it rather than reason about it.
	note("-- and what the save side then writes --")
	var root: Node3D = await fresh_root("PrefabNames")
	root.auto_spawn_player = false
	var brush = box(root, Vector3(1, 1, 1), Vector3.ZERO)
	await frame()
	var escaped: Array[String] = []
	var refused: Array[String] = []
	for entry in cases:
		var wanted := str(entry[0])
		if wanted.strip_edges() == "":
			continue
		var written: String = root.prefab_system.quick_save_prefab([brush], [], wanted, false)
		# `begins_with` is not enough: "res://prefabs/../escape.hfprefab" starts with
		# the directory and resolves outside it.
		var resolved := written.simplify_path()
		var inside := (
			written != "" and resolved.begins_with(HFPrefabSystemType.PREFAB_DIR + "/")
		)
		var exists := written != "" and FileAccess.file_exists(written)
		note(
			"%s -> '%s' (resolves to '%s')" % [entry[1], written, resolved],
			"inside the prefab directory: %s, file exists: %s" % [inside, exists]
		)
		if written != "":
			_written_paths.append(written)
		if written != "" and not inside:
			escaped.append("%s -> %s" % [wanted, resolved])
		if written == "":
			refused.append(str(entry[1]))
	if not escaped.is_empty():
		flag(
			"a prefab name with a path in it writes outside the prefab directory",
			(
				"`quick_save_prefab()` builds its filename as "
				+ "`prefab_name.to_snake_case() + '.hfprefab'` and joins it onto "
				+ "PREFAB_DIR, and `to_snake_case()` leaves a slash alone: %s. The name "
				+ "comes straight off a free-text box in the panel with no validation on "
				+ "either side"
			) % str(escaped)
		)
	note("names the save side refused, returning an empty path", refused)
	if not refused.is_empty():
		flag(
			"a prefab name the filesystem will not take fails with no message",
			(
				"%s return an empty string from `quick_save_prefab()` and nothing above "
				+ "it turns that into anything the mapper sees -- the name stays in the "
				+ "box, the list does not change, and the Save button looks like it did "
				+ "not register the click"
			) % str(refused)
		)


## A directory a mapper shares between projects has other things in it.
func _files_that_are_not_prefabs() -> void:
	note("-- what a bad file in the directory does to the panel --")
	var dir := HFPrefabSystemType.PREFAB_DIR
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	for entry in [
		["vibe_broken.hfprefab", "this is not json"],
		["vibe_empty.hfprefab", ""],
		["vibe_wrong_shape.hfprefab", '{"prefab_name": 42}'],
		["vibe_notes.txt", "a readme someone left here"],
	]:
		var written_path := "%s/%s" % [dir, entry[0]]
		HFVibe.write_text(written_path, str(entry[1]))
		_written_paths.append(written_path)

	var panel = await _library()
	panel.refresh()
	await frame()
	note("rows after four odd files", panel._file_list.item_count)
	var rows: Array[String] = []
	for i in panel._file_list.item_count:
		rows.append(panel._file_list.get_item_text(i))
	note("row labels", rows)
	var shows_broken := false
	for r in rows:
		if r.to_lower().find("broken") >= 0 or r.to_lower().find("empty") >= 0:
			shows_broken = true
	note("a malformed prefab is still listed", shows_broken)
	note("the .txt is listed", rows.any(func(r: String): return r.find("notes") >= 0))

	# The tag filter reads each file to collect tags, so a malformed one is read
	# on every refresh.
	note("tags offered with malformed files present", _tag_items(panel))
	panel._search_bar.text = "vibe"
	panel._apply_filters()
	await frame()
	note("filtering with malformed files present left", panel._file_list.item_count)
	if shows_broken:
		note(
			"a malformed prefab is offered for placement",
			"selecting it and dragging it into the viewport is the next thing a mapper does"
		)


## The panel is a drag source. What it hands over decides what the viewport can
## do with it -- `viewport-drop` covers the receiving end.
func _the_drag_payload() -> void:
	note("-- the drag payload --")
	var panel = await _library()
	panel.refresh()
	await frame()
	if panel._file_list.item_count == 0:
		note("nothing in the list to drag")
		return
	panel._file_list.size = Vector2(240, 400)
	await frame()
	var rect: Rect2 = panel._file_list.get_item_rect(0)
	var payload = panel._get_drag_data_fw(rect.get_center(), panel._file_list)
	note("payload from over the first row", payload)
	note("payload from above the list", panel._get_drag_data_fw(Vector2(-10, -10), panel._file_list))
	if payload == null:
		note(
			"no payload from over a row",
			"`get_item_at_position(pos, true)` wants an exact hit; a headless list has "
			+ "no layout, so this is the harness rather than the panel"
		)
	else:
		note("payload type", str((payload as Dictionary).get("type", "")))
		var dragged := str((payload as Dictionary).get("path", ""))
		note("payload path exists on disk", FileAccess.file_exists(dragged))
		if not FileAccess.file_exists(dragged):
			flag("the drag payload names a file that is not there", dragged)


## Rows the filter left readable. `_apply_filters()` disables rather than removes.
func _enabled(panel: Control) -> int:
	var n := 0
	for i in panel._file_list.item_count:
		if not panel._file_list.is_item_disabled(i):
			n += 1
	return n


func _count_on_disk() -> int:
	var dir := DirAccess.open(HFPrefabSystemType.PREFAB_DIR)
	if dir == null:
		return 0
	var n := 0
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.ends_with(".hfprefab"):
			n += 1
		entry = dir.get_next()
	dir.list_dir_end()
	return n


func _tag_items(panel: Control) -> Array:
	var out: Array = []
	if panel._tag_filter == null:
		return out
	for i in panel._tag_filter.item_count:
		out.append(panel._tag_filter.get_item_text(i))
	return out
