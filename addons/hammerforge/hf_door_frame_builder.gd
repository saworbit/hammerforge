@tool
extends RefCounted
class_name HFDoorFrameBuilder

## A framed doorway: two posts and a head round a clear opening, and the cut that
## makes the opening, one brush each (#1411).
##
## By hand that is a cut and three frame brushes, each sized from the same opening
## and wall, and an arched head is an Arch built to match. Change the width and
## every piece has to be resized and lined up again, and nothing ties the cut to
## the frame. Here they are one structure, so an Update moves them together.
##
## Width and Height are the clear opening: the posts' inner faces and the head's
## underside bound exactly that, and the cut is exactly that. An Arched head is
## `HFArchBuilder`'s half circle, its inside the opening's width, lifted so it rests
## on the posts; Height is then the opening's height at its crown. The cut for an
## arched opening is one convex piece, the box to the springing line and the half
## polygon of the arch's inside over it, so Validate measures the doorway by its
## full height and not only to where the arch springs.
##
## Built about its own middle like every structure: the opening's width along X,
## its height up Y, and the wall's thickness along Z. The caller places it.

# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFArchBuilder = preload("hf_arch_builder.gd")
const HFConvexClip = preload("hf_convex_clip.gd")
const HFGeneratorSchema = preload("hf_generator_schema.gd")
const HFNumberFormat = preload("hf_number_format.gd")
const HFOpResult = preload("hf_op_result.gd")
@warning_ignore_restore("shadowed_global_identifier")

const HEAD_FLAT := 0
const HEAD_ARCHED := 1

## An arched head is a half turn, and a piece spanning half a turn is not convex,
## so two is the fewest. The arched cut has five faces more than this, which keeps
## it far inside `HFConvexClip.MAX_BOOLEAN_PLANES`.
const MIN_SEGMENTS := 2
const MAX_SEGMENTS := 64

## The thinnest a box piece is let be, as on the Stairs
## (`HFBrushSystem.MIN_BRUSH_EXTENT`). The posts, a flat head and the cut are boxes.
## Every field that sizes one starts here (#1605): Wall too, since the frame is at
## least as deep.
## `validate()` holds the posts under an arched head, which Height only feeds, and
## the pieces of an arched head as the Arch holds its segments.
const MIN_PIECE := 0.1
## A side this near the minimum is the minimum after a float rounding, as 0.6 less
## half of 1.0 is, and the brush system builds it as it is.
const THIN_SLACK := 0.00001


static func settings_schema() -> Array:
	return [
		{
			"key": "width",
			"label": "Width",
			"type": HFGeneratorSchema.TYPE_FLOAT,
			"min": MIN_PIECE,
			"max": 1024.0,
			"step": 0.05,
			"default": 1.0,
			"tooltip": "How wide the clear opening is, between the posts",
		},
		{
			"key": "height",
			"label": "Height",
			"type": HFGeneratorSchema.TYPE_FLOAT,
			"min": MIN_PIECE,
			"max": 1024.0,
			"step": 0.05,
			"default": 2.1,
			"tooltip":
			"How high the clear opening is, to the head, or to the crown of an arched one",
		},
		{
			"key": "wall",
			"label": "Wall",
			"type": HFGeneratorSchema.TYPE_FLOAT,
			"min": MIN_PIECE,
			"max": 1024.0,
			"step": 0.01,
			"default": 0.2,
			"tooltip": "How thick the wall is that the frame wraps",
		},
		{
			"key": "frame",
			"label": "Frame",
			"type": HFGeneratorSchema.TYPE_FLOAT,
			"min": MIN_PIECE,
			"max": 512.0,
			"step": 0.01,
			"default": 0.1,
			"tooltip": "How wide each post and the head are on the wall's face",
		},
		{
			"key": "proud",
			"label": "Proud",
			"type": HFGeneratorSchema.TYPE_FLOAT,
			"min": 0.0,
			"max": 512.0,
			"step": 0.01,
			"default": 0.02,
			"tooltip": "How far the frame stands out from each face of the wall",
		},
		{
			"key": "head",
			"label": "Head",
			"type": HFGeneratorSchema.TYPE_ENUM,
			"options": ["Flat", "Arched"],
			"default": HEAD_FLAT,
			"tooltip": "A flat lintel over the opening, or a half round arch on the posts",
		},
		{
			"key": "segments",
			"label": "Segments",
			"type": HFGeneratorSchema.TYPE_INT,
			"min": MIN_SEGMENTS,
			"max": MAX_SEGMENTS,
			"step": 1,
			"default": 8,
			"tooltip": "One brush per piece of an arched head. More segments, smoother curve",
		},
		{
			"key": "cut_opening",
			"label": "Cut opening",
			"type": HFGeneratorSchema.TYPE_BOOL,
			"default": true,
			"tooltip": "Also make the cut for the opening, a Pending Cut until it is applied",
		},
	]


