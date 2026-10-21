@tool
extends RefCounted
class_name HFBrushConversion

## Convert to Brushes: Godot nodes made into brushes where they stand (#1440).
##
## A blockout started with Godot's CSG nodes, or a crate modelled as a mesh,
## could not join a level as brushes: the mapper redrew each one by hand. A
## `MeshInstance3D` whose mesh closes one convex solid becomes a CUSTOM brush, a
## face per flat surface with that surface's material and UVs. A CSG box,
## cylinder, cone and sphere become those primitives, so they keep their resize
## handles and Sides, and a Depth polygon that is convex becomes a CUSTOM prism.
## The node's material goes on every face of a CSG brush, and either kind of
## material joins the palette when it is not there yet.
##
## A brush stands in the node's global transform. Its scale, and a mirror, are
## folded into the brush the way Apply Rotation and Scale folds them
## (`HFTransformSystem.fold_basis()`), so the brush keeps only the node's turn and
## its size reads in metres.
##
## Everything that cannot be a brush is refused by name and left as it was: a
## concave mesh or polygon, a CSG node with CSG children, which is a boolean of
## several shapes, and one that intersects its parent, which no brush does.
## Godot's own convex decomposition
## (`MeshInstance3D.create_multiple_convex_collisions()`) was tried for splitting
## a concave mesh. On an L of two boxes it gave one hull around the whole L, every
## corner off the mesh's own, so there is no Split: its pieces are not the mesh.

# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const DraftBrush = preload("brush_instance.gd")
const FaceData = preload("face_data.gd")
const HFConvexClip = preload("hf_convex_clip.gd")
const HFTransformSystem = preload("systems/hf_transform_system.gd")
@warning_ignore_restore("shadowed_global_identifier")

const BrushShape = DraftBrush.BrushShape

## How far a corner may stand in front of a face's plane, as a fraction of the
## mesh's size, and the mesh still count as convex. Coarse enough for the float
## noise an imported mesh carries, and far finer than any dent a mapper models.
const CONVEX_TOLERANCE := 0.0001


## Whether `node` is a kind Convert to Brushes takes, before asking whether this
## one can be a brush. The Space menu offers the command on these.
static func is_convertible_kind(node: Object) -> bool:
	return node is MeshInstance3D or node is CSGShape3D


## Make a brush in `root`'s level from each node in `nodes`, in scene order, so a
## CSG cut lands after the shapes it cuts. Nothing is hidden and no undo step is
## recorded; the caller does both.
##
## Returns `{"brushes": Array[DraftBrush], "converted": Array[Node], "refused":
## Array[String], "custom": Array[String]}`: the brushes made, the nodes they were
## made from, each node left alone with why, and each CSG primitive that became
## a custom brush because its scale is uneven across its round side.
static func convert_nodes(root: Node, nodes: Array) -> Dictionary:
	var out := {"brushes": [], "converted": [], "refused": [], "custom": []}
	var ordered: Array = []
	for node in nodes:
		if node is Node and is_instance_valid(node) and (node as Node).is_inside_tree():
			ordered.append(node)
	ordered.sort_custom(func(a: Node, b: Node) -> bool: return b.is_greater_than(a))
	var slots := {}
	for node in ordered:
		var plan := brush_plan(node, root)
		if plan.has("refused"):
			(out["refused"] as Array).append("%s (%s)" % [node.name, plan["refused"]])
			continue
		var brush = root.create_brush_from_info(plan["info"])
		if not (brush is DraftBrush):
			(out["refused"] as Array).append("%s (could not be built)" % node.name)
			continue
		var draft := brush as DraftBrush
		var keep := HFTransformSystem.rotation_part(draft.global_transform.basis)
		var folded: Dictionary = root.transform_system.fold_basis(draft, keep)
		if folded["custom"]:
			(out["custom"] as Array).append(str(node.name))
		# Materials join the palette only for a brush that was made, so a node
		# that could not be leaves the palette as it was.
		var by_surface: Array = plan.get("surface_materials", [])
		for face in draft.faces:
			var mat: Variant = plan.get("material", null)
			if not plan.has("material"):
				var surface: int = face.material_idx
				mat = by_surface[surface] if surface >= 0 and surface < by_surface.size() else null
			face.material_idx = _palette_slot(root, mat, slots)
		draft.rebuild_preview()
		(out["brushes"] as Array).append(draft)
		(out["converted"] as Array).append(node)
	return out


## The brush info `node` converts to, as `{"info": Dictionary}` with what its
## faces wear: `material` for every face, or `surface_materials` indexed by the
## surface number each face's `material_idx` holds. `{"refused": why}` when it
## cannot be a brush. The info's transform is the node's own, scale and all.
static func brush_plan(node: Node, root: Node) -> Dictionary:
	if not is_convertible_kind(node):
		return {"refused": "not a mesh or a CSG shape"}
	if root != null and (node == root or root.is_ancestor_of(node)):
		return {"refused": "part of the level already"}
	if root != null and node.is_ancestor_of(root):
		return {"refused": "it holds the level"}
	var xform: Transform3D = (node as Node3D).global_transform
	if (
		not xform.is_finite()
		or absf(xform.basis.determinant()) < HFTransformSystem.FLAT_DETERMINANT
	):
		return {"refused": "squashed flat"}
	if node is MeshInstance3D:
		return _mesh_plan(node as MeshInstance3D, xform)
	return _csg_plan(node as CSGShape3D, xform)


