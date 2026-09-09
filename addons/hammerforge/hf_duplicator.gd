@tool
class_name HFDuplicator
extends RefCounted

## Manages a set of duplicate brush copies laid out from source brushes.
##
## Three layouts share one instance bookkeeping: a linear run of progressive
## offsets, a radial ring about an axis, and a 3D lattice. Radial copies compose
## their transform through `HFTransformSystem`, so there is one rotation
## implementation in the plugin rather than two.

enum ArrayMode { LINEAR, RADIAL, GRID }

## The most brushes one array may make. The same budget the dome builder keeps,
## in the same currency: brushes that will exist afterwards. A 32 by 32 by 32
## lattice is thirty-two thousand of them, which is not a level-editing operation
## but a hang, and the layout controls will happily ask for it.
const MAX_COPY_BRUSHES := 256


## Where one copy goes, applied to a source brush's own transform.
##
## The one definition of the layout arithmetic. What the ghost draws and what the
## button builds read the same placements, so the two cannot drift into disagreeing
## about how many copies there are or where they land.
class CopyPlacement:
	extends RefCounted

	var rotation: Basis = Basis.IDENTITY
	var pivot: Vector3 = Vector3.ZERO
	var translation: Vector3 = Vector3.ZERO

	func applied_to(source: Transform3D) -> Transform3D:
		var out: Transform3D = HFTransformSystem.rotated_transform(source, rotation, pivot)
		out.origin += translation
		return out


static func _translated(translation: Vector3) -> CopyPlacement:
	var placement := CopyPlacement.new()
	placement.translation = translation
	return placement


## A run of copies, each one offset further than the last.
static func linear_placements(p_count: int, p_offset: Vector3) -> Array:
	var out: Array = []
	for copy_index in range(1, maxi(0, p_count) + 1):
		out.append(_translated(p_offset * copy_index))
	return out


## A ring of copies about `p_pivot`, optionally climbing as it turns.
static func radial_placements(
	p_count: int, p_axis_index: int, p_step_degrees: float, p_pivot: Vector3, p_rise: float = 0.0
) -> Array:
	var out: Array = []
	var climb := HFTransformSystem.axis_vector(p_axis_index) * p_rise
	for copy_index in range(1, maxi(0, p_count) + 1):
		var placement := CopyPlacement.new()
		placement.rotation = HFTransformSystem.rotation_basis(
			p_axis_index, deg_to_rad(p_step_degrees * copy_index)
		)
		placement.pivot = p_pivot
		placement.translation = climb * float(copy_index)
		out.append(placement)
	return out


## A lattice of copies. `p_counts` includes the source cell on each axis, so the
## cell the source already occupies is not among the placements.
static func grid_placements(p_counts: Vector3i, p_spacing: Vector3) -> Array:
	var counts := Vector3i(maxi(1, p_counts.x), maxi(1, p_counts.y), maxi(1, p_counts.z))
	var out: Array = []
	for ix in counts.x:
		for iy in counts.y:
			for iz in counts.z:
				if ix == 0 and iy == 0 and iz == 0:
					continue
				out.append(
					_translated(Vector3(p_spacing.x * ix, p_spacing.y * iy, p_spacing.z * iz))
				)
	return out


## The placements a layout produces, read from one dictionary of control values.
##
## Both the ghost and the button go through here, so the numbers on screen and the
## brushes that appear are the same arithmetic rather than two copies of it.
static func placements_for(mode: int, params: Dictionary) -> Array:
	match mode:
		ArrayMode.RADIAL:
			return radial_placements(
				int(params.get("count", 0)),
				int(params.get("axis_index", 1)),
				float(params.get("step_degrees", 90.0)),
				params.get("pivot", Vector3.ZERO),
				float(params.get("rise", 0.0))
			)
		ArrayMode.GRID:
			return grid_placements(
				params.get("counts", Vector3i.ONE), params.get("spacing", Vector3.ZERO)
			)
		_:
			return linear_placements(
				int(params.get("count", 0)), params.get("offset", Vector3.ZERO)
			)


