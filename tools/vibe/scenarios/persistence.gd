@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Capture and restore, which is what undo replays and what every whole-level
## operation leans on.
##
## The round trip here is `capture_state()` -> `restore_state()`. It is supposed
## to be exact: the state a capture wrote back onto a level should leave that
## level indistinguishable from the one it came off. When it is not, the loss is
## silent -- the operation reports success and the level is just poorer, which
## is the shape every round-trip defect in this project has had.


func id() -> String:
	return "persistence"


func summary() -> String:
	return "capture/restore round trips, repeated restores, and level health after them"


func run() -> void:
	await _capture_restore_round_trip()
	await _restore_is_idempotent()
	await _restore_across_levels()
	await _junk_state()


## A level with something of everything on it.
func _furnish(root: Node3D) -> void:
	var mats: Array = []
	for i in range(3):
		var m := StandardMaterial3D.new()
		m.resource_name = "mat_%d" % i
		mats.append(m)
	root.set_materials(mats)

	var a = box(root, Vector3(128, 64, 64), Vector3(-128, 0, 0))
	var b = box(root, Vector3(64, 64, 64), Vector3(128, 0, 0))
	a.faces[0].material_idx = 2
	a.faces[1].uv_scale = Vector2(2, 4)
	a.faces[1].uv_offset = Vector2(0.25, 0.5)
	b.faces[3].uv_rotation = 0.75
	root.create_visgroup("lights", Color.YELLOW)
	root.add_selection_to_visgroup("lights", [b])
	root.tie_brushes_to_entity([str(b.get_meta("brush_id", ""))], "func_door")
	var entity = (
		root
		. _restore_entity_from_info(
			{
				"entity_type": "light",
				"entity_class": "light",
				"transform": Transform3D(Basis.IDENTITY, Vector3(0, 64, 0)),
				"properties": {"brightness": 2.5},
				"name": "light_1",
				"entity_name": "light_1",
			}
		)
	)
	if entity:
		root.add_entity_output(entity, "OnStart", "door_1", "Open")
	root.create_generator(
		"stairs", HFGeneratorSystem.default_settings("stairs"), Transform3D.IDENTITY
	)
	root.create_displacement(str(a.get_meta("brush_id", "")), 2, 2)
	root.add_paint_layer()


## Capture a furnished level, change it, put the capture back.
func _capture_restore_round_trip() -> void:
	var root: Node3D = await fresh_root()
	_furnish(root)
	await frame()
	var before := HFVibe.describe_level(root)
	var state: Dictionary = root.capture_state()
	note("captured", "%d top-level keys" % state.size())

	# Wreck the level, so a restore that quietly does nothing is visible.
	root.clear_brushes()
	root._clear_entities()
	await frame()
	note("after clearing", "%d brushes" % root.get_live_brush_count())

	root.restore_state(state)
	await frame()
	var after := HFVibe.describe_level(root)
	diff_levels(before, after, "capture_state and restore_state")
	for problem in HFVibe.check_invariants(root):
		flag("restore_state broke an invariant", problem)


## Restoring the same capture twice must land in the same place as once.
## Undo replays a capture every time it is stepped over.
func _restore_is_idempotent() -> void:
	var root: Node3D = await fresh_root()
	_furnish(root)
	await frame()
	var state: Dictionary = root.capture_state()
	root.restore_state(state)
	await frame()
	var once := HFVibe.describe_level(root)
	for _i in range(3):
		root.restore_state(state)
		await frame()
	var four_times := HFVibe.describe_level(root)
	note("restored the same capture four times", "%d brushes" % root.get_live_brush_count())
	diff_levels(once, four_times, "restoring the same capture four times rather than once")
	for problem in HFVibe.check_invariants(root):
		flag("repeated restore broke an invariant", problem)


