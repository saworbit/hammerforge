@tool
class_name HFInferenceEngine
extends RefCounted

## Stroke intent classification, and a cleanup pass that was never written.
##
## Nothing assigns this to `HFPaintTool.inference`, so nothing runs it. It used
## to be assigned to every level's paint tool, where it classified each stroke on
## mouse release and then walked the stroke's dirty chunks calling a `_cleanup_chunk()`
## that does nothing. Every setting below described behaviour the paint pipeline
## presented as a working stage and did not have.
##
## `infer_intent()` works and is the half worth keeping. The rest is a shape to
## fill in: denoise, small hole fill, gap bridging, corridor width and angle
## handling, bounded to the dirty chunks with a one cell border so a cleanup
## cannot seam at a chunk edge or touch a cell the stroke never reached.
##
## Turning it on means assigning an engine to the paint tool, and that should
## come with a setting and a default that the floor paint guide can describe.

const HFStroke = preload("hf_stroke.gd")


class InferenceSettings:
	var denoise_min_island_area := 3
	var fill_max_hole_area := 2
	var gap_tolerance := 1
	var min_corridor_width := 2
	var angle_snap_degrees := 12.0


func infer_intent(stroke: HFStroke) -> StringName:
	# deterministic intent labels: "corridor", "room", "blob", "erase"
	if stroke.tool == HFStroke.Tool.ERASE:
		return &"erase"
	if stroke.is_closed and stroke.aspect_ratio < 3.0:
		return &"room"
	if stroke.aspect_ratio >= 3.0 and stroke.avg_speed >= 10.0:
		return &"corridor"
	return &"blob"


## Not implemented. Changes no cells.
##
## Kept so the shape of the stage is on record: chunk local and bounded, one
## chunk mask at a time with a one cell border, denoise then gap bridge then
## corridor width, writing back only cells inside the chunk.
func apply_cleanup(
	_layer: HFPaintLayer,
	_dirty_chunks: Array[Vector2i],
	_intent: StringName,
	_settings: InferenceSettings
) -> void:
	pass
