@tool
extends RefCounted
class_name HFValidationSystem

const DraftBrush = preload("../brush_instance.gd")
const HFPaintGrid = preload("../paint/hf_paint_grid.gd")

var root: Node3D

## Vertex welding tolerance — vertices closer than this are considered coincident.
## Increase for legacy .map imports with floating-point drift (e.g. 0.01–0.1).
var weld_tolerance: float = 0.001

## Maximum allowed distance a vertex may deviate from its face plane before
## the face is flagged as non-planar. Increase for imported geometry.
var planarity_tolerance: float = 0.01

## Diagnostic: how many brush pairs reached an AABB test in the last
## `check_bake_issues()` pass. Read by the scale test and useful when profiling a
## cutter-heavy level. Reset at the start of every pass.
var pair_tests: int = 0


func _init(level_root: Node3D) -> void:
	root = level_root


func check_missing_dependencies() -> Array:
	var warnings: Array = []
	if not root:
		return warnings
	# Material palette checks
	if root.material_manager:
		var materials: Array = root.material_manager.materials
		for i in range(materials.size()):
			var mat = materials[i]
			if mat == null:
				warnings.append("Material palette entry %d is null" % i)
				continue
			if mat.resource_path != "" and not ResourceLoader.exists(mat.resource_path):
				warnings.append("Material %d path missing: %s" % [i, mat.resource_path])
			if mat is ShaderMaterial:
				var shader_mat := mat as ShaderMaterial
				if shader_mat.shader == null:
					warnings.append("ShaderMaterial %d has no shader" % i)
	# Blend shader check for heightmaps
	var has_heightmap := false
	if root.paint_layers:
		for layer in root.paint_layers.layers:
			if layer and layer.has_heightmap():
				has_heightmap = true
				break
	if not has_heightmap and root.generated_heightmap_floors:
		has_heightmap = root.generated_heightmap_floors.get_child_count() > 0
	if has_heightmap:
		var blend_path := "res://addons/hammerforge/paint/hf_blend.gdshader"
		if not ResourceLoader.exists(blend_path):
			warnings.append("Missing blend shader: %s" % blend_path)
	# Face material bake without palette
	if root.bake_use_face_materials and root.material_manager:
		if root.material_manager.materials.is_empty():
			warnings.append("Face material bake enabled but material palette is empty")
	return warnings