## Whether an array of this size is one to build, asked before an undo action is
## opened and before a ghost is drawn.
##
## The count the controls ask for is said back, the way the dome builder says the
## number of panels it was asked for, because "too many" without a number leaves
## the user guessing which control to turn.
static func can_generate(copy_count: int, source_count: int) -> HFOpResult:
	if source_count < 1:
		return HFOpResult.fail("Array: nothing selected to copy", "Select a brush first")
	if copy_count < 1:
		return HFOpResult.fail("Array: that layout makes no copies", "Raise the count")
	var total := copy_count * source_count
	if total > MAX_COPY_BRUSHES:
		return HFOpResult.fail(
			(
				"Array: %d copies of %d brush%s is %d brushes"
				% [copy_count, source_count, "" if source_count == 1 else "es", total]
			),
			"Keep the total at or below %d" % MAX_COPY_BRUSHES
		)
	return HFOpResult.success("%d copies" % copy_count)


var duplicator_id := ""
var source_brush_ids: PackedStringArray = PackedStringArray()
var instance_groups: Array = []  # Array of PackedStringArray, one per copy
var count := 0
var offset := Vector3.ZERO
var mode: int = ArrayMode.LINEAR
## Radial layout: rotation axis (0 = X, 1 = Y, 2 = Z), degrees between copies,
## and the world point the ring turns about.
var axis_index: int = 1
var step_degrees: float = 90.0
var pivot: Vector3 = Vector3.ZERO
## Distance each radial copy climbs along the rotation axis. Zero is a flat
## ring; anything else is a helix, and with a box as the source, a spiral stair.
var rise: float = 0.0
## Grid layout: copies per axis including the source cell, and the gap between
## cells on each axis.
var grid_counts: Vector3i = Vector3i(2, 1, 2)
var grid_spacing: Vector3 = Vector3(64.0, 64.0, 64.0)


func _init() -> void:
	duplicator_id = "dup_%d" % Time.get_ticks_msec()


## Create N copies of the source brushes with progressive offset.
## brush_system is untyped to avoid circular preload.
func generate(brush_system, p_count: int, p_offset: Vector3) -> bool:
	if source_brush_ids.is_empty() or p_count < 1:
		return false
	count = p_count
	offset = p_offset
	instance_groups.clear()

	for placement in linear_placements(p_count, p_offset):
		var copy_ids := PackedStringArray()
		for source_id in source_brush_ids:
			var brush_node = brush_system.find_brush_by_id(source_id)
			if not is_instance_valid(brush_node):
				push_warning("HFDuplicator: source brush '%s' not found, skipping" % source_id)
				continue
			var info: Dictionary = brush_system.build_duplicate_info(
				brush_node, placement.translation
			)
			if info.is_empty():
				continue
			var new_brush = brush_system.create_brush_from_info(info)
			if not is_instance_valid(new_brush):
				continue
			new_brush.set_meta("duplicator_instance_of", duplicator_id)
			var new_id: String = str(info.get("brush_id", ""))
			if new_id != "":
				copy_ids.append(new_id)
		instance_groups.append(copy_ids)

	# Tag source brushes
	for source_id in source_brush_ids:
		var source_brush = brush_system.find_brush_by_id(source_id)
		if is_instance_valid(source_brush):
			source_brush.set_meta("duplicator_id", duplicator_id)

	return true


## Create N copies rotated `step_degrees` apart about `p_pivot`.
##
## The step is given directly rather than as a total sweep so there is no
## ambiguity about whether the last copy lands on the end angle. To close a full
## ring, pass `360.0 / (p_count + 1)`.
func generate_radial(
	brush_system,
	p_count: int,
	p_axis_index: int,
	p_step_degrees: float,
	p_pivot: Vector3,
	p_rise: float = 0.0
) -> bool:
	if source_brush_ids.is_empty() or p_count < 1:
		return false
	mode = ArrayMode.RADIAL
	count = p_count
	axis_index = p_axis_index
	step_degrees = p_step_degrees
	pivot = p_pivot
	rise = p_rise
	instance_groups.clear()

	for placement in radial_placements(p_count, p_axis_index, p_step_degrees, p_pivot, p_rise):
		var copy_ids := PackedStringArray()
		for source_id in source_brush_ids:
			var info := _copy_info(brush_system, source_id)
			if info.is_empty():
				continue
			var source_xform: Transform3D = info.get("transform", Transform3D.IDENTITY)
			info["transform"] = placement.applied_to(source_xform)
			info.erase("center")
			var new_id := _spawn_copy(brush_system, info)
			if new_id != "":
				copy_ids.append(new_id)
		instance_groups.append(copy_ids)

	_tag_sources(brush_system)
	return true


