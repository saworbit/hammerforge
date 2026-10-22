extends GutTest

## The brush being drawn and a cut waiting for Apply were literal colours, so
## High Contrast and a mapper's own picks never reached them, and under High
## Contrast a committed cut was orange like a pending one (#1680).

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const HFOverlayColors = preload("res://addons/hammerforge/hf_overlay_colors.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")

var root: LevelRoot


func before_each():
	root = LevelRootType.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)


func after_each():
	HFOverlayColors.reset()


func _use(preset: Dictionary) -> void:
	HFOverlayColors._colors = preset.duplicate()
	HFOverlayColors._revision += 1


func _preview() -> Color:
	return (
		(root._make_brush_material(CSGShape3D.OPERATION_UNION) as StandardMaterial3D).albedo_color
	)


func test_the_default_look_is_the_one_these_replaced():
	assert_eq(_preview(), Color(0.3, 0.6, 1.0, 0.35))
	assert_eq(DraftBrush.pending_cut_look().albedo_color, Color(1.0, 0.3, 0.1, 0.5))


func test_high_contrast_reaches_the_draw_preview_and_a_pending_cut():
	var before := _preview()
	_use(HFOverlayColors.HIGH_CONTRAST)
	var high: Dictionary = HFOverlayColors.HIGH_CONTRAST
	assert_ne(_preview(), before, "a new palette is a new preview look")
	assert_eq(_preview(), high[HFOverlayColors.DRAW_PREVIEW])
	assert_eq(DraftBrush.pending_cut_look().albedo_color, high[HFOverlayColors.PENDING_CUT])


func test_a_pending_cut_and_a_committed_cut_differ_in_every_preset():
	for preset: Dictionary in [HFOverlayColors.DEFAULTS, HFOverlayColors.HIGH_CONTRAST]:
		var pending: Color = preset[HFOverlayColors.PENDING_CUT]
		var committed: Color = preset[HFOverlayColors.SUBTRACTIVE_BRUSH]
		assert_ne(pending, committed)
	var high: Dictionary = HFOverlayColors.HIGH_CONTRAST
	var hue_apart := absf(
		(
			(high[HFOverlayColors.PENDING_CUT] as Color).h
			- (high[HFOverlayColors.SUBTRACTIVE_BRUSH] as Color).h
		)
	)
	assert_gt(minf(hue_apart, 1.0 - hue_apart), 0.2, "High Contrast keeps them apart by hue")


func test_every_colour_has_a_label_a_tooltip_and_a_high_contrast_value():
	for key in HFOverlayColors.DEFAULTS:
		assert_true(HFOverlayColors.LABELS.has(key), key)
		assert_true(HFOverlayColors.TOOLTIPS.has(key), key)
		assert_true(HFOverlayColors.HIGH_CONTRAST.has(key), key)
