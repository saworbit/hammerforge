@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## What Update on a generated structure does to the pieces a mapper has edited.
##
## A generated staircase is a starting point. Nobody leaves one alone: one step
## gets resized to meet a landing, one tread gets a different texture, one step
## is deleted to make a gap, a railing brush is drawn beside it and grouped with
## it, one step is tied to an entity, and the whole flight is dragged into place.
## Then the mapper changes their mind about the number of steps and presses
## Update.
##
## `structures` pins that Update with unchanged settings is a no-op on an
## untouched structure, and `generator-geometry` covers every piece across the
## schema. This asks the question in between: for each kind of hand edit, is it
## kept, lost with a warning the dock would show, or lost with nothing said? And
## can undo bring it back? The dock's warning is `edited_generator_pieces()` (the
## "N pieces have been edited by hand" line), `generator_appearance_at_risk()`
## (the paint warning that makes Update take two presses) and
## `generator_pieces_disagree()`; those three are what a mapper is told.

const TYPE := "stairs"


func id() -> String:
	return "generator-hand-edits"


func summary() -> String:
	return "what Update on a generated structure does to pieces edited by hand"


func run() -> void:
	for edit in ["resize", "retexture", "delete", "group", "tie", "move"]:
		for changed in [false, true]:
			await _one_edit(edit, changed)
	await _undo_brings_it_back()
	await _every_piece_deleted()


func _settings(changed: bool) -> Dictionary:
	var s: Dictionary = HFGeneratorSystem.default_settings(TYPE)
	if changed:
		s["steps"] = int(s["steps"]) + 2
		s["rise"] = 0.25
	return s


func _bid(node: Node) -> String:
	return str(node.get_meta("brush_id", ""))


## The pieces in the order the record lists them, which is the order Update puts
## appearance back in.
func _pieces(root: Node3D, gid: String) -> Array:
	var out: Array = []
	var record = root.generator_for_id(gid)
	if record == null:
		return out
	for brush_id in record.brush_ids:
		var b = root.find_brush_by_id(str(brush_id))
		if b != null and str(b.get_meta("hf_generator_id", "")) == gid:
			out.append(b)
	return out


func _build(root: Node3D) -> String:
	var before := {}
	for r in root.generator_system.capture():
		before[str(r.get("generator_id", ""))] = true
	var result = root.create_generator(
		TYPE, _settings(false), Transform3D(Basis.IDENTITY, Vector3(4, 0, 4))
	)
	if result == null or not result.ok:
		return ""
	for r in root.generator_system.capture():
		var gid := str(r.get("generator_id", ""))
		if not before.has(gid):
			return gid
	return ""


func _top_face(brush: Node) -> int:
	var best := -1
	var best_dot := -INF
	for i in brush.faces.size():
		var d: float = (brush.faces[i].normal as Vector3).normalized().dot(Vector3.UP)
		if d > best_dot:
			best_dot = d
			best = i
	return best


## Make one hand edit. Returns what the check needs to find it again.
func _apply(root: Node3D, gid: String, edit: String) -> Dictionary:
	var pieces := _pieces(root, gid)
	var ctx := {"pieces": pieces.size()}
	match edit:
		"resize":
			var p = pieces[2]
			var size: Vector3 = p.size + Vector3(0, 0, 0.5)
			root.set_brush_transform_by_id(_bid(p), size, p.global_position)
			ctx["index"] = 2
			ctx["size"] = size
		"retexture":
			root.add_material_to_palette(
				ResourceLoader.load(
					"res://addons/hammerforge/textures/prototypes/materials/proto_brick_red.tres"
				)
			)
			var p = pieces[3]
			var top := _top_face(p)
			root.assign_material_to_faces_by_id(_bid(p), [top], 0)
			ctx["index"] = 3
		"delete":
			root.delete_brushes_by_id([_bid(pieces[4])])
		"group":
			var rail = box(root, Vector3(0.1, 1, 3), Vector3(5, 1, 4))
			await frame()
			ctx["rail"] = _bid(rail)
			var members: Array = pieces.duplicate()
			members.append(rail)
			root.group_selection("Flight", members)
			root.create_visgroup("Stairs")
			root.add_selection_to_visgroup("Stairs", members)
			# Hidden, the way a mapper hides the stairs to work on the floor under them.
			root.set_visgroup_visible("Stairs", false)
			ctx["showing_before"] = pieces.filter(func(b): return b.visible).size()
		"tie":
			root.tie_brushes_to_entity([_bid(pieces[5])], "func_wall", "secret_step")
			ctx["index"] = 5
		"move":
			var ids: Array = pieces.map(func(b): return _bid(b))
			root.nudge_brushes_by_id(ids, Vector3(3, 0, 0))
			ctx["first_x"] = pieces[0].global_position.x
	await frame()
	return ctx