func validate(auto_fix: bool = false) -> Dictionary:
	var issues: Array = []
	var fixed := 0
	if not root:
		return {"issues": issues, "fixed": fixed}

	# Dependencies
	for warning in check_missing_dependencies():
		issues.append("Dependency: %s" % str(warning))

	# Zero-size brushes
	var brush_nodes: Array = []
	if root.draft_brushes_node:
		brush_nodes.append_array(root.draft_brushes_node.get_children())
	if root.pending_node:
		brush_nodes.append_array(root.pending_node.get_children())
	if root.committed_node:
		brush_nodes.append_array(root.committed_node.get_children())
	var geometry_repairs: Array[DraftBrush] = []
	var brushes_to_delete: Array[DraftBrush] = []
	for node in brush_nodes:
		if not (node is DraftBrush):
			continue
		var brush := node as DraftBrush
		var size = brush.size
		# Finite first, then the sign. Every comparison against NaN is false and
		# an infinite size is legitimately `> 0.0`, so the sign test below could
		# not see either — and this is the backstop: a mapper with a NaN-sized
		# brush saw a clean badge, baked, and got a mesh with a poisoned AABB
		# with nothing anywhere naming the brush responsible. The brush cannot be
		# found by eye either, because a NaN size draws nothing.
		if not size.is_finite():
			issues.append("Brush size is not a number: %s" % brush.name)
			if auto_fix:
				brush.size = root.brush_size_default
				fixed += 1
		elif size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
			# A negative size is not a zero size. It builds the brush inside out,
			# with every face normal pointing the opposite way from the vertices
			# it holds, and saying "zero" sends the reader looking for the wrong
			# thing.
			var negative: bool = size.x < 0.0 or size.y < 0.0 or size.z < 0.0
			var label: String = "Inverted brush" if negative else "Zero-size brush"
			issues.append("%s: %s" % [label, brush.name])
			if auto_fix:
				var next = Vector3(
					max(0.1, abs(size.x)), max(0.1, abs(size.y)), max(0.1, abs(size.z))
				)
				brush.size = next
				fixed += 1
		# The transform has the same effect and nothing checked it either. There
		# is no honest repair for a non-finite origin or basis, so this reports.
		if not brush.global_transform.is_finite():
			issues.append("Brush position is not a number: %s" % brush.name)
		_check_brush_geometry(brush, issues, geometry_repairs, brushes_to_delete)

	# The repairs and the deletion happen after the walk, so the loop is not
	# mutating the list it is reading.
	if auto_fix:
		for brush in geometry_repairs:
			var repaired := fix_non_planar_faces(brush)
			repaired += weld_brush_vertices(brush)
			if repaired > 0:
				fixed += repaired
				if root.has_method("tag_brush_dirty"):
					root.tag_brush_dirty(str(brush.brush_id))
		for brush in brushes_to_delete:
			if is_instance_valid(brush) and root.brush_system:
				root.brush_system.delete_brush(brush)
				fixed += 1

	# Invalid face indices in selection
	var invalid_indices := 0
	var next_selection: Dictionary = {}
	for key in root.face_selection.keys():
		var brush = root._find_brush_by_key(str(key))
		var indices: Array = root.face_selection.get(key, [])
		if not brush or not (brush is DraftBrush):
			invalid_indices += indices.size()
			continue
		var max_idx = (brush as DraftBrush).faces.size()
		var filtered: Array = []
		for idx in indices:
			var value = int(idx)
			if value >= 0 and value < max_idx:
				filtered.append(value)
			else:
				invalid_indices += 1
		if filtered.size() > 0:
			next_selection[key] = filtered
	if invalid_indices > 0:
		issues.append("Face selection contains %d invalid indices" % invalid_indices)
		if auto_fix:
			root.face_selection = next_selection
			root._apply_face_selection()
			fixed += invalid_indices

	# Face material indices out of palette bounds
	var palette_count = root.material_manager.materials.size() if root.material_manager else 0
	var invalid_face_mats := 0
	var invalid_projections := 0
	for node in brush_nodes:
		if not (node is DraftBrush):
			continue
		var brush := node as DraftBrush
		for face in brush.faces:
			if face == null:
				continue
			var idx = int(face.material_idx)
			# -1 is the default slot. Anything else has to be in the palette —
			# below it as well as past the end, which a level can acquire from a
			# file written against a longer palette or by a call that was never
			# checked.
			if idx < -1 or idx >= palette_count:
				invalid_face_mats += 1
				if auto_fix:
					face.material_idx = -1
			if not FaceData.is_valid_projection(int(face.uv_projection)):
				invalid_projections += 1
				if auto_fix:
					face.uv_projection = FaceData.UVProjection.PLANAR_Z
					face.custom_uvs = PackedVector2Array()
	if invalid_face_mats > 0:
		issues.append("Faces reference missing materials: %d" % invalid_face_mats)
		if auto_fix:
			fixed += invalid_face_mats
			if root.brush_system:
				root.brush_system._refresh_brush_previews()
	if invalid_projections > 0:
		issues.append("Faces carry a UV projection that is not one: %d" % invalid_projections)
		if auto_fix:
			fixed += invalid_projections
			if root.brush_system:
				root.brush_system._refresh_brush_previews()

	# Two entities answering to the same authored name, and wiring with a field
	# missing. A level can get either from a paste, a `.map` import or a hand
	# edit, so the check at the setter is not enough on its own.
	var seen_names: Dictionary = {}
	var duplicate_names: Array = []
	var broken_connections := 0
	if root.entities_node:
		for child in root.entities_node.get_children():
			var authored := str(child.get_meta("entity_name", "")).strip_edges()
			if authored != "":
				if seen_names.has(authored):
					if not (authored in duplicate_names):
						duplicate_names.append(authored)
				seen_names[authored] = true
			for connection in child.get_meta("entity_io_outputs", []):
				if not (connection is Dictionary):
					broken_connections += 1
					continue
				var fields: Dictionary = connection
				var delay = fields.get("delay", 0.0)
				if (
					str(fields.get("output_name", "")).strip_edges() == ""
					or str(fields.get("target_name", "")).strip_edges() == ""
					or str(fields.get("input_name", "")).strip_edges() == ""
					or not is_finite(float(delay))
					or float(delay) < 0.0
				):
					broken_connections += 1
	for authored in duplicate_names:
		issues.append("Entity name '%s' is answered to by more than one entity" % authored)
	if broken_connections > 0:
		issues.append(
			(
				"I/O connections with a missing field or a delay that is not one: %d"
				% broken_connections
			)
		)

	# Paint layers without grid
	if root.paint_layers:
		var grid_template: HFPaintGrid = root.paint_layers.base_grid
		for layer in root.paint_layers.layers:
			if layer == null:
				continue
			if layer.grid == null:
				issues.append("Paint layer %s has no grid" % str(layer.layer_id))
				if auto_fix:
					if grid_template == null:
						grid_template = HFPaintGrid.new()
						root.paint_layers.base_grid = grid_template
					var grid = grid_template.duplicate() as HFPaintGrid
					if grid == null:
						grid = HFPaintGrid.new()
					grid.layer_y = root.grid_plane_origin.y
					layer.grid = grid
					fixed += 1

	return {"issues": issues, "fixed": fixed}


