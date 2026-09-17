@tool
extends Resource
class_name FaceData

enum UVProjection { PLANAR_X, PLANAR_Y, PLANAR_Z, BOX_UV, CYLINDRICAL }

## How far a rotated projection plane may lean off a local axis and still be
## treated as that axis. Rotations arrive as exact quarter turns or as a turn
## about the projection axis itself, so anything past this is a genuine tilt.
const UV_AXIS_EPSILON := 0.0001
enum PaintBlend { OVERLAY, MULTIPLY, ADD }

## Kept as a name on `FaceData` because every call site spells it
## `FaceData.PaintLayer`, and as a file of its own because an inner class has no
## type a `.tscn` can name: the scene wrote the layers and refused them on load,
## so a painted face reopened unpainted (#665). See `hf_face_paint_layer.gd`.
const PaintLayer = preload("res://addons/hammerforge/paint/hf_face_paint_layer.gd")

@export var material_idx: int = -1
## The texture this face was named in the `.map` it came from.
##
## In this lineage the texture name *is* the surface's behaviour -- `AAATRIGGER`
## is a trigger volume, `*water1` is water, `sky1` is sky -- so dropping it drops
## the classification, not just the decoration. The importer parsed the name and
## nothing stored it, and the exporter wrote `__default` on all sixty faces of a
## ten brush map (#662). Kept whether or not the palette has a slot for it, so a
## round trip is lossless with no materials loaded at all.
@export var map_texture: String = ""
## PLANAR_Z maps (x, y) -> (u, v), so on a face whose plane contains the Z axis,
## or one lying flat in Y, one UV axis is constant across the whole face and every
## point on it samples the same line of the texture: four of a box's six faces.
## BOX_UV resolves to the dominant normal axis per face, which is the answer the
## dock's "Apply + Re-project (Box UV)" button already applies by hand.
## `_transfer_face_data()` carries this across a rebuild, so a saved level keeps
## whatever it was saved with.
@export var uv_projection: int = UVProjection.BOX_UV
@export var uv_scale: Vector2 = Vector2.ONE
@export var uv_offset: Vector2 = Vector2.ZERO
@export var uv_rotation: float = 0.0
@export var custom_uvs: PackedVector2Array = PackedVector2Array()
@export var paint_layers: Array[PaintLayer] = []
@export var bounds: AABB = AABB()
@export var local_verts: PackedVector3Array = PackedVector3Array()
## Where this face's brush sits in the level, so a planar projection can be taken
## in world space rather than in the brush's own space.
##
## Two brushes of the same size used to get identical UVs wherever they were, so
## a wall built out of three panels was three copies of the same patch of texture
## with a hard restart at every seam -- and building a surface out of several
## brushes is the fundamental move in this style of editor (#652). Every other
## editor in this lineage projects from world space for that reason, and the
## `.map` formats already mean it: `hf_map_valve220.gd` writes world texture axes.
##
## Not persisted. It is the brush's transform, kept in step by `DraftBrush`, and
## a face that has never been told is at the origin -- which is what a face with
## no brush (a test, a raw `from_dict`) should assume.
var world_transform: Transform3D = Transform3D.IDENTITY
## The `uv_format_version` this face was loaded from, so a brush that has just
## been given its transform can migrate offsets tuned against the old projection.
## Back to -1 once the brush has done it, and -1 for a face that was built
## rather than loaded.
var pending_uv_migration: int = -1
## The brush orientation these UVs were laid out against, so a face that swings
## onto a different Box UV axis can keep the handedness it had (#684).
##
## Not persisted, and not a default anyone should read as meaningful: the first
## time a brush tells a face where it is, whatever it says is the layout. That
## is what makes a saved level safe -- it reopens with the orientation it was
## saved at, so nothing is reconciled and nothing moves.
var _uv_layout_basis: Basis = Basis.IDENTITY
var _uv_layout_known: bool = false
@export var normal: Vector3 = Vector3.UP

## Optional displacement data. When non-null the face is a displacement surface
## and triangulate() produces a subdivided grid mesh instead of a flat fan.
var displacement: Resource = null  # HFDisplacementData (avoid preload cycle)

## Memoised result of `get_painted_albedo()`, keyed by the paint inputs.
##
## Every `rebuild_preview()` (27 call sites, including one per surface-paint
## sample) recomposites every painted face of the brush, even the faces that did
## not change. Building the key hashes each weight image, which on Godot 4.7
## measures 0.077 ms for 256x256 against 61.7 ms for the composite itself — see
## `tools/benchmark_paint_hot_paths.gd`.
##
## The cost is one retained image per painted face, sized like that face's weight
## image (256x256 by default). Faces with no paint layers cache nothing.
var _albedo_cache: Image = null
var _albedo_cache_key: String = ""


func ensure_geometry() -> void:
	_compute_normal()
	_compute_bounds()


