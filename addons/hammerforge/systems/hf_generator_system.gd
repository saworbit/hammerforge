@tool
extends RefCounted
class_name HFGeneratorSystem

## Keeps generated structures editable after they exist.
##
## A generator turns a handful of numbers into a lot of brushes. Without a record
## of that, the numbers are lost the moment the brushes appear, and changing your
## mind about a radius means rebuilding by hand. This holds the records, and
## rebuilds a structure in place when its settings change.
##
## The record is a hint, never a guarantee. Brushes can be deleted, carved or
## merged away without this system knowing, so every use filters the record
## against what actually exists.

# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFArchBuilder = preload("../hf_arch_builder.gd")
const HFDomeBuilder = preload("../hf_dome_builder.gd")
const HFDoorFrameBuilder = preload("../hf_door_frame_builder.gd")
const FaceData = preload("../face_data.gd")
const HFGenerator = preload("../hf_generator.gd")
const HFOpResult = preload("../hf_op_result.gd")
const HFSpiralStairsBuilder = preload("../hf_spiral_stairs_builder.gd")
const HFStairsBuilder = preload("../hf_stairs_builder.gd")
const HFRebuildCarry = preload("../hf_rebuild_carry.gd")
const HFRingBuilder = preload("../hf_ring_builder.gd")
const HFSolidMeasure = preload("../hf_solid_measure.gd")
const HFTrimRunBuilder = preload("../hf_trim_run_builder.gd")
const HFSweepBuilder = preload("../hf_sweep_builder.gd")
@warning_ignore_restore("shadowed_global_identifier")

const GENERATOR_META := &"hf_generator_id"

## Generator types this system can build. A builder owns its own settings, its own
## validation and its own arithmetic, so adding one means writing the builder and
## naming it in `builder_for()`. Nothing else in the system, and nothing at all in
## the dock, has to know it exists.
const TYPE_ARCH := "arch"
const TYPE_STAIRS := "stairs"
const TYPE_SPIRAL_STAIRS := "spiral_stairs"
const TYPE_DOME := "dome"
const TYPE_RING := "ring"
const TYPE_DOOR_FRAME := "door_frame"
## Built along wall faces rather than about its own origin (#1414), so it is not
## one of `known_types()`: see `structure_types()`.
const TYPE_TRIM_RUN := "trim_run"
## Sweep Faces kept as a structure, built along the faces it swept (#1885).
const TYPE_SWEEP := "sweep"

## How far two pieces can disagree about how far they have moved and still count
## as having moved together. A user dragging a structure moves every piece by
## exactly the same amount; anything looser than this is individual editing.
const RELOCATION_EPSILON := 0.01

## How far two pieces can disagree about how far they have been *turned* and
## still count as having been turned together. Basis columns are unit length, so
## this is an angle in disguise: about a twentieth of a degree.
const ROTATION_EPSILON := 0.001

## How far apart, in UV, a face's corners may show its texture and still show the
## look its builder gave it, as Compare allows (#1969).
const SHOWN_NEAR := 0.001

## What an Update keeps of each piece: all of it but its shape, which is the
## settings'. Its look is what a designer adds after generating, and losing it on
## every radius nudge would make this not worth using. Its node name and its brush
## entity are what wires aim at (#1165, #1163), and its visgroups and group are
## what keep a hidden structure hidden (#1201). The authored name is the entity's.
const CARRIED := [
	HFRebuildCarry.APPEARANCE,
	HFRebuildCarry.NODE_NAME,
	HFRebuildCarry.ENTITY,
	HFRebuildCarry.MEMBERSHIP,
]

var root: Node3D
var generators: Dictionary = {}  # generator_id -> HFGenerator
## Whether a node may still carry a structure's tag that no record gives it:
## `clear()` emptied the records, and no restore has walked the nodes since.
var _tags_may_remain := false


func _init(level_root: Node3D = null) -> void:
	root = level_root


# ---------------------------------------------------------------------------
# The builders this system knows
# ---------------------------------------------------------------------------


## The types built about their own origin from their settings alone, which is
## what Create and an agent's create_structure place, and what every check that
## builds a type from its defaults reads.
static func known_types() -> PackedStringArray:
	return PackedStringArray(
		[TYPE_ARCH, TYPE_STAIRS, TYPE_SPIRAL_STAIRS, TYPE_DOME, TYPE_RING, TYPE_DOOR_FRAME]
	)


## Every type the Structure section edits: the known types, and the ones built
## along a run read from the level, which Create builds from the faces picked in
## Face Select rather than at the selection (#1414).
static func structure_types() -> PackedStringArray:
	var out := known_types()
	out.append(TYPE_TRIM_RUN)
	out.append(TYPE_SWEEP)
	return out


## Whether a type is built along a run the record keeps beside its settings,
## read from the level, rather than from its settings alone (#1414).
static func follows_run(type: String) -> bool:
	var builder = builder_for(type)
	return builder != null and builder.has_method("build_along")


## The one place that knows which builder is which. Everything below asks here.
static func builder_for(type: String):
	match type:
		TYPE_ARCH:
			return HFArchBuilder
		TYPE_STAIRS:
			return HFStairsBuilder
		TYPE_SPIRAL_STAIRS:
			return HFSpiralStairsBuilder
		TYPE_DOME:
			return HFDomeBuilder
		TYPE_RING:
			return HFRingBuilder
		TYPE_DOOR_FRAME:
			return HFDoorFrameBuilder
		TYPE_TRIM_RUN:
			return HFTrimRunBuilder
		TYPE_SWEEP:
			return HFSweepBuilder
		_:
			return null


## What to call this in the dock. Derived rather than tabled, so a new type gets a
## readable name without a second list to keep in step.
static func display_name(type: String) -> String:
	return type.replace("_", " ").capitalize()


## What an Update refused by `can_build()` says, from the dock and from the agent
## bridge alike.
static func not_changed_text(type: String, refusal: HFOpResult) -> String:
	return "%s not changed. %s" % [display_name(type), refusal.user_text()]


static func default_settings(type: String) -> Dictionary:
	var builder = builder_for(type)
	return builder.default_settings() if builder else {}


## The fields a type has, described well enough for the dock to build controls.
static func settings_schema(type: String) -> Array:
	var builder = builder_for(type)
	return builder.settings_schema() if builder else []


