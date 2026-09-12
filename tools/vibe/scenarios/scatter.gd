@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## The scatter brush, the foliage populator and the paint layer list behind them.
##
## Scatter is the one part of the plugin that puts hundreds of nodes into the
## scene from one click, so what it orients them to, how many it is willing to
## make, and whether the scene keeps them afterwards are all worth measuring
## rather than trusting.

const ScatterBrush = preload("res://addons/hammerforge/paint/hf_scatter_brush.gd")
const FoliagePopulator = preload("res://addons/hammerforge/paint/hf_foliage_populator.gd")


func id() -> String:
	return "scatter"


func summary() -> String:
	return "what a scattered instance is oriented to, how many one click makes, and what the scene keeps"


func run() -> void:
	await _which_way_is_up()
	await _how_many_one_click_makes()
	await _what_the_scene_keeps()
	await _the_layer_list_under_it()


func _flat_layer(root: Node3D):
	var layer = root.paint_layers.get_active_layer()
	for y in range(-8, 9):
		for x in range(-8, 9):
			layer.set_cell(Vector2i(x, y), true)
	return layer


func _settings(mesh_needed: bool = false):
	var s = ScatterBrush.ScatterSettings.new()
	s.seed = 12345
	s.density = 0.1
	s.radius = 4.0
	if mesh_needed:
		s.mesh = BoxMesh.new()
	return s


## A scattered tree on flat ground, asked to stand up.
func _which_way_is_up() -> void:
	var root: Node3D = await fresh_root()
	var layer = _flat_layer(root)
	var brush = ScatterBrush.new()

	var s = _settings()
	s.align_to_normal = false
	s.random_rotation = false
	var plain = brush.scatter_circle(Vector3.ZERO, layer, s)
	note("flat ground, no align: instances", plain.transforms.size())
	if not plain.transforms.is_empty():
		note("  first basis y", plain.transforms[0].basis.y)

	s.align_to_normal = true
	var aligned = brush.scatter_circle(Vector3.ZERO, layer, s)
	note("flat ground, align to normal: instances", aligned.transforms.size())
	if aligned.transforms.is_empty():
		note("  nothing placed, nothing to measure")
		return
	var up: Vector3 = aligned.transforms[0].basis.y.normalized()
	note("  first basis y", up)
	if up.y < 0.0:
		known(
			429,
			"align to surface normal stands every scattered instance on its head",
			(
				"flat ground, so the surface normal is +Y; the instance basis y is %s. " % str(up)
				+ "_compute_normal() crosses the X tangent into the Z tangent, which on a "
				+ "height field points down -- tz.cross(tx) is the up-facing order"
			)
		)


## The budget. One drag with the radius wound up.
func _how_many_one_click_makes() -> void:
	var root: Node3D = await fresh_root()
	var layer = root.paint_layers.get_active_layer()
	var brush = ScatterBrush.new()
	var s = _settings()
	s.min_height = -100000.0
	s.max_height = 100000.0
	s.max_slope = 90.0

	for radius in [10.0, 100.0, 300.0]:
		s.radius = radius
		s.density = 1.0
		var started := Time.get_ticks_msec()
		var result = brush.scatter_circle(Vector3.ZERO, layer, s)
		var took := Time.get_ticks_msec() - started
		note(
			"radius %s density 1.0" % radius,
			(
				"%d candidates, %d placed, %d ms"
				% [result.total_candidates, result.transforms.size(), took]
			)
		)
		if result.transforms.size() > 100000:
			known(
				430,
				"one scatter stroke lays out more instances than any cap allows",
				(
					(
						"radius %s at density 1.0 produced %d transforms in %d ms with no refusal. "
						% [radius, result.transforms.size(), took]
					)
					+ "HFDuplicator refuses past MAX_COPY_BRUSHES (256); scatter has no equivalent"
				)
			)
			break


## What the scene has after a commit, and what an undo could take back.
func _what_the_scene_keeps() -> void:
	var root: Node3D = await fresh_root()
	var layer = _flat_layer(root)
	var brush = ScatterBrush.new()
	var s = _settings(true)
	var result = brush.scatter_circle(Vector3.ZERO, layer, s)
	note("instances to commit", result.transforms.size())

	var before := root.get_child_count()
	var mmi = brush.commit(result.transforms, s, root)
	await frame()
	note("committed node", mmi.name if mmi else "<null>")
	note("root children before/after", "%d -> %d" % [before, root.get_child_count()])
	if mmi:
		note("committed node owner", mmi.owner)
		if mmi.owner == null:
			known(
				431,
				"a committed scatter is not owned, so saving the scene drops every instance",
				(
					"HFScatterBrush.commit() calls parent.add_child(mmi) and never sets "
					+ "mmi.owner. A node without an owner is not written into the .tscn, so "
					+ "the scatter is there until the scene is closed and gone after"
				)
			)

	var populator = FoliagePopulator.new()
	var fs = FoliagePopulator.FoliageSettings.new()
	fs.mesh = BoxMesh.new()
	fs.seed = 7
	var foliage = populator.populate(layer, fs, root)
	note("foliage node", foliage.name if foliage else "<null>")
	if foliage:
		note("foliage owner", foliage.owner)

	var described := HFVibe.describe_level(root)
	note("brush count after two commits", described.get("brushes", []).size())


## The layer list the scatter target is chosen from.
func _the_layer_list_under_it() -> void:
	var root: Node3D = await fresh_root()
	var mgr = root.paint_layers
	mgr.create_layer(&"upper", 32.0)
	mgr.create_layer(&"roof", 64.0)
	var ids: Array = []
	for l in mgr.layers:
		ids.append(str(l.layer_id))
	note("layer ids", ids)

	mgr.set_active_layer(1)
	var active_before: StringName = mgr.get_active_layer().layer_id
	note("active layer before remove", str(active_before))
	mgr.remove_layer(0)
	var active_after: StringName = mgr.get_active_layer().layer_id
	note("active layer after removing layer 0", str(active_after))
	if active_after != active_before:
		known(
			432,
			"deleting a paint layer moves the selection to a different layer",
			(
				(
					"active was '%s'; after removing the layer above it in the list the active "
					% str(active_before)
				)
				+ (
					"layer is '%s'. remove_layer() clamps active_layer_index instead of "
					% str(active_after)
				)
				+ "decrementing it when the removed index is below the active one, so the "
				+ "next stroke lands on a layer the mapper did not choose"
			)
		)

	var dup = mgr.create_layer(&"roof", 96.0)
	var roof_count := 0
	for l in mgr.layers:
		if l.layer_id == &"roof":
			roof_count += 1
	note("layers named 'roof'", roof_count)
	note("duplicate layer node name", dup.name)
	if roof_count > 1:
		known(
			433,
			"two paint layers can share one layer_id",
			(
				"create_layer() does not check the id is free; the node name collides too, so the second layer is named '%s'"
				% dup.name
			)
		)
