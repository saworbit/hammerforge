@tool
extends Node
class_name Baker

const DEFAULT_UV2_TEXEL_SIZE := 0.1
# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const HFLog = preload("hf_log.gd")
const LOD_NORMAL_MERGE_ANGLE := 25.0
const LOD_NORMAL_SPLIT_ANGLE := 60.0
const DraftBrush = preload("brush_instance.gd")
const FaceData = preload("face_data.gd")
const MaterialManager = preload("material_manager.gd")
const HFBakeSplit = preload("hf_bake_split.gd")
const HFSmoothing = preload("hf_smoothing.gd")
const HFHiddenFaces = preload("hf_hidden_faces.gd")
@warning_ignore_restore("shadowed_global_identifier")
const HFMaterialAtlasScript = preload("hf_material_atlas.gd")

## The bake option `bake_from_csg()` reads an `HFSmoothing` from, holding every
## smoothed face the boolean was handed, to put their shading back on what it
## made (#1429). Left out when no face is in a smoothing group.
const SHADING_OPTION := "smoothing"

## What the last atlas pass did, for the Console and for tests. The pass was the
## only one in the bake with no output at all: a mapper ticked Use atlas once and
## nothing anywhere distinguished "packed 6 materials into 1" from "did nothing"
## (#623).
var last_atlas_report: String = ""

## One name per collision shape on the baked body, so a game can tell metal from
## wood underfoot (#707).
##
## The index is the `shape` a hit reports, and it names the material of the
## surface that was hit. Its presence is also the signal that the shapes are
## per surface: the per-brush collision modes do not write it, because there a
## shape is a brush and a brush has six faces with six materials.
##
## `face_index` would have been the better answer and is not available. Both
## `intersect_ray()` and `RayCast3D.get_collision_face_index()` return -1 on a
## `ConcavePolygonShape3D` under Jolt, which is this project's physics engine,
## so the index that actually survives a hit is the shape.
const SURFACE_NAMES_META := "hf_surface_names"


func bake_from_csg(
	csg_node: CSGCombiner3D,
	material_override: Material = null,
	collision_layer: int = 1,
	collision_mask: int = 1,
	options: Dictionary = {}
) -> Node3D:
	if not csg_node:
		return null

	var entries = csg_node.get_meshes()
	if entries.is_empty():
		return null
	# Before anything reads the normals: the LODs simplify by them, and the UV2
	# unwrap splits its charts by them.
	var shading: Variant = options.get(SHADING_OPTION, null)
	if shading is HFSmoothing:
		entries = _reshaded_entries(entries, shading as HFSmoothing)

	var merge_meshes = bool(options.get("merge_meshes", false))
	var generate_lods = bool(options.get("generate_lods", false))
	var unwrap_uv0_flag = bool(options.get("unwrap_uv0", false))
	var unwrap_uv2 = bool(options.get("unwrap_uv2", false))
	var uv2_texel_size = float(options.get("uv2_texel_size", DEFAULT_UV2_TEXEL_SIZE))
	var use_thread_pool = bool(options.get("use_thread_pool", true))

	var result = Node3D.new()
	result.name = "BakedGeometry"

	var static_body = StaticBody3D.new()
	static_body.name = "FloorCollision"
	static_body.collision_layer = collision_layer
	static_body.collision_mask = collision_mask
	result.add_child(static_body)

	var collision_mode: int = int(options.get("collision_mode", 0))
	var convex_clean: bool = bool(options.get("convex_clean", true))
	var convex_simplify: float = float(options.get("convex_simplify", 0.0))
	# The convex modes hull the brushes, never this output (#1513). It is the
	# whole level as one mesh, so a hull of it filled every gap between brushes
	# and every cut. Whoever built the CSG knows its brushes and hands their
	# pieces over as `per_brush_verts`; without them the triangles stand in.
	var hull_verts: Array = []
	if collision_mode >= 1:
		hull_verts = _placed_like_csg_mesh(options.get("per_brush_verts", []), entries)

	if merge_meshes:
		var raw = _merge_entries(entries, use_thread_pool)
		if raw:
			# Hidden faces draw nothing and hold what they held (#1719).
			var shown := HFHiddenFaces.without_hidden(raw)
			var merged: Mesh = null
			if shown:
				merged = _postprocess_mesh(
					shown, generate_lods, unwrap_uv2, uv2_texel_size, unwrap_uv0_flag
				)
			var solid: Mesh = raw if shown != raw else merged
			if solid:
				if merged:
					var mesh_inst = MeshInstance3D.new()
					mesh_inst.name = "BakedMesh_0"
					mesh_inst.mesh = merged
					HFBakeSplit.apply(mesh_inst, options)
					if material_override:
						mesh_inst.material_override = material_override
					result.add_child(mesh_inst)
				_add_collision(
					static_body,
					solid,
					Transform3D.IDENTITY,
					hull_verts,
					collision_mode,
					convex_clean,
					convex_simplify
				)
				return result

	var mesh_count := 0
	var hulled := false
	var empty_only := false
	var held := false
	for pair in _csg_mesh_pairs(entries):
		var mesh: Mesh = pair["mesh"]
		var mesh_xform: Transform3D = pair["transform"]
		# A pass with no structural brush in it, such as Bake Selected of brush
		# entities alone, still hands back a mesh, with no surfaces. It draws nothing
		# and holds nothing, so it gets no mesh node and no collision (#1562).
		if mesh != null and mesh.get_surface_count() == 0:
			empty_only = true
			continue

		# Hidden faces draw nothing, so they are not in the mesh and get no
		# lightmap, and the collision is still taken from all of it (#1719).
		var shown := HFHiddenFaces.without_hidden(mesh)
		var processed: Mesh = null
		if shown:
			processed = _postprocess_mesh(
				shown, generate_lods, unwrap_uv2, uv2_texel_size, unwrap_uv0_flag
			)
		var solid: Mesh = mesh if shown != mesh else processed
		if not solid:
			continue

		if processed:
			var mesh_inst = MeshInstance3D.new()
			mesh_inst.name = "BakedMesh_%d" % mesh_count
			mesh_inst.mesh = processed
			HFBakeSplit.apply(mesh_inst, options)
			mesh_inst.transform = mesh_xform
			if material_override:
				mesh_inst.material_override = material_override
			result.add_child(mesh_inst)
			mesh_count += 1

		# The hulls are the whole level's, so once they are on, a later mesh
		# needs nothing more.
		if not hulled:
			hulled = _add_collision(
				static_body,
				solid,
				mesh_xform,
				hull_verts,
				collision_mode,
				convex_clean,
				convex_simplify
			)
		held = true

	if mesh_count == 0 and not held:
		if not empty_only:
			result.free()
			return null
		# Still a bake: the brush entities beside it bake into this node.
		result.remove_child(static_body)
		static_body.free()

	return result


