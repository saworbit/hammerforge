## Runtime I/O dispatcher — translates HammerForge entity I/O metadata into
## live Godot signals.  Attach this node to a baked/exported scene and it will
## auto-wire every connection stored in `entity_io_outputs` metadata on child
## entities so that firing an output on one entity calls the corresponding
## input method (or signal) on the target entity, with delay and fire-once
## semantics handled automatically.
##
## Usage from game code:
##   var dispatcher = $HFIODispatcher  # or get the singleton
##   dispatcher.fire("my_button", "OnPressed", "")
##
## Or from an entity script:
##   HFIORuntime.fire_on(self, "OnTrigger")
extends Node
class_name HFIORuntime

## Emitted whenever an I/O output fires (useful for debugging / logging).
signal io_fired(
	source_name: String,
	output_name: String,
	target_name: String,
	input_name: String,
	parameter: String
)

## Emitted when an input is delivered to a target entity.
signal io_received(target_name: String, input_name: String, parameter: String)

# ---------------------------------------------------------------------------
# Internal bookkeeping
# ---------------------------------------------------------------------------

## instance_id (int) -> [{output_name, target_name, input_name, parameter, delay, fire_once, _fired}]
## Keyed by object instance ID so two sources sharing a name keep separate connection sets.
var _connections: Dictionary = {}

## source_name (String) -> [instance_id, ...] reverse lookup for the string-based fire() API.
var _source_name_to_ids: Dictionary = {}

## name -> [Node, ...] cache (rebuilt on wire).  Multiple nodes may share a name.
var _entity_cache: Dictionary = {}

## Persistent node paths for additional scan roots.  Survives scene save/reload
## because @export NodePath values are serialized by Godot.  Resolved to live
## Node references at wire() time.
@export var extra_scan_root_paths: Array[NodePath] = []

## Transient extra scan roots set via script (not serialized).  Use this from
## code paths like _attach_io_dispatcher that run in the same session.
var extra_scan_roots: Array[Node] = []

## Tracks connected (entity, signal_name) pairs so wire() can disconnect
## stale lambdas before reconnecting.
var _signal_connections: Array = []  # [{entity: Node, sig_name: String, callable: Callable}]

## If true, prints every I/O fire to the console.
@export var debug_logging: bool = false

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------


func _ready() -> void:
	wire()


## Scan the scene tree for entities carrying `entity_io_outputs` metadata and
## build the runtime connection table.  Safe to call multiple times (clears
## previous state).
func wire() -> void:
	_disconnect_all_signals()
	_connections.clear()
	_source_name_to_ids.clear()
	_entity_cache.clear()
	# Collect all candidate scan roots, then prune overlapping subtrees so no
	# node is visited twice.
	var roots: Array[Node] = []
	var primary: Node = get_parent() if get_parent() else self
	roots.append(primary)
	for np in extra_scan_root_paths:
		if np != NodePath(""):
			var resolved: Node = get_node_or_null(np)
			if is_instance_valid(resolved):
				roots.append(resolved)
	for extra_root in extra_scan_roots:
		if is_instance_valid(extra_root):
			roots.append(extra_root)
	var pruned: Array[Node] = _prune_overlapping_roots(roots)
	for r in pruned:
		_cache_entities(r)
		_collect_connections(r)
	_create_user_signals()
	_connect_signals()
	if debug_logging:
		print(
			(
				"HFIORuntime: wired %d source(s), %d entity(ies) cached"
				% [_connections.size(), _entity_cache.size()]
			)
		)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


## Fire an output by source entity name.  When multiple sources share the same
## name, fires from ALL of them (use fire_from() or fire_on() for per-instance
## dispatch).
func fire(source_name: String, output_name: String, parameter: String = "") -> void:
	var ids: Array = _source_name_to_ids.get(source_name, [])
	for id in ids:
		_fire_instance(id, source_name, output_name, parameter)


## Fire an output from a specific source node instance.  Only runs connections
## that belong to this exact node, even if other nodes share the same name.
func fire_from(entity: Node, output_name: String, parameter: String = "") -> void:
	if not is_instance_valid(entity):
		return
	var id: int = entity.get_instance_id()
	_fire_instance(id, entity.name, output_name, parameter)


## Static convenience — fire an output from a specific node reference.
static func fire_on(entity: Node, output_name: String, parameter: String = "") -> void:
	if not is_instance_valid(entity) or not entity.is_inside_tree():
		return
	var dispatcher := _find_dispatcher(entity)
	if dispatcher:
		dispatcher.fire_from(entity, output_name, parameter)