func ensure_custom_uvs() -> void:
	if custom_uvs.size() == local_verts.size():
		return
	custom_uvs = _project_uvs_for_vertices(local_verts)


func adjust_uvs_for_transform(pos_delta: Vector3, size_ratio: Vector3) -> void:
	var projection = uv_projection
	if projection == UVProjection.BOX_UV:
		# `pos_delta` is a move through the level, so the axis is the one the
		# projection is using there.
		projection = _box_projection_axis_in(world_transform)
	if projection == UVProjection.CYLINDRICAL:
		return
	var offset_delta = Vector2.ZERO
	var inv_size = Vector2.ONE
	match projection:
		UVProjection.PLANAR_X:
			offset_delta = Vector2(pos_delta.z, pos_delta.y)
			if size_ratio.z > 0.001 and size_ratio.y > 0.001:
				inv_size = Vector2(1.0 / size_ratio.z, 1.0 / size_ratio.y)
		UVProjection.PLANAR_Y:
			offset_delta = Vector2(pos_delta.x, pos_delta.z)
			if size_ratio.x > 0.001 and size_ratio.z > 0.001:
				inv_size = Vector2(1.0 / size_ratio.x, 1.0 / size_ratio.z)
		UVProjection.PLANAR_Z:
			offset_delta = Vector2(pos_delta.x, pos_delta.y)
			if size_ratio.x > 0.001 and size_ratio.y > 0.001:
				inv_size = Vector2(1.0 / size_ratio.x, 1.0 / size_ratio.y)
	# Rotation is applied before scale and offset in _apply_uv_transform, so the
	# projected move has to be rotated the same way before it is subtracted.
	var rotated_delta: Vector2 = offset_delta
	if uv_rotation != 0.0:
		rotated_delta = offset_delta.rotated(uv_rotation)
	uv_offset -= rotated_delta * uv_scale
	if not inv_size.is_equal_approx(Vector2.ONE):
		uv_scale *= inv_size


## Whether an integer names one of this enum's projections.
##
## `uv_projection` is a bare `int`, and the projector falls through its `match`
## to the `(x, y)` branch for anything else — so an out of range value is stored,
## saved, reloaded and exported as a projection nobody chose and no dock control
## can show.
static func is_valid_projection(projection: int) -> bool:
	return projection >= 0 and projection <= UVProjection.CYLINDRICAL


## The two local directions a planar projection reads, in (u, v) order.
##
## These are the axes `_project_uvs_for_vertices()` samples, written out so the
## texture-lock maths can work with the projection rather than guess at it.
## Note the handedness is not the same for all three: PLANAR_Z reads (x, y) and
## PLANAR_Y reads (x, z), so a turn about Y moves U the opposite way round to a
## turn about Z. That is the sign that used to be assumed.
static func projection_axes(projection: int) -> Array:
	match projection:
		UVProjection.PLANAR_X:
			return [Vector3.BACK, Vector3.UP]
		UVProjection.PLANAR_Y:
			return [Vector3.RIGHT, Vector3.BACK]
		_:
			return [Vector3.RIGHT, Vector3.UP]


## Keep this face's texture on the brush while the brush turns.
##
## `local_rot` is the brush's rotation expressed in the brush's own space: a
## local point `v` ends up where `local_rot * v` used to be. Since #652 the
## projection is taken in the level, so a turn already moves the projection
## across the face and doing nothing leaves the texture where it was in the
## world. Carrying it round with the brush is the thing that needs saying, and
## it is said by reading the projection at `local_rot.inverse() * v` -- the turn
## cancelled rather than counted twice.
##
## That is the same reading as texture lock on a move, which holds the texture on
## a brush that slides. Before #652 it was the other way round, because a
## projection from a brush's own vertices did not move when the brush did, so the
## compensation was what unstuck the texture. Turn texture lock off and the
## texture stays where it is in the level, which is a projection from the level
## doing nothing at all.
##
## That only stays a projection of the same kind when the turn keeps the
## projection plane where it is — a turn about the projection axis, at any angle.
## Then the whole difference is a turn inside the UV plane, which `uv_rotation`
## can hold. A turn about any other axis swings the face out from under its own
## projection, and nothing the stored fields can say expresses that, so the face
## is left alone and its texture travels with the brush rather than being tipped
## on its side.
##
## Returns true if the UVs were adjusted.
func adjust_uvs_for_rotation(local_rot: Basis) -> bool:
	if uv_projection == UVProjection.CYLINDRICAL:
		return false
	var effective := uv_projection
	if effective == UVProjection.BOX_UV:
		effective = _box_projection_axis()
	var axes: Array = projection_axes(effective)
	# The composed map reads the old projection axes pushed through the turn, so
	# these two vectors span the plane the projection would have to be.
	var f_u: Vector3 = local_rot * (axes[0] as Vector3)
	var f_v: Vector3 = local_rot * (axes[1] as Vector3)
	var kept: Vector3 = (axes[0] as Vector3).cross(axes[1] as Vector3)
	if absf(f_u.cross(f_v).dot(kept)) < 1.0 - UV_AXIS_EPSILON:
		return false
	# The change of basis from the projection's own axes to the pulled-back ones.
	# It is orthogonal, so it is a turn in the UV plane, possibly mirrored.
	var a00 := f_u.dot(axes[0])
	var a01 := f_u.dot(axes[1])
	var a10 := f_v.dot(axes[0])
	var a11 := f_v.dot(axes[1])
	var turn := atan2(a10, a00)
	if a00 * a11 - a01 * a10 >= 0.0:
		uv_rotation = wrapf(uv_rotation + turn, -PI, PI)
	else:
		# The turn put the plane back the other way up. `diag(sx, sy) * rot(r) *
		# diag(1, -1)` is the same map as `diag(sx, -sy) * rot(-r)`, which the
		# stored fields can hold, so the flip folds into the V scale.
		uv_rotation = wrapf(-(uv_rotation + turn), -PI, PI)
		uv_scale.y = -uv_scale.y
	custom_uvs = PackedVector2Array()
	return true


