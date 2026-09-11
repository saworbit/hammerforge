@tool
class_name HFValidation
extends RefCounted
## Centralized null/structure guards for LevelRoot subsystems.
##
## Replaces the 300+ scattered `if not root.draft_brushes_node: return false`
## patterns. Each helper returns a bool so callers can chain:
##
##     if not HFValidation.has_draft_containers(root):
##         return false


static func is_valid_root(root: Object) -> bool:
	return root != null and is_instance_valid(root)


## Verifies the standard draft/pending/baked containers exist. Used by the
## brush, paint, bake, and entity systems before any geometry mutation.
static func has_draft_containers(root: Object) -> bool:
	if not is_valid_root(root):
		return false
	var required := ["draft_brushes_node", "pending_node"]
	for name in required:
		var v = root.get(name)
		if not v or not is_instance_valid(v):
			return false
	return true


## Verifies the entity container exists.
static func has_entity_container(root: Object) -> bool:
	if not is_valid_root(root):
		return false
	var v = root.get("entities_node")
	return v != null and is_instance_valid(v)


## Verifies the baked container exists (required before bake commits / clears).
static func has_baked_container(root: Object) -> bool:
	if not is_valid_root(root):
		return false
	var v = root.get("baked_container")
	return v != null and is_instance_valid(v)


## Single-property check by name. For one-off validation; prefer the
## domain-specific helpers above when available.
static func has_node(root: Object, property_name: String) -> bool:
	if not is_valid_root(root):
		return false
	var v = root.get(property_name)
	return v != null and is_instance_valid(v)


## Checks that a list of named Node3D properties on root are all valid.
## Returns true only if every name resolves to a live instance.
static func has_nodes(root: Object, property_names: Array) -> bool:
	if not is_valid_root(root):
		return false
	for name in property_names:
		if not has_node(root, name):
			return false
	return true


## Logs which named container is missing (debug aid). Returns true if all
## present, false if any missing — and push_warning lists the absent ones.
static func require_nodes(root: Object, property_names: Array, context: String = "") -> bool:
	if not is_valid_root(root):
		push_warning("[HFValidation] root is null/invalid (%s)" % context)
		return false
	var missing: Array = []
	for name in property_names:
		if not has_node(root, name):
			missing.append(name)
	if missing.size() > 0:
		push_warning("[HFValidation] missing on root: %s (%s)" % [missing, context])
		return false
	return true


## What is wrong with the shape of a level state, or "" when nothing is.
##
## `restore_state()` reads a state into typed locals, so a key holding the wrong
## kind of thing is an engine error mid-restore — and by then the level has
## already been cleared, so a malformed `.hflevel` does not fail to load, it
## destroys what was loaded and then fails. A `.hflevel` is JSON on disk: it gets
## truncated by a full disk, edited by hand, written by an older version, or
## synced half finished, and every one of those arrives here.
##
## Only the keys `restore_state()` types are checked, and only when present, so a
## state written by a newer version is not refused for carrying something extra.
static func level_state_problem(state: Dictionary) -> String:
	const ARRAY_KEYS := [
		"brushes",
		"pending",
		"committed",
		"entities",
		"materials",
		"generators",
		"duplicators",
		"hollows",
		"paint_layers",
		"paint_connectors",
	]
	const DICTIONARY_KEYS := [
		"face_selection",
		"visgroups",
		"groups",
		"terrain_regions",
		"floor",
		"sun",
		"prefab_instances",
	]
	for key in ARRAY_KEYS:
		if state.has(key) and not (state[key] is Array):
			return "'%s' should be a list and is a %s" % [key, type_string(typeof(state[key]))]
	for key in DICTIONARY_KEYS:
		if state.has(key) and not (state[key] is Dictionary):
			return (
				"'%s' should be a set of values and is a %s"
				% [key, type_string(typeof(state[key]))]
			)
	return ""
