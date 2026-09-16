@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## The I/O wiring overlay: what it draws against what the level stores.
##
## A mapper wires a button to a door and turns the overlay on to check the wire
## landed. So the overlay is a *diagnostic*, and a diagnostic that quietly omits
## the broken half of the picture is worse than none: the wire that does not
## work is exactly the one you are looking at the overlay to find.


func id() -> String:
	return "io-visualizer"


func summary() -> String:
	return "what the wiring overlay draws against what the level stores, and when it notices a change"


func run() -> void:
	await _drawn_against_stored()
	await _a_broken_wire_is_invisible()
	await _staleness()
	await _summary_counts()
	await _overlay_nodes_in_the_level()
	await _what_notices_a_dangling_wire()


func _spawn(root: Node3D, type: String, where: Vector3, authored: String) -> Node3D:
	return root._restore_entity_from_info(
		{
			"entity_type": type,
			"entity_class": type,
			"transform": Transform3D(Basis.IDENTITY, where),
			"properties": {},
			"name": authored,
			"entity_name": authored,
		}
	)


## Line-vertex count of whatever the overlay last drew. Each route is
## CURVE_SEGMENTS segments plus a two-line arrowhead, so 2*(12+2) = 28.
func _drawn_vertices(vis) -> int:
	var mesh = vis._immediate_mesh
	if mesh == null or mesh.get_surface_count() == 0:
		return 0
	var total := 0
	for s in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(s)
		if arrays.size() > Mesh.ARRAY_VERTEX and arrays[Mesh.ARRAY_VERTEX] != null:
			total += arrays[Mesh.ARRAY_VERTEX].size()
	return total


const VERTS_PER_ROUTE := 28


## Three good wires between three entities should be three routes.
func _drawn_against_stored() -> void:
	var root: Node3D = await fresh_root()
	var vis = root.io_visualizer
	if vis == null:
		flag("no io_visualizer on a fresh level root")
		return
	var button := _spawn(root, "func_button", Vector3.ZERO, "button_1")
	var door := _spawn(root, "func_door", Vector3(128, 0, 0), "door_1")
	var light := _spawn(root, "light", Vector3(0, 0, 128), "light_1")
	root.add_entity_output(button, "OnPressed", "door_1", "Open")
	root.add_entity_output(button, "OnPressed", "light_1", "TurnOn")
	root.add_entity_output(door, "OnFullyOpen", "light_1", "TurnOff")
	await frame()

	vis.set_enabled(true)
	await frame()
	var stored: int = root.entity_system.get_all_connections().size()
	var verts := _drawn_vertices(vis)
	note("connections stored", stored)
	note("overlay line vertices", verts)
	note("routes drawn", float(verts) / float(VERTS_PER_ROUTE))
	if verts != stored * VERTS_PER_ROUTE:
		flag(
			"the overlay drew %.2f routes for %d stored connections" % [
				float(verts) / float(VERTS_PER_ROUTE), stored
			],
			"expected one route per connection"
		)
	note("overlay mesh visible", vis._mesh_instance.visible if vis._mesh_instance else "no mesh")
	note("refresh_count", vis.refresh_count)
	if light == null:
		note("light entity", "not created")