## Create a lattice of copies. `p_counts` includes the source cell on each axis,
## so 2x1x2 produces three copies around one original.
func generate_grid(brush_system, p_counts: Vector3i, p_spacing: Vector3) -> bool:
	if source_brush_ids.is_empty():
		return false
	var counts := Vector3i(maxi(1, p_counts.x), maxi(1, p_counts.y), maxi(1, p_counts.z))
	if counts.x * counts.y * counts.z <= 1:
		return false
	mode = ArrayMode.GRID
	grid_counts = counts
	grid_spacing = p_spacing
	count = counts.x * counts.y * counts.z - 1
	instance_groups.clear()

	for placement in grid_placements(counts, p_spacing):
		var copy_ids := PackedStringArray()
		for source_id in source_brush_ids:
			var brush_node = brush_system.find_brush_by_id(source_id)
			if not is_instance_valid(brush_node):
				push_warning("HFDuplicator: source brush '%s' not found, skipping" % source_id)
				continue
			var info: Dictionary = brush_system.build_duplicate_info(
				brush_node, placement.translation
			)
			if info.is_empty():
				continue
			var new_id := _spawn_copy(brush_system, info)
			if new_id != "":
				copy_ids.append(new_id)
		instance_groups.append(copy_ids)

	_tag_sources(brush_system)
	return true


func _copy_info(brush_system, source_id: String) -> Dictionary:
	var brush_node = brush_system.find_brush_by_id(source_id)
	if not is_instance_valid(brush_node):
		push_warning("HFDuplicator: source brush '%s' not found, skipping" % source_id)
		return {}
	return brush_system.build_duplicate_info(brush_node, Vector3.ZERO)


func _spawn_copy(brush_system, info: Dictionary) -> String:
	var new_brush = brush_system.create_brush_from_info(info)
	if not is_instance_valid(new_brush):
		return ""
	new_brush.set_meta("duplicator_instance_of", duplicator_id)
	return str(info.get("brush_id", ""))


func _tag_sources(brush_system) -> void:
	for source_id in source_brush_ids:
		var source_brush = brush_system.find_brush_by_id(source_id)
		if is_instance_valid(source_brush):
			source_brush.set_meta("duplicator_id", duplicator_id)


## Every number this array was laid out from, in the shape `placements_for` takes.
##
## What the section loads back into its controls when a piece of an existing
## array is selected. All three layouts are reported at once, because changing
## the layout of an existing array is one of the things a rebuild is for and the
## numbers for the layout you are leaving should still be there when you come
## back to it.
func settings() -> Dictionary:
	return {
		"count": count,
		"offset": offset,
		"axis_index": axis_index,
		"step_degrees": step_degrees,
		"rise": rise,
		"pivot": pivot,
		"counts": grid_counts,
		"spacing": grid_spacing,
	}


## Rebuild this array's copies from new numbers, keeping the array itself.
##
## The copies are thrown away and made again rather than moved, because a change
## of layout — or of count — changes how many there are. `clear_instances()`
## takes the `duplicator_id` back off the sources and each `generate*` puts it
## on again, so the array keeps its identity across the rebuild and the section
## stays an editor for it.
func regenerate(brush_system, p_mode: int, params: Dictionary) -> bool:
	if source_brush_ids.is_empty():
		return false
	clear_instances(brush_system)
	if not _lay_out(brush_system, p_mode, params):
		return false
	# Every source can have been deleted since the array was made — nothing cleans
	# a duplicator record when a brush goes — and the layout calls answer "yes" to
	# having run rather than to having produced anything. An array of no copies is
	# not an array, and saying so is what lets the caller drop the dead record
	# rather than leave one that cannot be rebuilt.
	return not get_all_instance_ids().is_empty()


func _lay_out(brush_system, p_mode: int, params: Dictionary) -> bool:
	match p_mode:
		ArrayMode.RADIAL:
			return generate_radial(
				brush_system,
				int(params.get("count", count)),
				int(params.get("axis_index", axis_index)),
				float(params.get("step_degrees", step_degrees)),
				params.get("pivot", pivot),
				float(params.get("rise", rise))
			)
		ArrayMode.GRID:
			return generate_grid(
				brush_system, params.get("counts", grid_counts), params.get("spacing", grid_spacing)
			)
		_:
			mode = ArrayMode.LINEAR
			return generate(
				brush_system, int(params.get("count", count)), params.get("offset", offset)
			)


