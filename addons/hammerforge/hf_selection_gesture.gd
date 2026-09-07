@tool
class_name HFSelectionGesture
extends RefCounted

## Owns one Select-tool LMB sequence. HammerForge delays marquee ownership long
## enough for Godot's native transform gizmo to claim the same press, then keeps
## exactly one owner through release.

enum Owner { NONE, PENDING, MARQUEE, NATIVE_GIZMO }
enum MotionDecision { IDLE, WAITING, DRAW_MARQUEE, NATIVE_GIZMO, RECOVERED }
enum ReleaseDecision { PASS_THROUGH, CLICK, MARQUEE, NATIVE_GIZMO }

var owner := Owner.NONE
var origin := Vector2.ZERO
var current := Vector2.ZERO
var additive := false
var toggle := false
var face_select := false
var marquee_allowed := false
var click_allowed := true
var native_passthrough := false
var native_cancel_candidate := false

var _native_probe_complete := false
var _transform_snapshots: Array[Dictionary] = []


func begin(
	position: Vector2,
	additive_selection: bool,
	toggle_selection: bool,
	face_selection: bool,
	allow_marquee: bool,
	allow_click: bool,
	pass_to_native: bool,
	selected_nodes: Array,
	may_be_native_gizmo: bool = false,
) -> void:
	reset()
	owner = Owner.PENDING
	origin = position
	current = position
	additive = additive_selection
	toggle = toggle_selection
	face_select = face_selection
	marquee_allowed = allow_marquee
	click_allowed = allow_click
	native_passthrough = pass_to_native
	native_cancel_candidate = may_be_native_gizmo
	_capture_transforms(selected_nodes)


func reset() -> void:
	owner = Owner.NONE
	origin = Vector2.ZERO
	current = Vector2.ZERO
	additive = false
	toggle = false
	face_select = false
	marquee_allowed = false
	click_allowed = true
	native_passthrough = false
	native_cancel_candidate = false
	_native_probe_complete = false
	_transform_snapshots.clear()


func is_active() -> bool:
	return owner != Owner.NONE


func is_native_owned() -> bool:
	return owner == Owner.NATIVE_GIZMO


func is_marquee_owned() -> bool:
	return owner == Owner.MARQUEE


## RMB and Escape must reach Godot while one of its opaque built-in gizmos may
## own this press. CUSTOM forwarding still lets gizmos inspect LMB, but there is
## no public callback for native transform/property gizmos to announce a claim.
func should_yield_cancel_to_native() -> bool:
	return owner == Owner.NATIVE_GIZMO or native_passthrough or native_cancel_candidate


func claim_native_gizmo() -> void:
	if owner != Owner.NONE:
		owner = Owner.NATIVE_GIZMO


func update_motion(position: Vector2, left_button_held: bool, threshold: float) -> int:
	if owner == Owner.NONE:
		return MotionDecision.IDLE
	current = position
	if not left_button_held:
		reset()
		return MotionDecision.RECOVERED
	if owner == Owner.NATIVE_GIZMO:
		return MotionDecision.NATIVE_GIZMO
	if _selected_transform_changed():
		owner = Owner.NATIVE_GIZMO
		return MotionDecision.NATIVE_GIZMO
	if origin.distance_to(position) < threshold:
		return MotionDecision.WAITING
	if not marquee_allowed:
		return MotionDecision.WAITING
	# A native transform gizmo is not exposed through EditorPlugin. Give it one
	# forwarded motion event to mutate the captured transform before claiming a
	# marquee. Custom brush handles claim explicitly through their plugin signal.
	if not _transform_snapshots.is_empty() and not _native_probe_complete:
		_native_probe_complete = true
		return MotionDecision.WAITING
	owner = Owner.MARQUEE
	return MotionDecision.DRAW_MARQUEE


func finish(position: Vector2, threshold: float) -> Dictionary:
	var result := {
		"decision": ReleaseDecision.PASS_THROUGH,
		"origin": origin,
		"position": position,
		"distance": origin.distance_to(position),
		"additive": additive,
		"toggle": toggle,
		"face_select": face_select,
		"native_cancel_candidate": native_cancel_candidate,
	}
	if owner == Owner.NONE:
		return result
	current = position
	if owner == Owner.NATIVE_GIZMO or _selected_transform_changed():
		result["decision"] = ReleaseDecision.NATIVE_GIZMO
	elif owner == Owner.MARQUEE or (marquee_allowed and origin.distance_to(position) >= threshold):
		result["decision"] = ReleaseDecision.MARQUEE
	elif click_allowed and (origin.distance_to(position) < threshold or not marquee_allowed):
		result["decision"] = ReleaseDecision.CLICK
	reset()
	return result


func _capture_transforms(selected_nodes: Array) -> void:
	for node in selected_nodes:
		if not (node is Node3D) or not is_instance_valid(node):
			continue
		_transform_snapshots.append(
			{"node": weakref(node), "transform": (node as Node3D).global_transform}
		)


func _selected_transform_changed() -> bool:
	for snapshot in _transform_snapshots:
		var node_ref: WeakRef = snapshot.get("node")
		var node = node_ref.get_ref() if node_ref else null
		if not is_instance_valid(node) or not (node is Node3D):
			continue
		var original: Transform3D = snapshot.get("transform", Transform3D.IDENTITY)
		if not (node as Node3D).global_transform.is_equal_approx(original):
			return true
	return false