# ---------------------------------------------------------------------------
# Bake-specific issue detection
# ---------------------------------------------------------------------------


## Scan for issues that affect bake quality. Returns Array of Dictionaries:
## {type: String, severity: int (0=info,1=warn,2=error), message: String, node: Node3D or null}
func check_bake_issues() -> Array:
	var issues: Array = []
	if not root:
		return issues
	var brush_nodes: Array = []
	if root.draft_brushes_node:
		brush_nodes.append_array(root.draft_brushes_node.get_children())
	if root.committed_node:
		brush_nodes.append_array(root.committed_node.get_children())

	# One pass builds every world AABB the subtraction checks need, and one sweep
	# answers both of them. Testing each subtraction against the whole brush list
	# and then every subtraction against every other made the two checks cost
	# roughly brushes times subtractions plus subtractions squared, on a level
	# where most of those pairs are nowhere near each other.
	pair_tests = 0
	var records := _build_brush_records(brush_nodes)
	var overlaps := _sweep_subtract_pairs(records)

	for node in brush_nodes:
		if not (node is DraftBrush):
			continue
		var brush := node as DraftBrush
		if root.is_entity_node(brush):
			continue
		_check_degenerate_brush(brush, issues)
		_check_floating_subtract(brush, overlaps["grounded"], issues)
		_check_non_manifold(brush, issues)
		_check_non_planar_faces(brush, issues)

	_report_overlapping_subtracts(records, overlaps["subtract_pairs"], issues)
	_check_micro_gaps(brush_nodes, issues)
	issues.append_array(check_occlusion_coverage())
	return issues


func _check_degenerate_brush(brush: DraftBrush, issues: Array) -> void:
	var size = brush.size
	var min_dim := min(size.x, min(size.y, size.z))
	if min_dim < 0.01 and (size.x > 0.0 or size.y > 0.0 or size.z > 0.0):
		issues.append(
			{
				"type": "degenerate",
				"severity": 2,
				"message": "Near-zero thickness brush '%s' (%.3f)" % [brush.name, min_dim],
				"node": brush
			}
		)
	var max_dim := max(size.x, max(size.y, size.z))
	if max_dim > 2048.0:
		issues.append(
			{
				"type": "oversized",
				"severity": 1,
				"message": "Very large brush '%s' (%.0f units)" % [brush.name, max_dim],
				"node": brush
			}
		)


## Every brush the subtraction checks care about, with its world AABB measured
## once, in the order the level lists them.
##
## The box is the brush's own size placed at its origin, which is what both
## checks have always compared. It ignores rotation deliberately: widening it to
## the turned brush's real extent would change which levels report an issue, and
## that is a different question from this one.
func _build_brush_records(brush_nodes: Array) -> Array:
	var records: Array = []
	for node in brush_nodes:
		if not (node is DraftBrush):
			continue
		var brush := node as DraftBrush
		if root.is_entity_node(brush):
			continue
		var half: Vector3 = brush.size * 0.5
		(
			records
			. append(
				{
					"brush": brush,
					"aabb": AABB(brush.global_position - half, brush.size),
					"subtract": brush.operation == CSGShape3D.OPERATION_SUBTRACTION,
				}
			)
		)
	return records


## Sort along one axis and walk it, keeping only the boxes still open at the
## current position. Two boxes that intersect must overlap on that axis, so they
## are both in the active list at the same moment and every intersecting pair is
## seen exactly once. Boxes that are far apart never meet.
##
## The axis is whichever one the level is widest on, because that is the one that
## separates the most brushes. A level is usually a floor plan, so it is normally
## X or Z and almost never Y.
##
## Returns the subtractions that landed on an additive brush, keyed by instance
## id, and the subtraction pairs that overlap each other, as index pairs into
## `records`.
func _sweep_subtract_pairs(records: Array) -> Dictionary:
	var grounded: Dictionary = {}
	var subtract_pairs: Array = []
	var axis := _widest_axis(records)
	var order: Array = []
	for i in range(records.size()):
		order.append(i)
	order.sort_custom(
		func(a: int, b: int) -> bool:
			return (
				(records[a]["aabb"] as AABB).position[axis]
				< (records[b]["aabb"] as AABB).position[axis]
			)
	)
	var active: Array = []
	for index: int in order:
		var record: Dictionary = records[index]
		var aabb: AABB = record["aabb"]
		var still_open: Array = []
		for other_index: int in active:
			var other: Dictionary = records[other_index]
			var other_aabb: AABB = other["aabb"]
			if other_aabb.end[axis] < aabb.position[axis]:
				continue
			still_open.append(other_index)
			pair_tests += 1
			if not other_aabb.intersects(aabb):
				continue
			if record["subtract"] and other["subtract"]:
				subtract_pairs.append([other_index, index])
			elif record["subtract"]:
				grounded[(record["brush"] as Node).get_instance_id()] = true
			elif other["subtract"]:
				grounded[(other["brush"] as Node).get_instance_id()] = true
		still_open.append(index)
		active = still_open
	return {"grounded": grounded, "subtract_pairs": subtract_pairs}


