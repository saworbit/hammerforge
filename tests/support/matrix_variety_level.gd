extends RefCounted
## The level the action matrix builds for itself (#1648), with the kinds of brush
## the levels in `tests/levels/` do not hold: every brush there is a box square to
## the world. Turned and tilted boxes, a wedge, a pyramid, two prisms, cylinders
## and a cone, a box cut on a slant, a brush entity, a spiral stair's pieces, and
## neighbours for Merge, Carve and Clip to Face. Built the same way every time,
## so the matrix names its items the same way every time.

## What the matrix calls it beside the folders in tests/levels.
const NAME := "variety"


## Build it in `level`, which is in the tree and empty.
static func fill(level: Node, tree: SceneTree) -> void:
	# A palette, as the editor gives an empty level, so Material has a slot to give.
	level.add_prototype_materials()
	var shapes := LevelRoot.BrushShape
	_brush(level, shapes.BOX, Vector3(4, 2, 2), Vector3(0, 1, 0), Vector3(0, 30, 0))
	_brush(level, shapes.BOX, Vector3(2, 2, 2), Vector3(6, 2, 0), Vector3(20, 35, 0))
	_brush(level, shapes.WEDGE, Vector3(2, 2, 2), Vector3(12, 1, 0))
	_brush(level, shapes.PYRAMID, Vector3(2, 2, 2), Vector3(16, 1, 0))
	_brush(level, shapes.PRISM_TRI, Vector3(2, 2, 2), Vector3(20, 1, 0))
	_brush(level, shapes.PRISM_PENT, Vector3(2, 2, 2), Vector3(24, 1, 0))
	_brush(level, shapes.CYLINDER, Vector3(2, 2, 2), Vector3(28, 1, 0), Vector3.ZERO, 8)
	_brush(level, shapes.CYLINDER, Vector3(2, 4, 2), Vector3(32, 1, 0), Vector3(90, 0, 0), 12)
	_brush(level, shapes.CONE, Vector3(2, 2, 2), Vector3(36, 1, 0), Vector3.ZERO, 8)
	# A box cut on a slant, by the plane of a turned face.
	var slanted = _brush(level, shapes.BOX, Vector3(2, 4, 2), Vector3(40, 2, 0))
	var slope := Plane(Vector3(0.4, 1, 0).normalized(), Vector3(40, 2.5, 0))
	level.clip_brushes_by_plane([str(slanted.brush_id)], slope)
	# A brush entity.
	(
		level
		. create_brush_from_info(
			{
				"shape": shapes.BOX,
				"size": Vector3(2, 2, 2),
				"center": Vector3(44, 1, 0),
				"brush_entity_class": "func_detail",
			}
		)
	)
	# Two side by side, one Merge joins, and a turned one into them, for Carve.
	_brush(level, shapes.BOX, Vector3(2, 2, 2), Vector3(48, 1, 0))
	_brush(level, shapes.BOX, Vector3(2, 2, 2), Vector3(50, 1, 0))
	_brush(level, shapes.BOX, Vector3(1, 3, 1), Vector3(49, 1, 0), Vector3(0, 45, 0))
	# A structure's pieces.
	if level.has_method("create_generator"):
		level.create_generator(
			"spiral_stairs",
			level.generator_system.default_settings("spiral_stairs"),
			Transform3D(Basis.IDENTITY, Vector3(60, 0, 0))
		)
	await tree.process_frame


static func _brush(
	level: Node, shape: int, size: Vector3, center: Vector3, degrees := Vector3.ZERO, sides := 0
) -> Node:
	var info := {
		"shape": shape,
		"size": size,
		"center": center,
		"transform": Transform3D(Basis.from_euler(degrees * (PI / 180.0)), center),
	}
	if sides > 0:
		info["sides"] = sides
	return level.create_brush_from_info(info)
