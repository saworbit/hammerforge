@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Whether Generate occluders makes occluders of things that move or are seen through.
##
## An occluder is static: the renderer culls whatever is behind it for the life
## of the scene. `_generate_occluders()` builds them from every triangle of every
## MeshInstance3D under the baked container (`_collect_mesh_instances()`). Doors,
## physboxes and illusionary brushes all bake a MeshInstance3D there. A door
## swings or slides away, a physbox is pushed, and an illusionary brush is a bead
## curtain or a light shaft the player sees and walks through. This bakes one of
## each as a wall-sized brush, with a static detail wall beside them as the
## control, and counts the occluder area that lands inside each brush.

const CLASSES := ["func_detail", "func_door", "func_physbox", "func_illusionary"]
const WALL := Vector3(4, 3, 0.2)


func id() -> String:
	return "occluder-movers"


func summary() -> String:
	return "whether Generate occluders makes occluders of doors, physboxes and illusionary brushes"


func expected_issues() -> Array[int]:
	return [1961]


func run() -> void:
	var root: Node3D = await fresh_root("OccluderLevel")
	box(root, Vector3(40, 0.2, 10), Vector3(0, -0.1, 0))
	var places: Dictionary = {}
	var x := -15.0
	for cls in CLASSES:
		var at := Vector3(x, WALL.y * 0.5, 0)
		var b = box(root, WALL, at)
		root.tie_brushes_to_entity([str(b.get_meta("brush_id", ""))], cls, cls.replace("func_", ""))
		places[cls] = AABB(at - WALL * 0.5 - Vector3.ONE * 0.05, WALL + Vector3.ONE * 0.1)
		x += 10.0
	root.bake_generate_occluders = true
	root.bake_occluder_min_area = 1.0
	await root.bake(true, false)
	await frame()
	var container := root.get_node_or_null("BakedGeometry") as Node3D
	var areas := _occluder_area_in(container, places)
	for cls in CLASSES:
		note("%s: occluder area inside the brush" % cls, snappedf(float(areas.get(cls, 0.0)), 0.01))
	if float(areas.get("func_detail", 0.0)) < 1.0:
		note("the static control wall got no occluder, so nothing below says anything", areas)
		await drop_root(root)
		return
	var door_mover := _mover_of(container, "door")
	note("what the door bakes as", door_mover)
	for cls in ["func_door", "func_physbox", "func_illusionary"]:
		var area := float(areas.get(cls, 0.0))
		if area > 0.5:
			known(
				1961,
				"Generate occluders makes a static occluder of a %s" % cls,
				(
					"a %s wall 4 x 3 bakes %.1f square units of occluder inside it, as much as the func_detail wall beside it (%.1f). %s"
					% [
						cls,
						area,
						float(areas["func_detail"]),
						_why(cls),
					]
				)
			)
	await drop_root(root)


func _why(cls: String) -> String:
	match cls:
		"func_door":
			return "The door opens; its occluder stays where the closed door was and culls the room behind the open doorway."
		"func_physbox":
			return "The crate is pushed away; its occluder stays where it was placed and culls what is behind that spot."
		"func_illusionary":
			return "It is seen and walked through (a bead curtain, cobwebs, a light shaft); its occluder culls what is behind it."
	return ""


## The occluder area, in square units, whose triangles' centres lie in each AABB.
func _occluder_area_in(container: Node3D, places: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	if container == null:
		return out
	var occluders := container.get_node_or_null("Occluders")
	if occluders == null:
		return out
	for inst in occluders.get_children():
		if not (inst is OccluderInstance3D):
			continue
		var occ := (inst as OccluderInstance3D).occluder as ArrayOccluder3D
		if occ == null:
			continue
		var xform: Transform3D = (inst as OccluderInstance3D).global_transform
		var verts := occ.vertices
		var idx := occ.indices
		for i in range(0, idx.size() - 2, 3):
			var a: Vector3 = xform * verts[idx[i]]
			var b: Vector3 = xform * verts[idx[i + 1]]
			var c: Vector3 = xform * verts[idx[i + 2]]
			var centre := (a + b + c) / 3.0
			var area := (b - a).cross(c - a).length() * 0.5
			for cls in places:
				if (places[cls] as AABB).has_point(centre):
					out[cls] = float(out.get(cls, 0.0)) + area
	return out


## The class of the node the door's mesh hangs from, and of its parent.
func _mover_of(container: Node3D, entity_name: String) -> String:
	if container == null:
		return "no baked container"
	var found := container.find_child(entity_name, true, false)
	if found == null:
		return "no node named %s" % entity_name
	return "%s under %s" % [found.get_class(), found.get_parent().get_class()]
