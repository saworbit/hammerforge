@tool
class_name HFFacePaintLayer
extends Resource

## One surface-paint layer on one face: a texture, a weight mask and how the two
## blend over what is underneath.
##
## This lived as `class PaintLayer` inside `FaceData` and had to come out.
## `FaceData` is a Resource, so a face reaches the `.tscn` that Godot's own
## Ctrl+S writes -- but an inner class has no type the scene can name, so on load
## the engine refused the restored objects with "Attempted to assign an object
## into a TypedArray, that does not inherit from 'GDScript'" and the face came
## back with `paint_layers` empty (#665). A painted wall reopened unpainted, and
## the error went to the console rather than to the mapper.
##
## `FaceData.PaintLayer` still names it, as a const preload, so every existing
## call site reads the same.

const DEFAULT_WEIGHT_SIZE := Vector2i(256, 256)

@export var texture: Texture2D = null
@export var weight_image: Image = null
@export var blend_mode: int = FaceData.PaintBlend.OVERLAY
@export var opacity: float = 1.0


func ensure_weight_image(size: Vector2i = DEFAULT_WEIGHT_SIZE) -> void:
	if weight_image == null or weight_image.is_empty():
		weight_image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
		weight_image.fill(Color(0, 0, 0, 1))
