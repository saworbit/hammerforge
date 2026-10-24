@tool
extends RefCounted
## Findings a mapper has looked at and accepted for this level (#1731).
##
## Some findings are right for the level and will stay: a decorative stair nobody
## walks, a step meant to be jumped, a brush inside another while a shape is
## being worked out. Reported on every pass, they buried the real problems, and an
## agent "fixed" what was meant. An accepted finding is set aside instead, with a
## note and the date, keyed by what it says and the objects it names, as
## `hf_validate` tells two findings apart. It is kept in the level's registries,
## so it saves with the `.hflevel` and the scene and undoes like any edit.
##
## Each record also holds a fingerprint of the objects as they stood when it was
## accepted. Once one of them changes, the finding comes back, marked changed
## since accepted, because the reason it was fine may not hold any more.

# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const DraftBrush = preload("brush_instance.gd")
const DraftEntity = preload("draft_entity.gd")
@warning_ignore_restore("shadowed_global_identifier")


## What tells this finding from every other: its kind of pass, its text, and the
## objects it names, by brush id or by path in the level.
static func key_of(root: Node, finding: Dictionary) -> String:
	return (
		"%s|%s|%s|%s"
		% [
			str(finding.get("type", "validate")),
			str(finding.get("message", "")),
			object_id(root, finding.get("node")),
			object_id(root, finding.get("other_node")),
		]
	)


## A brush by its id, which survives a save and a load; anything else by its path
## in the level; "" for none.
static func object_id(root: Node, node: Variant) -> String:
	if not (node is Node) or not is_instance_valid(node):
		return ""
	if node is DraftBrush and str(node.brush_id) != "":
		return "brush:%s" % str(node.brush_id)
	if root != null and is_instance_valid(root) and root.is_ancestor_of(node):
		return "node:%s" % str(root.get_path_to(node))
	return "node:%s" % str(node.name)


## The objects a finding names, as they stand now. Any change to a brush's place,
## size, shape, operation or faces, or to an entity's place, class or properties,
## gives another number.
static func fingerprint(finding: Dictionary) -> int:
	return hash(_state_of(finding.get("node")) + "|" + _state_of(finding.get("other_node")))


static func _state_of(node: Variant) -> String:
	if not (node is Node) or not is_instance_valid(node):
		return ""
	if node is DraftBrush:
		var brush := node as DraftBrush
		var verts: Array = []
		for face in brush.faces:
			if face != null:
				verts.append(face.local_verts)
		return var_to_str(
			[brush.global_transform, brush.size, int(brush.shape), int(brush.operation), verts]
		)
	if node is DraftEntity:
		var entity := node as DraftEntity
		return var_to_str([entity.global_transform, entity.entity_type, entity.entity_data])
	if node is Node3D:
		return var_to_str((node as Node3D).global_transform)
	return str(node.name)


## The records, key to `{message, note, date, fingerprint}`, held by the level's
## validation system.
static func records(root: Node) -> Dictionary:
	var system = root.get("validation_system") if root else null
	return system.accepted if system else {}


## Accept `finding`, with `note` saying why it is fine. Returns its key, or "" for
## a level that cannot hold one.
static func accept(root: Node, finding: Dictionary, note: String = "") -> String:
	var system = root.get("validation_system") if root else null
	if system == null:
		return ""
	var key := key_of(root, finding)
	system.accepted[key] = {
		"message": str(finding.get("message", "")),
		"note": note.strip_edges(),
		"date": Time.get_date_string_from_system(),
		"fingerprint": fingerprint(finding),
	}
	return key


## Take an acceptance back. False when there was none under `key`.
static func unaccept(root: Node, key: String) -> bool:
	var system = root.get("validation_system") if root else null
	if system == null or not system.accepted.has(key):
		return false
	system.accepted.erase(key)
	return true


## Split `findings` into those to show and those set aside. A finding accepted
## while its objects stood as they stand now is set aside, as a copy carrying its
## `key` and its record under `accepted`. One whose objects have changed since
## comes back as a copy marked `changed_since_accepted`, with the note.
static func sort(root: Node, findings: Array) -> Dictionary:
	var open: Array = []
	var set_aside: Array = []
	var held := records(root)
	for item in findings:
		if not (item is Dictionary):
			continue
		var finding: Dictionary = item
		var key := key_of(root, finding)
		var record: Variant = held.get(key)
		if not (record is Dictionary):
			open.append(finding)
			continue
		var copy := finding.duplicate()
		copy["key"] = key
		if int(record.get("fingerprint", 0)) == fingerprint(finding):
			copy["accepted"] = record
			set_aside.append(copy)
		else:
			copy["changed_since_accepted"] = true
			copy["accepted_note"] = str(record.get("note", ""))
			open.append(copy)
	return {"open": open, "accepted": set_aside}
