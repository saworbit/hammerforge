@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## The navmesh a game actually needs AI to walk on.
##
## `bake-options` records that ticking Bake navmesh adds a `NavigationRegion3D`
## to the container. That is the cheap half of the question. A region with an
## empty `NavigationMesh` is the same node, and the only way a mapper finds out
## is when every agent in the game refuses to move. This checks the polygons,
## where they are, and whether the four agent spins on the Manage tab reach the
## resource at all.
##
## Everything here is in the project's own units, where the playtest player is
## 1.6 tall, so a room is twelve units across rather than five hundred.


func id() -> String:
	return "navmesh"


func summary() -> String:
	return "whether the baked navmesh has polygons over the floor, and whose agent settings"


func run() -> void:
	await _does_it_have_polygons()
	await _do_the_agent_settings_reach_it()
	await _does_it_survive_a_rebake()
	await _what_an_obstacle_does()


## A room a person can walk across: 12 x 3 x 12, which is a large-ish room.
func _room(root: Node3D) -> void:
	box(root, Vector3(12, 0.2, 12), Vector3(0, -0.1, 0))
	box(root, Vector3(12, 3, 0.3), Vector3(0, 1.5, -6))
	box(root, Vector3(12, 3, 0.3), Vector3(0, 1.5, 6))
	box(root, Vector3(0.3, 3, 12), Vector3(-6, 1.5, 0))
	box(root, Vector3(0.3, 3, 12), Vector3(6, 1.5, 0))


func _nav_facts(container: Node3D) -> Dictionary:
	var region := container.get_node_or_null("BakedNavmesh") as NavigationRegion3D
	if region == null:
		return {"region": false}
	var nav: NavigationMesh = region.navigation_mesh
	if nav == null:
		return {"region": true, "mesh": false}
	var verts: PackedVector3Array = nav.get_vertices()
	var bounds := "empty"
	if verts.size() > 0:
		var aabb := AABB(verts[0], Vector3.ZERO)
		for v in verts:
			aabb = aabb.expand(v)
		bounds = "%s .. %s" % [aabb.position, aabb.end]
	return {
		"region": true,
		"mesh": true,
		"polygons": nav.get_polygon_count(),
		"vertices": verts.size(),
		"bounds": bounds,
		"cell_size": nav.cell_size,
		"cell_height": nav.cell_height,
		"agent_height": nav.agent_height,
		"agent_radius": nav.agent_radius,
		"agent_max_climb": nav.agent_max_climb,
		"agent_max_slope": nav.agent_max_slope,
	}


func _does_it_have_polygons() -> void:
	var root: Node3D = await fresh_root()
	root.auto_spawn_player = false
	_room(root)
	root.bake_navmesh = true
	await root.bake(false, false)
	await frame()
	var container := root.get_node_or_null("BakedGeometry") as Node3D
	if container == null:
		flag("navmesh: the bake produced no BakedGeometry to look in")
		return
	var facts := _nav_facts(container)
	note("a 12-unit room, bake_navmesh on", facts)
	if not facts.get("region", false):
		flag("no BakedNavmesh node after a bake with bake_navmesh on")
		return
	if not facts.get("mesh", false):
		flag("BakedNavmesh has no NavigationMesh resource")
		return
	if int(facts.get("polygons", 0)) == 0:
		flag(
			"the baked navmesh has no polygons",
			(
				"the region exists and the resource exists, so every check short of "
				+ "counting polygons passes, and nothing in the game can path on it"
			)
		)
	else:
		note("polygons over a walkable floor", facts.get("polygons"))


