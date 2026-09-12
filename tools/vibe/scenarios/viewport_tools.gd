@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## The three tools that put nodes in the scene without going through the brush
## CRUD: Extrude, Decal and Measure.
##
## Each one adds children to the level while it is running -- a ghost brush, a
## `Decal`, a mesh and a pile of `Label3D`s. The contract for a node like that is
## the same as for any other preview: it must not be counted, must not be saved,
## must not be baked, and must not outlive the gesture. And whatever the tool
## finally commits has to be undoable and has to survive a round trip, or the
## work is gone.

const ExtrudeTool = preload("res://addons/hammerforge/hf_extrude_tool.gd")
const DecalTool = preload("res://addons/hammerforge/hf_decal_tool.gd")
const MeasureTool = preload("res://addons/hammerforge/hf_measure_tool.gd")


func id() -> String:
	return "viewport-tools"


func summary() -> String:
	return "extrude, decal and measure: what their scene nodes do to the count, the save and the bake"


func run() -> void:
	await _extrude_preview_is_a_real_brush()
	await _extrude_ids()
	await _decals_and_the_level()
	await _measure_tool_state()
	await _extrude_preview_placement()
	await _decals_through_a_save()


func _bid(node: Node) -> String:
	return str(node.get_meta("brush_id", ""))


## Start an extrusion off a real face the way `begin_extrude()` does, without a
## camera: everything after `pick_face()` is pure geometry.
func _arm_extrude(root: Node3D, brush: Node) -> Object:
	var tool_instance = ExtrudeTool.new(root)
	var face = brush.faces[0]
	face.ensure_geometry()
	tool_instance.source_brush = brush
	tool_instance.source_face_idx = 0
	tool_instance.source_face_normal = (brush.global_transform.basis * face.normal).normalized()
	tool_instance.source_face_center = tool_instance._compute_face_center(brush, face)
	tool_instance.source_face_size = tool_instance._compute_face_extents(face)
	tool_instance._snap = 16.0
	tool_instance.active = true
	return tool_instance


## The extrude ghost is a `DraftBrush` parented into `draft_brushes_node`, which
## is the container everything authoritative iterates. Every other preview in
## the editor is either held off to one side or excluded by name.
func _extrude_preview_is_a_real_brush() -> void:
	var root: Node3D = await fresh_root()
	var b := box(root, Vector3(128, 64, 128))
	await frame()

	var before_count: int = root.brush_system.get_live_brush_count()
	var before_state := HFVibe.describe_level(root)
	var before_managed: int = root._iter_managed_brush_nodes().size()

	var extrude := _arm_extrude(root, b)
	extrude._update_preview(64.0)
	await frame()

	var during_managed: int = root._iter_managed_brush_nodes().size()
	note("managed brush nodes before the extrude ghost", before_managed)
	note("managed brush nodes while the ghost is up", during_managed)
	if during_managed > before_managed:
		known(
			400,
			"the extrude preview is counted as a managed brush",
			(
				"_ExtrudePreview is parented into draft_brushes_node, so _iter_managed_brush_nodes()"
				+ " returns it: %d -> %d" % [before_managed, during_managed]
			)
		)

	var during_state := HFVibe.describe_level(root)
	if HFVibe.canonical(before_state["brushes"]) != HFVibe.canonical(during_state["brushes"]):
		known(
			400,
			"the extrude preview reaches capture_state",
			"a save or an undo snapshot taken mid-drag stores the ghost as a brush"
		)

	# Snap candidates are the other thing that walks the containers.
	root.snap_system.enabled_modes = root.snap_system.SnapMode.VERTEX
	var candidates = root.snap_system._collect_candidates([])
	note("snap candidates with the ghost up", candidates.size())

	await root.bake_dirty()
	await frame()
	note("bake with the ghost up: brush count", root.brush_system.get_live_brush_count())

	extrude.cancel_extrude()
	await frame()
	await frame()
	var after_managed: int = root._iter_managed_brush_nodes().size()
	if after_managed != before_managed:
		flag(
			"the extrude ghost outlives the cancel",
			"%d managed nodes before, %d after cancel_extrude()" % [before_managed, after_managed]
		)
	note("live brush count after cancel", root.brush_system.get_live_brush_count())
	for issue in HFVibe.check_invariants(root):
		flag("invariant after an extrude preview", issue)


