@tool
class_name HFSweepBuilder
extends RefCounted
## Sweep Faces as a structure (#1885): the picked faces carried along a straight
## run, an arc or an S bend, kept so it can be changed after it is made.
##
## A sweep was final once made: its values were gone the moment OK was pressed, so
## eight segments that looked faceted, or a radius a little tight, meant deleting
## the pieces and sweeping again, and any texture work done on them since. Now OK
## records it with `HFGeneratorSystem` as a type that follows a run, as Trim Run
## does (#1414): the run is the picked faces, and the dialog's values are its
## settings. Selecting a piece shows them in the Structure section, and a change
## rebuilds it in place in one undo step.
##
## A run is plain data, as a level file holds it, in the space of the sweep's
## start frame, so it moves with the structure:
##
##     {"rings": [[[x, y, z], ...], ...], "looks": [{"swept": look, "sides": [look or null, ...]}, ...]}
##
## each ring a picked face's corners, all in the frame's XY plane facing +Z, and
## beside it the look of that face and of the face of its brush along each edge
## (`LOOK_KEYS`), which the sides take (#1899).

# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const FaceData = preload("face_data.gd")
const HFGeneratorSchema = preload("hf_generator_schema.gd")
const HFOpResult = preload("hf_op_result.gd")
@warning_ignore_restore("shadowed_global_identifier")
const HFFaceSweep = preload("hf_face_sweep.gd")

## Which way an arc turns or an S bend steps aside is an angle in the faces'
## plane, in degrees from the faces' own right toward their up, so a pivot dragged
## any way along the faces turns the run that way. These name the four the dialog
## used to offer.
const TOWARD_DEGREES := {"Right": 0.0, "Up": 90.0, "Left": 180.0, "Down": 270.0}
## The Radius field's step, which a dragged pivot lands on.
const RADIUS_STEP := 0.01

## What a face's look is: the fields `FaceData.copy_appearance_from()` copies and
## `FaceData.appearance_matches()` compares, Hidden and the smoothing group among
## them (#1934). A level saved before they were here reads without them.
const LOOK_KEYS := [
	"material_idx",
	"map_texture",
	"face_type",
	"uv_projection",
	"legacy_wall_axes",
	"uv_scale",
	"uv_offset",
	"uv_rotation",
	"smoothing_group",
]


static func settings_schema() -> Array:
	return [
		{
			"key": "path",
			"label": "Path",
			"type": HFGeneratorSchema.TYPE_ENUM,
			"options": HFFaceSweep.PATH_NAMES.duplicate(),
			"default": HFFaceSweep.Path.ARC,
			"tooltip": "A straight run, a circular arc, or an S bend",
		},
		_number(
			"length", "Length", 0.1, 1000.0, 0.1, 4.0, "How far a straight run or an S bend goes"
		),
		_number("angle", "Angle", -360.0, 360.0, 1.0, 90.0, "How far an arc turns, in degrees"),
		# Steps a dragged pivot lands on, so a field read back keeps it (#1885).
		_number(
			"radius",
			"Radius",
			0.1,
			1000.0,
			RADIUS_STEP,
			4.0,
			"How far from the faces an arc turns about"
		),
		_number("offset", "Offset", -1000.0, 1000.0, 0.1, 2.0, "How far aside an S bend steps"),
		_number(
			"toward",
			"Toward",
			-360.0,
			360.0,
			1.0,
			0.0,
			"Which way along the faces an arc turns or an S bend steps: 0 right, 90 up"
		),
		{
			"key": "segments",
			"label": "Segments",
			"type": HFGeneratorSchema.TYPE_INT,
			"min": 1,
			"max": HFFaceSweep.MAX_SEGMENTS,
			"step": 1,
			"default": 8,
			"tooltip": "How many pieces the run is cut into",
		},
		{
			"key": "iterations",
			"label": "Iterations",
			"type": HFGeneratorSchema.TYPE_INT,
			"min": 1,
			"max": HFFaceSweep.MAX_ITERATIONS,
			"step": 1,
			"default": 1,
			"tooltip": "How many times the sweep repeats from where it ended",
		},
		_number(
			"end_width",
			"End width scale",
			0.05,
			20.0,
			0.05,
			1.0,
			"How wide the far end is, as a part of the start"
		),
		_number(
			"end_height",
			"End height scale",
			0.05,
			20.0,
			0.05,
			1.0,
			"How tall the far end is, as a part of the start"
		),
	]