static func validate(type: String, settings: Dictionary) -> HFOpResult:
	var builder = builder_for(type)
	if builder == null:
		return HFOpResult.fail(
			"Structure: '%s' is not a structure type" % type,
			"Known types: %s" % ", ".join(known_types())
		)
	# Before the builder, because the builder cannot catch either of these: a
	# non-finite number passes every comparison it makes, and the upper bounds
	# live in the schema rather than in the builder at all.
	var range_problem := HFGeneratorSchema.check_ranges(builder.settings_schema(), settings)
	if range_problem != "":
		return HFOpResult.fail("%s: %s" % [display_name(type), range_problem])
	var result = builder.validate(settings)
	# A builder that returns nothing is a bug in the builder, but it must not
	# become a null out of create_generator(), which is declared to hand back a
	# result every caller then reads `.ok` off.
	if result == null:
		return HFOpResult.fail(
			"Structure: '%s' could not check those settings" % type,
			"Check the settings for a value of the wrong type"
		)
	return result


## One face set per piece the structure is made of, in the structure's own space.
## A type that `follows_run()` is built along `run`, and builds nothing without
## one.
static func build_faces(type: String, settings: Dictionary, run: Dictionary = {}) -> Array:
	var builder = builder_for(type)
	if builder == null:
		return []
	if follows_run(type):
		return builder.build_along(settings, run)
	return builder.build(settings)


## What the settings came to, where a builder works something out from them that
## no field shows: the step count and rise a stair takes from its total height
## (#1410). Empty for a builder that has nothing to say, or settings that cannot
## build.
static func summary(type: String, settings: Dictionary) -> String:
	var builder = builder_for(type)
	if builder == null or not builder.has_method("summary"):
		return ""
	return str(builder.summary(settings))


## Which pieces of `build_faces()` are cuts rather than solids, by their place in
## it. A builder that makes cuts answers `cutter_pieces()`, as the door frame's
## opening does; every other builder makes none.
static func cutter_pieces(type: String, settings: Dictionary) -> PackedInt32Array:
	var builder = builder_for(type)
	if builder == null or not builder.has_method("cutter_pieces"):
		return PackedInt32Array()
	return builder.cutter_pieces(settings)


## How far up a structure built round its own middle goes to stand on its origin:
## minus the lowest corner of its solid pieces. The Structure section lifts a new
## one by this when nothing is selected, so it stands on the floor at y = 0
## rather than half under it (#1821). 0 for a type built along a run, or settings
## that build nothing.
static func stand_height(type: String, settings: Dictionary) -> float:
	if follows_run(type):
		return 0.0
	var pieces := build_faces(type, settings)
	var cutters := cutter_pieces(type, settings)
	var lowest := INF
	for index in pieces.size():
		if cutters.has(index):
			continue
		for face in pieces[index]:
			for point in HFSolidMeasure.ring(face):
				lowest = minf(lowest, point.y)
	return -lowest if is_finite(lowest) else 0.0


## Whether these settings would build, without building anything that lasts.
##
## Each field can be in range while the combination is not: a wall as thick as
## the arch is wide, an arc of zero, a wide arc across too few segments. The
## builder refuses those, so the dock has to be able to ask before it opens an
## undo action and tells the user it worked.
##
## A type built along a run is asked about `run`: the builder says why a run it
## cannot follow is refused, which "no geometry" would not.
static func can_build(type: String, settings: Dictionary, run: Dictionary = {}) -> HFOpResult:
	var check := validate(type, settings)
	if not check.ok:
		return check
	if follows_run(type):
		var along: HFOpResult = builder_for(type).check_along(settings, run)
		if not along.ok:
			return along
	if build_faces(type, settings, run).is_empty():
		return HFOpResult.fail(
			"%s: those settings produce no geometry" % display_name(type),
			"Widen the structure or add segments"
		)
	return HFOpResult.success()


# ---------------------------------------------------------------------------
# Creating, changing and forgetting
# ---------------------------------------------------------------------------


## A new structure's pieces all get `material` as their whole-brush material, when
## there is one. An Update never takes one: each piece keeps the look it has, and
## a piece it adds takes the material most pieces have.
##
## A type that `follows_run()` is built along `run`, in the structure's own
## space, and the record keeps it.
func create(
	type: String,
	settings: Dictionary,
	placement: Transform3D,
	material: Material = null,
	run: Dictionary = {}
) -> HFOpResult:
	var check := _check(type, settings, run)
	if not check.ok:
		return check
	var face_sets := build_faces(type, settings, run)
	if face_sets.is_empty():
		return HFOpResult.fail("Structure: '%s' produced no geometry" % type)

	var record := HFGenerator.new()
	record.type = type
	record.settings = settings.duplicate(true)
	record.run = run.duplicate(true) if follows_run(type) else {}
	record.placement = placement
	# A cut starts pending, as a drawn Cutout does, and waits for Apply.
	var cuts := _cuts_of(type, settings, true)
	record.brush_ids = _spawn(face_sets, placement, record.generator_id, null, material, cuts)
	if record.brush_ids.is_empty():
		return HFOpResult.fail("Structure: '%s' produced no geometry" % type)
	_record_signatures(record)

	generators[record.generator_id] = record
	# New work joins the current visgroup (#1732).
	if root and root.visgroup_system:
		for brush_id in record.brush_ids:
			root.visgroup_system.join_current(root.find_brush_by_id(brush_id))
	var message := "%s: created %d pieces" % [type.capitalize(), record.brush_ids.size()]
	if root and root.has_method("_log"):
		root._log(message)
	return HFOpResult.success(message)


## Rebuild a structure in place from new settings.
##
## Nothing is deleted until the new settings are known to be buildable, so a bad
## edit leaves the existing structure exactly as it was rather than removing it
## and then failing to replace it.
##
## It always rebuilds. An Update asks `update_changes_nothing()` first, because a
## rebuild that puts back the same pieces still gives each a new id.
func regenerate(generator_id: String, settings: Dictionary) -> HFOpResult:
	if not generators.has(generator_id):
		return HFOpResult.fail("Structure: no structure with id '%s'" % generator_id)
	var record: HFGenerator = generators[generator_id]
	return _rebuild(record, settings, record.run, null)


