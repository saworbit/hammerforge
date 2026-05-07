@tool
class_name HFSystem
extends RefCounted
## Base class for HammerForge subsystems.
##
## Provides a uniform lifecycle (init/destroy/clear/set_enabled) so callers
## can treat any subsystem the same way during teardown, scene reload, or
## bulk-disable. Existing systems can opt in by changing
## `extends RefCounted` to `extends HFSystem` and removing duplicate
## `var root` / `_init` / `_enabled` declarations.

var root: Node3D
var _enabled: bool = true


func _init(level_root: Node3D = null) -> void:
	root = level_root


## Override to release pooled nodes, free containers, disconnect signals.
## Called from `level_root._exit_tree()`. Use `free()` on Node3D children,
## not `queue_free()` — the next frame may not arrive during teardown.
func destroy() -> void:
	pass


## Override to hide/reset transient state without freeing pooled resources.
## Distinct from destroy(): clear() expects the system to be reusable after.
func clear() -> void:
	pass


func set_enabled(value: bool) -> void:
	_enabled = value


func is_enabled() -> bool:
	return _enabled


## Helper for subclasses: returns false (and pushes a warning) if root is
## missing the required Node3D containers. Replaces scattered `if not
## root.draft_brushes_node: return false` patterns.
func _has_nodes(names: Array) -> bool:
	if not is_instance_valid(root):
		return false
	for n in names:
		var v = root.get(n)
		if not v or not is_instance_valid(v):
			return false
	return true
