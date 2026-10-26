@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## What Sweep Faces makes, and what the structure it keeps does after it is made.
##
## The source is a 1 x 1 x 1 box with each face in its own palette slot by the way
## it faces, its +X face picked. Every run is measured rather than read off the
## sweep's own report: each piece a closed solid with no face turned in, the
## volume against the exact volume of the pieces the path should make (an arc of
## n segments of a 1 x 1 section at radius R is n sin(angle / n) R; a straight run
## that tapers is the prismatoid's), and each face's slot against the face of the
## source it ran along. Then the angles the schema and the end handle allow, a
## taper on a bend, the round trips a mapper puts a structure through (undo and
## redo as whole-level state, `.hflevel`, an Update with unchanged settings), and
## a Re-pick after the sweep has been moved, which is when the looks the guide
## says it dresses the pieces in are put to the test.

const HFFaceSweep = preload("res://addons/hammerforge/hf_face_sweep.gd")
## A face's slot by the way it faced on the source box.
const SLOT_OF := {"right": 2, "up": 3, "down": 4, "back": 5, "forward": 6, "left": 7}
const DIRECTIONS := {
	"right": Vector3.RIGHT,
	"left": Vector3.LEFT,
	"up": Vector3.UP,
	"down": Vector3.DOWN,
	"back": Vector3.BACK,
	"forward": Vector3.FORWARD,
}


func id() -> String:
	return "sweep-faces"


func summary() -> String:
	return "Sweep Faces along each path, past a half turn, with taper, and as a structure through moves, saves and Re-pick"


func expected_issues() -> Array[int]:
	return [1968, 1969, 1970]


func run() -> void:
	await _paths_measured()
	await _half_turn_and_past()
	await _taper_on_a_bend()
	await _round_trips()
	await _repick_after_a_move()
	await _odd_sources()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


func _settings(changes: Dictionary) -> Dictionary:
	var s: Dictionary = HFSweepBuilder.default_settings()
	s["path"] = HFFaceSweep.Path.ARC
	s.merge(changes, true)
	return s


func _bid(n: Node) -> String:
	return str(n.get_meta("brush_id", ""))


## A 1 x 1 x 1 box at `centre`, each face in its own slot, its +X face picked.
func _source(root: Node3D, centre: Vector3) -> Node:
	var b = box(root, Vector3(1, 1, 1), centre)
	var picked := -1
	for i in b.faces.size():
		var n: Vector3 = b.faces[i].normal.normalized()
		for k in DIRECTIONS:
			if n.is_equal_approx(DIRECTIONS[k]):
				b.faces[i].material_idx = SLOT_OF[k]
		if n.is_equal_approx(Vector3.RIGHT):
			picked = i
	root.face_selection = {_bid(b): [picked]}
	return b


## Sweep the picked faces as the dialog's OK does: `[result, generator id]`.
func _sweep(root: Node3D, settings: Dictionary) -> Array:
	var read: Dictionary = root.run_from_faces("sweep", root.face_selection)
	if read.has("refused"):
		return [HFOpResult.fail(str(read["refused"])), ""]
	var before: Array = root.generator_system.generators.keys()
	var result = root.create_generator("sweep", settings, read["placement"], null, read["run"])
	for g in root.generator_system.generators:
		if not before.has(g):
			return [result, str(g)]
	return [result, ""]


func _pieces(root: Node3D, gid: String) -> Array:
	var out: Array = []
	var record = root.generator_for_id(gid)
	if record == null:
		return out
	for brush_id in record.brush_ids:
		var b = root.find_brush_by_id(str(brush_id))
		if b:
			out.append(b)
	return out


func _measure(pieces: Array) -> Dictionary:
	var volume := 0.0
	var open := 0
	var inward := 0
	var faces := 0
	var slots := {}
	for p in pieces:
		volume += HFVibe.solid_volume(p.faces) * absf(p.global_basis.determinant())
		open += HFVibe.open_edge_count(p.faces)
		inward += HFVibe.inward_face_count(p)
		faces += p.faces.size()
		for f in p.faces:
			slots[int(f.material_idx)] = int(slots.get(int(f.material_idx), 0)) + 1
	return {"volume": volume, "open": open, "inward": inward, "faces": faces, "slots": slots}


## The faces of `pieces` that face mostly up or down in the level, and of those
## how many are not in the slot of the source face that faced that way.
func _wrong_tops(pieces: Array) -> Array:
	var count := 0
	var wrong := 0
	for p in pieces:
		for f in p.faces:
			var facing: float = (p.global_basis * f.normal).normalized().y
			if absf(facing) < 0.7:
				continue
			count += 1
			if int(f.material_idx) != (SLOT_OF["up"] if facing > 0.0 else SLOT_OF["down"]):
				wrong += 1
	return [count, wrong]


