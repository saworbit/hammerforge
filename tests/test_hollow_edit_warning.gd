extends GutTest

## What a Re-hollow would undo, said before it undoes it.
##
## Live hollow gave the row a Re-hollow button. Nothing said that pressing it
## throws away a wall you had moved, resized or retextured on purpose — Detach sat
## beside it as the way out, but a choice you do not know you are making is not a
## choice.
##
## The reading is simpler here than it was for the array. The walls are not copies
## of each other, so there is nothing to group them against; each one is compared
## with the shape it was created as, which the record now keeps beside where it was
## put. Movement is read against what a re-shell would actually do: a room moved as
## a whole re-shells where it now stands and loses nothing, and walls that disagree
## about where the room is get rebuilt back at the recorded placement.

const DockScene = preload("res://addons/hammerforge/dock.tscn")
const SCENE_PATH := "user://hf_hollow_edit_warning_test.tscn"
const LEVEL_PATH := "user://hf_hollow_edit_warning_test.hflevel"

var dock: HammerForgeDock
var root: LevelRoot


func before_each() -> void:
	dock = DockScene.instantiate()
	add_child_autoqfree(dock)
	root = LevelRoot.new()
	root.auto_spawn_player = false
	root.commit_freeze = false
	root.hflevel_autosave_enabled = false
	add_child_autoqfree(root)
	dock.level_root = root


