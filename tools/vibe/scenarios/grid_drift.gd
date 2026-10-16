@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Whether a decimal grid stays a grid.
##
## The project is on metric scale, so the grids a mapper actually uses are 0.1,
## 0.25 and 0.05 -- none of which a float32 can hold exactly. A brush that has
## been nudged a thousand times, resized, turned all the way round, mirrored
## twice, arrayed, saved and loaded, and sent out to a `.map` and back has been
## through a lot of float arithmetic. The question is whether it is still on the
## grid it was drawn on, and whether two brushes drawn to touch still touch:
## `_check_micro_gaps()` reports two vertices between 1e-5 and the weld tolerance
## apart as a micro-gap, so drift in that band turns into a Validate finding about
## a level nobody edited badly.
##
## Every measurement is against the exact expected value worked out here, not
## against what the operation reported. Errors are given in metres and in float32
## ulps at that coordinate, because a float32 cannot do better than half an ulp
## and anything within a couple of ulps is the type, not the code.

const HFLP := "user://grid-drift.hflevel"
const MAP_Q := "user://grid-drift_quake.map"
const MAP_V := "user://grid-drift_valve.map"
const MAP_M := "user://grid-drift_metres.map"

var _worst: Dictionary = {}


func id() -> String:
	return "grid-drift"


func summary() -> String:
	return "whether a decimal grid stays on the grid through nudges, resizes, saves and exports"


func run() -> void:
	for g in [0.1, 0.25, 0.05]:
		await _one_grid(g)
	await _nudged_then_butted()
	await _what_the_map_writes()
	for path in [HFLP, MAP_Q, MAP_V, MAP_M]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	note("worst error per stage, metres", _worst)


# ---------------------------------------------------------------------------
# Measuring
# ---------------------------------------------------------------------------


func _bid(node: Node) -> String:
	return str(node.get_meta("brush_id", ""))


## A float in scientific notation, which `%` formatting does not offer.
static func _e(v: float) -> String:
	if v == 0.0:
		return "0"
	var power := floori(log(absf(v)) / log(10.0))
	return "%.2fe%d" % [v / pow(10.0, power), power]


## The float32 spacing at `v`: what one rounding can cost there.
static func _ulp(v: float) -> float:
	var a := absf(v)
	if a < 1e-30:
		return 1.4e-45
	return pow(2.0, floor(log(a) / log(2.0)) - 23.0)


## World-space corners of a brush's own face geometry.
static func _world_box(brush: Node) -> AABB:
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for f in brush.faces:
		for v in f.local_verts:
			var w: Vector3 = brush.global_transform * v
			lo = lo.min(w)
			hi = hi.max(w)
	return AABB(lo, hi - lo)


## How far each corner of `box` is from where it should be, worst axis.
static func _box_error(box: AABB, want: AABB) -> float:
	var e := (box.position - want.position).abs()
	var f := (box.end - want.end).abs()
	return maxf(maxf(e.x, maxf(e.y, e.z)), maxf(f.x, maxf(f.y, f.z)))


## How far each corner of `box` is from the nearest grid line, worst axis.
static func _off_grid(box: AABB, g: float) -> float:
	var worst := 0.0
	for v in [box.position, box.end]:
		for axis in 3:
			var c: float = v[axis]
			worst = maxf(worst, absf(c - roundf(c / g) * g))
	return worst


func _record(stage: String, err: float) -> void:
	_worst[stage] = maxf(float(_worst.get(stage, 0.0)), err)


func _say(g: float, stage: String, box: AABB, want: AABB) -> float:
	var err := _box_error(box, want)
	var far := maxf(box.end.abs().x, maxf(box.end.abs().y, box.end.abs().z))
	var off := _off_grid(box, g)
	note(
		"grid %s, %s" % [g, stage],
		(
			"corner error %s m (%.1f ulp at %.2f), off grid %s m"
			% [_e(err), err / _ulp(far), far, _e(off)]
		)
	)
	_record(stage, err)
	return err


## The gap between `left`'s +x face and `right`'s -x face, measured on the faces.
static func _gap(left: Node, right: Node) -> float:
	return _world_box(right).position.x - _world_box(left).end.x