# ---------------------------------------------------------------------------
# Each path, measured
# ---------------------------------------------------------------------------


## An arc of `angle` degrees in `n` pieces of a 1 x 1 section at radius `r`.
static func _arc_volume(angle: float, n: int, r: float) -> float:
	return float(n) * sin(deg_to_rad(angle) / float(n)) * r


## A straight run of `length` of a 1 x 1 section, the far end `w` wide and `h` tall.
static func _straight_volume(length: float, w: float, h: float) -> float:
	var a := w - 1.0
	var b := h - 1.0
	return length * (1.0 + (a + b) * 0.5 + a * b / 3.0)


func _paths_measured() -> void:
	var cases := [
		["arc 90 in 8", {}, _arc_volume(90.0, 8, 4.0)],
		["arc 90 toward 45", {"toward": 45.0}, _arc_volume(90.0, 8, 4.0)],
		["arc 90 in 1", {"segments": 1}, _arc_volume(90.0, 1, 4.0)],
		["arc 179 in 16", {"angle": 179.0, "segments": 16}, _arc_volume(179.0, 16, 4.0)],
		["four turns of 90", {"iterations": 4}, 4.0 * _arc_volume(90.0, 8, 4.0)],
		[
			"straight 4 in 4",
			{"path": HFFaceSweep.Path.STRAIGHT, "segments": 4},
			_straight_volume(4.0, 1.0, 1.0)
		],
		[
			"straight tapering to 0.5 x 0.25",
			{"path": HFFaceSweep.Path.STRAIGHT, "end_width": 0.5, "end_height": 0.25},
			_straight_volume(4.0, 0.5, 0.25)
		],
		[
			"straight widening to 3 x 2",
			{"path": HFFaceSweep.Path.STRAIGHT, "end_width": 3.0, "end_height": 2.0},
			_straight_volume(4.0, 3.0, 2.0)
		],
		["s bend", {"path": HFFaceSweep.Path.S_BEND}, -1.0],
	]
	for c in cases:
		var root: Node3D = await fresh_root()
		_source(root, Vector3(0, 0.5, 0))
		var made := _sweep(root, _settings(c[1]))
		if not made[0].ok:
			flag("Sweep refused a path it should build: %s" % c[0], made[0].user_text())
			await drop_root(root)
			continue
		var m := _measure(_pieces(root, made[1]))
		var expected: float = c[2]
		note(
			c[0],
			(
				"%d faces, volume %.4f (expected %s), %d open edges, %d turned in, slots %s"
				% [
					m["faces"],
					m["volume"],
					"%.4f" % expected if expected > 0.0 else "-",
					m["open"],
					m["inward"],
					m["slots"]
				]
			)
		)
		if m["open"] > 0 or m["inward"] > 0:
			flag("A swept piece is not a closed outward solid: %s" % c[0], m)
		if expected > 0.0 and absf(float(m["volume"]) - expected) > 0.001:
			flag(
				"The pieces of a sweep do not hold the volume the path makes: %s" % c[0],
				"%.4f against %.4f" % [m["volume"], expected]
			)
		await drop_root(root)


# ---------------------------------------------------------------------------
# Past a half turn
# ---------------------------------------------------------------------------


## The schema, the dialog's spin box and the end handle all allow -360 to 360, and
## the guide says the end handle drags "on past a half turn". An arc of 180 or
## more is refused as folding, with advice that cannot help, while the same arc
## made as two iterations of half of it builds: the angle only reaches the
## geometry as an end frame, and the turn read back off the two frames is never
## more than a half turn (`HFFaceSweep._arc()`).
func _half_turn_and_past() -> void:
	var refused: Array = []
	for angle in [180.0, 270.0, 360.0]:
		var root: Node3D = await fresh_root()
		_source(root, Vector3(0, 0.5, 0))
		var made := _sweep(root, _settings({"angle": angle, "segments": 16}))
		note("arc %d in 16 at radius 4" % angle, made[0].user_text() if not made[0].ok else "built")
		if not made[0].ok:
			refused.append("%d: %s" % [angle, made[0].user_text()])
		await drop_root(root)
	var root: Node3D = await fresh_root()
	_source(root, Vector3(0, 0.5, 0))
	var two := _sweep(root, _settings({"angle": 135.0, "segments": 8, "iterations": 2}))
	var m := _measure(_pieces(root, two[1]))
	note(
		"two iterations of 135 in 8",
		(
			"%s, volume %.4f (expected %.4f), %d open"
			% [two[0].ok, m["volume"], 2.0 * _arc_volume(135.0, 8, 4.0), m["open"]]
		)
	)
	await drop_root(root)
	if not refused.is_empty() and two[0].ok:
		known(
			1968,
			"An arc of 180 degrees or more is refused as folding back, though it does not fold",
			(
				(
					"radius 4, a 1 m face, 16 segments: %s. Two iterations of 135 build the same 270 "
					+ "degrees cleanly, so neither a wider radius nor more segments is the fix"
				)
				% [refused]
			)
		)


