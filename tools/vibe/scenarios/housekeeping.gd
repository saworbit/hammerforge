@tool
extends HFVibeScenario

## Visgroups, groups, the cordon and paint layers -- the bookkeeping a mapper
## builds up around the geometry rather than in it.
##
## None of it is geometry, so none of it is checked by anything that looks at
## geometry. A visgroup named by a blank string, a cordon built from nothing, a
## paint layer renamed to the name of another: each is a small thing that only
## shows up later, when the level is loaded and something is missing.


func id() -> String:
	return "housekeeping"


func summary() -> String:
	return "visgroup and group names, the cordon, and the paint layer list at their edges"


func run() -> void:
	await _visgroup_names()
	await _group_names()
	await _cordon_from_nothing()
	await _paint_layer_list()


func _visgroup_names() -> void:
	var root: Node3D = await fresh_root()
	var b = box(root, Vector3(64, 64, 64))
	for vg_name in ["", "   ", "lights", "lights"]:
		root.create_visgroup(vg_name, Color.WHITE)
		await frame()
	var names: PackedStringArray = root.get_visgroup_names()
	note("created '', '   ', 'lights' twice", "visgroups now %s" % [names])
	for n in names:
		if n != "" and n.strip_edges() == "":
			known(
				349,
				"a visgroup can be named with nothing but whitespace",
				(
					"'' is refused but '%s' is not, so the dock shows a blank row that cannot be told from another"
					% n
				)
			)
	var lights := 0
	for n in names:
		if n == "lights":
			lights += 1
	if lights > 1:
		flag("creating a visgroup twice makes two of them", "%d named 'lights'" % lights)

	# Hiding a visgroup, then adding a brush to it.
	root.set_visgroup_visible("lights", false)
	await frame()
	root.add_selection_to_visgroup("lights", [b])
	await frame()
	note("brush added to a hidden visgroup", "visible = %s" % b.visible)
	if b.visible:
		flag(
			"a brush added to a hidden visgroup stays visible",
			"the visgroup is hidden, so its members should not be on screen"
		)
	root.set_visgroup_visible("lights", true)
	await frame()
	note("after showing the visgroup again", "visible = %s" % b.visible)
	if not b.visible:
		flag("showing a visgroup again does not bring its members back", "brush is still hidden")

	# Removing a visgroup a brush is still in.
	root.remove_visgroup("lights")
	await frame()
	var left: PackedStringArray = b.get_meta("visgroups", PackedStringArray())
	note("after removing the visgroup", "brush still lists %s, visible = %s" % [left, b.visible])
	if Array(left).has("lights"):
		flag(
			"removing a visgroup leaves its name on the brushes that were in it",
			"the brush still carries 'lights' in its visgroups meta, which is saved and reloaded"
		)
	for problem in HFVibe.check_invariants(root):
		flag("visgroup bookkeeping broke an invariant", problem)


func _group_names() -> void:
	var root: Node3D = await fresh_root()
	var a = box(root, Vector3(64, 64, 64), Vector3(-64, 0, 0))
	var b = box(root, Vector3(64, 64, 64), Vector3(64, 0, 0))
	root.group_selection("", [a, b])
	await frame()
	note("group with a blank name", "%d members" % root.get_group_members("").size())
	root.group_selection("crates", [a, b])
	await frame()
	note("group 'crates'", "%d members" % root.get_group_members("crates").size())
	# Regrouping one member into another group: which group does it end up in?
	root.group_selection("barrels", [a])
	await frame()
	note(
		"after regrouping one member",
		(
			"crates %d, barrels %d"
			% [root.get_group_members("crates").size(), root.get_group_members("barrels").size()]
		)
	)
	root.ungroup_nodes([a, b])
	await frame()
	note(
		"after ungrouping both",
		(
			"crates %d, barrels %d"
			% [root.get_group_members("crates").size(), root.get_group_members("barrels").size()]
		)
	)


func _cordon_from_nothing() -> void:
	var root: Node3D = await fresh_root()
	root.set_cordon_from_selection([])
	await frame()
	note("cordon from an empty selection", "enabled = %s" % root.get("cordon_enabled"))
	var b = box(root, Vector3(64, 64, 64))
	root.set_cordon_from_selection([b])
	await frame()
	note("cordon from one brush", "enabled = %s" % root.get("cordon_enabled"))
	var dry: Dictionary = root.bake_dry_run()
	note("bake dry run inside the cordon", dry)
	# A cordon that excludes everything: move the brush far outside it.
	b.global_position = Vector3(100000, 0, 0)
	await frame()
	var dry_outside: Dictionary = root.bake_dry_run()
	note("bake dry run with the only brush outside the cordon", dry_outside)
	if int(dry_outside.get("brushes", -1)) > 0:
		flag(
			"the dry run counts a brush that the cordon excludes",
			(
				"the brush sits at %s, far outside the cordon, and the dry run reports %s"
				% [b.global_position, dry_outside]
			)
		)


func _paint_layer_list() -> void:
	var root: Node3D = await fresh_root()
	for _i in range(4):
		root.add_paint_layer()
	await frame()
	var names: Array = root.get_paint_layer_names()
	note("four layers added", names)
	for bad in [-1, 99]:
		var renamed: bool = root.rename_paint_layer(bad, "nope")
		note("rename layer %d" % bad, "returned %s" % renamed)
		if renamed:
			flag("renaming a paint layer that does not exist reports success", "index %d" % bad)
		root.set_active_paint_layer(bad)
		await frame()
		note("set active layer %d" % bad, "active is now %d" % root.get_active_paint_layer_index())
		if root.get_active_paint_layer_index() == bad:
			flag(
				"the active paint layer can be set to index %d" % bad,
				"every paint stroke from here writes into a layer that is not there"
			)
	var blank: bool = root.rename_paint_layer(0, "")
	await frame()
	note(
		"rename layer 0 to a blank name",
		"returned %s, names now %s" % [blank, root.get_paint_layer_names()]
	)
	# Remove every layer, one at a time, and keep going past the end.
	for _i in range(8):
		root.set_active_paint_layer(0)
		root.remove_active_paint_layer()
		await frame()
	note(
		"removed eight layers from a list of four", "%d left" % root.get_paint_layer_names().size()
	)
	if root.get_paint_layer_names().is_empty():
		flag(
			"every paint layer can be removed, leaving a level with none",
			"the paint tool has no layer to write into and the dock has no row to select"
		)
