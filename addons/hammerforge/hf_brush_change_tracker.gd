@tool
class_name HFBrushChangeTracker
extends RefCounted

## Reconciles edits owned by Godot's native Inspector/transform gizmos with
## HammerForge's incremental bake tags. The cache is deliberately keyed by the
## stable brush ID so native undo/redo and node recreation cannot confuse it.

const PREFAB_LINK_META := [
	&"hf_prefab_entity_id", &"hf_prefab_instance", &"hf_prefab_source", &"hf_prefab_variant"
]

var _root_instance_id := 0
var _signatures: Dictionary = {}
var _instances_by_id: Dictionary = {}
var _containers_by_id: Dictionary = {}
var _parents_by_id: Dictionary = {}
var _entity_names_by_instance: Dictionary = {}
var _entity_prefab_links_by_instance: Dictionary = {}
var _bake_configuration: Dictionary = {}


func reset() -> void:
	_root_instance_id = 0
	_signatures.clear()
	_instances_by_id.clear()
	_containers_by_id.clear()
	_parents_by_id.clear()
	_entity_names_by_instance.clear()
	_entity_prefab_links_by_instance.clear()
	_bake_configuration.clear()


func is_tracking_root(root: Node) -> bool:
	return root != null and is_instance_valid(root) and _root_instance_id == root.get_instance_id()


func ensure_root(root: Node) -> void:
	if not is_tracking_root(root):
		prime(root)


func prime(root: Node) -> void:
	reset()
	if not root or not is_instance_valid(root):
		return
	_root_instance_id = root.get_instance_id()
	var brushes := _brushes(root)
	var repaired_ids := _normalize_brush_ids(root, brushes)
	if repaired_ids:
		_tag_structural_change(root)
		brushes = _brushes(root)
	for brush in brushes:
		var brush_id := _brush_id(brush)
		if not brush_id.is_empty():
			_signatures[brush_id] = _signature(brush)
			_instances_by_id[brush_id] = brush.get_instance_id()
			_containers_by_id[brush_id] = _container_role(brush)
			_parents_by_id[brush_id] = weakref(brush.get_parent())
	var entities := _entity_nodes(root)
	_entity_names_by_instance = _entity_names(entities)
	_entity_prefab_links_by_instance = _entity_prefab_links(entities)
	_bake_configuration = _bake_configuration_signature(root)