## The micro-gap findings of the dock's Check Issues button. `validate_level()`
## does not run the micro-gap check; `check_bake_issues()` does.
func _micro_gaps(root: Node3D) -> Array:
	var out: Array = []
	for issue in root.validation_system.check_bake_issues():
		if issue is Dictionary and str(issue.get("type", "")) == "micro_gap":
			out.append(str(issue.get("message", "")))
	return out


# ---------------------------------------------------------------------------
# One grid, every operation
# ---------------------------------------------------------------------------


func _one_grid(g: float) -> void:
	note("-- grid %s --" % g)
	var root: Node3D = await fresh_root("Grid%s" % str(g).replace(".", "_"))
	root.grid_snap = g
	note("grid_snap reads back", root.grid_snap)
	# A brush drawn on the grid: 3 x 2 x 4 cells, its low corner on (1, 0, 1) cells.
	var size := Vector3(3 * g, 2 * g, 4 * g)
	var low := Vector3(g, 0, g)
	var b = box(root, size, low + size / 2.0)
	# Its neighbour, drawn to touch it on +x: 4 cells wide, same height and depth.
	var n_size := Vector3(4 * g, 2 * g, 4 * g)
	var n = box(
		root,
		n_size,
		Vector3(low.x + size.x + n_size.x / 2.0, low.y + size.y / 2.0, low.z + size.z / 2.0)
	)
	await frame()
	var home := _world_box(b)
	var n_home := _world_box(n)
	var both: Array = [_bid(b), _bid(n)]
	_say(g, "as drawn", home, AABB(low, size))
	note("grid %s, gap between the butted pair as drawn" % g, "%s m" % _e(_gap(b, n)))

	# 1000 arrow-key nudges right, then 1000 back, both brushes selected.
	for i in 1000:
		root.nudge_brushes_by_id(both, Vector3(g, 0, 0))
	var far_want := AABB(home.position + Vector3(1000 * g, 0, 0), home.size)
	_say(g, "after 1000 nudges right", _world_box(b), far_want)
	note("grid %s, butted gap 1000 cells out" % g, "%s m" % _e(_gap(b, n)))
	for i in 1000:
		root.nudge_brushes_by_id(both, Vector3(-g, 0, 0))
	_say(g, "after 1000 nudges back", _world_box(b), home)
	note("grid %s, butted gap back home" % g, "%s m" % _e(_gap(b, n)))

	# A face drag of one cell on +y, 100 times, then 100 back: the low face stays.
	var bottom: float = _world_box(b).position.y
	for i in 100:
		root.set_brush_transform_by_id(
			_bid(b), b.size + Vector3(0, g, 0), b.global_position + Vector3(0, g / 2.0, 0)
		)
	_say(
		g,
		"after 100 one-cell resizes up",
		_world_box(b),
		AABB(home.position, home.size + Vector3(0, 100 * g, 0))
	)
	for i in 100:
		root.set_brush_transform_by_id(
			_bid(b), b.size - Vector3(0, g, 0), b.global_position - Vector3(0, g / 2.0, 0)
		)
	_say(g, "after 100 resizes back down", _world_box(b), home)
	note("grid %s, size after the resizes" % g, "%s (drawn %s)" % [b.size, size])
	note("grid %s, low face moved by" % g, "%s m" % _e(absf(_world_box(b).position.y - bottom)))

	# 24 turns of 15 degrees about Y, the pair together about their joint centre.
	var pivot: Vector3 = root.resolve_transform_pivot(both, [])
	for i in 24:
		root.rotate_managed_nodes(both, [], 1, 15.0, pivot)
	await frame()
	_say(g, "after 24 x 15 degree turns", _world_box(b), home)
	var basis_err: float = (b.global_transform.basis.x - Vector3.RIGHT).length()
	basis_err = maxf(basis_err, (b.global_transform.basis.z - Vector3.BACK).length())
	note("grid %s, basis off identity after the full turn" % g, _e(basis_err))
	note("grid %s, butted gap after the full turn" % g, "%s m" % _e(_gap(b, n)))

	# A flip pair on X about the same pivot.
	root.flip_managed_nodes(both, [], 0, pivot)
	root.flip_managed_nodes(both, [], 0, pivot)
	await frame()
	_say(g, "after a flip pair", _world_box(b), home)
	note("grid %s, butted gap after the flips" % g, "%s m" % _e(_gap(b, n)))

	# A duplicate array of ten, one brush width plus a cell apart.
	var step := Vector3(size.x + g, 0, 0)
	var before_ids := {}
	for c in root.draft_brushes_node.get_children():
		before_ids[_bid(c)] = true
	var dup = root.create_duplicate_array(PackedStringArray([_bid(b)]), 10, step)
	await frame()
	var worst_copy := 0.0
	var worst_off := 0.0
	var copies := 0
	var here := _world_box(b)
	for c in root.draft_brushes_node.get_children():
		if before_ids.has(_bid(c)):
			continue
		copies += 1
		var box := _world_box(c)
		var k := roundf((box.position.x - here.position.x) / step.x)
		worst_copy = maxf(worst_copy, _box_error(box, AABB(here.position + step * k, here.size)))
		worst_off = maxf(worst_off, _off_grid(box, g))
	note(
		"grid %s, duplicate array" % g,
		(
			"%d copies, worst corner error %s m, worst off grid %s m"
			% [copies, _e(worst_copy), _e(worst_off)]
		)
	)
	_record("duplicate array", worst_copy)
	if dup != null and root.has_method("remove_duplicate_array"):
		root.remove_duplicate_array(str(dup.duplicator_id))
		await frame()

	var gaps_now: Array = _micro_gaps(root)
	note("grid %s, Validate micro-gaps after the edits" % g, gaps_now)

	# .hflevel round trip.
	var before_save := [_world_box(b), _world_box(n)]
	root.save_hflevel(HFLP, true)
	await HFVibe.settle_save(_tree, root)
	root.clear_brushes()
	await frame()
	root.load_hflevel(HFLP)
	await frame()
	var loaded := _sorted_brushes(root)
	if loaded.size() == 2:
		_say(g, "after a .hflevel round trip", _world_box(loaded[0]), before_save[0])
		note("grid %s, butted gap after the load" % g, "%s m" % _e(_gap(loaded[0], loaded[1])))
	else:
		flag("the .hflevel round trip brought back %d brushes, not 2" % loaded.size())

	# .map round trip in both formats, into a fresh level.
	for pair in [["quake", MAP_Q], ["valve220", MAP_V]]:
		root.export_map(pair[1], pair[0])
		var other: Node3D = await fresh_root("MapBack")
		other.import_map(pair[1])
		await frame()
		var back := _sorted_brushes(other)
		if back.size() != 2:
			flag("a %s .map round trip brought back %d brushes" % [pair[0], back.size()])
		else:
			_say(g, "after a %s .map round trip" % pair[0], _world_box(back[0]), before_save[0])
			var gap := _gap(back[0], back[1])
			note("grid %s, butted gap after %s .map" % [g, pair[0]], "%s m" % _e(gap))
			var mg: Array = _micro_gaps(other)
			note("grid %s, Validate micro-gaps after %s .map" % [g, pair[0]], mg)
			if not mg.is_empty():
				flag(
					(
						"a butted pair on a %s grid comes back from a %s .map with a micro-gap Validate reports"
						% [g, pair[0]]
					),
					"gap %s m; %s" % [_e(gap), mg]
				)
		await drop_root(other)

	for problem in HFVibe.check_invariants(root):
		flag("grid %s broke an invariant" % g, problem)
	var final_gaps: Array = _micro_gaps(root)
	if not final_gaps.is_empty():
		flag("a butted pair on a %s grid drifts into a micro-gap Validate reports" % g, final_gaps)
	await drop_root(root)