static func _number(
	key: String, label: String, low: float, high: float, step: float, start: float, tip: String
) -> Dictionary:
	return {
		"key": key,
		"label": label,
		"type": HFGeneratorSchema.TYPE_FLOAT,
		"min": low,
		"max": high,
		"step": step,
		"default": start,
		"tooltip": tip,
	}


static func default_settings() -> Dictionary:
	return HFGeneratorSchema.defaults(settings_schema())


## The settings alone: every field's range is the schema's. What a sweep cannot
## do is bend its faces tighter than they are wide, which `check_along()` answers.
static func validate(_settings: Dictionary) -> HFOpResult:
	return HFOpResult.success()


# ===========================================================================
# Reading a run from faces
# ===========================================================================


## The run of `picked` faces, read in world space: each `{"verts", "normal",
## "look", "sides"}`, its corners, its outward normal, its look, and the look of
## its brush's face along each edge. `{"run", "placement"}` with the run in the
## space of the sweep's start frame, or `{"refused", "hint"}`.
static func read(picked: Array) -> Dictionary:
	if picked.is_empty():
		return _refused("Sweep: pick the faces to sweep in Face Select first", "")
	var rings: Array = []
	var normal: Vector3 = picked[0]["normal"]
	var first: PackedVector3Array = picked[0]["verts"]
	var plane := Plane(normal, first[0])
	for face: Dictionary in picked:
		var ring: PackedVector3Array = face["verts"]
		var facing: Vector3 = face["normal"]
		if facing.dot(normal) < 0.999 or absf(plane.distance_to(ring[0])) > 0.001:
			return _refused(
				"Sweep: pick faces that lie in one plane, facing one way",
				"Pick faces of one wall, floor or end"
			)
		rings.append(ring)
	var start := HFFaceSweep.start_frame(rings, normal)
	var to_start := start.affine_inverse()
	var plain_rings: Array = []
	var looks: Array = []
	for i in picked.size():
		var ring: Array = []
		for corner in rings[i] as PackedVector3Array:
			ring.append(_plain(to_start * corner))
		plain_rings.append(ring)
		looks.append(
			{"swept": picked[i]["look"], "sides": (picked[i]["sides"] as Array).duplicate()}
		)
	# `used` and `hidden` as a Trim Run's read gives them, for the message a
	# Re-pick shows: a sweep takes every face picked and leaves none out (#1932).
	return {
		"run": {"rings": plain_rings, "looks": looks},
		"placement": start,
		"used": picked.size(),
		"hidden": PackedStringArray(),
	}


## The run as it reads in the space `placement` sets up: every corner carried back
## through the placement. The looks are not where anything is, so they stay.
static func in_space(run: Dictionary, placement: Transform3D) -> Dictionary:
	var back := placement.affine_inverse()
	var rings: Array = []
	for ring in rings_of(run):
		var plain: Array = []
		for corner in ring as PackedVector3Array:
			plain.append(_plain(back * corner))
		rings.append(plain)
	return {"rings": rings, "looks": (run.get("looks", []) as Array).duplicate(true)}


## Two runs that build the same sweep: the same faces, read to a thousandth, in
## the same looks. What a Re-pick asks before it rebuilds (#1932).
static func same_run(a: Dictionary, b: Dictionary) -> bool:
	return _run_text(a) == _run_text(b)


static func _run_text(run: Dictionary) -> String:
	var parts := PackedStringArray()
	for ring in rings_of(run):
		parts.append("ring")
		for corner in ring as PackedVector3Array:
			parts.append("%.3f %.3f %.3f" % [corner.x, corner.y, corner.z])
	parts.append(_value_text(run.get("looks", [])))
	return ",".join(parts)