static func _mesh_plan(node: MeshInstance3D, xform: Transform3D) -> Dictionary:
	var mesh := node.mesh
	if mesh == null or mesh.get_surface_count() == 0:
		return {"refused": "no mesh"}
	if not is_closed_mesh(mesh):
		return {"refused": "not a closed solid"}
	var faces: Array = []
	var materials: Array = []
	for surface in mesh.get_surface_count():
		materials.append(node.get_active_material(surface))
		for face in DraftBrush.faces_of_mesh_surface(mesh, surface):
			face.material_idx = surface
			faces.append(face)
	var refusal := _convexity_refusal(faces)
	if refusal != "":
		return {"refused": refusal}
	return {"info": _custom_info(faces, xform), "surface_materials": materials}


## Whether every triangle surface of `mesh` together closes one solid: each edge
## shared by exactly two triangles, running opposite ways along it. Corners are
## the same point when they round to the same thousandth, as the face merge reads
## them. A surface of lines or points is no solid.
static func is_closed_mesh(mesh: Mesh) -> bool:
	var ids := {}
	var edges := {}
	for surface in mesh.get_surface_count():
		if not DraftBrush.surface_is_triangles(mesh, surface):
			return false
		var arrays: Array = mesh.surface_get_arrays(surface)
		if arrays.is_empty():
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices := PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
			indices = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			for i in verts.size():
				indices.append(i)
		for t in range(0, indices.size() - 2, 3):
			var corners := PackedInt32Array()
			for k in 3:
				var at := indices[t + k]
				if at < 0 or at >= verts.size():
					return false
				var key: Vector3i = DraftBrush._merge_key(verts[at])
				if not ids.has(key):
					ids[key] = ids.size()
				corners.append(ids[key])
			# A triangle with two corners on one point covers nothing.
			if corners[0] == corners[1] or corners[1] == corners[2] or corners[0] == corners[2]:
				continue
			for k in 3:
				var edge := Vector2i(corners[k], corners[(k + 1) % 3])
				edges[edge] = int(edges.get(edge, 0)) + 1
	if edges.is_empty():
		return false
	for edge: Vector2i in edges:
		if int(edges[edge]) != 1 or int(edges.get(Vector2i(edge.y, edge.x), 0)) != 1:
			return false
	return true


static func _csg_plan(node: CSGShape3D, xform: Transform3D) -> Dictionary:
	for child in node.get_children():
		if child is CSGShape3D:
			return {"refused": "it has CSG children"}
	# Only a shape inside another one combines with it; Godot draws a root shape
	# the same whatever its operation says.
	var operation := CSGShape3D.OPERATION_UNION
	if not node.is_root_shape():
		match node.operation:
			CSGShape3D.OPERATION_SUBTRACTION:
				operation = CSGShape3D.OPERATION_SUBTRACTION
			CSGShape3D.OPERATION_INTERSECTION:
				return {"refused": "it intersects its parent, which no brush can"}
	var material: Material = node.get("material") as Material
	if node.is_root_shape() and node.material_override != null:
		material = node.material_override
	var info := {}
	if node is CSGBox3D:
		info = {"shape": BrushShape.BOX, "size": (node as CSGBox3D).size}
	elif node is CSGCylinder3D:
		info = _cylinder_info(node as CSGCylinder3D, xform)
	elif node is CSGSphere3D:
		var sphere := node as CSGSphere3D
		info = {
			"shape": BrushShape.SPHERE,
			"size": Vector3.ONE * sphere.radius * 2.0,
			"sides": sphere.radial_segments,
		}
	elif node is CSGPolygon3D:
		info = _polygon_info(node as CSGPolygon3D, xform)
	else:
		return {"refused": "only a CSG box, cylinder, sphere or Depth polygon converts"}
	if info.has("refused"):
		return info
	info["operation"] = operation
	if not info.has("transform"):
		info["transform"] = xform
	return {"info": info, "material": material}