func _sorted_brushes(root: Node3D) -> Array:
	var out: Array = []
	for c in root.draft_brushes_node.get_children():
		if root.is_brush_node(c):
			out.append(c)
	out.sort_custom(func(x, y): return _world_box(x).position.x < _world_box(y).position.x)
	return out


# ---------------------------------------------------------------------------
# A nudged brush against a brush drawn on the grid afterwards
# ---------------------------------------------------------------------------


## The pair above moves together, so whatever it drifts it drifts as one and the
## gap between them stays inside float noise. The case that bites is the brush
## drawn *after* the nudging: it goes where the grid says, and the nudged one is
## no longer there. Nudge one brush N cells right from a grid line at `start`,
## draw its neighbour on the grid where its +x face should be, and ask Validate.
func _nudged_then_butted() -> void:
	note("-- one brush nudged N cells on the 0.1 grid, then a neighbour drawn on the grid --")
	var g := 0.1
	var first_reported := {}
	for start in [2.0, 20.0, 60.0]:
		for count in [10, 30, 100, 300]:
			var root: Node3D = await fresh_root("Nudged")
			root.grid_snap = g
			var size := Vector3(4 * g, 3 * g, 4 * g)
			var b = box(root, size, Vector3(start + size.x / 2.0, size.y / 2.0, 0))
			await frame()
			for i in count:
				root.nudge_brushes_by_id([_bid(b)], Vector3(g, 0, 0))
			# Where the +x face should be: a grid line, worked out in double precision.
			var face_should: float = start + size.x + count * g
			var face_is: float = _world_box(b).end.x
			var neighbour = box(root, size, Vector3(face_should + size.x / 2.0, size.y / 2.0, 0))
			await frame()
			var gap: float = _world_box(neighbour).position.x - face_is
			var gaps: Array = _micro_gaps(root)
			note(
				"from x=%s, %d nudges" % [start, count],
				(
					"face at %.7f, should be %.7f: off by %s m (%.0f ulp); Validate micro-gaps %d"
					% [
						face_is,
						face_should,
						_e(absf(face_is - face_should)),
						absf(face_is - face_should) / _ulp(face_should),
						gaps.size()
					]
				)
			)
			if not gaps.is_empty() and not first_reported.has(start):
				first_reported[start] = [count, gap]
			await drop_root(root)
	note(
		"fewest nudges (of those tried) before Validate reports the pair, by start x",
		first_reported
	)
	if not first_reported.is_empty():
		known(
			1203,
			"[Build] Arrow-key nudges add the grid step in float32 and never put the brush back on the grid, so a brush drawn beside it later is a micro-gap",
			(
				(
					"on the 0.1 grid each nudge is `draft.global_position + offset` "
					+ "(hf_brush_system.gd:301, `nudge_brushes_by_id`), a float32 add whose rounding "
					+ "leans the same way every press, so the error grows with the count instead of "
					+ "averaging out: 1000 presses right from x=0.1 leave the face 0.95 mm off its grid "
					+ "line (125 ulp at 100 m). A brush drawn on the grid against it afterwards is then "
					+ "between `_touching_distance()` and the 1 mm weld tolerance, and Validate reports a "
					+ "micro-gap the mapper never made. First reported (nudges, gap m) by start x: %s. "
					+ "0.25 and 0.5 grids are exact in binary and never drift"
				)
				% [first_reported]
			)
		)


