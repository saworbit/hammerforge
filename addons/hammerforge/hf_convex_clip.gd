@tool
extends RefCounted
class_name HFConvexClip

## Splitting a convex solid, described by its faces, along an arbitrary plane.
##
## This is the geometry behind Clip and Carve. It is deliberately free of the
## scene: it takes `FaceData` and a `Plane` in the same space and returns
## `FaceData`, so both callers — and their tests — can work without a LevelRoot.
##
## Two conventions matter throughout.
##
## **Winding is clockwise as seen from outside.** `FaceData.triangulate()` fans
## straight off `local_verts`, and Godot reads front faces as clockwise, so the
## vertex order *is* the geometry's outward direction. The mathematically natural
## ordering of a coplanar ring is counter-clockwise about its normal, so anything
## built here rather than carried through has to be reversed. `sort_coplanar_cw()`
## names that in its signature so no caller has to rediscover it.
##
## **Front is the side the plane normal points to.** `split()` names its halves
## after the plane, not after the caller's intent.

# Preloaded under its global name so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const FaceData = preload("face_data.gd")
@warning_ignore_restore("shadowed_global_identifier")

## Points closer than this to the plane count as lying on it. Brush coordinates
## run in the tens to thousands, so a thousandth of a unit is far below anything
## a user can author and far above float noise.
const DEFAULT_EPSILON := 0.001

## A side needs at least this many faces to bound a volume: four, as a
## tetrahedron does. Fewer means the plane grazed the solid and the "piece" is a
## sliver, not a brush.
const MIN_SOLID_FACES := 4

## A solid thinner than this every way across is a sliver rather than a brush.
## Validate reports a brush this thin as near-zero thickness, and a structure
## refuses to build a piece this thin (#1605).
const NEAR_ZERO_THICKNESS := 0.01

## The most bounding planes a boolean operation will work through.
##
## Every plane is a split of an ever-growing face set, so the cost climbs steeply
## with the count, and so does the number of pieces that come out. A box has six
## planes and a cylinder sixty-six — a tube, which is a reasonable thing to ask
## for. A sphere built from Godot's default mesh had thousands, because every one
## of its triangles is its own plane: shelling one took a minute and produced two
## thousand brushes, which is never what anybody meant. Round brushes are built
## from 128 faces since #1057. Past this many, the operation says so instead.
const MAX_BOOLEAN_PLANES := 128


## World axis for an index: 0 = X, 1 = Y, anything else = Z.
##
## One definition, in `HFTransformSystem`, which is where the guard for the
## fall-through lives. This was a byte-identical second copy, so a fix to either
## was not a fix to the other.
static func axis_normal(axis_index: int) -> Vector3:
	return HFTransformSystem.axis_vector(axis_index)


## The plane a face lies in, in the face's own space.
static func face_plane(face: FaceData) -> Plane:
	if face == null or face.local_verts.size() < 3:
		return Plane()
	var normal := _face_normal(face)
	if normal.length_squared() < 0.5:
		return Plane()
	return Plane(normal, normal.dot(face.local_verts[0]))


## Build a convex solid from the ordered corner rings of its faces.
##
## Generators describe a shape by writing out its corners, and the general case
## they want to write is the eight-corner box. But a shape that pinches — a dome
## panel at the pole, where the inner surface closes onto the axis — has rings
## that collapse to a line or a point at exactly that corner, and a ring with two
## copies of the same corner is not a polygon.
##
## Collapsing coincident corners here means a generator can write the general case
## once and get a wedge where the shape pinches, rather than carrying a special
## case through its own arithmetic. Winding is settled afterwards by measurement
## against the interior point, as everywhere else.
##
## `smoothing`, when given, is each ring's smoothing group, in the rings' order:
## a generator knows which of its faces lie on a curve (#1429).
static func solid_from_rings(
	rings: Array, epsilon := DEFAULT_EPSILON, smoothing := PackedInt32Array()
) -> Array:
	var faces: Array = []
	for i in rings.size():
		var corners: PackedVector3Array = _collapse_ring(rings[i], epsilon)
		if corners.size() < 3:
			continue
		var face := FaceData.new()
		face.local_verts = corners
		if i < smoothing.size():
			face.smoothing_group = smoothing[i]
		face.ensure_geometry()
		faces.append(face)
	if faces.size() < MIN_SOLID_FACES:
		return []
	return orient_faces_outward(faces, interior_point(faces))