## Lay a structure built along a run along a new one (#1414): Re-pick. `run` is
## in the space of `placement`, which becomes the structure's. Its settings stay,
## and nothing is deleted unless the new run builds.
func repick(generator_id: String, run: Dictionary, placement: Transform3D) -> HFOpResult:
	if not generators.has(generator_id):
		return HFOpResult.fail("Structure: no structure with id '%s'" % generator_id)
	var record: HFGenerator = generators[generator_id]
	if not follows_run(record.type):
		return HFOpResult.fail(
			"%s is not built along faces, so it has no run to re-pick" % display_name(record.type)
		)
	return _rebuild(record, record.settings, run, placement)


## Whether rebuilding this structure with these settings would build, asked of
## the run it keeps when it follows one. What the dock and the agent bridge ask
## before an Update opens an undo action.
func can_rebuild(generator_id: String, settings: Dictionary) -> HFOpResult:
	var record: HFGenerator = generators.get(generator_id, null)
	if record == null:
		return HFOpResult.fail("Structure: no structure with id '%s'" % generator_id)
	return can_build(record.type, settings, record.run)


## Whether a Re-pick with `run` at `placement` would put back what is there: the
## same run where the structure stands now, on pieces nobody touched (#1368).
func repick_changes_nothing(generator_id: String, run: Dictionary, placement: Transform3D) -> bool:
	var record: HFGenerator = generators.get(generator_id, null)
	if record == null or not follows_run(record.type):
		return false
	if not update_changes_nothing(generator_id, record.settings):
		return false
	# Both read in the space the structure stands in now, as its own type reads a
	# run: a Trim Run's walls or a Sweep's faces (#1932).
	var builder = builder_for(record.type)
	var world: Dictionary = builder.in_space(run, placement.affine_inverse())
	var now: Dictionary = builder.in_space(world, rebuild_placement(generator_id))
	return builder.same_run(now, record.run)


## What `create()` and a rebuild ask first: the settings, and for a type built
## along a run, the run as well.
static func _check(type: String, settings: Dictionary, run: Dictionary) -> HFOpResult:
	return can_build(type, settings, run) if follows_run(type) else validate(type, settings)


## Rebuild `record` with `settings` along `run`, at `placement`, or where the
## structure now stands when that is null.
func _rebuild(
	record: HFGenerator, settings: Dictionary, run: Dictionary, placement: Variant
) -> HFOpResult:
	var generator_id := record.generator_id
	var check := _check(record.type, settings, run)
	if not check.ok:
		return check
	var face_sets := build_faces(record.type, settings, run)
	if face_sets.is_empty():
		return HFOpResult.fail("Structure: those settings produce no geometry")

	# What each piece has that the settings do not say (`CARRIED`), read off in
	# order and put back by index. When the piece count changes there is no
	# correspondence past the shorter list: an extra piece takes default faces, the
	# whole-brush material most pieces had (#1526), and what every piece shared.
	var carry := _carry_of(record)
	# A doorway already cut stays cut at its new size, and one still pending stays
	# pending, so its cuts are read before they go.
	var cuts := _cuts_of(record.type, settings, not _cuts_applied(record))
	# Where the structure is now, not where it was made, unless a Re-pick says
	# where its new run is. Read before anything is deleted, because it is the
	# existing pieces that say where they have gone.
	if placement is Transform3D:
		record.placement = placement
	else:
		record.placement = relocation_transform(generator_id) * record.placement
	_delete_brushes(record.brush_ids, generator_id)

	record.settings = settings.duplicate(true)
	if follows_run(record.type):
		record.run = run.duplicate(true)
	record.brush_ids = _spawn(face_sets, record.placement, generator_id, carry, null, cuts)
	if record.brush_ids.is_empty():
		generators.erase(generator_id)
		return HFOpResult.fail("Structure: those settings produce no geometry")
	_record_signatures(record)
	var message := "%s: rebuilt as %d pieces" % [record.type.capitalize(), record.brush_ids.size()]
	if root and root.has_method("_log"):
		root._log(message)
	return HFOpResult.success(message)


## Whether an Update with these settings would put back exactly what is there.
##
## A rebuild of the same pieces gives every one a new id, which breaks whatever
## named the old ones (a wire, a cordon round them, a prefab record), and leaves
## a step that undoes nothing a mapper can see (#1368). So the dock, the toolbar
## and the agent bridge ask here first and do nothing when this says so.
##
## True when the settings are the record's and every piece the record names is
## still there, still this structure's and still the shape and place it was
## built in. A structure moved or turned as a whole counts, because a rebuild
## puts it back exactly where it stands. A piece this cannot vouch for counts as
## a change, so the rebuild goes ahead as before: a deleted one, which it puts
## back; one whose id now names a brush that is not ours (#1221), whose place it
## fills; one with no signature to compare against, from an older record.
func update_changes_nothing(generator_id: String, settings: Dictionary) -> bool:
	if not generators.has(generator_id):
		return false
	var record: HFGenerator = generators[generator_id]
	if builder_for(record.type) == null or record.brush_ids.is_empty():
		return false
	if not same_settings(record.type, record.settings, settings):
		return false
	for brush_id in record.brush_ids:
		if (record.brush_signatures.get(str(brush_id), {}) as Dictionary).is_empty():
			return false
		if _owned_brush(str(brush_id), generator_id) == null:
			return false
	return edited_brush_ids(generator_id).is_empty()


## Whether two sets of settings build the same structure. Each is read the way
## the builder reads it, so a whole number saved as a float, or handed back as
## one by a SpinBox, agrees with the int it was; a float only has to be nearly
## equal, so a value that went through a save and a SpinBox still matches.
static func same_settings(type: String, a: Dictionary, b: Dictionary) -> bool:
	var schema := settings_schema(type)
	var left := HFGeneratorSchema.merge(schema, a)
	var right := HFGeneratorSchema.merge(schema, b)
	for key in left:
		var mine = left[key]
		var theirs = right.get(key)
		if mine is float and theirs is float:
			if not is_equal_approx(mine, theirs):
				return false
		elif mine != theirs:
			return false
	return true


