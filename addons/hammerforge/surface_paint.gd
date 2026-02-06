@tool
extends Node
class_name SurfacePaint

const FaceData = preload("face_data.gd")

@export var default_layer_size: Vector2i = Vector2i(256, 256)

func paint_at_uv(face: FaceData, layer_idx: int, uv: Vector2, radius_uv: float, strength: float) -> void:
	if face == null:
		return
	var layer = _ensure_layer(face, layer_idx)
	if layer == null:
		return
	layer.ensure_weight_image(default_layer_size)
	var img = layer.weight_image
	if img == null or img.is_empty():
		return
	var size = img.get_size()
	var radius_px = int(max(1.0, radius_uv * float(max(size.x, size.y))))
	var center = Vector2(uv.x * size.x, uv.y * size.y)
	img.lock()
	for y in range(int(center.y) - radius_px, int(center.y) + radius_px + 1):
		if y < 0 or y >= size.y:
			continue
		for x in range(int(center.x) - radius_px, int(center.x) + radius_px + 1):
			if x < 0 or x >= size.x:
				continue
			var dx = float(x) - center.x
			var dy = float(y) - center.y
			var dist = sqrt(dx * dx + dy * dy)
			if dist > radius_px:
				continue
			var falloff = 1.0 - (dist / float(radius_px))
			var weight = clamp(strength * falloff, -1.0, 1.0)
			var current = img.get_pixel(x, y)
			var next = clamp(current.r + weight, 0.0, 1.0)
			img.set_pixel(x, y, Color(next, current.g, current.b, 1.0))
	img.unlock()

func _ensure_layer(face: FaceData, layer_idx: int) -> FaceData.PaintLayer:
	if layer_idx < 0:
		layer_idx = 0
	while face.paint_layers.size() <= layer_idx:
		face.paint_layers.append(FaceData.PaintLayer.new())
	return face.paint_layers[layer_idx]