## A capture taken off one level, restored onto another. This is what a prefab
## drop, a paste and a whole-level replace all do.
func _restore_across_levels() -> void:
	var source: Node3D = await fresh_root("Source")
	_furnish(source)
	await frame()
	var before := HFVibe.describe_level(source)
	var state: Dictionary = source.capture_state()

	var target: Node3D = await fresh_root("Target")
	target.restore_state(state)
	await frame()
	var after := HFVibe.describe_level(target)
	diff_levels(before, after, "a capture restored onto a different level")
	for problem in HFVibe.check_invariants(target):
		flag("restoring onto another level broke an invariant", problem)

	# And the source must not have been emptied out from under the caller by the
	# restore reparenting its nodes. #282 was exactly this shape.
	var source_after := HFVibe.describe_level(source)
	diff_levels(before, source_after, "the source level after its capture was restored elsewhere")


## A state dictionary that did not come from `capture_state`: truncated, wrong
## types, absurd counts. A hand-edited `.hflevel` produces all three.
func _junk_state() -> void:
	# Two kinds of bad state, and they are not the same failure.
	#
	# A state whose *shape* is wrong cannot be read at all, and the level must be
	# left as it was: the cost used to be that it was cleared first, so a bad file
	# took the good level with it.
	#
	# A state that can be read is a replacement, even when one entry in it is
	# rubbish. The level is meant to become what the state says, so the check is
	# that the entries it could read survived and the one it could not was
	# dropped rather than built.
	var good := {"shape": 0, "size": Vector3(64, 64, 64)}
	var unreadable := {
		"brushes is a string": {"brushes": "nope", "entities": [], "materials": []},
		"entities is a dictionary": {"brushes": [], "entities": {}, "materials": []},
		"face_selection is a list": {"brushes": [], "face_selection": [], "materials": []},
	}
	var readable := {
		"empty": [{}, -1],
		"a brush entry is a number": [{"brushes": [42, good], "entities": [], "materials": []}, 1],
		"a brush with no size": [{"brushes": [{"shape": 0}], "entities": [], "materials": []}, 1],
		"a brush with a NAN size":
		[
			{
				"brushes": [{"shape": 0, "size": Vector3(NAN, NAN, NAN)}, good],
				"entities": [],
				"materials": []
			},
			1
		],
		"materials holds junk":
		[{"brushes": [good], "entities": [], "materials": [1, "two", null]}, 1],
	}

	note("--- a state whose shape cannot be read must leave the level alone")
	for label in unreadable:
		var root: Node3D = await fresh_root()
		_furnish(root)
		await frame()
		var before_count: int = root.get_live_brush_count()
		root.restore_state(unreadable[label])
		await frame()
		note(
			"restore_state with %s" % label,
			"%d brushes (was %d)" % [root.get_live_brush_count(), before_count]
		)
		if root.get_live_brush_count() < before_count:
			flag(
				"restore_state with %s emptied a level it could not read" % label,
				"%d brushes before, %d after" % [before_count, root.get_live_brush_count()]
			)

	note("--- a state that can be read replaces the level, minus what it could not use")
	for label in readable:
		var root: Node3D = await fresh_root()
		_furnish(root)
		await frame()
		var before_count: int = root.get_live_brush_count()
		var entry: Array = readable[label]
		var expected: int = int(entry[1])
		root.restore_state(entry[0])
		await frame()
		var after_count: int = root.get_live_brush_count()
		note(
			"restore_state with %s" % label,
			(
				"%d brushes (was %d), %d materials"
				% [after_count, before_count, root.get_materials().size()]
			)
		)
		if expected >= 0 and after_count != expected:
			flag(
				"restore_state with %s built %d brushes, not %d" % [label, after_count, expected],
				"an entry it could not read should be skipped, and the rest should be built"
			)
		if expected < 0 and after_count != before_count:
			flag(
				"restore_state with an empty state changed the level",
				"%d brushes before, %d after" % [before_count, after_count]
			)
		var junk_materials := 0
		for m in root.get_materials():
			if m != null and not (m is Material):
				junk_materials += 1
		if junk_materials > 0:
			flag(
				(
					"restore_state with %s puts %d non-materials in the palette"
					% [label, junk_materials]
				),
				"get_materials() hands those back to every caller that then reads a Material off them"
			)
		for problem in HFVibe.check_invariants(root):
			flag("restore_state with %s broke an invariant" % label, problem)
