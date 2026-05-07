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
	var v = root.get("draft_entities_node")
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