## Forget the record and leave the brushes as ordinary geometry.
##
## The escape hatch for a structure that has been edited by hand and should stop
## being rebuilt out from under those edits.
func detach(generator_id: String) -> bool:
	if not generators.has(generator_id):
		return false
	var record: HFGenerator = generators[generator_id]
	for brush_id in record.brush_ids:
		var brush = _brush(str(brush_id))
		if brush and brush.has_meta(GENERATOR_META):
			brush.remove_meta(GENERATOR_META)
	generators.erase(generator_id)
	return true


## Delete the structure and its record together.
func remove(generator_id: String) -> bool:
	if not generators.has(generator_id):
		return false
	var record: HFGenerator = generators[generator_id]
	_delete_brushes(record.brush_ids, generator_id)
	generators.erase(generator_id)
	return true


# ---------------------------------------------------------------------------
# Lookups
# ---------------------------------------------------------------------------


func generator_for_id(generator_id: String) -> HFGenerator:
	return generators.get(generator_id, null)


func generator_for_brush(brush_id: String) -> HFGenerator:
	var brush = _brush(brush_id)
	if brush == null or not brush.has_meta(GENERATOR_META):
		return null
	var generator_id := str(brush.get_meta(GENERATOR_META))
	return generators.get(generator_id, null)


## The generator that owns the first brush in a selection that belongs to one.
func generator_for_selection(brush_ids: Array) -> HFGenerator:
	for brush_id in brush_ids:
		var record := generator_for_brush(str(brush_id))
		if record != null:
			return record
	return null


# ---------------------------------------------------------------------------
# What has happened to a structure since it was made
# ---------------------------------------------------------------------------


## How far the whole structure has been dragged since it was last built.
##
## A user who moves a structure moves every piece of it by exactly the same
## amount, so that is the test: if every surviving piece agrees on the delta, the
## structure was relocated and it should rebuild where it now is. If the pieces
## disagree they were moved individually, which is editing rather than
## relocating, and the placement stays where it was.
##
## Without this, dragging an arch into a doorway and then widening it puts the
## arch back where it was created — which is where the whole premise of changing
## your mind after seeing it in place falls down.
func relocation_transform(generator_id: String) -> Transform3D:
	var vote := _relocation_vote(generator_id)
	return vote["move"]


## Whether the pieces could not agree on where the structure is, having plainly
## been moved from where they were put.
##
## The honest reading of a structure nobody can locate: a rebuild has nowhere to
## put it but the placement it was created at, which may be across the level. The
## section says that rather than only counting shapes.
func pieces_disagree_about_placement(generator_id: String) -> bool:
	var vote := _relocation_vote(generator_id)
	return not vote["agreed"] and vote["moved"]


## Where the structure has gone, decided by vote rather than by unanimity.
##
## Unanimity sounds like the stricter test and is in fact the worse one. Nudge a
## single brush of a twelve-piece arch you have dragged across the level and the
## eleven that agree are overruled: the structure reads as twelve hand edits
## instead of one, and Update carries the whole thing back to the origin it was
## created at. More than half the pieces agreeing is enough to say where the
## structure went, and the ones outside that majority are the hand edits — which
## is exactly what they are.
##
## A piece whose move is not rigid never joins a group, so a mirrored or squashed
## structure cannot out-vote its own refusal however many pieces it has.
##
## Returns `move` (the relocation, identity when undecided), `agreed` (whether a
## majority was found) and `moved` (whether any piece has left its recorded spot).
func _relocation_vote(generator_id: String) -> Dictionary:
	var undecided := {"move": Transform3D.IDENTITY, "agreed": false, "moved": false}
	if not generators.has(generator_id):
		return undecided
	var record: HFGenerator = generators[generator_id]
	var rigid: Array = []
	var voters := 0
	for brush_id in record.brush_ids:
		var reading = _piece_move(record, str(brush_id), generator_id)
		if reading == null:
			continue
		voters += 1
		var move: Transform3D = reading
		if not _same_move(move, Transform3D.IDENTITY):
			undecided["moved"] = true
		if _is_rigid(move):
			rigid.append(move)
	var best := HFRebuildCarry.most_agreed(rigid, _same_move)
	if int(best[1]) * 2 <= voters:
		return undecided
	return {"move": best[0], "agreed": true, "moved": undecided["moved"]}


## How one piece has moved since it was recorded, or `null` when it cannot say:
## no signature, not ours any more, or a signature that never was a usable frame.
func _piece_move(record: HFGenerator, brush_id: String, generator_id: String) -> Variant:
	var signature: Dictionary = record.brush_signatures.get(brush_id, {})
	if signature.is_empty():
		return null
	var brush = _owned_brush(brush_id, generator_id)
	if brush == null:
		return null
	var was := _signature_transform(record, signature)
	if is_zero_approx(was.basis.determinant()):
		return null
	return brush.global_transform * was.affine_inverse()


## How far the structure has been dragged, ignoring any turn.
##
## Kept because a translation is what most callers mean and what most of the
## tests ask about. The rebuild itself uses the whole transform.
func relocation_delta(generator_id: String) -> Vector3:
	return relocation_transform(generator_id).origin


## Where a piece was put, as a transform rather than a point.
##
## A record written before turning was understood has no basis for its pieces,
## and the right answer for one of those is the placement's own basis: that is
## what every piece the generator built was given, so a record that predates the
## field reads exactly as it would have been written today.
static func _signature_transform(record: HFGenerator, signature: Dictionary) -> Transform3D:
	return Transform3D(
		signature.get("basis", record.placement.basis), signature.get("origin", Vector3.ZERO)
	)


static func _same_move(a: Transform3D, b: Transform3D) -> bool:
	if a.origin.distance_to(b.origin) > RELOCATION_EPSILON:
		return false
	for axis in 3:
		if a.basis[axis].distance_to(b.basis[axis]) > ROTATION_EPSILON:
			return false
	return true


## Whether a move is one a structure could have been given as a whole: a turn and
## a slide, nothing else.
##
## A squash or a stretch is not a relocation, and a mirror is worse than not one —
## rebuilding through a negative-determinant basis would invert the winding of
## every face in the structure and not look wrong until the bake. Both answer no,
## which leaves the placement alone and lets the pieces read as edited, which is
## what they are.
static func _is_rigid(move: Transform3D) -> bool:
	return HFTransformSystem.is_rotation_basis(move.basis)


