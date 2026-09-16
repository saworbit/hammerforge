@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## What the editor costs once a level is the size of a real level.
##
## `cost` measures one brush of each shape. This measures the level: a greybox
## the size of a small map, and the price of every operation a mapper repeats
## hundreds of times an hour -- an undo step, a save, a validate, a bake.
##
## Undo in HammerForge is a whole-level snapshot: `capture_state()` walks every
## brush, face, entity, paint cell and material and `restore_state()` clears the
## level and rebuilds it. That is fine for ten brushes. The question this asks is
## at what size it stops being fine, measured rather than assumed.

const SIZES: Array[int] = [25, 100, 400]


func id() -> String:
	return "level-scale"


func summary() -> String:
	return "what an undo step, a save, a validate and a bake cost as a level grows"


func run() -> void:
	await _the_cost_curve()
	await _undo_of_one_brush_move()
	await _face_selection_at_scale()
	await _what_the_save_thread_is_not_doing()


func _build(root: Node3D, count: int) -> void:
	var per_row := 20
	for i in count:
		var x := float(i % per_row) * 128.0
		var z := float(i / per_row) * 128.0
		box(root, Vector3(64, 64, 64), Vector3(x, 0, z))


func _ms(usec_start: int) -> float:
	return float(Time.get_ticks_usec() - usec_start) / 1000.0


## Build, then time each thing a mapper does over and over.
func _the_cost_curve() -> void:
	var rows: Array = []
	for count in SIZES:
		var root: Node3D = await fresh_root("Level%d" % count)
		var t := Time.get_ticks_usec()
		_build(root, count)
		var build_ms := _ms(t)
		await frame()

		t = Time.get_ticks_usec()
		var state: Dictionary = root.capture_state()
		var capture_ms := _ms(t)

		var state_bytes: int = var_to_bytes(state).size()

		t = Time.get_ticks_usec()
		root.restore_state(state)
		var restore_ms := _ms(t)
		await frame()

		t = Time.get_ticks_usec()
		var report: Dictionary = root.validate_level()
		var validate_ms := _ms(t)

		var save_path := "user://vibe_scale_%d.hflevel" % count
		t = Time.get_ticks_usec()
		root.save_hflevel(save_path)
		# What the editor's main thread pays before the "threaded" write starts.
		var queued_ms := _ms(t)
		await HFVibe.settle_save(_tree, root)
		var save_ms := _ms(t)
		var size_kb := float(HFVibe.file_size(save_path)) / 1024.0

		t = Time.get_ticks_usec()
		await root.bake()
		var bake_ms := _ms(t)

		(
			rows
			. append(
				{
					"brushes": count,
					"build_ms": snappedf(build_ms, 0.1),
					"capture_ms": snappedf(capture_ms, 0.1),
					"state_kb": snappedf(float(state_bytes) / 1024.0, 0.1),
					"restore_ms": snappedf(restore_ms, 0.1),
					"validate_ms": snappedf(validate_ms, 0.1),
					"save_blocking_ms": snappedf(queued_ms, 0.1),
					"save_total_ms": snappedf(save_ms, 0.1),
					"file_kb": snappedf(size_kb, 0.1),
					"bake_ms": snappedf(bake_ms, 0.1),
				}
			)
		)
		note("scale row", rows[-1])
		if report.has("issues"):
			note(
				"  validate issues",
				report["issues"].size() if report["issues"] is Array else report["issues"]
			)

	note("cost curve", rows)
	if rows.size() >= 2:
		var small: Dictionary = rows[0]
		var large: Dictionary = rows[-1]
		var brush_ratio := float(large["brushes"]) / float(small["brushes"])
		for key in ["capture_ms", "restore_ms", "validate_ms", "bake_ms", "state_kb"]:
			var lo := float(small[key])
			var hi := float(large[key])
			if lo <= 0.0:
				continue
			note(
				"  %s grew %.1fx for %.0fx the brushes" % [key, hi / lo, brush_ratio],
				"%s -> %s" % [lo, hi]
			)
			if hi / lo > brush_ratio * 2.0:
				flag(
					"%s grows faster than the level does" % key,
					(
						"%.1fx the cost for %.0fx the brushes (%s -> %s)"
						% [hi / lo, brush_ratio, lo, hi]
					)
				)

	# The number a mapper feels: one undo step on a level this size.
	var last: Dictionary = rows[-1]
	if float(last["save_blocking_ms"]) > 100.0:
		known(
			601,
			(
				"save_hflevel() blocks for %.0f ms at %d brushes before the write thread starts"
				% [last["save_blocking_ms"], last["brushes"]]
			),
			(
				"the write is threaded but the serialization is not; autosave runs on a "
				+ "timer, so the editor stalls for that long on its own schedule. The whole "
				+ "save took %s ms" % last["save_total_ms"]
			)
		)
	var undo_ms := float(last["capture_ms"]) + float(last["restore_ms"])
	note(
		"one undo step at %d brushes" % last["brushes"],
		(
			"%.1f ms (capture %.1f + restore %.1f), snapshot %s KB"
			% [undo_ms, last["capture_ms"], last["restore_ms"], last["state_kb"]]
		)
	)
	if undo_ms > 100.0:
		known(
			600,
			"an undo step at %d brushes costs %.0f ms" % [last["brushes"], undo_ms],
			(
				(
					"undo is a whole-level snapshot -- capture_state() walks every brush, face, "
					+ "entity and paint cell and restore_state() clears the level and rebuilds "
					+ "it -- so the price of undoing a one-brush nudge is set by the size of the "
					+ "level, not the size of the edit. The snapshot itself is %s KB, and the "
					+ "editor keeps a stack of them"
				)
				% last["state_kb"]
			)
		)