func bake_from_faces(
	brushes: Array,
	material_manager: MaterialManager,
	material_override: Material = null,
	collision_layer: int = 1,
	collision_mask: int = 1,
	options: Dictionary = {}
) -> Node3D:
	if brushes.is_empty():
		return null
	var use_atlas: bool = bool(options.get("use_atlas", false))
	var collision_mode: int = int(options.get("collision_mode", 0))
	var snapshots: Array = []
	for brush in brushes:
		if brush is DraftBrush:
			snapshots.append(
				snapshot_brush_faces(brush, material_manager, material_override, use_atlas)
			)
	# A smoothing group runs across every brush baked here, so a curve built of
	# several brushes is one curve (#1429).
	shade_snapshots(snapshots)
	var groups: Dictionary = {}
	var per_brush_verts: Array = []
	for snapshot: Dictionary in snapshots:
		collect_snapshot_groups(snapshot, use_atlas, groups)
		if collision_mode >= 1:
			per_brush_verts.append(snapshot.get("hull_verts", PackedVector3Array()))
	if collision_mode >= 1 and not per_brush_verts.is_empty():
		options["per_brush_verts"] = per_brush_verts
	return build_mesh_from_groups(groups, collision_layer, collision_mask, options)


## An atlas rect cannot repeat, so a face whose UVs leave the unit square cannot
## be atlased. HammerForge's projection maps world units into UV space, so an
## ordinary 64-unit face is 0..64 and every group is excluded - which is correct,
## and used to be silent.
func _report_atlas_outcome(
	result: HFMaterialAtlasScript.AtlasResult, group_count: int, tiling_count: int
) -> void:
	if result and result.atlas_material:
		last_atlas_report = (
			"Atlas: packed %d of %d material groups into one atlas"
			% [result.atlased_keys.size(), group_count]
		)
		return
	if tiling_count > 0:
		last_atlas_report = (
			(
				"Atlas: skipped, %d of %d material groups have tiling UVs. Atlasing "
				+ "needs a group's UVs inside 0..1; scale the face UVs down to atlas it."
			)
			% [tiling_count, group_count]
		)
	else:
		last_atlas_report = (
			"Atlas: skipped, fewer than two of %d material groups could be packed" % group_count
		)
	HFLog.warn("Bake: %s" % last_atlas_report)


func _add_group_surface(
	combined_mesh: ArrayMesh, surface_materials: Array[Material], group: Dictionary
) -> void:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mat: Material = group.get("material", null)
	var verts: PackedVector3Array = group.get("verts", PackedVector3Array())
	var uvs: PackedVector2Array = group.get("uvs", PackedVector2Array())
	var normals: PackedVector3Array = group.get("normals", PackedVector3Array())
	for i in range(verts.size()):
		if normals.size() > i:
			st.set_normal(normals[i])
		if uvs.size() > i:
			st.set_uv(uvs[i])
		st.add_vertex(verts[i])
	# Weld the duplicated corners into an index array. Godot generates LODs off
	# the indices, so an unindexed surface comes back with none however the Bake
	# Options are set.
	st.index()
	var surface_mesh = st.commit()
	if not surface_mesh or surface_mesh.get_surface_count() == 0:
		return
	var arrays = surface_mesh.surface_get_arrays(0)
	combined_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	surface_materials.append(mat)


## Collect triangulated face geometry from a single brush into material groups.
## Call once per brush; pass the same [param groups] dictionary across all brushes
## so that faces sharing a material key are merged into a single group. A
## smoothing group is shared within the brush only; a bake that takes several
## brushes snapshots them all and hands them to `shade_snapshots()` together.
func collect_brush_face_groups(
	brush: DraftBrush,
	material_manager: MaterialManager,
	material_override: Material,
	use_atlas: bool,
	groups: Dictionary
) -> void:
	var snapshot := snapshot_brush_faces(brush, material_manager, material_override, use_atlas)
	shade_snapshots([snapshot])
	collect_snapshot_groups(snapshot, use_atlas, groups)


## Synchronously capture a brush's face geometry and resolved materials into plain
## data (PackedArrays and Materials) that is fully independent of live nodes.
## Returns a dictionary with "records" (per-face tri results), "basis", and "origin".
func snapshot_brush_faces(
	brush: DraftBrush,
	material_manager: MaterialManager,
	material_override: Material,
	use_atlas: bool
) -> Dictionary:
	var faces: Array = brush.get_faces()
	var records: Array = []
	var brush_material: Material = brush.material_override
	for face in faces:
		if face == null:
			continue
		face.ensure_geometry()
		var tri = face.triangulate()
		var verts: PackedVector3Array = tri.get("verts", PackedVector3Array())
		var uvs: PackedVector2Array = tri.get("uvs", PackedVector2Array())
		if verts.is_empty():
			continue
		var mat = _resolve_face_material(face, material_manager, brush_material, material_override)
		var face_tiles: bool = use_atlas and HFMaterialAtlasScript.group_has_tiling_uvs(uvs)
		var tri_normals: PackedVector3Array = tri.get("normals", PackedVector3Array())
		(
			records
			. append(
				{
					"verts": verts,
					"uvs": uvs,
					"normals": tri_normals,
					"face_normal": face.normal,
					"material": mat,
					"tiling": face_tiles,
					# What `shade_snapshots()` reads: 0 for a face that shades flat.
					"smoothing_group": face.smoothing_group if HFSmoothing.smooths(face) else 0,
					"corners": face.local_verts.duplicate(),
				}
			)
		)
	# Collect all unique world-space vertices for convex hull collision
	var basis: Basis = brush.global_transform.basis
	var origin: Vector3 = brush.global_transform.origin
	var hull_verts := PackedVector3Array()
	for rec in records:
		var verts: PackedVector3Array = rec["verts"]
		for v in verts:
			hull_verts.append(origin + basis * v)
	return {
		"records": records,
		"basis": basis,
		"origin": origin,
		"hull_verts": hull_verts,
	}