## Every other brush id in the editor carries a per-session prefix so two
## levels can never name the same brush. The extrude tool mints its own from
## the millisecond clock.
func _extrude_ids() -> void:
	var root: Node3D = await fresh_root()
	var b := box(root, Vector3(128, 64, 128))
	await frame()
	var natural := _bid(b)
	note("id from the ordinary create path", natural)

	var extrude := _arm_extrude(root, b)
	var first: Dictionary = extrude._build_brush_info(32.0)
	var second: Dictionary = extrude._build_brush_info(64.0)
	note("id the extrude tool mints", first.get("brush_id", ""))
	if first.get("brush_id", "") == second.get("brush_id", ""):
		known(
			402,
			"two extrusions in the same millisecond claim the same brush id",
			(
				(
					"_generate_extrude_id() is 'extrude_<dir>_<ticks_msec>': %s twice."
					% first.get("brush_id", "")
				)
				+ " Nothing else in the editor mints an id without the session prefix"
			)
		)
	extrude.cancel_extrude()


## A decal is a plain `Decal` node added under the level root with an owner set.
## Nothing in the level format knows about it.
func _decals_and_the_level() -> void:
	var root: Node3D = await fresh_root()
	box(root, Vector3(128, 64, 128))
	await frame()

	var decal_tool = DecalTool.new()
	decal_tool.root = root
	decal_tool.is_active = true
	decal_tool._place_decal(Vector3(0, 32, 0), Vector3.UP)
	await frame()

	var decals := _count_decals(root)
	note("decals in the level after placing one", decals)

	var state: Dictionary = root.state_system.capture_state(true)
	note("capture_state keys", state.keys())
	var has_decals := false
	for k in state.keys():
		if str(k).findn("decal") >= 0:
			has_decals = true
	if not has_decals:
		known(
			403,
			"a placed decal is not part of the level state",
			(
				"capture_state() has no decal key, so a decal is lost by every undo that"
				+ " restores state, by .hflevel save/load, and by the bake"
			)
		)

	root.state_system.restore_state(state)
	await frame()
	var after_restore := _count_decals(root)
	note("decals after a restore_state round trip", after_restore)
	if after_restore != decals:
		flag(
			"restore_state loses placed decals",
			(
				"%d decals before, %d after -- and every undo goes through restore_state"
				% [decals, after_restore]
			)
		)

	# Placing one twice in a row: both are called "HFDecal".
	decal_tool._place_decal(Vector3(64, 32, 0), Vector3.UP)
	await frame()
	note("decal node names", _decal_names(root))
	for issue in HFVibe.check_invariants(root):
		flag("invariant after placing decals", issue)


func _count_decals(root: Node3D) -> int:
	var n := 0
	var stack: Array = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			if child is Decal:
				n += 1
			stack.append(child)
	return n


func _decal_names(root: Node3D) -> Array:
	var names: Array = []
	for child in root.get_children():
		if child is Decal:
			names.append(child.name)
	return names


## The measure tool owns one piece of level state that outlives it: the custom
## snap line it installs on the snap system.
func _measure_tool_state() -> void:
	var root: Node3D = await fresh_root()
	box(root, Vector3(128, 64, 128))
	await frame()

	var measure = MeasureTool.new()
	measure.root = root
	measure.is_active = true
	measure._pending_point = Vector3(0, 0, 0)
	measure._has_pending = true
	measure._finish_ruler(Vector3(128, 0, 0))
	measure._pending_point = Vector3(0, 0, 128)
	measure._has_pending = true
	measure._finish_ruler(Vector3(128, 0, 128))
	await frame()
	note("rulers", measure._measurements.size())

	# Pick the first ruler as the align reference, the way Ctrl+Click does.
	measure._snap_ref_index = 0
	measure._align_active = true
	measure._apply_snap_reference()
	note("snap line installed", root.snap_system._has_custom_snap)

	measure._toggle_align()
	note("align off: reference index", measure._snap_ref_index)
	measure._toggle_align()
	note("align on again: reference index", measure._snap_ref_index)
	if measure._snap_ref_index != 0:
		known(
			405,
			"toggling align off forgets which ruler was the reference",
			(
				"_toggle_align() turns it off through _remove_snap_reference(), which sets"
				+ " _snap_ref_index back to -1, so turning it on again silently picks the"
				+ (
					" newest ruler (%d) instead of the one that was chosen (0)."
					% measure._snap_ref_index
				)
			)
		)

	# The tool's own nodes: a mesh and one Label3D per ruler, parented to the level.
	measure._update_visuals()
	await frame()
	note("labels the measure tool parents to the level", measure._labels.size())
	var state := HFVibe.describe_level(root)
	note(
		"brushes with the measure overlay up",
		state["brushes"].size() if state.has("brushes") else -1
	)

	# A ruler with both ends in the same place: a zero-length snap direction.
	measure._pending_point = Vector3(500, 0, 500)
	measure._has_pending = true
	measure._finish_ruler(Vector3(500, 0, 500))
	measure._snap_ref_index = measure._measurements.size() - 1
	measure._align_active = true
	measure._apply_snap_reference()
	var snapped: Vector3 = root.snap_system.snap_point(Vector3(10, 10, 10), 0.0)
	note("snap_point with a zero-length ruler as reference", snapped)

	measure.deactivate()
	await frame()
	if root.snap_system._has_custom_snap:
		flag("the custom snap line survives the measure tool's deactivate()")
	for issue in HFVibe.check_invariants(root):
		flag("invariant after the measure tool", issue)


