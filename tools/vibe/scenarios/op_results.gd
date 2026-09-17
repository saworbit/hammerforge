@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Operations that can refuse, and whether the mapper is told.
##
## `HFOpResult` exists so a refusal can carry a reason and a fix:
##
##     static func fail(msg: String, hint: String = "") -> HFOpResult
##     func user_text() -> String:  # "msg — hint"
##
## Thirty-nine functions return one. The question is what happens to the message
## on the way to the screen: a caller that reads `.ok` and drops `.message` turns
## a specific refusal into a button that did nothing.
##
## `operations` checks that each `can_*()` rule is also enforced by the operation
## it guards. This checks the other direction -- that the enforcement is audible.

const HANDLER_SOURCES := [
	"res://addons/hammerforge/dock.gd",
	"res://addons/hammerforge/dock_brush_handler.gd",
	"res://addons/hammerforge/dock_manage_handler.gd",
	"res://addons/hammerforge/dock_entity_handler.gd",
	"res://addons/hammerforge/dock_visgroup_handler.gd",
	"res://addons/hammerforge/dock_paint_handler.gd",
	"res://addons/hammerforge/dock_file_handler.gd",
	"res://addons/hammerforge/plugin_commands.gd",
	"res://addons/hammerforge/plugin_selection_commands.gd",
	"res://addons/hammerforge/plugin_vertex_ops.gd",
]


func id() -> String:
	return "op-results"


func summary() -> String:
	return "which refusals carry a reason to the mapper, and which are silent"


func run() -> void:
	await _what_the_refusals_say()
	await _hints_that_are_never_written()
	await _who_reads_the_message()


## Drive each operation into its refusal and read what comes back.
func _what_the_refusals_say() -> void:
	note("-- an operation refused, and the text it gives back --")
	var root: Node3D = await fresh_root()
	root.auto_spawn_player = false
	var a = box(root, Vector3(2, 2, 2), Vector3.ZERO)
	await frame()
	var b = box(root, Vector3(2, 2, 2), Vector3(8, 0, 0))
	await frame()

	var cases: Array = [
		["hollow with a wall thicker than the brush", root.can_hollow_brush(str(a.brush_id), 99.0)],
		["hollow a brush that is not there", root.can_hollow_brush("nope", 0.25)],
		["hollow with a negative wall", root.can_hollow_brush(str(a.brush_id), -1.0)],
		["clip on a plane that misses", root.can_clip_brush(str(a.brush_id), 0, 500.0)],
		["clip a brush that is not there", root.can_clip_brush("nope", 0, 0.0)],
		["merge two brushes that do not touch", root.can_merge_brushes([str(a.brush_id), str(b.brush_id)])],
		["merge one brush", root.can_merge_brushes([str(a.brush_id)])],
		["merge nothing", root.can_merge_brushes([])],
		["flip a brush that is not there", root.can_flip_brushes(["nope"])],
		["build a generator nobody has heard of", root.can_build_generator("banana", {})],
		["build stairs with no steps", root.can_build_generator("stairs", {"steps": 0})],
		["delete a brush that is not there", root.delete_brush_by_id("nope")],
		["carve with a brush that is not there", root.carve_with_brush("nope")],
		["merge brushes that are not there", root.merge_brushes_by_ids(["nope", "nope2"])],
		["hollow that is not there", root.update_hollow("nope", 0.25)],
	]
	var silent: Array[String] = []
	var no_hint: Array[String] = []
	for entry in cases:
		var label: String = entry[0]
		var result = entry[1]
		if result == null:
			note("%s: returned null rather than a result" % label)
			continue
		note(
			"%s" % label,
			'ok=%s message="%s" hint="%s"' % [result.ok, result.message, result.fix_hint]
		)
		if result.ok:
			note("  (accepted, so nothing to say)")
			continue
		if str(result.message).strip_edges() == "":
			silent.append(label)
		elif str(result.fix_hint).strip_edges() == "":
			no_hint.append(label)
	if not silent.is_empty():
		flag(
			"an operation refuses with no message at all",
			(
				"%s return ok=false and an empty `message`, so a caller that shows "
				+ "`user_text()` shows an empty string and the mapper sees the button "
				+ "do nothing"
			) % str(silent)
		)
	note("refusals with a message and no fix hint", no_hint.size())
	note("  they are", no_hint)
	await _guards_that_say_yes(root, a, b)