## Give every face in `snapshots` that is in a smoothing group the normals it
## shades with (#1429), shared with the faces of its group it meets in any of
## them: `world_normals` on its record, one per triangle corner, in the level, as
## `collect_snapshot_groups()` writes them. A face shares only with faces handed
## over in the same call, so a bake hands over every brush it takes at once.
## Plain data in and out, so it runs before the yields with the snapshots.
static func shade_snapshots(snapshots: Array) -> void:
	var shading := HFSmoothing.new()
	var shaded: Array = []
	for snapshot: Dictionary in snapshots:
		var basis: Basis = snapshot.get("basis", Basis.IDENTITY)
		var origin: Vector3 = snapshot.get("origin", Vector3.ZERO)
		var place := Transform3D(basis, origin)
		var to_normal := FaceData.normal_basis(basis)
		for record: Dictionary in snapshot.get("records", []):
			var group := int(record.get("smoothing_group", 0))
			if group <= 0:
				continue
			var corners: PackedVector3Array = record["corners"]
			var normal: Vector3 = to_normal * (record["face_normal"] as Vector3)
			shaded.append([record, shading.add(place * corners, normal, group)])
	for entry: Array in shaded:
		var record: Dictionary = entry[0]
		record["world_normals"] = HFSmoothing.fan(shading.corner_normals(entry[1]))


## Append pre-snapshotted face records (from [method snapshot_brush_faces]) into
## material groups.  Performs only world-space transforms and array appends — no
## live node or FaceData access, safe to call between frame yields.
func collect_snapshot_groups(snapshot: Dictionary, _use_atlas: bool, groups: Dictionary) -> void:
	var records: Array = snapshot.get("records", [])
	var basis: Basis = snapshot.get("basis", Basis.IDENTITY)
	var origin: Vector3 = snapshot.get("origin", Vector3.ZERO)
	for rec in records:
		var mat: Material = rec["material"]
		var face_tiles: bool = rec["tiling"]
		var key: Variant = "_default"
		if mat != null:
			key = mat
		if face_tiles:
			key = [key, "_tiling"]
		if not groups.has(key):
			groups[key] = {
				"material": mat,
				"verts": PackedVector3Array(),
				"uvs": PackedVector2Array(),
				"normals": PackedVector3Array(),
				"tiling": face_tiles,
			}
		var group = groups[key]
		_append_transformed_face(
			group,
			rec["verts"] as PackedVector3Array,
			rec["uvs"] as PackedVector2Array,
			rec["normals"] as PackedVector3Array,
			origin,
			basis,
			rec["face_normal"] as Vector3,
			rec.get("world_normals", PackedVector3Array()) as PackedVector3Array
		)


## Build final baked geometry (atlas pass, ArrayMesh, collision) from pre-collected
## material groups.  This is the second phase of a face-based bake — call after
## [method collect_brush_face_groups] has populated [param groups].
func build_mesh_from_groups(
	groups: Dictionary, collision_layer: int = 1, collision_mask: int = 1, options: Dictionary = {}
) -> Node3D:
	if groups.is_empty():
		return null
	# Hidden faces go into the collision and nothing else (#1719): not the mesh,
	# so not the lightmap, and not the atlas.
	var hidden_groups: Array = []
	var shown_groups: Dictionary = {}
	for key in groups:
		if HFHiddenFaces.is_hidden_material(groups[key].get("material")):
			hidden_groups.append(groups[key])
		else:
			shown_groups[key] = groups[key]
	groups = shown_groups
	var result = Node3D.new()
	result.name = "BakedGeometry"

	var static_body = StaticBody3D.new()
	static_body.name = "FaceCollision"
	static_body.collision_layer = collision_layer
	static_body.collision_mask = collision_mask
	result.add_child(static_body)

	var use_atlas: bool = bool(options.get("use_atlas", false))

	# --- Material atlasing pass ---
	var atlas_result: HFMaterialAtlasScript.AtlasResult = null
	last_atlas_report = ""
	if use_atlas and groups.size() > 1:
		var tiling_keys: Dictionary = {}
		for key in groups:
			if groups[key].get("tiling", false):
				tiling_keys[key] = true
		atlas_result = HFMaterialAtlasScript.build_atlas(groups.keys(), tiling_keys)
		if atlas_result and atlas_result.atlased_keys.size() < 2:
			atlas_result = null
		_report_atlas_outcome(atlas_result, groups.size(), tiling_keys.size())
	elif use_atlas:
		last_atlas_report = "Atlas: skipped, the level bakes to one material group"
		HFLog.warn("Bake: %s" % last_atlas_report)

	# Build one ArrayMesh with one surface per material group.
	var combined_mesh = ArrayMesh.new()
	var surface_materials: Array[Material] = []

	if atlas_result and atlas_result.atlas_material:
		var all_verts := PackedVector3Array()
		var all_uvs := PackedVector2Array()
		var all_normals := PackedVector3Array()
		for mat_key in atlas_result.atlased_keys:
			var group: Dictionary = groups[mat_key]
			var rect: Rect2 = atlas_result.rects[mat_key]
			var gv: PackedVector3Array = group.get("verts", PackedVector3Array())
			var gu: PackedVector2Array = group.get("uvs", PackedVector2Array())
			var gn: PackedVector3Array = group.get("normals", PackedVector3Array())
			for i in range(gv.size()):
				all_verts.append(gv[i])
				var uv: Vector2 = gu[i] if gu.size() > i else Vector2.ZERO
				all_uvs.append(HFMaterialAtlasScript.remap_uv(uv, rect))
				all_normals.append(gn[i] if gn.size() > i else Vector3.UP)
		if all_verts.size() > 0:
			var st = SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for i in range(all_verts.size()):
				st.set_normal(all_normals[i])
				st.set_uv(all_uvs[i])
				st.add_vertex(all_verts[i])
			st.index()
			var surface_mesh = st.commit()
			if surface_mesh and surface_mesh.get_surface_count() > 0:
				var arrays = surface_mesh.surface_get_arrays(0)
				combined_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
				surface_materials.append(atlas_result.atlas_material)
		for fb_key in atlas_result.fallback_keys:
			if not groups.has(fb_key):
				continue
			_add_group_surface(combined_mesh, surface_materials, groups[fb_key])
	else:
		for group in groups.values():
			_add_group_surface(combined_mesh, surface_materials, group)

	if combined_mesh.get_surface_count() == 0 and hidden_groups.is_empty():
		result.free()
		return null

	for i in range(surface_materials.size()):
		if surface_materials[i]:
			combined_mesh.surface_set_material(i, surface_materials[i])

	# The same finishing pass the CSG path runs. `bake_use_face_materials` is the
	# default since #491, so without this every default bake silently dropped the
	# LODs and the lightmap UV2 the Bake Options asked for.
	if combined_mesh.get_surface_count() > 0:
		combined_mesh = _postprocess_mesh(
			combined_mesh,
			bool(options.get("generate_lods", false)),
			bool(options.get("unwrap_uv2", false)),
			float(options.get("uv2_texel_size", DEFAULT_UV2_TEXEL_SIZE)),
			bool(options.get("unwrap_uv0", false))
		)
		if combined_mesh == null:
			result.free()
			return null
		var mesh_inst = MeshInstance3D.new()
		mesh_inst.name = "BakedMesh_0"
		mesh_inst.mesh = combined_mesh
		# How it casts shadows and how fine its lightmap is: the level's, or the
		# settings of the part of the bake these groups were collected for.
		HFBakeSplit.apply(mesh_inst, options)
		result.add_child(mesh_inst)

	var collision_mode: int = int(options.get("collision_mode", 0))
	var per_brush_verts: Array = options.get("per_brush_verts", [])
	var convex_clean: bool = bool(options.get("convex_clean", true))
	var convex_simplify: float = float(options.get("convex_simplify", 0.0))

	_add_collision(
		static_body,
		_with_groups(combined_mesh, hidden_groups),
		Transform3D.IDENTITY,
		per_brush_verts,
		collision_mode,
		convex_clean,
		convex_simplify
	)

	return result