static func default_settings() -> Dictionary:
	return HFGeneratorSchema.defaults(settings_schema())


static func validate(settings: Dictionary) -> HFOpResult:
	var merged := HFGeneratorSchema.merge(settings_schema(), settings)
	for pair in [["width", "width"], ["height", "height"], ["wall", "wall"], ["frame", "frame"]]:
		if float(merged[pair[0]]) <= 0.0:
			return HFOpResult.fail(
				"Door Frame: %s must be greater than zero" % pair[1], "Set a positive %s" % pair[1]
			)
	if float(merged["proud"]) < 0.0:
		return HFOpResult.fail("Door Frame: proud cannot be negative", "Set 0 for a flush frame")
	if int(merged["head"]) == HEAD_ARCHED:
		var segments: int = merged["segments"]
		if segments < MIN_SEGMENTS or segments > MAX_SEGMENTS:
			return HFOpResult.fail(
				"Door Frame: an arched head of %d segment(s) cannot be built" % segments,
				"Use %d to %d segments" % [MIN_SEGMENTS, MAX_SEGMENTS]
			)
		# The posts stand up to where the arch springs, so they need a brush's height.
		var least := float(merged["width"]) * 0.5 + MIN_PIECE
		if float(merged["height"]) < least - THIN_SLACK:
			return HFOpResult.fail(
				(
					"Door Frame: an arched head on a %s wide opening needs a height of %s or more"
					% [_number(float(merged["width"])), _number(least)]
				),
				"Raise the height, narrow the opening, or use a flat head"
			)
		# The head is measured as the Arch measures its segments: only against a
		# sliver, since a piece square to an axis is a box only at the minimum.
		var thin := HFArchBuilder.thin_segment(_arch_settings(merged))
		if not thin.is_empty():
			var what := "a sliver, too thin to build"
			if thin["box"]:
				what = "a box thinner than a box can be"
			return HFOpResult.fail(
				(
					"Door Frame: an arched head piece %s across is %s"
					% [_number(thin["across"]), what]
				),
				"Use fewer than %d segments, or a wider opening" % segments
			)
	return HFOpResult.success()


static func _number(value: float) -> String:
	return HFNumberFormat.number(value, 0.0001)


## Which pieces `build()` returns are cuts rather than solids, by their place in
## it. `HFGeneratorSystem` makes these Cutout brushes, pending until applied.
static func cutter_pieces(settings: Dictionary) -> PackedInt32Array:
	if not validate(settings).ok:
		return PackedInt32Array()
	var merged := HFGeneratorSchema.merge(settings_schema(), settings)
	if not bool(merged["cut_opening"]):
		return PackedInt32Array()
	return PackedInt32Array([_solid_count(merged)])


