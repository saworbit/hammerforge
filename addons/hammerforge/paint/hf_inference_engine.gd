@tool
class_name HFInferenceEngine
extends RefCounted

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


func apply_cleanup(
	layer: HFPaintLayer,
	dirty_chunks: Array[Vector2i],
	intent: StringName,
	settings: InferenceSettings
) -> void:
	# Keep this chunk-local and bounded.
	# MVP: implement denoise + gap bridge + corridor width (dilate/erode) by operating on a chunk mask with 1-cell border.
	for cid in dirty_chunks:
		_cleanup_chunk(layer, cid, intent, settings)


func _cleanup_chunk(
	layer: HFPaintLayer, cid: Vector2i, intent: StringName, s: InferenceSettings
) -> void:
	# Implementation detail: build a small boolean grid for this chunk + border.
	# Then run passes and write back only for cells in this chunk.
	pass