## Tag changed existing brushes, update the baseline, add new IDs without a
## duplicate tag (creation already tags), and forget deleted IDs.
func reconcile(root: Node) -> PackedStringArray:
	var changed := PackedStringArray()
	if not root or not is_instance_valid(root):
		reset()
		return changed
	if not is_tracking_root(root):
		prime(root)
		return changed

	_recover_illegal_reparents(root)
	var current_bake_configuration := _bake_configuration_signature(root)
	var bake_configuration_changed := current_bake_configuration != _bake_configuration
	var brushes := _brushes(root)
	var repaired_ids := _normalize_brush_ids(root, brushes)
	var current_instances: Dictionary = {}
	var current_containers: Dictionary = {}
	var current_parents: Dictionary = {}
	for brush in brushes:
		var brush_id := _brush_id(brush)
		if brush_id.is_empty():
			continue
		current_instances[brush_id] = brush.get_instance_id()
		current_containers[brush_id] = _container_role(brush)
		current_parents[brush_id] = weakref(brush.get_parent())

	var structure_changed := repaired_ids or _instances_by_id.size() != current_instances.size()
	var managed_container_changes: Dictionary = {}
	if not structure_changed:
		for brush_id in current_instances:
			if _instances_by_id.get(brush_id, 0) != current_instances[brush_id]:
				structure_changed = true
				break
			var old_role := str(_containers_by_id.get(brush_id, ""))
			var new_role := str(current_containers.get(brush_id, ""))
			if old_role != new_role:
				var brush := _brush_for_id(brushes, str(brush_id))
				if brush and str(brush.get_meta("hf_container_role", "")) == new_role:
					# HammerForge moved this brush deliberately (Apply/Commit/Restore).
					# Those operations already own the bake boundary, so only re-seed.
					managed_container_changes[brush_id] = true
				else:
					structure_changed = true
					break
	if structure_changed:
		_tag_structural_change(root)
		brushes = _brushes(root)
	elif bake_configuration_changed and root.has_method("tag_full_reconcile"):
		# Inspector and native Undo bypass LevelRoot's editor UI callbacks. A bake
		# setting change invalidates every output even when all brushes are stable.
		root.call("tag_full_reconcile")

	var current: Dictionary = {}
	current_instances.clear()
	current_containers.clear()
	current_parents.clear()
	for brush in brushes:
		var brush_id := _brush_id(brush)
		if brush_id.is_empty():
			continue
		var signature := _signature(brush)
		current_instances[brush_id] = brush.get_instance_id()
		current_containers[brush_id] = _container_role(brush)
		current_parents[brush_id] = weakref(brush.get_parent())
		if (
			_signatures.has(brush_id)
			and not managed_container_changes.has(brush_id)
			and _signature_changed(_signatures[brush_id], signature)
		):
			var previous_signature: Dictionary = _signatures[brush_id]
			if previous_signature.get("faces") != signature.get("faces"):
				_refresh_face_preview(brush)
				signature = _signature(brush)
			if root.has_method("tag_brush_dirty"):
				root.call("tag_brush_dirty", brush_id)
			changed.append(brush_id)
		current[brush_id] = signature

	var entities := _entity_nodes(root)
	_normalize_native_entity_prefab_duplicates(entities)
	var current_entity_names := _entity_names(entities)
	if current_entity_names != _entity_names_by_instance:
		if root.has_method("reconcile_external_entity_names"):
			# Deletion intentionally reports only the structural/name delta. Soft I/O
			# target strings remain untouched so Godot Undo can restore resolution.
			(
				root
				. call(
					"reconcile_external_entity_names",
					_entity_names_by_instance,
					current_entity_names,
				)
			)
	_signatures = current
	_instances_by_id = current_instances
	_containers_by_id = current_containers
	_parents_by_id = current_parents
	_entity_names_by_instance = current_entity_names
	_entity_prefab_links_by_instance = _entity_prefab_links(entities)
	_bake_configuration = current_bake_configuration
	return changed


func _brushes(root: Node) -> Array:
	var authoritative := root.has_method("_iter_managed_brush_nodes")
	if not authoritative and not root.has_method("_iter_pick_nodes"):
		return []
	var brushes: Array = []
	var candidates: Variant = root.call(
		"_iter_managed_brush_nodes" if authoritative else "_iter_pick_nodes"
	)
	if not (candidates is Array):
		return brushes
	for candidate in candidates:
		if not is_instance_valid(candidate) or not (candidate is Node3D):
			continue
		if (
			not authoritative
			and root.has_method("is_brush_node")
			and not bool(root.call("is_brush_node", candidate))
		):
			continue
		brushes.append(candidate)
	return brushes


func _recover_illegal_reparents(root: Node) -> void:
	# A native Scene-tree drag can move a DraftBrush under Entities, a helper,
	# or LevelRoot itself. Such a node disappears from the authoritative brush
	# traversal and becomes deceptively uneditable. Recover only a still-live,
	# previously tracked node that remains inside this LevelRoot. Detached,
	# deleted, or moved-to-another-scene nodes are deliberately never resurrected.
	for brush_id in _instances_by_id:
		var brush_object := instance_from_id(int(_instances_by_id[brush_id]))
		if not brush_object is Node or not is_instance_valid(brush_object):
			continue
		var brush := brush_object as Node
		if brush.is_queued_for_deletion() or brush.get_parent() == null:
			continue
		if not root.is_ancestor_of(brush):
			continue
		var previous_ref := _parents_by_id.get(brush_id, null) as WeakRef
		if previous_ref == null:
			continue
		var previous_parent := previous_ref.get_ref() as Node
		if previous_parent == null or not is_instance_valid(previous_parent):
			continue
		if previous_parent != root and not root.is_ancestor_of(previous_parent):
			continue
		var current_parent := brush.get_parent()
		if current_parent == previous_parent:
			continue
		var managed_role := _managed_container_role(root, current_parent)
		if (
			not managed_role.is_empty()
			and str(brush.get_meta("hf_container_role", "")) == managed_role
		):
			# Apply/Commit/Restore synchronizes role metadata before reconciliation.
			# Accept that managed move and seed its new parent as the baseline.
			continue
		brush.reparent(previous_parent, true)