## The ghost is positioned with `global_position` and `global_transform.basis`
## before it is added to the tree. Both are tree-relative operations.
func _extrude_preview_placement() -> void:
	var root: Node3D = await fresh_root()
	var b := box(root, Vector3(128, 64, 128))
	b.rotation = Vector3(0.0, deg_to_rad(45.0), 0.0)
	await frame()

	var extrude := _arm_extrude(root, b)
	var wanted_centre: Vector3 = extrude.source_face_center
	extrude._update_preview(64.0)
	await frame()
	var ghost: Node3D = null
	for child in root.draft_brushes_node.get_children():
		if str(child.name).begins_with("_ExtrudePreview"):
			ghost = child
	if ghost == null:
		note("no extrude ghost found")
		return
	var expected: Vector3 = wanted_centre + extrude._extrude_axis() * 32.0
	note("face centre the extrusion starts from", wanted_centre)
	note("where the ghost should sit", expected)
	note("ghost position", ghost.global_position)
	if not ghost.global_position.is_equal_approx(expected):
		known(
			401,
			"the extrude ghost is placed at the wrong point",
			(
				"_update_preview() writes global_position before add_child(), so the write"
				+ " lands on a node outside the tree -- the engine prints 'Condition"
				+ (
					" !is_inside_tree() is true' twice and the ghost ends up at %s instead of %s"
					% [ghost.global_position, expected]
				)
			)
		)
	note("source brush basis y-rotation (deg)", rad_to_deg(b.rotation.y))
	note("ghost basis y-rotation (deg)", rad_to_deg(ghost.rotation.y))
	if not ghost.basis.is_equal_approx(b.global_transform.basis):
		known(
			401,
			"the extrude ghost does not take the rotation of the brush it comes from",
			(
				"_update_preview() writes global_position and global_transform.basis before"
				+ " add_child(), so both go to a node that is not in the tree yet -- the engine"
				+ " prints 'Condition !is_inside_tree() is true' and the ghost keeps identity"
				+ (
					" basis. Source y-rotation %.1f deg, ghost %.1f deg"
					% [rad_to_deg(b.rotation.y), rad_to_deg(ghost.rotation.y)]
				)
			)
		)
	extrude.cancel_extrude()


## What a save and a reload do to a placed decal.
func _decals_through_a_save() -> void:
	var root: Node3D = await fresh_root()
	box(root, Vector3(128, 64, 128))
	await frame()
	var decal_tool = DecalTool.new()
	decal_tool.root = root
	decal_tool.is_active = true
	decal_tool._place_decal(Vector3(0, 32, 0), Vector3.UP)
	await frame()
	note("decals before the save", _count_decals(root))

	var path := "user://vibe_decals.hflevel"
	root.save_hflevel(path)
	var settled: bool = await HFVibe.settle_save(_tree, root)
	if not settled:
		note("save did not settle")
		return
	note("saved bytes", HFVibe.file_size(path))

	var reloaded: Node3D = await fresh_root("Reloaded")
	reloaded.load_hflevel(path)
	await frame()
	await frame()
	note("brushes after the reload", reloaded.brush_system.get_live_brush_count())
	var after := _count_decals(reloaded)
	note("decals after the reload", after)
	if after == 0:
		known(
			403,
			"a placed decal does not survive a .hflevel round trip",
			"one decal placed, the level saved and loaded, no decal in the loaded level"
		)