## The axis the brushes are most spread out along, as an index into Vector3.
static func _widest_axis(records: Array) -> int:
	if records.is_empty():
		return Vector3.AXIS_X
	var low: Vector3 = (records[0]["aabb"] as AABB).position
	var high: Vector3 = low
	for record in records:
		var aabb: AABB = record["aabb"]
		low = Vector3(
			minf(low.x, aabb.position.x), minf(low.y, aabb.position.y), minf(low.z, aabb.position.z)
		)
		high = Vector3(
			maxf(high.x, aabb.position.x),
			maxf(high.y, aabb.position.y),
			maxf(high.z, aabb.position.z)
		)
	var spread: Vector3 = high - low
	if spread.x >= spread.y and spread.x >= spread.z:
		return Vector3.AXIS_X
	if spread.z >= spread.y:
		return Vector3.AXIS_Z
	return Vector3.AXIS_Y


func _check_floating_subtract(brush: DraftBrush, grounded: Dictionary, issues: Array) -> void:
	if brush.operation != CSGShape3D.OPERATION_SUBTRACTION:
		return
	if grounded.has(brush.get_instance_id()):
		return
	issues.append(
		{
			"type": "floating_subtract",
			"severity": 1,
			"message": "Subtraction '%s' doesn't intersect any additive brush" % brush.name,
			"node": brush
		}
	)


## Report the overlapping pairs in level order, so the list reads the same as it
## did when both loops walked the brushes from the top.
func _report_overlapping_subtracts(records: Array, pairs: Array, issues: Array) -> void:
	var ordered: Array = []
	for pair in pairs:
		var first: int = mini(pair[0], pair[1])
		var second: int = maxi(pair[0], pair[1])
		ordered.append([first, second])
	ordered.sort_custom(
		func(a: Array, b: Array) -> bool: return a[0] < b[0] if a[0] != b[0] else a[1] < b[1]
	)
	for pair in ordered:
		var a: DraftBrush = records[pair[0]]["brush"]
		var b: DraftBrush = records[pair[1]]["brush"]
		issues.append(
			{
				"type": "overlapping_subtract",
				"severity": 1,
				"message": "Overlapping subtractions: '%s' and '%s'" % [a.name, b.name],
				"node": a
			}
		)


## Check for non-manifold and open-edge geometry by analyzing the edge adjacency
## of a brush's faces. An edge shared by exactly 2 faces is manifold; 1 = open edge;
## 3+ = non-manifold edge.
func _check_non_manifold(brush: DraftBrush, issues: Array) -> void:
	if brush.faces.is_empty():
		return
	# Build edge→face count map. Edge key = sorted pair of rounded vertex positions.
	var edge_counts: Dictionary = {}  # String -> int
	for face_idx in range(brush.faces.size()):
		var face = brush.faces[face_idx]
		if not face or face.local_verts.size() < 3:
			continue
		var verts: PackedVector3Array = face.local_verts
		for i in range(verts.size()):
			var a: Vector3 = verts[i]
			var b: Vector3 = verts[(i + 1) % verts.size()]
			var key: Array = _edge_key(a, b)
			edge_counts[key] = edge_counts.get(key, 0) + 1
	var open_count := 0
	var non_manifold_count := 0
	for key: Array in edge_counts:
		var count: int = edge_counts[key]
		if count == 1:
			open_count += 1
		elif count > 2:
			non_manifold_count += 1
	if open_count > 0:
		issues.append(
			{
				"type": "open_edge",
				"severity": 1,
				"message":
				(
					"Brush '%s' has %d open edge(s) — geometry is not watertight"
					% [brush.name, open_count]
				),
				"node": brush
			}
		)
	if non_manifold_count > 0:
		issues.append(
			{
				"type": "non_manifold",
				"severity": 2,
				"message":
				(
					"Brush '%s' has %d non-manifold edge(s) — may cause bake artifacts"
					% [brush.name, non_manifold_count]
				),
				"node": brush
			}
		)


