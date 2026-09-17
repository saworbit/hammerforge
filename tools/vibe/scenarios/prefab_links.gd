@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## The live-linked half of prefabs: variants, per-instance overrides, and
## propagating a source change to every instance of it.
##
## The `prefabs` scenario covers capture, the `.hfprefab` round trip, placement
## and the instance registry. This one covers what happens to an instance
## *after* it is placed, which is where a link either earns its keep or quietly
## moves the mapper's level about.

const PrefabType = preload("res://addons/hammerforge/hf_prefab.gd")


func id() -> String:
	return "prefab-links"


func summary() -> String:
	return "whether cycling a variant leaves an instance where it was, and what it does to overrides"


func run() -> void:
	await _cycling_a_variant()


func _tmp(suffix: String) -> String:
	return "user://vibe_prefab_%s.hfprefab" % suffix


## A deliberately lopsided selection: one big brush and one small one, so the
## merged AABB centre and the mean of the origins are not the same point.
func _lopsided(root: Node3D) -> Array:
	var big = root.create_brush_from_info(
		{"shape": 0, "size": Vector3(128, 32, 32), "center": Vector3(0, 0, 0)}
	)
	var small = root.create_brush_from_info(
		{"shape": 0, "size": Vector3(16, 16, 16), "center": Vector3(96, 0, 0)}
	)
	return [big, small]


func _instance_centre(root: Node3D, rec) -> Vector3:
	var c := Vector3.ZERO
	var n := 0
	for bid in rec.brush_ids:
		var brush = root.find_brush_by_id(str(bid))
		if brush:
			c += brush.global_position
			n += 1
	return c / float(maxi(n, 1))


func _instance_bounds(root: Node3D, rec) -> AABB:
	var merged := AABB()
	var started := false
	for bid in rec.brush_ids:
		var brush = root.find_brush_by_id(str(bid))
		if brush == null:
			continue
		var extent: Vector3 = HFVibe.local_extent(brush)
		var box := AABB(brush.global_position - extent * 0.5, extent)
		if not started:
			merged = box
			started = true
		else:
			merged = merged.merge(box)
	return merged


func _cycling_a_variant() -> void:
	var root: Node3D = await fresh_root("PrefabLinks")
	var nodes: Array = _lopsided(root)
	await frame()

	var prefab = PrefabType.capture_from_selection(root.brush_system, root.entity_system, nodes, [])
	var aabb_centroid: Vector3 = PrefabType.compute_selection_centroid(nodes, [])
	var origin_mean := Vector3.ZERO
	for n in nodes:
		origin_mean += (n as Node3D).global_position
	origin_mean /= float(nodes.size())
	note("capture centroid (merged visual AABB centre)", aabb_centroid)
	note("mean of the same brushes' origins", origin_mean)
	note("the two differ by", (origin_mean - aabb_centroid).length())

	# A second variant, so there is something to cycle to.
	var alt_a = root.create_brush_from_info(
		{"shape": 0, "size": Vector3(128, 32, 32), "center": Vector3(0, 128, 0)}
	)
	var alt_b = root.create_brush_from_info(
		{"shape": 0, "size": Vector3(16, 16, 16), "center": Vector3(96, 128, 0)}
	)
	await frame()
	prefab.add_variant_from_selection(
		"tall", root.brush_system, root.entity_system, [alt_a, alt_b], []
	)
	note("variants on the prefab", prefab.get_variant_names())

	var path := _tmp("variants")
	var err: int = prefab.save_to_file(path)
	note("saved", "err %d, %d bytes" % [err, HFVibe.file_size(path)])

	# Start from a clean level and place one instance somewhere specific.
	var level: Node3D = await fresh_root("PrefabTarget")
	var loaded = PrefabType.load_from_file(path)
	if loaded == null:
		flag("the prefab just written will not load back", path)
		return
	var where := Vector3(512, 0, -256)
	var placed: Dictionary = loaded.instantiate(
		level.brush_system, level.entity_system, level, where
	)
	await frame()
	var instance_id: String = level.prefab_system.register_instance(
		path, placed.get("brush_ids", []), [], true, "base"
	)
	note("placed instance id", instance_id)
	var rec = level.prefab_system.get_instance(instance_id)
	if rec == null:
		flag("placing a prefab registered no instance record", placed)
		return

	var before_bounds: AABB = _instance_bounds(level, rec)
	var before_centre: Vector3 = _instance_centre(level, rec)
	note("placed at", where)
	note("instance bounds centre before the swap", before_bounds.get_center())
	note("instance origin mean before the swap", before_centre)

	# This used to set a per-instance override here and check what became of it
	# across the swap. `set_override()` was removed with the rest of that
	# mechanism in #582, for the reason `hf_prefab_system.gd` records where it
	# reads past the old key: it had no way in from the editor and wrote a meta
	# nothing read. The call stayed behind and errored, which cost nothing
	# visible because a script error was not a finding and the scenario went on
	# reporting clean (#739).
	note("per-instance overrides", "the mechanism was removed in #582; nothing to measure")
	var first_brush = level.find_brush_by_id(str(rec.brush_ids[0]))
	note("size of piece 0 before the swap", first_brush.size if first_brush else null)

	var new_variant: String = level.prefab_system.cycle_variant(instance_id)
	await frame()
	note("cycled to variant", new_variant)
	rec = level.prefab_system.get_instance(instance_id)
	var after_bounds: AABB = _instance_bounds(level, rec)
	var after_centre: Vector3 = _instance_centre(level, rec)
	note("instance bounds centre after the swap", after_bounds.get_center())
	note("instance origin mean after the swap", after_centre)

	# The two variants are the same shapes 128 apart in Y, so the only difference
	# the swap should make on X and Z is none at all.
	var drift := Vector2(
		after_bounds.get_center().x - before_bounds.get_center().x,
		after_bounds.get_center().z - before_bounds.get_center().z
	)
	note("horizontal drift from one variant swap", drift)
	if drift.length() > 0.5:
		known(
			565,
			"cycling a prefab variant moves the instance sideways",
			(
				(
					"`HFPrefab.capture_from_selection()` makes every transform relative to the"
					+ " merged visual AABB centre and `place()` adds the placement back onto it,"
					+ " while `HFPrefabSystem._apply_variant()` re-places the new variant at"
					+ " `_compute_instance_centroid()`, which is the mean of the node origins."
					+ " On any prefab that is not symmetric about that mean the two points"
					+ " differ -- here by %.1f units -- and the instance jumps by the difference"
					+ " every time the variant is cycled: %s"
				)
				% [(origin_mean - aabb_centroid).length(), str(drift)]
			)
		)

	# What the pieces are after the swap, which is what the override block used to
	# read and is still worth having on its own.
	var piece = (
		level.find_brush_by_id(str(rec.brush_ids[0])) if not rec.brush_ids.is_empty() else null
	)
	note("size of piece 0 after the swap", piece.size if piece else null)