## `mesh` with a surface more for each of `groups`, for a collision that holds
## the Hidden faces the mesh leaves out (#1719). `mesh` itself when there are none.
func _with_groups(mesh: ArrayMesh, groups: Array) -> ArrayMesh:
	if groups.is_empty():
		return mesh
	var out := ArrayMesh.new()
	var materials: Array[Material] = []
	for i in mesh.get_surface_count():
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(i))
		materials.append(mesh.surface_get_material(i))
	for group in groups:
		_add_group_surface(out, materials, group)
	for i in materials.size():
		if materials[i]:
			out.surface_set_material(i, materials[i])
	return out


## One baked node from the nodes the parts of one bake made, each a
## `BakedGeometry` with its meshes and one collision body (#1444, #1438). A bake
## splits its brushes by the settings a mesh carries as a whole and bakes each
## part as it baked the level, and the first part's node then takes in the rest:
## their meshes, numbered on from its own, and their collision shapes, into its
## body, each with the name of the surface it was cut from, so a hit still names
## its material (#707). A part that made nothing is skipped. Null when none made
## anything. One part comes back as it was.
static func gather_parts(parts: Array) -> Node3D:
	var made: Array = []
	for part in parts:
		if part is Node3D:
			made.append(part)
	if made.is_empty():
		return null
	var into: Node3D = made[0]
	var body := _collision_body(into)
	var mesh_count := 0
	for child in into.get_children():
		if child is MeshInstance3D:
			mesh_count += 1
	for i in range(1, made.size()):
		var part: Node3D = made[i]
		var part_body := _collision_body(part)
		for child in part.get_children():
			if child == part_body:
				continue
			part.remove_child(child)
			if child is MeshInstance3D:
				if str(child.name).begins_with("BakedMesh_"):
					child.name = "BakedMesh_%d" % mesh_count
				mesh_count += 1
			into.add_child(child, true)
		if part_body != null:
			if body == null:
				part.remove_child(part_body)
				into.add_child(part_body, true)
				body = part_body
			else:
				_move_shapes(part_body, body)
		part.free()
	return into


static func _collision_body(node: Node3D) -> StaticBody3D:
	for body_name in ["FaceCollision", "FloorCollision"]:
		var body := node.get_node_or_null(NodePath(body_name)) as StaticBody3D
		if body != null:
			return body
	return null


## Every shape of `from` onto `to`, after the shapes `to` has, and the names of
## the surfaces they were cut from after its names. A shape that is not a surface,
## a hull, keeps its place with no name, as `record_surface_identity()` leaves one.
static func _move_shapes(from: StaticBody3D, to: StaticBody3D) -> void:
	var named := from.has_meta(SURFACE_NAMES_META) or to.has_meta(SURFACE_NAMES_META)
	var first := _shape_count(to)
	var names := PackedStringArray()
	if to.has_meta(SURFACE_NAMES_META):
		names = to.get_meta(SURFACE_NAMES_META)
	names.resize(first)
	var moved := PackedStringArray()
	if from.has_meta(SURFACE_NAMES_META):
		moved = from.get_meta(SURFACE_NAMES_META)
	moved.resize(_shape_count(from))
	var index := 0
	for shape in from.get_children():
		from.remove_child(shape)
		var col := shape as CollisionShape3D
		if col != null and str(col.name).begins_with("SurfaceCollision_"):
			col.name = "SurfaceCollision_%d" % (first + index)
		if col != null and col.shape != null:
			index += 1
		to.add_child(shape, true)
	if named:
		names.append_array(moved)
		to.set_meta(SURFACE_NAMES_META, names)


## Collision for one baked mesh, the same on every bake path (#1462).
##
## Collision mode 0 is the mesh's own triangles. Modes 1 and 2 are one convex
## hull per entry of `hull_verts`, which are already in the body's space; when
## no entry is solid enough to hull, the triangles stand in. The triangles are
## always one shape per surface, so a hit can name its material (#707) whichever
## path baked the level. Only they need `xform`, which places the mesh.
##
## True when the collision is hulls, false when it is the triangles.
static func _add_collision(
	body: StaticBody3D,
	mesh: Mesh,
	xform: Transform3D,
	hull_verts: Array,
	collision_mode: int,
	convex_clean: bool,
	convex_simplify: float
) -> bool:
	if collision_mode >= 1 and not hull_verts.is_empty():
		var shapes: Array = build_convex_collision_shapes(hull_verts, convex_clean, convex_simplify)
		for shape in shapes:
			var col := CollisionShape3D.new()
			col.shape = shape
			body.add_child(col)
		if not shapes.is_empty():
			return true
	_add_per_surface_trimesh(body, mesh, xform)
	return false