## Create a canonical edge key from two vertices (order-independent, rounded to 0.001).
## This tolerance is intentionally fixed — it must NOT vary with weld_tolerance,
## because non-manifold/open-edge detection depends on stable topology hashing.
## An edge as the pair of grid cells its ends fall in, smaller end first so
## (A,B) and (B,A) are one edge.
##
## Deliberately a pair of Vector3i rather than a formatted string. This runs for
## every edge of every face of every brush, and building the string cost more
## than everything it was a key for.
func _edge_key(a: Vector3, b: Vector3) -> Array:
	var ai := _quantise(a, 0.001)
	var bi := _quantise(b, 0.001)
	if (
		ai.x < bi.x
		or (ai.x == bi.x and ai.y < bi.y)
		or (ai.x == bi.x and ai.y == bi.y and ai.z < bi.z)
	):
		return [ai, bi]
	return [bi, ai]


## The geometry checks validate() had none of.
##
## Fixing the setters that create these states does nothing for a `.hflevel`
## saved last week, a `.map` imported from another editor, or a file that was
## hand-edited. The validator is what covers that ground, and it checked brush
## size, face selection indices, material slots, UV projections, entity names,
## I/O fields and paint layer grids — and nothing about the faces themselves,
## while owning two geometry repairs that nothing called.
func _check_brush_geometry(
	brush: DraftBrush, issues: Array, repairs: Array[DraftBrush], to_delete: Array[DraftBrush]
) -> void:
	if brush.faces.is_empty():
		# A live, selectable, saved brush with no geometry. It exports as a solid
		# with no planes, which is malformed in both `.map` formats, and the
		# mapper cannot find it to delete it because it draws nothing. There is
		# nothing to repair, so the fix is to remove it.
		issues.append("Brush has no faces: %s" % brush.name)
		to_delete.append(brush)
		return
	var non_finite := 0
	var worst_drift := 0.0
	var coincident := false
	for face in brush.faces:
		if face == null:
			continue
		var verts: PackedVector3Array = face.local_verts
		for v in verts:
			if not v.is_finite():
				non_finite += 1
		if verts.size() < 3:
			continue
		for i in verts.size():
			for j in range(i + 1, verts.size()):
				# Near but not identical, which is what weld_brush_vertices()
				# repairs: it snaps a group to its average, so afterwards the pair
				# is exactly coincident rather than gone. A pair that is already
				# exactly coincident is a degenerate face, not a weld job.
				var gap := verts[i].distance_to(verts[j])
				if gap > 0.0 and gap <= weld_tolerance:
					coincident = true
		worst_drift = maxf(worst_drift, _face_plane_drift(face))
	if non_finite > 0:
		# No honest repair: there is no nearest position to a NaN, and the value
		# poisons the brush AABB and normal and propagates through any later clip
		# or carve. Report it and name the brush.
		issues.append("Brush has %d vertices that are not numbers: %s" % [non_finite, brush.name])
	if worst_drift > planarity_tolerance:
		issues.append("Brush face is not a plane (%.4f unit drift): %s" % [worst_drift, brush.name])
		repairs.append(brush)
	elif coincident:
		issues.append("Brush has vertices a weld apart: %s" % brush.name)
		repairs.append(brush)


## How far the furthest vertex of a face sits off the plane through its first
## three non-collinear vertices, or 0.0 when the face has no measurable plane.
func _face_plane_drift(face) -> float:
	var verts: PackedVector3Array = face.local_verts
	if verts.size() < 4:
		return 0.0  # triangles are always planar
	var anchor: Vector3 = verts[0]
	if not anchor.is_finite():
		return 0.0
	var normal := Vector3.ZERO
	for i in range(1, verts.size() - 1):
		if not verts[i].is_finite() or not verts[i + 1].is_finite():
			continue
		# Both edges have to be real edges. A pair of near-coincident vertices
		# normalises to a direction that has nothing to do with the face, and the
		# plane built from it reports the rest of the face as drift — so a brush
		# with two vertices welded together came back as "not a plane" instead.
		if (
			(verts[i] - anchor).length() <= weld_tolerance
			or (verts[i + 1] - anchor).length() <= weld_tolerance
		):
			continue
		var candidate: Vector3 = (verts[i + 1] - anchor).normalized().cross(
			(verts[i] - anchor).normalized()
		)
		if candidate.length() > 0.0001:
			normal = candidate.normalized()
			break
	if normal.length_squared() < 0.0001 or not normal.is_finite():
		return 0.0
	var drift := 0.0
	for v in verts:
		if not v.is_finite():
			continue
		drift = maxf(drift, absf(normal.dot(v - anchor)))
	return drift