## The pieces of a structure that are no longer the shape they were generated as.
##
## Vertex-dragged, clipped, bevelled, resized or turned — anything that changes
## what the piece *is* rather than only where it is. A rebuild replaces these, so
## the count is worth saying out loud before it happens.
##
## Deleted as well. A rebuild puts a deleted piece back, filling a gap cut on
## purpose, and passing over it as missing rather than changed let that happen
## with nothing said (#1201). A brush that is there but not ours is not counted.
func edited_brush_ids(generator_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not generators.has(generator_id):
		return out
	var record: HFGenerator = generators[generator_id]
	var moved := relocation_transform(generator_id)
	for brush_id in record.brush_ids:
		var signature: Dictionary = record.brush_signatures.get(str(brush_id), {})
		if signature.is_empty():
			continue
		if _brush(str(brush_id)) == null:
			out.append(str(brush_id))
			continue
		var brush = _owned_brush(str(brush_id), generator_id)
		if brush == null:
			continue
		var was := _signature_transform(record, signature)
		# The shape is asked about in the basis the piece was recorded in, not the
		# one it is standing in now. Hashing the same Basis value on both sides is
		# exact, where un-turning the current one would compare rounded floats
		# against the rounding of a different arithmetic path.
		if _geometry_hash_in_basis(brush, was.basis) != str(signature.get("geometry", "")):
			out.append(str(brush_id))
			continue
		# A piece that has moved on its own has been edited even though its shape
		# is untouched, because a rebuild will put it back in the row.
		if not _same_move(brush.global_transform, moved * was):
			out.append(str(brush_id))
	return out


func edited_piece_count(generator_id: String) -> int:
	return edited_brush_ids(generator_id).size()


## Where a rebuild of this structure would put it.
##
## Which is not where it was created: a structure dragged or turned into place
## rebuilds where it now stands, and a preview of the rebuild has to stand in the
## same spot and at the same angle or it is showing the wrong answer.
func rebuild_placement(generator_id: String) -> Transform3D:
	if not generators.has(generator_id):
		return Transform3D.IDENTITY
	return relocation_transform(generator_id) * generators[generator_id].placement


## The collision a structure bakes in place of its steps when its Collision is
## Ramp (#1416), where the structure now stands.
##
## `{}` when it asks for none. `{"refused": String}` when it asks and cannot have
## one: a piece edited by hand, deleted or no longer this structure's, which the
## ramp would not follow, or the builder's own refusal. Otherwise `pieces`, each
## `{"points": PackedVector3Array, "over": String}` in the space the pieces stand
## in, `over` naming the piece it lies over, `covers`, the ids of the pieces it
## stands in for, and `slope_degrees`.
func ramp_collision(generator_id: String) -> Dictionary:
	var record: HFGenerator = generators.get(generator_id, null)
	if record == null:
		return {}
	var builder = builder_for(record.type)
	if builder == null or not builder.has_method("ramp_collision"):
		return {}
	var ramp: Dictionary = builder.ramp_collision(record.settings)
	if ramp.is_empty() or ramp.has("refused"):
		return ramp
	var edited := edited_brush_ids(generator_id)
	if not edited.is_empty():
		return {
			"refused":
			(
				"%d of its pieces %s been edited by hand"
				% [edited.size(), "has" if edited.size() == 1 else "have"]
			)
		}
	if build_faces(record.type, record.settings, record.run).size() != record.brush_ids.size():
		return {"refused": "its pieces no longer match its settings"}
	var covers := PackedStringArray()
	for index in ramp["covers"]:
		var brush_id := str(record.brush_ids[int(index)])
		if _owned_brush(brush_id, generator_id) == null:
			return {"refused": "a piece of it is gone"}
		covers.append(brush_id)
	var placement := rebuild_placement(generator_id)
	var pieces: Array = []
	var over: PackedInt32Array = ramp["over"]
	for i in (ramp["pieces"] as Array).size():
		var points: PackedVector3Array = ramp["pieces"][i]
		pieces.append({"points": placement * points, "over": str(record.brush_ids[over[i]])})
	return {"pieces": pieces, "covers": covers, "slope_degrees": float(ramp["slope_degrees"])}


# ---------------------------------------------------------------------------
# A run read from the level
# ---------------------------------------------------------------------------


## The run a type that `follows_run()` is built along, read from the faces
## picked in Face Select: what Create and Re-pick both ask. `{"run",
## "placement"}` or `{"refused", "hint"}`.
func run_from_faces(type: String, face_selection: Dictionary) -> Dictionary:
	if type == TYPE_SWEEP:
		return sweep_run_from_faces(face_selection)
	return trim_run_from_faces(face_selection)


## A sweep's run from the faces picked in Face Select (#1885): each face's corners
## and outward normal in world space, its look, and the look of its brush's face
## along each edge. See `HFSweepBuilder.read()`.
func sweep_run_from_faces(face_selection: Dictionary) -> Dictionary:
	if root == null or root.get("brush_system") == null:
		return {"refused": "Sweep: there is no level to read faces from", "hint": ""}
	var picked: Array = []
	for key in face_selection:
		var brush = root._find_brush_by_key(str(key))
		if brush == null or not (face_selection[key] is Array):
			continue
		var xform: Transform3D = (brush as Node3D).global_transform
		for index in face_selection[key]:
			var face_index := int(index)
			if face_index < 0 or face_index >= brush.faces.size():
				continue
			var face = brush.faces[face_index]
			if face == null or face.local_verts.size() < 3:
				continue
			var ring := PackedVector3Array()
			for corner in face.local_verts:
				ring.append(xform * corner)
			(
				picked
				. append(
					{
						"verts": ring,
						"normal": (xform.basis.inverse().transposed() * face.normal).normalized(),
						"look": HFSweepBuilder.look_of(face),
						"sides": HFSweepBuilder.side_looks(brush.faces, face),
					}
				)
			)
	return HFSweepBuilder.read(picked)


## The run a Trim Run would follow along the faces picked in `face_selection`
## (`{brush key: [face index, ...]}`), read from the level as it stands (#1414).
##
## Another brush in front of a face hides the part of it it covers: a floor the
## wall's foot, the wall a face runs on into past a corner. Every Cutout brush,
## pending or applied, is a doorway where it takes away the wall behind a face.
## No piece of a Trim Run hides anything, so a skirting already there does not
## lift a dado rail run above it, and a Re-pick reads past the run's own pieces.
##
## Returns `{"run", "placement", "used", "hidden"}`, the run in the space of the
## placement a new structure takes, or `{"refused", "hint"}`.
func trim_run_from_faces(face_selection: Dictionary) -> Dictionary:
	if root == null or root.get("brush_system") == null:
		return {"refused": "Trim Run: there is no level to read faces from", "hint": ""}
	var picked: Array = []
	for key in face_selection:
		var brush = root._find_brush_by_key(str(key))
		if brush == null:
			continue
		var solid := _world_solid(brush)
		var rings: Array = solid["rings"]
		var indices = face_selection[key]
		if not (indices is Array):
			continue
		for index in indices:
			var face_index := int(index)
			if face_index < 0 or face_index >= rings.size():
				continue
			var ring: PackedVector3Array = rings[face_index]
			if ring.size() < 3:
				continue
			var face := {"id": solid["id"], "verts": ring}
			face["name"] = "face %d of %s" % [face_index, brush.name]
			face["normal"] = (solid["normals"] as Array)[face_index]
			picked.append(face)
	# Only a brush near a picked face can hide or hole one.
	var reach := AABB()
	var seeded := false
	for face: Dictionary in picked:
		for corner in face["verts"] as PackedVector3Array:
			reach = reach.expand(corner) if seeded else AABB(corner, Vector3.ZERO)
			seeded = true
	reach = reach.grow(HFTrimRunBuilder.COVER * 4.0)
	var solids: Array = []
	var cutters: Array = []
	for brush in root._iter_managed_brush_nodes():
		if picked.is_empty() or not root.brush_system.world_bounds_of(brush).intersects(reach):
			continue
		if brush.operation == CSGShape3D.OPERATION_SUBTRACTION:
			cutters.append(_world_solid(brush))
		elif not _is_trim_piece(brush):
			solids.append(_world_solid(brush))
	var read: Dictionary = HFTrimRunBuilder.read(picked, solids, cutters)
	if read.has("refused"):
		return read
	var placement := HFTrimRunBuilder.anchor(read["run"])
	return {
		"run": HFTrimRunBuilder.in_space(read["run"], placement),
		"placement": placement,
		"used": read["used"],
		"hidden": read["hidden"],
	}


## Whether a brush is a piece of a Trim Run, which hides no face another run
## reads.
func _is_trim_piece(brush) -> bool:
	if not brush.has_meta(GENERATOR_META):
		return false
	var record: HFGenerator = generators.get(str(brush.get_meta(GENERATOR_META)), null)
	return record != null and record.type == TYPE_TRIM_RUN


## A brush in world space: each face's corners and outward normal by its index,
## the outward plane of every face, and its bounds. A face is put the right way
## out by the brush's middle, so a brush mirrored by its transform reads as well.
func _world_solid(brush) -> Dictionary:
	var box: AABB = root.brush_system.world_bounds_of(brush)
	var xform: Transform3D = brush.global_transform
	var rings: Array = []
	var middle := Vector3.ZERO
	var count := 0
	for face in brush.get_faces():
		var ring := PackedVector3Array()
		if face != null:
			for corner in face.local_verts:
				ring.append(xform * corner)
				middle += xform * corner
				count += 1
		rings.append(ring)
	if count > 0:
		middle /= float(count)
	var normals: Array = []
	var planes: Array = []
	for i in rings.size():
		var ring: PackedVector3Array = rings[i]
		var normal := Vector3.ZERO
		if ring.size() >= 3:
			normal = brush.get_faces()[i].normal_through(xform.basis)
			if normal.dot(ring[0] - middle) < 0.0:
				normal = -normal
			planes.append(Plane(normal, normal.dot(ring[0])))
		normals.append(normal)
	return {
		"id": brush.get_instance_id(),
		"rings": rings,
		"normals": normals,
		"planes": planes,
		"box": box,
	}


# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------


func capture() -> Array:
	var out: Array = []
	for generator_id in generators:
		out.append(generators[generator_id].to_dict())
	return out


## Restore records and put the meta back on the brushes that belong to them, and
## take it off the brushes that no longer do.
func restore(records: Array) -> void:
	var had_structures := _tags_may_remain or not generators.is_empty()
	generators.clear()
	var restored: Dictionary = {}
	for entry in records:
		if not (entry is Dictionary):
			continue
		var record := HFGenerator.from_dict(entry)
		if record.type == "":
			continue
		generators[record.generator_id] = record
		for brush_id in record.brush_ids:
			var brush = _brush(str(brush_id))
			if brush:
				brush.set_meta(GENERATOR_META, record.generator_id)
				restored[brush] = {GENERATOR_META: record.generator_id}
		_take_old_signatures_again(record)
	# A restore that reuses a brush's node keeps its metadata. Undo a Detach and
	# redo it, and the old pieces went on saying they belonged to a structure that
	# was gone, in the scene file as well (#1306). Every reader asks the record, so
	# nothing acted on it, but the next one to trust the tag would have. With no
	# structure before and none now no node holds a tag, so the walk of every node
	# is skipped (#1866).
	if root != null and (had_structures or not generators.is_empty()):
		root.clear_stale_membership([GENERATOR_META], restored)
		_tags_may_remain = false


## A step saved before #879 lists its faces the way the stairs builder made them,
## and it is put into the box builder's order as it loads, so the signature taken
## over the old order no longer matches it though nobody touched it, and every
## step of an older flight read as edited (#878). A step whose faces as loaded
## still match its signature was untouched when it was saved, and only that
## step's signature is taken again. A step edited before the save still counts.
func _take_old_signatures_again(record: HFGenerator) -> void:
	for brush_id in record.brush_ids:
		var signature: Dictionary = record.brush_signatures.get(str(brush_id), {})
		if signature.is_empty():
			continue
		var brush = _owned_brush(str(brush_id), record.generator_id)
		if brush == null or not ("faces_as_loaded" in brush) or brush.faces_as_loaded.is_empty():
			continue
		var basis := _signature_transform(record, signature).basis
		var recorded := str(signature.get("geometry", ""))
		var now := _geometry_hash_in_basis(brush, basis)
		if (
			now != recorded
			and _geometry_hash_in_basis(brush, basis, brush.faces_as_loaded) == recorded
		):
			signature["geometry"] = now


func clear() -> void:
	# A restore empties the records here before it reads its own, with the tags
	# still on the nodes it keeps, so its walk must not be skipped (#1866).
	if not generators.is_empty():
		_tags_may_remain = true
	generators.clear()


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------


## `cuts` names the pieces that are cuts, as `{index: pending}`.
func _spawn(
	face_sets: Array,
	placement: Transform3D,
	generator_id: String,
	carry: HFRebuildCarry,
	material: Material = null,
	cuts: Dictionary = {}
) -> PackedStringArray:
	if root == null or root.get("brush_system") == null:
		return PackedStringArray()
	var created: PackedStringArray = root.brush_system.create_brushes_from_face_sets(
		face_sets, placement, material, cuts
	)
	# Each piece made, under its place in the structure, for the carry to give it
	# what the piece there had.
	var keys := _piece_keys(face_sets.size(), cuts.keys())
	var made: Array = []
	var made_cuts: Array = []
	for i in mini(created.size(), keys.size()):
		var brush = _brush(str(created[i]))
		if brush == null:
			continue
		brush.set_meta(GENERATOR_META, generator_id)
		made.append([keys[i], brush])
		if cuts.has(i):
			made_cuts.append([keys[i], brush])
	if carry:
		carry.restore(made)
		# A cut keeps the cut look, as a drawn Cutout does, so one an Update adds
		# does not take the material most of the pieces had.
		var looks := carry.kept(HFRebuildCarry.APPEARANCE)
		for entry in made_cuts:
			if not looks.has(entry[0]):
				entry[1].material_override = null
	return created


## What each of `count` pieces is called when a rebuild carries what it had: a cut
## by its place among the cuts, and a solid by its place among the solids. So a
## head of more pieces, or a cut added or taken away, never hands a cut a solid's
## look or name, nor a solid a cut's. With no cuts it is each piece's index.
static func _piece_keys(count: int, cut_indices: Array) -> PackedStringArray:
	var keys := PackedStringArray()
	var solids := 0
	var cuts := 0
	for i in count:
		if cut_indices.has(i):
			keys.append("cut%d" % cuts)
			cuts += 1
		else:
			keys.append(str(solids))
			solids += 1
	return keys


## The cuts among a structure's pieces, as `{index: pending}`, all pending or all
## applied.
static func _cuts_of(type: String, settings: Dictionary, pending: bool) -> Dictionary:
	var out: Dictionary = {}
	for index in cutter_pieces(type, settings):
		out[index] = pending
	return out


## Whether a structure's cuts have been applied: one of its cut pieces is still
## its own and no longer waits in Pending Cuts.
func _cuts_applied(record: HFGenerator) -> bool:
	for index in cutter_pieces(record.type, record.settings):
		if index >= record.brush_ids.size():
			continue
		var brush = _owned_brush(str(record.brush_ids[index]), record.generator_id)
		if brush == null or brush.operation != CSGShape3D.OPERATION_SUBTRACTION:
			continue
		if not brush.is_pending_cut():
			return true
	return false


## What each piece of a structure has that its settings do not say, under its
## place in the record. A deleted piece has nothing, so the piece an Update puts
## back in its place joins what every piece shared. Nor has a brush the record
## names that is no longer ours: an Update leaves it standing, and reading it as
## the piece gave the new piece a stranger's name, entity and visgroups (#1221).
func _carry_of(record: HFGenerator) -> HFRebuildCarry:
	var keys := _old_piece_keys(record)
	var built := build_faces(record.type, record.settings, record.run)
	var pieces: Array = []
	var as_built: Dictionary = {}
	for i in record.brush_ids.size():
		var brush = _owned_brush(str(record.brush_ids[i]), record.generator_id)
		if brush:
			pieces.append([keys[i], brush])
			var was := _built_at(record, str(record.brush_ids[i]), brush)
			as_built[keys[i]] = _faces_as_built(brush, built[i] if i < built.size() else [], was)
	var visgroups = root.get("visgroup_system") if root else null
	var carry := HFRebuildCarry.capture(pieces, CARRIED, visgroups)
	# A face still in the look its builder gave it is the builder's to dress again.
	# A Sweep dresses its pieces in the looks of the faces it was picked from, so a
	# Re-pick's pieces wear the new faces' looks, not the old ones (#1932).
	for key in as_built:
		carry.forget_faces(key, as_built[key])
	return carry


## The pieces whose authored appearance a rebuild with these settings could not
## put back: the ones a shorter piece list drops, and the ones whose faces would
## no longer line up one to one.
##
## Asked before an Update, because that is the last moment the user can choose
## Detach instead. A piece with nothing authored on it is never at risk; there is
## nothing there to lose.
func appearance_at_risk(generator_id: String, settings: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	if not generators.has(generator_id):
		return out
	var record: HFGenerator = generators[generator_id]
	var face_sets := build_faces(record.type, settings, record.run)
	var built := build_faces(record.type, record.settings, record.run)
	# Each old piece is matched to the new piece the carry gives its look to.
	var new_keys := _piece_keys(face_sets.size(), Array(cutter_pieces(record.type, settings)))
	var old_keys := _old_piece_keys(record)
	for i in record.brush_ids.size():
		var brush = _owned_brush(str(record.brush_ids[i]), generator_id)
		if brush == null:
			continue
		var piece_built: Array = built[i] if i < built.size() else []
		var was := _built_at(record, str(record.brush_ids[i]), brush)
		if _faces_as_built(brush, piece_built, was).size() == brush.faces.size():
			continue
		var j := new_keys.find(old_keys[i])
		if j < 0 or face_sets[j].size() != brush.faces.size():
			out.append(str(record.brush_ids[i]))
	return out


## The carry's name for each piece the record holds, read from the settings it was
## built with.
static func _old_piece_keys(record: HFGenerator) -> PackedStringArray:
	var cut_indices := Array(cutter_pieces(record.type, record.settings))
	return _piece_keys(record.brush_ids.size(), cut_indices)


## The faces of `brush` nobody has worked on since its builder made them from
## `built`, the face set the piece came from: each still in the look the builder
## gave it, with no paint, no hand UV layout and no texture group. A face the
## builder made plain and the Paint tab, a `.map` name or a hidden face type has
## changed since is work; so is a Sweep's face dressed in anything but the look of
## the face it was picked from (#1932). By index. When the piece has another
## number of faces than `built`, each is held to a plain face, as before a builder
## could dress one. `was` is where the piece stood when it was built, which a move
## or a turn of the structure since has left behind (`_looks_as_built()`).
static func _faces_as_built(brush, built: Array, was: Transform3D) -> PackedInt32Array:
	var looks: Array = []
	if built.size() == brush.faces.size():
		for face in built:
			if face != null:
				face.ensure_geometry()
		# A box piece lists its faces in box order, so each is matched by the way it
		# points, as the carry matches them.
		var sources := HFRebuildCarry._stored_face_for_each(brush, built)
		for i in brush.faces.size():
			looks.append(built[sources[i]])
	else:
		for face in brush.faces:
			looks.append(FaceData.new())
	var out := PackedInt32Array()
	for i in brush.faces.size():
		var face = brush.faces[i]
		var look = looks[i]
		if face == null or look == null:
			out.append(i)
			continue
		if not face.paint_layers.is_empty() or face.has_hand_layout():
			continue
		if face.uv_group != 0 or not _looks_as_built(face, look, was, brush.global_transform):
			continue
		out.append(i)
	return out


## Where the piece `brush_id` of `record`, `brush`, stood when it was built: its
## signature's place, or where it stands now when it has none.
static func _built_at(record: HFGenerator, brush_id: String, brush) -> Transform3D:
	var signature: Dictionary = record.brush_signatures.get(brush_id, {})
	if signature.is_empty():
		return brush.global_transform
	return _signature_transform(record, signature)


## Whether `face`, on a piece standing at `now`, has the look `look` gave it on the
## piece built at `was`. Texture Lock, on by default, rewrites a face's offset,
## turn and the sign of its scale through a move or a turn so the texture stays
## where it was on the piece, and that is not work done on it (#1969). So where
## the texture lies is read as what the face shows at its corners, in the piece's
## own frame, as Compare reads it (#1989): the same picture, or the same picture a
## whole number of repeats along. A face whose values are the look's is the other
## way a texture stays put, in the level, as a move with Texture Lock off leaves it.
static func _looks_as_built(face, look, was: Transform3D, now: Transform3D) -> bool:
	if face.appearance_matches(look):
		return true
	var laid := FaceData.new()
	laid.copy_appearance_from(face)
	laid.uv_scale = look.uv_scale
	laid.uv_offset = look.uv_offset
	laid.uv_rotation = look.uv_rotation
	if not laid.appearance_matches(look):
		return false
	var as_built := _shown_at(face, look, was)
	var shown := _shown_at(face, face, now)
	if as_built.is_empty() or as_built.size() != shown.size():
		return false
	var repeats := (shown[0] - as_built[0]).round()
	for i in shown.size():
		if (shown[i] - as_built[i] - repeats).length() > SHOWN_NEAR:
			return false
	return true


## The UVs `look` lays at the corners of `face` on a piece standing at `place`.
static func _shown_at(face, look, place: Transform3D) -> PackedVector2Array:
	var probe := FaceData.new()
	probe.local_verts = face.local_verts
	probe.normal = face.normal
	probe.copy_appearance_from(look)
	probe.world_transform = place
	return probe.projected_uvs()


## Delete only the brushes that still say they belong to this generator.
##
## The record is a hint. Brush ids are reissued as the counter moves, and a stale
## entry could otherwise name a brush that now belongs to something else — so a
## rebuild would quietly delete a neighbour's geometry. The meta on the brush is
## the authority, not the list.
func _delete_brushes(brush_ids: PackedStringArray, generator_id: String) -> void:
	if root == null or root.get("brush_system") == null:
		return
	for brush_id in brush_ids:
		var brush = _brush(str(brush_id))
		if brush == null:
			continue
		if str(brush.get_meta(GENERATOR_META, "")) != generator_id:
			continue
		root.brush_system.delete_brush_by_id(str(brush_id))


func _brush(brush_id: String):
	if brush_id == "" or root == null or root.get("brush_system") == null:
		return null
	return root.brush_system.find_brush_by_id(brush_id)


## A brush, but only if it still says it belongs to this generator.
##
## The record is a hint. Ids are reissued as the counter moves, so asking about a
## brush by id alone can answer about somebody else's geometry.
func _owned_brush(brush_id: String, generator_id: String):
	var brush = _brush(brush_id)
	if brush == null or str(brush.get_meta(GENERATOR_META, "")) != generator_id:
		return null
	return brush


## Remember what each piece was, so a later question about what has changed has
## something to compare against.
func _record_signatures(record: HFGenerator) -> void:
	record.brush_signatures.clear()
	for brush_id in record.brush_ids:
		var brush = _brush(str(brush_id))
		if brush == null:
			continue
		record.brush_signatures[str(brush_id)] = {
			"origin": brush.global_transform.origin,
			"basis": brush.global_transform.basis,
			"geometry": _geometry_hash(brush),
		}


## What a piece *is*, independent of where it is: its rotation, its shape, its
## size and its face vertices, rounded to a thousandth so that the float
## formatting a save and reload goes through does not read as an edit.
func _geometry_hash(brush) -> String:
	if brush == null:
		return ""
	return _geometry_hash_in_basis(brush, brush.global_transform.basis)


## The same question asked about a basis the piece is not necessarily standing
## in. A structure turned as a whole has every piece in a new basis and none of
## them changed, so the comparison has to be made in the basis each piece was
## recorded in rather than the one it is standing in now.
##
## `face_list` reads other faces than the brush holds now, for a step's faces as
## it was loaded (#878).
static func _geometry_hash_in_basis(brush, basis: Basis, face_list: Array = []) -> String:
	if brush == null:
		return ""
	var parts := PackedStringArray()
	parts.append("s%d" % int(brush.shape))
	parts.append(_rounded(brush.size))
	parts.append(_rounded(basis.x))
	parts.append(_rounded(basis.y))
	parts.append(_rounded(basis.z))
	var read_from: Array = face_list if not face_list.is_empty() else brush.faces
	for face in read_from:
		if face == null:
			continue
		for vertex in face.local_verts:
			parts.append(_rounded(vertex))
		parts.append("/")
	return str(", ".join(parts).hash())


static func _rounded(v: Vector3) -> String:
	return "%.3f %.3f %.3f" % [v.x, v.y, v.z]