## One trimesh collision shape per baked surface, rather than one for the level.
##
## This is what makes a footstep able to name what it is standing on (#707). The
## documented route was `face_index` on the hit, which resolves a concave shape
## down to a triangle. It is -1 here, from both `intersect_ray()` and
## `RayCast3D.get_collision_face_index()`, because this project runs Jolt and
## Jolt does not populate it. `shape` is populated, so the index that survives is
## the one that says which shape was hit, and giving each surface its own shape
## makes that index name a material exactly.
##
## The cost is a shape per material rather than one for the level, which is a
## dozen on a real map. Collision behaviour is unchanged: the same triangles, in
## the same places, partitioned rather than merged.
##
## A surface that produces no triangles is still given its shape, empty, so that
## a shape index keeps naming the surface with the same number.
##
## `xform` places the mesh in the body, as the CSG path's meshes need.
static func _add_per_surface_trimesh(
	body: StaticBody3D, mesh: Mesh, xform: Transform3D = Transform3D.IDENTITY
) -> void:
	var first := _shape_count(body)
	record_surface_identity(body, mesh)
	if mesh.get_surface_count() <= 1:
		var single := CollisionShape3D.new()
		single.shape = mesh.create_trimesh_shape()
		single.transform = xform
		body.add_child(single)
		return
	for i in mesh.get_surface_count():
		var surface := ArrayMesh.new()
		surface.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(i))
		var col := CollisionShape3D.new()
		col.name = "SurfaceCollision_%d" % (first + i)
		col.shape = surface.create_trimesh_shape()
		col.transform = xform
		body.add_child(col)


## Name each collision shape after the surface it was cut from (#707).
##
## Written only where a shape is a surface, which is why it is called from
## `_add_per_surface_trimesh()` rather than from the caller: the per-brush
## collision modes index shapes by brush, and a brush has six faces. A game that
## finds no names knows the body cannot answer, rather than being told the wrong
## material.
##
## The names go on after the shapes the body already has, because a body can
## take collision from more than one mesh. A shape already there that is not a
## surface, such as a hull, keeps its place with an empty name, which reads as
## unknown, rather than every later name sliding onto the wrong shape.
static func record_surface_identity(body: StaticBody3D, mesh: Mesh) -> void:
	if body == null or mesh == null:
		return
	var names := PackedStringArray()
	if body.has_meta(SURFACE_NAMES_META):
		names = body.get_meta(SURFACE_NAMES_META)
	names.resize(_shape_count(body))
	for i in mesh.get_surface_count():
		names.append(surface_label(mesh.surface_get_material(i)))
	body.set_meta(SURFACE_NAMES_META, names)


## How many shapes a hit can report on this body. A CollisionShape3D with no
## shape takes no index, so it is not counted.
static func _shape_count(body: StaticBody3D) -> int:
	var count := 0
	for child in body.get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape != null:
			count += 1
	return count


## What to call a surface, from the material it draws with.
##
## The same rule `MaterialManager.get_material_names()` uses, because a mapper
## reading a footstep table should see the name the Materials tab showed them.
static func surface_label(material: Material) -> String:
	if material == null:
		return "<none>"
	if material.resource_name != "":
		return material.resource_name
	var file := material.resource_path.get_file()
	return file if file != "" else "Material"


## Build convex collision shapes from per-brush vertex clusters.
## [param brush_verts] is an Array of PackedVector3Array, one entry per brush.
## Returns an Array of ConvexPolygonShape3D (one per brush with ≥4 verts).
static func build_convex_collision_shapes(
	brush_verts: Array, convex_clean: bool = true, convex_simplify: float = 0.0
) -> Array:
	var shapes: Array = []
	for verts in brush_verts:
		if not (verts is PackedVector3Array):
			continue
		var pva: PackedVector3Array = verts
		if pva.size() < 4:
			continue
		# Always deduplicate to count truly unique positions — this is the
		# degeneracy guard.  convex_clean controls whether the deduplicated
		# result replaces the working set sent to the shape.
		var unique := PackedVector3Array()
		var seen: Dictionary = {}
		for v in pva:
			var key := Vector3i(
				int(round(v.x * 1000.0)), int(round(v.y * 1000.0)), int(round(v.z * 1000.0))
			)
			if not seen.has(key):
				seen[key] = true
				unique.append(v)
		if unique.size() < 4:
			continue
		var working: PackedVector3Array = unique if convex_clean else pva
		# convex_simplify: reduce point count by merging nearby vertices into a
		# coarser grid.  A value of 0.0 skips simplification; higher values use
		# a proportionally larger grid cell derived from the AABB diagonal.
		if convex_simplify > 0.0 and working.size() > 4:
			var aabb := AABB(working[0], Vector3.ZERO)
			for v in working:
				aabb = aabb.expand(v)
			var cell: float = aabb.get_longest_axis_size() * convex_simplify
			if cell > 0.001:
				var simplified := PackedVector3Array()
				var grid: Dictionary = {}
				for v in working:
					var key := Vector3i(
						int(floor(v.x / cell)), int(floor(v.y / cell)), int(floor(v.z / cell))
					)
					if not grid.has(key):
						grid[key] = true
						simplified.append(v)
				if simplified.size() >= 4:
					working = simplified
		var shape := ConvexPolygonShape3D.new()
		shape.points = working
		shapes.append(shape)
	return shapes


func _resolve_face_material(
	face: FaceData, material_manager: MaterialManager, brush_material: Material, fallback: Material
) -> Material:
	return face.resolved_material(material_manager, brush_material, fallback)


## Process a private triangle mesh for a brush that keeps its own baked node.
## PrimitiveMesh cannot unwrap or carry LODs, and an ArrayMesh may still be the
## editor's live preview. Copy its surfaces before the in-place UV work.
## `options` uses generate_lods, unwrap_uv2 and unwrap_uv0 (all false by default),
## plus uv2_texel_size in metres (DEFAULT_UV2_TEXEL_SIZE). Null input returns null;
## surface materials are kept and the source mesh is left unchanged.
func postprocess_detail_mesh(mesh: Mesh, options: Dictionary) -> Mesh:
	if mesh == null:
		return null
	var copy := ArrayMesh.new()
	for i in mesh.get_surface_count():
		copy.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(i))
		copy.surface_set_material(i, mesh.surface_get_material(i))
	return _postprocess_mesh(
		copy,
		bool(options.get("generate_lods", false)),
		bool(options.get("unwrap_uv2", false)),
		float(options.get("uv2_texel_size", DEFAULT_UV2_TEXEL_SIZE)),
		bool(options.get("unwrap_uv0", false))
	)