# ---------------------------------------------------------------------------
# Non-planar face detection
# ---------------------------------------------------------------------------


## Check whether any face has vertices that deviate from the face plane beyond
## planarity_tolerance.  Returns issues appended to the provided array.
func _check_non_planar_faces(brush: DraftBrush, issues: Array) -> void:
	for face_idx in range(brush.faces.size()):
		var face = brush.faces[face_idx]
		if not face or face.local_verts.size() < 4:
			continue  # triangles are always planar
		var verts: PackedVector3Array = face.local_verts
		var normal: Vector3 = face.normal
		if normal.length_squared() < 0.0001:
			# Compute from first 3 verts
			normal = (verts[2] - verts[0]).cross(verts[1] - verts[0]).normalized()
		if normal.length_squared() < 0.0001:
			continue
		var plane_d: float = normal.dot(verts[0])
		var max_deviation := 0.0
		for i in range(1, verts.size()):
			var dev: float = absf(normal.dot(verts[i]) - plane_d)
			if dev > max_deviation:
				max_deviation = dev
		if max_deviation > planarity_tolerance:
			issues.append(
				{
					"type": "non_planar",
					"severity": 1,
					"message":
					(
						"Brush '%s' face %d has %.4f unit vertex drift (tolerance %.4f)"
						% [brush.name, face_idx, max_deviation, planarity_tolerance]
					),
					"node": brush
				}
			)


# ---------------------------------------------------------------------------
# Micro-gap detection (near-coincident but not welded vertices between brushes)
# ---------------------------------------------------------------------------


## Detect vertices across different brushes that are within weld_tolerance of each
## other but not exactly coincident.  These cause micro-gaps after bake.
## Uses spatial hashing with 27-cell neighbor lookup so pairs straddling a bucket
## boundary are never missed.
func _check_micro_gaps(all_brushes: Array, issues: Array) -> void:
	var tol: float = weld_tolerance
	# Collect all world-space vertices into spatial hash
	var entries: Array = []  # Array of {brush: DraftBrush, pos: Vector3}
	var cells: Dictionary = {}  # cell_key -> Array[int] (indices into entries)
	for node in all_brushes:
		if not (node is DraftBrush):
			continue
		var brush := node as DraftBrush
		if root.is_entity_node(brush):
			continue
		for face in brush.faces:
			if not face or face.local_verts.size() < 3:
				continue
			for vi in range(face.local_verts.size()):
				var world_v: Vector3 = brush.global_transform * face.local_verts[vi]
				var idx: int = entries.size()
				entries.append({"brush": brush, "pos": world_v})
				var key: Vector3i = _snap_key(world_v, tol)
				if not cells.has(key):
					cells[key] = []
				(cells[key] as Array).append(idx)
	# For each vertex, search own cell + 26 neighbors for cross-brush near-pairs
	var flagged_pairs: Dictionary = {}  # avoid duplicate warnings
	for i in range(entries.size()):
		var pos_i: Vector3 = entries[i]["pos"]
		for cell_key: Vector3i in _cell_keys(pos_i, tol):
			for j: int in cells.get(cell_key, []):
				if j <= i:
					continue  # ordered pair dedup
				if entries[i]["brush"] == entries[j]["brush"]:
					continue
				var dist: float = pos_i.distance_to(entries[j]["pos"])
				if dist > 0.0 and dist <= tol:
					var pair_key: String = _brush_pair_key(entries[i]["brush"], entries[j]["brush"])
					flagged_pairs[pair_key] = flagged_pairs.get(pair_key, 0) + 1
	for pair_key: String in flagged_pairs:
		var count: int = flagged_pairs[pair_key]
		issues.append(
			{
				"type": "micro_gap",
				"severity": 1,
				"message":
				(
					"Micro-gap: %d near-coincident vertex pair(s) between %s (weld tolerance %.4f)"
					% [count, pair_key, weld_tolerance]
				),
				"node": null
			}
		)


func _brush_pair_key(a: DraftBrush, b: DraftBrush) -> String:
	var na: String = a.name if a.name <= b.name else b.name
	var nb: String = b.name if a.name <= b.name else a.name
	return "'%s' and '%s'" % [na, nb]


# ---------------------------------------------------------------------------
# Auto-fix: weld near-coincident vertices within a brush
# ---------------------------------------------------------------------------