## Internal: fire connections belonging to a single source instance ID.
func _fire_instance(id: int, source_name: String, output_name: String, parameter: String) -> void:
	var conns: Array = _connections.get(id, [])
	for conn in conns:
		if str(conn.get("output_name", "")) != output_name:
			continue
		if conn.get("_fired", false) and conn.get("fire_once", false):
			continue
		var target_name: String = str(conn.get("target_name", ""))
		var input_name: String = str(conn.get("input_name", ""))
		var param: String = parameter if parameter != "" else str(conn.get("parameter", ""))
		var delay: float = float(conn.get("delay", 0.0))
		if delay > 0.0:
			_fire_delayed(source_name, output_name, target_name, input_name, param, delay, conn)
		else:
			_deliver(source_name, output_name, target_name, input_name, param)
			if conn.get("fire_once", false):
				conn["_fired"] = true


# ---------------------------------------------------------------------------
# Signal creation & connection
# ---------------------------------------------------------------------------


## For every source entity, add user signals for each unique output_name so
## that standard Godot emit_signal / connect also works.
func _create_user_signals() -> void:
	for id in _connections:
		var entity: Node = instance_from_id(id)
		if not is_instance_valid(entity):
			continue
		var seen: Dictionary = {}
		for conn in _connections[id]:
			var sig_name: String = _signal_name(str(conn.get("output_name", "")))
			if seen.has(sig_name):
				continue
			seen[sig_name] = true
			if not entity.has_signal(sig_name):
				entity.add_user_signal(sig_name, [{"name": "parameter", "type": TYPE_STRING}])


## Disconnect all signal connections made by previous wire() calls.
func _disconnect_all_signals() -> void:
	for entry in _signal_connections:
		var entity: Node = entry["entity"]
		if is_instance_valid(entity) and entity.is_connected(entry["sig_name"], entry["callable"]):
			entity.disconnect(entry["sig_name"], entry["callable"])
	_signal_connections.clear()


## Connect user signals on source entities to a lambda that calls fire_from(),
## so game scripts can simply `entity.emit_signal("io_OnTrigger", "")`.
## Uses fire_from (instance-aware) to avoid cross-firing when names collide.
func _connect_signals() -> void:
	for id in _connections:
		var entity: Node = instance_from_id(id)
		if not is_instance_valid(entity):
			continue
		var seen: Dictionary = {}
		for conn in _connections[id]:
			var sig_name: String = _signal_name(str(conn.get("output_name", "")))
			if seen.has(sig_name):
				continue
			seen[sig_name] = true
			var ent: Node = entity  # capture for lambda
			var on: String = str(conn.get("output_name", ""))
			var cb := func(param: String = "") -> void: fire_from(ent, on, param)
			entity.connect(sig_name, cb)
			_signal_connections.append({"entity": entity, "sig_name": sig_name, "callable": cb})


# ---------------------------------------------------------------------------
# Delivery
# ---------------------------------------------------------------------------


func _deliver(
	source_name: String,
	output_name: String,
	target_name: String,
	input_name: String,
	parameter: String
) -> void:
	var targets: Array = _entity_cache.get(target_name, [])
	# Filter out stale refs
	var valid_targets: Array = []
	for t in targets:
		if is_instance_valid(t):
			valid_targets.append(t)
	if valid_targets.is_empty():
		if debug_logging:
			push_warning(
				(
					"HFIORuntime: target '%s' not found for %s.%s"
					% [target_name, source_name, output_name]
				)
			)
		return

	for target in valid_targets:
		io_fired.emit(source_name, output_name, target_name, input_name, parameter)
		io_received.emit(target_name, input_name, parameter)
		if debug_logging:
			print(
				(
					"HFIORuntime: %s.%s -> %s.%s(%s)"
					% [source_name, output_name, target_name, input_name, parameter]
				)
			)
		_deliver_to_target(target, input_name, parameter)


## Deliver an input to a single target node.
func _deliver_to_target(target: Node, input_name: String, parameter: String) -> void:
	# 1) Try calling the input method directly on the target (e.g. "Open", "TurnOn").
	var method_name: String = input_name
	if target.has_method(method_name):
		if parameter != "":
			target.call(method_name, parameter)
		else:
			target.call(method_name)
		return

	# 2) Try snake_case variant (e.g. "TurnOn" -> "turn_on").
	var snake_name: String = _to_snake_case(method_name)
	if snake_name != method_name and target.has_method(snake_name):
		if parameter != "":
			target.call(snake_name, parameter)
		else:
			target.call(snake_name)
		return

	# 3) Try a generic handler: _on_io_input(input_name, parameter).
	if target.has_method("_on_io_input"):
		target.call("_on_io_input", input_name, parameter)
		return

	# 4) Emit a user signal on the target so scripts can connect to it.
	var target_sig: String = _signal_name(input_name)
	if not target.has_signal(target_sig):
		target.add_user_signal(target_sig, [{"name": "parameter", "type": TYPE_STRING}])
	target.emit_signal(target_sig, parameter)