## Two of the guards above said yes to input the operation cannot do anything
## sensible with. What the operation then does is the finding, not the yes.
func _guards_that_say_yes(root: Node3D, a: Node, b: Node) -> void:
	note("-- what happens after a guard says yes to something it should not --")

	# Merge two brushes eight units apart, which `can_merge_brushes()` allows.
	var before: int = root.get_live_brush_count()
	var volume_before := _volume(a) + _volume(b)
	var merged = root.merge_brushes_by_ids([str(a.brush_id), str(b.brush_id)])
	await frame()
	note("merge of two disjoint brushes reported", "%s %s" % [merged.ok, merged.user_text()])
	note("brushes: %s -> %s" % [before, root.get_live_brush_count()])
	var survivor: Node = null
	for child in root.draft_brushes_node.get_children():
		if root.is_brush_node(child):
			survivor = child
	if survivor == null:
		flag("merging two disjoint brushes left no brush at all")
		return
	var volume_after := _volume(survivor)
	note("volume: %.2f + %.2f = %.2f -> %.2f" % [
		_volume(a) if is_instance_valid(a) else 0.0,
		_volume(b) if is_instance_valid(b) else 0.0,
		volume_before,
		volume_after
	])
	note("the result is convex", root.vertex_system.validate_convexity(survivor))
	note("its extent", HFVibe.local_extent(survivor))
	if not root.vertex_system.validate_convexity(survivor):
		# What a non-convex brush then does to the two things that require one.
		var report: Dictionary = root.validate_level()
		note("validate_level on the merged brush", report)
		var map_path := "user://vibe_op_results_merged.map"
		root.export_map(map_path, "valve220")
		await frame()
		var text := FileAccess.get_file_as_string(map_path)
		var planes := text.count("( ")
		note(".map written from the merged brush", "%s bytes, %s plane points" % [text.length(), planes])
		var baked = await root.bake(true, false, 1)
		await frame()
		note("bake of the merged brush returned", baked)
		flag(
			"merging two brushes that do not touch makes one brush that is not convex",
			(
				"`can_merge_brushes()` returns ok for two 2-cubes 8 units apart and the "
				+ "merge reports 'Merged 2 brushes'. The survivor spans %s, holds %.1f "
				+ "cubic units in two disconnected lumps, and "
				+ "`vertex_system.validate_convexity()` says false. Convexity is the one "
				+ "thing a brush has to be: a `.map` brush is an intersection of "
				+ "half-spaces, and the convex collision hull the bake generates will "
				+ "fill the gap. validate_level() reports %s issues about it"
			) % [
				HFVibe.local_extent(survivor),
				volume_after,
				(report.get("issues", []) as Array).size(),
			]
		)
	elif volume_after > volume_before * 1.5:
		flag(
			"merging two brushes that do not touch fills the gap between them",
			(
				"%.1f cubic units of brush become %.1f, so the empty space between two "
				+ "pillars becomes solid"
			) % [volume_before, volume_after]
		)


func _volume(brush) -> float:
	if brush == null or not is_instance_valid(brush):
		return 0.0
	var total := 0.0
	for face in brush.faces:
		var tri: Dictionary = face.triangulate()
		var verts: PackedVector3Array = tri.get("verts", PackedVector3Array())
		for t in range(verts.size() / 3):
			var i := t * 3
			total += verts[i].dot(verts[i + 1].cross(verts[i + 2])) / 6.0
	return absf(total)


