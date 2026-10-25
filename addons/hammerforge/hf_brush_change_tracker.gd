@tool
class_name HFBrushChangeTracker
extends RefCounted

## Reconciles edits owned by Godot's native Inspector/transform gizmos with
## HammerForge's incremental bake tags, turns a door's or a spawn's angle with a
## turn they make, and unpicks the faces of a brush Godot's Delete took away.
## The cache is deliberately keyed by the stable brush ID so native
## undo/redo and node recreation cannot confuse it.

# Preloaded under its global name so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const DraftBrush = preload("brush_instance.gd")
const DraftEntity = preload("draft_entity.gd")
const HFPrefabSystem = preload("systems/hf_prefab_system.gd")
const HFBakeSplit = preload("hf_bake_split.gd")
@warning_ignore_restore("shadowed_global_identifier")
const HFBakeSystemType = preload("systems/hf_bake_system.gd")

var _root_instance_id := 0
var _signatures: Dictionary = {}
var _instances_by_id: Dictionary = {}
var _containers_by_id: Dictionary = {}
var _parents_by_id: Dictionary = {}
var _entity_names_by_instance: Dictionary = {}
var _entity_prefab_links_by_instance: Dictionary = {}
var _bake_configuration: Dictionary = {}
## Where HammerForge's own commands last left each brush they touched since the
## last reconcile, by brush id: what a turn Godot made is measured from.
var _placed_by_commands: Dictionary = {}
var _watched_root: WeakRef = null
## Where each point entity stood and the `angle` it held at the last reconcile,
## by instance.
var _entity_turns_by_instance: Dictionary = {}
## How many nodes each of the level's folders held at the last reconcile.
var _folder_counts: Array = []

# The check after a step looks at the brushes the step can have touched rather
# than at every brush, which grew with the level: 296 ms at 3,000 brushes
# (#1619). These say which brushes those are, and owe a full walk when they
# cannot.

## Records kept of what steps changed, oldest dropped first.
const MAX_STEP_RECORDS := 512
## Brush ids each step of the scene's undo history changed, by the version the
## step led to, so its undo or redo checks those brushes.
var _step_brushes: Dictionary = {}
## The name of the step each version led to, when it was last seen, so a new step
## taken where a redo was waiting is told from that redo.
var _step_names: Dictionary = {}
## The scene history's version, and whether it held a redo, as last noted. -1
## before the first note.
var _noted_version := -1
var _noted_redo := false
## Versions noted since the last reconcile, whose record that reconcile writes.
var _unrecorded_versions: Array[int] = []
## Brush ids the undo or redo of a recorded step puts back, by id.
var _owed_ids: Dictionary = {}
## A step noted since the last reconcile that nothing narrows to some brushes.
var _owed_full := false
## Every brush HammerForge's own commands tagged since the last reconcile.
var _tagged_ids: Dictionary = {}
## A reconcile looked at only some brushes since the last full walk, so a change
## made outside them waits for the full walk a bake asks for.
var _full_walk_owed := false


func reset() -> void:
	_stop_watching()
	_root_instance_id = 0
	_signatures.clear()
	_instances_by_id.clear()
	_containers_by_id.clear()
	_parents_by_id.clear()
	_entity_names_by_instance.clear()
	_entity_prefab_links_by_instance.clear()
	_entity_turns_by_instance.clear()
	_folder_counts.clear()
	_bake_configuration.clear()
	_step_brushes.clear()
	_step_names.clear()
	_noted_version = -1
	_noted_redo = false
	_unrecorded_versions.clear()
	_owed_ids.clear()
	_owed_full = false
	_tagged_ids.clear()
	_full_walk_owed = false


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
	_watch(root)
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
	_entity_turns_by_instance = _entity_turns(entities)
	_folder_counts = _folder_counts_of(root)
	_bake_configuration = _bake_configuration_signature(root)


