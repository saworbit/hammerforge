@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Whether Bake Changed notices painted ground and terrain that changed.
##
## `bake_dirty()` rebuilds when a brush is tagged dirty or a full reconcile is
## pending. A painted floor and a heightmap terrain are not brushes the mapper
## drew, and `LevelRoot.tag_paint_dirty()` has no caller. This paints ground,
## bakes it, changes it the ways a mapper does (more cells, a taller heightmap),
## and asks Bake Changed for the result, with the editor's change tracker
## reconciled in between the way the plugin runs it. The baked terrain is
## measured against a full bake of the same level.

const Tracker = preload("res://addons/hammerforge/hf_brush_change_tracker.gd")


func id() -> String:
	return "bake-changed-paint"


func summary() -> String:
	return "whether Bake Changed rebuilds painted floors and heightmap terrain after they change"


func run() -> void:
	await _case("flat floor: paint 8 more cells", false, Vector3(0, 0, 0))
	await _case("heightmap: paint 8 more cells", true, Vector3(0, 0, 0))
	await _case("heightmap: height scale 4 to 12", true, Vector3(0, 0, 0), true)


## The baked container's bounds over every mesh in it.
func _baked_bounds(root: Node3D) -> AABB:
	var container := root.get_node_or_null("BakedGeometry") as Node3D
	var out := AABB()
	var first := true
	if container == null:
		return out
	for n in container.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var box: AABB = mi.global_transform * mi.mesh.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out


func _case(label: String, heightmap: bool, _at: Vector3, rescale: bool = false) -> void:
	var root: Node3D = await fresh_root()
	if heightmap:
		root.generate_heightmap_noise({})
		await frame()
		root.set_heightmap_scale(4.0)
	var layer = root.paint_layers.get_active_layer()
	for y in range(0, 8):
		for x in range(0, 8):
			layer.set_cell(Vector2i(x, y), true)
	root.paint_system.regenerate_paint_layers()
	for _i in 4:
		await frame()
	await root.bake(false, false)
	await frame()
	var tracker = Tracker.new()
	tracker.prime(root)
	var before := _baked_bounds(root)

	if rescale:
		root.set_heightmap_scale(12.0)
	else:
		for y in range(0, 8):
			layer.set_cell(Vector2i(8, y), true)
	root.paint_system.regenerate_paint_layers()
	for _i in 4:
		await frame()
	var tagged: PackedStringArray = tracker.reconcile(root)
	var ran: bool = await root.bake_dirty()
	await frame()
	var after_changed := _baked_bounds(root)
	await root.bake(false, false)
	await frame()
	var after_full := _baked_bounds(root)
	note(
		label,
		(
			"tracker tagged %d, Bake Changed ran %s; baked bounds before %s, after Bake Changed %s, after a full bake %s"
			% [tagged.size(), ran, before, after_changed, after_full]
		)
	)
	if after_changed.is_equal_approx(after_full):
		note("  Bake Changed rebuilt the ground as a full bake does")
	else:
		flag(
			"Bake Changed keeps the old ground after %s" % label.split(": ")[1],
			(
				(
					"%s. The tracker tagged %d brush(es) and bake_dirty() returned %s, so the "
					+ "baked level keeps bounds %s where a full bake gives %s."
				)
				% [label, tagged.size(), ran, after_changed, after_full]
			)
		)
	await drop_root(root)
