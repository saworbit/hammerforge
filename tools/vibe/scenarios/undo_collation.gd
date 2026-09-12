@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## `HFUndoHelper`'s collation window -- the thing that keeps a held-down nudge
## from filling the undo history with one entry per grid square.
##
## It decides whether to merge by comparing a tag, a flag and a timestamp held
## in `static var`s. Statics on a `RefCounted` are per-script, not per-level, so
## the question is what the state of one level has to do with the next action
## taken on another.

const UndoHelper = preload("res://addons/hammerforge/undo_helper.gd")


func id() -> String:
	return "undo-collation"


func summary() -> String:
	return "whether the undo collation window can carry state from one level root to another"


func run() -> void:
	await _two_levels_inside_one_window()
	await _the_window_across_unrelated_actions()


func _fired(names: Array) -> Callable:
	return func(action_name: String) -> void: names.append(action_name)


## Two `LevelRoot`s in the tree at once -- a level and a test scene, or two open
## scenes -- and the same command on each inside the collation window.
##
## The tag `plugin_edit_actions.collation_tag()` builds is the action, the brush
## ids, the entity paths and the inputs. Brush ids restart at `<session>_1` in
## every root, so two levels produce the same tag for the same command on their
## own first brush.
func _two_levels_inside_one_window() -> void:
	var a: Node3D = await fresh_root("LevelA")
	var b: Node3D = await fresh_root("LevelB")
	var brush_a := box(a, Vector3(64, 64, 64))
	var brush_b := box(b, Vector3(64, 64, 64))
	await frame()
	var id_a := str(brush_a.get_meta("brush_id", ""))
	var id_b := str(brush_b.get_meta("brush_id", ""))
	note("first brush id in each level", "%s / %s" % [id_a, id_b])
	if id_a == id_b:
		note("the two levels mint the same first brush id, so the tags match exactly")

	var tag := "nudge|%s|(0, 1, 0)|16" % id_a
	var history_a: Array = []
	var history_b: Array = []

	UndoHelper.commit(
		null,
		a,
		"Nudge HammerForge Objects",
		"nudge_managed_nodes",
		[[id_a], [], Vector3(0, 16, 0)],
		false,
		_fired(history_a),
		tag,
		true
	)
	UndoHelper.commit(
		null,
		b,
		"Nudge HammerForge Objects",
		"nudge_managed_nodes",
		[[id_b], [], Vector3(0, 16, 0)],
		false,
		_fired(history_b),
		tag.replace(id_a, id_b),
		true
	)
	note("history entries recorded for level A", history_a)
	note("history entries recorded for level B", history_b)
	if history_b.is_empty():
		flag(
			"an action on one level collates with the last action on another",
			(
				"HFUndoHelper keeps _last_collation_tag / _last_collation_time /"
				+ " _last_collation_state in static vars, so the window is global rather than"
				+ " per level. The nudge on LevelB inside the window was treated as a"
				+ " continuation of the nudge on LevelA: its history entry was suppressed, and"
				+ " on the undo_redo path it would have been registered with LevelA's captured"
				+ " state as its undo, so undoing it restores one level's geometry into the"
				+ " other. can_collate compares the tag, the full_state flag and the clock --"
				+ " never the root."
			)
		)

	# The state held over is the other level's, not this one's.
	note("static collation state is held for tag", UndoHelper._last_collation_tag)


## The window is a second wide and the tag is the only thing separating two
## unrelated commands.
func _the_window_across_unrelated_actions() -> void:
	var root: Node3D = await fresh_root()
	var brush := box(root, Vector3(64, 64, 64))
	await frame()
	var brush_id := str(brush.get_meta("brush_id", ""))
	var history: Array = []

	for i in range(3):
		UndoHelper.commit(
			null,
			root,
			"Nudge HammerForge Objects",
			"nudge_managed_nodes",
			[[brush_id], [], Vector3(0, 16, 0)],
			false,
			_fired(history),
			"nudge|%s|(0, 1, 0)|16" % brush_id,
			true
		)
	note("history entries for three identical nudges", history)
	if history.size() != 1:
		flag("three nudges in a run did not collate into one history entry", history)

	UndoHelper.commit(
		null,
		root,
		"Nudge HammerForge Objects",
		"nudge_managed_nodes",
		[[brush_id], [], Vector3(0, -16, 0)],
		false,
		_fired(history),
		"nudge|%s|(0, -1, 0)|16" % brush_id,
		true
	)
	note("history after nudging back the other way", history)
	note("brush position after four nudges", brush.global_position)