func after_each() -> void:
	dock = null
	root = null
	for path in [SCENE_PATH, LEVEL_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


func _a_brush(at: Vector3 = Vector3.ZERO) -> Node3D:
	var brush_id: String = root.brush_system._next_brush_id()
	var made = (
		root
		. brush_system
		. create_brush_from_info(
			{
				"shape": root.BrushShape.BOX,
				"size": Vector3(64, 64, 64),
				"operation": CSGShape3D.OPERATION_UNION,
				"brush_id": brush_id,
				"transform": Transform3D(Basis.IDENTITY, at),
			}
		)
	)
	assert_not_null(made, "the fixture needs a brush to hollow")
	return made


func _hollow(brush: Node3D, thickness: float = 4.0) -> Dictionary:
	var brush_id := str(root.get_brush_info_from_node(brush).get("brush_id", ""))
	var result: HFOpResult = root.brush_system.hollow_brush_by_id(brush_id, thickness)
	assert_true(result.ok, "the fixture needs a hollow: %s" % result.message)
	var record = root.brush_system.hollow_for_selection(_wall_ids_in_level())
	assert_not_null(record, "hollowing records the solid it shelled")
	return record


func _wall_ids_in_level() -> Array:
	var out: Array = []
	for child in root.draft_brushes_node.get_children():
		out.append(str(root.get_brush_info_from_node(child).get("brush_id", "")))
	return out


func _walls(record: Dictionary) -> Array:
	var out: Array = []
	for wall_id in record["wall_ids"]:
		var wall = root.brush_system.find_brush_by_id(str(wall_id))
		if is_instance_valid(wall):
			out.append(wall)
	return out


func _drag(brush: Node3D, by: Vector3) -> void:
	brush.global_position += by


func _repaint(brush: Node3D) -> void:
	root.brush_system._ensure_faces(brush)
	brush.get_faces()[0].material_idx = 7


## A solid with a stroke on every face, so each wall shelled from it starts with
## a paint layer of its own (#863).
func _a_painted_brush() -> Node3D:
	var brush := _a_brush()
	root.brush_system._ensure_faces(brush)
	for face in brush.get_faces():
		root.surface_paint.paint_at_uv(face, 0, Vector2(0.25, 0.25), 0.1, 1.0)
	return brush


## The first face of a wall that came out of the shell already painted.
func _inherited_face(wall: Node3D) -> FaceData:
	for face in wall.get_faces():
		if face != null and not face.paint_layers.is_empty():
			return face
	assert_true(false, "a wall of a painted solid starts with the solid's paint")
	return null


## A stroke the way the Paint tool lays one: into the layer the face already has,
## which adds no layer and resizes nothing.
func _stroke(face: FaceData) -> void:
	var layers := face.paint_layers.size()
	root.surface_paint.paint_at_uv(face, 0, Vector2(0.75, 0.75), 0.1, 1.0)
	assert_eq(face.paint_layers.size(), layers, "the stroke landed in an existing layer")


## The owners the editor assigns. Headless there is no edited scene, so without
## them `pack()` writes an empty scene.
func _own(node: Node) -> void:
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var next: Node = stack.pop_back()
		for child in next.get_children():
			child.owner = node
			stack.append(child)


## Save the level the way Ctrl+S does, and open the file again.
func _save_and_reopen() -> LevelRoot:
	root.owner = self
	_own(root)
	var packed := PackedScene.new()
	assert_eq(packed.pack(root), OK, "the level packs")
	assert_eq(ResourceSaver.save(packed, SCENE_PATH), OK, "the scene saves")
	var loaded := (
		ResourceLoader.load(SCENE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	)
	var copy := loaded.instantiate() as LevelRoot
	add_child_autoqfree(copy)
	return copy


func _edited(record: Dictionary) -> int:
	return root.edited_hollow_walls(str(record["hollow_id"]))


func _warning() -> String:
	return dock.hollow_warning.text if (dock.hollow_warning and dock.hollow_warning.visible) else ""


func _select(nodes: Array) -> void:
	dock.set_selection_nodes(nodes)


func _brush_count() -> int:
	return root.draft_brushes_node.get_child_count()


func _thickness_of(record: Dictionary) -> float:
	return float(root.hollow_for_id(str(record["hollow_id"]))["thickness"])


# ===========================================================================
# Reading what has happened to the walls
# ===========================================================================


func test_a_hollow_nobody_has_touched_counts_nothing():
	var record := _hollow(_a_brush())
	assert_eq(_edited(record), 0, "the walls are exactly as the shell left them")


func test_a_moved_wall_is_counted():
	var record := _hollow(_a_brush())
	_drag(_walls(record)[0], Vector3(0, 96, 0))
	assert_eq(_edited(record), 1)


func test_a_resized_wall_is_counted():
	var record := _hollow(_a_brush())
	_walls(record)[0].size = Vector3(96, 96, 96)
	assert_eq(_edited(record), 1, "a wall that has not moved can still have been reworked")


func test_a_repainted_wall_is_counted():
	var record := _hollow(_a_brush())
	_repaint(_walls(record)[0])
	assert_eq(_edited(record), 1)


func test_a_wall_both_moved_and_resized_is_counted_once():
	var record := _hollow(_a_brush())
	var wall: Node3D = _walls(record)[0]
	_drag(wall, Vector3(0, 96, 0))
	wall.size = Vector3(96, 96, 96)
	assert_eq(_edited(record), 1)


func test_two_reworked_walls_read_as_two():
	var record := _hollow(_a_brush())
	_drag(_walls(record)[0], Vector3(0, 96, 0))
	_repaint(_walls(record)[1])
	assert_eq(_edited(record), 2)


func test_a_room_relocated_as_a_whole_counts_nothing():
	# Dragging the room is not editing it. The re-shell follows it, so there is
	# nothing to lose and nothing to warn about.
	var record := _hollow(_a_brush())
	for wall in _walls(record):
		_drag(wall, Vector3(512, 0, 0))
	assert_eq(_edited(record), 0)


func test_a_room_turned_as_a_whole_counts_nothing():
	var record := _hollow(_a_brush())
	var turn := Transform3D(Basis(Vector3.UP, deg_to_rad(45.0)))
	for wall in _walls(record):
		wall.global_transform = turn * wall.global_transform
	assert_eq(_edited(record), 0)


func test_a_relocated_room_with_one_wall_pushed_further_counts_that_wall():
	# The walls no longer agree on one move, so the re-shell goes back to the
	# recorded placement and every wall standing anywhere else is about to move.
	var record := _hollow(_a_brush())
	var walls := _walls(record)
	for wall in walls:
		_drag(wall, Vector3(512, 0, 0))
	_drag(walls[0], Vector3(0, 96, 0))
	assert_eq(_edited(record), walls.size(), "the whole room is now standing off its record")


func test_a_wall_that_has_been_deleted_is_not_counted():
	var record := _hollow(_a_brush())
	root.brush_system.delete_brush_by_id(str(record["wall_ids"][0]))
	assert_eq(_edited(record), 0, "a wall that is gone cannot be rebuilt over")


func test_an_unknown_hollow_counts_nothing():
	assert_eq(root.edited_hollow_walls("hol_that_never_existed"), 0)


func test_a_record_from_before_the_new_fields_counts_nothing():
	# Older levels answer "cannot tell" rather than guessing, which is what lets
	# them load and re-shell with no migration.
	var record := _hollow(_a_brush())
	var stored: Dictionary = root.brush_system._hollows[str(record["hollow_id"])]
	stored.erase("wall_shapes")
	stored.erase("wall_transforms")
	stored.erase("wall_paint")
	var wall: Node3D = _walls(record)[0]
	_drag(wall, Vector3(0, 96, 0))
	wall.size = Vector3(96, 96, 96)
	assert_eq(_edited(record), 0)


func test_a_hollow_that_has_been_restored_is_not_reported_as_reworked():
	# An undo rebuilds every wall from its brush info. If that came back as a
	# different shape the row would warn after every Ctrl+Z.
	var record := _hollow(_a_brush())
	root.restore_state(root.capture_state())
	assert_eq(_edited(record), 0)


func test_re_hollowing_starts_the_count_again():
	var record := _hollow(_a_brush())
	_drag(_walls(record)[0], Vector3(0, 96, 0))
	root.update_hollow(str(record["hollow_id"]), 8.0)
	assert_eq(_edited(record), 0, "the walls it rebuilt are its own again")


# ===========================================================================
# A stroke inside a layer the wall started with (#869)
# ===========================================================================
#
# Walls keep the paint of the solid they were shelled from (#863), so a stroke on
# one can land in a layer it already has. That adds no layer and resizes none,
# which is all the shape signature sees of paint, so the record keeps what the
# masks held as well.


func test_a_stroke_inside_a_layer_the_wall_inherited_is_counted():
	var record := _hollow(_a_painted_brush())
	_stroke(_inherited_face(_walls(record)[0]))
	assert_eq(_edited(record), 1, "Re-hollow would put the solid's paint back over the stroke")


func test_the_walls_of_a_painted_solid_count_nothing_until_painted():
	var record := _hollow(_a_painted_brush())
	assert_eq(_edited(record), 0, "starting with the solid's paint is not a hand edit")


func test_strokes_on_two_walls_read_as_two():
	var record := _hollow(_a_painted_brush())
	_stroke(_inherited_face(_walls(record)[0]))
	_stroke(_inherited_face(_walls(record)[1]))
	assert_eq(_edited(record), 2)


func test_a_painted_hollow_that_has_been_restored_is_not_reported_as_reworked():
	# An undo rebuilds every wall from its brush info, which carries each mask as
	# a PNG. A mask that came back as different bytes would count every painted
	# wall after every Ctrl+Z.
	var record := _hollow(_a_painted_brush())
	root.restore_state(root.capture_state())
	assert_eq(_edited(record), 0)
	_stroke(_inherited_face(_walls(record)[0]))
	assert_eq(_edited(record), 1, "and a stroke after the undo is still seen")


func test_a_wall_s_paint_reads_the_same_after_the_scene_is_saved_and_reopened():
	# Ctrl+S keeps each mask as an Image in the scene, and opening the scene
	# rebuilds every box. Neither is a stroke.
	var record := _hollow(_a_painted_brush())
	var hollow_id := str(record["hollow_id"])
	var before := _inherited_face(_walls(record)[0])
	var copy := _save_and_reopen()
	var kept: Array = copy.hollow_for_id(hollow_id)["wall_paint"]
	var walls: Array = []
	for i in record["wall_ids"].size():
		var wall = copy.brush_system.find_brush_by_id(str(record["wall_ids"][i]))
		assert_true(is_instance_valid(wall), "wall %d came back with the scene" % i)
		assert_eq(HFDuplicator.paint_signature(wall), str(kept[i]), "wall %d" % i)
		walls.append(wall)
	var after := _inherited_face(walls[0])
	assert_ne(
		after.paint_layers[0].weight_image,
		before.paint_layers[0].weight_image,
		"the mask was read from the file, not shared with the level that saved it"
	)
	_stroke(after)
	assert_ne(
		HFDuplicator.paint_signature(walls[0]), str(kept[0]), "a stroke after reopening is seen"
	)


func test_a_painted_hollow_through_an_hflevel_is_not_reported_as_reworked():
	# Written here rather than through save_hflevel(), which writes on a thread.
	var record := _hollow(_a_painted_brush())
	assert_eq(
		HFLevelIO.save_to_path(LEVEL_PATH, root._capture_hflevel_state(), false),
		OK,
		"the level saves"
	)
	root.clear_brushes()
	assert_true(root.load_hflevel(LEVEL_PATH), "and loads")
	assert_eq(_edited(record), 0)
	_stroke(_inherited_face(_walls(record)[0]))
	assert_eq(_edited(record), 1)


func test_re_hollowing_a_stroked_room_starts_the_count_again():
	var record := _hollow(_a_painted_brush())
	_stroke(_inherited_face(_walls(record)[0]))
	root.update_hollow(str(record["hollow_id"]), 8.0)
	assert_eq(_edited(record), 0, "the rebuilt walls carry the solid's paint, which is theirs")


func test_a_record_from_before_masks_were_kept_cannot_see_a_stroke():
	# It answers "cannot tell" for that half, as for the shape and the placement,
	# so an older level loads and re-shells unmigrated and the rest still counts.
	var record := _hollow(_a_painted_brush())
	root.brush_system._hollows[str(record["hollow_id"])].erase("wall_paint")
	_stroke(_inherited_face(_walls(record)[0]))
	_walls(record)[1].size = Vector3(96, 96, 96)
	assert_eq(_edited(record), 1, "the resize is still seen, and the stroke cannot be")


func test_two_copies_of_one_painted_wall_have_one_paint_signature():
	# Values only, like the shape signature: the copy's masks are separate images
	# holding the same texels, and that has to read as the same paint.
	var record := _hollow(_a_painted_brush())
	var wall: Node3D = _walls(record)[0]
	var info: Dictionary = root.get_brush_info_from_node(wall)
	info["brush_id"] = root.brush_system._next_brush_id()
	var copy = root.brush_system.create_brush_from_info(info)
	assert_eq(HFDuplicator.paint_signature(copy), HFDuplicator.paint_signature(wall))
	_stroke(_inherited_face(copy))
	assert_ne(HFDuplicator.paint_signature(copy), HFDuplicator.paint_signature(wall))


func test_a_wall_s_paint_signature_does_not_depend_on_the_order_of_its_faces():
	# A box rebuild lists a cut piece's faces in the order the builder makes them
	# (#867), which moves no paint.
	var record := _hollow(_a_painted_brush())
	var wall: Node3D = _walls(record)[0]
	var before := HFDuplicator.paint_signature(wall)
	var reordered: Array[FaceData] = wall.faces.duplicate()
	reordered.reverse()
	wall.faces = reordered
	assert_eq(HFDuplicator.paint_signature(wall), before)


# ===========================================================================
# Through a save and reopen (#873)
# ===========================================================================
#
# Opening a scene rebuilds every box, and the rebuild lists the faces and their
# corners the way the box builder makes them. The walls are stored that way when
# they are made, so the rebuild changes nothing the record reads.


## A solid whose size and place are not whole numbers, so centring each wall on
## itself leaves float noise in every corner it computes.
func _an_off_grid_brush() -> Node3D:
	var brush_id: String = root.brush_system._next_brush_id()
	var made = (
		root
		. brush_system
		. create_brush_from_info(
			{
				"shape": root.BrushShape.BOX,
				"size": Vector3(50.6, 30.2, 70.4),
				"operation": CSGShape3D.OPERATION_UNION,
				"brush_id": brush_id,
				"transform": Transform3D(Basis.IDENTITY, Vector3(13.3, 7.1, -5.7)),
			}
		)
	)
	assert_not_null(made, "the fixture needs a brush to hollow")
	return made


## How many walls the reopened level counts, having checked that every wall was
## read from the file rather than shared with the level that saved it.
func _edited_after_reopening(record: Dictionary) -> int:
	var before: Array = []
	for wall in _walls(record):
		before.append(wall.faces[0])
	var copy := _save_and_reopen()
	for i in record["wall_ids"].size():
		var wall = copy.brush_system.find_brush_by_id(str(record["wall_ids"][i]))
		assert_true(is_instance_valid(wall), "wall %d came back with the scene" % i)
		if is_instance_valid(wall):
			assert_ne(wall.faces[0], before[i], "wall %d was read from the file" % i)
	return copy.edited_hollow_walls(str(record["hollow_id"]))


func test_an_untouched_hollow_counts_nothing_after_its_scene_is_reopened():
	var record := _hollow(_a_brush())
	assert_eq(_edited_after_reopening(record), 0, "a rebuild on open is not a hand edit")


func test_an_untouched_painted_hollow_counts_nothing_after_its_scene_is_reopened():
	var record := _hollow(_a_painted_brush())
	assert_eq(_edited_after_reopening(record), 0)


func test_a_hollow_off_the_grid_counts_nothing_after_its_scene_is_reopened():
	var record := _hollow(_an_off_grid_brush(), 3.3)
	assert_eq(_edited_after_reopening(record), 0)


func test_walls_reworked_before_the_save_are_still_counted_after_the_reopen():
	var record := _hollow(_a_painted_brush())
	var walls := _walls(record)
	_drag(walls[0], Vector3(0, 96, 0))
	walls[1].size = Vector3(96, 96, 96)
	_repaint(walls[2])
	_stroke(_inherited_face(walls[3]))
	assert_eq(_edited(record), 4, "four walls reworked four ways")
	assert_eq(_edited_after_reopening(record), 4, "and the reopen hides none of them")


# ===========================================================================
# What the section says
# ===========================================================================


func test_the_section_is_quiet_about_an_untouched_hollow():
	var record := _hollow(_a_brush())
	_select([_walls(record)[0]])
	assert_eq(_warning(), "")


func test_the_section_names_the_number_of_reworked_walls():
	var record := _hollow(_a_brush())
	_drag(_walls(record)[0], Vector3(0, 96, 0))
	_repaint(_walls(record)[1])
	_select([_walls(record)[2]])
	var text := _warning()
	assert_true(text.contains("2 walls have been reworked"), "got '%s'" % text)
	assert_true(text.contains("Detach"), "the way out belongs in the sentence: got '%s'" % text)


func test_one_reworked_wall_reads_as_one():
	var record := _hollow(_a_brush())
	_repaint(_walls(record)[0])
	_select([_walls(record)[1]])
	assert_true(_warning().contains("1 wall has been reworked"), "got '%s'" % _warning())


func test_the_warning_goes_when_the_selection_leaves_the_hollow():
	var record := _hollow(_a_brush())
	_repaint(_walls(record)[0])
	_select([_walls(record)[1]])
	assert_ne(_warning(), "")
	_select([_a_brush(Vector3(500, 0, 500))])
	assert_eq(_warning(), "")


# ===========================================================================
# The second press
# ===========================================================================


func test_the_first_press_over_a_reworked_wall_does_nothing():
	var record := _hollow(_a_brush(), 4.0)
	var reworked: Node3D = _walls(record)[0]
	_repaint(reworked)
	_select([_walls(record)[1]])
	dock.hollow_thickness.set_value_no_signal(12.0)
	HFDockBrushHandler.on_hollow(dock)
	assert_almost_eq(_thickness_of(record), 4.0, 0.001, "nothing was rebuilt on the first press")
	assert_true(is_instance_valid(reworked), "and the wall the user reworked is still there")


func test_the_second_press_goes_ahead():
	var record := _hollow(_a_brush(), 4.0)
	_repaint(_walls(record)[0])
	_select([_walls(record)[1]])
	dock.hollow_thickness.set_value_no_signal(12.0)
	HFDockBrushHandler.on_hollow(dock)
	HFDockBrushHandler.on_hollow(dock)
	assert_almost_eq(_thickness_of(record), 12.0, 0.001)


func test_a_stroke_on_a_wall_of_a_painted_solid_makes_re_hollow_ask_twice():
	var record := _hollow(_a_painted_brush(), 4.0)
	var stroked: Node3D = _walls(record)[0]
	_stroke(_inherited_face(stroked))
	_select([_walls(record)[1]])
	dock.hollow_thickness.set_value_no_signal(12.0)
	HFDockBrushHandler.on_hollow(dock)
	assert_almost_eq(_thickness_of(record), 4.0, 0.001, "nothing was rebuilt on the first press")
	assert_true(is_instance_valid(stroked), "and the wall with the stroke is still there")
	assert_true(_warning().contains("1 wall has been reworked"), "got '%s'" % _warning())
	HFDockBrushHandler.on_hollow(dock)
	assert_almost_eq(_thickness_of(record), 12.0, 0.001, "the second press goes ahead")


func test_changing_the_thickness_after_the_warning_earns_it_again():
	# The second press agrees to one particular re-shell, not to every re-shell
	# from here on.
	var record := _hollow(_a_brush(), 4.0)
	_repaint(_walls(record)[0])
	_select([_walls(record)[1]])
	dock.hollow_thickness.set_value_no_signal(12.0)
	HFDockBrushHandler.on_hollow(dock)
	dock.hollow_thickness.set_value_no_signal(10.0)
	HFDockBrushHandler.on_hollow(dock)
	assert_almost_eq(
		_thickness_of(record), 4.0, 0.001, "the changed thickness has not been agreed to yet"
	)


func test_an_untouched_hollow_re_hollows_on_the_first_press():
	var record := _hollow(_a_brush(), 4.0)
	_select([_walls(record)[0]])
	dock.hollow_thickness.set_value_no_signal(12.0)
	HFDockBrushHandler.on_hollow(dock)
	assert_almost_eq(_thickness_of(record), 12.0, 0.001, "there was nothing to warn about")


func test_a_relocated_room_re_hollows_on_the_first_press():
	# Following the room is what a live hollow is for, not something to agree to.
	var record := _hollow(_a_brush(), 4.0)
	for wall in _walls(record):
		_drag(wall, Vector3(512, 0, 0))
	_select([_walls(record)[0]])
	dock.hollow_thickness.set_value_no_signal(12.0)
	HFDockBrushHandler.on_hollow(dock)
	assert_almost_eq(_thickness_of(record), 12.0, 0.001)


func test_a_rebuild_puts_the_warning_away():
	var record := _hollow(_a_brush(), 4.0)
	_repaint(_walls(record)[0])
	_select([_walls(record)[1]])
	dock.hollow_thickness.set_value_no_signal(12.0)
	HFDockBrushHandler.on_hollow(dock)
	HFDockBrushHandler.on_hollow(dock)
	assert_eq(_warning(), "", "the walls are all the shell's own again")


func test_detaching_after_the_warning_forgets_the_agreement():
	var record := _hollow(_a_brush(), 4.0)
	_repaint(_walls(record)[0])
	_select([_walls(record)[1]])
	dock.hollow_thickness.set_value_no_signal(12.0)
	HFDockBrushHandler.on_hollow(dock)
	assert_ne(dock._hollow_overwrite_ack, "")
	HFDockBrushHandler.on_detach_hollow(dock)
	assert_eq(dock._hollow_overwrite_ack, "")
	assert_eq(_warning(), "")
	assert_eq(_brush_count(), 6, "detach deletes nothing")