## Note that the scene's undo history moved to `version`, holding a redo or not,
## and that `action_name` is the step it now stands on. The plugin calls this on
## every version change, so the next `reconcile_step()` knows which brushes the
## steps since can have touched.
##
## A step taken from the newest version is an edit of the selection, by Godot's
## gizmo or Inspector, or a command of HammerForge's that tags what it changes.
## An undo puts back what the step it undoes changed, and a redo what the step it
## redoes changed, which the record of that step says. A step with no record, or
## a jump of more than one, owes a full walk.
func note_step(version: int, has_redo: bool, action_name := "") -> void:
	if _noted_version < 0:
		_owed_full = true
	elif version == _noted_version:
		# A step merged into the newest one, as a dragged Inspector slider is, or a
		# step in another history. What it changed joins the newest step's record.
		_unrecorded_versions.append(version)
	elif version == _noted_version + 1:
		# With a redo waiting this may be that redo, or a new step in its place;
		# the record covers the one and the selection and tags the other. A name
		# other than the redo's is a new step, which a redo cannot be.
		var redo_name := str(_step_names.get(version, ""))
		var new_step := action_name != "" and redo_name != "" and redo_name != action_name
		if _noted_redo and not new_step:
			if _step_brushes.has(version):
				_owe(_step_brushes[version])
			else:
				_owed_full = true
		_unrecorded_versions.append(version)
		_step_names[version] = action_name
		if not has_redo:
			# The redos are gone, and with them the steps those records were of.
			for later in _step_brushes.keys():
				if int(later) > version:
					_step_brushes.erase(later)
			for later in _step_names.keys():
				if int(later) > version:
					_step_names.erase(later)
	elif version == _noted_version - 1:
		if _step_brushes.has(_noted_version):
			_owe(_step_brushes[_noted_version])
		else:
			_owed_full = true
	else:
		_owed_full = true
	_noted_version = version
	_noted_redo = has_redo


func _owe(brush_ids: PackedStringArray) -> void:
	for brush_id in brush_ids:
		_owed_ids[brush_id] = true


## The check the plugin runs after a step: the brushes the step can have touched
## when the notes say which, and every brush when `full` asks for it, when a
## noted step cannot be narrowed, or when the level's brushes or entities came or
## went. `selected` is the editor's selection, the nodes Godot's gizmo and
## Inspector edit.
func reconcile_step(root: Node, selected: Array, full := false) -> PackedStringArray:
	if full or _owed_full or not is_tracking_root(root):
		return reconcile(root)
	var scope: Variant = _step_scope(root, selected)
	if scope == null:
		return reconcile(root)
	var changed: Variant = _reconcile_scope(root, scope)
	if changed == null:
		return reconcile(root)
	return changed


## Whether a reconcile since the last full walk looked at only some brushes.
func owes_full_walk() -> bool:
	return _full_walk_owed


## Tag changed existing brushes, update the baseline, add new IDs without a
## duplicate tag (creation already tags), and forget deleted IDs.
func reconcile(root: Node) -> PackedStringArray:
	var changed := PackedStringArray()
	if not root or not is_instance_valid(root):
		reset()
		return changed
	if not is_tracking_root(root):
		prime(root)
		root.call("drop_faces_of_departed_brushes")
		return changed

	# Taken before anything below tags a brush itself.
	var placed := _placed_by_commands.duplicate()
	_recover_illegal_reparents(root)
	var current_bake_configuration := _bake_configuration_signature(root)
	var bake_configuration_changed := current_bake_configuration != _bake_configuration
	var brushes := _brushes(root)
	var repaired_ids := _normalize_brush_ids(root, brushes)
	_normalize_handedness(root, brushes)
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
	elif bake_configuration_changed:
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
		if not managed_container_changes.has(brush_id):
			_follow_native_turn(root, brush, brush_id, placed)
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
			root.call("tag_brush_dirty", brush_id)
			changed.append(brush_id)
		current[brush_id] = signature

	var entities := _entity_nodes(root)
	_normalize_native_entity_prefab_duplicates(entities)
	for entity in entities:
		_follow_native_entity_turn(root, entity)
	var current_entity_names := _entity_names(entities)
	if current_entity_names != _entity_names_by_instance:
		# Deletion intentionally reports only the structural/name delta. Soft I/O
		# target strings remain untouched so Godot Undo can restore resolution.
		root.call(
			"reconcile_external_entity_names", _entity_names_by_instance, current_entity_names
		)
	_signatures = current
	_instances_by_id = current_instances
	_containers_by_id = current_containers
	_parents_by_id = current_parents
	_entity_names_by_instance = current_entity_names
	_entity_prefab_links_by_instance = _entity_prefab_links(entities)
	_entity_turns_by_instance = _entity_turns(entities)
	_folder_counts = _folder_counts_of(root)
	_bake_configuration = current_bake_configuration
	_placed_by_commands.clear()
	_full_walk_owed = false
	_finish_check(changed, structure_changed)
	# Not only on a structure change seen above: that is measured against what
	# this tracker last saw, and a brush made since without a step of its own is
	# not in it. A face picked on a brush Godot then deleted stayed picked (#1515).
	root.call("drop_faces_of_departed_brushes")
	return changed