## `HFOpResult.fail()` takes a hint and most callers do not give one, so
## `user_text()` -- the whole reason the class has two fields -- is the message
## on its own nearly everywhere.
func _hints_that_are_never_written() -> void:
	note("-- how often a refusal carries a fix hint --")
	var with_hint := 0
	var without := 0
	var examples: Array[String] = []
	for path in _every_source():
		var source := FileAccess.get_file_as_string(path)
		var at := 0
		while true:
			at = source.find("HFOpResult.fail(", at)
			if at < 0:
				break
			var call := source.substr(at, 400)
			var close := call.find(")")
			var body := call.substr(16, close - 16) if close > 16 else call
			# A hint is a second argument at the call's own comma depth.
			if _top_level_commas(body) >= 1:
				with_hint += 1
			else:
				without += 1
				if examples.size() < 6:
					examples.append("%s: %s" % [path.get_file(), body.substr(0, 70)])
			at += 16
	note("HFOpResult.fail() with a fix hint", with_hint)
	note("HFOpResult.fail() with only a message", without)
	for e in examples:
		note("  no hint", e)
	if without > with_hint * 2:
		flag(
			"the fix hint is the exception rather than the rule",
			(
				"%s of the %s `HFOpResult.fail()` calls pass only a message, so "
				+ "`user_text()` -- which exists to append the hint -- is the message on "
				+ "its own in %d%% of refusals. The class carries a field the codebase "
				+ "does not fill"
			) % [without, without + with_hint, roundi(100.0 * without / float(without + with_hint))]
		)


## And what the dock does with the object once it has it.
func _who_reads_the_message() -> void:
	note("-- callers that check .ok and never read .message --")
	var checks_ok := 0
	var reads_text := 0
	var drops: Array[String] = []
	for path in HANDLER_SOURCES:
		if not FileAccess.file_exists(path):
			continue
		var source := FileAccess.get_file_as_string(path)
		var lines := source.split("\n")
		for i in lines.size():
			var line: String = lines[i]
			# `.ok` as a property read, not `ok_button_text` and friends.
			if line.find(".ok") < 0 or line.find(".ok_") >= 0:
				continue
			checks_ok += 1
			# The message has to be read within a few lines of the check for the
			# mapper to see it.
			var window := ""
			for j in range(i, min(i + 6, lines.size())):
				window += lines[j]
			if (
				window.find("user_text()") >= 0
				or window.find(".message") >= 0
				or window.find("fix_hint") >= 0
			):
				reads_text += 1
			else:
				drops.append("%s:%d %s" % [path.get_file(), i + 1, line.strip_edges().substr(0, 70)])
	note("places a result's .ok is tested in a dock or command handler", checks_ok)
	note("of those, ones that also read the text within six lines", reads_text)
	note("ones that do not", drops.size())
	for d in drops.slice(0, 12):
		note("  drops the message", d)
	if drops.size() > reads_text:
		flag(
			"most callers test a refusal and throw the reason away",
			(
				"%s of %s `.ok` tests in the dock and command handlers do not read "
				+ "`user_text()`, `.message` or `.fix_hint` anywhere near the test. The "
				+ "operation knows exactly why it refused -- 'wall thickness exceeds "
				+ "brush size', 'brushes do not overlap' -- and the mapper gets a button "
				+ "that did nothing"
			) % [drops.size(), checks_ok]
		)


func _every_source() -> Array[String]:
	var out: Array[String] = []
	var stack: Array[String] = ["res://addons/hammerforge"]
	while not stack.is_empty():
		var dir_path: String = stack.pop_back()
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			var full := "%s/%s" % [dir_path, entry]
			if dir.current_is_dir():
				stack.append(full)
			elif entry.ends_with(".gd"):
				out.append(full)
			entry = dir.get_next()
		dir.list_dir_end()
	return out


## Commas at depth zero inside a call's argument list.
func _top_level_commas(body: String) -> int:
	var depth := 0
	var in_string := false
	var quote := ""
	var count := 0
	for i in body.length():
		var c := body[i]
		if in_string:
			if c == quote:
				in_string = false
			continue
		if c == '"' or c == "'":
			in_string = true
			quote = c
		elif c in ["(", "[", "{"]:
			depth += 1
		elif c in [")", "]", "}"]:
			if depth == 0:
				break
			depth -= 1
		elif c == "," and depth == 0:
			count += 1
	return count
