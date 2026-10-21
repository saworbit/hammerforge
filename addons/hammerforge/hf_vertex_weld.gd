@tool
extends RefCounted
class_name HFVertexWeld

## Which near-coincident points weld together, and where they meet.
##
## The `.map` import closes the drift another editor left between plane points,
## and Check Issues' weld fix closes the same drift between a brush's corners.
## Each used to carry its own copy of this, and the copies had already drifted
## apart in how they named a grid cell (#1454). With one routine a file imports
## with the joins the fix would have made.
##
## Free of the scene: points in, groups of indices out. Each caller keeps track
## of which face a point came from and writes the result back itself.


## The grid cell a point falls in, at `tol` spacing.
##
## The index rather than the formatted position: same buckets, no allocation.
## `snapped()` is kept in the middle so the bucket boundaries are exactly the
## ones the formatted keys had.
static func cell(v: Vector3, tol: float) -> Vector3i:
	return Vector3i(
		roundi(snapped(v.x, tol) / tol),
		roundi(snapped(v.y, tol) / tol),
		roundi(snapped(v.z, tol) / tol)
	)


## Every group of two or more points that chain together within `tol`, as a
## `PackedInt32Array` of indices into `points`.
##
## Chained, so A joins C through B even when A and C are further apart than
## `tol`. A group starts at its lowest index and lists the rest in the order the
## search reached them, which is the order `average()` adds them up in. A point
## with nothing in reach is in no group, and a `tol` that is not above zero joins
## nothing.
##
## A pair close enough to join can still fall either side of a cell boundary, so
## each point looks in its own cell and the 26 around it. A cell is `tol` wide,
## so nothing in reach is further away than that.
static func cluster(points: PackedVector3Array, tol: float) -> Array:
	var groups: Array = []
	if not (tol > 0.0 and is_finite(tol)):
		return groups
	var count := points.size()
	var cell_of: Array[Vector3i] = []
	cell_of.resize(count)
	var cells: Dictionary = {}  # Vector3i -> Array of indices, lowest first
	for i in count:
		var key := cell(points[i], tol)
		cell_of[i] = key
		var bucket: Variant = cells.get(key)
		if bucket == null:
			cells[key] = [i]
		else:
			(bucket as Array).append(i)
	var taken := PackedByteArray()
	taken.resize(count)
	taken.fill(0)
	for first in count:
		if taken[first]:
			continue
		taken[first] = 1
		# Breadth first, with the group as its own queue.
		var members := PackedInt32Array([first])
		var head := 0
		while head < members.size():
			var at: Vector3 = points[members[head]]
			var c: Vector3i = cell_of[members[head]]
			head += 1
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					for dz in range(-1, 2):
						var bucket: Variant = cells.get(Vector3i(c.x + dx, c.y + dy, c.z + dz))
						if bucket == null:
							continue
						for other: int in bucket:
							if taken[other]:
								continue
							if at.distance_to(points[other]) <= tol:
								taken[other] = 1
								members.append(other)
		if members.size() > 1:
			groups.append(members)
	return groups


## Where a group meets: the mean of its points, added up in the group's order.
static func average(points: PackedVector3Array, group: PackedInt32Array) -> Vector3:
	var sum := Vector3.ZERO
	for i in group:
		sum += points[i]
	return sum / float(group.size())