## The brush ids, by id, and the entity nodes a step can have touched: what the
## notes owe, what commands tagged and the selection. Null when that is every
## brush, as when the selection holds the level or one of its folders, which
## moves every brush in it.
func _step_scope(root: Node, selected: Array) -> Variant:
	var brush_ids := _owed_ids.duplicate()
	brush_ids.merge(_tagged_ids)
	var entities: Array[Node] = []
	var folders: Array = []
	for folder_name in ["draft_brushes_node", "pending_node", "committed_node", "entities_node"]:
		var folder: Variant = root.get(folder_name)
		if folder is Node:
			folders.append(folder)
	for node in selected:
		if not (node is Node) or not is_instance_valid(node):
			continue
		if node == root or node.is_ancestor_of(root) or folders.has(node):
			return null
		if not root.is_ancestor_of(node):
			continue
		if node is DraftBrush:
			var brush_id := _brush_id(node)
			if brush_id.is_empty():
				return null
			brush_ids[brush_id] = true
		elif bool(root.call("is_entity_node", node)):
			entities.append(node)
	return {"brush_ids": brush_ids, "entities": entities}


## Reconcile only the brushes and entities `scope` names, as `reconcile()` does
## each brush, and leave the rest as they were last seen. A brush a command made
## and tagged is taken in as the full walk takes in a new one, and one the scope
## names that has gone is let go as the full walk lets it go: the undo of a
## placement takes away the brush its step's record names (#1866). Null, having
## changed nothing, when the level's structure moved any other way since: a brush
## or entity came, went or changed folder or id, or a node became an entity or
## stopped being one. Each of those is the full walk's to repair.
func _reconcile_scope(root: Node, scope: Dictionary) -> Variant:
	var moved: Variant = _scope_arrivals(root, scope["brush_ids"])
	if moved == null:
		return null
	var arrived: Dictionary = moved["arrived"]
	var departed: Dictionary = moved["departed"]
	var nodes: Dictionary = {}
	for brush_id in scope["brush_ids"]:
		# Taken in or let go below, or gone and never tracked since.
		if arrived.has(brush_id) or departed.has(brush_id) or not _instances_by_id.has(brush_id):
			continue
		var brush := _tracked_brush(root, str(brush_id))
		if brush == null or not _entity_name_is_known(root, brush):
			return null
		nodes[brush_id] = brush
	for entity in scope["entities"]:
		if not _entity_name_is_known(root, entity):
			return null

	var placed := _placed_by_commands.duplicate()
	var current_bake_configuration := _bake_configuration_signature(root)
	if current_bake_configuration != _bake_configuration:
		root.call("tag_full_reconcile")
	var changed := PackedStringArray()
	for brush_id in nodes:
		var brush: DraftBrush = nodes[brush_id]
		if brush.global_transform.basis.determinant() < 0.0:
			root.get("transform_system").normalize_handedness(brush)
		var role := _container_role(brush)
		# Apply, Commit and Restore move a brush between folders and own its bake
		# boundary, so a managed move only re-seeds, as in `reconcile()`.
		var managed_move := role != str(_containers_by_id.get(brush_id, ""))
		if not managed_move:
			_follow_native_turn(root, brush, brush_id, placed)
		var signature := _signature(brush)
		if not managed_move and _signature_changed(_signatures[brush_id], signature):
			var previous_signature: Dictionary = _signatures[brush_id]
			if previous_signature.get("faces") != signature.get("faces"):
				_refresh_face_preview(brush)
				signature = _signature(brush)
			root.call("tag_brush_dirty", brush_id)
			changed.append(brush_id)
		_signatures[brush_id] = signature
		_containers_by_id[brush_id] = role
		_parents_by_id[brush_id] = weakref(brush.get_parent())
		if _entity_names_by_instance.has(brush.get_instance_id()):
			_entity_prefab_links_by_instance[brush.get_instance_id()] = _prefab_link(brush)
	for entity in scope["entities"]:
		_follow_native_entity_turn(root, entity)
		var instance_id: int = entity.get_instance_id()
		_entity_prefab_links_by_instance[instance_id] = _prefab_link(entity)
		var turns := _entity_turns([entity])
		if turns.has(instance_id):
			_entity_turns_by_instance[instance_id] = turns[instance_id]
	for brush_id in arrived:
		var brush: DraftBrush = arrived[brush_id]
		_signatures[brush_id] = _signature(brush)
		_instances_by_id[brush_id] = brush.get_instance_id()
		_containers_by_id[brush_id] = _container_role(brush)
		_parents_by_id[brush_id] = weakref(brush.get_parent())
	for brush_id in departed:
		_signatures.erase(brush_id)
		_instances_by_id.erase(brush_id)
		_containers_by_id.erase(brush_id)
		_parents_by_id.erase(brush_id)
	if not arrived.is_empty() or not departed.is_empty():
		# What the full walk does on a brush that came or went, so the level's
		# records agree.
		_tag_structural_change(root)
		_folder_counts = _folder_counts_of(root)
	_bake_configuration = current_bake_configuration
	_placed_by_commands.clear()
	_full_walk_owed = true
	_finish_check(changed, false)
	root.call("drop_faces_of_departed_brushes")
	return changed


