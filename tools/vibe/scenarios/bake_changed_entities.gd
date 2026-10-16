@tool
extends "res://tools/vibe/hf_vibe_scenario.gd"

## Whether Bake Changed notices an edit to a door that is not a move.
##
## Bake Changed (`bake_dirty()`) rebuilds only when something is tagged dirty.
## LevelRoot's own commands tag what they change, and `HFBrushChangeTracker`
## tags what the Inspector and native undo change behind them. A door is more
## than its geometry: its speed, wait and lock live in `brush_entity_data`, and
## which brushes are one door lives in the tie. If none of that tags anything,
## Bake Changed says "No changed brushes since last bake" and the game keeps
## the door as it was at the last full bake.
##
## Driven the way the editor drives it: a full bake, the tracker primed on the
## result, the edit made through LevelRoot's API, the tracker reconciled, and
## Bake Changed. Then the baked door is read for what the game will get.

const Tracker = preload("res://addons/hammerforge/hf_brush_change_tracker.gd")
const HFBrushEntity = preload("res://addons/hammerforge/hf_brush_entity.gd")


func id() -> String:
	return "bake-changed-entities"


func summary() -> String:
	return "whether Bake Changed rebuilds a door after its speed, lock or tie changes"


func run() -> void:
	await _a_property("speed", 9.0, Vector3(0, 0, 0))
	await _a_property("locked", true, Vector3(100, 0, 0))
	await _a_retie(Vector3(200, 0, 0))
	await _a_rename(Vector3(300, 0, 0))


func _door(root: Node3D, at: Vector3, entity_name: String) -> Array:
	box(root, Vector3(8, 0.2, 8), at + Vector3(0, -0.1, 0))
	var ids: Array = []
	for i in 2:
		var b = box(root, Vector3(1, 2, 0.2), at + Vector3(i * 1.0 - 0.5, 1, 0))
		ids.append(str(b.get_meta("brush_id", "")))
	root.tie_brushes_to_entity(ids, "func_door", entity_name)
	return ids


## Each mover in the bake: its node name and the entity data it carries.
func _movers(root: Node3D) -> Array:
	var out: Array = []
	var container := root.get_node_or_null("BakedGeometry")
	if container == null:
		return out
	for n in container.find_children("*", "Node3D", true, false):
		if n.has_meta("entity_data") or (n.get_script() and n.has_method("apply_entity_data")):
			var data: Dictionary = n.get_meta("entity_data", {})
			out.append(
				{
					"name": str(n.name),
					"data": data,
					"speed": n.get("speed"),
					"locked": n.get("locked")
				}
			)
	return out


## How many doors the bake holds, by the identity each baked door node carries.
func _baked_doors(root: Node3D) -> int:
	var container := root.get_node_or_null("BakedGeometry")
	if container == null:
		return 0
	var seen := {}
	for n in container.find_children("*", "", true, false):
		if HFBrushEntity.entity_class(n) == "func_door":
			seen[HFBrushEntity.baked_identity(n)] = true
	return seen.size()


func _bake_changed(root: Node3D, tracker) -> Dictionary:
	var tagged: PackedStringArray = tracker.reconcile(root)
	var ran: bool = await root.bake_dirty()
	await frame()
	return {"tracker tagged": tagged.size(), "bake_dirty ran": ran}


func _a_property(key: String, value: Variant, at: Vector3) -> void:
	var root: Node3D = await fresh_root()
	var ids := _door(root, at, "gate")
	await root.bake(false, false)
	await frame()
	var tracker = Tracker.new()
	tracker.prime(root)
	var before := _movers(root)
	root.set_entity_property(root.find_brush_by_id(ids[0]), key, value)
	var run := await _bake_changed(root, tracker)
	var after := _movers(root)
	note("door 'gate': %s set to %s, then Bake Changed" % [key, value], run)
	note("  movers before", before)
	note("  movers after", after)
	var stale := after.is_empty()
	for m in after:
		if (
			str(m.get(key)) != str(value)
			and str((m["data"] as Dictionary).get(key, "")) != str(value)
		):
			stale = true
	if not stale:
		note("  the baked door carries the new %s" % key)
	else:
		flag(
			"Bake Changed keeps a door's old %s after the %s is changed" % [key, key],
			(
				(
					"door 'gate' baked, then %s set to %s through set_entity_property() (what "
					+ "the Entity panel calls). The tracker tagged %d brush(es) and bake_dirty() "
					+ "returned %s. The baked mover still carries %s."
				)
				% [key, value, int(run["tracker tagged"]), run["bake_dirty ran"], after]
			)
		)
	await drop_root(root)


func _a_retie(at: Vector3) -> void:
	# Two leaves tied as two doors of their own, then tied together as one.
	var root: Node3D = await fresh_root()
	box(root, Vector3(8, 0.2, 8), at + Vector3(0, -0.1, 0))
	var ids: Array = []
	for i in 2:
		var b = box(root, Vector3(1, 2, 0.2), at + Vector3(i * 1.0 - 0.5, 1, 0))
		ids.append(str(b.get_meta("brush_id", "")))
		root.tie_brushes_to_entity([ids[i]], "func_door")
	await root.bake(false, false)
	await frame()
	var tracker = Tracker.new()
	tracker.prime(root)
	var before := _baked_doors(root)
	root.tie_brushes_to_entity(ids, "func_door")
	var run := await _bake_changed(root, tracker)
	var after := _baked_doors(root)
	note("two one-leaf doors tied together as one, then Bake Changed", run)
	await root.bake(false, false)
	await frame()
	var full := _baked_doors(root)
	note(
		(
			"  baked doors before %d, after Bake Changed %d, after a full bake %d"
			% [before, after, full]
		)
	)
	if after == full:
		note("  Bake Changed holds as many doors as a full bake")
	else:
		flag(
			"Bake Changed keeps two doors after their leaves are tied as one",
			(
				(
					"two func_door brushes, each its own door, baked; then tied together with "
					+ "tie_brushes_to_entity(). The tracker tagged %d brush(es), bake_dirty() "
					+ "returned %s, and the bake still holds %d doors, so the leaves open apart."
				)
				% [int(run["tracker tagged"]), run["bake_dirty ran"], after]
			)
		)
	await drop_root(root)


func _a_rename(at: Vector3) -> void:
	# The control: a rename is in the tracker's signature, so this should rebuild.
	var root: Node3D = await fresh_root()
	var ids := _door(root, at, "gate")
	await root.bake(false, false)
	await frame()
	var tracker = Tracker.new()
	tracker.prime(root)
	root.tie_brushes_to_entity(ids, "func_door", "portcullis")
	var run := await _bake_changed(root, tracker)
	note("door renamed 'gate' to 'portcullis', then Bake Changed (control)", run)
	note("  movers after", _movers(root).map(func(m): return m["name"]))
	await drop_root(root)
