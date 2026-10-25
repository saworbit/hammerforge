@tool
class_name HFSizeLabels
extends RefCounted
## The one look a size or a distance has in the viewport: the Measure tool's
## labels, white or coloured text on a black outline, facing the camera and
## drawn over the geometry in front of it.
##
## In the 3D view as Label3D nodes: the Measure tool's rulers (`make_label()`),
## and the size labels on a selection (#1403), which an instance of this holds on
## the level as one internal child with no owner, like the Face Select mark:
## never saved, never in the Scene tree, freed as soon as there is nothing to
## label. Over the viewport in 2D for the size beside the cursor (#1402), which
## follows the pointer rather than anything in the level (`draw_2d()`).

const OUTLINE_COLOR := Color.BLACK
const OUTLINE_SIZE := 4
const FONT_SIZE := 24
## A world-sized label, as the Measure tool's rulers are: the text is this many
## units per pixel of the font.
const PIXEL_SIZE := 0.005
## A label that keeps one size on screen whatever its distance, as a size readout
## has to be readable on a 64-unit room and on a 0.25 step alike: about the size
## of the editor's own text in a 700-pixel viewport. Half this was measured in
## the editor at 8 pixels, too small to read past the gizmo.
const FIXED_PIXEL_SIZE := 0.0016
const NODE_NAME := &"_SizeLabels"

## What the labels' node is called, so two sets on one level are told apart.
var container_name: StringName = NODE_NAME
## Where the 2D label sits from the pointer: below and to the right, clear of the
## corner being dragged, as a tooltip sits.
const POINTER_OFFSET := Vector2(18, 20)

var _container: Node3D = null


## A label in the Measure tool's style, not yet in the tree.
static func make_label(text: String, color: Color, fixed_size := false) -> Label3D:
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = fixed_size
	label.pixel_size = FIXED_PIXEL_SIZE if fixed_size else PIXEL_SIZE
	label.font_size = FONT_SIZE
	label.modulate = color
	label.outline_modulate = OUTLINE_COLOR
	label.outline_size = OUTLINE_SIZE
	label.text = text
	return label


## Show [param entries] on [param parent], each `{"position", "text", "color"}`
## with the position in world space, and an `offset` in the label's pixels to set
## it beside that point, replacing whatever was shown. Nothing to show takes the
## node down.
func show_labels(parent: Node, entries: Array) -> void:
	if parent == null or not is_instance_valid(parent) or entries.is_empty():
		clear()
		return
	_ensure_container(parent)
	var labels := get_labels()
	# Reused rather than made again, as these follow a drag frame by frame.
	while labels.size() > entries.size():
		var spare: Label3D = labels.pop_back()
		_container.remove_child(spare)
		spare.free()
	for i in entries.size():
		var entry: Dictionary = entries[i]
		var label: Label3D = null
		if i < labels.size():
			label = labels[i]
		else:
			label = make_label("", Color.WHITE, true)
			label.name = "SizeLabel%d" % i
			_container.add_child(label)
		label.text = str(entry.get("text", ""))
		label.modulate = entry.get("color", Color.WHITE)
		label.offset = entry.get("offset", Vector2.ZERO)
		label.position = entry.get("position", Vector3.ZERO)


## Take every label down.
func clear() -> void:
	if is_instance_valid(_container):
		var parent := _container.get_parent()
		if parent:
			parent.remove_child(_container)
		_container.free()
	_container = null


## The labels shown now, in the order they were given.
func get_labels() -> Array[Label3D]:
	var out: Array[Label3D] = []
	if not is_instance_valid(_container):
		return out
	for child in _container.get_children():
		if child is Label3D:
			out.append(child)
	return out


## The node the labels hang from, or null while none is shown.
func get_container() -> Node3D:
	return _container if is_instance_valid(_container) else null


func _ensure_container(parent: Node) -> void:
	if is_instance_valid(_container) and _container.get_parent() == parent:
		return
	clear()
	_container = Node3D.new()
	_container.name = container_name
	# The positions are world space, so the level's own transform must not move them.
	_container.top_level = true
	parent.add_child(_container, false, Node.INTERNAL_MODE_BACK)


## Draw [param text] beside [param pointer] on [param canvas], in the same look.
## Only from inside the canvas's draw, as every CanvasItem draw call is.
static func draw_2d(canvas: Control, pointer: Vector2, text: String, color := Color.WHITE) -> void:
	if canvas == null or text.is_empty():
		return
	var font: Font = canvas.get_theme_default_font()
	var font_size: int = canvas.get_theme_default_font_size()
	if font == null:
		return
	var text_size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var top_left := place_2d(canvas.size, pointer, text_size)
	var baseline := top_left + Vector2(0, font.get_ascent(font_size))
	canvas.draw_string_outline(
		font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, OUTLINE_SIZE, OUTLINE_COLOR
	)
	canvas.draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


## Where a block of [param text_size] goes beside [param pointer] in an [param area]
## that size: below and to the right, or across to the other side of the pointer
## where that would run off the edge.
static func place_2d(area: Vector2, pointer: Vector2, text_size: Vector2) -> Vector2:
	var top_left := pointer + POINTER_OFFSET
	if top_left.x + text_size.x > area.x:
		top_left.x = pointer.x - POINTER_OFFSET.x - text_size.x
	if top_left.y + text_size.y > area.y:
		top_left.y = pointer.y - POINTER_OFFSET.y - text_size.y
	return top_left
