extends GutTest

## The change tracker is how an Inspector edit reaches Bake Changed. A face's
## smoothing group, the axes an old face was laid on with, and a brush's Cast
## Shadows and Lightmap Scale are all bake inputs the Inspector edits, and none
## was in the signature it compares, so Bake Changed found nothing to do (#1661).

const LevelRootType = preload("res://addons/hammerforge/level_root.gd")
const BrushChangeTracker = preload("res://addons/hammerforge/hf_brush_change_tracker.gd")
const HFBakeSplit = preload("res://addons/hammerforge/hf_bake_split.gd")


func _fresh_root() -> LevelRoot:
	var root := LevelRootType.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	root.owner = self
	return root


## A box with its faces built, and a tracker primed on the level.
func _tracked(root: LevelRoot) -> Array:
	var brush: DraftBrush = (
		root
		. create_brush_from_info(
			{
				"shape": root.BrushShape.BOX,
				"size": Vector3(2, 2, 2),
				"transform": Transform3D.IDENTITY,
				"brush_id": "t",
			}
		)
	)
	root.brush_system._ensure_faces(brush)
	var tracker := BrushChangeTracker.new()
	tracker.prime(root)
	root.consume_dirty_tags()
	return [brush, tracker]


func test_a_smoothing_group_edit_is_seen():
	var root := _fresh_root()
	var pair := _tracked(root)
	(pair[0] as DraftBrush).get_faces()[0].smoothing_group = 3
	assert_eq((pair[1] as BrushChangeTracker).reconcile(root), PackedStringArray(["t"]))


func test_a_legacy_axes_edit_is_seen():
	var root := _fresh_root()
	var pair := _tracked(root)
	var face: FaceData = (pair[0] as DraftBrush).get_faces()[0]
	face.legacy_wall_axes = not face.legacy_wall_axes
	assert_eq((pair[1] as BrushChangeTracker).reconcile(root), PackedStringArray(["t"]))


func test_a_cast_shadow_meta_edit_is_seen():
	var root := _fresh_root()
	var pair := _tracked(root)
	(pair[0] as Node).set_meta(HFBakeSplit.CAST_SHADOW_META, 0)
	assert_eq((pair[1] as BrushChangeTracker).reconcile(root), PackedStringArray(["t"]))


func test_a_lightmap_scale_meta_edit_is_seen():
	var root := _fresh_root()
	var pair := _tracked(root)
	(pair[0] as Node).set_meta(HFBakeSplit.LIGHTMAP_SCALE_META, 4.0)
	assert_eq((pair[1] as BrushChangeTracker).reconcile(root), PackedStringArray(["t"]))


func test_no_edit_is_no_change():
	var root := _fresh_root()
	var pair := _tracked(root)
	assert_eq((pair[1] as BrushChangeTracker).reconcile(root), PackedStringArray())