## The brushes made and the brushes gone since the last reconcile, as
## `{arrived, departed}` by id, when every one of them is a plain brush in
## `brush_ids`, made by a command that tagged it or taken away by a step whose
## record names it, and nothing else changed how many brushes or entities each
## folder holds. Null when the level's brushes changed any other way, such as a
## copy Godot made, which carries its original's id and no tag. An id in
## `brush_ids` that no brush has and was not tracked is passed over.
func _scope_arrivals(root: Node, brush_ids: Dictionary) -> Variant:
	var departed: Variant = _departed_brushes(root, brush_ids)
	if departed == null:
		return null
	var grown := _brushes(root).size() - (_instances_by_id.size() - (departed as Dictionary).size())
	if grown < 0:
		return null
	var arrived: Dictionary = {}
	var expected: Array = _folder_counts.duplicate()
	for brush_id in departed:
		var gone_from := ["draft", "pending", "committed"].find(
			str(_containers_by_id.get(brush_id, ""))
		)
		if gone_from < 0 or expected.size() <= gone_from:
			return null
		expected[gone_from] = int(expected[gone_from]) - 1
	if grown > 0:
		for brush_id in brush_ids:
			if _instances_by_id.has(brush_id):
				continue
			var brush := root.call("find_brush_by_id", str(brush_id)) as DraftBrush
			# Gone: a record of an undone step names a brush its undo took away.
			if brush == null:
				continue
			if (
				not root.is_ancestor_of(brush)
				or _brush_id(brush) != str(brush_id)
				or not str(brush.get_meta("brush_entity_class", "")).is_empty()
			):
				return null
			var folder := ["draft", "pending", "committed"].find(_container_role(brush))
			if folder < 0 or expected.size() <= folder:
				return null
			expected[folder] = int(expected[folder]) + 1
			arrived[brush_id] = brush
	if arrived.size() != grown or _folder_counts_of(root) != expected:
		return null
	return {"arrived": arrived, "departed": departed}


## The tracked brushes among `brush_ids` that have gone from the level: their
## node freed or out of it, and no brush answering to the id. Null when one of
## them carried an entity name, whose going the full walk reconciles.
func _departed_brushes(root: Node, brush_ids: Dictionary) -> Variant:
	var departed: Dictionary = {}
	for brush_id in brush_ids:
		if not _instances_by_id.has(brush_id):
			continue
		var instance_id := int(_instances_by_id[brush_id])
		var found := instance_from_id(instance_id)
		if (
			found is Node
			and is_instance_valid(found)
			and not (found as Node).is_queued_for_deletion()
			and root.is_ancestor_of(found)
		):
			continue
		if root.call("find_brush_by_id", str(brush_id)) != null:
			continue
		if _entity_names_by_instance.has(instance_id):
			return null
		departed[brush_id] = true
	return departed