## Forget the array without touching a single brush.
##
## The copies stay exactly where they are, as ordinary geometry. This is the way
## out for someone who wants the layout an array gave them and then wants to edit
## one copy of it — the answer that is not "Remove Array", which deletes them.
func detach(brush_system) -> void:
	for group in instance_groups:
		for brush_id in group:
			var copy_brush = brush_system.find_brush_by_id(brush_id)
			if is_instance_valid(copy_brush) and copy_brush.has_meta("duplicator_instance_of"):
				copy_brush.remove_meta("duplicator_instance_of")
	for source_id in source_brush_ids:
		var source_brush = brush_system.find_brush_by_id(source_id)
		if is_instance_valid(source_brush) and source_brush.has_meta("duplicator_id"):
			source_brush.remove_meta("duplicator_id")
	instance_groups.clear()
	count = 0


## Where each copy of this array should be standing, keyed by its brush id.
##
## Recomputed from the live sources rather than remembered, so it costs nothing
## in the `.hflevel` and cannot go stale: an array's arithmetic is deterministic,
## and where a copy *would* be rebuilt is therefore always computable.
##
## Answers with nothing when the copies and the sources no longer pair up — a
## source deleted after the array was made shifts every group — because guessing
## the pairing would report every copy in the level as moved.
func expected_copy_transforms(brush_system) -> Dictionary:
	var out: Dictionary = {}
	var placements := placements_for(mode, settings())
	if placements.size() != instance_groups.size():
		return out
	var sources: Array = []
	for source_id in source_brush_ids:
		var source = brush_system.find_brush_by_id(source_id)
		if not is_instance_valid(source):
			return {}
		sources.append(source)
	for i in instance_groups.size():
		var group: PackedStringArray = instance_groups[i]
		if group.size() != sources.size():
			return {}
		for j in group.size():
			out[group[j]] = placements[i].applied_to(sources[j].global_transform)
	return out


## What has happened to this array's copies since it laid them out.
##
## `move` is the one transform most of the copies would need to reach their
## placement, `followers` is how many agree on it, and `strays` names the ones
## that do not.
##
## Read as a vote for the same reason the structure records are: a source that has
## been dragged leaves every copy needing the same move, and calling that twelve
## hand edits would be a lie. One copy pulled out of a ring of twelve is the other
## reading, and it is the one an Update is about to undo.
func relocation_vote(brush_system) -> Dictionary:
	var quiet := {"move": Transform3D.IDENTITY, "followers": 0, "strays": PackedStringArray()}
	var expected := expected_copy_transforms(brush_system)
	if expected.is_empty():
		return quiet
	# Group the copies by the move each of them would need. Transform3D is not a
	# dictionary key worth trusting across float noise, so the groups are built by
	# comparing against the moves already seen.
	var moves: Array = []
	var groups: Array = []
	for brush_id in expected:
		var copy_brush = brush_system.find_brush_by_id(brush_id)
		if not is_instance_valid(copy_brush):
			continue
		var delta: Transform3D = expected[brush_id] * copy_brush.global_transform.affine_inverse()
		var found := -1
		for i in moves.size():
			if _same_placement(moves[i], delta):
				found = i
				break
		if found < 0:
			moves.append(delta)
			groups.append(PackedStringArray([str(brush_id)]))
		else:
			groups[found].append(str(brush_id))
	if moves.is_empty():
		return quiet
	var winner := 0
	for i in groups.size():
		if groups[i].size() > groups[winner].size():
			winner = i
	var strays := PackedStringArray()
	for i in groups.size():
		if i == winner:
			continue
		for brush_id in groups[i]:
			strays.append(brush_id)
	return {"move": moves[winner], "followers": groups[winner].size(), "strays": strays}


