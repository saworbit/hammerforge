@tool
extends Resource
class_name FaceData

enum UVProjection { PLANAR_X, PLANAR_Y, PLANAR_Z, BOX_UV, CYLINDRICAL }
enum PaintBlend { OVERLAY, MULTIPLY, ADD }

class PaintLayer:
	extends Resource
	@export var texture: Texture2D = null
	@export var weight_image: Image = null
	@export var blend_mode: int = PaintBlend.OVERLAY
	@export var opacity: float = 1.0

	func ensure_weight_image(size: Vector2i = Vector2i(256, 256)) -> void:
		if weight_image == null or weight_image.is_empty():
			weight_image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
			weight_image.fill(Color(0, 0, 0, 1))

@export var material_idx: int = -1
@export var uv_projection: int = UVProjection.PLANAR_Z
@export var uv_scale: Vector2 = Vector2.ONE
@export var uv_offset: Vector2 = Vector2.ZERO
@export var uv_rotation: float = 0.0
@export var custom_uvs: PackedVector2Array = PackedVector2Array()
@export var paint_layers: Array[PaintLayer] = []
@export var bounds: AABB = AABB()
@export var local_verts: PackedVector3Array = PackedVector3Array()
@export var normal: Vector3 = Vector3.UP

func ensure_geometry() -> void:
	_compute_normal()
	_compute_bounds()

func ensure_custom_uvs() -> void:
	if custom_uvs.size() == local_verts.size():
		return
	custom_uvs = _project_uvs_for_vertices(local_verts)

func triangulate() -> Dictionary:
	var tri_verts := PackedVector3Array()
	var tri_uvs := PackedVector2Array()
	var count = local_verts.size()
	if count < 3:
		return { "verts": tri_verts, "uvs": tri_uvs }
	var source_uvs = custom_uvs
	if source_uvs.size() != count:
		source_uvs = _project_uvs_for_vertices(local_verts)
	for i in range(1, count - 1):
		tri_verts.append(local_verts[0])
		tri_verts.append(local_verts[i])
		tri_verts.append(local_verts[i + 1])
		tri_uvs.append(source_uvs[0])
		tri_uvs.append(source_uvs[i])
		tri_uvs.append(source_uvs[i + 1])
	return { "verts": tri_verts, "uvs": tri_uvs }

func get_painted_albedo(max_size: int = 512) -> Image:
	var layers: Array = paint_layers
	if layers.is_empty():
		return null
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
		return null
	if max_size > 0:
		var scale = min(1.0, float(max_size) / float(max(target_w, target_h)))
		target_w = max(1, int(round(target_w * scale)))
		target_h = max(1, int(round(target_h * scale)))
	var out = Image.create(target_w, target_h, false, Image.FORMAT_RGBA8)
	out.fill(Color(1, 1, 1, 1))
	for layer in layers:
		if layer == null or layer.opacity <= 0.0:
			continue
		if not layer.texture or not layer.texture is Texture2D:
			continue
		var tex_img = layer.texture.get_image()
		if tex_img.is_empty():
			continue
		var paint_img = layer.weight_image
		if paint_img == null or paint_img.is_empty():
			layer.ensure_weight_image(Vector2i(target_w, target_h))
			paint_img = layer.weight_image
		if tex_img.get_width() != target_w or tex_img.get_height() != target_h:
			tex_img = tex_img.duplicate()
			tex_img.resize(target_w, target_h, Image.INTERPOLATE_LANCZOS)
		if paint_img.get_width() != target_w or paint_img.get_height() != target_h:
			paint_img = paint_img.duplicate()
			paint_img.resize(target_w, target_h, Image.INTERPOLATE_LANCZOS)
		out.lock()
		tex_img.lock()
		paint_img.lock()
		for y in range(target_h):
			for x in range(target_w):
				var w = clamp(paint_img.get_pixel(x, y).r * layer.opacity, 0.0, 1.0)
				if w <= 0.0:
					continue
				var base = out.get_pixel(x, y)
				var tex = tex_img.get_pixel(x, y)
				var blended = _blend_color(base, tex, w, layer.blend_mode)
				out.set_pixel(x, y, blended)
		out.unlock()
		tex_img.unlock()
		paint_img.unlock()
	return out

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
		"uv_projection": uv_projection,
		"uv_scale": _encode_vec2(uv_scale),
		"uv_offset": _encode_vec2(uv_offset),
		"uv_rotation": uv_rotation,
		"custom_uvs": _encode_vec2_array(custom_uvs),
		"local_verts": _encode_vec3_array(local_verts),
		"normal": _encode_vec3(normal),
		"paint_layers": layer_data
	}

static func from_dict(data: Dictionary) -> FaceData:
	var face = FaceData.new()
	face.material_idx = int(data.get("material_idx", -1))
	face.uv_projection = int(data.get("uv_projection", UVProjection.PLANAR_Z))
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
		uv = _apply_uv_transform(uv)
		out.append(uv)
	return out

func _apply_uv_transform(uv: Vector2) -> Vector2:
	var out = uv * uv_scale + uv_offset
	if uv_rotation != 0.0:
		out = out.rotated(uv_rotation)
	return out

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
	var a = local_verts[0]
	var b = local_verts[1]
	var c = local_verts[2]
	var n = (b - a).cross(c - a)
	if n.length() > 0.0001:
		normal = n.normalized()
	else:
		normal = Vector3.UP

func _blend_color(base: Color, tex: Color, weight: float, mode: int) -> Color:
	match mode:
		PaintBlend.MULTIPLY:
			var mult = Color(
				lerp(1.0, tex.r, weight),
				lerp(1.0, tex.g, weight),
				lerp(1.0, tex.b, weight),
				1.0
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