## The wire whose target does not exist is the one a mapper turned the overlay
## on to find, and it is the one route the overlay leaves out.
func _a_broken_wire_is_invisible() -> void:
	var root: Node3D = await fresh_root()
	var vis = root.io_visualizer
	var button := _spawn(root, "func_button", Vector3.ZERO, "button_1")
	var door := _spawn(root, "func_door", Vector3(128, 0, 0), "door_1")
	root.add_entity_output(button, "OnPressed", "door_1", "Open")
	root.add_entity_output(button, "OnPressed", "door_2", "Open")  # nothing answers to door_2
	await frame()
	vis.set_enabled(true)
	await frame()
	var stored: int = root.entity_system.get_all_connections().size()
	var routes := float(_drawn_vertices(vis)) / float(VERTS_PER_ROUTE)
	note("stored connections", stored)
	note("routes drawn", routes)
	if stored == 2 and routes == 1.0:
		flag(
			"a wire whose target does not exist is drawn as nothing at all",
			(
				"2 outputs on the button, 1 route on the overlay; the dangling one is "
				+ "silently omitted rather than drawn as broken, and the overlay is the "
				+ "surface a mapper opens to find exactly that wire"
			)
		)

	# And with *every* wire dangling the overlay hides itself entirely, which
	# reads as "this entity is not wired to anything".
	var root2: Node3D = await fresh_root("Level2")
	var vis2 = root2.io_visualizer
	var b2 := _spawn(root2, "func_button", Vector3.ZERO, "button_1")
	root2.add_entity_output(b2, "OnPressed", "ghost", "Open")
	await frame()
	vis2.set_enabled(true)
	await frame()
	note("all-dangling level: stored", root2.entity_system.get_all_connections().size())
	note(
		"all-dangling level: overlay visible",
		vis2._mesh_instance.visible if vis2._mesh_instance else "no mesh"
	)
	if vis2._mesh_instance and not vis2._mesh_instance.visible:
		note(
			"all-dangling level",
			"overlay hides itself, so a level whose wiring is entirely broken looks unwired"
		)
	if door == null:
		note("door entity", "not created")


## How long the picture can stay wrong, and what changes it notices at all.
func _staleness() -> void:
	var root: Node3D = await fresh_root()
	var vis = root.io_visualizer
	var button := _spawn(root, "func_button", Vector3.ZERO, "button_1")
	var door := _spawn(root, "func_door", Vector3(128, 0, 0), "door_1")
	root.add_entity_output(button, "OnPressed", "door_1", "Open")
	await frame()
	vis.set_enabled(true)
	await frame()
	var base: int = vis.refresh_count

	# Move the door: the picture is wrong until the next staleness check.
	door.global_position = Vector3(256, 0, 0)
	var frames_to_notice := -1
	for i in range(40):
		vis.process(1.0 / 60.0)
		if vis.refresh_count > base:
			frames_to_notice = i + 1
			break
	note("frames before a moved entity redraws", frames_to_notice)
	if frames_to_notice > 1:
		note(
			"staleness interval",
			(
				"REFRESH_INTERVAL is %d, so the overlay lags a drag by up to that many frames"
				% vis.REFRESH_INTERVAL
			)
		)

	# A delay change is a change to the drawn colour. Is it in the fingerprint?
	base = vis.refresh_count
	var outputs: Array = root.get_entity_outputs(button)
	if not outputs.is_empty():
		outputs[0]["delay"] = 5.0
		button.set_meta("entity_io_outputs", outputs)
	var noticed := false
	for i in range(40):
		vis.process(1.0 / 60.0)
		if vis.refresh_count > base:
			noticed = true
			break
	note("a changed delay redraws", noticed)
	if not noticed:
		flag(
			"changing a connection's delay does not redraw the overlay",
			"delay dims the drawn colour, so the overlay keeps showing the old one"
		)


## A self-wired entity, and what the summary the toolbar shows says about it.
func _summary_counts() -> void:
	var root: Node3D = await fresh_root()
	var relay := _spawn(root, "func_button", Vector3.ZERO, "relay_1")
	root.add_entity_output(relay, "OnPressed", "relay_1", "Toggle")
	await frame()
	var summary: Dictionary = root.get_connection_summary("relay_1")
	note("self-wired entity summary", summary)
	if int(summary.get("triggers", 0)) == 1 and int(summary.get("triggered_by", 0)) == 0:
		flag(
			"a self-wired entity is not counted among what triggers it",
			(
				"relay_1 -> relay_1 reports triggers=1, triggered_by=0; the summary is an "
				+ "if/elif on the same connection, so a loop back to the same entity is "
				+ "only ever counted once"
			)
		)

	# Two entities, one wire, each asked about itself.
	var root2: Node3D = await fresh_root("Level2")
	var a := _spawn(root2, "func_button", Vector3.ZERO, "a")
	var b := _spawn(root2, "func_door", Vector3(64, 0, 0), "b")
	root2.add_entity_output(a, "OnPressed", "b", "Open")
	await frame()
	note("source side", root2.get_connection_summary("a"))
	note("target side", root2.get_connection_summary("b"))
	if b == null:
		note("b", "not created")