## What each copy is, apart from where it is standing.
##
## Values only, and no resource identity: two copies of one brush hold equal but
## separate `FaceData` and separate weight images, so a signature that included
## identity would report every copy in a painted array as unique. That is exactly
## what `HFBrushChangeTracker._signature()` does, correctly — it asks whether one
## brush has changed since it last looked at *that* brush, and identity is a
## sound answer to that question. This asks whether two brushes are the same
## shape, which is a different question.
##
## The transform is not in it either: movement is the other vote's business.
##
## Public because a hollow's walls ask the same question of themselves. They are
## each a different shape by design, so they cannot be grouped against each other
## the way copies are — but "is this brush still the shape it was" is the same
## computation, and there is no reason for two of it.
static func shape_signature(brush) -> String:
	if not is_instance_valid(brush):
		return ""
	var parts := PackedStringArray(
		[
			"s%d" % int(brush.shape),
			"n%d" % int(brush.sides),
			"o%d" % int(brush.operation),
			_rounded(brush.size),
		]
	)
	for face in brush.faces:
		if face == null:
			parts.append("-")
			continue
		parts.append(
			(
				"m%d/p%d/r%.4f/%s/%s"
				% [
					int(face.material_idx),
					int(face.uv_projection),
					float(face.uv_rotation),
					str(face.uv_scale),
					str(face.uv_offset)
				]
			)
		)
		for vertex in face.local_verts:
			parts.append(_rounded(vertex))
		for uv in face.custom_uvs:
			parts.append(str(uv))
		# The weight images themselves are left out. Hashing every texel of every
		# face of every copy measured 127 ms over a full-budget array against 22 ms
		# without, on an event that fires whenever the selection changes — so a
		# layer added, removed, retextured or resized is noticed, and painting
		# inside an existing one is not.
		for layer in face.paint_layers:
			if layer == null:
				parts.append("-")
				continue
			var image_size := "none"
			if layer.weight_image != null and not layer.weight_image.is_empty():
				image_size = str(layer.weight_image.get_size())
			parts.append(
				(
					"t%s/b%d/o%.4f/%s"
					% [
						layer.texture.resource_path if layer.texture else "",
						int(layer.blend_mode),
						float(layer.opacity),
						image_size
					]
				)
			)
		if face.displacement == null:
			parts.append("d-")
		else:
			parts.append(
				(
					"d%d/%.4f/%d"
					% [
						face.displacement.distances.size(),
						float(face.displacement.elevation),
						hash(face.displacement.distances)
					]
				)
			)
	return "/".join(parts)


static func _rounded(v: Vector3) -> String:
	return "%.3f %.3f %.3f" % [v.x, v.y, v.z]


## The copies that are not the shape the rest of the array agrees on.
##
## Grouped rather than compared against the source, and for the same reason the
## move is read as a vote: paint the original and every copy differs from it at
## once, which is the source having changed rather than anybody editing copies.
## Copies that still agree with each other are the array; a copy on its own is
## the edit.
func reshaped_copy_ids(brush_system) -> PackedStringArray:
	var groups: Dictionary = {}
	for brush_id in expected_copy_transforms(brush_system):
		var copy_brush = brush_system.find_brush_by_id(brush_id)
		if not is_instance_valid(copy_brush):
			continue
		var signature := shape_signature(copy_brush)
		if not groups.has(signature):
			groups[signature] = PackedStringArray()
		groups[signature].append(str(brush_id))
	if groups.size() < 2:
		return PackedStringArray()
	var winner := ""
	for signature in groups:
		if winner == "" or groups[signature].size() > groups[winner].size():
			winner = signature
	var strays := PackedStringArray()
	for signature in groups:
		if signature == winner:
			continue
		for brush_id in groups[signature]:
			strays.append(brush_id)
	return strays


## Everything a rebuild of this array would undo: the copies that have been moved
## and the copies that have been reshaped or repainted.
func edited_copy_ids(brush_system) -> PackedStringArray:
	var out := displaced_copy_ids(brush_system)
	for brush_id in reshaped_copy_ids(brush_system):
		if not out.has(brush_id):
			out.append(brush_id)
	return out


## The copies that are not standing where the rest of the array agrees it stands.
##
## What an Update would move, and therefore what it would undo of the user's own
## work. A copy that has been resized, reshaped or repainted rather than dragged
## is not among them: that needs a signature recorded per copy, which is what a
## structure has and an array does not.
func displaced_copy_ids(brush_system) -> PackedStringArray:
	return relocation_vote(brush_system)["strays"]