## A look as text that reads the same after a save: a whole number read back as a
## float, and a float to a ten thousandth.
static func _value_text(value: Variant) -> String:
	if value is int or value is float:
		return "%.4f" % float(value)
	if value is Array:
		var parts := PackedStringArray()
		for item in value:
			parts.append(_value_text(item))
		return "[%s]" % ",".join(parts)
	if value is Dictionary:
		var keys: Array = (value as Dictionary).keys()
		keys.sort()
		var parts := PackedStringArray()
		for key in keys:
			parts.append("%s:%s" % [key, _value_text(value[key])])
		return "{%s}" % ",".join(parts)
	return str(value)


## `face`'s look, as plain data a level file holds.
static func look_of(face: FaceData) -> Dictionary:
	var out := {}
	for key in LOOK_KEYS:
		var value = face.get(key)
		if value is Vector2:
			value = [value.x, value.y]
		out[key] = value
	return out


## For each edge of `face`, from corner i to i + 1, the look of the other face of
## `faces` holding both its corners, or null.
static func side_looks(faces: Array, face: FaceData) -> Array:
	var out: Array = []
	var corners: PackedVector3Array = face.local_verts
	for i in corners.size():
		var a := corners[i]
		var b := corners[(i + 1) % corners.size()]
		var found: Variant = null
		for other in faces:
			if other == null or other == face:
				continue
			var has_a := false
			var has_b := false
			for corner in (other as FaceData).local_verts:
				has_a = has_a or corner.distance_to(a) <= 0.001
				has_b = has_b or corner.distance_to(b) <= 0.001
			if has_a and has_b:
				found = look_of(other)
				break
		out.append(found)
	return out


# ===========================================================================
# Building along a run
# ===========================================================================


## What sweeping the run with `settings` makes, in the start frame's space:
## `{pieces, folded, frames}` as `HFFaceSweep.pieces()` gives them.
static func plan(settings: Dictionary, run: Dictionary) -> Dictionary:
	var merged := HFGeneratorSchema.merge(settings_schema(), settings)
	var path := int(merged["path"])
	var toward := toward_of(float(merged["toward"]))
	var angle := float(merged["angle"])
	var radius := float(merged["radius"])
	var start := Transform3D.IDENTITY
	var end := HFFaceSweep.end_frame(
		start, path, float(merged["length"]), angle, radius, float(merged["offset"]), toward
	)
	# An arc turns by the Angle itself, not by what the end frame reads back as,
	# which is never past a half turn (#1968).
	var turn := {}
	if path == HFFaceSweep.Path.ARC:
		turn = HFFaceSweep.arc_turn(start, angle, radius, toward)
	var frame_list := HFFaceSweep.frames(path, start, end, int(merged["segments"]), turn)
	frame_list = HFFaceSweep.repeated(frame_list, int(merged["iterations"]))
	var end_scale := Vector2(float(merged["end_width"]), float(merged["end_height"]))
	var backward := path == HFFaceSweep.Path.ARC and angle < 0.0
	var made := HFFaceSweep.pieces(rings_of(run), frame_list, end_scale, backward)
	made["frames"] = frame_list
	return made


## Toward as a direction in the faces' plane: `degrees` from their right toward
## their up.
static func toward_of(degrees: float) -> Vector2:
	var turn := deg_to_rad(degrees)
	return Vector2(cos(turn), sin(turn))


## Where an arc of `settings` turns about, in the start frame's space: `radius`
## from the faces' middle, toward Toward. What the pivot handle shows.
static func pivot_of(settings: Dictionary) -> Vector3:
	var merged := HFGeneratorSchema.merge(settings_schema(), settings)
	var toward := toward_of(float(merged["toward"]))
	return Vector3(toward.x, toward.y, 0.0) * float(merged["radius"])


## The line an arc of `settings` turns about, through `pivot_of()`, in the start
## frame's space.
static func axis_of(settings: Dictionary) -> Vector3:
	var merged := HFGeneratorSchema.merge(settings_schema(), settings)
	var toward := toward_of(float(merged["toward"]))
	return Vector3.BACK.cross(Vector3(toward.x, toward.y, 0.0)).normalized()