## Whether the edit is still there, and a description of what is.
func _kept(root: Node3D, gid: String, edit: String, ctx: Dictionary, changed: bool) -> Array:
	var pieces := _pieces(root, gid)
	match edit:
		"resize":
			var p = pieces[ctx["index"]] if pieces.size() > ctx["index"] else null
			var size: Vector3 = p.size if p else Vector3.ZERO
			return [p != null and size.is_equal_approx(ctx["size"]), "step 2 size %s" % size]
		"retexture":
			var p = pieces[ctx["index"]] if pieces.size() > ctx["index"] else null
			var mat: int = p.faces[_top_face(p)].material_idx if p else -9
			return [mat == 0, "step 3 top face slot %d" % mat]
		"delete":
			var want: int = (ctx["pieces"] as int) - 1 + (2 if changed else 0)
			return [
				pieces.size() == want, "%d pieces (%d with the gap kept)" % [pieces.size(), want]
			]
		"group":
			var in_group := 0
			var in_vg := 0
			var showing := 0
			for p in pieces:
				if p.visible:
					showing += 1
				if str(p.get_meta("group_id", "")) == "Flight":
					in_group += 1
				if (p.get_meta("visgroups", PackedStringArray()) as PackedStringArray).has(
					"Stairs"
				):
					in_vg += 1
			note("  pieces showing with the visgroup hidden, before Update", ctx["showing_before"])
			var rail = root.find_brush_by_id(str(ctx["rail"]))
			var rail_ok: bool = rail != null and str(rail.get_meta("group_id", "")) == "Flight"
			return [
				in_group == pieces.size() and in_vg == pieces.size() and rail_ok,
				(
					(
						"%d of %d pieces in group Flight, %d in hidden visgroup Stairs, %d showing, "
						+ "rail still grouped %s, group members %d"
					)
					% [
						in_group,
						pieces.size(),
						in_vg,
						showing,
						rail_ok,
						root.get_group_members("Flight").size()
					]
				)
			]
		"tie":
			var p = pieces[ctx["index"]] if pieces.size() > ctx["index"] else null
			var cls := str(p.get_meta("brush_entity_class", "")) if p else ""
			var nm := str(p.get_meta("entity_name", "")) if p else ""
			var tied := 0
			for q in pieces:
				if str(q.get_meta("brush_entity_class", "")) != "":
					tied += 1
			return [
				cls == "func_wall" and nm == "secret_step" and tied == 1,
				"step 5 is '%s' named '%s', %d pieces tied" % [cls, nm, tied]
			]
		"move":
			var x: float = pieces[0].global_position.x if not pieces.is_empty() else NAN
			return [
				is_equal_approx(x, ctx["first_x"]),
				"first step x %.3f (moved to %.3f)" % [x, ctx["first_x"]]
			]
	return [false, "?"]


func _one_edit(edit: String, changed: bool) -> void:
	var root: Node3D = await fresh_root()
	var gid := _build(root)
	if gid == "":
		flag("the stairs would not build")
		await drop_root(root)
		return
	var ctx := await _apply(root, gid, edit)
	var settings := _settings(changed)
	var edited: int = root.edited_generator_pieces(gid)
	var at_risk: int = root.generator_appearance_at_risk(gid, settings).size()
	var disagree: bool = root.generator_pieces_disagree(gid)
	var warned := edited > 0 or at_risk > 0 or disagree
	var result = root.regenerate_generator(gid, settings)
	await frame()
	var kept := _kept(root, gid, edit, ctx, changed)
	var verdict := "kept" if kept[0] else ("lost with a warning" if warned else "LOST SILENTLY")
	note(
		"%s, Update %s" % [edit, "with changed settings" if changed else "unchanged"],
		(
			"%s -- %s (dock would say: %d edited, %d paint at risk, disagree %s; update ok %s)"
			% [verdict, kept[1], edited, at_risk, disagree, result.ok if result else "null"]
		)
	)
	for problem in HFVibe.check_invariants(root):
		flag("%s then Update broke an invariant" % edit, problem)
	if not kept[0] and not warned:
		_flag_silent(edit, changed, kept[1])
	await drop_root(root)


