extends GutTest

## A sound can be picked and heard from the Entity panel (#991).
##
## `ambient_sound.stream` was a text box: the path had to be typed, and the only
## way to hear the sound was to export and play. A property the definition lists
## under `resource_properties` now gets a picker beside its field, and a sound one
## gets a Play button that plays it in the editor until the selection changes.

const DockScene = preload("res://addons/hammerforge/dock.tscn")
const HFDockEntityHandler = preload("res://addons/hammerforge/dock_entity_handler.gd")

const TONE := "user://hf_test_preview_tone.tres"

var root: LevelRoot
var dock: Node
var sound: Node3D


func before_each() -> void:
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	dock = DockScene.instantiate()
	add_child_autoqfree(dock)
	dock.level_root = root
	dock.connected_root = root
	dock._connect_root_signals()
	if dock.entity_defs.is_empty():
		dock._load_entity_definitions()
	sound = root._create_entity_from_map({"classname": "ambient_sound", "origin": Vector3.ZERO})
	dock._selection_nodes = [sound]
	HFDockEntityHandler.rebuild_entity_props(dock, sound)
	# One second of silence: something to load and play, and nothing to hear.
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = 8000
	var data := PackedByteArray()
	data.resize(8000)
	wav.data = data
	assert_eq(ResourceSaver.save(wav, TONE), OK, "fixture: the sound file")


func after_each() -> void:
	HFDockEntityHandler.stop_sound_preview(dock)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TONE))
	root = null
	dock = null
	sound = null


func _row(label: String) -> HBoxContainer:
	for row in dock._entity_props_controls:
		if row is HBoxContainer and (row.get_child(0) as Label).text == label:
			return row
	return null


func _button(row: HBoxContainer, text: String) -> Button:
	for child in row.get_children():
		if child is Button and (child as Button).text == text:
			return child
	return null


func _field(row: HBoxContainer) -> LineEdit:
	for child in row.get_children():
		if child is LineEdit:
			return child
	return null


func test_a_sound_property_has_a_picker_and_a_play_button():
	var row := _row("Stream:")
	assert_not_null(row, "fixture: the panel shows the stream")
	if row == null:
		return
	assert_not_null(_field(row), "the path can still be typed")
	assert_not_null(_button(row, "..."), "or picked")
	assert_not_null(_button(row, "Play"), "and heard")


func test_a_picked_file_lands_in_the_field_and_on_the_entity():
	var row := _row("Stream:")
	_button(row, "...").pressed.emit()
	var dialog: FileDialog = dock._entity_resource_dialog
	assert_not_null(dialog, "the picker opened")
	if dialog == null:
		return
	assert_string_contains(dialog.filters[0], "*.wav", "it offers the files a sound can be")
	dialog.file_selected.emit(TONE)
	assert_eq(_field(row).text, TONE, "the field shows the pick")
	assert_eq(sound.entity_data.get("stream"), TONE, "and the entity holds it")


func test_play_plays_the_file_and_a_second_press_stops_it():
	var row := _row("Stream:")
	_field(row).text = TONE
	_button(row, "Play").pressed.emit()
	var player: AudioStreamPlayer = dock._sound_preview
	assert_not_null(player, "a player was made")
	if player == null:
		return
	assert_true(player.stream is AudioStreamWAV, "holding the file")
	assert_true(player.playing, "and playing it")
	_button(row, "Play").pressed.emit()
	assert_false(player.playing, "the second press stops it")


func test_a_selection_change_stops_the_sound():
	_field(_row("Stream:")).text = TONE
	_button(_row("Stream:"), "Play").pressed.emit()
	var player: AudioStreamPlayer = dock._sound_preview
	assert_true(player != null and player.playing, "fixture: playing")
	HFDockEntityHandler.rebuild_entity_props(dock, null)
	assert_false(player.playing, "nothing selected, nothing playing")


func test_play_with_no_file_makes_no_player():
	_button(_row("Stream:"), "Play").pressed.emit()
	assert_null(dock._sound_preview, "there was nothing to play")


func test_a_light_gets_no_picker():
	var lamp := root._create_entity_from_map({"classname": "light_point", "origin": Vector3.ZERO})
	dock._selection_nodes = [lamp]
	HFDockEntityHandler.rebuild_entity_props(dock, lamp)
	for row in dock._entity_props_controls:
		assert_null(_button(row, "..."), "a light has no file properties")