## Where one turn of an arc of `settings` ends, in the start frame's space. What
## the end handle shows.
static func end_of(settings: Dictionary) -> Vector3:
	var merged := HFGeneratorSchema.merge(settings_schema(), settings)
	var end := HFFaceSweep.end_frame(
		Transform3D.IDENTITY,
		HFFaceSweep.Path.ARC,
		float(merged["length"]),
		float(merged["angle"]),
		float(merged["radius"]),
		float(merged["offset"]),
		toward_of(float(merged["toward"]))
	)
	return end.origin


## The settings a pivot at `local` in the faces' plane gives: its distance from
## the faces' middle as Radius, in steps of `grid_step`, and its direction as
## Toward, in steps of `angle_step` degrees. A step of 0 lands where the pointer
## is, to the fields' own precision.
static func pivot_settings(
	settings: Dictionary, local: Vector3, grid_step: float, angle_step: float
) -> Dictionary:
	var out := settings.duplicate()
	var flat := Vector2(local.x, local.y)
	var reach := snappedf(flat.length(), grid_step if grid_step > 0.0 else RADIUS_STEP)
	var least := maxf(grid_step, RADIUS_STEP * 10.0)
	out["radius"] = snappedf(maxf(reach, least), RADIUS_STEP)
	if flat.length() > 0.000001:
		var turn := snappedf(rad_to_deg(flat.angle()), angle_step if angle_step > 0.0 else 1.0)
		out["toward"] = fposmod(turn, 360.0)
	return out


## The run's rings as corner lists.
static func rings_of(run: Dictionary) -> Array:
	var out: Array = []
	for ring in run.get("rings", []):
		var corners := PackedVector3Array()
		for point in ring:
			if point is Array and (point as Array).size() == 3:
				corners.append(Vector3(float(point[0]), float(point[1]), float(point[2])))
		if corners.size() >= 3:
			out.append(corners)
	return out


static func check_along(settings: Dictionary, run: Dictionary) -> HFOpResult:
	if rings_of(run).is_empty():
		return HFOpResult.fail("Sweep: there are no faces to sweep", "Pick faces in Face Select")
	var made := plan(settings, run)
	var folded := int(made["folded"])
	if folded > 0:
		return HFOpResult.fail(
			(
				"Sweep: %d of %d pieces fold back on themselves"
				% [folded, (made["pieces"] as Array).size()]
			),
			"Widen the radius or cut more segments"
		)
	return HFOpResult.success()


## One face set per piece, in the start frame's space, each face with the look of
## the face it ran along and each end with the swept face's.
static func build_along(settings: Dictionary, run: Dictionary) -> Array:
	var made := plan(settings, run)
	if int(made["folded"]) > 0:
		return []
	var looks: Array = run.get("looks", [])
	var out: Array = []
	for piece in made["pieces"]:
		var faces: Array = piece["faces"]
		var ring_looks: Dictionary = {}
		var section := int(piece["section"])
		if section < looks.size() and looks[section] is Dictionary:
			ring_looks = looks[section]
		var edges: PackedInt32Array = piece.get("edges", PackedInt32Array())
		var sides: Array = ring_looks.get("sides", [])
		for i in faces.size():
			var edge := edges[i] if i < edges.size() else -1
			var look: Variant = ring_looks.get("swept")
			if edge >= 0 and edge < sides.size() and sides[edge] is Dictionary:
				look = sides[edge]
			if look is Dictionary:
				give_look(faces[i], look)
		out.append(faces)
	return out


## Lay `look`, as `look_of()` gives it, on `face`.
static func give_look(face: FaceData, look: Dictionary) -> void:
	for key in LOOK_KEYS:
		if not look.has(key) or look[key] == null:
			continue
		var value = look[key]
		if key in ["uv_scale", "uv_offset"] and value is Array and (value as Array).size() == 2:
			value = Vector2(float(value[0]), float(value[1]))
		face.set(key, value)


static func _plain(v: Vector3) -> Array:
	return [snappedf(v.x, 0.000001), snappedf(v.y, 0.000001), snappedf(v.z, 0.000001)]


static func _refused(message: String, hint: String) -> Dictionary:
	return {"refused": message, "hint": hint}
