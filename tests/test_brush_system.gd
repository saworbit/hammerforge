extends GutTest
## Brush-cache authority: DraftBrush lookup does not depend on BrushManager.

const HFBrushSystem = preload("res://addons/hammerforge/systems/hf_brush_system.gd")
const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")

var root: LevelRoot
var sys: HFBrushSystem


func before_each():
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	sys = root.brush_system


func after_each():
	root = null
	sys = null


## The real root builds a BrushManager. These tests are about the cache standing
## on its own, so they take the legacy mirror away first.
func _without_brush_manager() -> void:
	root.brush_manager = null


func test_create_from_info_caches_without_brush_manager():
	_without_brush_manager()
	var brush = sys.create_brush_from_info(
		{"shape": 0, "size": Vector3(16, 16, 16), "center": Vector3(8, 8, 8), "brush_id": "box_1"}
	)
	assert_not_null(brush)
	assert_eq(sys.get_cached_brush_count(), 1)
	assert_eq(sys.find_brush_by_id("box_1"), brush)
	var cached: Array = sys.get_cached_brushes()
	assert_eq(cached.size(), 1)
	assert_eq(cached[0], brush)


func test_delete_removes_from_cache_without_brush_manager():
	_without_brush_manager()
	sys.create_brush_from_info({"size": Vector3(8, 8, 8), "center": Vector3.ZERO, "brush_id": "a"})
	sys.create_brush_from_info({"size": Vector3(8, 8, 8), "center": Vector3.ONE, "brush_id": "b"})
	assert_eq(sys.get_cached_brush_count(), 2)
	var result = sys.delete_brush_by_id("a")
	assert_true(result.ok)
	assert_null(sys.find_brush_by_id("a"))
	assert_eq(sys.get_cached_brush_count(), 1)
	assert_not_null(sys.find_brush_by_id("b"))


func test_legacy_manager_mirror_stays_optional():
	# Cache remains usable even if a later restore never creates BrushManager.
	_without_brush_manager()
	var brush = sys.create_brush_from_info(
		{"size": Vector3(4, 4, 4), "center": Vector3.ZERO, "brush_id": "solo"}
	)
	assert_null(root.brush_manager)
	assert_eq(sys.get_cached_brushes(), [brush])


func test_cache_is_authority_when_legacy_manager_exists():
	var manager: BrushManager = root.brush_manager
	assert_not_null(manager, "the real root builds the legacy manager")
	var brush = sys.create_brush_from_info(
		{"size": Vector3(4, 4, 4), "center": Vector3.ZERO, "brush_id": "cached"}
	)
	assert_eq(sys.get_cached_brush_count(), 1)
	assert_eq(sys.find_brush_by_id("cached"), brush)
	assert_eq(manager.brushes, [brush], "Legacy list is a mirror of the cache")
	sys.delete_brush_by_id("cached")
	assert_eq(sys.get_cached_brush_count(), 0)
	assert_eq(manager.brushes, [])


func test_place_brush_uses_world_space_when_root_is_offset():
	var hit_root := _FixedHitRoot.new()
	hit_root.auto_spawn_player = false
	hit_root.hflevel_autosave_enabled = false
	add_child_autoqfree(hit_root)
	hit_root.position = Vector3(50, 0, 50)
	hit_root.raycast_position = Vector3.ZERO
	var camera := Camera3D.new()
	add_child_autoqfree(camera)
	var placed = hit_root.brush_system.place_brush(
		Vector2.ZERO, CSGShape3D.OPERATION_UNION, Vector3(16, 16, 16), camera
	)
	assert_true(placed, "A hit under the cursor places a brush")
	assert_eq(hit_root.draft_brushes_node.get_child_count(), 1)
	var brush = hit_root.draft_brushes_node.get_child(0)
	assert_almost_eq(
		brush.global_position,
		Vector3(0, 8, 0),
		Vector3(0.001, 0.001, 0.001),
		"The brush sits on the point the ray hit, not that point plus the root offset"
	)
	assert_almost_eq(
		hit_root.last_brush_center,
		Vector3(0, 8, 0),
		Vector3(0.001, 0.001, 0.001),
		"The recorded last brush position is the world position too"
	)


## The real root with the ray answered by a fixed hit, so place_brush() has a
## point to land on without a physics world or a viewport behind the camera.
class _FixedHitRoot:
	extends LevelRoot
	var raycast_position := Vector3.ZERO

	func _raycast(_camera: Camera3D, _mouse_pos: Vector2) -> Dictionary:
		return {"position": raycast_position}