# ---------------------------------------------------------------------------
# A taper on a bend
# ---------------------------------------------------------------------------


## Each side takes the look of the face it ran along (#1913). On a straight run a
## tapering side is still flat; on an arc or an S bend a side whose edge narrows
## across the turn is not, the hull splits it in two, and neither half holds all
## four corners `_edges_run_along()` asks for, so both take the swept face's look.
func _taper_on_a_bend() -> void:
	var cases := [
		["straight, height 0.5", {"path": HFFaceSweep.Path.STRAIGHT, "end_height": 0.5}],
		["arc 90, no taper", {}],
		["arc 90, height 0.5", {"end_height": 0.5}],
		# Narrowing toward the pivot leaves the top and bottom flat: the inner and
		# outer walls are the ones it tilts, and they stay upright.
		["arc 90, width 0.5", {"end_width": 0.5}],
		["s bend, height 0.5", {"path": HFFaceSweep.Path.S_BEND, "end_height": 0.5}],
	]
	var lost: Array = []
	for c in cases:
		var root: Node3D = await fresh_root()
		_source(root, Vector3(0, 0.5, 0))
		var made := _sweep(root, _settings(c[1]))
		var pieces := _pieces(root, made[1])
		var m := _measure(pieces)
		var tops := _wrong_tops(pieces)
		note(
			"taper " + c[0],
			(
				"%d faces, %d up or down, %d of them not the source's top or bottom; slots %s"
				% [m["faces"], tops[0], tops[1], m["slots"]]
			)
		)
		if m["open"] > 0 or m["inward"] > 0:
			flag("A tapered swept piece is not a closed outward solid: %s" % c[0], m)
		if tops[1] > 0:
			lost.append("%s: %d of %d" % [c[0], tops[1], tops[0]])
		await drop_root(root)
	if not lost.is_empty():
		known(
			1970,
			"A taper on an arc or an S bend gives the sides it tilts the swept face's look, not their own",
			"top and bottom faces (source slots 3 and 4) that came out in another slot: %s" % [lost]
		)


# ---------------------------------------------------------------------------
# Round trips
# ---------------------------------------------------------------------------


func _round_trips() -> void:
	var root: Node3D = await fresh_root()
	_source(root, Vector3(0, 0.5, 0))
	var empty: Dictionary = root.capture_state()
	var made := _sweep(root, _settings({"end_width": 0.5, "toward": 30.0}))
	var gid: String = made[1]
	var settings: Dictionary = root.generator_for_id(gid).settings.duplicate(true)
	var first := _measure(_pieces(root, gid))
	var after: Dictionary = root.capture_state()
	root.restore_state(empty)
	await frame()
	var undone := (
		"%d brushes, %d structures"
		% [root._iter_managed_brush_nodes().size(), root.generator_count()]
	)
	root.restore_state(after)
	await frame()
	var redone := _measure(_pieces(root, gid))
	var no_op: bool = root.generator_update_changes_nothing(gid, settings)
	note("undo as state", undone)
	note(
		"redo as state", "same pieces %s, Update would change nothing %s" % [redone == first, no_op]
	)
	if undone != "1 brushes, 0 structures" or redone != first or not no_op:
		flag("A sweep does not come back whole through undo and redo", [undone, redone, no_op])
	var again = root.regenerate_generator(gid, settings)
	var rebuilt := _measure(_pieces(root, gid))
	note("Update with unchanged settings", "%s, same pieces %s" % [again.ok, rebuilt == first])
	if not again.ok or rebuilt != first:
		flag("An Update with unchanged settings changes a sweep", [first, rebuilt])

	var path := "user://vibe_sweep_faces.hflevel"
	root.save_hflevel(path, true)
	await HFVibe.settle_save(_tree, root)
	var other: Node3D = await fresh_root("Reopened")
	var loaded: bool = other.load_hflevel(path)
	await frame()
	var record = other.generator_for_id(gid)
	if not loaded or record == null:
		flag("A sweep does not come back from a .hflevel", "loaded %s" % loaded)
	else:
		var back := _measure(_pieces(other, gid))
		var unchanged: bool = other.generator_update_changes_nothing(gid, settings)
		var same_run := HFSweepBuilder.same_run(record.run, root.generator_for_id(gid).run)
		note(
			".hflevel",
			(
				"same pieces %s, same run %s, Update would change nothing %s"
				% [back == first, same_run, unchanged]
			)
		)
		if back != first or not same_run or not unchanged:
			flag("A sweep reads back different from a .hflevel", [first, back, same_run, unchanged])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	await drop_root(other)
	await drop_root(root)