## A cylinder or a cone, with its sides. Godot's CSG cylinder puts its first side
## corner on +X and a brush's starts on +Z, so the brush is turned about its own
## axis by however far that leaves them apart, and its corners land on the
## node's. Fewer sides than a round brush is built with is a prism or a pyramid,
## made custom from the node's own corners.
static func _cylinder_info(node: CSGCylinder3D, xform: Transform3D) -> Dictionary:
	var sides := node.sides
	var shape := BrushShape.CONE if node.cone else BrushShape.CYLINDER
	if sides >= DraftBrush.MIN_ROUND_SIDES:
		var offset := fposmod(PI / 2.0, TAU / sides)
		if is_equal_approx(offset, TAU / sides):
			offset = 0.0
		var diameter := node.radius * 2.0
		return {
			"shape": shape,
			"size": Vector3(diameter, node.height, diameter),
			"sides": sides,
			"transform": Transform3D(xform.basis * Basis(Vector3.UP, offset), xform.origin),
		}
	var half := node.height * 0.5
	var bottom := PackedVector3Array()
	var top := PackedVector3Array()
	for i in sides:
		var angle := TAU * i / sides
		var around := Vector3(cos(angle), 0.0, sin(angle)) * node.radius
		bottom.append(around + Vector3.DOWN * half)
		top.append(around + Vector3.UP * half)
	var rings: Array = [bottom]
	if node.cone:
		for i in sides:
			rings.append(
				PackedVector3Array([bottom[i], bottom[(i + 1) % sides], Vector3.UP * half])
			)
	else:
		rings.append(top)
		for i in sides:
			var j := (i + 1) % sides
			rings.append(PackedVector3Array([bottom[i], bottom[j], top[j], top[i]]))
	return _custom_info(HFConvexClip.solid_from_rings(rings), xform)


## A Depth polygon: the outline in X and Y at z = 0, pushed back to -depth, as
## Godot builds it. Only a convex outline is one brush.
static func _polygon_info(node: CSGPolygon3D, xform: Transform3D) -> Dictionary:
	if node.mode != CSGPolygon3D.MODE_DEPTH:
		return {"refused": "only a Depth polygon converts"}
	var outline := convex_outline(node.polygon)
	if outline.is_empty():
		return {"refused": "its polygon is not convex"}
	var front := PackedVector3Array()
	var back := PackedVector3Array()
	for point in outline:
		front.append(Vector3(point.x, point.y, 0.0))
		back.append(Vector3(point.x, point.y, -node.depth))
	var rings: Array = [front, back]
	for i in outline.size():
		var j := (i + 1) % outline.size()
		rings.append(PackedVector3Array([front[i], front[j], back[j], back[i]]))
	return _custom_info(HFConvexClip.solid_from_rings(rings), xform)


## `polygon` with repeated and in-line corners dropped, when what is left is a
## convex outline: three corners or more, every turn the same way, and one lap
## round. Empty otherwise.
static func convex_outline(polygon: PackedVector2Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	for point in polygon:
		if points.is_empty() or points[-1].distance_to(point) > 0.0001:
			points.append(point)
	while points.size() > 1 and points[0].distance_to(points[-1]) <= 0.0001:
		points.remove_at(points.size() - 1)
	var corners := PackedVector2Array()
	var count := points.size()
	for i in count:
		var into := points[i] - points[(i - 1 + count) % count]
		var out_of := points[(i + 1) % count] - points[i]
		if absf(into.cross(out_of)) > 0.000001 * into.length() * out_of.length():
			corners.append(points[i])
	count = corners.size()
	if count < 3:
		return PackedVector2Array()
	var hand := 0.0
	var turned := 0.0
	for i in count:
		var into := corners[i] - corners[(i - 1 + count) % count]
		var out_of := corners[(i + 1) % count] - corners[i]
		var turn := signf(into.cross(out_of))
		if hand == 0.0:
			hand = turn
		elif turn != hand:
			return PackedVector2Array()
		turned += into.angle_to(out_of)
	if absf(absf(turned) - TAU) > 0.001:
		return PackedVector2Array()
	return corners


## Why `faces` are not one convex solid, or "" when they are. They are turned to
## face outward first, which a mesh drawn inside out needs.
static func _convexity_refusal(faces: Array) -> String:
	if faces.size() < HFConvexClip.MIN_SOLID_FACES:
		return "not a closed solid"
	var interior := HFConvexClip.interior_point(faces)
	HFConvexClip.orient_faces_outward(faces, interior)
	var bounds := DraftBrush._vertex_bounds(faces)
	var tolerance := maxf(bounds.get_longest_axis_size() * CONVEX_TOLERANCE, 0.00001)
	if not HFConvexClip.is_convex_solid(faces, interior, tolerance):
		return "not convex"
	return ""


## A CUSTOM brush's info: these faces, in the node's own space, standing where
## the node stands.
static func _custom_info(faces: Array, xform: Transform3D) -> Dictionary:
	if faces.is_empty():
		return {"refused": "no volume"}
	var stored: Array = []
	for face in faces:
		stored.append((face as FaceData).to_dict())
	return {
		"shape": BrushShape.CUSTOM,
		"size": DraftBrush._vertex_bounds(faces).size,
		"transform": xform,
		"faces": stored,
	}


## The palette slot holding `mat`, added when it is not there. -1 for none.
static func _palette_slot(root: Node, mat: Variant, added: Dictionary) -> int:
	if not (mat is Material):
		return -1
	if added.has(mat):
		return int(added[mat])
	var palette = root.get("material_manager")
	var slot := -1
	if palette != null:
		slot = (palette.materials as Array).find(mat)
	if slot < 0:
		slot = int(root.add_material_to_palette(mat))
	added[mat] = slot
	return slot