## The brush tracked as `brush_id`, when it is still that brush where it was last
## seen or in the folder a managed move put it in. Null otherwise.
func _tracked_brush(root: Node, brush_id: String) -> DraftBrush:
	if not _instances_by_id.has(brush_id):
		return null
	var found := instance_from_id(int(_instances_by_id[brush_id]))
	if not (found is DraftBrush) or not is_instance_valid(found):
		return null
	var brush := found as DraftBrush
	if brush.is_queued_for_deletion() or not root.is_ancestor_of(brush):
		return null
	if _brush_id(brush) != brush_id:
		return null
	var previous_ref := _parents_by_id.get(brush_id, null) as WeakRef
	var previous_parent: Node = previous_ref.get_ref() if previous_ref != null else null
	if brush.get_parent() != previous_parent:
		var role := _managed_container_role(root, brush.get_parent())
		if role.is_empty() or str(brush.get_meta("hf_container_role", "")) != role:
			return null
	return brush


## Whether `node` is an entity exactly when it was one at the last reconcile, and
## under the name it had. A rename or a new entity class is the full walk's.
func _entity_name_is_known(root: Node, node: Node) -> bool:
	var is_entity := (
		bool(root.call("is_entity_node", node))
		or (
			bool(root.call("is_brush_node", node))
			and not str(node.get_meta("brush_entity_class", "")).is_empty()
		)
	)
	var instance_id := node.get_instance_id()
	if is_entity != _entity_names_by_instance.has(instance_id):
		return false
	return not is_entity or str(_entity_names_by_instance[instance_id]) == str(node.name)


## How many nodes the brush folders and the Entities folder hold. A brush Godot
## moved from one folder to another, or an entity made or deleted, changes these
## when the number of brushes stays the same.
static func _folder_counts_of(root: Node) -> Array:
	var counts: Array = []
	for folder_name in ["draft_brushes_node", "pending_node", "committed_node", "entities_node"]:
		var folder: Variant = root.get(folder_name)
		counts.append((folder as Node).get_child_count() if folder is Node else 0)
	return counts


## Write what this reconcile found as the record of each step noted since the
## last one, joining what the record already held, or drop those records when
## the level's structure moved. Then owe nothing.
func _finish_check(changed: PackedStringArray, structural: bool) -> void:
	var found := _tagged_ids.duplicate()
	for brush_id in changed:
		found[brush_id] = true
	for version in _unrecorded_versions:
		if structural:
			_step_brushes.erase(version)
			continue
		var record: Dictionary = {}
		for brush_id in _step_brushes.get(version, PackedStringArray()):
			record[brush_id] = true
		record.merge(found)
		_step_brushes[version] = PackedStringArray(record.keys())
	while _step_brushes.size() > MAX_STEP_RECORDS:
		_step_brushes.erase(_step_brushes.keys().min())
	while _step_names.size() > MAX_STEP_RECORDS:
		_step_names.erase(_step_names.keys().min())
	_unrecorded_versions.clear()
	_owed_ids.clear()
	_owed_full = false
	_tagged_ids.clear()


func _brushes(root: Node) -> Array:
	return root.call("_iter_managed_brush_nodes")


## Hear each tag HammerForge's own commands put on a brush. A command tags a
## brush when it has finished with it, so that is where its part in the brush's
## change ends and anything Godot does after begins.
func _watch(root: Node) -> void:
	if not root.has_signal("brush_changed"):
		return
	root.connect("brush_changed", _on_brush_changed)
	if root.has_signal("brush_changes_wanted"):
		root.connect("brush_changes_wanted", _on_brush_changes_wanted)
	_watched_root = weakref(root)


func _stop_watching() -> void:
	var watched: Node = _watched_root.get_ref() if _watched_root != null else null
	if watched != null and watched.is_connected("brush_changed", _on_brush_changed):
		watched.disconnect("brush_changed", _on_brush_changed)
	if watched != null and watched.is_connected("brush_changes_wanted", _on_brush_changes_wanted):
		watched.disconnect("brush_changes_wanted", _on_brush_changes_wanted)
	_watched_root = null
	_placed_by_commands.clear()


func _on_brush_changed(brush_id: String) -> void:
	var watched: Node = _watched_root.get_ref() if _watched_root != null else null
	if watched == null:
		return
	_tagged_ids[brush_id] = true
	var brush := watched.call("find_brush_by_id", brush_id) as Node3D
	if brush != null and brush.is_inside_tree():
		_placed_by_commands[brush_id] = brush.global_transform