## The smallest possible edit, and what it costs to take back.
func _undo_of_one_brush_move() -> void:
	var root: Node3D = await fresh_root()
	_build(root, 200)
	await frame()
	var brushes: Array = root.draft_brushes_node.get_children()
	if brushes.is_empty():
		note("no brushes", "skipping")
		return
	var target: Node3D = brushes[0]

	var t := Time.get_ticks_usec()
	var before: Dictionary = root.capture_state()
	var capture_ms := _ms(t)
	target.global_position += Vector3(16, 0, 0)
	t = Time.get_ticks_usec()
	var after: Dictionary = root.capture_state()
	var capture2_ms := _ms(t)

	# How much of the two snapshots is identical? That is the part re-recorded
	# for an edit that did not touch it.
	var same := 0
	var moved := 0
	for k in before.keys():
		if HFVibe.canonical(before[k]) == HFVibe.canonical(after.get(k, null)):
			same += 1
		else:
			moved += 1
	note("200 brushes: capture before %.1f ms, after %.1f ms" % [capture_ms, capture2_ms])
	note("snapshot keys unchanged by a one-brush nudge", "%d of %d" % [same, same + moved])
	var changed_keys: Array = []
	for k in before.keys():
		if HFVibe.canonical(before[k]) != HFVibe.canonical(after.get(k, null)):
			changed_keys.append(k)
	note("keys a one-brush nudge actually changed", changed_keys)
	note(
		"snapshot size for a 16-unit nudge",
		"%.1f KB" % (float(var_to_bytes(after).size()) / 1024.0)
	)


## Face selection is the other per-frame cost: every bulk texture operation
## walks it.
func _face_selection_at_scale() -> void:
	var root: Node3D = await fresh_root()
	_build(root, 200)
	await frame()
	var t := Time.get_ticks_usec()
	for b in root.draft_brushes_node.get_children():
		var faces = b.get("faces")
		if faces is Array:
			for i in faces.size():
				root.toggle_face_selection(b, i, true, false)
	var select_ms := _ms(t)
	note("selecting every face on 200 brushes", "%.1f ms" % select_ms)
	note("brushes with a face selection", root.face_selection.size())
	t = Time.get_ticks_usec()
	var state: Dictionary = root.capture_state()
	note(
		"capture_state with a full face selection",
		"%.1f ms, %.1f KB" % [_ms(t), float(var_to_bytes(state).size()) / 1024.0]
	)


## `save_hflevel()` is documented as threaded. Time the half that is not.
##
## #601 was fixed by splitting the capture from the encode: the scene walk and
## the Resource reads stay on the calling thread, and `encode_variant()` moved
## onto the write thread. So the thing to time is the payload the handoff
## actually builds, not the finished structure it used to build.
func _what_the_save_thread_is_not_doing() -> void:
	var root: Node3D = await fresh_root()
	_build(root, 400)
	await frame()
	var t := Time.get_ticks_usec()
	var payload = root._capture_hflevel_payload()
	var payload_ms := _ms(t)
	t = Time.get_ticks_usec()
	var encoded = HFLevelIO.encode_variant(payload)
	var encode_ms := _ms(t)
	note("400 brushes: _capture_hflevel_payload(), the blocking half", "%.1f ms" % payload_ms)
	note("  then encode_variant() on the write thread", "%.1f ms" % encode_ms)
	note("encoded payload", "%.1f KB" % (float(var_to_bytes(encoded).size()) / 1024.0))
	# The handoff has to hold nothing the editor owns, because the worker reads it.
	if HFLevelIO.holds_resource(payload):
		known(
			601,
			"a live Resource crosses to the write thread",
			(
				"capture_hflevel_payload() resolves Resources before the handoff so the "
				+ "worker only ever touches values. Something is getting past it."
			)
		)
	# The split is only worth having while the encode is the larger half.
	if encode_ms < payload_ms:
		note(
			"the encode is no longer the expensive half",
			"blocking %.1f ms vs threaded %.1f ms" % [payload_ms, encode_ms]
		)
