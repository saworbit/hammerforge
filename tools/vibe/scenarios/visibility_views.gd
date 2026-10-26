@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Views (#1795, #1697): hide the selection, isolate, Previous Visibility, saved
## views, the visgroup lock (#1798), a current visgroup and one left out of the
## bake (#1783), and View Filters (#1840).
##
## The guide says these change what is shown without changing the level, that
## "Ctrl+Z never undoes a visibility change", and that locking is a view change
## and not an undo step. A whole-level undo restores the visgroup records, and
## the lock and the eye are fields of those records. It also asks whether a lock
## holds against tools that reach brushes other than the selection (Carve, a
## texture group), whether a saved view follows a renamed visgroup, and whether a
## visgroup left out of the bake stays out of every export.
##
## `visibility-workflow` asserts the opposite of the first flag here: that a
## restore of a snapshot taken while a visgroup was hidden hides it again. The
## two cannot both be right; the guide sides with this one.

const SAVE_PATH := "user://vibe_visibility_views.hflevel"
const PLAYTEST_PATH := "user://vibe_visibility_views_playtest.tscn"
const PluginRig = preload("res://tests/support/plugin_rig.gd")
const HFPluginGroups = preload("res://addons/hammerforge/plugin_groups.gd")
const HFPluginEditActions = preload("res://addons/hammerforge/plugin_edit_actions.gd")

var rig = null
var _host: Node = null


func id() -> String:
	return "visibility-views"


func summary() -> String:
	return "views, isolate, lock, current visgroup and filters through undo, save and bake"


func expected_issues() -> Array[int]:
	return [1973, 1978, 1979, 1980, 1981]


func run() -> void:
	await _view_state_through_a_whole_level_undo()
	await _isolate_through_an_undo()
	await _saved_views_and_a_rename()
	await _hide_selection_through_delete_and_undo()
	await _views_through_a_save()
	await _left_out_of_bake_entities()
	await _a_locked_brush_against_carve_and_texture_groups()
	_host = Node.new()
	_host.name = "VibeRigHost"
	_tree.root.add_child(_host)
	rig = PluginRig.new()
	await rig.bring_up(_host, true)
	if rig.plugin == null:
		flag("the plugin stand-in did not come up", rig.error())
	else:
		await _view_state_through_the_plugins_undo()
	await rig.take_down()
	_host.queue_free()
	await frame()
	for path in [SAVE_PATH, PLAYTEST_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _bid(node: Node) -> String:
	return str(node.get_meta("brush_id", ""))


func _shown(root: Node3D) -> Array:
	var out: Array = []
	for b in root.draft_brushes_node.get_children():
		if (b as Node3D).visible:
			out.append(_bid(b))
	out.sort()
	return out


func _four(root: Node3D) -> Array:
	var out: Array = []
	for i in 4:
		out.append(box(root, Vector3(2, 2, 2), Vector3(i * 5.0, 1, 0)))
	return out


## A view change is not an undo step, so an undo of an edit made before it
## should leave it as it is.
func _view_state_through_a_whole_level_undo() -> void:
	var root: Node3D = await fresh_root()
	var vg = root.visgroup_system
	var bs := _four(root)
	root.create_visgroup("Done")
	root.add_selection_to_visgroup("Done", [bs[2]])
	root.create_visgroup("Roof")
	root.add_selection_to_visgroup("Roof", [bs[3]])
	await frame()
	# An edit, as a whole-level step: group the first two.
	var before_edit: Dictionary = root.capture_state()
	vg.group_units("Pair", [bs[0], bs[1]])
	var after_edit: Dictionary = root.capture_state()
	# Then two view changes.
	vg.set_visgroup_locked("Done", true)
	vg.set_visgroup_visible("Roof", false)
	await frame()
	root.restore_state(before_edit)
	await frame()
	var locked_after_undo: bool = vg.is_visgroup_locked("Done")
	var roof_after_undo: bool = vg.is_visgroup_visible("Roof")
	root.restore_state(after_edit)
	await frame()
	var locked_after_redo: bool = vg.is_visgroup_locked("Done")
	note(
		"Done locked after undoing an earlier edit, and after redoing it",
		[locked_after_undo, locked_after_redo]
	)
	note("Roof shown after undoing an earlier edit (it was hidden)", roof_after_undo)
	if not locked_after_undo or not locked_after_redo or roof_after_undo:
		known(
			1981,
			"undoing or redoing an edit made before a lock or a hide unlocks or shows the visgroup again",
			(
				(
					"Done was locked and Roof hidden after a Group Selection; after its undo Done is locked=%s and Roof shown=%s, after the redo locked=%s. "
					+ "The guide says Ctrl+Z never undoes a visibility change and that locking is a view change, not an undo step, but both are fields of the visgroup record capture_state() takes, and restore_visgroups() puts back the record from the snapshot"
				)
				% [locked_after_undo, roof_after_undo, locked_after_redo]
			)
		)
	await drop_root(root)


## Isolate sets every visgroup's eye; an undo of an earlier edit then puts back
## the eyes from before it, while the isolate still thinks it is on.
func _isolate_through_an_undo() -> void:
	var root: Node3D = await fresh_root()
	var vg = root.visgroup_system
	var bs := _four(root)
	root.create_visgroup("Upper")
	root.add_selection_to_visgroup("Upper", [bs[0]])
	root.create_visgroup("Lower")
	root.add_selection_to_visgroup("Lower", [bs[1]])
	await frame()
	var before_edit: Dictionary = root.capture_state()
	vg.group_units("Pair", [bs[2], bs[3]])
	vg.isolate_visgroups(["Upper"])
	await frame()
	var isolated := _shown(root)
	root.restore_state(before_edit)
	await frame()
	var after_undo := _shown(root)
	var still_isolating: bool = vg.is_isolating()
	note("isolate Upper: shown", isolated)
	note(
		"after undoing the group made before it: shown, still isolating",
		[after_undo, still_isolating]
	)
	vg.end_isolate()
	await frame()
	note("after End Isolate: shown", _shown(root))
	if after_undo != isolated:
		known(
			1981,
			"an undo of an edit made before an isolate or a Hide Selection undoes them",
			(
				(
					"isolating Upper showed %s; after undoing an earlier Group Selection %s are shown while is_isolating() is still %s. "
					+ "The undo puts back the visgroup eyes the isolate set, and the brushes it rebuilt are new nodes, which _view_hidden (keyed by node) does not hold. A brush hidden with Hide Selection comes back the same way after a delete and its undo (below)"
				)
				% [isolated, after_undo, still_isolating]
			)
		)
	await drop_root(root)


## A saved view names its visgroups. Rename one and the view loses its hold on it.
func _saved_views_and_a_rename() -> void:
	var root: Node3D = await fresh_root()
	var vg = root.visgroup_system
	var bs := _four(root)
	root.create_visgroup("Upper")
	root.add_selection_to_visgroup("Upper", [bs[0]])
	root.create_visgroup("Lower")
	root.add_selection_to_visgroup("Lower", [bs[1]])
	root.set_visgroup_visible("Lower", false)
	await frame()
	root.save_visibility_view("Upper only")
	note("saved views", vg.saved_views)
	root.rename_visgroup("Lower", "Basement")
	note("saved views after renaming Lower to Basement", vg.saved_views)
	root.set_visgroup_visible("Basement", true)
	await frame()
	vg.restore_saved_view("Upper only")
	await frame()
	var basement_shown: bool = vg.is_visgroup_visible("Basement")
	note("Basement shown after showing 'Upper only' (it was saved hidden)", basement_shown)
	if basement_shown:
		known(
			1979,
			"renaming a visgroup takes it out of every saved view",
			"'Upper only' was saved with Lower hidden; after renaming Lower to Basement the view still says {Lower: false}, so Show leaves Basement shown -- rename_visgroup() renames the record, the current visgroup and the members, and not saved_views"
		)
	# A name typed with spaces is kept trimmed, and asked for as typed.
	note("save_view(' Lit ')", vg.save_view(" Lit "))
	note("restore_saved_view(' Lit ')", vg.restore_saved_view(" Lit "))
	note("save_view('   ')", vg.save_view("   "))
	await drop_root(root)


## Hide Selection holds the node. Anything that rebuilds it shows it again.
func _hide_selection_through_delete_and_undo() -> void:
	var root: Node3D = await fresh_root()
	var vg = root.visgroup_system
	var bs := _four(root)
	var id := _bid(bs[0])
	vg.hide_from_view([bs[0]])
	await frame()
	note("hidden by Hide Selection", not bs[0].visible)
	var before: Dictionary = root.capture_state()
	root.delete_brush_by_id(id)
	await frame()
	root.restore_state(before)
	await frame()
	var back = root.find_brush_by_id(id)
	note("after a delete and its undo: visible", back.visible if back else null)
	note("view hidden count", vg.view_hidden_nodes().size())
	await drop_root(root)


## Hide Selection and an isolate are not saved; the lock is.
func _views_through_a_save() -> void:
	var root: Node3D = await fresh_root()
	var vg = root.visgroup_system
	var bs := _four(root)
	root.create_visgroup("Upper")
	root.add_selection_to_visgroup("Upper", [bs[0]])
	root.create_visgroup("Lower")
	root.add_selection_to_visgroup("Lower", [bs[1]])
	root.create_visgroup("Safe")
	root.add_selection_to_visgroup("Safe", [bs[2]])
	vg.set_visgroup_locked("Safe", true)
	vg.isolate_visgroups(["Upper"])
	await frame()
	root.save_hflevel(SAVE_PATH, true)
	await HFVibe.settle_save(_tree, root)
	await drop_root(root)
	var other: Node3D = await fresh_root("Loaded")
	other.load_hflevel(SAVE_PATH)
	await frame()
	var ovg = other.visgroup_system
	note("after a save made during an isolate: Lower shown", ovg.is_visgroup_visible("Lower"))
	note("Safe still locked", ovg.is_visgroup_locked("Safe"))
	note("shown", _shown(other))
	if not ovg.is_visgroup_locked("Safe"):
		flag("a locked visgroup comes back unlocked from a .hflevel")
	await drop_root(other)


## A visgroup left out of the bake: brushes are, and the `.map` leaves its
## entities out as well. What does the playtest scene do with them?
func _left_out_of_bake_entities() -> void:
	var root: Node3D = await fresh_root()
	box(root, Vector3(8, 0.5, 8), Vector3(0, -0.25, 0))
	var guide := box(root, Vector3(2, 2, 2), Vector3(0, 1, 0))
	var lamp = root._create_entity_from_map(
		{"classname": "light_point", "origin": Vector3(0, 3, 0)}
	)
	lamp.set_meta("entity_name", "guide_lamp")
	root.create_visgroup("Guides")
	root.add_selection_to_visgroup("Guides", [guide, lamp])
	root.set_visgroup_bakes("Guides", false)
	await frame()
	note("left out count", root.visgroup_system.left_out_count())
	await root.bake()
	await frame()
	var map_path := "user://vibe_visibility_views.map"
	root.export_map(map_path, "valve220")
	var text := FileAccess.get_file_as_string(map_path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(map_path))
	note(".map holds the left-out lamp", text.find("light_point") >= 0)
	var ok: bool = root.export_playtest_scene(PLAYTEST_PATH)
	var scene: PackedScene = load(PLAYTEST_PATH) if ok else null
	var lamps := 0
	if scene:
		var inst := scene.instantiate()
		for node in inst.find_children("*", "", true, false):
			if str(node.name).to_lower().find("draftentity") >= 0 or node is Light3D:
				if (
					node is OmniLight3D
					or str(node.get_meta("entity_class", "")) == "light_point"
					or str(node.get("entity_class")) == "light_point"
				):
					lamps += 1
		inst.free()
	note("playtest scene: light_point copies", lamps)
	if lamps > 0:
		known(
			1980,
			"the playtest and Export Game Scene ship the entities of a visgroup left out of the bake",
			(
				"a light_point in 'Guides' (Leave out of bake) is left out of the .map and counted by left_out_count(), and the exported scene still holds %d -- export_playtest_scene(), which Export Game Scene runs, copies every entity but a note and never asks is_left_out_of_bake(); #1732 says such a visgroup is in no bake and no export, and never ships"
				% lamps
			)
		)
	await drop_root(root)


## The lock promises nothing changes a locked brush. Carve cuts what the carver
## overlaps, not what is selected, and a texture group spreads a change to every
## face in it.
func _a_locked_brush_against_carve_and_texture_groups() -> void:
	var root: Node3D = await fresh_root()
	var vg = root.visgroup_system
	var free := box(root, Vector3(4, 4, 4), Vector3(0, 2, 0))
	var done := box(root, Vector3(4, 4, 4), Vector3(4, 2, 0))
	root.create_visgroup("Done")
	root.add_selection_to_visgroup("Done", [done])
	await frame()
	# A texture group across the two +Z faces, made before the lock.
	var free_key: String = root.brush_system.face_key(free)
	var done_key: String = root.brush_system.face_key(done)
	var free_face := _face_facing(free, Vector3.BACK)
	var done_face := _face_facing(done, Vector3.BACK)
	root.face_selection = {free_key: [free_face], done_key: [done_face]}
	root.brush_system.link_selected_faces()
	vg.set_visgroup_locked("Done", true)
	var done_id := _bid(done)
	var before: Dictionary = root.get_brush_info_from_node(done)
	# Scale the free face's texture: its group mate is the locked one.
	root.face_selection = {free_key: [free_face]}
	root.edit_selected_face_uvs("scale_up")
	var after_uv: Dictionary = root.get_brush_info_from_node(root.find_brush_by_id(done_id))
	note(
		"locked face's uv_scale before, after scaling its unlocked group mate",
		[before["faces"][done_face]["uv_scale"], after_uv["faces"][done_face]["uv_scale"]]
	)
	if HFVibe.canonical(before) != HFVibe.canonical(after_uv):
		known(
			1978,
			"scaling a face's texture changes its texture-group mate on a locked brush",
			(
				"uv_scale %s -> %s on the locked brush's face; spread_texture_groups() lays every face of the group without asking is_locked()"
				% [before["faces"][done_face]["uv_scale"], after_uv["faces"][done_face]["uv_scale"]]
			)
		)
	# Carve with an unlocked carver that overlaps both.
	var carver := box(root, Vector3(1, 1, 8), Vector3(2, 2, 0))
	var locked_info := HFVibe.canonical(
		root.get_brush_info_from_node(root.find_brush_by_id(done_id))
	)
	var result = root.carve_with_brush(_bid(carver))
	await frame()
	var still = root.find_brush_by_id(done_id)
	var pieces := 0
	for b in root.draft_brushes_node.get_children():
		if vg.get_visgroups_of(b).has("Done"):
			pieces += 1
	note("carve result", result.message if result else null)
	note("locked brush after carve: still there, pieces in Done", [still != null, pieces])
	if still == null or HFVibe.canonical(root.get_brush_info_from_node(still)) != locked_info:
		known(
			1973,
			"Carve cuts a brush in a locked visgroup",
			(
				"an unlocked carver overlapping a locked brush cut it into %d pieces (%s); _overlapping_brushes() leaves out hidden brushes and never asks is_locked()"
				% [pieces, result.message if result else ""]
			)
		)
	await drop_root(root)


func _face_facing(brush: Node, normal: Vector3) -> int:
	var faces: Array = brush.faces
	for i in faces.size():
		if (faces[i].normal as Vector3).dot(normal) > 0.9:
			return i
	return -1


## The same through the plugin's own commands and its undo manager.
func _view_state_through_the_plugins_undo() -> void:
	var level = await rig.make_level()
	level.grid_snap = 1.0
	var vg = level.visgroup_system
	var a = rig.box(level, "a", Vector3(0, 1, 0), Vector3(2, 2, 2))
	var b = rig.box(level, "b", Vector3(5, 1, 0), Vector3(2, 2, 2))
	var c = rig.box(level, "c", Vector3(10, 1, 0), Vector3(2, 2, 2))
	rig.box(level, "d", Vector3(15, 1, 0), Vector3(2, 2, 2))
	level.create_visgroup("Done")
	level.add_selection_to_visgroup("Done", [c])
	rig.undo().clear()
	rig.select([a, b])
	await rig.frame()
	HFPluginGroups._group_as(rig.plugin, level, [a, b], "Pair")
	vg.set_visgroup_locked("Done", true)
	rig.undo().press_undo()
	await rig.frame()
	var after_undo: bool = vg.is_visgroup_locked("Done")
	rig.undo().press_redo()
	await rig.frame()
	note(
		"plugin: Done locked after Ctrl+Z, Ctrl+Shift+Z of Group Selection",
		[after_undo, vg.is_visgroup_locked("Done")]
	)
	# And the brush in it can then be selected and deleted.
	rig.select([level.find_brush_by_id("c")])
	await rig.frame()
	note(
		"plugin: c selectable afterwards",
		rig.plugin.stand_in_editor.selection.get_selected_nodes().size() == 1
	)
	# Hide Selection after a nudge, then Ctrl+Z of the nudge (a scoped step).
	vg.set_visgroup_locked("Done", false)
	rig.undo().clear()
	rig.select([level.find_brush_by_id("d")])
	await rig.frame()
	HFPluginEditActions.nudge_selected(rig.plugin, level, Vector3.RIGHT)
	await rig.frame()
	rig.select([level.find_brush_by_id("d")])
	await rig.frame()
	rig.plugin._on_hotkey_palette_action("hide_selection")
	await rig.frame()
	rig.undo().press_undo()
	await rig.frame()
	note(
		"plugin: Hide Selection'd d after Ctrl+Z of its nudge: visible",
		level.find_brush_by_id("d").visible
	)
	# Carve from the palette with an unlocked carver over the locked c.
	vg.set_visgroup_locked("Done", true)
	var carver = rig.box(level, "carver", Vector3(10, 1, 0), Vector3(1, 1, 6))
	rig.select([carver])
	await rig.frame()
	rig.plugin._on_hotkey_palette_action("carve")
	await rig.frame()
	var asked: Array = []
	for dialog in rig.open_dialogs():
		asked.append(dialog.dialog_text.replace("\n", " / "))
	await rig.accept_dialogs()
	await rig.frame()
	note("plugin: Carve asked", asked)
	note("plugin: locked c after Carve: still there", level.find_brush_by_id("c") != null)
	await rig.leave_level(level)