## A bake is about to read which brushes changed. When a check since the last
## full walk looked at only some brushes, look at every one now, so a change made
## outside them reaches the bake (#1619).
func _on_brush_changes_wanted() -> void:
	var watched: Node = _watched_root.get_ref() if _watched_root != null else null
	if watched != null and _full_walk_owed and is_tracking_root(watched):
		reconcile(watched)


## Turn a brush entity's `angle` with a turn Godot made, so a door turned with
## the gizmo or the Inspector still slides along its wall (#1256).
##
## HammerForge's own commands turn the angle themselves, and an undo of one puts
## back the angle it recorded, so the turn counted is the one since a command
## last left the brush, or since the last reconcile when none has. Counting from
## the last reconcile alone turned a door Rotate had already turned a second time.
## A node that is not the one seen last time was rebuilt by a restore, which
## brought its angle with it. Godot's undo of a gizmo turn is a turn back, and
## turns the angle back.
func _follow_native_turn(root: Node, brush: Node, brush_id: String, placed: Dictionary) -> void:
	if not (brush is DraftBrush) or str(brush.get_meta("brush_entity_class", "")).is_empty():
		return
	var before: Transform3D
	if placed.has(brush_id):
		before = placed[brush_id]
	elif (
		_signatures.has(brush_id)
		and int(_instances_by_id.get(brush_id, 0)) == brush.get_instance_id()
	):
		var previous_signature: Dictionary = _signatures[brush_id]
		before = previous_signature.get("transform", Transform3D.IDENTITY)
	else:
		return
	var after := (brush as DraftBrush).global_transform
	var transform_system = root.get("transform_system")
	if transform_system == null or after.basis.is_equal_approx(before.basis):
		return
	var turn := after.basis.orthonormalized() * before.basis.orthonormalized().inverse()
	transform_system.turn_brush_entity_angle(brush, turn)


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
	if parent == null or parent.get_parent() != root:
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
	for candidate in root.call("_iter_pick_nodes"):
		var is_entity := bool(root.call("is_entity_node", candidate))
		var is_brush_entity := (
			bool(root.call("is_brush_node", candidate))
			and not str(candidate.get_meta("brush_entity_class", "")).is_empty()
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
			HFPrefabSystem.untag(entity)


static func _entity_turns(entities: Array[Node]) -> Dictionary:
	var turns: Dictionary = {}
	for entity in entities:
		if entity is DraftEntity and entity.is_inside_tree():
			turns[entity.get_instance_id()] = {
				"transform": (entity as DraftEntity).global_transform,
				"angle": (entity as DraftEntity).entity_data.get("angle", null),
			}
	return turns


## Turn a point entity's yaw with a turn Godot made, so a spawn turned with the
## gizmo or the Inspector faces the player the way it was turned.
##
## No signal says a command of HammerForge's has placed an entity, as one does
## for a brush. Each sets the angle along with the turn, though: Rotate turns it,
## Flip mirrors it and an undo puts back the one it recorded. So the turn counted
## is one that left the angle where it was at the last reconcile, and Godot's
## undo of it is a turn back that turns the angle back.
func _follow_native_entity_turn(root: Node, entity: Node) -> void:
	var before: Dictionary = _entity_turns_by_instance.get(entity.get_instance_id(), {})
	if before.is_empty() or not (entity is DraftEntity):
		return
	var draft := entity as DraftEntity
	var angle: Variant = draft.entity_data.get("angle", null)
	var held: Variant = before.get("angle", null)
	if typeof(angle) != typeof(held) or angle != held:
		return
	var was: Transform3D = before["transform"]
	var now := draft.global_transform
	var transform_system = root.get("transform_system")
	if transform_system == null or now.basis.is_equal_approx(was.basis):
		return
	var turn := now.basis.orthonormalized() * was.basis.orthonormalized().inverse()
	transform_system.turn_entity_angle(draft, turn)


static func _prefab_link(node: Node) -> Dictionary:
	var link: Dictionary = {}
	for meta_name in HFPrefabSystem.LINK_META:
		link[meta_name] = str(node.get_meta(meta_name, ""))
	return link


static func _prefab_link_fingerprint(link: Dictionary) -> String:
	var values: Array[String] = []
	var has_value := false
	for meta_name in HFPrefabSystem.LINK_META:
		var value := str(link.get(meta_name, ""))
		values.append(value)
		has_value = has_value or not value.is_empty()
	return JSON.stringify(values) if has_value else ""


static func _bake_configuration_signature(root: Node) -> Dictionary:
	var signature: Dictionary = {}
	for property in root.get_property_list():
		var property_name := str(property.get("name", ""))
		if not HFBakeSystemType.is_bake_setting(property_name):
			continue
		# Saved or shown: a bake setting kept out of the Inspector, as the cordon
		# switches are (#972), still changes the bake when a script or undo sets it.
		if (int(property.get("usage", 0)) & (PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_STORAGE)) == 0:
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
		"entity_meta": _entity_meta_signature(brush),
		# Cast Shadows and Lightmap Scale are metadata the Inspector edits (#1661).
		"bake_split": HFBakeSplit.fields(brush),
	}