static func _managed_container_role(root: Node, parent: Node) -> String:
	if parent == null:
		return ""
	if parent == root:
		# Lightweight integrations may store drafts directly on their root. A real
		# LevelRoot with DraftBrushes never considers a direct child managed.
		return "" if root.get_node_or_null("DraftBrushes") != null else "draft"
	if parent.get_parent() != root:
		return ""
	match str(parent.name):
		"DraftBrushes":
			return "draft"
		"PendingCuts":
			return "pending"
		"CommittedCuts":
			return "committed"
		_:
			return ""


func _entity_nodes(root: Node) -> Array[Node]:
	var entities: Array[Node] = []
	if not root.has_method("_iter_pick_nodes"):
		return entities
	var candidates: Variant = root.call("_iter_pick_nodes")
	if not candidates is Array:
		return entities
	for candidate in candidates:
		if not is_instance_valid(candidate) or not candidate is Node:
			continue
		var is_entity := (
			root.has_method("is_entity_node") and bool(root.call("is_entity_node", candidate))
		)
		var is_brush := (
			root.has_method("is_brush_node") and bool(root.call("is_brush_node", candidate))
		)
		var is_brush_entity := (
			is_brush and not str(candidate.get_meta("brush_entity_class", "")).is_empty()
		)
		if is_entity or is_brush_entity:
			entities.append(candidate)
	return entities


static func _entity_names(entities: Array[Node]) -> Dictionary:
	var names: Dictionary = {}
	for entity in entities:
		names[entity.get_instance_id()] = str(entity.name)
	return names


static func _entity_prefab_links(entities: Array[Node]) -> Dictionary:
	var links: Dictionary = {}
	for entity in entities:
		links[entity.get_instance_id()] = _prefab_link(entity)
	return links


func _normalize_native_entity_prefab_duplicates(entities: Array[Node]) -> void:
	var current_ids: Dictionary = {}
	for entity in entities:
		current_ids[entity.get_instance_id()] = true

	var existing_links: Dictionary = {}
	for instance_id in _entity_prefab_links_by_instance:
		if not current_ids.has(instance_id):
			continue
		var fingerprint := _prefab_link_fingerprint(_entity_prefab_links_by_instance[instance_id])
		if not fingerprint.is_empty():
			existing_links[fingerprint] = true

	for entity in entities:
		if _entity_prefab_links_by_instance.has(entity.get_instance_id()):
			continue
		var fingerprint := _prefab_link_fingerprint(_prefab_link(entity))
		if not fingerprint.is_empty() and existing_links.has(fingerprint):
			_clear_prefab_linkage(entity)


static func _prefab_link(node: Node) -> Dictionary:
	var link: Dictionary = {}
	for meta_name in PREFAB_LINK_META:
		link[meta_name] = str(node.get_meta(meta_name, ""))
	return link


static func _prefab_link_fingerprint(link: Dictionary) -> String:
	var values: Array[String] = []
	var has_value := false
	for meta_name in PREFAB_LINK_META:
		var value := str(link.get(meta_name, ""))
		values.append(value)
		has_value = has_value or not value.is_empty()
	return JSON.stringify(values) if has_value else ""


static func _clear_prefab_linkage(node: Node) -> void:
	for meta_name in PREFAB_LINK_META:
		if node.has_meta(meta_name):
			node.remove_meta(meta_name)


static func _bake_configuration_signature(root: Node) -> Dictionary:
	var signature: Dictionary = {}
	for property in root.get_property_list():
		var property_name := str(property.get("name", ""))
		if (
			not property_name.begins_with("bake_")
			and property_name not in ["cordon_enabled", "cordon_aabb"]
		):
			continue
		if (int(property.get("usage", 0)) & PROPERTY_USAGE_EDITOR) == 0:
			continue
		var value: Variant = root.get(property_name)
		signature[property_name] = _configuration_value(value)
	return signature


