@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## `validate_level()` is the editor's own answer to "is this level sound?". It
## is what the validation badge in the dock reports and what a mapper runs
## before a bake.
##
## So the interesting question is not whether it works -- it is what a level can
## be wrong in that it says nothing about. Each case here breaks the level in
## one specific way, asks the validator, and records whether the report mentions
## it. A defect the validator misses is a defect that ships, because the mapper
## has been told the level is clean.


func id() -> String:
	return "validation"


func summary() -> String:
	return "what validate_level() reports, and what it says nothing about"


func run() -> void:
	await _a_clean_level_is_clean()
	await _a_non_finite_brush_size()
	await _a_brush_with_no_faces()
	await _a_face_bowed_out_of_plane()
	await _non_finite_vertices()
	await _the_repair_functions_nothing_calls()


func _bid(node: Node) -> String:
	return str(node.get_meta("brush_id", ""))


func _issues(root: Node3D) -> Array:
	var report: Dictionary = root.validate_level(false)
	return report.get("issues", [])


func _mentions(issues: Array, needle: String) -> bool:
	for i in issues:
		if str(i).to_lower().contains(needle.to_lower()):
			return true
	return false


func _a_clean_level_is_clean() -> void:
	var root: Node3D = await fresh_root()
	box(root, Vector3(64, 64, 64))
	await frame()
	var issues := _issues(root)
	note("a level with one untouched box", "%d issue(s): %s" % [issues.size(), issues])
	if not issues.is_empty():
		flag("validate_level reports issues on a level with one default box", issues)


## The zero-size check is `size.x <= 0.0 or ...`. Every comparison against NaN is
## false, so the check that exists for exactly this class of broken brush cannot
## see the worst member of it.
func _a_non_finite_brush_size() -> void:
	for bad in [Vector3(NAN, 64, 64), Vector3(64, INF, 64), Vector3(NAN, NAN, NAN)]:
		var root: Node3D = await fresh_root()
		var b := box(root, Vector3(64, 64, 64))
		b.size = bad
		await frame()
		var issues := _issues(root)
		note("brush size %s" % bad, "%d issue(s): %s" % [issues.size(), issues])
		if not _mentions(issues, "brush"):
			known(
				371,
				"validate_level says nothing about a brush whose size is not a number",
				(
					"size %s, report: %s -- the zero-size check is written as `size.x <= 0.0`, and NaN fails every comparison, so the one check aimed at this class of brush is the one that cannot see it"
					% [bad, issues]
				)
			)


## A brush with every face removed. `merge_vertices()` produces one (see #366),
## and so does a `.hflevel` whose face list did not survive.
func _a_brush_with_no_faces() -> void:
	var root: Node3D = await fresh_root()
	var b := box(root, Vector3(64, 64, 64))
	b.faces.clear()
	await frame()
	var issues := _issues(root)
	note("a brush with no faces", "%d issue(s): %s" % [issues.size(), issues])
	if issues.is_empty():
		known(
			372,
			"validate_level reports nothing about a brush with no faces",
			"the brush is live, selectable, saved and exported, and has no geometry at all"
		)


## `HFValidationSystem.fix_non_planar_faces()` exists, so a bowed face is a
## known-bad state. `validate()` never looks for one.
func _a_face_bowed_out_of_plane() -> void:
	var root: Node3D = await fresh_root()
	var b := box(root, Vector3(64, 64, 64))
	var vs = root.vertex_system
	vs.select_vertex(_bid(b), 0)
	vs.move_vertices(Vector3(0, -256, 0))
	await frame()

	var worst := 0.0
	for face in b.faces:
		if face == null or face.local_verts.size() < 4:
			continue
		var fv: PackedVector3Array = face.local_verts
		var n: Vector3 = (fv[1] - fv[0]).cross(fv[2] - fv[0])
		if n.length() < 0.0001:
			continue
		n = n.normalized()
		for v in fv:
			worst = maxf(worst, absf(n.dot(v - fv[0])))

	var issues := _issues(root)
	note("worst face non-planarity", "%.1f units" % worst)
	note("what the validator says", "%d issue(s): %s" % [issues.size(), issues])
	if worst > 1.0 and not _mentions(issues, "planar"):
		known(
			372,
			"validate_level reports nothing about a face bowed out of plane",
			(
				"a face sits %.1f units off its own plane and the report is %s -- the system has fix_non_planar_faces() for exactly this, and validate() never calls it"
				% [worst, issues]
			)
		)


## A NaN vertex position, which #365 shows a vertex move will happily write.
func _non_finite_vertices() -> void:
	var root: Node3D = await fresh_root()
	var b := box(root, Vector3(64, 64, 64))
	var poisoned := PackedVector3Array()
	for v in b.faces[0].local_verts:
		poisoned.append(v)
	poisoned[0] = Vector3(NAN, NAN, NAN)
	b.faces[0].local_verts = poisoned
	b.faces[0].ensure_geometry()
	await frame()

	var issues := _issues(root)
	note("a face with a NaN vertex", "%d issue(s): %s" % [issues.size(), issues])
	if issues.is_empty():
		known(
			372,
			"validate_level reports nothing about a face with a non-finite vertex",
			"the brush's AABB, its face normal and everything computed from them are now NaN, and the level is reported clean"
		)


## Two repair routines exist on the validation system and are covered by the GUT
## suite. Whether anything in the editor can reach them is a different question.
func _the_repair_functions_nothing_calls() -> void:
	var root: Node3D = await fresh_root()
	var vsys = root.validation_system
	for fn in ["fix_non_planar_faces", "weld_brush_vertices", "check_occlusion_coverage"]:
		note("validation system has %s" % fn, vsys.has_method(fn))

	# A bowed brush, then the repair, run by hand.
	var b := box(root, Vector3(64, 64, 64))
	root.vertex_system.select_vertex(_bid(b), 0)
	root.vertex_system.move_vertices(Vector3(0, -256, 0))
	await frame()
	var fixed: int = vsys.fix_non_planar_faces(b)
	var report: Dictionary = root.validate_level(true)
	note("fix_non_planar_faces called directly", "repaired %d face(s)" % fixed)
	note("validate_level(auto_fix = true)", "fixed %d" % report.get("fixed", 0))
	if fixed > 0 and int(report.get("fixed", 0)) == 0:
		known(
			372,
			"the auto-fix pass does not use the geometry repairs the validation system already has",
			(
				"fix_non_planar_faces() repaired %d face(s) when called by hand, and validate_level(auto_fix = true) repaired 0 -- neither it nor weld_brush_vertices() has any caller outside tests/"
				% fixed
			)
		)