func _postprocess_mesh(
	mesh: Mesh,
	generate_lods: bool,
	unwrap_uv2: bool,
	uv2_texel_size: float,
	unwrap_uv0: bool = false
) -> Mesh:
	if not mesh:
		return null
	var result = mesh
	if result is ArrayMesh:
		var arr_mesh := result as ArrayMesh
		if unwrap_uv0:
			arr_mesh = _unwrap_uv0(arr_mesh)
			result = arr_mesh
		if unwrap_uv2:
			# `lightmap_unwrap()` returns an Error and mutates the mesh in place, so
			# the branch that checked for a Mesh was never true and the Error went
			# into a local nobody read (#700). The unwrap itself worked, because
			# `arr_mesh` and `result` are the same object. What was missing was the
			# failure: ERR_UNAVAILABLE when the engine has no unwrapper, and
			# ERR_CANT_CREATE when it cannot lay the mesh out. Either way the bake
			# reported success, the checkbox stayed ticked, and a LightmapGI over
			# the result baked black with nothing said.
			var unwrap_err: int = arr_mesh.lightmap_unwrap(Transform3D.IDENTITY, uv2_texel_size)
			if unwrap_err != OK:
				HFLog.warn(
					(
						(
							"Bake: lightmap UV2 unwrap failed (%s), so this mesh has no UV2 and a "
							+ "LightmapGI over it will bake black."
						)
						% error_string(unwrap_err)
					)
				)
			result = arr_mesh
		if generate_lods and result is ArrayMesh:
			result = _mesh_with_lods(result as ArrayMesh)
	return result


## LOD generation lives on ImporterMesh, not ArrayMesh. Round trip through one
## and hand back the original mesh if the engine cannot build any levels.
## The angles are the values Godot uses for its own scene imports.
func _mesh_with_lods(mesh: ArrayMesh) -> ArrayMesh:
	if mesh.get_surface_count() == 0:
		return mesh
	# Both rebuilds below make a new mesh, and a new mesh has no lightmap size
	# hint. LightmapGI sizes a lightmap from it, and without it gave every mesh
	# 64 x 64 whatever the texel size (#1566).
	var hint := mesh.lightmap_size_hint
	# `generate_lods()` builds LOD *index* arrays by simplifying an indexed
	# surface. The CSG merge path hands over a triangle soup - every corner a
	# loose vertex, no indices - so the simplifier had nothing to collapse and
	# returned the surface unchanged, with no warning (#611). The face-material
	# path already indexes in `_add_group_surface()`; this is the other one.
	mesh = _indexed(mesh)
	mesh.lightmap_size_hint = hint
	var importer := ImporterMesh.from_mesh(mesh)
	if importer == null:
		HFLog.warn("Bake: could not build an ImporterMesh, skipping LOD generation")
		return mesh
	importer.generate_lods(LOD_NORMAL_MERGE_ANGLE, LOD_NORMAL_SPLIT_ANGLE, [])
	var out := importer.get_mesh()
	if out == null:
		HFLog.warn("Bake: LOD generation produced no mesh, keeping the original")
		return mesh
	out.lightmap_size_hint = hint
	return out


## Weld each unindexed surface into an indexed one, keeping its material. A
## surface that already has indices is left exactly as it is, so nothing that
## was already working goes through SurfaceTool a second time.
func _indexed(mesh: ArrayMesh) -> ArrayMesh:
	var needs_work := false
	for i in range(mesh.get_surface_count()):
		if mesh.surface_get_arrays(i)[Mesh.ARRAY_INDEX] == null:
			needs_work = true
			break
	if not needs_work:
		return mesh
	var out := ArrayMesh.new()
	for i in range(mesh.get_surface_count()):
		var material := mesh.surface_get_material(i)
		var arrays: Array = mesh.surface_get_arrays(i)
		if arrays[Mesh.ARRAY_INDEX] != null:
			out.add_surface_from_arrays(mesh.surface_get_primitive_type(i), arrays)
			if material:
				out.surface_set_material(out.get_surface_count() - 1, material)
			continue
		var st := SurfaceTool.new()
		st.create_from(mesh, i)
		st.index()
		var welded := st.commit()
		if welded == null or welded.get_surface_count() == 0:
			out.add_surface_from_arrays(mesh.surface_get_primitive_type(i), arrays)
		else:
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, welded.surface_get_arrays(0))
		if material:
			out.surface_set_material(out.get_surface_count() - 1, material)
	return out


func _unwrap_uv0(mesh: ArrayMesh) -> ArrayMesh:
	var out = ArrayMesh.new()
	for s_idx in range(mesh.get_surface_count()):
		var arrays = mesh.surface_get_arrays(s_idx)
		if arrays.is_empty():
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals = arrays[Mesh.ARRAY_NORMAL]
		if verts.is_empty():
			continue
		# Generate planar-projected UVs per vertex based on dominant normal axis,
		# on the axes a face projects with, so a wall is the right way up (#907).
		var floor_axes: Array = FaceData.projection_axes(FaceData.UVProjection.PLANAR_Y)
		var x_axes: Array = FaceData.projection_axes(FaceData.UVProjection.PLANAR_X)
		var z_axes: Array = FaceData.projection_axes(FaceData.UVProjection.PLANAR_Z)
		var new_uvs = PackedVector2Array()
		new_uvs.resize(verts.size())
		for i in range(verts.size()):
			var v: Vector3 = verts[i]
			var n: Vector3 = (
				normals[i] if normals is PackedVector3Array and normals.size() > i else Vector3.UP
			)
			var abs_n = n.abs()
			var axes: Array = z_axes
			if abs_n.y >= abs_n.x and abs_n.y >= abs_n.z:
				axes = floor_axes
			elif abs_n.x >= abs_n.z:
				axes = x_axes
			new_uvs[i] = Vector2(v.dot(axes[0]), v.dot(axes[1]))
		arrays[Mesh.ARRAY_TEX_UV] = new_uvs
		var primitive = mesh.surface_get_primitive_type(s_idx)
		out.add_surface_from_arrays(primitive, arrays)
		var mat: Material = mesh.surface_get_material(s_idx)
		if mat:
			out.surface_set_material(out.get_surface_count() - 1, mat)
	return out


