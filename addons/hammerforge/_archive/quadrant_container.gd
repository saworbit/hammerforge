@tool
extends GridContainer
class_name QuadrantContainer

@onready var views := {
	"Top": $TopView, "Front": $FrontView, "Side": $SideView, "Perspective": $PerspectiveView
}

var current_world: World3D = null


func _ready() -> void:
	call_deferred("_sync_world")
	set_process(true)


func _sync_world() -> void:
	var world = _resolve_editor_world()
	if world:
		set_world_3d(world)


func _process(_delta: float) -> void:
	if current_world:
		return
	var world = _resolve_editor_world()
	if world:
		set_world_3d(world)


func _resolve_editor_world() -> World3D:
	var scene = get_tree().edited_scene_root
	if scene and scene.has_method("get_world_3d"):
		var world = scene.call("get_world_3d")
		if world:
			return world
	if scene and scene.is_inside_tree():
		return scene.get_viewport().world_3d
	var current = get_tree().get_current_scene()
	if current and current.is_inside_tree():
		return current.get_viewport().world_3d
	var root = get_tree().root
	if root:
		var sub_viewports = root.find_children("", "SubViewport", true, false)
		var best_world: World3D = null
		var best_area := 0.0
		for item in sub_viewports:
			var sub_vp := item as SubViewport
			if not sub_vp:
				continue
			if not sub_vp.world_3d:
				continue
			var area = sub_vp.size.x * sub_vp.size.y
			if area > best_area:
				best_area = area
				best_world = sub_vp.world_3d
		if best_world:
			return best_world
	var vp = get_viewport()
	if vp:
		return vp.world_3d
	return null


func set_world_3d(world: World3D) -> void:
	if not world:
		return
	current_world = world
	for view in views.values():
		if view and view.has_method("set_world_3d"):
			view.call("set_world_3d", world)


func _screen_to_local(screen_pos: Vector2) -> Vector2:
	var xform: Transform2D = get_global_transform_with_canvas().affine_inverse()
	return xform * screen_pos


func get_camera_at_screen_pos(screen_pos: Vector2) -> Dictionary:
	var local = _screen_to_local(screen_pos)
	for view in views.values():
		var view_control := view as Control
		if not view_control:
			continue
		var rect: Rect2 = view_control.get_rect()
		if rect.has_point(local):
			var local_pos = local - rect.position
			var cam = view_control.call("get_camera")
			return {"camera": cam, "pos": local_pos}
	return {}