# ---------------------------------------------------------------------------
# The number itself
# ---------------------------------------------------------------------------


## A brush whose low x face is at 0.3, written out in Quake units and in metres.
func _what_the_map_writes() -> void:
	note("-- what the .map says for a face at x = 0.3 --")
	var root: Node3D = await fresh_root("PointThree")
	root.grid_snap = 0.1
	var b = box(root, Vector3(0.2, 0.2, 0.2), Vector3(0.4, 0.1, 0.1))
	await frame()
	note("the face as a float32 holds it", "%.9f" % _world_box(b).position.x)
	root.export_map(MAP_Q, "quake")
	root.export_map(MAP_M, "quake", 1.0)
	for path in [MAP_Q, MAP_M]:
		var text := FileAccess.get_file_as_string(path)
		var lines: Array = []
		for line in text.split("\n"):
			if line.begins_with("("):
				lines.append(
					line.substr(0, line.find(")", line.find(")", line.find(")") + 1) + 1) + 1)
				)
		note("%s plane points" % path.get_file(), lines.slice(0, 2))
		var long_decimal := RegEx.create_from_string("\\(([^)]*\\d\\.\\d{5,}[^)]*)\\)")
		var hit := long_decimal.search(text)
		if hit:
			flag(
				"the .map writes a coordinate with float32 noise in it",
				"%s: '%s'" % [path.get_file(), hit.get_string()]
			)
	await drop_root(root)