func triangulate() -> Dictionary:
	var tri_verts := PackedVector3Array()
	var tri_uvs := PackedVector2Array()
	var count = local_verts.size()
	if count < 3:
		return {"verts": tri_verts, "uvs": tri_uvs}
	var source_uvs = custom_uvs
	if source_uvs.size() != count:
		source_uvs = _project_uvs_for_vertices(local_verts)
	# Displacement path: delegate to HFDisplacementData for subdivided mesh.
	if displacement != null and count == 4:
		var corners: Array[Vector3] = [
			local_verts[0], local_verts[1], local_verts[3], local_verts[2]
		]
		var uv_corners: Array[Vector2] = [
			source_uvs[0], source_uvs[1], source_uvs[3], source_uvs[2]
		]
		var result: Dictionary = displacement.triangulate_displaced(corners, normal, uv_corners)
		return {
			"verts": result.get("verts", tri_verts),
			"uvs": result.get("uvs", tri_uvs),
			"normals": result.get("normals", PackedVector3Array())
		}
	for i in range(1, count - 1):
		tri_verts.append(local_verts[0])
		tri_verts.append(local_verts[i])
		tri_verts.append(local_verts[i + 1])
		tri_uvs.append(source_uvs[0])
		tri_uvs.append(source_uvs[i])
		tri_uvs.append(source_uvs[i + 1])
	return {"verts": tri_verts, "uvs": tri_uvs}


## Composites the face's paint layers into a single albedo image.
##
## The returned image is cached and shared — treat it as read-only. Both callers
## (`Baker` and `BrushInstance`) hand it to `ImageTexture.create_from_image()`,
## which copies.
func get_painted_albedo(max_size: int = 512) -> Image:
	var layers: Array = paint_layers
	if layers.is_empty():
		_invalidate_albedo_cache()
		return null
	if _albedo_cache != null and _albedo_cache_key_for(max_size) == _albedo_cache_key:
		return _albedo_cache
	var target_w = 0
	var target_h = 0
	for layer in layers:
		if layer == null:
			continue
		if layer.weight_image:
			target_w = max(target_w, layer.weight_image.get_width())
			target_h = max(target_h, layer.weight_image.get_height())
		elif layer.texture and layer.texture is Texture2D:
			var img = layer.texture.get_image()
			target_w = max(target_w, img.get_width())
			target_h = max(target_h, img.get_height())
	if target_w <= 0 or target_h <= 0:
		_invalidate_albedo_cache()
		return null
	if max_size > 0:
		var scale = min(1.0, float(max_size) / float(max(target_w, target_h)))
		target_w = max(1, int(round(target_w * scale)))
		target_h = max(1, int(round(target_h * scale)))
	var out = Image.create(target_w, target_h, false, Image.FORMAT_RGBA8)
	out.fill(Color(1, 1, 1, 1))
	var tex_cache: Dictionary = {}
	for layer in layers:
		if layer == null or layer.opacity <= 0.0:
			continue
		if not layer.texture or not layer.texture is Texture2D:
			continue
		var tex_key = layer.texture.resource_path
		var tex_img: Image
		if tex_key != "" and tex_cache.has(tex_key):
			tex_img = tex_cache[tex_key]
		else:
			var source_img = layer.texture.get_image()
			if source_img == null or source_img.is_empty():
				continue
			# Always copy: get_image() can hand back the texture's live image, and a
			# compressed format has to be expanded before get_pixel() can read it.
			tex_img = source_img.duplicate() as Image
			if tex_img.is_compressed():
				if tex_img.decompress() != OK:
					continue
			if tex_img.get_width() != target_w or tex_img.get_height() != target_h:
				tex_img.resize(target_w, target_h, Image.INTERPOLATE_LANCZOS)
			if tex_key != "":
				tex_cache[tex_key] = tex_img
		var paint_img = layer.weight_image
		if paint_img == null or paint_img.is_empty():
			layer.ensure_weight_image(Vector2i(target_w, target_h))
			paint_img = layer.weight_image
		if paint_img.get_width() != target_w or paint_img.get_height() != target_h:
			paint_img = paint_img.duplicate() as Image
			paint_img.resize(target_w, target_h, Image.INTERPOLATE_LANCZOS)
		for y in range(target_h):
			for x in range(target_w):
				var w = clamp(paint_img.get_pixel(x, y).r * layer.opacity, 0.0, 1.0)
				if w <= 0.0:
					continue
				var base = out.get_pixel(x, y)
				var tex = tex_img.get_pixel(x, y)
				var blended = _blend_color(base, tex, w, layer.blend_mode)
				out.set_pixel(x, y, blended)
	_albedo_cache = out
	# Re-key rather than reusing cache_key: the loop above can call
	# ensure_weight_image() on a texture-only layer, which changes the signature.
	_albedo_cache_key = _albedo_cache_key_for(max_size)
	return out