## Snap vertices that are within weld_tolerance of each other to a shared position.
## Operates on face local_verts in local space.  Uses BFS over a spatial hash with
## 27-cell neighbor lookup so pairs straddling a bucket boundary are never missed.
## Returns number of vertices welded.
func weld_brush_vertices(brush: DraftBrush) -> int:
	if not brush or brush.faces.is_empty():
		return 0
	var tol: float = weld_tolerance
	# Collect every vertex reference into a flat list + spatial hash
	var entries: Array = []  # Array of {fi: int, vi: int, pos: Vector3}
	var cells: Dictionary = {}  # cell_key -> Array[int]
	for fi in range(brush.faces.size()):
		var face = brush.faces[fi]
		if not face:
			continue
		for vi in range(face.local_verts.size()):
			var idx: int = entries.size()
			var pos: Vector3 = face.local_verts[vi]
			entries.append({"fi": fi, "vi": vi, "pos": pos})
			var key: Vector3i = _snap_key(pos, tol)
			if not cells.has(key):
				cells[key] = []
			(cells[key] as Array).append(idx)
	# BFS grouping: vertices within tolerance are transitively merged
	var group_of: PackedInt32Array = PackedInt32Array()
	group_of.resize(entries.size())
	group_of.fill(-1)
	var groups: Array = []  # Array of Array[int]
	for seed_idx in range(entries.size()):
		if group_of[seed_idx] >= 0:
			continue
		var gid: int = groups.size()
		var members: Array = [seed_idx]
		group_of[seed_idx] = gid
		var queue: Array = [seed_idx]
		while not queue.is_empty():
			var cur: int = queue.pop_front()
			var cur_pos: Vector3 = entries[cur]["pos"]
			for cell_key: Vector3i in _cell_keys(cur_pos, tol):
				for neighbor_idx: int in cells.get(cell_key, []):
					if group_of[neighbor_idx] >= 0:
						continue
					if cur_pos.distance_to(entries[neighbor_idx]["pos"]) <= tol:
						group_of[neighbor_idx] = gid
						members.append(neighbor_idx)
						queue.append(neighbor_idx)
		groups.append(members)
	# Compute group averages and write back
	var welded := 0
	var dirty_faces: Dictionary = {}  # fi -> true
	for members: Array in groups:
		if members.size() < 2:
			continue
		var avg := Vector3.ZERO
		for idx: int in members:
			avg += entries[idx]["pos"]
		avg /= float(members.size())
		for idx: int in members:
			var fi: int = entries[idx]["fi"]
			var vi: int = entries[idx]["vi"]
			var face = brush.faces[fi]
			var verts: PackedVector3Array = face.local_verts
			if verts[vi].distance_to(avg) > 0.0:
				verts[vi] = avg
				face.local_verts = verts
				welded += 1
				dirty_faces[fi] = true
	# Refresh derived state (normal, bounds) on every modified face
	for fi: int in dirty_faces:
		brush.faces[fi].ensure_geometry()
	return welded


# ---------------------------------------------------------------------------
# Auto-fix: project drifting vertices back onto their face plane
# ---------------------------------------------------------------------------


## For each face with >3 vertices, compute the best-fit plane from the first 3
## vertices and project any drifting vertices back onto it.  Returns number of
## vertices corrected.
func fix_non_planar_faces(brush: DraftBrush) -> int:
	if not brush or brush.faces.is_empty():
		return 0
	var fixed := 0
	for face in brush.faces:
		if not face or face.local_verts.size() < 4:
			continue
		var verts: PackedVector3Array = face.local_verts
		var normal: Vector3 = (verts[2] - verts[0]).cross(verts[1] - verts[0]).normalized()
		if normal.length_squared() < 0.0001:
			continue
		var plane_d: float = normal.dot(verts[0])
		for i in range(1, verts.size()):
			var dev: float = normal.dot(verts[i]) - plane_d
			if absf(dev) > planarity_tolerance:
				verts[i] = verts[i] - normal * dev
				fixed += 1
		face.local_verts = verts
		if fixed > 0:
			face.ensure_geometry()
	return fixed


## The grid cell a point falls in, at `tol` spacing.
##
## The index rather than the formatted position: same buckets, no allocation.
## `snapped()` is kept in the middle so the bucket boundaries are exactly the
## ones this used to produce.
func _quantise(v: Vector3, tol: float) -> Vector3i:
	return Vector3i(
		roundi(snapped(v.x, tol) / tol),
		roundi(snapped(v.y, tol) / tol),
		roundi(snapped(v.z, tol) / tol)
	)