static func _append_transformed_face(
	group: Dictionary,
	verts: PackedVector3Array,
	uvs: PackedVector2Array,
	tri_normals: PackedVector3Array,
	origin: Vector3,
	basis: Basis,
	fallback_normal: Vector3,
	world_normals: PackedVector3Array = PackedVector3Array()
) -> void:
	var count := verts.size()
	if count <= 0:
		return
	var dest_verts: PackedVector3Array = group["verts"]
	var dest_uvs: PackedVector2Array = group["uvs"]
	var dest_normals: PackedVector3Array = group["normals"]
	var start := dest_verts.size()
	dest_verts.resize(start + count)
	dest_uvs.resize(start + count)
	dest_normals.resize(start + count)
	# A stretched ramp baked lit as though it faced elsewhere (#884).
	var to_normal := FaceData.normal_basis(basis)
	var fallback := (to_normal * fallback_normal).normalized()
	for i in range(count):
		dest_verts[start + i] = origin + basis * verts[i]
		dest_uvs[start + i] = uvs[i] if uvs.size() > i else Vector2.ZERO
		# A smoothed face's normals are worked out in the level already (#1429).
		if world_normals.size() > i:
			dest_normals[start + i] = world_normals[i]
		elif tri_normals.size() > i:
			dest_normals[start + i] = (to_normal * tri_normals[i]).normalized()
		else:
			dest_normals[start + i] = fallback
	group["verts"] = dest_verts
	group["uvs"] = dest_uvs
	group["normals"] = dest_normals


func _merge_entries(entries: Array, use_thread_pool: bool) -> ArrayMesh:
	var mesh_entries = _collect_mesh_entries(entries)
	if mesh_entries.is_empty():
		return null
	var payloads: Array = _extract_surface_payloads(mesh_entries)
	if payloads.is_empty():
		return null
	var grouped: Array = []
	if use_thread_pool:
		var bucket: Array = []
		var task_id: int = WorkerThreadPool.add_task(
			func() -> void: bucket.append(_group_surface_payloads(payloads))
		)
		WorkerThreadPool.wait_for_task_completion(task_id)
		if not bucket.is_empty():
			grouped = bucket[0]
	else:
		grouped = _group_surface_payloads(payloads)
	return _assemble_merged_mesh(grouped)


## The pieces handed to `bake_from_csg()` for hulls, moved to where its mesh goes.
##
## They come in the CSG node's own space, which is the space its mesh comes out
## in, so they take the placement the mesh takes. Godot 4.7 hands back an
## identity there, and this keeps the hulls on the mesh if that ever changes.
static func _placed_like_csg_mesh(hull_verts: Array, entries: Array) -> Array:
	var pairs := _csg_mesh_pairs(entries)
	if pairs.is_empty():
		return hull_verts
	var xform: Transform3D = pairs[0]["transform"]
	if xform == Transform3D.IDENTITY:
		return hull_verts
	var placed: Array = []
	for verts in hull_verts:
		if verts is PackedVector3Array:
			placed.append(xform * (verts as PackedVector3Array))
	return placed


## What `CSGShape3D.get_meshes()` handed back, as mesh-and-placement pairs.
##
## Godot 4 returns a flat two-element array: the node's `Transform3D` first, then
## its root `Mesh`. It is not a list of meshes and not a list of pairs. Walking it
## as a list still finds the mesh, because the second element is one, and throws
## the transform away, because the first element is not a mesh and nothing else
## looks at it. A CSG node standing anywhere but the origin therefore baked its
## visual mesh and its convex collision at the origin.
##
## The flat pair is read first. The per-entry walk stays behind it for a list of
## meshes or of pairs, in either order, so a build that returns one is read rather
## than quietly mishandled. `HFSubtractPreview.extract_csg_meshes()` already had
## this shape; the baker had three copies of the version without it.
func _collect_mesh_entries(entries: Array) -> Array:
	return _csg_mesh_pairs(entries)


## What the CSG handed back with each mesh shaded as its smoothed faces shade
## (#1429), as a list of `[Transform3D, Mesh]` pairs, which `_csg_mesh_pairs()` reads.
static func _reshaded_entries(entries: Array, shading: HFSmoothing) -> Array:
	var out: Array = []
	for pair in _csg_mesh_pairs(entries):
		out.append([pair["transform"], shading.reshade(pair["mesh"])])
	return out


static func _csg_mesh_pairs(entries: Array) -> Array:
	var list: Array = []
	if entries.is_empty():
		return list
	if entries.size() >= 2 and entries[0] is Transform3D and entries[1] is Mesh:
		list.append({"mesh": entries[1], "transform": entries[0]})
		return list
	for entry in entries:
		var mesh: Mesh = null
		var mesh_xform := Transform3D.IDENTITY
		if entry is Mesh:
			mesh = entry
		elif entry is Array:
			if entry.size() > 0 and entry[0] is Transform3D:
				mesh_xform = entry[0]
			if entry.size() > 1 and entry[1] is Mesh:
				mesh = entry[1]
			elif entry.size() > 0 and entry[0] is Mesh:
				mesh = entry[0]
			if entry.size() > 1 and entry[1] is Transform3D:
				mesh_xform = entry[1]
		if mesh:
			list.append({"mesh": mesh, "transform": mesh_xform})
	return list


func _merge_entries_worker(mesh_entries: Array) -> ArrayMesh:
	return _assemble_merged_mesh(_group_surface_payloads(_extract_surface_payloads(mesh_entries)))


func _extract_surface_payloads(mesh_entries: Array) -> Array:
	var payloads: Array = []
	for entry in mesh_entries:
		var mesh: Mesh = entry.get("mesh", null)
		var xform: Transform3D = entry.get("transform", Transform3D.IDENTITY)
		if not mesh:
			continue
		for surface in range(mesh.get_surface_count()):
			var arrays = mesh.surface_get_arrays(surface)
			if arrays.is_empty():
				continue
			(
				payloads
				. append(
					{
						"arrays": arrays,
						"transform": xform,
						"material": mesh.surface_get_material(surface),
					}
				)
			)
	return payloads


