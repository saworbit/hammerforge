@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## The Example Level library in the Manage tab.
##
## Its one action replaces the level in front of the mapper, which makes it the
## most destructive button in the dock. What it does to work already in the
## scene, and whether that is recoverable, is the whole scenario.

const ExampleLibrary = preload("res://addons/hammerforge/ui/hf_example_library.gd")
const DOCK_SOURCE := "res://addons/hammerforge/dock.gd"


func id() -> String:
	return "examples"


func summary() -> String:
	return "what loading an example does to the level already in the scene, and whether it can be undone"


func run() -> void:
	await _what_load_costs_the_open_level()
	await _the_card_list_and_its_search()


func _library() -> Control:
	var lib = ExampleLibrary.new()
	_tree.get_root().add_child(lib)
	return lib


func _dock_source() -> String:
	var f := FileAccess.open(DOCK_SOURCE, FileAccess.READ)
	return f.get_as_text() if f else ""


func _function_body(source: String, header: String) -> String:
	var start := source.find(header)
	if start < 0:
		return ""
	var rest := source.substr(start)
	var next := rest.find("\nfunc ", 1)
	return rest.substr(0, next) if next > 0 else rest


## A level with work in it, then the sequence the Load button runs.
func _what_load_costs_the_open_level() -> void:
	var root: Node3D = await fresh_root()
	for i in range(6):
		box(root, Vector3(64, 64, 64), Vector3(i * 128, 0, 0))
	await frame()
	var entity = DraftEntity.new()
	entity.entity_type = "player_start"
	entity.entity_class = "player_start"
	root.add_entity(entity)
	await frame()

	var before := HFVibe.describe_level(root)
	note(
		"the mapper's level",
		(
			"%d brushes, %d entities"
			% [before.get("brushes", []).size(), before.get("entities", []).size()]
		)
	)

	var lib = _library()
	await frame()
	note("examples in the library", lib.get_example_count())
	var data: Dictionary = lib.get_example_data("simple_room")
	note("simple_room brushes", (data.get("brushes", []) as Array).size())

	# Exactly what dock._load_example_data() does before it places anything.
	root.clear_brushes()
	if root.entity_system and root.entity_system.has_method("clear_entities"):
		root.entity_system.clear_entities()
	await frame()
	var after := HFVibe.describe_level(root)
	note(
		"after the two clears the Load button runs",
		(
			"%d brushes, %d entities"
			% [after.get("brushes", []).size(), after.get("entities", []).size()]
		)
	)

	var source := _dock_source()
	# The load is two functions: the one that asks, and the one that does the
	# work. Read both, or the undo step looks missing because it is next door.
	var load_body := (
		_function_body(source, "func _load_example_data(")
		+ _function_body(source, "func _apply_example_data(")
	)
	var clear_body := _function_body(source, "func _on_clear(")
	var load_is_undoable := (
		load_body.contains("HFUndoHelper")
		or load_body.contains("_commit_state_action")
		or load_body.contains("_commit_done_state_action")
		or load_body.contains("create_action")
	)
	var clear_is_undoable := (
		clear_body.contains("HFUndoHelper") or clear_body.contains("_commit_state_action")
	)
	note("_on_clear goes through undo", clear_is_undoable)
	note("_load_example_data goes through undo", load_is_undoable)
	var confirms := load_body.contains("ConfirmationDialog") or load_body.contains("confirm")
	note("_load_example_data asks first", confirms)

	if not load_is_undoable or not confirms:
		known(
			443,
			"loading an example silently destroys the open level, with no confirmation and no undo",
			(
				"dock._load_example_data() calls level_root.clear_brushes() and "
				+ "entity_system.clear_entities() directly before placing the example, and "
				+ "the Load button on each card emits load_requested straight from "
				+ "_on_load_pressed() with nothing in between. The Clear Brushes button next "
				+ "to it in the same tab goes through _commit_state_action('Clear Brushes', "
				+ (
					"'clear_brushes') and is undoable; this path is not. A level of %d brushes "
					% before.get("brushes", []).size()
				)
				+ (
					"and %d entit(ies) went to %d and %d, and Ctrl+Z cannot bring it back"
					% [
						before.get("entities", []).size(),
						after.get("brushes", []).size(),
						after.get("entities", []).size(),
					]
				)
			)
		)
	lib.queue_free()


## The cards, and the search that indexes into them.
func _the_card_list_and_its_search() -> void:
	var lib = _library()
	await frame()
	var cards: int = lib._cards_container.get_child_count()
	note("cards after the first build", cards)

	# A second build in the same frame -- what a reload or a settings change does.
	lib._load_examples()
	var doubled: int = lib._cards_container.get_child_count()
	note("cards after a rebuild in the same frame", doubled)
	if doubled > cards:
		known(
			444,
			"rebuilding the example list leaves the old cards in place",
			(
				"_rebuild_cards() calls child.queue_free() without remove_child(), so the old "
				+ "cards stay in the container until the end of the frame and the new ones are "
				+ (
					"appended below them: %d cards became %d. _on_search_changed() then indexes "
					% [cards, doubled]
				)
				+ "_examples[i] by the container's child order and stops at "
				+ "i >= _examples.size(), so while the duplicates are alive the search shows "
				+ "and hides the wrong cards"
			)
		)

	lib._on_search_changed("arena")
	var visible_titles: Array = []
	for i in range(lib._cards_container.get_child_count()):
		var card: Control = lib._cards_container.get_child(i)
		if card.visible:
			visible_titles.append(card.name)
	note("cards visible for the search 'arena'", visible_titles)
	lib.queue_free()