func _fire_delayed(
	source_name: String,
	output_name: String,
	target_name: String,
	input_name: String,
	parameter: String,
	delay: float,
	conn: Dictionary
) -> void:
	if not is_inside_tree():
		return
	var timer := get_tree().create_timer(delay)
	timer.timeout.connect(
		func() -> void:
			if not is_instance_valid(self):
				return
			if conn.get("_fired", false) and conn.get("fire_once", false):
				return
			_deliver(source_name, output_name, target_name, input_name, parameter)
			if conn.get("fire_once", false):
				conn["_fired"] = true
	)


# ---------------------------------------------------------------------------
# Tree scanning
# ---------------------------------------------------------------------------


func _cache_entities(node: Node) -> void:
	if node == self:
		for child in node.get_children():
			_cache_entities(child)
		return
	# Cache by node name — multiple nodes may share a name
	_cache_entity_under_key(node.name, node)
	# Also cache by entity_name meta if present
	var meta_name = node.get_meta("entity_name", "")
	if meta_name != "" and str(meta_name) != node.name:
		_cache_entity_under_key(str(meta_name), node)
	for child in node.get_children():
		_cache_entities(child)


func _cache_entity_under_key(key: String, node: Node) -> void:
	if not _entity_cache.has(key):
		_entity_cache[key] = []
	var arr: Array = _entity_cache[key]
	if node not in arr:
		arr.append(node)


func _collect_connections(node: Node) -> void:
	if node == self:
		for child in node.get_children():
			_collect_connections(child)
		return
	var outputs: Array = node.get_meta("entity_io_outputs", [])
	if not outputs.is_empty():
		var id: int = node.get_instance_id()
		var source_name: String = node.name
		if not _connections.has(id):
			_connections[id] = []
		for conn in outputs:
			if conn is Dictionary:
				var entry: Dictionary = conn.duplicate()
				entry["_fired"] = false
				_connections[id].append(entry)
		# Reverse lookup: name -> [instance_id, ...]
		if not _source_name_to_ids.has(source_name):
			_source_name_to_ids[source_name] = []
		var id_list: Array = _source_name_to_ids[source_name]
		if id not in id_list:
			id_list.append(id)
	for child in node.get_children():
		_collect_connections(child)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


## Remove roots that are descendants of (or identical to) another root in the
## list, so no subtree is scanned more than once.  O(n²) on the root count
## which is typically 1–3.
static func _prune_overlapping_roots(roots: Array[Node]) -> Array[Node]:
	# Deduplicate by instance ID first
	var seen_ids: Dictionary = {}
	var unique: Array[Node] = []
	for r in roots:
		var id: int = r.get_instance_id()
		if not seen_ids.has(id):
			seen_ids[id] = true
			unique.append(r)
	# Remove any root that is a descendant of another root
	var pruned: Array[Node] = []
	for i in range(unique.size()):
		var is_covered := false
		for j in range(unique.size()):
			if i != j and unique[j].is_ancestor_of(unique[i]):
				is_covered = true
				break
		if not is_covered:
			pruned.append(unique[i])
	return pruned


## Find the HFIORuntime dispatcher in the scene tree.  Tries current_scene
## first, then walks up from the node to the tree root as a fallback (covers
## GUT tests and editor context where current_scene is null).
static func _find_dispatcher(node: Node) -> HFIORuntime:
	var tree := node.get_tree() if node else null
	if not tree:
		return null
	# Try current_scene first (runtime game context)
	var scene_root: Node = tree.current_scene
	if scene_root:
		var found := _find_dispatcher_recursive(scene_root)
		if found:
			return found
	# Fallback: walk up to the highest ancestor, then search down
	var top: Node = node
	while top.get_parent():
		top = top.get_parent()
	return _find_dispatcher_recursive(top)


static func _find_dispatcher_recursive(node: Node) -> HFIORuntime:
	for child in node.get_children():
		if child is HFIORuntime:
			return child
		var found := _find_dispatcher_recursive(child)
		if found:
			return found
	return null


## Convert an output/input name to a Godot signal name.
## e.g. "OnTrigger" -> "io_OnTrigger"
static func _signal_name(io_name: String) -> String:
	return "io_" + io_name


## Convert PascalCase / camelCase to snake_case.
static func _to_snake_case(s: String) -> String:
	var result := ""
	for i in range(s.length()):
		var c: String = s[i]
		if c == c.to_upper() and c != c.to_lower() and i > 0:
			result += "_"
		result += c.to_lower()
	return result
