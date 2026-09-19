@tool
extends Node
class_name SurfacePaint

const FaceData = preload("face_data.gd")

@export var default_layer_size: Vector2i = Vector2i(256, 256)

## The smallest weight an 8-bit channel can hold. A contribution below it cannot
## change the stored value, so the read and the write are skipped.
const MIN_TEXEL_WEIGHT := 1.0 / 255.0


## Paint one circular sample into a face's weight image.
##
## `uv` is a position inside one tile of the face's texture, 0..1, which is what
## the renderer samples the painted albedo with. The brush wraps at the tile
## edges for the same reason, so a stroke on a seam is not cut in half.
##
## The loop walks each row's actual span instead of the circle's bounding square:
## the corners are about a fifth of that square and were being tested and thrown
## away one texel at a time. `while` rather than `for` because `range()` builds an
## array per row, which at the top of the dock's radius range is 257 of them.
func paint_at_uv(
	face: FaceData, layer_idx: int, uv: Vector2, radius_uv: float, strength: float
) -> void:
	if face == null:
		return
	var layer = _ensure_layer(face, layer_idx)
	if layer == null:
		return
	layer.ensure_weight_image(default_layer_size)
	var img: Image = layer.weight_image
	if img == null or img.is_empty():
		return
	var size := img.get_size()
	if size.x <= 0 or size.y <= 0:
		return
	# A radius past half the image would wrap onto itself, painting some texels
	# twice in one sample. That is not a bigger brush, it is a wrong one.
	var max_radius: int = maxi(1, mini(size.x, size.y) / 2)
	var radius_px: int = clampi(
		int(max(1.0, radius_uv * float(max(size.x, size.y)))), 1, max_radius
	)
	var center_x := uv.x * float(size.x)
	var center_y := uv.y * float(size.y)
	var radius_f := float(radius_px)
	var inv_radius := 1.0 / radius_f
	var radius_sq := radius_f * radius_f

	var y := int(floor(center_y)) - radius_px
	var y_end := int(floor(center_y)) + radius_px
	while y <= y_end:
		var dy := float(y) - center_y
		var dy_sq := dy * dy
		if dy_sq > radius_sq:
			y += 1
			continue
		# The half-width of the circle on this row. One sqrt a row replaces a
		# distance test on every texel of the bounding square.
		var half_width := sqrt(radius_sq - dy_sq)
		var wy := y
		if wy < 0:
			wy += size.y
		elif wy >= size.y:
			wy -= size.y
		var x := int(ceil(center_x - half_width))
		var x_end := int(floor(center_x + half_width))
		while x <= x_end:
			var dx := float(x) - center_x
			var falloff := 1.0 - sqrt(dx * dx + dy_sq) * inv_radius
			var weight: float = clamp(strength * falloff, -1.0, 1.0)
			if absf(weight) < MIN_TEXEL_WEIGHT:
				x += 1
				continue
			# The radius cap keeps this at most one image away in either
			# direction, so one correction is enough and posmod is not needed.
			var wx := x
			if wx < 0:
				wx += size.x
			elif wx >= size.x:
				wx -= size.x
			var current: Color = img.get_pixel(wx, wy)
			var next: float = clamp(current.r + weight, 0.0, 1.0)
			img.set_pixel(wx, wy, Color(next, current.g, current.b, 1.0))
			x += 1
		y += 1


## How many textures may be blended over one face. The same cap
## `LevelRoot.add_surface_paint_layer()` enforces, because painting into a layer
## index creates the layers below it and would otherwise walk straight past it.
const MAX_PAINT_LAYERS := 8


func _ensure_layer(face: FaceData, layer_idx: int) -> FaceData.PaintLayer:
	if layer_idx < 0:
		layer_idx = 0
	if layer_idx >= MAX_PAINT_LAYERS:
		return null
	while face.paint_layers.size() <= layer_idx:
		face.paint_layers.append(FaceData.PaintLayer.new())
	return face.paint_layers[layer_idx]
