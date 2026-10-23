extends GutTest

## Notes left in the level for the people working on it (#1700).

const HFNotes = preload("res://addons/hammerforge/hf_notes.gd")
const HFStatusBoard = preload("res://addons/hammerforge/hf_status_board.gd")
const HFEntityPropUtils = preload("res://addons/hammerforge/ui/hf_entity_prop_utils.gd")
const HFConsolePanel = preload("res://addons/hammerforge/ui/hf_console_panel.gd")

const MAP := "user://hf_test_level_notes.map"
const SCENE := "user://hf_test_level_notes_playtest.tscn"
const LEVEL := "user://hf_test_level_notes.hflevel"

var root: LevelRoot
var _saved_author := ""


class DockStub:
	extends Node
	var level_root: Node = null


func before_each() -> void:
	_saved_author = DraftEntity.last_note_author
	DraftEntity.last_note_author = ""
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)


func after_each() -> void:
	DraftEntity.last_note_author = _saved_author
	for path in [MAP, SCENE, LEVEL]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _note(title: String, kind := "Note", done := false, at := Vector3.ZERO) -> DraftEntity:
	return (
		root
		. entity_system
		. restore_entity_from_info(
			{
				"name": "Note",
				"entity_type": "note",
				"properties":
				{"title": title, "body": "", "kind": kind, "author": "", "done": done},
				"transform": Transform3D(Basis(), at),
			}
		)
	)


func test_the_class_is_for_the_editor_only():
	var definition := root.get_entity_definition("note")
	assert_eq(definition.get("editor_only"), true)
	assert_eq(str(definition.get("category", "")), "Editor")
	var note := _note("Lift goes here")
	assert_true(HFNotes.is_editor_only(root, note))
	var lamp: DraftEntity = DraftEntity.new()
	lamp.entity_type = "light_point"
	root.entities_node.add_child(lamp)
	assert_false(HFNotes.is_editor_only(root, lamp), "a light is not")


func test_the_marker_shows_the_title_and_the_body_on_hover():
	var note := _note("Temporary wall")
	note.entity_data["body"] = "Remove after the art pass"
	note._assign_preview(note._note_preview())
	var title: Label3D = note.preview_node.get_node("Title")
	var body: Label3D = note.preview_node.get_node("Body")
	assert_eq(title.text, "Temporary wall")
	assert_false(body.visible, "the body waits for the cursor")
	var camera := Camera3D.new()
	add_child_autofree(camera)
	camera.look_at_from_position(Vector3(0, 2, 6), Vector3.ZERO)
	await get_tree().process_frame
	HFNotes.hover(root, camera, camera.unproject_position(note.global_position))
	assert_true(body.visible, "the cursor over it shows the body")
	HFNotes.hover(root, camera, Vector2(-500, -500))
	assert_false(body.visible, "and moving away hides it")


func test_each_kind_has_its_own_marker_and_a_done_note_fades():
	var todo := _note("Fix the ledge", "To Do")
	var playtest := _note("Players stuck", "Playtest")
	var shapes := []
	for note in [_note("Plain"), todo, playtest]:
		var marker: MeshInstance3D = note._note_preview().get_node("Marker")
		shapes.append(marker.mesh.get_class())
		marker.get_parent().free()
	assert_eq(shapes, ["SphereMesh", "BoxMesh", "CylinderMesh"])
	todo.entity_data["done"] = true
	var faded := todo._note_preview()
	var alpha: float = (faded.get_node("Marker") as MeshInstance3D).material_override.albedo_color.a
	assert_lt(alpha, 0.5, "done fades")
	faded.free()


func test_a_change_to_what_is_drawn_redraws_it():
	var note := _note("A")
	assert_true(note.refreshes_preview_on("title"))
	assert_true(note.refreshes_preview_on("done"))
	assert_false(note.refreshes_preview_on("author"))


func test_a_new_note_is_signed_with_the_last_author():
	var note := _note("A")
	HFEntityPropUtils.set_entity_property(note, "author", "Sam")
	assert_eq(DraftEntity.last_note_author, "Sam")
	var next: DraftEntity = DraftEntity.new()
	next.entity_type = "note"
	root.entities_node.add_child(next)
	next._apply_entity_defaults()
	assert_eq(str(next.entity_data.get("author", "")), "Sam")


func test_a_map_export_leaves_notes_out_and_says_so():
	_note("Not in the map")
	root.create_brush_from_info({"size": Vector3(2, 2, 2), "center": Vector3(0, 1, 0)})
	watch_signals(root)
	root.export_map(MAP)
	var text := FileAccess.get_file_as_string(MAP)
	assert_false(text.contains('"classname" "note"'), "no note in the map")
	var said := false
	for call in get_signal_parameters_list(root, "user_message"):
		if str(call[0]).contains("left out 1 note"):
			said = true
	assert_true(said, "the export says how many it left out")