## Drops the memoised composite. Call after mutating paint layers outside
## `get_painted_albedo()`; the key covers the ordinary edits already.
func invalidate_painted_albedo() -> void:
	_invalidate_albedo_cache()


func _invalidate_albedo_cache() -> void:
	_albedo_cache = null
	_albedo_cache_key = ""


## Builds a signature for the current paint inputs.
##
## Weight images are hashed by content, so any paint stroke misses the cache.
## Textures are identified by resource path (falling back to instance id) and
## size rather than content: palette textures are immutable resources, and
## swapping one assigns a different texture instance. A texture edited in place
## under the same path is the gap here — call `invalidate_painted_albedo()`.
func _albedo_cache_key_for(max_size: int) -> String:
	var parts: PackedStringArray = [str(max_size), str(paint_layers.size())]
	for layer in paint_layers:
		if layer == null:
			parts.append("-")
			continue
		var tex_id := "none"
		if layer.texture:
			tex_id = layer.texture.resource_path
			if tex_id == "":
				tex_id = "id%d" % layer.texture.get_instance_id()
			tex_id += "@%s" % layer.texture.get_size()
		var weight_id := "none"
		if layer.weight_image and not layer.weight_image.is_empty():
			weight_id = (
				"%dx%d#%d"
				% [
					layer.weight_image.get_width(),
					layer.weight_image.get_height(),
					hash(layer.weight_image.get_data())
				]
			)
		parts.append("%s|%s|%d|%.4f" % [tex_id, weight_id, layer.blend_mode, layer.opacity])
	return "\n".join(parts)


func to_dict() -> Dictionary:
	var layer_data: Array = []
	for layer in paint_layers:
		if layer == null:
			continue
		var entry: Dictionary = {
			"texture_path": layer.texture.resource_path if layer.texture else "",
			"blend_mode": layer.blend_mode,
			"opacity": layer.opacity
		}
		if layer.weight_image and not layer.weight_image.is_empty():
			var png_bytes = layer.weight_image.save_png_to_buffer()
			entry["weight_png"] = Marshalls.raw_to_base64(png_bytes)
			entry["weight_w"] = layer.weight_image.get_width()
			entry["weight_h"] = layer.weight_image.get_height()
		layer_data.append(entry)
	return {
		"material_idx": material_idx,
		"map_texture": map_texture,
		"uv_projection": uv_projection,
		"uv_scale": _encode_vec2(uv_scale),
		"uv_offset": _encode_vec2(uv_offset),
		"uv_rotation": uv_rotation,
		"uv_format_version": 2,
		"winding_version": 3,
		"custom_uvs": _encode_vec2_array(custom_uvs),
		"local_verts": _encode_vec3_array(local_verts),
		"normal": _encode_vec3(normal),
		"paint_layers": layer_data,
		"displacement": displacement.to_dict() if displacement != null else null
	}