## Build the frame. One `Array[FaceData]` per piece in its own space: the left
## and right posts, the head (one lintel, or one piece per arch segment), and the
## cut last when there is one.
static func build(settings: Dictionary) -> Array:
	if not validate(settings).ok:
		return []
	var merged := HFGeneratorSchema.merge(settings_schema(), settings)
	var half_width: float = float(merged["width"]) * 0.5
	var height: float = merged["height"]
	var frame: float = merged["frame"]
	var half_depth: float = float(merged["wall"]) * 0.5 + float(merged["proud"])
	var arched := int(merged["head"]) == HEAD_ARCHED
	var outer := half_width + frame
	# The foot of the opening, with the whole frame centred on its own middle.
	var foot := -(height + frame) * 0.5
	# Where the posts stop: the head's underside, or where the arch springs.
	var spring := foot + (height - half_width if arched else height)

	var out: Array = []
	out.append(_box(-outer, foot, -half_width, spring, half_depth))
	out.append(_box(half_width, foot, outer, spring, half_depth))
	if arched:
		for piece in HFArchBuilder.build(_arch_settings(merged)):
			out.append(_lifted(piece, spring))
	else:
		out.append(_box(-outer, spring, outer, spring + frame, half_depth))
	if bool(merged["cut_opening"]):
		var outline := PackedVector2Array([Vector2(-half_width, foot), Vector2(half_width, foot)])
		if arched:
			# The arch's own inside corners, so the cut meets every segment exactly.
			var segments: int = merged["segments"]
			outline.append(Vector2(half_width, spring))
			for k in range(1, segments):
				var angle := PI * float(k) / float(segments)
				outline.append(Vector2(half_width * cos(angle), spring + half_width * sin(angle)))
			outline.append(Vector2(-half_width, spring))
		else:
			outline.append(Vector2(half_width, spring))
			outline.append(Vector2(-half_width, spring))
		out.append(_prism(outline, half_depth))
	return out


## The Arch an arched head is: a half circle, its inside the opening's width and
## its wall the frame, as deep as the frame.
static func _arch_settings(merged: Dictionary) -> Dictionary:
	return {
		"radius": float(merged["width"]) * 0.5 + float(merged["frame"]),
		"wall_thickness": merged["frame"],
		"depth": float(merged["wall"]) + float(merged["proud"]) * 2.0,
		"arc_degrees": 180.0,
		"segments": int(merged["segments"]),
		"start_degrees": 0.0,
	}


## How many solid pieces these settings make: two posts and the head's.
static func _solid_count(merged: Dictionary) -> int:
	return 2 + (int(merged["segments"]) if int(merged["head"]) == HEAD_ARCHED else 1)


## The box from (x0, y0) to (x1, y1), through the frame's depth.
static func _box(x0: float, y0: float, x1: float, y1: float, half_depth: float) -> Array:
	var corners := [Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)]
	return _prism(PackedVector2Array(corners), half_depth)


## A convex outline in XY, stood through Z from -half_depth to half_depth.
static func _prism(outline: PackedVector2Array, half_depth: float) -> Array:
	var front := PackedVector3Array()
	var back := PackedVector3Array()
	for corner in outline:
		front.append(Vector3(corner.x, corner.y, half_depth))
		back.append(Vector3(corner.x, corner.y, -half_depth))
	var rings: Array = [front, back]
	for k in outline.size():
		var next := (k + 1) % outline.size()
		rings.append([front[k], front[next], back[next], back[k]])
	# Winding is measured, not listed: `solid_from_rings` turns every face to point
	# away from the middle of the piece.
	return HFConvexClip.solid_from_rings(rings)


## An arch piece, built about the arch's centre, moved up to stand at `y`.
static func _lifted(faces: Array, y: float) -> Array:
	var shift := Vector3(0.0, y, 0.0)
	for face in faces:
		var moved := PackedVector3Array()
		for vertex in face.local_verts:
			moved.append(vertex + shift)
		face.local_verts = moved
		face.ensure_geometry()
	return faces