func _snap_key(v: Vector3, tol: float) -> Vector3i:
	return _quantise(v, tol)


## Return all 27 cell keys (self + 26 neighbors) for a spatial hash lookup.
## Guarantees that any point within `cell_size` distance shares at least one cell.
## This cell and its 26 neighbours, so a pair straddling a boundary is still
## found.
##
## In index space the neighbours are just +/-1, which is why this is the change
## that mattered: the old version formatted 27 strings for every vertex of every
## brush, and that was almost the whole cost of a Check Issues pass.
func _cell_keys(v: Vector3, cell_size: float) -> Array:
	var c := _quantise(v, cell_size)
	var keys: Array = []
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				keys.append(Vector3i(c.x + dx, c.y + dy, c.z + dz))
	return keys


# ---------------------------------------------------------------------------
# Occlusion coverage analysis
# ---------------------------------------------------------------------------


## Estimate how much of the baked geometry AABB is covered by OccluderInstance3D
## nodes.  Returns an array of validation issues (severity 0 = info, 1 = warn).
func check_occlusion_coverage() -> Array:
	var issues: Array = []
	if not root:
		return issues
	if not _object_has_property(root, "baked_container"):
		return issues
	var container: Node3D = root.get("baked_container") as Node3D
	if not container or not is_instance_valid(container):
		return issues

	# Compute total baked mesh AABB (recurse into BakedChunk_* nodes).
	var baked_aabb := AABB()
	var has_mesh := false
	var all_meshes: Array = _collect_mesh_instances_recursive(container)
	for mi: MeshInstance3D in all_meshes:
		if mi.mesh:
			var mi_aabb: AABB = (
				(container.global_transform.affine_inverse() * mi.global_transform)
				* mi.mesh.get_aabb()
			)
			if has_mesh:
				baked_aabb = baked_aabb.merge(mi_aabb)
			else:
				baked_aabb = mi_aabb
				has_mesh = true
	if not has_mesh:
		return issues

	# Compute total occluder area vs baked surface area estimate.
	var occluder_node: Node = container.find_child("Occluders", false, false)
	var occluder_area := 0.0
	var occluder_count := 0
	if occluder_node:
		for child in occluder_node.get_children():
			if child is OccluderInstance3D:
				var inst: OccluderInstance3D = child as OccluderInstance3D
				occluder_count += 1
				var occ = inst.occluder
				if occ is ArrayOccluder3D:
					occluder_area += _array_occluder_area(occ)

	# Estimate baked surface area from AABB (2 * (xy + xz + yz)).
	var s: Vector3 = baked_aabb.size
	var baked_surface: float = 2.0 * (s.x * s.y + s.x * s.z + s.y * s.z)
	if baked_surface < 0.01:
		return issues

	var coverage: float = occluder_area / baked_surface
	if occluder_count == 0 and _object_property_as_bool(root, "bake_generate_occluders", false):
		(
			issues
			. append(
				{
					"type": "OcclusionMissing",
					"severity": 1,
					"message":
					"Occluder generation enabled but no occluders were created (surfaces may be too small)",
					"node": container
				}
			)
		)
	elif occluder_count > 0:
		issues.append(
			{
				"type": "OcclusionCoverage",
				"severity": 0,
				"message":
				(
					"Occlusion: %d occluders covering ~%.0f%% of baked AABB surface"
					% [occluder_count, coverage * 100.0]
				),
				"node": occluder_node
			}
		)
	return issues


func _array_occluder_area(occ: ArrayOccluder3D) -> float:
	var verts: PackedVector3Array = occ.vertices
	var indices: PackedInt32Array = occ.indices
	var area := 0.0
	var i := 0
	while i + 2 < indices.size():
		var a: Vector3 = verts[indices[i]]
		var b: Vector3 = verts[indices[i + 1]]
		var c: Vector3 = verts[indices[i + 2]]
		area += (c - a).cross(b - a).length() * 0.5
		i += 3
	return area


static func _collect_mesh_instances_recursive(node: Node) -> Array:
	var result: Array = []
	for child in node.get_children():
		if child is MeshInstance3D:
			result.append(child)
		elif child is Node3D and child.name != "Occluders":
			result.append_array(_collect_mesh_instances_recursive(child))
	return result


static func _object_has_property(obj: Object, property_name: String) -> bool:
	if not obj or property_name == "":
		return false
	for prop in obj.get_property_list():
		if prop.get("name", "") == property_name:
			return true
	return false


static func _object_property_as_bool(
	obj: Object, property_name: String, default_value: bool
) -> bool:
	if not _object_has_property(obj, property_name):
		return default_value
	return bool(obj.get(property_name))