static func from_dict(data: Dictionary) -> FaceData:
	var face = FaceData.new()
	face.material_idx = int(data.get("material_idx", -1))
	face.map_texture = str(data.get("map_texture", ""))
	var stored_projection := int(data.get("uv_projection", UVProjection.PLANAR_Z))
	if not is_valid_projection(stored_projection):
		# An older or newer file, or a hand edit. The enum has to mean something.
		stored_projection = UVProjection.PLANAR_Z
	face.uv_projection = stored_projection
	face.uv_scale = _decode_vec2(data.get("uv_scale", null), Vector2.ONE)
	face.uv_offset = _decode_vec2(data.get("uv_offset", null), Vector2.ZERO)
	face.uv_rotation = float(data.get("uv_rotation", 0.0))
	face.custom_uvs = _decode_vec2_array(data.get("custom_uvs", []))
	face.local_verts = _decode_vec3_array(data.get("local_verts", []))
	face.normal = _decode_vec3(data.get("normal", null), Vector3.UP)
	face.paint_layers.clear()
	var layers: Array = data.get("paint_layers", [])
	for entry in layers:
		if not (entry is Dictionary):
			continue
		var layer = PaintLayer.new()
		var texture_path = str(entry.get("texture_path", ""))
		if texture_path != "" and ResourceLoader.exists(texture_path):
			var tex = ResourceLoader.load(texture_path)
			if tex is Texture2D:
				layer.texture = tex
		layer.blend_mode = int(entry.get("blend_mode", PaintBlend.OVERLAY))
		layer.opacity = float(entry.get("opacity", 1.0))
		var b64 = str(entry.get("weight_png", ""))
		if b64 != "":
			var raw = Marshalls.base64_to_raw(b64)
			if raw.size() > 0:
				var img = Image.new()
				if img.load_png_from_buffer(raw) == OK:
					layer.weight_image = img
		if layer.weight_image == null or layer.weight_image.is_empty():
			var w = int(entry.get("weight_w", 256))
			var h = int(entry.get("weight_h", 256))
			layer.ensure_weight_image(Vector2i(w, h))
		face.paint_layers.append(layer)
	face.ensure_geometry()
	# Migrate v0 UV data: old order was (uv * scale + offset).rotated(R),
	# new order is uv.rotated(R) * scale + offset. Only affects faces with
	# non-zero rotation.
	var uv_fmt: int = int(data.get("uv_format_version", 0))
	# v2 moved the planar projection out of the brush's space and into the
	# level's (#652), which changes what `uv_offset` measures from. A face
	# cannot fold that in here, because it does not know where its brush is
	# until the brush tells it. Record the version and let the brush do it.
	if uv_fmt < 2:
		face.pending_uv_migration = uv_fmt
	if uv_fmt < 1 and face.uv_rotation != 0.0:
		if is_equal_approx(face.uv_scale.x, face.uv_scale.y):
			# Uniform scale: rotation commutes with scale, only offset changes.
			# Old: rotate(uv*s + O, R) = rotate(uv,R)*s + rotate(O,R)
			face.uv_offset = face.uv_offset.rotated(face.uv_rotation)
		else:
			# Non-uniform scale: can't represent with same params. Bake UVs
			# using old transform order, then clear parametric transforms.
			if face.local_verts.size() >= 3 and face.custom_uvs.size() != face.local_verts.size():
				face.custom_uvs = face._project_uvs_v0(face.local_verts)
			elif face.custom_uvs.size() == face.local_verts.size():
				# custom_uvs were already baked with old transform — re-apply
				# the old rotation that was previously baked in at save time.
				pass  # custom_uvs are already correct from the old save
			face.uv_rotation = 0.0
			face.uv_scale = Vector2.ONE
			face.uv_offset = Vector2.ZERO
	# Displacement data
	var disp_data: Variant = data.get("displacement", null)
	if disp_data is Dictionary:
		face.displacement = HFDisplacementData.from_dict(disp_data)
	return face


static func _encode_vec2(value: Vector2) -> Array:
	return [value.x, value.y]


static func _encode_vec3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


static func _decode_vec2(value: Variant, fallback: Vector2) -> Vector2:
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return fallback


static func _decode_vec3(value: Variant, fallback: Vector3) -> Vector3:
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return fallback


static func _encode_vec2_array(values: PackedVector2Array) -> Array:
	var out: Array = []
	for v in values:
		out.append([v.x, v.y])
	return out


static func _encode_vec3_array(values: PackedVector3Array) -> Array:
	var out: Array = []
	for v in values:
		out.append([v.x, v.y, v.z])
	return out