func get_signal_parameters_list(object: Object, signal_name: String) -> Array:
	var out := []
	for i in get_signal_emit_count(object, signal_name):
		out.append(get_signal_parameters(object, signal_name, i))
	return out


func test_a_playtest_export_and_a_running_game_carry_no_note():
	_note("Not in the game")
	var lamp: DraftEntity = DraftEntity.new()
	lamp.entity_type = "light_point"
	root.entities_node.add_child(lamp)
	lamp.owner = root
	assert_true(root.export_playtest_scene(SCENE, false))
	var scene: Node = (load(SCENE) as PackedScene).instantiate()
	var found_note := false
	for node in scene.find_children("*", "", true, false):
		if node is DraftEntity and (node as DraftEntity).entity_type == "note":
			found_note = true
	assert_false(found_note, "the exported scene has no note")
	scene.free()
	root._run_entities_as_nodes()
	assert_eq(HFNotes.notes(root).size(), 0, "a running game drops it")


func test_notes_survive_a_level_save_and_load():
	var note := _note("Keep me", "To Do")
	note.entity_data["body"] = "body text"
	note.entity_data["author"] = "Sam"
	assert_eq(root.save_hflevel(LEVEL, true), OK)
	await _finish_saving(root)
	var again := LevelRoot.new()
	again.auto_spawn_player = false
	again.hflevel_autosave_enabled = false
	add_child_autoqfree(again)
	assert_true(again.load_hflevel(LEVEL))
	var notes := HFNotes.notes(again)
	assert_eq(notes.size(), 1)
	if notes.size() == 1:
		assert_eq(notes[0]["title"], "Keep me")
		assert_eq(notes[0]["kind"], "To Do")
		assert_eq(notes[0]["body"], "body text")
		assert_eq(notes[0]["author"], "Sam")


func _finish_saving(level: LevelRoot) -> void:
	var files = level.file_system
	for _i in 400:
		if files._hflevel_thread and files._hflevel_thread.is_alive():
			await get_tree().process_frame
			continue
		files.process_thread_queue()
		if not files._hflevel_thread and files._hflevel_pending.is_empty():
			return


func test_notes_survive_in_the_scene():
	var note := _note("In the scene", "Playtest")
	# The editor owns these by the edited scene; a test has to say so itself.
	root.entities_node.owner = root
	note.owner = root
	var packed := PackedScene.new()
	assert_eq(packed.pack(root), OK)
	var copy: Node = packed.instantiate()
	add_child_autofree(copy)
	await get_tree().process_frame
	var notes := HFNotes.notes(copy)
	assert_eq(notes.size(), 1)
	if notes.size() == 1:
		assert_eq(notes[0]["title"], "In the scene")
		assert_eq(notes[0]["kind"], "Playtest")


func test_the_status_board_counts_open_notes():
	_note("A", "To Do")
	_note("B", "To Do", true)
	_note("C", "Playtest")
	var ctx := HFStatusBoard.collect_context(root, null)
	var row: Dictionary = {}
	for check in HFStatusBoard.evaluate(ctx):
		if check["id"] == "notes":
			row = check
	assert_eq(str(row.get("value", "")), "2 open")
	assert_string_contains(str(row.get("detail", "")), "To Do 1")
	assert_string_contains(str(row.get("detail", "")), "Playtest 1")
	assert_eq(str(row.get("action_id", "")), "show_notes")


func test_the_console_lists_notes_by_kind_and_a_click_asks_for_it():
	var todo := _note("Fix the ledge", "To Do")
	_note("Players stuck", "Playtest", true)
	var dock := DockStub.new()
	dock.level_root = root
	add_child_autofree(dock)
	var panel := HFConsolePanel.new()
	add_child_autofree(panel)
	panel.set_dock(dock)
	panel.refresh_notes()
	var groups := []
	var top: TreeItem = panel._notes_tree.get_root()
	for group in top.get_children():
		groups.append(group.get_text(0))
	assert_eq(groups, ["To Do (1 open)", "Playtest (0 open)"])
	watch_signals(panel)
	var first: TreeItem = top.get_child(0).get_child(0)
	first.select(0)
	await get_tree().process_frame
	assert_signal_emitted_with_parameters(
		panel, "action_requested", ["select_note:%s" % root.get_path_to(todo)]
	)