func _group_surface_payloads(payloads: Array) -> Array:
	var mat_groups: Dictionary = {}
	for payload in payloads:
		var arrays: Array = payload.get("arrays", [])
		if arrays.is_empty():
			continue
		var xform: Transform3D = payload.get("transform", Transform3D.IDENTITY)
		var mat: Material = payload.get("material", null)
		var key: Variant = "_default"
		if mat != null:
			key = mat
		if not mat_groups.has(key):
			mat_groups[key] = {"material": mat, "arrays_list": []}
		mat_groups[key]["arrays_list"].append(_transform_arrays(arrays, xform))
	var grouped: Array = []
	for group in mat_groups.values():
		grouped.append(group)
	return grouped


func _assemble_merged_mesh(grouped: Array) -> ArrayMesh:
	if grouped.is_empty():
		return null
	var merged = ArrayMesh.new()
	for group in grouped:
		var combined = _concat_surface_arrays(group.get("arrays_list", []))
		if combined.is_empty():
			continue
		merged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, combined)
		var mat: Material = group.get("material", null)
		if mat:
			merged.surface_set_material(merged.get_surface_count() - 1, mat)
	return merged if merged.get_surface_count() > 0 else null


func _concat_surface_arrays(arrays_list: Array) -> Array:
	if arrays_list.is_empty():
		return []
	if arrays_list.size() == 1:
		return arrays_list[0]

	var out: Array = []
	out.resize(Mesh.ARRAY_MAX)
	# Initialize from the first entry — packed arrays are value types in Variant
	# containers, so we must duplicate to get a mutable copy.
	var first: Array = arrays_list[0]
	for i in range(Mesh.ARRAY_MAX):
		if first[i] == null:
			continue
		out[i] = _dup_packed(first[i])

	# Append subsequent entries. Packed arrays in a Variant Array are copied on
	# access, so we must extract → append → reassign to actually mutate.
	# IMPORTANT: ARRAY_INDEX values must be rebased by the current vertex count
	# so that indices in later surfaces point at the correct merged vertices.
	# When mixing indexed and non-indexed surfaces, synthesize sequential indices
	# for the non-indexed portion so the merge produces valid indexed geometry.
	for list_idx in range(1, arrays_list.size()):
		var src: Array = arrays_list[list_idx]
		# Track current vertex count before appending (for index rebasing)
		var vert_count := 0
		if out[Mesh.ARRAY_VERTEX] is PackedVector3Array:
			vert_count = (out[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		# Handle ARRAY_INDEX separately due to rebasing + mixed indexed/non-indexed
		var idx_channel: int = Mesh.ARRAY_INDEX
		var out_has_idx: bool = out[idx_channel] is PackedInt32Array
		var src_has_idx: bool = src[idx_channel] is PackedInt32Array
		if out_has_idx or src_has_idx:
			# Ensure out has an index buffer; if first surface was non-indexed,
			# synthesize sequential indices [0, 1, 2, ...] for its vertices.
			if not out_has_idx:
				var synth := PackedInt32Array()
				synth.resize(vert_count)
				for vi in range(vert_count):
					synth[vi] = vi
				out[idx_channel] = synth
			# Get src indices — synthesize if this surface is non-indexed
			var src_indices: PackedInt32Array
			if src_has_idx:
				src_indices = PackedInt32Array(src[idx_channel] as PackedInt32Array)
			else:
				var src_vert_count := 0
				if src[Mesh.ARRAY_VERTEX] is PackedVector3Array:
					src_vert_count = (src[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
				src_indices = PackedInt32Array()
				src_indices.resize(src_vert_count)
				for vi in range(src_vert_count):
					src_indices[vi] = vi
			# Rebase src indices by current vertex count
			if vert_count > 0:
				for vi in range(src_indices.size()):
					src_indices[vi] += vert_count
			out[idx_channel] = _append_packed(out[idx_channel], src_indices)
		# Append all other channels normally
		for i in range(Mesh.ARRAY_MAX):
			if i == idx_channel:
				continue
			if src[i] == null or out[i] == null:
				continue
			out[i] = _append_packed(out[i], src[i])
	return out


static func _dup_packed(v: Variant) -> Variant:
	if v is PackedVector3Array:
		return PackedVector3Array(v)
	if v is PackedVector2Array:
		return PackedVector2Array(v)
	if v is PackedFloat32Array:
		return PackedFloat32Array(v)
	if v is PackedInt32Array:
		return PackedInt32Array(v)
	if v is PackedColorArray:
		return PackedColorArray(v)
	return v


static func _append_packed(dst: Variant, src: Variant) -> Variant:
	if dst is PackedVector3Array and src is PackedVector3Array:
		var arr: PackedVector3Array = dst
		arr.append_array(src)
		return arr
	if dst is PackedVector2Array and src is PackedVector2Array:
		var arr: PackedVector2Array = dst
		arr.append_array(src)
		return arr
	if dst is PackedFloat32Array and src is PackedFloat32Array:
		var arr: PackedFloat32Array = dst
		arr.append_array(src)
		return arr
	if dst is PackedInt32Array and src is PackedInt32Array:
		var arr: PackedInt32Array = dst
		arr.append_array(src)
		return arr
	if dst is PackedColorArray and src is PackedColorArray:
		var arr: PackedColorArray = dst
		arr.append_array(src)
		return arr
	return dst


func _transform_arrays(arrays: Array, xform: Transform3D) -> Array:
	var out: Array = []
	out.resize(Mesh.ARRAY_MAX)
	for i in range(arrays.size()):
		out[i] = arrays[i]
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if verts.size() > 0:
		var new_verts = PackedVector3Array()
		new_verts.resize(verts.size())
		for i in range(verts.size()):
			new_verts[i] = xform * verts[i]
		out[Mesh.ARRAY_VERTEX] = new_verts
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	if normals.size() > 0:
		var new_normals = PackedVector3Array()
		new_normals.resize(normals.size())
		var to_normal := FaceData.normal_basis(xform.basis)
		for i in range(normals.size()):
			new_normals[i] = (to_normal * normals[i]).normalized()
		out[Mesh.ARRAY_NORMAL] = new_normals
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
	if tangents.size() > 0:
		var new_tangents = PackedFloat32Array()
		new_tangents.resize(tangents.size())
		var basis_t = xform.basis
		for i in range(0, tangents.size(), 4):
			var t = Vector3(tangents[i], tangents[i + 1], tangents[i + 2])
			t = (basis_t * t).normalized()
			new_tangents[i] = t.x
			new_tangents[i + 1] = t.y
			new_tangents[i + 2] = t.z
			new_tangents[i + 3] = tangents[i + 3]
		out[Mesh.ARRAY_TANGENT] = new_tangents
	return out