## The metadata that decides what a brush becomes in the bake.
##
## `brush_entity_class` chooses whether the brush is world geometry or a
## `func_door`, `entity_name` is the address every connection aims at, and
## `entity_io_outputs` is the wiring itself. This tracker exists for edits
## HammerForge's own commands did not make, and Godot 4's Inspector has a
## Metadata section that edits exactly these keys - so all three could be
## changed with Bake Changed reporting nothing to do, and the baked output kept
## the brush as plain geometry or wired to a target that no longer exists.
##
## The outputs are an Array of Dictionaries, deep copied the way
## `_configuration_value()` already copies an array, or the snapshot changes
## underneath the comparison.
##
## `brush_entity_data` is a door's speed and lock, which the bake copies onto the
## mover, and `brush_entity_group` is the tie that makes several brushes one
## door. Both are bake inputs the Inspector edits as well (#1198).
static func _entity_meta_signature(brush: Node) -> Dictionary:
	return {
		"class": str(brush.get_meta("brush_entity_class", "")),
		"name": str(brush.get_meta("entity_name", "")),
		"io": _configuration_value(brush.get_meta("entity_io_outputs", [])),
		"data": _configuration_value(brush.get_meta("brush_entity_data", {})),
		"tie": str(brush.get_meta("brush_entity_group", "")),
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
					"legacy_wall_axes": face.get("legacy_wall_axes"),
					"smoothing_group": face.get("smoothing_group"),
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
		"flip_diagonals": displacement.get("flip_diagonals"),
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


## Take the mirror off any brush a native edit left with a negative determinant.
##
## Godot's own scale gizmo will drag a handle past zero, and the Inspector will
## take a typed negative, and neither goes anywhere near HammerForge's own Flip -
## which folds its reflection away precisely so this cannot happen. The brush then
## bakes inside out, or, as a cutter, adds its volume instead of removing it
## (#749). The viewport draws it the right shape either way, so the bake is the
## first place it shows, and it shows as a window that did not open.
##
## Repaired here for the same reason `_recover_illegal_reparents()` is: this is
## where an edit Godot owns is reconciled against what HammerForge needs to be
## true. The fold leaves every world vertex and every face's appearance exactly
## where it was, so there is nothing for the user to undo.
func _normalize_handedness(root: Node, brushes: Array) -> void:
	for brush in brushes:
		if not is_instance_valid(brush) or not (brush is DraftBrush):
			continue
		if (brush as DraftBrush).global_transform.basis.determinant() >= 0.0:
			continue
		root.get("transform_system").normalize_handedness(brush)


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
			HFPrefabSystem.untag(duplicate)
			_write_brush_id(duplicate, _next_unique_brush_id(root, reserved, duplicate))
			repaired = true
	for brush in empty_id_brushes:
		_write_brush_id(brush, _next_unique_brush_id(root, reserved, brush))
		repaired = true
	return repaired


static func _next_unique_brush_id(root: Node, reserved: Dictionary, brush: Node) -> String:
	var candidate := ""
	for _attempt in range(64):
		candidate = str(root.call("_next_brush_id"))
		if not reserved.has(candidate):
			reserved[candidate] = true
			return candidate
	# The instance suffix makes this deterministic and collision-safe even if a
	# malformed root keeps returning the same custom ID.
	candidate = "%s_%d" % [candidate, brush.get_instance_id()]
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
	root.call("tag_full_reconcile")
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
	for field in [
		"visible", "shape", "operation", "sides", "material", "faces", "entity_meta", "bake_split"
	]:
		if before.get(field) != after.get(field):
			return true
	return false