static func _configuration_value(value: Variant) -> Variant:
	if value is Object:
		return _object_identity(value)
	if value is Array:
		return (value as Array).duplicate(true)
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return value


static func _brush_id(brush: Node) -> String:
	var brush_id := str(brush.get_meta("brush_id", ""))
	if brush_id.is_empty():
		var property_id: Variant = brush.get("brush_id")
		brush_id = str(property_id) if property_id != null else ""
	return brush_id


static func _container_role(brush: Node) -> String:
	var parent := brush.get_parent()
	if not parent:
		return ""
	match str(parent.name):
		"PendingCuts":
			return "pending"
		"CommittedCuts":
			return "committed"
		_:
			return "draft"


static func _brush_for_id(brushes: Array, brush_id: String) -> Node:
	for brush in brushes:
		if _brush_id(brush) == brush_id:
			return brush
	return null


static func _signature(brush: Node3D) -> Dictionary:
	return {
		"transform": brush.global_transform,
		"visible": brush.visible,
		"size": brush.get("size"),
		"shape": brush.get("shape"),
		"operation": brush.get("operation"),
		"sides": brush.get("sides"),
		"material": _object_identity(brush.get("material_override")),
		"faces": _faces_signature(brush.get("faces")),
	}


static func _object_identity(value: Variant) -> int:
	return value.get_instance_id() if value is Object and is_instance_valid(value) else 0


## FaceData is an exported nested resource, so Godot's Inspector can edit it
## without invoking any LevelRoot mutation boundary. Capture the bake-relevant
## value state rather than only the resource identity; otherwise UV, material,
## vertex, paint, or displacement changes can leave Bake Changed stale.
static func _faces_signature(value: Variant) -> Array:
	var result: Array = []
	if not value is Array:
		return result
	for face_value in value:
		if not face_value is Object or not is_instance_valid(face_value):
			result.append(null)
			continue
		var face := face_value as Object
		(
			result
			. append(
				{
					"material_idx": face.get("material_idx"),
					"uv_projection": face.get("uv_projection"),
					"uv_scale": face.get("uv_scale"),
					"uv_offset": face.get("uv_offset"),
					"uv_rotation": face.get("uv_rotation"),
					"custom_uvs": _snapshot_packed_array(face.get("custom_uvs")),
					"local_verts": _snapshot_packed_array(face.get("local_verts")),
					"paint_layers": _paint_layers_signature(face.get("paint_layers")),
					"displacement": _displacement_signature(face.get("displacement")),
				}
			)
		)
	return result


static func _paint_layers_signature(value: Variant) -> Array:
	var result: Array = []
	if not value is Array:
		return result
	for layer_value in value:
		if not layer_value is Object or not is_instance_valid(layer_value):
			result.append(null)
			continue
		var layer := layer_value as Object
		(
			result
			. append(
				{
					"texture": _object_identity(layer.get("texture")),
					"weight_image": _image_signature(layer.get("weight_image")),
					"blend_mode": layer.get("blend_mode"),
					"opacity": layer.get("opacity"),
				}
			)
		)
	return result


static func _image_signature(value: Variant) -> Variant:
	if not value is Image or not is_instance_valid(value):
		return null
	var image := value as Image
	return {
		"identity": image.get_instance_id(),
		"size": image.get_size(),
		"format": image.get_format(),
		"mipmaps": image.has_mipmaps(),
		"data_hash": hash(image.get_data()),
	}


static func _displacement_signature(value: Variant) -> Variant:
	if not value is Object or not is_instance_valid(value):
		return null
	var displacement := value as Object
	return {
		"power": displacement.get("power"),
		"distances": _snapshot_packed_array(displacement.get("distances")),
		"offsets": _snapshot_packed_array(displacement.get("offsets")),
		"alphas": _snapshot_packed_array(displacement.get("alphas")),
		"sew_group": displacement.get("sew_group"),
		"elevation": displacement.get("elevation"),
	}


