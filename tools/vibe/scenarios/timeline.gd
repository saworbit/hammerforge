@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## The operation timeline overlay and the history browser beside it.
##
## Both exist to let a mapper read back what they just did and jump to it. So
## what is worth checking is whether the glyph and colour an operation gets
## actually tell it apart from the others, and whether the control that does
## the jumping can be reached at all.

const OperationReplay = preload("res://addons/hammerforge/ui/hf_operation_replay.gd")

## The undo action names the plugin really records, taken from the
## create_action / history_callback strings in the source.
const REAL_ACTIONS := [
	"Clear Brushes",
	"Apply Brush Material",
	"Create Polygon Brush",
	"Clip Brush",
	"Assign Face Material",
	"Move to Floor",
	"Bevel Edge",
	"Group Selection",
	"Bake Selected",
	"Place Prefab: door",
]


func id() -> String:
	return "timeline"


func summary() -> String:
	return "the glyph and colour an operation gets on the timeline, and whether Replay can be clicked"


func run() -> void:
	await _what_each_operation_looks_like()
	await _reaching_the_replay_button()
	await _the_three_different_caps()


func _panel() -> Control:
	var panel = OperationReplay.new()
	_tree.get_root().add_child(panel)
	return panel


## Every real action name through the icon and colour tables.
func _what_each_operation_looks_like() -> void:
	var by_glyph: Dictionary = {}
	for action in REAL_ACTIONS:
		var glyph: String = OperationReplay._get_icon_for_action(action)
		var colour: Color = OperationReplay._get_color_for_action(action)
		note("  %-22s" % action, "'%s'  %s" % [glyph, colour])
		by_glyph[glyph] = by_glyph.get(glyph, 0) + 1

	var create_glyph := OperationReplay._get_icon_for_action("Create Polygon Brush")
	var clear_glyph := OperationReplay._get_icon_for_action("Clear Brushes")
	var clear_colour := OperationReplay._get_color_for_action("Clear Brushes")
	var delete_colour := OperationReplay._get_color_for_action("Delete Selection")
	note("Clear Brushes glyph/colour", "'%s' %s" % [clear_glyph, clear_colour])
	note("Delete Selection colour", delete_colour)
	if clear_glyph == create_glyph and clear_colour != delete_colour:
		known(
			437,
			"a destructive operation is drawn on the timeline as a creation",
			(
				"_get_icon_for_action() tests 'draw'/'brush'/'create' before 'delete'/'remove' "
				+ "is reachable for it, and 'Clear Brushes' contains 'brush', so it gets the "
				+ (
					"create glyph '%s' and the create colour %s rather than the destructive "
					% [clear_glyph, clear_colour]
				)
				+ "red %s. The name is only in the tooltip" % str(delete_colour)
			)
		)

	var material_glyph := OperationReplay._get_icon_for_action("Apply Brush Material")
	var face_material_glyph := OperationReplay._get_icon_for_action("Assign Face Material")
	note(
		"Apply Brush Material vs Assign Face Material",
		"'%s' vs '%s'" % [material_glyph, face_material_glyph]
	)
	if material_glyph != face_material_glyph:
		known(
			437,
			"two material operations get different glyphs because one of them says 'brush'",
			(
				(
					"'Apply Brush Material' is drawn '%s' (create) and 'Assign Face Material' is "
					% material_glyph
				)
				+ (
					"drawn '%s' (material). The generic 'brush' test sits above 'material', "
					% face_material_glyph
				)
				+ "'move', 'rotate', 'vertex' and 'paint' in the same if-chain, so any action "
				+ "whose name mentions a brush is filed as a creation whatever it did"
			)
		)

	note("distinct glyphs across %d real action names" % REAL_ACTIONS.size(), by_glyph.size())
	note(
		"move and redo share a glyph",
		(
			OperationReplay._get_icon_for_action("Move Selection")
			== OperationReplay._get_icon_for_action("Redo")
		)
	)


## Hover an entry, then try to click Replay.
func _reaching_the_replay_button() -> void:
	var panel = _panel()
	await frame()
	panel.record_operation("Create Polygon Brush", 4)
	panel.record_operation("Clip Brush", 5)
	await frame()
	note("entries", panel.get_entry_count())

	panel._on_entry_hovered(1)
	note("after hovering entry 1: Replay visible", panel._replay_btn.visible)
	note("  hovered index", panel._hovered_index)

	# Moving the pointer off the entry towards the Replay button is a mouse_exited
	# on the entry -- there is nothing between them.
	panel._on_entry_unhovered()
	note("after the pointer leaves the entry: Replay visible", panel._replay_btn.visible)
	note("  hovered index", panel._hovered_index)

	var emitted := [false]
	panel.replay_requested.connect(func(_i: int) -> void: emitted[0] = true)
	panel._on_replay_pressed()
	note("pressing Replay now emits", emitted[0])

	# And after clicking the entry rather than hovering it.
	panel._on_entry_clicked(1)
	note("after clicking entry 1: Replay visible", panel._replay_btn.visible)
	panel._on_entry_unhovered()
	note("  then the pointer leaves: Replay visible", panel._replay_btn.visible)
	panel._on_replay_pressed()
	note("  pressing Replay emits", emitted[0])

	if not emitted[0]:
		known(
			438,
			"the Replay button cannot be reached: moving towards it is what hides it",
			(
				"_replay_btn is shown by _on_entry_hovered() and hidden again by "
				+ "_on_entry_unhovered(), which also resets _hovered_index to -1. The button "
				+ "sits in the header, outside the entry it belongs to, so any pointer path "
				+ "from the entry to the button crosses a mouse_exited first. Clicking the "
				+ "entry does not help -- _on_entry_clicked() sets the same _hovered_index "
				+ "that the next mouse_exited clears. _on_replay_pressed() then sees -1 and "
				+ "emits nothing, so the whole replay path is dead"
			)
		)
	panel.queue_free()


## Three components remember three different numbers of operations.
func _the_three_different_caps() -> void:
	var panel = _panel()
	await frame()
	for i in range(40):
		panel.record_operation("Create Polygon Brush", i)
	await frame()
	note("timeline MAX_ENTRIES", OperationReplay.MAX_ENTRIES)
	note("entries after 40 operations", panel.get_entry_count())
	note("version at index 0 after the overflow", panel.get_entry_version(0))
	note("history browser MAX_ENTRIES", HFHistoryBrowser.MAX_ENTRIES)
	panel.queue_free()
