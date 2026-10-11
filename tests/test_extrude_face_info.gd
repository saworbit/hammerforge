extends GutTest

## Extruding a face by its index, without a camera or a drag. The MCP bridge
## calls this, and the Extrude tool's own brush comes from the same code, so a
## drag and a call make the same brush.

const DraftBrush = preload("res://addons/hammerforge/brush_instance.gd")

## Box faces are stored +X, -X, +Y, -Y, +Z, -Z.
const TOP := 2

var root: LevelRoot


func before_each() -> void:
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.hflevel_autosave_enabled = false
	root.grid_snap = 1.0
	add_child_autoqfree(root)


func _box(brush_id: String) -> DraftBrush:
	var info := {
		"shape": LevelRoot.BrushShape.BOX,
		"size": Vector3(4, 2, 4),
		"transform": Transform3D(),
		"brush_id": brush_id,
	}
	return root.create_brush_from_info(info) as DraftBrush


func test_the_top_face_makes_a_box_on_top():
	_box("e1")
	var info: Dictionary = root.extrude_face_info("e1", TOP, 3.0)
	assert_false(info.is_empty())
	assert_eq(info["shape"], LevelRoot.BrushShape.BOX)
	assert_eq(info["operation"], CSGShape3D.OPERATION_UNION)
	assert_eq(info["size"], Vector3(4, 3, 4))
	var xform: Transform3D = info["transform"]
	assert_eq(xform.origin, Vector3(0, 2.5, 0))
	assert_ne(str(info.get("brush_id", "")), "", "an id minted for redo to keep")


func test_the_source_brush_is_left_alone():
	var brush := _box("e2")
	var before: Array = brush.serialize_faces()
	root.extrude_face_info("e2", TOP, 3.0)
	assert_eq(brush.serialize_faces(), before)
	assert_eq(root._iter_managed_brush_nodes().size(), 1, "the info is not a brush yet")


func test_a_side_face():
	_box("e3")
	var info: Dictionary = root.extrude_face_info("e3", 0, 2.0)
	assert_eq(info["size"], Vector3(2, 2, 4))
	assert_eq((info["transform"] as Transform3D).origin, Vector3(3, 0, 0))


func test_it_matches_what_the_extrude_tool_builds():
	var brush := _box("e4")
	var tool = root.extrude_tool
	assert_true(tool.begin_on_face(brush, TOP, tool.Direction.UP))
	var from_tool: Dictionary = tool._build_brush_info(3.0)
	tool.cancel_extrude()
	var from_call: Dictionary = root.extrude_face_info("e4", TOP, 3.0)
	assert_eq(from_call["size"], from_tool["size"])
	assert_eq(from_call["transform"], from_tool["transform"])
	assert_eq(from_call["shape"], from_tool["shape"])


func test_refusals():
	_box("e5")
	var counter: int = root._brush_id_counter
	assert_eq(root.extrude_face_info("e5", TOP, 0.0), {})
	assert_eq(root.extrude_face_info("e5", TOP, -1.0), {})
	assert_eq(root.extrude_face_info("e5", TOP, 300.0), {})
	assert_eq(root.extrude_face_info("e5", TOP, NAN), {})
	assert_eq(root.extrude_face_info("e5", 99, 1.0), {})
	assert_eq(root.extrude_face_info("e5", -1, 1.0), {})
	assert_eq(root.extrude_face_info("nope", TOP, 1.0), {})
	assert_eq(root.extrude_face_info("", TOP, 1.0), {})
	assert_eq(root._brush_id_counter, counter, "no id spent on a refusal")
