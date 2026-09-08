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