func _do_the_agent_settings_reach_it() -> void:
	var root: Node3D = await fresh_root()
	root.auto_spawn_player = false
	_room(root)
	root.bake_navmesh = true
	# Values a mapper picks for a big, slow character.
	root.bake_navmesh_cell_size = 0.5
	root.bake_navmesh_cell_height = 0.5
	root.bake_navmesh_agent_height = 3.0
	root.bake_navmesh_agent_radius = 1.0
	note(
		"asked for",
		(
			"cell %s/%s agent %s/%s"
			% [
				root.bake_navmesh_cell_size,
				root.bake_navmesh_cell_height,
				root.bake_navmesh_agent_height,
				root.bake_navmesh_agent_radius
			]
		)
	)
	await root.bake(false, false)
	await frame()
	var container := root.get_node_or_null("BakedGeometry") as Node3D
	if container == null:
		return
	var facts := _nav_facts(container)
	note("got", facts)
	for pair in [
		["cell_size", root.bake_navmesh_cell_size],
		["cell_height", root.bake_navmesh_cell_height],
		["agent_height", root.bake_navmesh_agent_height],
	]:
		if not is_equal_approx(float(facts.get(pair[0], -1.0)), float(pair[1])):
			flag(
				"navmesh %s is not what the Manage tab asked for" % pair[0],
				"asked %s, got %s" % [pair[1], facts.get(pair[0])]
			)
	# agent_radius is deliberately ceil'd to a cell multiple, so check the
	# rounding rather than equality.
	var want_radius: float = (
		ceil(root.bake_navmesh_agent_radius / root.bake_navmesh_cell_size)
		* root.bake_navmesh_cell_size
	)
	if not is_equal_approx(float(facts.get("agent_radius", -1.0)), want_radius):
		flag(
			"navmesh agent_radius is neither the asked value nor its cell multiple",
			"asked 1.0, cell multiple %s, got %s" % [want_radius, facts.get("agent_radius")]
		)
	# The two that decide whether an agent can use the stairs this plugin builds.
	# A stair a player can walk up is unreachable to an agent whose max climb is
	# below its rise.
	for pair in [
		["agent_max_climb", root.bake_navmesh_agent_max_climb],
		["agent_max_slope", root.bake_navmesh_agent_max_slope],
	]:
		if not is_equal_approx(float(facts.get(pair[0], -1.0)), float(pair[1])):
			flag(
				"navmesh %s is not what the level asked for" % pair[0],
				"asked %s, got %s" % [pair[1], facts.get(pair[0])]
			)
	note(
		"the stair the plugin builds against the climb the agent is given",
		(
			"bake_connector_stair_height = %s, agent_max_climb = %s"
			% [root.get("bake_connector_stair_height"), root.bake_navmesh_agent_max_climb]
		)
	)

	# Raising the step without raising the climb is the combination that produces
	# stairs nothing can use, and Validate is what has to say so.
	root.bake_auto_connectors = true
	root.bake_connector_stair_height = root.bake_navmesh_agent_max_climb + 0.2
	# Bake Check, not Level Check: these are two separate reports, and the one
	# that answers "will this bake give me what I asked for" is this one.
	var reported: Array = root.validation_system.check_bake_issues()
	var named: Array = []
	for entry in reported:
		var text := str(entry.get("message", "")) if entry is Dictionary else str(entry)
		if text.to_lower().contains("climb"):
			named.append(text)
	note("what Validate says about a step taller than the agent can climb", named)
	if named.is_empty():
		flag(
			"nothing says when the stairs the level builds are taller than its agents climb",
			(
				"The auto-connector's step and the navmesh agent's max climb are two "
				+ "settings that have to agree, and a level where they do not bakes a "
				+ "staircase nothing in the game can use, with nothing said anywhere."
			)
		)


func _does_it_survive_a_rebake() -> void:
	var root: Node3D = await fresh_root()
	root.auto_spawn_player = false
	_room(root)
	root.bake_navmesh = true
	await root.bake(false, false)
	await frame()
	var container := root.get_node_or_null("BakedGeometry") as Node3D
	var first := _nav_facts(container) if container else {}
	# Now the mapper adds an annex and bakes again, which is the loop.
	box(root, Vector3(8, 0.2, 8), Vector3(10, -0.1, 0))
	await root.bake(false, false)
	await frame()
	container = root.get_node_or_null("BakedGeometry") as Node3D
	var second := _nav_facts(container) if container else {}
	note("first bake", first)
	note("after adding an 8-unit annex and baking again", second)
	if int(second.get("polygons", 0)) <= int(first.get("polygons", 0)):
		flag(
			"the navmesh did not grow when the level did",
			(
				"added an 8x8 floor slab beside the room and re-baked; polygons went %s -> %s"
				% [first.get("polygons"), second.get("polygons")]
			)
		)


func _what_an_obstacle_does() -> void:
	var root: Node3D = await fresh_root()
	root.auto_spawn_player = false
	_room(root)
	# A pillar in the middle. A navmesh worth having has a hole in it.
	box(root, Vector3(1.5, 3, 1.5), Vector3(0, 1.5, 0))
	root.bake_navmesh = true
	await root.bake(false, false)
	await frame()
	var container := root.get_node_or_null("BakedGeometry") as Node3D
	if container == null:
		return
	note("room with a 1.5-unit pillar in the middle", _nav_facts(container))