static func _snapshot_packed_array(value: Variant) -> Variant:
	# Packed arrays may share their backing store with a Resource property. An
	# Inspector/in-place element edit would then mutate both the live value and a
	# naively cached signature, making the change invisible to reconciliation.
	if value is PackedVector2Array:
		return (value as PackedVector2Array).duplicate()
	if value is PackedVector3Array:
		return (value as PackedVector3Array).duplicate()
	if value is PackedFloat32Array:
		return (value as PackedFloat32Array).duplicate()
	return value


func _normalize_brush_ids(root: Node, brushes: Array) -> bool:
	var groups: Dictionary = {}
	var reserved: Dictionary = {}
	var empty_id_brushes: Array = []
	for brush in brushes:
		var brush_id := _brush_id(brush)
		if brush_id.is_empty():
			empty_id_brushes.append(brush)
			continue
		reserved[brush_id] = true
		if not groups.has(brush_id):
			groups[brush_id] = []
		groups[brush_id].append(brush)

	var repaired := false
	for brush_id in groups:
		var duplicates: Array = groups[brush_id]
		var keeper := duplicates[0] as Node
		var known_instance := int(_instances_by_id.get(brush_id, 0))
		if known_instance != 0:
			for candidate in duplicates:
				if candidate.get_instance_id() == known_instance:
					keeper = candidate
					break
		repaired = _write_brush_id(keeper, str(brush_id)) or repaired
		for duplicate in duplicates:
			if duplicate == keeper:
				continue
			_make_brush_resources_unique(duplicate)
			_clear_prefab_linkage(duplicate)
			_write_brush_id(duplicate, _next_unique_brush_id(root, reserved, duplicate))
			repaired = true
	for brush in empty_id_brushes:
		_write_brush_id(brush, _next_unique_brush_id(root, reserved, brush))
		repaired = true
	return repaired


static func _next_unique_brush_id(root: Node, reserved: Dictionary, brush: Node) -> String:
	var candidate := ""
	for _attempt in range(64):
		candidate = str(root.call("_next_brush_id")) if root.has_method("_next_brush_id") else ""
		if candidate.is_empty():
			candidate = "external_%d_%d" % [Time.get_ticks_usec(), brush.get_instance_id()]
		if not reserved.has(candidate):
			reserved[candidate] = true
			return candidate
	# The instance suffix makes this deterministic and collision-safe even if a
	# malformed root keeps returning the same custom ID.
	candidate = (
		"%s_%d" % [candidate if not candidate.is_empty() else "external", brush.get_instance_id()]
	)
	while reserved.has(candidate):
		candidate += "_copy"
	reserved[candidate] = true
	return candidate


static func _write_brush_id(brush: Node, brush_id: String) -> bool:
	var changed := false
	if str(brush.get("brush_id")) != brush_id:
		brush.set("brush_id", brush_id)
		changed = true
	if not brush.has_meta("brush_id") or str(brush.get_meta("brush_id")) != brush_id:
		brush.set_meta("brush_id", brush_id)
		changed = true
	return changed


static func _refresh_face_preview(brush: Node) -> void:
	if brush.has_method("rebuild_preview"):
		brush.call("rebuild_preview")


static func _make_brush_resources_unique(brush: Node) -> void:
	if brush.has_method("make_face_resources_unique"):
		brush.call("make_face_resources_unique")


static func _tag_structural_change(root: Node) -> void:
	if root.has_method("tag_full_reconcile"):
		root.call("tag_full_reconcile")
	if root.has_method("reconcile_external_brush_structure"):
		root.call("reconcile_external_brush_structure")


static func _signature_changed(before: Dictionary, after: Dictionary) -> bool:
	var old_transform: Transform3D = before.get("transform", Transform3D.IDENTITY)
	var new_transform: Transform3D = after.get("transform", Transform3D.IDENTITY)
	if not old_transform.is_equal_approx(new_transform):
		return true
	var old_size: Variant = before.get("size")
	var new_size: Variant = after.get("size")
	if old_size is Vector3 and new_size is Vector3:
		if not (old_size as Vector3).is_equal_approx(new_size as Vector3):
			return true
	elif old_size != new_size:
		return true
	for field in ["visible", "shape", "operation", "sides", "material", "faces"]:
		if before.get(field) != after.get(field):
			return true
	return false