## The overlay parents its mesh and its pulse spheres to the LevelRoot. What
## does the rest of the level make of those children?
func _overlay_nodes_in_the_level() -> void:
	var root: Node3D = await fresh_root()
	var vis = root.io_visualizer
	var button := _spawn(root, "func_button", Vector3.ZERO, "button_1")
	var door := _spawn(root, "func_door", Vector3(128, 0, 0), "door_1")
	root.add_entity_output(button, "OnPressed", "door_1", "Open")
	await frame()
	var children_before: int = root.get_child_count()
	vis.set_enabled(true)
	vis.set_highlight_connected(true)
	vis.set_selected_entities([button])
	await frame()
	note("LevelRoot children before enabling the overlay", children_before)
	note("after enabling", root.get_child_count())
	var names: Array = []
	for c in root.get_children():
		names.append(c.name)
	note("LevelRoot children", names)
	note("pulse overlays", vis._highlight_overlays.size())
	var owned := 0
	for c in root.get_children():
		if c.owner != null:
			owned += 1
	note("LevelRoot children with an owner (ie saved into the scene)", owned)

	# A restore_state() is the undo path. Does the overlay survive it, and does
	# it leave its spheres behind?
	var state: Dictionary = root.capture_state()
	root.restore_state(state)
	await frame()
	var after: Array = []
	for c in root.get_children():
		after.append(c.name)
	note("LevelRoot children after restore_state", after)
	note("pulse overlays after restore_state", vis._highlight_overlays.size())
	var stale := 0
	for c in root.get_children():
		if c.has_meta("_io_pulse_overlay"):
			stale += 1
	note("pulse spheres still parented after restore_state", stale)
	if stale > 0 and vis._highlight_overlays.is_empty():
		flag(
			"restore_state leaves the overlay's pulse spheres in the level",
			"%d sphere(s) parented to the LevelRoot that the visualizer no longer tracks" % stale
		)
	if door == null:
		note("door", "not created")


## Every surface that could tell a mapper a wire points at nothing, asked.
func _what_notices_a_dangling_wire() -> void:
	var root: Node3D = await fresh_root()
	var button := _spawn(root, "func_button", Vector3.ZERO, "button_1")
	var door := _spawn(root, "func_door", Vector3(128, 0, 0), "door_1")
	root.add_entity_output(button, "OnPressed", "door_1", "Open")
	await frame()
	note("wired, both ends live: validate issues", root.validate_level().get("issues", []))

	# The most ordinary way a wire breaks: rename the target in the Scene dock.
	door.set_meta("entity_name", "door_main")
	door.name = "door_main"
	await frame()
	note("after renaming the target to door_main", "the output still says door_1")
	note("  entities answering to door_1", root.find_entities_by_name("door_1").size())
	var report: Dictionary = root.validate_level()
	note("  validate_level issues", report.get("issues", []))
	var summary: Dictionary = root.get_connection_summary("button_1")
	note("  connection summary for the source", summary)
	var vis = root.io_visualizer
	vis.set_enabled(true)
	await frame()
	note(
		"  routes on the overlay",
		float(_drawn_vertices(vis)) / float(VERTS_PER_ROUTE)
	)
	var issues: Array = report.get("issues", [])
	var named := false
	for issue in issues:
		if str(issue).find("door_1") >= 0 or str(issue).to_lower().find("dangl") >= 0:
			named = true
	if not named:
		flag(
			"nothing in the editor reports a wire whose target no longer exists",
			(
				"the target was renamed, the output still names door_1, and: "
				+ "validate_level() reports %s; get_connection_summary() still counts it "
				+ "as a live trigger with target_names %s; and the overlay draws no route "
				+ "for it. HFValidationSystem checks an output for empty fields "
				+ "(hf_validation_system.gd:243) and never resolves target_name against "
				+ "the level. cleanup_dangling_connections() exists but only runs on "
				+ "delete, so a rename leaves the wire behind with no surface that says so"
			) % [issues, summary.get("target_names", [])]
		)