## Whether the copies have been left behind by a source that moved.
##
## An Update in that state carries the whole array over to follow its source,
## which is what an array is for. It is said differently from a hand edit because
## nothing of the user's is lost.
func copies_follow_a_moved_source(brush_system) -> bool:
	var vote := relocation_vote(brush_system)
	if int(vote["followers"]) < 1:
		return false
	return not _same_placement(vote["move"], Transform3D.IDENTITY)


static func _same_placement(a: Transform3D, b: Transform3D) -> bool:
	return HFTransformSystem.same_transform(a, b)


## Remove all instance brushes created by this duplicator.
func clear_instances(brush_system) -> void:
	for group in instance_groups:
		for brush_id in group:
			brush_system.delete_brush_by_id(brush_id)
	instance_groups.clear()

	# Remove meta from source brushes (if they still exist)
	for source_id in source_brush_ids:
		var source_brush = brush_system.find_brush_by_id(source_id)
		if is_instance_valid(source_brush) and source_brush.has_meta("duplicator_id"):
			source_brush.remove_meta("duplicator_id")
	count = 0


## Return all instance brush IDs flattened into one array.
func get_all_instance_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for group in instance_groups:
		for brush_id in group:
			out.append(brush_id)
	return out


## Serialize to dictionary for state capture.
func to_dict() -> Dictionary:
	var groups_arr: Array = []
	for g in instance_groups:
		groups_arr.append(Array(g))
	return {
		"duplicator_id": duplicator_id,
		"source_brush_ids": Array(source_brush_ids),
		"count": count,
		"offset": [offset.x, offset.y, offset.z],
		"instance_groups": groups_arr,
		"mode": mode,
		"axis_index": axis_index,
		"step_degrees": step_degrees,
		"rise": rise,
		"pivot": [pivot.x, pivot.y, pivot.z],
		"grid_counts": [grid_counts.x, grid_counts.y, grid_counts.z],
		"grid_spacing": [grid_spacing.x, grid_spacing.y, grid_spacing.z],
	}


## Reconstruct a duplicator from a serialized dictionary.
static func from_dict(data: Dictionary) -> HFDuplicator:
	var dup := HFDuplicator.new()
	dup.duplicator_id = str(data.get("duplicator_id", dup.duplicator_id))
	var src_arr = data.get("source_brush_ids", [])
	var src := PackedStringArray()
	for s in src_arr:
		src.append(str(s))
	dup.source_brush_ids = src
	dup.count = int(data.get("count", 0))
	var off_arr = data.get("offset", [0.0, 0.0, 0.0])
	if off_arr is Array and off_arr.size() >= 3:
		dup.offset = Vector3(float(off_arr[0]), float(off_arr[1]), float(off_arr[2]))
	# A dictionary written before array modes existed has no "mode" key and loads
	# as the linear layout it was.
	dup.mode = int(data.get("mode", ArrayMode.LINEAR))
	dup.axis_index = int(data.get("axis_index", 1))
	dup.step_degrees = float(data.get("step_degrees", 90.0))
	# A duplicator written before radial arrays could climb loads as a flat ring.
	dup.rise = float(data.get("rise", 0.0))
	var pivot_arr = data.get("pivot", [0.0, 0.0, 0.0])
	if pivot_arr is Array and pivot_arr.size() >= 3:
		dup.pivot = Vector3(float(pivot_arr[0]), float(pivot_arr[1]), float(pivot_arr[2]))
	var counts_arr = data.get("grid_counts", [2, 1, 2])
	if counts_arr is Array and counts_arr.size() >= 3:
		dup.grid_counts = Vector3i(int(counts_arr[0]), int(counts_arr[1]), int(counts_arr[2]))
	var spacing_arr = data.get("grid_spacing", [64.0, 64.0, 64.0])
	if spacing_arr is Array and spacing_arr.size() >= 3:
		dup.grid_spacing = Vector3(
			float(spacing_arr[0]), float(spacing_arr[1]), float(spacing_arr[2])
		)
	var groups = data.get("instance_groups", [])
	dup.instance_groups = []
	for g in groups:
		var psa := PackedStringArray()
		for item in g:
			psa.append(str(item))
		dup.instance_groups.append(psa)
	return dup