func _flag_silent(edit: String, changed: bool, what: String) -> void:
	var when := "with changed settings" if changed else "with the settings it already had"
	match edit:
		"group":
			# Kept since #1201: `_capture_appearance()` takes each piece's membership
			# and `_spawn()` gives it back, as the prefab rebuild does.
			flag(
				"[Generators] Update drops a structure out of its group and visgroups again (#1201)",
				(
					"stairs and a rail grouped as 'Flight' in hidden visgroup 'Stairs', %s: %s"
					% [when, what]
				)
			)
		"delete":
			# Counted as an edit since #1201, so the dock warns before Update puts it back.
			flag(
				"[Generators] Update puts back a deleted piece with no warning again (#1201)",
				"one step of eight deleted, %s: %s" % [when, what]
			)
		_:
			flag(
				"[Generators] Update loses a hand %s without a warning" % edit,
				"%s: %s" % [when, what]
			)


## The dock commits Update as a state action, so undo is `restore_state()` of the
## snapshot taken before it. Every edit at once, then Update, then undo.
func _undo_brings_it_back() -> void:
	note("-- every edit at once, Update with changed settings, then undo --")
	var root: Node3D = await fresh_root()
	var gid := _build(root)
	var ctxs := {}
	for edit in ["resize", "retexture", "group", "tie", "move"]:
		ctxs[edit] = await _apply(root, gid, edit)
	var before := HFVibe.describe_brushes(root)
	var before_group: int = root.get_group_members("Flight").size()
	var snapshot: Dictionary = root.capture_state()
	root.regenerate_generator(gid, _settings(true))
	await frame()
	var during_group: int = root.get_group_members("Flight").size()
	root.restore_state(snapshot)
	await frame()
	var after := HFVibe.describe_brushes(root)
	note(
		"group Flight members before Update / after / after undo",
		"%d / %d / %d" % [before_group, during_group, root.get_group_members("Flight").size()]
	)
	diff_levels({"brushes": before}, {"brushes": after}, "undo of an Update")
	var record = root.generator_for_id(gid)
	note("after undo the record lists", "%d pieces" % (record.brush_ids.size() if record else -1))
	if record == null or _pieces(root, gid).size() != record.brush_ids.size():
		flag("undo of an Update leaves the record and the pieces disagreeing")
	if HFVibe.canonical(before) == HFVibe.canonical(after):
		note("undo of an Update", "every piece back as it was, hand edits included")
	await drop_root(root)


## Every piece deleted. The record is "a hint, never a guarantee"; what does it
## become when there is nothing left to hint about?
func _every_piece_deleted() -> void:
	note("-- every piece of the structure deleted --")
	var root: Node3D = await fresh_root()
	var gid := _build(root)
	var ids: Array = _pieces(root, gid).map(func(b): return _bid(b))
	root.delete_brushes_by_id(ids)
	await frame()
	note("brushes left", root.brush_system.get_live_brush_count())
	note("generator_count() after deleting every piece", root.generator_count())
	note("has_generator()", root.has_generator(gid))
	var state: Dictionary = root.capture_state()
	note("records in capture_state()", (state.get("generators", []) as Array).size())
	var result = root.regenerate_generator(gid, _settings(true))
	await frame()
	note("Update on it", "ok %s, %s" % [result.ok, result.message])
	note("brushes after that Update", root.brush_system.get_live_brush_count())
	note(
		"reading",
		(
			"the record outlives its pieces and is saved, and Update rebuilds the whole structure "
			+ "at its last placement. The dock cannot reach it: the Structure section finds a "
			+ "record through a selected piece, and there is none to select. Undo of the delete "
			+ "is the way back, so this is not flagged"
		)
	)
	await drop_root(root)