## Drop corners that repeat the one before them, and the last if it repeats the
## first. A ring is a closed loop, so both ends count as adjacent.
static func _collapse_ring(ring, epsilon: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for corner in ring:
		var point: Vector3 = corner
		if out.size() > 0 and out[out.size() - 1].distance_to(point) <= epsilon:
			continue
		out.append(point)
	while out.size() >= 2 and out[0].distance_to(out[out.size() - 1]) <= epsilon:
		out.remove_at(out.size() - 1)
	return out


## The point inside a solid that its own vertices average to.
static func interior_point(faces: Array) -> Vector3:
	var total := Vector3.ZERO
	var count := 0
	for face in faces:
		var data: FaceData = face as FaceData
		if data == null:
			continue
		for vertex in data.local_verts:
			total += vertex
			count += 1
	return total / float(count) if count > 0 else Vector3.ZERO


## How thin the solid that `rings` bound is, read off the corner rings
## `solid_from_rings()` would build it from: `{across, face}`, the least depth it
## has behind any of its faces, and that face's `normal`, the way it is thin. That
## is its narrowest way across whichever way it is turned, as `_thickness()`
## measures built faces. `corners` is every corner the rings use. `across` is INF
## when no ring is a face.
static func thickness_of(
	corners: PackedVector3Array, rings: Array, epsilon := DEFAULT_EPSILON
) -> Dictionary:
	var out := {"across": INF, "normal": Vector3.ZERO}
	for ring_corners in rings:
		var ring := _collapse_ring(ring_corners, epsilon)
		if ring.size() < 3:
			continue
		# Newell's sum, so a ring whose first corners nearly line up still has a
		# normal to measure along.
		var normal := Vector3.ZERO
		for k in ring.size():
			var a := ring[k]
			var b := ring[(k + 1) % ring.size()]
			normal += Vector3(
				(a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y)
			)
		if normal.length_squared() == 0.0:
			continue
		normal = normal.normalized()
		# The whole spread along the normal, not the distance from the face, so a
		# ring that is not quite a face of the solid can only read thicker.
		var low := INF
		var high := -INF
		for corner: Vector3 in corners:
			var along := normal.dot(corner)
			low = minf(low, along)
			high = maxf(high, along)
		if high - low < float(out["across"]):
			out = {"across": high - low, "normal": normal}
	return out


## Whether the solid `rings` bound comes out as a box when it is built: what
## `is_axis_aligned_box()` says of `solid_from_rings(rings)`, which is how the brush
## system decides a generated piece is a box brush. That takes six four-cornered
## faces each square to an axis, so most pieces are told apart by their rings
## before any face is made.
static func rings_build_a_box(rings: Array, epsilon := DEFAULT_EPSILON) -> Dictionary:
	var faces := 0
	for ring in rings:
		var corners := _collapse_ring(ring, epsilon)
		if corners.size() < 3:
			continue
		faces += 1
		if corners.size() != 4:
			return {}
		var normal := (corners[2] - corners[0]).cross(corners[1] - corners[0])
		# A little looser than the face test, whose first corner may be another.
		var squarest := maxf(absf(normal.x), maxf(absf(normal.y), absf(normal.z)))
		if normal.length_squared() > 0.000001 and squarest < normal.length() * 0.998:
			return {}
	if faces != 6:
		return {}
	return is_axis_aligned_box(solid_from_rings(rings, epsilon), epsilon)


## The thinnest piece too thin to build, or an empty dictionary when none is:
## `{piece, across, box, direction}`, `direction` being the way it is thin.
##
## A piece `rings_build_a_box()` says is a box becomes a box brush, which the brush
## system widens to `min_box` on every side and rebuilds from its size whenever its
## scene opens, so a box is held to `min_box`. Any other piece keeps the faces it
## was built with at any size (#1603), so it is held only above
## `NEAR_ZERO_THICKNESS`, measured the narrowest way across. `corner_sets[i]` and
## `ring_sets[i]` are one piece, as `thickness_of()` takes it.
static func too_thin(corner_sets: Array, ring_sets: Array, min_box: float) -> Dictionary:
	var worst := {}
	for i in mini(corner_sets.size(), ring_sets.size()):
		var found := {}
		var box := rings_build_a_box(ring_sets[i])
		if not box.is_empty():
			var size: Vector3 = box["size"]
			var axis := size.min_axis_index()
			# A side this near `min_box` is `min_box` read off float corners, and
			# the brush system builds it as it is.
			if size[axis] < min_box - 0.00001:
				var direction := Vector3.ZERO
				direction[axis] = 1.0
				found = {"piece": i, "across": size[axis], "box": true, "direction": direction}
		else:
			var measured := thickness_of(corner_sets[i], ring_sets[i])
			if float(measured["across"]) < NEAR_ZERO_THICKNESS:
				found = {
					"piece": i,
					"across": measured["across"],
					"box": false,
					"direction": measured["normal"],
				}
		if found.is_empty():
			continue
		if worst.is_empty() or float(found["across"]) < float(worst["across"]):
			worst = found
	return worst


## Every distinct bounding plane of a convex solid, each facing away from inside.
##
## Orientation comes from an interior point rather than from each face's own
## winding, because a single unreliable face normal is enough to ruin the whole
## operation. Brushes store triangles, and a primitive mesh has near-degenerate
## ones — at a sphere's poles, for instance — whose cross product has a length
## above any sane epsilon but a direction that is numerical noise. One of those
## flipped the wrong way turns an inset plane inside out, and shelling a sphere
## reports that there is no room inside it.
##
## Every face plane of a convex solid has the whole solid behind it, so which way
## round it goes is a question with an answer, not a matter of trusting the input.
static func outward_planes(
	faces: Array, interior: Vector3, epsilon: float = DEFAULT_EPSILON
) -> Array:
	var planes: Array = []
	for face in faces:
		var data: FaceData = face as FaceData
		if data == null or data.local_verts.size() < 3:
			continue
		var plane := face_plane(data)
		if plane.normal.length_squared() < 0.5:
			continue
		if plane.distance_to(interior) > 0.0:
			plane = Plane(-plane.normal, -plane.d)
		planes.append(plane)
	return dedupe_planes(planes, epsilon)


## Every bounding plane of a convex solid, taken into another space.
##
## Carve needs the carving brush's planes expressed in its target's frame. They
## face outward, so a point in front of one of them is outside the carver.
static func face_planes_in_space(faces: Array, into: Transform3D) -> Array:
	var planes: Array = []
	for plane in outward_planes(faces, interior_point(faces)):
		planes.append(into * plane)
	return planes


## Split a convex face set by a plane expressed in the same space.
##
## Returns `{"front": Array, "back": Array, "cut": PackedVector3Array,
## "origins": Dictionary}`. A side comes back empty when the plane misses the
## solid, or when what it would carve off is too thin to be a solid — which is how
## callers tell "nothing to do" from a real cut without measuring anything
## themselves. `origins` maps each new face to the face in `faces` it is a piece
## of, for `carry_surface_detail()`. A cap is a piece of nothing.
static func split(faces: Array, plane: Plane, epsilon: float = DEFAULT_EPSILON) -> Dictionary:
	var empty := {"front": [], "back": [], "cut": PackedVector3Array(), "origins": {}}
	if faces.is_empty():
		return empty

	var front: Array = []
	var back: Array = []
	var cut_points := PackedVector3Array()
	var origins := {}
	var saw_front := false
	var saw_back := false

	for face in faces:
		var source: FaceData = face as FaceData
		if source == null or source.local_verts.size() < 3:
			continue
		var verts: PackedVector3Array = source.local_verts
		var uvs: PackedVector2Array = source.custom_uvs
		var has_uvs := uvs.size() == verts.size()

		var above := 0
		var below := 0
		for vertex in verts:
			var distance := plane.distance_to(vertex)
			if distance > epsilon:
				above += 1
			elif distance < -epsilon:
				below += 1
		if above > 0:
			saw_front = true
		if below > 0:
			saw_back = true

		var whole_uvs := uvs if has_uvs else PackedVector2Array()
		if below == 0:
			# Entirely in front, or lying on the plane.
			front.append(_piece_of(source, verts, whole_uvs, origins))
			continue
		if above == 0:
			back.append(_piece_of(source, verts, whole_uvs, origins))
			continue

		var front_part := clip_polygon(verts, uvs, plane, true, epsilon)
		var back_part := clip_polygon(verts, uvs, plane, false, epsilon)
		var front_verts: PackedVector3Array = front_part["verts"]
		var back_verts: PackedVector3Array = back_part["verts"]
		if front_verts.size() >= 3:
			front.append(_piece_of(source, front_verts, front_part["uvs"], origins))
		if back_verts.size() >= 3:
			back.append(_piece_of(source, back_verts, back_part["uvs"], origins))
		cut_points.append_array(_crossing_points(verts, plane, epsilon))

	if not saw_front or not saw_back:
		# The plane never separated anything, so the solid belongs to one side.
		var whole := {}
		var copies := _duplicate_faces(faces, whole)
		if saw_back:
			return {"front": [], "back": copies, "cut": PackedVector3Array(), "origins": whole}
		return {"front": copies, "back": [], "cut": PackedVector3Array(), "origins": whole}

	var ring := cap_polygon(cut_points, -plane.normal, epsilon)
	if ring.size() >= 3:
		var template: FaceData = _nearest_face(faces, -plane.normal)
		# The two caps are the same ring seen from opposite sides, so one is the
		# reverse of the other. Front looks back down the plane normal; back looks
		# along it.
		front.append(_cap_face(template, ring, -plane.normal))
		var reversed_ring := PackedVector3Array()
		for i in range(ring.size() - 1, -1, -1):
			reversed_ring.append(ring[i])
		back.append(_cap_face(_nearest_face(faces, plane.normal), reversed_ring, plane.normal))

	if front.size() < MIN_SOLID_FACES:
		front = []
	if back.size() < MIN_SOLID_FACES:
		back = []
	return {"front": front, "back": back, "cut": cut_points, "origins": origins}


## Cut a convex solid down by a set of bounding planes, keeping what falls outside
## each one.
##
## This is the shape of both boolean operations HammerForge has. For each plane:
## split what is left, the half outside that plane can never be removed by a later
## plane so it is finished, and the half inside carries on. What survives every
## plane is the intersection of all of them.
##
## Carve passes the planes of the carving brush, and the intersection is the volume
## it removes. Hollow passes the brush's own planes pushed inward, and the
## intersection is the void. Intersect passes the planes of another brush, and
## keeps the intersection. Same loop, different planes.
##
## Returns `{"pieces": Array, "remainder": Array, "separated": bool, "origins":
## Dictionary}`. `separated` is false when the solid never straddled one of the
## planes, which means it lies entirely outside the intersection and nothing should
## be cut at all. `origins` maps every face of the pieces and the remainder to the
## face of `faces` it is a piece of, however many splits it went through, so a
## sculpt is resampled once from the face it was made on and not from a resample.
static func progressive_remainder(
	faces: Array, planes: Array, epsilon: float = DEFAULT_EPSILON
) -> Dictionary:
	var pieces: Array = []
	var origins := {}
	var remainder: Array = _duplicate_faces(faces, origins)
	if remainder.is_empty() or planes.is_empty():
		return {"pieces": pieces, "remainder": remainder, "separated": false, "origins": origins}
	for plane in dedupe_planes(planes):
		var halves: Dictionary = split(remainder, plane, epsilon)
		var outside: Array = halves["front"]
		var inside: Array = halves["back"]
		if inside.is_empty():
			# Nothing of the remainder is behind this plane, so nothing of it is
			# inside the intersection. There is nothing here to cut.
			return {"pieces": [], "remainder": [], "separated": false, "origins": {}}
		# A split names the face it cut, which is a piece of an earlier split, or
		# an earlier cap, which is a piece of nothing.
		var cut_from: Dictionary = halves["origins"]
		for face in cut_from:
			var first: FaceData = origins.get(cut_from[face])
			if first != null:
				origins[face] = first
		if not outside.is_empty():
			pieces.append(outside)
		remainder = inside
	return {"pieces": pieces, "remainder": remainder, "separated": true, "origins": origins}


## The one convex solid several convex solids make together, as Merge needs it.
##
## Returns `{"faces": Array, "convex": bool, "origins": Dictionary}`. `face_sets`
## are the solids, all in one space. The union is convex exactly when it is the
## space behind every input plane that has all of the inputs behind it, so that is
## what gets built, cut out of the inputs' bounding box. Each face of it lies on the
## plane of an input face that has every input behind it, so two boxes side by side
## come out as the box they are, without the two faces where they touched.
##
## Built from those planes alone, an L of three boxes would come out as its
## bounding box and two posts under a lintel as a block with no doorway, so the
## result is checked rather than trusted: every input is carved out of it, and
## whatever is left is space the merged brush would fill that no input did. Then
## `convex` is false and `faces` empty. A leftover no thicker than `gap` is the
## seam between two brushes that count as touching, and is let through. Comparing
## the volume against the inputs' would not do, because brushes may overlap, and
## then the sum of their volumes is more than the union's whatever shape it is.
##
## `origins` maps each face to the input face it came from, for
## `carry_onto_union()`: the largest input face lying on it, the first listed on a
## tie. A face that is that input face whole keeps its corners as they were.
static func union_of(
	face_sets: Array, gap: float = 0.0, epsilon: float = DEFAULT_EPSILON
) -> Dictionary:
	var refused := {"faces": [], "convex": false, "origins": {}}
	var solids: Array = []
	var corners: Array = []
	var points := PackedVector3Array()
	for face_set in face_sets:
		var usable: Array = []
		for face in face_set:
			var data: FaceData = face as FaceData
			if data != null and data.local_verts.size() >= 3:
				usable.append(data)
		if usable.size() >= MIN_SOLID_FACES:
			solids.append(usable)
			corners.append(_corners_of(usable))
			points.append_array(corners.back())
	if solids.is_empty():
		return refused

	var bounding: Array = []
	for solid in solids:
		bounding.append_array(_supporting_planes(solid, points, epsilon))
	var joined: Array = _box_around(points)
	for plane in dedupe_planes(bounding, epsilon):
		joined = split(joined, plane, epsilon)["back"]
		if joined.is_empty():
			return refused

	# Each input as its own hull, so a brush that is already not convex is read as
	# what the bake and a `.map` make of it rather than as nothing.
	var hulls: Array = []
	for i in solids.size():
		hulls.append(_supporting_planes(solids[i], corners[i], epsilon))
	# A corner no input holds is a corner the inputs do not have. That settles an L
	# or two spheres cheaply; a doorway has every corner and needs the carve below.
	for face in joined:
		for corner in (face as FaceData).local_verts:
			if not _held_by_any(corner, hulls, gap + epsilon):
				return refused
	# So does the middle of a face. Two round brushes side by side hold every
	# corner of the solid round them, but the face bridging the hollow between them
	# has its middle in neither, and the carve took a third of a second to find
	# that for two 64-sided cylinders (#1257). A convex union holds every point of
	# itself, so this refuses nothing the carve would let through.
	for face in joined:
		var verts: PackedVector3Array = (face as FaceData).local_verts
		var middle := Vector3.ZERO
		for corner in verts:
			middle += corner
		if not _held_by_any(middle / float(verts.size()), hulls, gap + epsilon):
			return refused

	var leftover: Array = [joined]
	for planes in hulls:
		var outside: Array = []
		for piece in leftover:
			var carved: Dictionary = progressive_remainder(piece, planes, epsilon)
			if carved["separated"]:
				outside.append_array(carved["pieces"])
			else:
				outside.append(piece)
		leftover = outside
	for piece in leftover:
		if _thickness(piece) > gap:
			return refused

	var sources: Array = []
	for solid in solids:
		sources.append_array(solid)
	var on_plane := maxf(gap, epsilon)
	var faces: Array = []
	var origins := {}
	var rank := {}
	for face in joined:
		var hull_face: FaceData = face as FaceData
		var source: FaceData = _largest_on_face(sources, hull_face, on_plane)
		if source == null:
			source = _nearest_face(sources, _face_normal(hull_face))
		var built: FaceData
		if _same_corners(hull_face.local_verts, source.local_verts, epsilon):
			built = _piece_of(source, source.local_verts, source.custom_uvs, origins)
		else:
			built = _piece_of(source, hull_face.local_verts, PackedVector2Array(), origins)
		rank[built] = sources.find(source)
		faces.append(built)
	# In the order of the faces they came from, so the merged brush lists the first
	# brush's faces first, as the brushes were selected.
	faces.sort_custom(func(a, b): return rank[a] < rank[b])
	return {"faces": faces, "convex": true, "origins": origins}


## Hand each face of a union from `union_of()` what is laid on the face it came
## from. Returns how many sculpts could not follow, so the caller can say so.
##
## A face that is its input face whole keeps everything: its UVs, its paint and
## its sculpt. A face that grew, because it joined other faces on its plane, keeps
## the texture where it was. Custom or Cylindrical UVs are read off the input face
## and carried on across the new corners, and Planar and Box UVs are taken in
## world space and carry on by themselves. Its paint goes with it, as it does onto
## a piece of a cut. A sculpt is laid against the four corners of its face and
## these are not them, so it cannot.
static func carry_onto_union(faces: Array, origins: Dictionary) -> int:
	var dropped := 0
	for face in faces:
		var built: FaceData = face as FaceData
		if built == null or not origins.has(built):
			continue
		var source: FaceData = origins[built]
		if not source.paint_layers.is_empty():
			built.copy_paint_from(source)
		if built.local_verts == source.local_verts:
			if source.displacement != null:
				built.displacement = source.displacement.duplicate(true)
			continue
		if (
			source.custom_uvs.size() == source.local_verts.size()
			or source.uv_projection == FaceData.UVProjection.CYLINDRICAL
		):
			built.custom_uvs = source.shown_uvs_at(built.local_verts)
		if source.displacement != null:
			dropped += 1
	return dropped


## Hand each face of the kept pieces the paint and the sculpt of the face it is a
## piece of. `origins` is what `split()` or `progressive_remainder()` returned.
##
## Paint is laid in one tile of the face's texture, and a piece keeps its face's
## UVs, so copies of the layers land where they were. Each piece face gets copies
## of its own, so painting one piece leaves the other alone. A cap is a piece of
## nothing and stays unpainted.
##
## A sculpt is laid against the four corners of its face. A piece that is the
## whole face takes a copy, and a four-cornered piece takes it resampled onto its
## own corners. Nothing else can hold one. Returns how many sculpts could not
## follow onto every piece of their face, so the caller can say so.
##
## A Cylindrical projection is taken in the brush's own space, about its middle,
## with the height measured over the face's own corners. Each piece is re-centred
## on a brush of its own and spans less height, so projected afresh its texture
## turned and stretched, and the paint, which is read through the UVs, went with
## it. So a piece of a Cylindrical face with no custom UVs gets, at each corner,
## the UV its face showed there, taken now, while the corners are still in the
## brush's space. Custom UVs then travel with the corners (#868). Planar and Box
## UVs are taken in world space and are the same at any point however the face
## is cut, so they need nothing.
static func carry_surface_detail(face_sets: Array, origins: Dictionary) -> int:
	var dropped := {}
	for face_set in face_sets:
		for face in face_set:
			var piece: FaceData = face as FaceData
			if piece == null or not origins.has(piece):
				continue
			var source: FaceData = origins[piece]
			if (
				source.uv_projection == FaceData.UVProjection.CYLINDRICAL
				and piece.custom_uvs.is_empty()
			):
				piece.custom_uvs = source.shown_uvs_at(piece.local_verts)
			if not source.paint_layers.is_empty():
				piece.copy_paint_from(source)
			if source.displacement == null:
				continue
			if piece.local_verts == source.local_verts:
				piece.displacement = source.displacement.duplicate(true)
				continue
			var resampled: Resource = null
			if piece.local_verts.size() == 4:
				resampled = source.displacement.resampled_onto(
					source.local_verts, piece.local_verts
				)
			if resampled == null:
				dropped[source] = true
			piece.displacement = resampled
	return dropped.size()


## How many sculpts a cut would drop: those with a piece that is neither the whole
## face nor four-cornered, which are the ones `carry_surface_detail()` cannot lay a
## sculpt on. It reads corner counts only, so a preview can ask before the cut
## without copying paint or resampling a sculpt (#871).
static func sculpts_a_cut_would_drop(face_sets: Array, origins: Dictionary) -> int:
	var dropped := {}
	for face_set in face_sets:
		for face in face_set:
			var piece: FaceData = face as FaceData
			if piece == null or not origins.has(piece):
				continue
			var source: FaceData = origins[piece]
			if source.displacement == null or piece.local_verts == source.local_verts:
				continue
			if piece.local_verts.size() != 4:
				dropped[source] = true
	return dropped.size()


## Whether a solid has few enough distinct planes to run a boolean against.
##
## Returns `{"ok": bool, "planes": int}` so a caller can report the real number.
static func boolean_plane_budget(faces: Array, interior: Vector3) -> Dictionary:
	var count: int = outward_planes(faces, interior).size()
	return {"ok": count <= MAX_BOOLEAN_PLANES, "planes": count}


## Whether `faces` close one convex solid: every corner on or behind every
## bounding plane. The booleans cut by planes, so on anything else they work on
## its hull. A torus is the shape that is not, and its 2,048 faces used to keep
## it over `MAX_BOOLEAN_PLANES` by chance, until round brushes were built from
## 128 (#1057).
static func is_convex_solid(faces: Array, interior: Vector3, tolerance: float = 0.01) -> bool:
	var planes: Array = outward_planes(faces, interior)
	for face in faces:
		var data: FaceData = face as FaceData
		if data == null:
			continue
		for corner in data.local_verts:
			for plane: Plane in planes:
				if plane.distance_to(corner) > tolerance:
					return false
	return true


## Drop planes that repeat one already in the list.
##
## A brush's faces are triangles, so a cylinder hands over 768 of them describing
## 66 distinct planes, and a sphere far more. A repeated plane can never cut
## anything a previous pass left, so every one of those is a whole split done for
## nothing.
static func dedupe_planes(planes: Array, epsilon: float = DEFAULT_EPSILON) -> Array:
	var out: Array = []
	var seen := {}
	var angular_step := maxf(epsilon, 0.000001)
	for plane in planes:
		var normal: Vector3 = plane.normal
		if normal.length_squared() < 0.5:
			continue
		var key := (
			"%d,%d,%d,%d"
			% [
				roundi(normal.x / angular_step),
				roundi(normal.y / angular_step),
				roundi(normal.z / angular_step),
				roundi(plane.d / angular_step),
			]
		)
		if seen.has(key):
			continue
		seen[key] = true
		out.append(plane)
	return out


## Move a plane along its own normal. Negative moves it inward for an outward
## normal, which is what shelling a solid needs.
static func offset_plane(plane: Plane, distance: float) -> Plane:
	return Plane(plane.normal, plane.d + distance)


## Reverse any face that points towards `interior` instead of away from it.
##
## The one safe way to wind a solid built from scratch. Every face of a convex
## solid points away from any point inside it, which is checkable rather than
## reasoned about — and reasoning about it is how rebuilt faces have shipped inside
## out before. Generators should build their faces in any order and finish here.
static func orient_faces_outward(faces: Array, interior: Vector3) -> Array:
	for face in faces:
		var data: FaceData = face as FaceData
		if data == null or data.local_verts.size() < 3:
			continue
		var centre := Vector3.ZERO
		for vertex in data.local_verts:
			centre += vertex
		centre /= float(data.local_verts.size())
		var outward := centre - interior
		if outward.length_squared() < 0.000001:
			continue
		if _face_normal(data).dot(outward) < 0.0:
			var flipped := PackedVector3Array()
			var uvs: PackedVector2Array = data.custom_uvs
			var carry_uvs := uvs.size() == data.local_verts.size()
			var flipped_uvs := PackedVector2Array()
			for i in range(data.local_verts.size() - 1, -1, -1):
				flipped.append(data.local_verts[i])
				if carry_uvs:
					flipped_uvs.append(uvs[i])
			data.local_verts = flipped
			data.custom_uvs = flipped_uvs if carry_uvs else PackedVector2Array()
		data.ensure_geometry()
	return faces


## Clip one convex planar polygon, keeping the front or the back half.
##
## Sutherland-Hodgman in three dimensions. UVs ride along and are interpolated at
## each crossing by the edge parameter, so a cut face keeps its texture alignment
## instead of being re-projected.
static func clip_polygon(
	verts: PackedVector3Array,
	uvs: PackedVector2Array,
	plane: Plane,
	keep_front: bool,
	epsilon: float = DEFAULT_EPSILON
) -> Dictionary:
	var out_verts := PackedVector3Array()
	var out_uvs := PackedVector2Array()
	var count := verts.size()
	if count < 3:
		return {"verts": out_verts, "uvs": out_uvs}
	var has_uvs := uvs.size() == count
	var side_sign := 1.0 if keep_front else -1.0

	for i in count:
		var next_index := (i + 1) % count
		var current: Vector3 = verts[i]
		var next: Vector3 = verts[next_index]
		var current_distance := plane.distance_to(current) * side_sign
		var next_distance := plane.distance_to(next) * side_sign
		# Three-way classification, not a two-way inside test. A vertex sitting on
		# the plane is kept once and generates no crossing; testing only for
		# "inside" would emit it and then emit an intersection at the same point,
		# leaving a zero-length edge that stops the piece being a closed solid.
		var current_on := absf(current_distance) <= epsilon
		var next_on := absf(next_distance) <= epsilon

		if current_on or current_distance > 0.0:
			out_verts.append(current)
			if has_uvs:
				out_uvs.append(uvs[i])
		if current_on or next_on:
			continue
		if (current_distance > 0.0) == (next_distance > 0.0):
			continue
		var span := current_distance - next_distance
		if absf(span) < 0.000001:
			continue
		var t: float = clampf(current_distance / span, 0.0, 1.0)
		out_verts.append(current.lerp(next, t))
		if has_uvs:
			out_uvs.append(uvs[i].lerp(uvs[next_index], t))

	return {"verts": out_verts, "uvs": out_uvs if has_uvs else PackedVector2Array()}


## Order coplanar points into a ring wound clockwise as seen from `outward_normal`.
##
## Sorting by angle about the centroid gives counter-clockwise about the normal
## by the right-hand rule, so the result is reversed. That reversal is the whole
## reason this function exists rather than being written inline at its two call
## sites: clockwise-from-outside is what the rest of the codebase means by a face.
static func sort_coplanar_cw(
	verts: PackedVector3Array, outward_normal: Vector3
) -> PackedVector3Array:
	var count := verts.size()
	if count < 3:
		return verts
	var normal := outward_normal.normalized()
	if normal.length_squared() < 0.5:
		return verts
	var centroid := Vector3.ZERO
	for vertex in verts:
		centroid += vertex
	centroid /= float(count)
	var ref_axis := Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var u := normal.cross(ref_axis).normalized()
	var v := normal.cross(u)
	var order: Array = []
	for i in count:
		var relative: Vector3 = verts[i] - centroid
		order.append({"index": i, "angle": atan2(relative.dot(v), relative.dot(u))})
	order.sort_custom(func(a, b): return a["angle"] < b["angle"])
	var sorted := PackedVector3Array()
	for i in range(order.size() - 1, -1, -1):
		sorted.append(verts[order[i]["index"]])
	return sorted


## Build the cut surface from the crossing points, deduplicated and ordered.
static func cap_polygon(
	cut_points: PackedVector3Array, outward_normal: Vector3, epsilon: float = DEFAULT_EPSILON
) -> PackedVector3Array:
	# Deduplicate by distance, not by grid cell. Two crossings a hair apart can
	# land either side of a cell boundary and both survive, and a cut ring with a
	# near-duplicate in it fans into a zero-area sliver whose normal is noise.
	# Cut rings have tens of points at most, so the quadratic scan is free.
	var unique := PackedVector3Array()
	var threshold := maxf(epsilon, 0.000001)
	var threshold_squared := threshold * threshold
	for point in cut_points:
		var duplicate := false
		for kept in unique:
			if kept.distance_squared_to(point) <= threshold_squared:
				duplicate = true
				break
		if not duplicate:
			unique.append(point)
	if unique.size() < 3:
		return PackedVector3Array()
	return _drop_collinear(sort_coplanar_cw(unique, outward_normal), threshold)


## Remove ring vertices that add nothing but a sliver triangle.
##
## A vertex lying on the straight line between its neighbours contributes a
## degenerate triangle when `FaceData.triangulate()` fans the polygon, and a
## degenerate triangle has no reliable normal.
static func _drop_collinear(ring: PackedVector3Array, threshold: float) -> PackedVector3Array:
	var count := ring.size()
	if count < 4:
		return ring
	var kept := PackedVector3Array()
	for i in count:
		var previous: Vector3 = ring[(i - 1 + count) % count]
		var current: Vector3 = ring[i]
		var next: Vector3 = ring[(i + 1) % count]
		var edge_a := current - previous
		var edge_b := next - current
		if edge_a.length() < threshold or edge_b.length() < threshold:
			continue
		# Twice the triangle area, compared against the longer edge: the distance
		# this vertex stands off the line through its neighbours.
		var offset := edge_a.cross(edge_b).length() / maxf(edge_a.length(), edge_b.length())
		if offset < threshold:
			continue
		kept.append(current)
	return kept if kept.size() >= 3 else ring


## Describe a face set as an axis-aligned box, or return an empty dictionary.
##
## A piece that is still a box should be emitted as one rather than as CUSTOM:
## a CUSTOM brush loses its resize handles, and the commonest cut of all — a box
## split down one of its own axes — produces two boxes.
##
## Returns `{"size": Vector3, "center": Vector3}` when the faces form a six-sided
## box aligned to the frame they are expressed in.
static func is_axis_aligned_box(faces: Array, epsilon: float = DEFAULT_EPSILON) -> Dictionary:
	if faces.size() != 6:
		return {}
	var bounds := AABB()
	var seeded := false
	for face in faces:
		var data: FaceData = face as FaceData
		if data == null or data.local_verts.size() != 4:
			return {}
		var normal := _face_normal(data)
		if not _is_axis_direction(normal, epsilon):
			return {}
		for vertex in data.local_verts:
			if seeded:
				bounds = bounds.expand(vertex)
			else:
				bounds = AABB(vertex, Vector3.ZERO)
				seeded = true
	if not seeded:
		return {}
	if bounds.size.x <= epsilon or bounds.size.y <= epsilon or bounds.size.z <= epsilon:
		return {}
	# Every vertex has to sit on the shell of those bounds, or the faces describe
	# something box-shaped only in outline.
	for face in faces:
		var data: FaceData = face as FaceData
		for vertex in data.local_verts:
			if not _on_box_shell(vertex, bounds, epsilon):
				return {}
	return {"size": bounds.size, "center": bounds.get_center()}


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------


## A copy of `source` carrying new geometry and its look.
##
## Not its paint or its sculpt. Every split makes these, the clip and carve
## previews included, and those run on every mouse move. A cut that is kept hands
## them over afterwards, through `carry_surface_detail()`.
static func _face_like(
	source: FaceData, verts: PackedVector3Array, uvs: PackedVector2Array
) -> FaceData:
	var face := FaceData.new()
	face.copy_appearance_from(source)
	face.local_verts = verts
	face.custom_uvs = uvs if uvs.size() == verts.size() else PackedVector2Array()
	face.ensure_geometry()
	return face


## `_face_like()`, noting in `origins` which face the new one is a piece of.
static func _piece_of(
	source: FaceData, verts: PackedVector3Array, uvs: PackedVector2Array, origins: Dictionary
) -> FaceData:
	var face := _face_like(source, verts, uvs)
	origins[face] = source
	return face


static func _cap_face(
	template: FaceData, ring: PackedVector3Array, outward_normal: Vector3
) -> FaceData:
	var face := FaceData.new()
	if template != null:
		face.copy_appearance_from(template)
	# A cut is flat. Taken from a round brush's side, the group smoothed the
	# brush's curve into the cut across its edge (#1429).
	face.smoothing_group = 0
	face.local_verts = ring
	face.normal = outward_normal.normalized()
	face.ensure_geometry()
	return face


static func _duplicate_faces(faces: Array, origins: Dictionary) -> Array:
	var out: Array = []
	for face in faces:
		var data: FaceData = face as FaceData
		if data == null or data.local_verts.size() < 3:
			continue
		out.append(_piece_of(data, data.local_verts, data.custom_uvs, origins))
	return out


## The face whose outward normal is most like `direction`. A cut surface has no
## texture of its own, so it borrows from the face it most resembles.
static func _nearest_face(faces: Array, direction: Vector3) -> FaceData:
	var best: FaceData = null
	var best_dot := -2.0
	for face in faces:
		var data: FaceData = face as FaceData
		if data == null or data.local_verts.size() < 3:
			continue
		var alignment := _face_normal(data).dot(direction.normalized())
		if alignment > best_dot:
			best_dot = alignment
			best = data
	return best


## The face planes of `faces` that have every one of `points` behind them, each
## turned to face away from the points. A plane with points on both sides is not
## on the hull of them, whichever way its face was wound.
static func _supporting_planes(faces: Array, points: PackedVector3Array, epsilon: float) -> Array:
	var face_planes: Array = []
	for face in faces:
		face_planes.append(face_plane(face as FaceData))
	var planes: Array = []
	# Distinct planes only: a round brush's cap is a fan of triangles on one plane.
	for plane: Plane in dedupe_planes(face_planes, epsilon):
		var ahead := false
		var behind := false
		for point in points:
			var distance := plane.distance_to(point)
			if distance > epsilon:
				ahead = true
			elif distance < -epsilon:
				behind = true
			if ahead and behind:
				break
		if not ahead:
			planes.append(plane)
		elif not behind:
			planes.append(Plane(-plane.normal, -plane.d))
	return dedupe_planes(planes, epsilon)


## Every corner of a solid once, though each is a corner of several faces.
static func _corners_of(faces: Array) -> PackedVector3Array:
	var seen := {}
	var out := PackedVector3Array()
	for face in faces:
		for corner in (face as FaceData).local_verts:
			if not seen.has(corner):
				seen[corner] = true
				out.append(corner)
	return out


## Whether `point` is within `tolerance` of the inside of one of `hulls`, each a
## convex solid's outward planes.
static func _held_by_any(point: Vector3, hulls: Array, tolerance: float) -> bool:
	for planes in hulls:
		var inside := true
		for plane: Plane in planes:
			if plane.distance_to(point) > tolerance:
				inside = false
				break
		if inside:
			return true
	return false


## The axis-aligned box around `points`, as a solid.
static func _box_around(points: PackedVector3Array) -> Array:
	var bounds := AABB(points[0], Vector3.ZERO)
	for point in points:
		bounds = bounds.expand(point)
	var low := bounds.position
	var high := bounds.end
	var corners: Array = []
	for i in 8:
		corners.append(
			Vector3(
				high.x if (i & 1) != 0 else low.x,
				high.y if (i & 2) != 0 else low.y,
				high.z if (i & 4) != 0 else low.z
			)
		)
	var rings: Array = []
	for quad in [
		[0, 2, 6, 4], [1, 5, 7, 3], [0, 4, 5, 1], [2, 3, 7, 6], [0, 1, 3, 2], [4, 6, 7, 5]
	]:
		var ring := PackedVector3Array()
		for index in quad:
			ring.append(corners[index])
		rings.append(ring)
	return solid_from_rings(rings)


## How thin a convex solid is: the least depth it has behind any of its own faces.
static func _thickness(faces: Array) -> float:
	var thinnest := INF
	for plane: Plane in outward_planes(faces, interior_point(faces)):
		var depth := 0.0
		for face in faces:
			for vertex in (face as FaceData).local_verts:
				depth = maxf(depth, -plane.distance_to(vertex))
		thinnest = minf(thinnest, depth)
	return 0.0 if is_inf(thinnest) else thinnest


## The largest of `sources` lying on `face` and facing the same way, the first on a
## tie, or null. Lying on it means every corner within `tolerance` of its plane.
static func _largest_on_face(sources: Array, face: FaceData, tolerance: float) -> FaceData:
	var plane := face_plane(face)
	var best: FaceData = null
	var best_area := 0.0
	for source in sources:
		var data: FaceData = source as FaceData
		if _face_normal(data).dot(plane.normal) < 0.999:
			continue
		var on_it := true
		for vertex in data.local_verts:
			if absf(plane.distance_to(vertex)) > tolerance:
				on_it = false
				break
		if not on_it:
			continue
		# Two faces a rounding error apart in size are a tie, not a winner.
		var area := _polygon_area(data.local_verts)
		if best == null or area > best_area * 1.0001:
			best = data
			best_area = area
	return best


static func _polygon_area(verts: PackedVector3Array) -> float:
	var twice := Vector3.ZERO
	for i in range(1, verts.size() - 1):
		twice += (verts[i] - verts[0]).cross(verts[i + 1] - verts[0])
	return twice.length() * 0.5


## Whether two polygons have the same corners, in whatever order.
static func _same_corners(a: PackedVector3Array, b: PackedVector3Array, epsilon: float) -> bool:
	if a.size() != b.size():
		return false
	for corner in a:
		var found := false
		for other in b:
			if corner.distance_to(other) <= epsilon:
				found = true
				break
		if not found:
			return false
	return true


static func _crossing_points(
	verts: PackedVector3Array, plane: Plane, epsilon: float
) -> PackedVector3Array:
	var out := PackedVector3Array()
	var count := verts.size()
	for i in count:
		var current: Vector3 = verts[i]
		var next: Vector3 = verts[(i + 1) % count]
		var current_distance := plane.distance_to(current)
		var next_distance := plane.distance_to(next)
		if absf(current_distance) <= epsilon:
			out.append(current)
			continue
		if (current_distance > 0.0) == (next_distance > 0.0):
			continue
		if absf(next_distance) <= epsilon:
			continue
		var span := current_distance - next_distance
		if absf(span) < 0.000001:
			continue
		out.append(current.lerp(next, clampf(current_distance / span, 0.0, 1.0)))
	return out


## The face's outward normal, recomputed from its winding rather than trusted.
##
## `FaceData.normal` is a stored field and a caller may not have refreshed it;
## the vertex order is the authority. Same cross-product convention as
## `FaceData._compute_normal()`.
static func _face_normal(face: FaceData) -> Vector3:
	var verts := face.local_verts
	if verts.size() < 3:
		return face.normal
	var a: Vector3 = verts[0]
	for i in range(1, verts.size() - 1):
		var normal := (verts[i + 1] - a).cross(verts[i] - a)
		if normal.length_squared() > 0.000001:
			return normal.normalized()
	return face.normal


static func _is_axis_direction(direction: Vector3, epsilon: float) -> bool:
	var tolerance := maxf(0.999, 1.0 - epsilon)
	return (
		absf(direction.dot(Vector3.RIGHT)) >= tolerance
		or absf(direction.dot(Vector3.UP)) >= tolerance
		or absf(direction.dot(Vector3.BACK)) >= tolerance
	)


static func _on_box_shell(point: Vector3, bounds: AABB, epsilon: float) -> bool:
	var low := bounds.position
	var high := bounds.position + bounds.size
	if point.x < low.x - epsilon or point.x > high.x + epsilon:
		return false
	if point.y < low.y - epsilon or point.y > high.y + epsilon:
		return false
	if point.z < low.z - epsilon or point.z > high.z + epsilon:
		return false
	return (
		absf(point.x - low.x) <= epsilon
		or absf(point.x - high.x) <= epsilon
		or absf(point.y - low.y) <= epsilon
		or absf(point.y - high.y) <= epsilon
		or absf(point.z - low.z) <= epsilon
		or absf(point.z - high.z) <= epsilon
	)


static func _quantize(point: Vector3, epsilon: float) -> String:
	var step := maxf(epsilon, 0.000001)
	return "%d,%d,%d" % [roundi(point.x / step), roundi(point.y / step), roundi(point.z / step)]