# ---------------------------------------------------------------------------
# Re-pick after a move
# ---------------------------------------------------------------------------


## Re-pick dresses the pieces in the new faces' looks, "keeping only what was
## painted on the pieces by hand" (#1946). A face counts as hand work when it no
## longer matches the look its builder gave it, UV offset and rotation included,
## and texture lock, on by default, rewrites those on every move and turn. So a
## sweep moved into place is a sweep painted all over: Re-pick keeps the old
## wall's looks, and an Update with fewer pieces warns of painted work to lose.
func _repick_after_a_move() -> void:
	var results := {}
	for mode in ["untouched", "nudged", "nudged, texture lock off", "turned"]:
		var root: Node3D = await fresh_root()
		if mode.ends_with("off"):
			root.texture_lock = false
		_source(root, Vector3(0, 0.5, 0))
		var made := _sweep(root, _settings({"path": HFFaceSweep.Path.STRAIGHT, "segments": 3}))
		var gid: String = made[1]
		var ids: Array = Array(root.generator_for_id(gid).brush_ids)
		if mode.begins_with("nudged"):
			root.nudge_brushes_by_id(ids, Vector3(0.25, 0, 5))
		elif mode == "turned":
			root.rotate_managed_nodes(ids, [], 1, 90.0, Vector3(0, 0.5, 0))
		var fewer: Dictionary = root.generator_for_id(gid).settings.duplicate()
		fewer["segments"] = 1
		var at_risk: int = root.generator_appearance_at_risk(gid, fewer).size()
		var wall = box(root, Vector3(1, 1, 1), Vector3(0, 0.5, -20))
		var pick := -1
		for i in wall.faces.size():
			wall.faces[i].material_idx = 11
			if wall.faces[i].normal.normalized().is_equal_approx(Vector3.RIGHT):
				pick = i
		wall.faces[pick].material_idx = 12
		root.face_selection = {_bid(wall): [pick]}
		var read: Dictionary = root.run_from_faces("sweep", root.face_selection)
		var result = root.repick_generator(gid, read["run"], read["placement"])
		var slots: Dictionary = _measure(_pieces(root, gid))["slots"]
		var old := 0
		for slot in slots:
			if int(slot) != 11 and int(slot) != 12:
				old += int(slots[slot])
		results[mode] = old
		note(
			"Re-pick after the sweep was %s" % mode,
			(
				"%s, slots %s: %d of 18 faces kept the old wall's look; Update to 1 segment puts %d pieces at risk"
				% [result.ok, slots, old, at_risk]
			)
		)
		await drop_root(root)
	if results["untouched"] == 0 and (results["nudged"] > 0 or results["turned"] > 0):
		known(
			1969,
			"After a sweep is moved or turned, Re-pick keeps the old wall's looks on faces nobody painted",
			(
				(
					"faces of 18 left in the old look: untouched %d, nudged %d, nudged with texture lock "
					+ "off %d, turned %d. Texture lock rewrites UV offset and rotation, and the as-built "
					+ "test reads that as hand work"
				)
				% [
					results["untouched"],
					results["nudged"],
					results["nudged, texture lock off"],
					results["turned"]
				]
			)
		)
	# The same reading on a staircase: an Update with two fewer steps after a nudge.
	var root: Node3D = await fresh_root()
	var stairs = root.create_generator(
		"stairs",
		HFGeneratorSystem.default_settings("stairs"),
		Transform3D(Basis.IDENTITY, Vector3(0, 0, 0))
	)
	var sid := ""
	for g in root.generator_system.generators:
		sid = str(g)
	var fewer_steps: Dictionary = root.generator_for_id(sid).settings.duplicate()
	fewer_steps["steps"] = int(fewer_steps["steps"]) - 2
	var before_move: int = root.generator_appearance_at_risk(sid, fewer_steps).size()
	root.nudge_brushes_by_id(Array(root.generator_for_id(sid).brush_ids), Vector3(0.25, 0, 3))
	var after_move: int = root.generator_appearance_at_risk(sid, fewer_steps).size()
	note(
		"stairs, two fewer steps",
		(
			"%s; pieces at risk %d before a nudge, %d after, nothing painted"
			% [stairs.ok, before_move, after_move]
		)
	)
	if before_move == 0 and after_move > 0:
		known(
			1969,
			"Moving a structure makes an Update warn of painted work on pieces nobody painted",
			(
				"a default staircase nudged by (0.25, 0, 3): %d steps at risk for two fewer steps"
				% after_move
			)
		)
	await drop_root(root)


