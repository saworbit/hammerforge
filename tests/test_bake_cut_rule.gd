extends GutTest

## What the bake cuts is one rule, `HFBakeSystem.is_structural_brush()`, and the
## places that show or predict a cut read it from there (#1563).
##
## Subtract Preview paired a cutter with every solid under it, brush entities
## included, and drew a cut through a `func_detail`, a `func_wall` or a `func_clip`
## that the bake left whole. This holds the rule to what the bake actually does,
## class by class, both ways round: a solid of the class under a world cutter, and
## a world solid under a cutter of the class.

const HFBakeSystem = preload("res://addons/hammerforge/systems/hf_bake_system.gd")
const HFEntityDefType = preload("res://addons/hammerforge/hf_entity_def.gd")

const ENTITIES := "res://addons/hammerforge/entities.json"
## A box standing at y 0.5 to 2.5, and a cutter wider than it taking its top half.
## Cut, the box tops out at 1.5; left whole, at 2.5.
const BOX_SIZE := Vector3(2, 2, 2)
const BOX_Y := 1.5
const CUT_SIZE := Vector3(4, 3, 4)
const CUT_Y := 3.0
const HALFWAY := 2.0
## Far enough apart that no cutter reaches another arrangement's box.
const SPACING := 10.0

var root: LevelRoot


func before_each():
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)


func after_each():
	root = null


func _box(center: Vector3, size: Vector3, subtract: bool, entity_class: String) -> DraftBrush:
	var op := CSGShape3D.OPERATION_SUBTRACTION if subtract else CSGShape3D.OPERATION_UNION
	var info := {"shape": LevelRoot.BrushShape.BOX, "size": size, "center": center, "operation": op}
	var brush := root.create_brush_from_info(info) as DraftBrush
	if entity_class != "":
		root.tie_brushes_to_entity([str(brush.brush_id)], entity_class)
	return brush


## The highest point the bake left over the box standing at `center`: the vertices
## of every baked mesh and every collision shape inside its outline from above. A
## clip and a trigger bake to collision alone, so the shapes count as well.
func _baked_top_over(center: Vector3) -> float:
	var reach := BOX_SIZE * 0.5 + Vector3(0.01, 0.0, 0.01)
	var top := -INF
	for node in root.baked_container.find_children("*", "", true, false):
		var mesh: Mesh = null
		if node is MeshInstance3D:
			mesh = (node as MeshInstance3D).mesh
		elif node is CollisionShape3D and (node as CollisionShape3D).shape:
			mesh = (node as CollisionShape3D).shape.get_debug_mesh()
		if mesh == null:
			continue
		var xform: Transform3D = (node as Node3D).global_transform
		for surface in mesh.get_surface_count():
			for vertex: Vector3 in mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				var point := xform * vertex
				if absf(point.x - center.x) <= reach.x and absf(point.z - center.z) <= reach.z:
					top = maxf(top, point.y)
	return top


func test_the_rule_and_the_bake_agree_on_every_brush_entity_class():
	# The world first, so the measure is seen to tell a cut box from a whole one.
	var classes: Array = [""]
	var defs := HFEntityDefType.load_definitions_from_file(ENTITIES)
	for def in HFEntityDefType.filter_brush_entities(defs):
		classes.append(def.classname)
	for wanted in ["func_detail", "func_wall", "func_clip"]:
		assert_has(classes, wanted, "read from entities.json")
	var solids: Array = []
	var cutters: Array = []
	for i in classes.size():
		var x := SPACING * i
		solids.append(_box(Vector3(x, BOX_Y, 0), BOX_SIZE, false, classes[i]))
		_box(Vector3(x, CUT_Y, 0), CUT_SIZE, true, "")
		_box(Vector3(x, BOX_Y, SPACING), BOX_SIZE, false, "")
		cutters.append(_box(Vector3(x, CUT_Y, SPACING), CUT_SIZE, true, classes[i]))
	assert_true(await root.bake(true, false, 0), "the level bakes")
	assert_not_null(root.baked_container)
	if root.baked_container == null:
		return
	for i in classes.size():
		var what := str(classes[i]) if classes[i] != "" else "world"
		var x := SPACING * i
		var top := _baked_top_over(Vector3(x, 0, 0))
		assert_gt(top, 0.0, "%s: the solid baked into something" % what)
		assert_eq(
			top < HALFWAY,
			HFBakeSystem.is_structural_brush(solids[i]),
			"%s solid under a world cutter: cut only if the rule says so (top %.2f)" % [what, top]
		)
		top = _baked_top_over(Vector3(x, 0, SPACING))
		assert_gt(top, 0.0, "%s: the world solid baked" % what)
		assert_eq(
			top < HALFWAY,
			HFBakeSystem.is_structural_brush(cutters[i]),
			"world solid under a %s cutter: cut only if the rule says so (top %.2f)" % [what, top]
		)
