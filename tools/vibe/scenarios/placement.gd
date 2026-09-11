@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Moving and resizing a brush that already exists.
##
## Creating a brush goes through `_usable_size()`, which takes the absolute
## value, floors each axis at `MIN_BRUSH_EXTENT`, and warns about what it
## changed. Resizing one goes through `set_brush_transform_by_id()`, and nudging
## one goes through `nudge_brushes_by_id()`. Whether those two agree with the
## creation path about what a size and a position are is the question here --
## they reach the same property on the same node, from the same dock fields.


func id() -> String:
	return "placement"


func summary() -> String:
	return "resize and nudge at their edges, against what the create path allows"


func _bid(node: Node) -> String:
	return str(node.get_meta("brush_id", ""))


func run() -> void:
	await _what_the_create_path_allows()
	await _what_the_resize_path_allows()
	await _what_the_nudge_path_allows()
	await _what_the_array_path_allows()


func _finite(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)


func _created_size(root: Node3D, size: Vector3) -> Vector3:
	var b = root.create_brush_from_info({"shape": 0, "size": size, "center": Vector3.ZERO})
	if b == null:
		return Vector3(-99999, -99999, -99999)
	return b.size


## The baseline: what a brush can be created with.
func _what_the_create_path_allows() -> void:
	var root: Node3D = await fresh_root()
	for size in [
		Vector3(0, 64, 64),
		Vector3(-64, 64, 64),
		Vector3(NAN, 64, 64),
		Vector3(INF, 64, 64),
	]:
		var got := _created_size(root, size)
		note("create_brush_from_info with size %s" % size, "the brush ends up %s" % got)
	await frame()
	note("brushes created", root.brush_system.get_live_brush_count())


## The resize path, which the dock's size fields and every scripted resize use.
func _what_the_resize_path_allows() -> void:
	var accepted: Array = []
	for size in [
		Vector3(0, 64, 64),
		Vector3(-64, 64, 64),
		Vector3(NAN, 64, 64),
		Vector3(INF, 64, 64),
		Vector3(NAN, NAN, NAN),
	]:
		var root: Node3D = await fresh_root()
		var b := box(root, Vector3(64, 64, 64))
		await frame()
		root.set_brush_transform_by_id(_bid(b), size, b.global_position)
		await frame()
		var got: Vector3 = b.size
		var extent := HFVibe.local_extent(b)
		note(
			"set_brush_transform_by_id with size %s" % size,
			"brush.size is now %s, its faces span %s" % [got, extent]
		)
		if not _finite(got):
			accepted.append("size %s -> %s" % [size, got])
			known(
				378,
				"resizing a brush to a non-finite size is accepted where creating one with it is not",
				(
					"set_brush_transform_by_id() wrote %s straight onto brush.size and the faces now span %s; create_brush_from_info() puts the same value through _usable_size(), which floors it and warns"
					% [got, extent]
				)
			)
		elif got.x <= 0.0 or got.y <= 0.0 or got.z <= 0.0:
			accepted.append("size %s -> %s" % [size, got])
			known(
				378,
				"resizing a brush to a zero or negative size is accepted where creating one with it is not",
				(
					"brush.size is now %s; a negative size builds the brush inside out and a zero size builds no volume, which is what _usable_size()'s own warning says on the create path"
					% got
				)
			)
		for problem in HFVibe.check_invariants(root):
			known(378, "after resizing to %s the invariant checker sees it too" % size, problem)
	note("sizes the resize path accepted that the create path would not", accepted.size())


## The nudge path. `offset.is_zero_approx()` is the only guard on the way in,
## and a NaN offset is not approximately zero.
func _what_the_nudge_path_allows() -> void:
	for offset in [Vector3(NAN, 0, 0), Vector3(0, INF, 0), Vector3(NAN, NAN, NAN)]:
		var root: Node3D = await fresh_root()
		var b := box(root, Vector3(64, 64, 64))
		await frame()
		root.nudge_brushes_by_id([_bid(b)], offset)
		await frame()
		var pos: Vector3 = b.global_position
		note("nudge by %s" % offset, "the brush is now at %s" % pos)
		if not _finite(pos):
			known(
				379,
				"nudging a brush by a non-finite offset puts it at a non-finite position",
				(
					"offset %s leaves global_position at %s -- the only guard on nudge_brushes_by_id() is `offset.is_zero_approx()`, and NaN is not approximately zero. The brush's AABB is now NaN, so it cannot be selected by a box pick, framed, or found again except by id."
					% [offset, pos]
				)
			)
		for problem in HFVibe.check_invariants(root):
			known(379, "after nudging by %s the invariant checker sees it too" % offset, problem)


## The array. `can_generate()` checks the copy count and the source count and
## never looks at the offset, the step angle or the rise -- so the one guard on
## the way in cannot see the number that decides where the copies land.
func _what_the_array_path_allows() -> void:
	for offset in [Vector3(NAN, 0, 0), Vector3(0, INF, 0)]:
		var root: Node3D = await fresh_root()
		var b := box(root, Vector3(64, 64, 64))
		await frame()
		var made = root.create_duplicate_array(PackedStringArray([_bid(b)]), 5, offset)
		await frame()
		var lost := 0
		var live: Array = root.draft_brushes_node.get_children()
		for child in live:
			if not _finite((child as Node3D).global_position):
				lost += 1
		note(
			"a 5-copy array with offset %s" % offset,
			(
				"created: %s, the level holds %d brushes and %d of them are at a non-finite position"
				% [made != null, live.size(), lost]
			)
		)
		if lost > 0:
			known(
				382,
				"an array with a non-finite offset builds every copy at a NaN position",
				(
					"five copies asked for with offset %s: %d of the %d brushes in the level are now at a non-finite position. can_generate() is the only check on the way in and it looks at the copy count and the source count, never at the offset. Each of those copies has a NaN AABB, so none can be box-selected, framed or found again -- and unlike a single bad nudge (#379) one action makes as many as the count asked for."
					% [offset, lost, live.size()]
				)
			)
		for problem in HFVibe.check_invariants(root):
			known(
				382,
				"after an array with offset %s the invariant checker sees it too" % offset,
				problem
			)