# ---------------------------------------------------------------------------
# Odd sources
# ---------------------------------------------------------------------------


func _odd_sources() -> void:
	# A Re-pick onto a face of a turned box far from the origin: the pieces start on
	# the face and end 4 along its normal.
	var root: Node3D = await fresh_root()
	_source(root, Vector3(0, 0.5, 0))
	var made := _sweep(root, _settings({"path": HFFaceSweep.Path.STRAIGHT, "segments": 3}))
	var gid: String = made[1]
	var at := Vector3(3000, 1, -2000)
	var far = box(root, Vector3(1, 2, 1), at)
	root.rotate_managed_nodes([_bid(far)], [], 1, 30.0, at)
	var pick := -1
	for i in far.faces.size():
		if far.faces[i].normal.normalized().is_equal_approx(Vector3.RIGHT):
			pick = i
	root.face_selection = {_bid(far): [pick]}
	var read: Dictionary = root.run_from_faces("sweep", root.face_selection)
	var result = root.repick_generator(gid, read["run"], read["placement"])
	var pieces := _pieces(root, gid)
	var normal: Vector3 = (far.global_basis * far.faces[pick].normal).normalized()
	var start: Array = []
	var finish: Array = []
	for v in far.faces[pick].local_verts:
		var w: Vector3 = far.global_transform * v
		start.append(w.snapped(Vector3.ONE * 0.001))
		finish.append((w + normal * 4.0).snapped(Vector3.ONE * 0.001))
	start.sort()
	finish.sort()
	var has_start := false
	var has_finish := false
	for p in pieces:
		for f in p.faces:
			var corners: Array = []
			for v in f.local_verts:
				corners.append((p.global_transform * v).snapped(Vector3.ONE * 0.001))
			corners.sort()
			has_start = has_start or corners == start
			has_finish = has_finish or corners == finish
	var m := _measure(pieces)
	note(
		"Re-pick onto a turned 1 x 2 face at %s" % at,
		(
			"%s, volume %.4f (8 expected), starts on the face %s, ends 4 along it %s, %d open"
			% [result.ok, m["volume"], has_start, has_finish, m["open"]]
		)
	)
	if not result.ok or not has_start or not has_finish or m["open"] > 0:
		flag("A Re-pick far from the origin does not sweep from the face picked", m)
	await drop_root(root)

	# Hidden, the smoothing group and the UV rotation of a side, from a brush tied
	# to a door.
	root = await fresh_root()
	var b = _source(root, Vector3(0, 0.5, 0))
	for f in b.faces:
		if f.normal.normalized().is_equal_approx(Vector3.UP):
			f.face_type = FaceData.FaceType.HIDDEN
			f.smoothing_group = 3
			f.uv_rotation = 30.0
	root.tie_brushes_to_entity([_bid(b)], "func_door", "door1")
	made = _sweep(root, _settings({"path": HFFaceSweep.Path.STRAIGHT, "segments": 2}))
	var hidden := 0
	var tied := 0
	pieces = _pieces(root, made[1])
	for p in pieces:
		if str(p.get_meta("brush_entity_class", "")) != "":
			tied += 1
		for f in p.faces:
			if f.face_type == FaceData.FaceType.HIDDEN and f.smoothing_group == 3:
				if is_equal_approx(f.uv_rotation, 30.0):
					hidden += 1
	note(
		"a hidden top on a door's brush",
		(
			"%d of %d pieces carry the hidden top whole; %d pieces tied to the door, which is plain geometry by design"
			% [hidden, pieces.size(), tied]
		)
	)
	if hidden != pieces.size():
		flag("A sweep drops part of a side's look (#1954)", "%d of %d" % [hidden, pieces.size()])
	await drop_root(root)