static func _decode_vec2_array(values: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for entry in values:
		if entry is Array and entry.size() >= 2:
			out.append(Vector2(float(entry[0]), float(entry[1])))
	return out


static func _decode_vec3_array(values: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for entry in values:
		if entry is Array and entry.size() >= 3:
			out.append(Vector3(float(entry[0]), float(entry[1]), float(entry[2])))
	return out


func _project_uvs_for_vertices(verts: PackedVector3Array) -> PackedVector2Array:
	return _project_uvs_in_space(verts, world_transform)


## The projection, in whatever space the caller asks for. `Transform3D.IDENTITY`
## is what the projection did before #652, which is what the migration folds out.
func _project_uvs_in_space(verts: PackedVector3Array, space: Transform3D) -> PackedVector2Array:
	var out := PackedVector2Array()
	var projection = uv_projection
	if projection == UVProjection.BOX_UV:
		projection = _box_projection_axis_in(space)
	var aabb = _compute_bounds_for(verts)
	var height = max(0.001, aabb.size.y)
	for local in verts:
		# World space, so the same face in two places gets two patches of texture
		# and a run of brushes reads as one surface (#652). Cylindrical keeps its
		# own space: its angle is measured about the brush's own axis, and taking
		# that in world space would spin the texture as the brush moved.
		var v: Vector3 = local if projection == UVProjection.CYLINDRICAL else space * local
		var uv = Vector2.ZERO
		match projection:
			UVProjection.PLANAR_X:
				uv = Vector2(v.z, v.y)
			UVProjection.PLANAR_Y:
				uv = Vector2(v.x, v.z)
			UVProjection.PLANAR_Z:
				uv = Vector2(v.x, v.y)
			UVProjection.CYLINDRICAL:
				var angle = atan2(v.z, v.x) / TAU + 0.5
				var vcoord = (v.y - aabb.position.y) / height
				uv = Vector2(angle, vcoord)
			_:
				uv = Vector2(v.x, v.y)
		uv = _apply_uv_transform(uv)
		out.append(uv)
	return out


## Fold a brush's placement into a hand-tuned `uv_offset`, so an alignment a
## mapper set before #652 survives the move to world-space projection.
##
## Before v2 a planar UV was projected from the brush's own vertices, so an
## offset meant "shift the texture along the brush". It now means "shift it
## along the level", and the two differ by wherever the brush is. Folding that
## in is the same sum texture lock does for a move, because moving a brush and
## changing the space it projects in do the same thing to the result.
##
## Only an offset somebody set is folded in. A face still on zero was never
## positioned by hand, and giving it one would put it back where #652 says it
## should not be, with the panels of a wall on the same patch of texture again.
## Those faces take the new projection, which is the fix arriving.
##
## A rotated brush cannot be corrected by an offset at all: world projection is
## a different map there, not the same one shifted. Those faces keep their old
## look the way the v0 to v1 migration keeps a non-uniform scale, by baking it
## into `custom_uvs`.
func migrate_uvs_to_world_space() -> void:
	var from_version := pending_uv_migration
	pending_uv_migration = -1
	if from_version < 0 or from_version >= 2:
		return
	if uv_offset.is_zero_approx():
		return
	if world_transform.is_equal_approx(Transform3D.IDENTITY):
		return
	var projection = uv_projection
	if projection == UVProjection.BOX_UV:
		projection = _box_projection_axis()
	# Cylindrical never left the brush's space, so it has nothing to fold in.
	if projection == UVProjection.CYLINDRICAL:
		return
	if not world_transform.basis.is_equal_approx(Basis.IDENTITY):
		if local_verts.size() >= 3 and custom_uvs.size() != local_verts.size():
			custom_uvs = _project_uvs_in_space(local_verts, Transform3D.IDENTITY)
		return
	var origin := world_transform.origin
	var placement := Vector2.ZERO
	match projection:
		UVProjection.PLANAR_X:
			placement = Vector2(origin.z, origin.y)
		UVProjection.PLANAR_Y:
			placement = Vector2(origin.x, origin.z)
		UVProjection.PLANAR_Z:
			placement = Vector2(origin.x, origin.y)
	# Rotation is applied before the scale and the offset, so the placement has
	# to be rotated the same way before it is taken back out.
	if uv_rotation != 0.0:
		placement = placement.rotated(uv_rotation)
	uv_offset -= placement * uv_scale


## Keep a face's texture the right way round when a turn moves it onto a
## different Box UV axis.
##
## `projection_axes()` is right handed for PLANAR_Z against its own normal and
## left handed for the other two. That could not matter while UVs were projected
## from a brush's own vertices, because a face's axis could not change. Since
## #652 the axis is resolved in the level, so a wall yawed a quarter turn moves
## from PLANAR_Z to PLANAR_X and comes back mirrored (#684).
##
## The correction is a sign on `uv_scale`, folded in at the moment the axis
## changes. Nothing on disk changes meaning, so no saved level needs migrating:
## a face reloaded after a turn already carries the flip in the scale it saved.
##
## Which of the two axes to flip is not a fixed answer. A yaw that takes a face
## from PLANAR_Z to PLANAR_X reverses U and leaves V; a roll that takes one from
## PLANAR_Y to PLANAR_Z reverses V and leaves U. So the old projection's axes are
## carried through the turn the brush made and compared with the new one's.
## A turn that does not land them on each other is a skew no planar projection
## holds, and is left alone rather than guessed at.
func reconcile_box_uv_axis() -> void:
	if uv_projection != UVProjection.BOX_UV:
		return
	var basis := world_transform.basis.orthonormalized()
	if not _uv_layout_known:
		_uv_layout_basis = basis
		_uv_layout_known = true
		return
	if basis.is_equal_approx(_uv_layout_basis):
		return
	var was := _uv_layout_basis
	_uv_layout_basis = basis
	var old_axis := _box_projection_axis_in(Transform3D(was, Vector3.ZERO))
	var new_axis := _box_projection_axis_in(Transform3D(basis, Vector3.ZERO))
	if old_axis == new_axis:
		# The face kept its plane. `adjust_uvs_for_rotation()` is what answers
		# for that case, and it is the caller's business whether to run it.
		return
	var turn := basis * was.inverse()
	var old_axes: Array = projection_axes(old_axis)
	var new_axes: Array = projection_axes(new_axis)
	var carried_u: Vector3 = (turn * (old_axes[0] as Vector3)).normalized()
	var carried_v: Vector3 = (turn * (old_axes[1] as Vector3)).normalized()
	var u_now: Vector3 = new_axes[0] as Vector3
	var v_now: Vector3 = new_axes[1] as Vector3
	var u_dot := u_now.dot(carried_u)
	var v_dot := v_now.dot(carried_v)
	if absf(u_dot) < 1.0 - UV_AXIS_EPSILON or absf(v_dot) < 1.0 - UV_AXIS_EPSILON:
		return
	if u_dot < 0.0:
		uv_scale.x = -uv_scale.x
	if v_dot < 0.0:
		uv_scale.y = -uv_scale.y


func _apply_uv_transform(uv: Vector2) -> Vector2:
	var out = uv
	if uv_rotation != 0.0:
		out = out.rotated(uv_rotation)
	out = out * uv_scale + uv_offset
	return out


## Old (v0) transform order: scale+offset first, then rotate.
## Used only for migrating persisted data from before uv_format_version 1.
func _apply_uv_transform_v0(uv: Vector2) -> Vector2:
	var out = uv * uv_scale + uv_offset
	if uv_rotation != 0.0:
		out = out.rotated(uv_rotation)
	return out


## Project UVs using the old (v0) transform order for migration.
func _project_uvs_v0(verts: PackedVector3Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var projection = uv_projection
	if projection == UVProjection.BOX_UV:
		projection = _box_projection_axis()
	var aabb = _compute_bounds_for(verts)
	var height = max(0.001, aabb.size.y)
	for v in verts:
		var uv = Vector2.ZERO
		match projection:
			UVProjection.PLANAR_X:
				uv = Vector2(v.z, v.y)
			UVProjection.PLANAR_Y:
				uv = Vector2(v.x, v.z)
			UVProjection.PLANAR_Z:
				uv = Vector2(v.x, v.y)
			UVProjection.CYLINDRICAL:
				var angle = atan2(v.z, v.x) / TAU + 0.5
				var vcoord = (v.y - aabb.position.y) / height
				uv = Vector2(angle, vcoord)
			_:
				uv = Vector2(v.x, v.y)
		uv = _apply_uv_transform_v0(uv)
		out.append(uv)
	return out


## Which planar axis Box UV resolves to, measured in `space`.
##
## Box UV picks the axis the face most nearly faces, so it has to be asked in
## the same space the projection is taken in. Asking in the brush's space while
## projecting in the level's is how a wall yawed a quarter turn kept `PLANAR_Z`
## and then projected world (x, y) onto a plane of constant x: every vertex got
## the same u and the texture smeared into a line (#652).
func _box_projection_axis_in(space: Transform3D) -> int:
	var n := normal if space.basis.is_equal_approx(Basis.IDENTITY) else space.basis * normal
	var ax = abs(n.x)
	var ay = abs(n.y)
	var az = abs(n.z)
	if ax >= ay and ax >= az:
		return UVProjection.PLANAR_X
	if ay >= ax and ay >= az:
		return UVProjection.PLANAR_Y
	return UVProjection.PLANAR_Z


## The axis as the face's own brush sees it. `adjust_uvs_for_rotation()` reasons
## in that space, and both migrations measure against what the old projection did.
func _box_projection_axis() -> int:
	var n = normal
	var ax = abs(n.x)
	var ay = abs(n.y)
	var az = abs(n.z)
	if ax >= ay and ax >= az:
		return UVProjection.PLANAR_X
	if ay >= ax and ay >= az:
		return UVProjection.PLANAR_Y
	return UVProjection.PLANAR_Z


func _compute_bounds() -> void:
	bounds = _compute_bounds_for(local_verts)


func _compute_bounds_for(verts: PackedVector3Array) -> AABB:
	if verts.is_empty():
		return AABB()
	var aabb = AABB(verts[0], Vector3.ZERO)
	for v in verts:
		aabb = aabb.expand(v)
	return aabb


func _compute_normal() -> void:
	if local_verts.size() < 3:
		normal = Vector3.UP
		return
	# A face with a vertex that is not a number has no normal, and asking for one
	# is an engine error per call rather than a value. The validator reports the
	# vertex; this just stops the noise.
	for v in local_verts:
		if not v.is_finite():
			normal = Vector3.UP
			return
	# Newell's method over the whole polygon, not the first three vertices.
	# Three consecutive vertices can be collinear without the face being
	# degenerate: `split_edge()` inserts a midpoint *on* an edge, and when the
	# split edge is the one at index 0 the first three vertices are collinear by
	# construction. The first-three cross product then measured zero, the
	# degenerate fallback fired, and a side wall was told it faced up — which is
	# what `validate_convexity()`, the bake and the `.map` export all read.
	#
	# The vertices are made relative to the first one and scaled by the face's
	# own extent before the sum, so what is measured is the shape rather than its
	# area. An absolute floor on the raw sum would call any small face
	# degenerate, which is the bug the previous comment here was about: a
	# 0.01-unit bevel cap came out facing into the solid whatever winding it was
	# built with, and the same is true of every tessellation sliver. Newell's sum
	# is translation invariant, so the shift costs nothing.
	var origin: Vector3 = local_verts[0]
	var extent := 0.0
	for v in local_verts:
		var offset: Vector3 = v - origin
		extent = maxf(extent, maxf(absf(offset.x), maxf(absf(offset.y), absf(offset.z))))
	if extent <= 0.0:
		normal = Vector3.UP
		return
	var inv_extent := 1.0 / extent
	var count := local_verts.size()
	var n := Vector3.ZERO
	for i in count:
		var current: Vector3 = (local_verts[i] - origin) * inv_extent
		var next: Vector3 = (local_verts[(i + 1) % count] - origin) * inv_extent
		n.x += (current.y - next.y) * (current.z + next.z)
		n.y += (current.z - next.z) * (current.x + next.x)
		n.z += (current.x - next.x) * (current.y + next.y)
	# Negated, because HammerForge winds a face clockwise seen from outside and
	# Newell's sum follows the other hand. This is the winding the old
	# `(c - a).cross(b - a)` produced.
	n = -n
	if n.length() > 0.0001:
		normal = n.normalized()
	else:
		normal = Vector3.UP


## The material a painted face renders with: the base with the composited albedo
## on it, and everything else about it kept.
##
## This used to build a bare `StandardMaterial3D` and copy three scalars across -
## `roughness`, `metallic` and `albedo_color` - so painting a face threw away its
## normal map, its roughness and metallic maps, its emission and its UV
## transform. On a tiled wall the UV scale going back to 1 is the visible one:
## the texture on the painted face is suddenly four times the size of the one
## beside it. Duplicating the base keeps all of it, including slots added to
## `StandardMaterial3D` in a future Godot version.
##
## A `ShaderMaterial` is refused rather than substituted. There is no way to
## reproduce one with an albedo texture on it, and building a plain
## `StandardMaterial3D` instead left one baked surface flat beside its
## neighbours with the shader silently gone. `HFMaterialAtlas.build_atlas()`
## already treats a ShaderMaterial this way, putting it in `fallback_keys` rather
## than pretending it can pack it. The base comes back unpainted, with a warning.
static func composite_painted_material(base: Material, painted: Image) -> Material:
	if painted == null:
		return base
	var tex := ImageTexture.create_from_image(painted)
	if tex == null:
		return base
	if base is ShaderMaterial:
		_warn_once_about_shader_paint(base)
		return base
	var mat: StandardMaterial3D
	if base is StandardMaterial3D:
		mat = (base as StandardMaterial3D).duplicate() as StandardMaterial3D
	else:
		# No palette material, or one this cannot read. The composite is the
		# whole surface.
		mat = StandardMaterial3D.new()
	mat.albedo_texture = tex
	return mat


## Once per material, not once per face per rebuild. `rebuild_preview()` runs on
## every paint sample.
static var _shader_paint_warned: Dictionary = {}


static func _warn_once_about_shader_paint(base: Material) -> void:
	var id := base.get_instance_id()
	if _shader_paint_warned.has(id):
		return
	_shader_paint_warned[id] = true
	(
		HFLog
		. warn(
			(
				"HammerForge: a face painted over a ShaderMaterial keeps the shader and drops the paint."
				+ " A shader cannot be composited over."
			)
		)
	)


func _blend_color(base: Color, tex: Color, weight: float, mode: int) -> Color:
	match mode:
		PaintBlend.MULTIPLY:
			var mult = Color(
				lerp(1.0, tex.r, weight), lerp(1.0, tex.g, weight), lerp(1.0, tex.b, weight), 1.0
			)
			return Color(base.r * mult.r, base.g * mult.g, base.b * mult.b, 1.0)
		PaintBlend.ADD:
			return Color(
				clamp(base.r + tex.r * weight, 0.0, 1.0),
				clamp(base.g + tex.g * weight, 0.0, 1.0),
				clamp(base.b + tex.b * weight, 0.0, 1.0),
				1.0
			)
		_:
			return base.lerp(tex, weight)
