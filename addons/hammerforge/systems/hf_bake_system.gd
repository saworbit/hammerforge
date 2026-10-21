@tool
extends RefCounted
class_name HFBakeSystem

# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const PrefabFactory = preload("../prefab_factory.gd")
const DraftBrush = preload("../brush_instance.gd")
const FaceData = preload("../face_data.gd")
const HFAutoConnector = preload("../paint/hf_auto_connector.gd")
const HFIORuntime = preload("../hf_io_runtime.gd")
const HFDoorRuntime = preload("../hf_door_runtime.gd")
const HFLog = preload("../hf_log.gd")
const HFBrushEntity = preload("../hf_brush_entity.gd")
const DraftEntity = preload("../draft_entity.gd")
@warning_ignore_restore("shadowed_global_identifier")

## What a baked static body detects: nothing.
##
## These never move, so a mask buys them nothing and only widens the broadphase.
## The mask used to be a copy of the layer, which meant changing the Physics
## Layer moved the mask with it - two controls' worth of behaviour from one
## dropdown, and not what either of them is for (#695).
const STATIC_BODY_MASK := 0

## Brush entity classes whose geometry moves, and so needs a node of its own to
## move with its collision.
const MOVER_CLASSES := ["func_door", "door_basic"]

const BAKED_CONTAINER_NAME := &"BakedGeometry"
const BAKED_CONTAINER_META := &"_hammerforge_baked_container"
const BAKED_CONTAINER_SCHEMA := 1
const BAKED_PREVIEW_MODE_META := &"_hammerforge_bake_preview_mode"
## The ids of the brushes a piece of the bake holds: on the container for a full
## bake, on each `BakedSelection_` node for a selection. Bake Selected reads them
## to take out what an earlier bake made of the brushes it bakes again (#1208).
const BAKED_BRUSH_IDS_META := &"_hammerforge_baked_brush_ids"
## The brush a CSG operand was built from, so the convex collision modes can hull
## the brushes the boolean took, in the order it took them (#1513).
const CSG_SOURCE_META := &"_hammerforge_csg_source"

## Bake preview mode: FULL produces final geometry, WIREFRAME skips materials
## and generates unshaded wireframe, PROXY uses simplified box meshes.
enum PreviewMode { FULL, WIREFRAME, PROXY }

## Why the last bake call returned what it did.
##
## Every bake entry point returns a plain bool, and false alone is ambiguous:
## a refused bake, a bake with nothing to do, and a bake that genuinely failed
## all look identical. Callers that need the difference read
## get_last_bake_status() immediately after the call.
enum BakeStatus { NOT_RUN, SUCCESS, FAILED, BUSY, NOTHING_TO_DO }

var root: Node3D

## The bake settings the last successful bake ran with, and whether there has
## been one. Any other signature means the baked result no longer answers the
## settings that are set — but only once there is a result for them to go stale.
var _last_bake_settings_signature: int = 0
## The same for the props the navmesh is cut around (`navmesh_props_signature()`).
var _last_navmesh_props_signature: int = 0
## And for the paint connectors the mapper kept (`connector_defs_signature()`).
var _last_connector_defs_signature: int = 0
var _has_baked_once: bool = false
var _last_bake_success: bool = false
var _last_bake_status: int = BakeStatus.NOT_RUN
var _bake_in_flight := false
## Set when the bake in flight found its level out of the tree after a wait, and
## stopped (`_wait_frames()`).
var _left_tree := false
## The answers to bake calls still waiting on a frame (`answer_to()`).
var _open_answers: Array[BakeAnswer] = []
## The painted chunks the bake in flight claimed, given back if it fails.
var _claimed_paint_chunks: Array[Vector2i] = []
static var _wireframe_shader: Shader = null
static var _wireframe_material: ShaderMaterial = null

## Number of brushes to process per frame during face-based bake collection.
## Lower values yield more often (smoother editor), higher values bake faster.
const _FACE_BAKE_BATCH := 8


func _init(level_root: Node3D) -> void:
	root = level_root


# ---------------------------------------------------------------------------
# Baked container lifecycle
# ---------------------------------------------------------------------------


## Re-adopt baked geometry persisted in the scene and collapse legacy duplicate
## roots created by the old queue_free-then-replace flow. Legacy anonymous
## nodes are only considered when every direct child is a known bake artifact
## and at least one child has an unmistakable baked-mesh signature.
func reconcile_baked_containers() -> Node3D:
	var candidates := _managed_baked_containers()
	if candidates.is_empty():
		root.baked_container = null
		return null

	# Child order is persistence order. The last populated candidate is the
	# newest legacy bake, which matters when the canonical node is an older or
	# empty container left behind by the duplication bug.
	var survivor: Node3D = null
	for candidate: Node3D in candidates:
		if _has_baked_payload(candidate):
			survivor = candidate
	if not survivor:
		for candidate: Node3D in candidates:
			if candidate.has_meta(BAKED_CONTAINER_META):
				survivor = candidate
	if not survivor:
		survivor = candidates[0]

	var removed := 0
	for candidate: Node3D in candidates:
		if candidate == survivor:
			continue
		_destroy_baked_container(candidate)
		removed += 1

	if survivor.get_parent() and survivor.get_parent() != root:
		survivor.get_parent().remove_child(survivor)
	survivor.name = BAKED_CONTAINER_NAME
	survivor.set_meta(BAKED_CONTAINER_META, BAKED_CONTAINER_SCHEMA)
	if survivor.get_parent() != root:
		root.add_child(survivor)
	root.baked_container = survivor
	if removed > 0 and root.has_method("_log"):
		root.call("_log", "Removed %d duplicate baked container(s)" % removed)
	return survivor


## Install a complete bake as the only managed container. Existing containers
## are detached synchronously so the canonical name is available before the
## replacement enters the tree, then queued for safe editor-aware deletion.
func replace_baked_container(container: Node3D) -> Node3D:
	if not container or not is_instance_valid(container):
		return null
	for candidate: Node3D in _managed_baked_containers():
		if candidate != container:
			_destroy_baked_container(candidate)
	if container.get_parent() and container.get_parent() != root:
		container.get_parent().remove_child(container)
	container.name = BAKED_CONTAINER_NAME
	container.set_meta(BAKED_CONTAINER_META, BAKED_CONTAINER_SCHEMA)
	if container.get_parent() != root:
		root.add_child(container)
	root.baked_container = container
	return container


## Remove all HammerForge-owned baked roots immediately. This is also used by
## clear/restore flows so a scene saved in the same frame cannot retain ghosts.
func clear_baked_containers() -> void:
	for candidate: Node3D in _managed_baked_containers():
		_destroy_baked_container(candidate)
	root.baked_container = null
	root._last_bake_preview_mode = PreviewMode.FULL


## Capture derived bake output for the small number of actions (notably Commit
## Cuts) whose Undo/Redo must restore the exact prior visual/collision result.
## Ordinary edit snapshots intentionally remain source-only to avoid bloating
## every undo entry with baked meshes.
func capture_baked_geometry_snapshot() -> PackedScene:
	var container := reconcile_baked_containers()
	if not container:
		return null
	var copy := container.duplicate() as Node3D
	if not copy:
		return null
	_assign_packed_snapshot_owners(copy, copy)
	var snapshot := PackedScene.new()
	var result := snapshot.pack(copy)
	copy.free()
	if result != OK:
		push_warning("Could not capture baked geometry for Undo/Redo (error %d)" % result)
		return null
	var preview_mode := clampi(root._last_bake_preview_mode, PreviewMode.FULL, PreviewMode.PROXY)
	snapshot.set_meta(BAKED_PREVIEW_MODE_META, preview_mode)
	return snapshot


func restore_baked_geometry_snapshot(
	snapshot: PackedScene, fallback_preview_mode: int = PreviewMode.FULL
) -> void:
	var preview_mode := clampi(fallback_preview_mode, PreviewMode.FULL, PreviewMode.PROXY)
	if snapshot != null:
		preview_mode = clampi(
			int(snapshot.get_meta(BAKED_PREVIEW_MODE_META, preview_mode)),
			PreviewMode.FULL,
			PreviewMode.PROXY,
		)
	clear_baked_containers()
	# Even an intentionally empty snapshot represents exact derived state. Keep
	# its state-level preview choice instead of inheriting clear()'s FULL reset.
	root._last_bake_preview_mode = preview_mode
	if snapshot == null or not snapshot.can_instantiate():
		return
	var restored := snapshot.instantiate() as Node3D
	if not restored:
		push_warning("Could not restore baked geometry snapshot")
		return
	replace_baked_container(restored)
	root._assign_owner_recursive(restored)


static func _assign_packed_snapshot_owners(node: Node, snapshot_root: Node) -> void:
	for child in node.get_children():
		child.owner = snapshot_root
		_assign_packed_snapshot_owners(child, snapshot_root)


func _managed_baked_containers() -> Array[Node3D]:
	var candidates: Array[Node3D] = []
	for child in root.get_children():
		if not (child is Node3D):
			continue
		var node := child as Node3D
		if (
			node == root.baked_container
			or node.name == BAKED_CONTAINER_NAME
			or node.has_meta(BAKED_CONTAINER_META)
			or _is_legacy_anonymous_bake(node)
		):
			candidates.append(node)
	if (
		root.baked_container
		and is_instance_valid(root.baked_container)
		and not candidates.has(root.baked_container)
	):
		candidates.append(root.baked_container)
	return candidates


static func _is_legacy_anonymous_bake(node: Node3D) -> bool:
	if not str(node.name).begins_with("@Node3D@") or node.get_child_count() == 0:
		return false
	var has_payload_signature := false
	for child in node.get_children():
		var child_name := str(child.name)
		if not _is_known_bake_artifact_name(child_name):
			return false
		if (
			child_name.begins_with("BakedChunk_")
			or child_name.begins_with("BakedMesh_")
			or child_name.begins_with("BakedSelection_")
			or child_name.begins_with("HMFloor__")
		):
			has_payload_signature = true
	return has_payload_signature


static func _is_known_bake_artifact_name(node_name: String) -> bool:
	return (
		node_name == "FloorCollision"
		or node_name == "FaceCollision"
		or node_name == "BakedNavmesh"
		or node_name == "HFIODispatcher"
		or node_name == "Occluders"
		or node_name == "Nonstructural"
		or node_name.begins_with("BakedChunk_")
		or node_name.begins_with("BakedMesh_")
		or node_name.begins_with("BakedSelection_")
		or node_name.begins_with("AutoConnector_")
		or node_name.begins_with("Collision_")
		or node_name.begins_with("HeightmapFloor_")
		or node_name.begins_with("HMFloor__")
		or node_name.begins_with("MMI_")
	)


static func _has_baked_payload(container: Node3D) -> bool:
	for child in container.get_children():
		var child_name := str(child.name)
		if (
			child is MeshInstance3D
			or child is MultiMeshInstance3D
			or child_name.begins_with("BakedChunk_")
			or child_name.begins_with("BakedSelection_")
			or child_name.begins_with("HMFloor__")
			or child_name == "Nonstructural"
		):
			return true
	return false


static func _destroy_baked_container(container: Node3D) -> void:
	if not container or not is_instance_valid(container):
		return
	if container.get_parent():
		container.get_parent().remove_child(container)
	if not container.is_queued_for_deletion():
		container.queue_free()


# ---------------------------------------------------------------------------
# Bake time estimation
# ---------------------------------------------------------------------------


## Returns an estimate dict: {estimated_ms, brush_count, tip}.
## Uses the ratio from the last real bake if available.
func estimate_bake_time(brush_ids: Array = []) -> Dictionary:
	var count := 0
	if brush_ids.is_empty():
		count = _total_bakeable_brush_count()
	else:
		count = brush_ids.size()
	var ms_per_brush := 2.0  # default fallback
	var last_count := _total_bakeable_brush_count()
	if root._last_bake_duration_ms > 0 and last_count > 0:
		ms_per_brush = float(root._last_bake_duration_ms) / float(last_count)
	var estimated_ms: int = int(ceil(ms_per_brush * count))
	var tip := ""
	if count > 500:
		tip = "Chunking recommended for >500 brushes"
	elif count > 200 and not bool(root.get("bake_use_thread_pool")):
		tip = "Consider enabling thread pool for faster bakes"
	elif count == 0:
		tip = "No brushes to bake"
	return {"estimated_ms": estimated_ms, "brush_count": count, "tip": tip}


func _total_bakeable_brush_count() -> int:
	var total := count_brushes_in(root.draft_brushes_node)
	total += count_brushes_in(root.generated_floors)
	total += count_brushes_in(root.generated_walls)
	if root.commit_freeze:
		total += count_brushes_in(root.committed_node)
	return total


# ---------------------------------------------------------------------------
# Selection / incremental bake
# ---------------------------------------------------------------------------


## Why the most recent bake call returned what it did. Read it immediately
## after the call: it is overwritten by the next one.
func get_last_bake_status() -> int:
	return _last_bake_status


func is_bake_in_flight() -> bool:
	return _bake_in_flight


func _try_begin_bake() -> bool:
	if _bake_in_flight:
		_last_bake_status = BakeStatus.BUSY
		root.emit_signal("user_message", "A bake is already running", 1)
		return false
	_bake_in_flight = true
	_last_bake_success = false
	_left_tree = false
	return true


## Wait `count` frames, and say whether the level is still in the tree after
## them. The wait goes through the main loop, which outlives the level's place in
## it: switching scene tabs takes the scene out of the tree (#928), and a wait on
## the level's own tree then found none and stopped on a script error (#1290).
##
## A level out of the tree stops the bake rather than waiting for it to come
## back. The CSG it waits on is only worked out in the tree, finishing places the
## result by global transforms, and the dock is shared between tabs, so a bake
## paused for as long as the mapper looks elsewhere held every tab's bake buttons
## disabled. A closed tab never comes back at all.
func _wait_frames(count: int) -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	for _i in count:
		await tree.process_frame
		if not is_instance_valid(root) or not root.is_inside_tree():
			_left_tree = true
			return false
	return true


## Say that a bake stopped because its level left the tree, and nothing when the
## level is gone, as there is nobody left to tell.
func _report_left_tree() -> void:
	_last_bake_success = false
	if not is_instance_valid(root):
		return
	root._log("Bake stopped: the level left the scene tree")
	root.emit_signal(
		"user_message",
		"Bake stopped: its scene was switched away from before it finished. Bake it again there.",
		1
	)
	root.bake_finished.emit(false)


## The answer to one of the level's bake calls, for a caller outside the level:
## the dock's bake actions, Quick Play, the exports and the bridge. A coroutine
## suspended inside the level is dropped when the level is freed, and this
## system's go with the level too, so the answer is given by the call's return
## or, for a level freed mid-bake, by `on_level_freeing()` (#1294).
class BakeAnswer:
	extends RefCounted

	## Given once: what the bake call returned, or false when its level was freed.
	signal given(baked: bool)

	var done := false
	var baked := false

	func give(result: bool) -> void:
		if done:
			return
		baked = result
		done = true
		given.emit(result)

	## A frame after the level was freed, so whoever awaited a bake finds the
	## level gone rather than going. Static, with the answers bound, so the
	## connection that waits for the frame holds them until then.
	static func give_all_false(answers: Array) -> void:
		for answer in answers:
			answer.give(false)


## Start `bake_call`, one of this system's bake coroutines or the level's own
## `bake()` with its arguments bound, for a caller outside the level to await:
## the answer itself when the call returned before its first wait, otherwise a
## signal given with the answer when it returns. The level's bake wrappers hand
## back what this returns rather than awaiting the call inside the level (#1294).
func answer_to(bake_call: Callable) -> Variant:
	var answer := BakeAnswer.new()
	_give_when_returned(answer, bake_call)
	if answer.done:
		return answer.baked
	_open_answers.append(answer)
	return answer.given


func _give_when_returned(answer: BakeAnswer, bake_call: Callable) -> void:
	var baked: bool = await bake_call.call()
	answer.give(baked)
	_open_answers.erase(answer)


## The level is being freed, a scene tab closed mid-bake, and this system and
## the bake in flight go with it. Every open answer is given false at the next
## frame, once the level is gone, through the main loop, which outlives both.
## One connection for all of them: a whole-level bake has two open, and a second
## bound callable to the same function is refused as already connected.
func on_level_freeing() -> void:
	if _open_answers.is_empty():
		return
	var tree := Engine.get_main_loop() as SceneTree
	var answers: Array = _open_answers.duplicate()
	_open_answers.clear()
	tree.process_frame.connect(BakeAnswer.give_all_false.bind(answers), CONNECT_ONE_SHOT)


## Bake only the given brush nodes (selection bake).
##
## What an earlier bake made of these brushes comes out first. Without that each
## press added another copy, and a moved brush left its old wall and collision
## behind (#1208).
## An earlier selection is baked again whole, with its other brushes, because its
## merged mesh cannot lose one of them. A full bake's merged mesh cannot be rebuilt
## short of a full bake, so a brush the full bake holds makes this one a full bake,
## and the mapper is told why.
func bake_selected(
	brush_nodes: Array, collision_layer_mask: int = 0, preview_mode: int = 0  # PreviewMode.FULL
) -> bool:
	if not _try_begin_bake():
		return false
	var plan := _selection_bake_plan(brush_nodes)
	var held := int(plan["held_by_full_bake"])
	if held > 0:
		root.emit_signal(
			"user_message",
			(
				(
					"Bake Selected baked the whole level: the last full bake holds %d of "
					+ "these brushes merged with others"
				)
				% held
			),
			1
		)
		# Handed to bake(), which takes the flag back before its first await.
		_bake_in_flight = false
		return await bake(false, false, collision_layer_mask, preview_mode)
	await _bake_selected_impl(plan["brushes"], collision_layer_mask, preview_mode, plan["replaces"])
	_bake_in_flight = false
	_last_bake_status = BakeStatus.SUCCESS if _last_bake_success else BakeStatus.FAILED
	return _last_bake_success


## The brushes a selection bake takes, the earlier selection pieces it replaces,
## and how many of its brushes a full bake already holds.
func _selection_bake_plan(brush_nodes: Array) -> Dictionary:
	var brushes: Array = []
	var ids: Dictionary = {}
	for node in brush_nodes:
		_join_selection(node, brushes, ids)
	var replaces: Array = []
	var held := 0
	var container := reconcile_baked_containers()
	if container:
		# A piece joined brings its brushes, and they may be in another piece.
		var joined := true
		while joined:
			joined = false
			for piece in container.get_children():
				if replaces.has(piece) or not _holds_any(piece, ids):
					continue
				replaces.append(piece)
				joined = true
				var held_ids := piece.get_meta(BAKED_BRUSH_IDS_META) as PackedStringArray
				for held_id in held_ids:
					_join_selection(root.find_brush_by_id(held_id), brushes, ids)
		held = _held_by_full_bake(container, brushes)
	return {"brushes": brushes, "replaces": replaces, "held_by_full_bake": held}


func _join_selection(node: Variant, brushes: Array, ids: Dictionary) -> void:
	if not is_instance_valid(node) or not (node is DraftBrush) or brushes.has(node):
		return
	brushes.append(node)
	var brush_id := str((node as DraftBrush).brush_id)
	if brush_id != "":
		ids[brush_id] = true


static func _is_selection_piece(node: Node) -> bool:
	return str(node.name).begins_with("BakedSelection_")


static func _holds_any(piece: Node, ids: Dictionary) -> bool:
	if not _is_selection_piece(piece) or not piece.has_meta(BAKED_BRUSH_IDS_META):
		return false
	var held_ids := piece.get_meta(BAKED_BRUSH_IDS_META) as PackedStringArray
	for held_id in held_ids:
		if ids.has(held_id):
			return true
	return false


## How many of these brushes the full bake in `container` holds. A bake from
## before bakes kept a record may hold any of them, and so may a brush with no id.
func _held_by_full_bake(container: Node3D, brushes: Array) -> int:
	var full_payload := false
	for child in container.get_children():
		if not _is_selection_piece(child):
			full_payload = true
		elif not child.has_meta(BAKED_BRUSH_IDS_META):
			return brushes.size()
	if not full_payload:
		return 0
	if not container.has_meta(BAKED_BRUSH_IDS_META):
		return brushes.size()
	var record := container.get_meta(BAKED_BRUSH_IDS_META) as PackedStringArray
	var held := 0
	for brush in brushes:
		var brush_id := str((brush as DraftBrush).brush_id)
		if brush_id == "" or record.has(brush_id):
			held += 1
	return held


## The ids of the brushes a bake took, for `BAKED_BRUSH_IDS_META`, by the rule
## every command reads them by. A brush with no id gets one here rather than
## being left out: left out, a later Bake Selected of it found no bake holding it
## and baked it a second time beside this one (#1455).
##
## Not `HFBrushSystem.brush_ids_of()`, which keeps to the brushes a selection
## can name. A full bake under Commit Freeze takes the committed cuts too, and a
## cut restored to the level is found in this record by its id.
func _brush_ids_of(brushes: Array) -> PackedStringArray:
	var ids := PackedStringArray()
	for brush in brushes:
		if is_instance_valid(brush) and brush is DraftBrush:
			ids.append(root.brush_system.ensure_brush_id(brush as DraftBrush))
	return ids


## Every brush a full bake takes.
func _full_bake_brushes() -> Array:
	var brushes: Array = []
	var containers: Array = [root.draft_brushes_node]
	if root.commit_freeze:
		containers.append(root.committed_node)
	for container in containers:
		if not container:
			continue
		for child in container.get_children():
			if child is DraftBrush and brush_bakes(child as DraftBrush):
				brushes.append(child)
	return brushes


func _bake_selected_impl(
	brush_nodes: Array, collision_layer_mask: int = 0, preview_mode: int = 0, replaces: Array = []
) -> void:
	if not root.baker:
		push_warning("Bake skipped: baker not initialized")
		root.bake_finished.emit(false)
		root.emit_signal("user_message", "Bake failed — baker not initialized", 2)
		return
	if brush_nodes.is_empty():
		root.bake_finished.emit(false)
		root.emit_signal("user_message", "No brushes selected to bake", 1)
		return
	var started = Time.get_ticks_msec()
	var yield_overhead_ms := 0  # Idle time spent in frame yields — excluded from estimator
	root._log("Selection Bake Started (%d brushes)" % brush_nodes.size())
	root.bake_started.emit()
	root.bake_progress.emit(0.0, "Preparing selection")
	var layer = (
		collision_layer_mask
		if collision_layer_mask > 0
		else root._layer_from_index(root.bake_collision_layer_index)
	)
	var bake_options = build_bake_options()
	_apply_preview_mode(bake_options, preview_mode)
	var temp_csg = CSGCombiner3D.new()
	temp_csg.hide()
	temp_csg.use_collision = false
	root.add_child(temp_csg)
	append_brush_list_to_csg(brush_nodes, temp_csg)
	bake_options = _csg_bake_options(temp_csg, bake_options)
	root.bake_progress.emit(0.5, "Baking selection")
	var yield_start_ms := Time.get_ticks_msec()
	if not await _wait_frames(2):
		if is_instance_valid(temp_csg):
			temp_csg.queue_free()
		_report_left_tree()
		return
	yield_overhead_ms += Time.get_ticks_msec() - yield_start_ms
	var baked = root.baker.bake_from_csg(
		temp_csg, root.bake_material_override, layer, STATIC_BODY_MASK, bake_options
	)
	if baked:
		# Baker derives both the visual mesh and collision from this final boolean
		# result. Re-baking additive brushes alone would fill every doorway/cutout.
		# Mode 2 splits it by visgroup as a full bake does. The bodies are this
		# piece's own, so a later selection that replaces it takes them too.
		_partition_csg_collision(baked, bake_options)
		_apply_preview_visuals(baked, preview_mode)
	temp_csg.queue_free()
	if baked:
		root._last_bake_duration_ms = max(0, Time.get_ticks_msec() - started - yield_overhead_ms)
		root.bake_progress.emit(1.0, "Finalizing")
		# Merge into existing baked container rather than replacing it, in place of
		# what earlier selections made of these brushes (#1208).
		var active_container := reconcile_baked_containers()
		if not active_container:
			# An empty container holding no brush of its own, so this bake is a piece
			# like any later one, and a later Bake Selected can take it out.
			active_container = Node3D.new()
			active_container.set_meta(BAKED_BRUSH_IDS_META, PackedStringArray())
			replace_baked_container(active_container)
		for piece in replaces:
			if is_instance_valid(piece) and piece.get_parent() == active_container:
				active_container.remove_child(piece)
				piece.queue_free()
		baked.name = "BakedSelection_%d" % Time.get_ticks_msec()
		baked.set_meta(BAKED_BRUSH_IDS_META, _brush_ids_of(brush_nodes))
		active_container.add_child(baked)
		postprocess_bake(baked, true, brush_nodes)
		root._assign_owner_recursive(active_container)
		root._last_bake_preview_mode = preview_mode
		_last_bake_success = true
		root._log("Selection bake finished (success=true)")
		root.bake_finished.emit(true)
	else:
		root._last_bake_duration_ms = max(0, Time.get_ticks_msec() - started - yield_overhead_ms)
		_last_bake_success = false
		root._log("Selection bake failed")
		root.bake_finished.emit(false)


## The cordon settings, which decide which brushes are in a bake. The two lists
## below take them from here, and so do the editor's change tracker and the dock
## through `is_bake_setting()`. Each used to keep its own copy (#975).
const CORDON_BAKE_SETTINGS := [
	"cordon_enabled",
	"cordon_aabb",
	"cordon_extra_aabbs",
	"cordon_active",
]

## Every setting that decides what goes into the bake, or how it is built.
##
## Compared against the values the last successful bake ran with. A hash rather
## than a flag on each setter: most of these properties have no setter, and the
## hash covers the `.hflevel` load path for free, which a setter-set flag would
## not. The cordons are in here because they decide which brushes are in the
## bake at all. `bake_material_override` goes into the signature by resource
## path instead, because a Material has no stable hash across a reload.
const BAKE_SETTING_NAMES := BAKE_OPTION_NAMES + CORDON_BAKE_SETTINGS

## The `bake_` settings in `BAKE_SETTING_NAMES`.
const BAKE_OPTION_NAMES := [
	"bake_visible_only",
	"bake_use_face_materials",
	"bake_collision_mode",
	"bake_collision_layer_index",
	"bake_convex_clean",
	"bake_convex_simplify",
	"bake_lightmap_uv2",
	"bake_lightmap_texel_size",
	"bake_unwrap_uv0",
	"bake_generate_lods",
	"bake_chunk_size",
	"bake_merge_meshes",
	"bake_use_atlas",
	"bake_generate_occluders",
	"bake_occluder_min_area",
	"bake_navmesh",
	"bake_navmesh_cell_size",
	"bake_navmesh_cell_height",
	"bake_navmesh_agent_height",
	"bake_navmesh_agent_radius",
	"bake_navmesh_agent_max_climb",
	"bake_navmesh_agent_max_slope",
	"bake_auto_connectors",
	"bake_connector_mode",
	"bake_connector_stair_height",
	"bake_connector_width",
	"bake_connector_stair_threshold",
	"bake_wire_io",
]

## The bake settings that decide which brushes go into the bake rather than how
## it is built. A bake profile leaves them where the mapper put them: switching to
## Shipping must not drop a hidden visgroup from the bake, or bake one room.
const SCOPE_SETTING_NAMES := ["bake_visible_only"] + CORDON_BAKE_SETTINGS


## Whether a level property is one a bake depends on: a `bake_` setting or a
## cordon one. A change to one has to rebuild the bake, which the change tracker
## and the dock both arrange.
static func is_bake_setting(property_name: String) -> bool:
	return property_name.begins_with("bake_") or property_name in CORDON_BAKE_SETTINGS


## The settings a bake profile carries: every bake setting except the scope ones.
## Read from the list above, so a new bake setting joins profiles without a third
## list to keep in step.
static func profile_setting_names() -> Array[String]:
	var names: Array[String] = []
	for name in BAKE_SETTING_NAMES:
		if name not in SCOPE_SETTING_NAMES:
			names.append(name)
	return names


## The level's bake options as a profile holds them (`HFBakeProfiles`).
func capture_profile_options() -> Dictionary:
	var values := {}
	for name in profile_setting_names():
		values[name] = root.get(name)
	return values


## Set the options a profile names. A name that is not a profile setting, or a
## value the setting cannot hold, is left alone and said. Each value goes through
## the level's own setter, so a range is held there as it is for the dock.
func apply_profile_options(values: Dictionary) -> void:
	var names := profile_setting_names()
	for key in values:
		var name := str(key)
		if name not in names:
			HFLog.warn("Bake profile: %s is not an option a profile sets. Left alone." % name)
			continue
		var value = profile_value(root.get(name), values[key])
		if value == null:
			HFLog.warn(
				"Bake profile: %s cannot be %s. Left alone." % [name, JSON.stringify(values[key])]
			)
			continue
		root.set(name, value)


## `value` in the form a setting now holding `current` takes, or null. JSON has
## one number type, so a saved whole number comes back as a float and is put back;
## anything else of the wrong kind is refused rather than guessed at.
static func profile_value(current: Variant, value: Variant) -> Variant:
	match typeof(current):
		TYPE_BOOL:
			return value if value is bool else null
		TYPE_INT:
			if value is int:
				return value
			if value is float and is_finite(value) and value == floorf(value):
				return int(value)
		TYPE_FLOAT:
			if value is int or (value is float and is_finite(value)):
				return float(value)
	return null


func bake_settings_signature() -> int:
	var values: Array = []
	for name in BAKE_SETTING_NAMES:
		values.append(root.get(name))
	# A Material has no stable hash across a reload, so it goes in by path.
	var override_path := ""
	var override: Material = root.bake_material_override
	if override != null:
		override_path = str(override.resource_path)
		if override_path == "":
			override_path = str(override.get_instance_id())
	values.append(override_path)
	return values.hash()


## Every entity the navmesh parse can take a model from, as the parse would read
## it: its class, its properties (the Scene among them) and where it stands. Empty
## while the navmesh is off, because then no entity reaches the bake.
func navmesh_props_signature() -> int:
	var values: Array = []
	if root.bake_navmesh and root.entities_node:
		for entity: Node in root.entities_node.get_children():
			if not _may_cut_navmesh(entity):
				continue
			var draft := entity as DraftEntity
			var placed := draft.global_transform if draft.is_inside_tree() else draft.transform
			values.append([draft.entity_type, draft.entity_data, placed])
	return values.hash()


## The paint connectors the mapper kept with Confirm. A full bake builds every one
## of them whether or not the automatic connectors are on.
func connector_defs_signature() -> int:
	var paint_tool = root.get("paint_tool")
	if paint_tool == null or not paint_tool.has_method("capture_connector_defs"):
		return [].hash()
	return paint_tool.capture_connector_defs().hash()


## Whether the export can build this entity from a scene, which is how one brings
## the static collider `_stand_in_props_for_parse()` gives the parse: its class
## names a scene, or lets each instance name one, as `prop_static` does.
func _may_cut_navmesh(entity: Node) -> bool:
	if not (entity is DraftEntity):
		return false
	var definition: Dictionary = root.get_entity_definition((entity as DraftEntity).entity_type)
	return (
		str(definition.get("scene", "")).strip_edges() != ""
		or str(definition.get("scene_property", "")).strip_edges() != ""
	)


## Rebuild from authoritative source when brush or structural dirty state exists.
## Missing dirty IDs represent deletions and therefore still require a bake.
func bake_dirty(collision_layer_mask: int = 0, preview_mode: int = 0) -> bool:
	if _bake_in_flight:
		_last_bake_status = BakeStatus.BUSY
		root.emit_signal("user_message", "A bake is already running", 1)
		return false
	var dirty_ids: Array = root._dirty_brush_ids.keys()
	var full_reconcile_started: bool = root._full_reconcile_needed
	# A changed setting is a change. Nothing marked the bake settings dirty, so a
	# rebake after one was flipped took the "no changed brushes" path and left the
	# previous result standing: hide a visgroup, bake to check something, turn
	# "bake visible only" off, bake again, and the level that ships is missing
	# every brush in that visgroup. Nothing about the result said it was stale.
	if _has_baked_once and bake_settings_signature() != _last_bake_settings_signature:
		root._log("Bake settings changed since the last bake, rebuilding in full")
		return await bake(true, false, collision_layer_mask, preview_mode)
	# So is a prop the navmesh is cut around. The parse takes each one (#1197) and no
	# edit to an entity tags anything, so a prop moved, added or deleted left its
	# hole where it was (#1239). Compared rather than tagged, so the gizmo, the
	# Inspector, undo and every command count alike.
	if _has_baked_once and navmesh_props_signature() != _last_navmesh_props_signature:
		root._log("A prop the navmesh is cut around changed since the last bake, rebuilding")
		return await bake(true, false, collision_layer_mask, preview_mode)
	# And so is a paint connector kept or taken back. Confirm adds to the list the
	# bake builds from and tags nothing, so Bake Changed left out the ramp (#1255).
	# Compared for the same reason as the props: undo, redo and a reload change the
	# list as well, and none of them goes through Confirm.
	if _has_baked_once and connector_defs_signature() != _last_connector_defs_signature:
		root._log("The paint connectors changed since the last bake, rebuilding")
		return await bake(true, false, collision_layer_mask, preview_mode)
	# Painted ground is a change too. Its chunks are tagged by every stroke and
	# regenerate, and nothing read them, so the bake kept the old terrain (#1199).
	var paint_dirty: bool = not root._dirty_paint_chunks.is_empty()
	if dirty_ids.is_empty() and not full_reconcile_started and not paint_dirty:
		_last_bake_status = BakeStatus.NOTHING_TO_DO
		root.emit_signal("user_message", "No changed brushes since last bake", 1)
		return false
	var brush_nodes: Array = []
	for bid in dirty_ids:
		var brush = root._find_brush_by_key(str(bid))
		if brush:
			brush_nodes.append(brush)
	root._log("Incremental bake: %d dirty brushes" % brush_nodes.size())
	# Full context needed for correct CSG — bake everything but track dirty set
	return await bake(true, false, collision_layer_mask, preview_mode)


func _has_bake_sources() -> bool:
	return (
		_has_positive_structural_sources()
		or _has_generated_heightmap_source()
		or _has_nonstructural_sources()
	)


func _has_positive_structural_sources() -> bool:
	for container in [root.draft_brushes_node, root.generated_floors, root.generated_walls]:
		if _has_positive_structural_brush(container):
			return true
	return false


func _has_generated_heightmap_source() -> bool:
	for heightmap in collect_generated_heightmap_meshes():
		if heightmap is MeshInstance3D and heightmap.mesh:
			return true
	return false


func _has_positive_structural_brush(container: Node3D) -> bool:
	if not container:
		return false
	for child in container.get_children():
		if not (child is DraftBrush) or root.is_entity_node(child):
			continue
		var brush := child as DraftBrush
		if brush.operation == CSGShape3D.OPERATION_SUBTRACTION:
			continue
		if not brush_bakes(brush):
			continue
		if not _is_structural_brush(brush):
			continue
		return true
	return false


## Whether any face of the level has been given its own material.
##
## Worth saying out loud before a bake drops them: the Materials panel, the face
## filters and "Apply to Selected Faces" all work on the preview whether or not
## the bake is going to carry the result.
func _faces_carry_materials() -> bool:
	for brush in collect_face_bake_brushes():
		if not (is_instance_valid(brush) and brush is DraftBrush):
			continue
		if _brush_carries_face_materials(brush as DraftBrush):
			return true
	return false


## The same question about one brush, which is what decides how it enters the
## CSG tree.
func _brush_carries_face_materials(brush: DraftBrush) -> bool:
	if not is_instance_valid(brush):
		return false
	for face in brush.faces:
		if face and face.material_idx >= 0:
			return true
	return false


## The mesh that puts a textured brush into the CSG tree with its texturing
## intact.
##
## Godot's CSG carries a material per face. `CSGMesh3D` takes one from each
## surface of its mesh and the boolean writes it through to the output, so a
## brush handed over as a mesh with one surface per material comes out the other
## side still wearing them. Assigning `CSGMesh3D.material` is the thing that
## collapses them all into one, and that is what this path did to every brush -
## so a single cutter anywhere in a level moved the whole level onto the CSG
## path and cost every brush in it its texturing (#693).
##
## The faces resolve exactly as the face-material bake resolves them, through the
## same `snapshot_brush_faces()`, so the two paths cannot disagree about what a
## face is painted with.
##
## Null for a brush with no face materials, which leaves every untextured brush
## on the prefab primitive it has always been cut with.
func _face_material_csg_mesh(draft: DraftBrush) -> Mesh:
	if not root.bake_use_face_materials or not root.baker:
		return null
	if not _brush_carries_face_materials(draft):
		return null
	var snapshot: Dictionary = root.baker.snapshot_brush_faces(
		draft, root.material_manager, root.bake_material_override, false
	)
	var records: Array = snapshot.get("records", [])
	if records.is_empty():
		return null
	# A boolean needs a closed solid. The face-material bake path draws whatever
	# triangles it is given and a hole costs it one invisible face, but a hole in
	# a CSG operand is a hole in the result, so a brush whose faces did not all
	# triangulate goes back on the primitive, which is always closed.
	var solid_faces := 0
	for face in draft.faces:
		if face:
			solid_faces += 1
	if records.size() != solid_faces:
		return null
	# Grouped by material, because a surface is a material and the whole point is
	# to hand CSG more than one of them.
	var groups: Dictionary = {}
	var order: Array = []
	for rec in records:
		var mat: Material = rec.get("material", null)
		var key: Variant = "_default"
		if mat != null:
			key = mat
		if not groups.has(key):
			groups[key] = {
				"material": mat,
				"verts": PackedVector3Array(),
				"uvs": PackedVector2Array(),
				"normals": PackedVector3Array(),
			}
			order.append(key)
		var group: Dictionary = groups[key]
		var verts: PackedVector3Array = rec.get("verts", PackedVector3Array())
		var uvs: PackedVector2Array = rec.get("uvs", PackedVector2Array())
		var normals: PackedVector3Array = rec.get("normals", PackedVector3Array())
		var face_normal: Vector3 = rec.get("face_normal", Vector3.UP)
		for i in range(verts.size()):
			group["verts"].append(verts[i])
			group["uvs"].append(uvs[i] if uvs.size() > i else Vector2.ZERO)
			group["normals"].append(normals[i] if normals.size() > i else face_normal)
	var mesh := ArrayMesh.new()
	for key in order:
		var group: Dictionary = groups[key]
		var verts: PackedVector3Array = group["verts"]
		if verts.is_empty():
			continue
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var mat: Material = group["material"]
		if mat:
			st.set_material(mat)
		var uvs: PackedVector2Array = group["uvs"]
		var normals: PackedVector3Array = group["normals"]
		for i in range(verts.size()):
			if normals.size() > i:
				st.set_normal(normals[i])
			if uvs.size() > i:
				st.set_uv(uvs[i])
			st.add_vertex(verts[i])
		st.commit(mesh)
	return mesh if mesh.get_surface_count() > 0 else null


func _has_effective_structural_subtractors() -> bool:
	for container in [root.draft_brushes_node, root.generated_floors, root.generated_walls]:
		if _container_has_effective_subtractor(container):
			return true
	# Frozen committed cutters are forced to subtraction by the CSG path even
	# when their serialized operation still says union.
	return root.commit_freeze and _container_has_effective_subtractor(root.committed_node, true)


func _container_has_effective_subtractor(container: Node3D, force_subtract: bool = false) -> bool:
	return _count_effective_subtractors(container, force_subtract, true) > 0


## How many cutters are in the level. Same walk as the test above, counted rather
## than answered yes or no, so the message that says the face-material path was
## dropped can name how many brushes caused it (#694).
func _count_effective_structural_subtractors() -> int:
	var total := 0
	for container in [root.draft_brushes_node, root.generated_floors, root.generated_walls]:
		total += _count_effective_subtractors(container)
	if root.commit_freeze:
		total += _count_effective_subtractors(root.committed_node, true)
	return total


func _count_effective_subtractors(
	container: Node3D, force_subtract: bool = false, stop_at_first: bool = false
) -> int:
	if not container:
		return 0
	var total := 0
	_begin_walk()
	for child in container.get_children():
		if not (child is DraftBrush) or root.is_entity_node(child):
			continue
		var brush := child as DraftBrush
		if not brush_bakes(brush):
			continue
		if not _is_structural_brush(brush):
			continue
		if force_subtract or brush.operation == CSGShape3D.OPERATION_SUBTRACTION:
			total += 1
			if stop_at_first:
				break
	_end_walk()
	return total


## Remove the exact set of dirty tags represented by a started bake.
## Clearing before the first await gives later edits a distinct live entry,
## even though the public dirty-tag dictionary stores only boolean values.
##
## The painted chunks are claimed with them, and held here rather than passed
## along: one bake runs at a time (#1199).
func _claim_dirty_tags(dirty_snapshot: Dictionary, full_reconcile_started: bool = false) -> void:
	for brush_id in dirty_snapshot:
		root._dirty_brush_ids.erase(brush_id)
	if full_reconcile_started:
		root._full_reconcile_needed = false
	_claimed_paint_chunks = root._dirty_paint_chunks.duplicate()
	root._dirty_paint_chunks.clear()


## A successful bake leaves only tags created while it was running. On
## failure, merge the claimed snapshot back without replacing concurrent tags.
func _finish_dirty_tag_claim(
	dirty_snapshot: Dictionary, succeeded: bool, full_reconcile_started: bool = false
) -> void:
	var claimed_paint := _claimed_paint_chunks
	_claimed_paint_chunks = []
	if succeeded:
		return
	for brush_id in dirty_snapshot:
		if not root._dirty_brush_ids.has(brush_id):
			root._dirty_brush_ids[brush_id] = dirty_snapshot[brush_id]
	if full_reconcile_started:
		root._full_reconcile_needed = true
	for chunk_id in claimed_paint:
		root.tag_paint_dirty(chunk_id)


# ---------------------------------------------------------------------------
# Preview mode helpers
# ---------------------------------------------------------------------------


func _apply_preview_mode(options: Dictionary, mode: int) -> void:
	if mode == PreviewMode.WIREFRAME:
		options["merge_meshes"] = false
		options["generate_lods"] = false
		options["unwrap_uv2"] = false
	elif mode == PreviewMode.PROXY:
		options["merge_meshes"] = false
		options["generate_lods"] = false
		options["unwrap_uv2"] = false


func _apply_preview_visuals(container: Node3D, mode: int) -> void:
	if mode == PreviewMode.FULL:
		return
	var mat: Material = null
	if mode == PreviewMode.WIREFRAME:
		mat = _get_wireframe_material()
	elif mode == PreviewMode.PROXY:
		var std_mat := StandardMaterial3D.new()
		std_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		std_mat.albedo_color = Color(0.5, 0.5, 0.5, 0.4)
		std_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat = std_mat
	if mat:
		_apply_material_recursive(container, mat)


static func _get_wireframe_material() -> ShaderMaterial:
	if _wireframe_material and _wireframe_material.shader:
		return _wireframe_material
	if _wireframe_shader == null:
		_wireframe_shader = Shader.new()
		_wireframe_shader.code = (
			"shader_type spatial;\n"
			+ "render_mode unshaded, cull_disabled, wireframe, depth_draw_never;\n"
			+ "uniform vec4 color : source_color = vec4(0.2, 0.8, 1.0, 0.6);\n"
			+ "void fragment() { ALBEDO = color.rgb; ALPHA = color.a; }\n"
		)
	_wireframe_material = ShaderMaterial.new()
	_wireframe_material.shader = _wireframe_shader
	return _wireframe_material


func _apply_material_recursive(node: Node3D, mat: Material) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			child.material_override = mat
		elif child is MultiMeshInstance3D:
			child.material_override = mat
		elif child is Node3D:
			_apply_material_recursive(child, mat)


# ---------------------------------------------------------------------------
# Main bake
# ---------------------------------------------------------------------------


func bake(
	apply_cuts: bool = true,
	hide_live: bool = false,
	collision_layer_mask: int = 0,
	preview_mode: int = 0,  # PreviewMode.FULL
	force_csg: bool = false
) -> bool:
	if not _try_begin_bake():
		return false
	var signature := bake_settings_signature()
	var props := navmesh_props_signature()
	var connectors := connector_defs_signature()
	await _bake_impl(apply_cuts, hide_live, collision_layer_mask, preview_mode, force_csg)
	_bake_in_flight = false
	_last_bake_status = BakeStatus.SUCCESS if _last_bake_success else BakeStatus.FAILED
	if _last_bake_success:
		# Taken before the bake ran, so a setting changed while it was in flight
		# is still a change the next bake has to answer for.
		_last_bake_settings_signature = signature
		_last_navmesh_props_signature = props
		_last_connector_defs_signature = connectors
		_has_baked_once = true
	return _last_bake_success


func _bake_impl(
	apply_cuts: bool = true,
	hide_live: bool = false,
	collision_layer_mask: int = 0,
	preview_mode: int = 0,
	force_csg: bool = false
) -> void:
	var dirty_snapshot: Dictionary = root._dirty_brush_ids.duplicate()
	var full_reconcile_started: bool = root._full_reconcile_needed
	_claim_dirty_tags(dirty_snapshot, full_reconcile_started)
	_last_bake_success = false
	var started = Time.get_ticks_msec()
	var yield_overhead_ms := 0  # Idle time spent in frame yields — excluded from estimator
	if not _has_bake_sources():
		_complete_empty_bake(dirty_snapshot, full_reconcile_started, started)
		return
	if _has_positive_structural_sources() and not root.baker:
		_finish_dirty_tag_claim(dirty_snapshot, false, full_reconcile_started)
		push_warning("Bake skipped: baker not initialized")
		root.bake_finished.emit(false)
		root.emit_signal("user_message", "Bake failed — baker not initialized", 2)
		return
	if apply_cuts:
		root.apply_pending_cuts()
	if not _has_bake_sources():
		_complete_empty_bake(dirty_snapshot, full_reconcile_started, started)
		return
	root._log("Virtual Bake Started (apply_cuts=%s, hide_live=%s)" % [apply_cuts, hide_live])
	root.bake_started.emit()
	root.bake_progress.emit(0.0, "Preparing")
	var layer = (
		collision_layer_mask
		if collision_layer_mask > 0
		else root._layer_from_index(root.bake_collision_layer_index)
	)
	var baked: Node3D = null
	var bake_options = build_bake_options()
	_apply_preview_mode(bake_options, preview_mode)
	var use_face_material_path: bool = (
		bool(root.bake_use_face_materials)
		and not force_csg
		and not _has_effective_structural_subtractors()
	)
	if root.bake_use_face_materials and not use_face_material_path:
		# Independent face triangulation has no boolean subtraction stage.
		# Keep every effective cutter by switching this bake to CSG.
		#
		# The texturing no longer goes with it. A textured brush enters the CSG
		# tree as a mesh with one surface per material and comes out of the
		# boolean still wearing them, so the mapper keeps what they painted and
		# the cut still cuts (#693). Nothing to warn about, which is why the
		# user_message that used to fire here is gone: it said the materials were
		# dropped, and they are not.
		if force_csg:
			root._log("Face-material bake switched to CSG: this bake was asked for as CSG")
		else:
			var cutters := _count_effective_structural_subtractors()
			root._log(
				(
					"Face-material bake switched to CSG to preserve %d active cut%s"
					% [cutters, "" if cutters == 1 else "s"]
				)
			)
	elif not root.bake_use_face_materials and _faces_carry_materials():
		# The only log on this path used to fire the other way round, so the
		# silent case was a mapper texturing a level, pressing Bake and getting one
		# material over everything with nothing said about it.
		root.emit_signal(
			"user_message", "Per-face materials were not baked: Use Face Materials is off", 1
		)
		root._log("Per-face materials dropped: the CSG path resolves one material per brush")
	if not _has_positive_structural_sources():
		baked = _bake_heightmap_only(layer)
		if baked == null and _has_nonstructural_sources():
			baked = Node3D.new()
			baked.name = String(BAKED_CONTAINER_NAME)
	elif use_face_material_path:
		# --- Synchronous snapshot: triangulate + resolve materials before yields ---
		var face_brushes = collect_face_bake_brushes()
		var use_atlas: bool = bool(bake_options.get("use_atlas", false))
		var collision_mode: int = int(bake_options.get("collision_mode", 0))
		var snapshots: Array = []
		# Track per-brush visgroup assignments for partitioned collision (mode 2)
		var brush_visgroups: Array = []  # parallel to snapshots: PackedStringArray per brush
		for brush in face_brushes:
			if is_instance_valid(brush) and brush is DraftBrush:
				snapshots.append(
					root.baker.snapshot_brush_faces(
						brush, root.material_manager, root.bake_material_override, use_atlas
					)
				)
				if collision_mode >= 2 and root.visgroup_system:
					brush_visgroups.append(root.visgroup_system.get_visgroups_of(brush))
				else:
					brush_visgroups.append(PackedStringArray())
		# --- Yielding pass: world-space transform + grouping from frozen data ---
		# Grouped per chunk, not just per material. The chunked branch used to
		# live only on the CSG path, and `bake_use_face_materials` defaults to
		# true, so on every default level the bake took the branch that had never
		# heard of `bake_chunk_size` -- while the dock offered a Chunk Size spin,
		# the health badge said "Consider Chunking" and the dry run reported a
		# chunk count the bake did not produce (#656). Per-face baking has no
		# boolean interactions to preserve across a boundary, which is exactly why
		# `_chunking_has_cross_boundary_interactions()` guards the CSG path and is
		# not needed here.
		var chunk_members := _face_chunk_members(snapshots)
		var chunk_coords: Array = chunk_members.keys()
		chunk_coords.sort_custom(_compare_chunk_coords)
		var snap_total: int = snapshots.size()
		var collected := 0
		var chunk_groups: Dictionary = {}
		for coord in chunk_coords:
			var members: Array = chunk_members[coord]
			var groups: Dictionary = {}
			for index in members:
				root.baker.collect_snapshot_groups(snapshots[index], use_atlas, groups)
				collected += 1
				if collected % _FACE_BAKE_BATCH == 0 or collected == snap_total:
					root.bake_progress.emit(
						float(collected) / float(max(1, snap_total)) * 0.7,
						"Collecting faces %d/%d" % [collected, snap_total]
					)
					var yield_start_ms := Time.get_ticks_msec()
					if not await _wait_frames(1):
						break
					yield_overhead_ms += Time.get_ticks_msec() - yield_start_ms
			if _left_tree:
				break
			chunk_groups[coord] = groups
		if not _left_tree:
			root.bake_progress.emit(0.75, "Building mesh")
			var build_yield_start_ms := Time.get_ticks_msec()
			await _wait_frames(1)
			yield_overhead_ms += Time.get_ticks_msec() - build_yield_start_ms
		if _left_tree:
			_finish_left_tree_bake(dirty_snapshot, full_reconcile_started)
			return
		baked = _build_face_chunks(
			chunk_coords,
			chunk_groups,
			chunk_members,
			snapshots,
			brush_visgroups,
			bake_options,
			layer
		)
		# Match the CSG path: append heightmaps after collision partitioning so
		# partition cleanup cannot remove the heightmap collision body.
		if baked:
			_append_heightmap_meshes_to_baked(baked, layer)
		elif _has_generated_heightmap_source():
			# A valid heightmap is still authoritative output when structural
			# face collection produces no mesh (for example, empty/invalid faces).
			baked = _bake_heightmap_only(layer)
	else:
		if root.bake_chunk_size > 0.0:
			baked = await bake_chunked(root.bake_chunk_size, layer, bake_options)
		else:
			root.bake_progress.emit(0.5, "Baking")
			baked = await bake_single(layer, bake_options)
		if _left_tree:
			_finish_left_tree_bake(dirty_snapshot, full_reconcile_started)
			return
	if baked:
		root._last_bake_duration_ms = max(0, Time.get_ticks_msec() - started - yield_overhead_ms)
		root.bake_progress.emit(1.0, "Finalizing")
		replace_baked_container(baked)
		baked.set_meta(BAKED_BRUSH_IDS_META, _brush_ids_of(_full_bake_brushes()))
		postprocess_bake(root.baked_container)
		_apply_preview_visuals(root.baked_container, preview_mode)
		root._assign_owner_recursive(root.baked_container)
		if hide_live:
			if root.draft_brushes_node:
				root.draft_brushes_node.visible = false
			if root.pending_node:
				root.pending_node.visible = false
		root._log("Bake finished (success=true)")
		root._last_bake_preview_mode = preview_mode
		_last_bake_success = true
	else:
		root._last_bake_duration_ms = max(0, Time.get_ticks_msec() - started - yield_overhead_ms)
		root._log("Bake failed")
		_last_bake_success = false
		warn_bake_failure()
	_finish_dirty_tag_claim(dirty_snapshot, _last_bake_success, full_reconcile_started)
	root.bake_finished.emit(_last_bake_success)


## A whole-level bake whose level left the tree: the dirty tags it claimed go back
## for the next bake, and it says why it stopped.
func _finish_left_tree_bake(dirty_snapshot: Dictionary, full_reconcile_started: bool) -> void:
	if is_instance_valid(root):
		_finish_dirty_tag_claim(dirty_snapshot, false, full_reconcile_started)
	_report_left_tree()


func _complete_empty_bake(
	dirty_snapshot: Dictionary, full_reconcile_started: bool, started: int
) -> void:
	root._log("Virtual Bake Started (empty authoritative source)")
	root.bake_started.emit()
	root.bake_progress.emit(0.0, "Preparing")
	clear_baked_containers()
	root._last_bake_duration_ms = max(0, Time.get_ticks_msec() - started)
	root.bake_progress.emit(1.0, "Clearing baked geometry")
	root._log("Bake finished (success=true, scene is empty)")
	_last_bake_success = true
	_finish_dirty_tag_claim(dirty_snapshot, true, full_reconcile_started)
	root.bake_finished.emit(true)


func warn_bake_failure() -> void:
	var draft_count = count_brushes_in(root.draft_brushes_node)
	var pending_count = count_brushes_in(root.pending_node)
	var committed_count = count_brushes_in(root.committed_node)
	var entities_count = root.entities_node.get_child_count() if root.entities_node else 0
	var detail := (
		"Bake failed: no baked geometry (draft=%s, pending=%s, committed=%s, entities=%s)"
		% [draft_count, pending_count, committed_count, entities_count]
	)
	HFLog.warn(detail)
	var hint := ""
	if draft_count == 0:
		hint = "No draft brushes found — draw some brushes first"
	elif pending_count > 0:
		hint = "You have %d pending cuts — try 'Commit Cuts' before baking" % pending_count
	else:
		hint = "CSG produced no geometry — check brush operations and overlaps"
	root.emit_signal("user_message", hint, 2)


func build_bake_options() -> Dictionary:
	return {
		"merge_meshes": root.bake_merge_meshes,
		"generate_lods": root.bake_generate_lods,
		"unwrap_uv0": root.bake_unwrap_uv0,
		"unwrap_uv2": root.bake_lightmap_uv2,
		"uv2_texel_size": root.bake_lightmap_texel_size,
		"use_thread_pool": root.bake_use_thread_pool,
		"use_face_materials": root.bake_use_face_materials,
		"use_atlas": root.bake_use_atlas,
		"collision_mode": root.bake_collision_mode,
		"convex_clean": root.bake_convex_clean,
		"convex_simplify": root.bake_convex_simplify,
	}


func postprocess_bake(
	container: Node3D, selection_only: bool = false, selected_brushes: Array = []
) -> void:
	if not container:
		return
	if selection_only:
		_append_nonstructural_brushes(container, selected_brushes)
	else:
		_append_nonstructural_brushes(container)
	if _root_bool("bake_generate_occluders", false) and not selection_only:
		_generate_occluders(container)
	var paint_tool = root.get("paint_tool")
	var has_committed_connectors: bool = (
		paint_tool != null
		and paint_tool.get("connector_defs") is Array
		and not paint_tool.connector_defs.is_empty()
	)
	if (root.bake_auto_connectors or has_committed_connectors) and not selection_only:
		_append_auto_connectors(container)
	if root.bake_navmesh:
		bake_navmesh(container)
	var bake_wire_io := false
	if "bake_wire_io" in root:
		bake_wire_io = bool(root.get("bake_wire_io"))
	if bake_wire_io and not selection_only:
		_attach_io_dispatcher(container)
	if root.bake_lightmap_uv2:
		_report_missing_lightmap_uv2(container)


## Name static output with no UV2 even when the engine kept the mesh after an
## unwrap failure. Dynamic movers intentionally use probes instead of lightmaps.
func _report_missing_lightmap_uv2(container: Node3D) -> void:
	for child in container.find_children("*", "MeshInstance3D", true, false):
		var instance := child as MeshInstance3D
		if instance.gi_mode != GeometryInstance3D.GI_MODE_STATIC or instance.mesh == null:
			continue
		for i in instance.mesh.get_surface_count():
			var uv2: Variant = instance.mesh.surface_get_arrays(i)[Mesh.ARRAY_TEX_UV2]
			if not (uv2 is PackedVector2Array) or uv2.is_empty():
				HFLog.warn("Bake: %s has no lightmap UV2." % container.get_path_to(instance))
				break


## Attach an HFIORuntime dispatcher to the baked container so that entity I/O
## connections are wired as live Godot signals at runtime.  The dispatcher is
## parented under the baked container but also scans entities_node (a sibling
## subtree) via extra_scan_roots.
func _direct_child_has_io(parent: Node) -> bool:
	if not parent:
		return false
	for child in parent.get_children():
		if not child.get_meta("entity_io_outputs", []).is_empty():
			return true
	return false


func _attach_io_dispatcher(container: Node3D) -> void:
	# Point entities and brush entities (triggers, buttons) both store outputs.
	var has_io := (
		_direct_child_has_io(root.entities_node) or _direct_child_has_io(root.draft_brushes_node)
	)
	if not has_io:
		return
	# Remove any existing dispatcher
	var existing: Node = container.get_node_or_null("HFIODispatcher")
	if existing:
		container.remove_child(existing)
		existing.free()
	var dispatcher := HFIORuntime.new()
	dispatcher.name = "HFIODispatcher"
	# The dispatcher lives under the baked container, but point entities live
	# under root.entities_node (a sibling). Tell it to scan that subtree too.
	if root.entities_node:
		dispatcher.extra_scan_roots.append(root.entities_node)
	container.add_child(dispatcher)
	if root.entities_node:
		var entities_path: NodePath = dispatcher.get_path_to(root.entities_node)
		dispatcher.extra_scan_root_paths.append(entities_path)
	root._assign_owner_recursive(dispatcher)


## Whether the bake will take this brush at all.
##
## The cordon and `bake_visible_only` are each checked in seven places along the
## bake path and in none of the counting. So the dry run, which is the preflight
## the user reads before committing to a bake, reported brushes the bake was
## going to skip. One predicate, so the two cannot drift apart again.
##
## Subtraction is deliberately not part of this. A subtractor is a brush the bake
## takes and uses, and the dry run reports pending cuts on their own line.
func brush_bakes(brush: DraftBrush) -> bool:
	if brush == null or not is_instance_valid(brush):
		return false
	if root.is_entity_node(brush):
		return false
	if not _shown_for_bake(brush):
		return false
	if root.cordon_enabled and not _brush_in_cordon(brush):
		return false
	return true


## Whether Bake Visible Only lets this brush in. A committed cutter is judged by
## its visgroups, not by `visible`: Commit Cuts hides it so it stops drawing, and
## read as the mapper hiding it, every committed hole was filled in (#1245).
func _shown_for_bake(brush: DraftBrush) -> bool:
	if not root.bake_visible_only:
		return true
	if root.committed_node != null and brush.get_parent() == root.committed_node:
		return (
			root.visgroup_system == null or not root.visgroup_system.is_hidden_by_visgroups(brush)
		)
	return brush.visible


## How many brushes in this container the bake will take.
func count_brushes_in(container: Node3D) -> int:
	if not container:
		return 0
	var count := 0
	_begin_walk()
	for child in container.get_children():
		if child is DraftBrush and brush_bakes(child as DraftBrush):
			count += 1
	_end_walk()
	return count


func bake_single(layer: int, options: Dictionary) -> Node3D:
	var temp_csg = CSGCombiner3D.new()
	temp_csg.hide()
	temp_csg.use_collision = false
	root.add_child(temp_csg)
	append_draft_brushes_to_csg(root.draft_brushes_node, temp_csg)
	if root.commit_freeze and root.committed_node:
		append_draft_brushes_to_csg(root.committed_node, temp_csg, true)
	append_generated_brushes_to_csg(temp_csg)
	# Read now, while the brushes are where the CSG was handed them.
	var csg_options := _csg_bake_options(temp_csg, options)
	if not await _wait_frames(2):
		if is_instance_valid(temp_csg):
			temp_csg.queue_free()
		return null
	var baked = root.baker.bake_from_csg(
		temp_csg, root.bake_material_override, layer, STATIC_BODY_MASK, csg_options
	)
	temp_csg.queue_free()
	if baked:
		# FloorCollision came from the same final CSG as the visual: its triangles,
		# or hulls of the brushes with the cuts carved out of them. A subtractor
		# therefore carves collision instead of becoming a solid.
		# Visgroup-partitioned collision (mode 2) for CSG path, from the same
		# pieces. Must run BEFORE heightmap append so that partitioning only
		# removes the brush-generated FloorCollision body, not heightmap collision.
		_partition_csg_collision(baked, csg_options)
		# Heightmap collision is appended after partitioning.  If FloorCollision
		# was removed by partitioning, _append_heightmap_meshes_to_baked creates
		# a fresh one for heightmap-only collision shapes.
		_append_heightmap_meshes_to_baked(baked, layer)
	return baked


func bake_chunked(chunk_size: float, layer: int, options: Dictionary) -> Node3D:
	var size = max(0.001, chunk_size)
	var chunks = _collect_all_chunks(size)
	if chunks.is_empty():
		return null
	# Independent CSG combiners cannot reproduce boolean interactions across
	# chunk boundaries. Preserve correctness by using one CSG tree whenever
	# brushes assigned to different chunks overlap (especially cutters).
	if _chunking_has_cross_boundary_interactions(chunks):
		return await bake_single(layer, options)
	var container = Node3D.new()
	container.name = BAKED_CONTAINER_NAME
	var chunk_count = 0
	var total_chunks = 0
	for coord in chunks:
		var entry: Dictionary = chunks[coord]
		var brushes: Array = entry.get("brushes", [])
		var committed: Array = entry.get("committed", [])
		var generated: Array = entry.get("generated", [])
		if brushes.is_empty() and committed.is_empty() and generated.is_empty():
			continue
		total_chunks += 1
	if total_chunks == 0:
		return null
	var processed = 0
	for coord in chunks:
		var entry: Dictionary = chunks[coord]
		var brushes: Array = entry.get("brushes", [])
		var committed: Array = entry.get("committed", [])
		var generated: Array = entry.get("generated", [])
		if brushes.is_empty() and committed.is_empty() and generated.is_empty():
			continue
		var temp_csg = CSGCombiner3D.new()
		temp_csg.hide()
		temp_csg.use_collision = false
		root.add_child(temp_csg)
		append_brush_list_to_csg(brushes, temp_csg)
		append_brush_list_to_csg(generated, temp_csg)
		if root.commit_freeze:
			append_brush_list_to_csg(committed, temp_csg, true)
		var csg_options := _csg_bake_options(temp_csg, options)
		if not await _wait_frames(2):
			if is_instance_valid(temp_csg):
				temp_csg.queue_free()
			container.free()
			return null
		var baked_chunk = root.baker.bake_from_csg(
			temp_csg, root.bake_material_override, layer, STATIC_BODY_MASK, csg_options
		)
		if baked_chunk:
			# Visgroup-partitioned collision (mode 2) for this chunk
			_partition_csg_collision(baked_chunk, csg_options)
			baked_chunk.name = "BakedChunk_%s_%s_%s" % [coord.x, coord.y, coord.z]
			container.add_child(baked_chunk)
			chunk_count += 1
		temp_csg.queue_free()
		processed += 1
		if total_chunks > 0:
			var progress = float(processed) / float(total_chunks)
			root.bake_progress.emit(progress, "Chunk %d/%d" % [processed, total_chunks])
	if container and chunk_count > 0:
		_append_heightmap_meshes_to_baked(container, layer)
	return container if chunk_count > 0 else null


## Which snapshots belong to which chunk, as `coord -> [snapshot index]`.
##
## One entry at `Vector3i.ZERO` when chunking is off, so the caller's loop is the
## same shape either way and an unchunked bake produces exactly what it did
## before. The brush's world origin is already in the snapshot, taken before the
## yields, so this needs nothing off the live node.
func _face_chunk_members(snapshots: Array) -> Dictionary:
	var members: Dictionary = {}
	var chunk_size: float = root.bake_chunk_size
	for i in snapshots.size():
		var coord := Vector3i.ZERO
		if chunk_size > 0.0:
			var origin: Vector3 = (snapshots[i] as Dictionary).get("origin", Vector3.ZERO)
			coord = chunk_coord(origin, chunk_size)
		if not members.has(coord):
			members[coord] = []
		members[coord].append(i)
	return members


## A stable order for chunk containers, so two bakes of the same level produce
## the same scene rather than whatever order the dictionary happened to hold.
func _compare_chunk_coords(a: Vector3i, b: Vector3i) -> bool:
	if a.x != b.x:
		return a.x < b.x
	if a.y != b.y:
		return a.y < b.y
	return a.z < b.z


## One mesh per chunk, or one mesh when there is one chunk.
##
## A single chunk returns exactly what the unchunked path returned, with the same
## node shape, so nothing downstream has to learn about chunking to keep working.
## Several chunks are wrapped the way the CSG path wraps them, in `BakedChunk_`
## children of one container, which is what `postprocess_bake()`,
## `clear_baked_containers()` and the preview modes already walk.
func _build_face_chunks(
	chunk_coords: Array,
	chunk_groups: Dictionary,
	chunk_members: Dictionary,
	snapshots: Array,
	brush_visgroups: Array,
	bake_options: Dictionary,
	layer: int
) -> Node3D:
	var collision_mode: int = int(bake_options.get("collision_mode", 0))
	var built: Array = []
	for coord in chunk_coords:
		var members: Array = chunk_members[coord]
		var options := bake_options.duplicate()
		# Per-brush collision data is per chunk too, or a chunk's convex hulls
		# would be built from the whole level's brushes.
		var hull_verts: Array = []
		var visgroups: Array = []
		for index in members:
			hull_verts.append(
				(snapshots[index] as Dictionary).get("hull_verts", PackedVector3Array())
			)
			visgroups.append(
				brush_visgroups[index] if index < brush_visgroups.size() else PackedStringArray()
			)
		if collision_mode >= 1:
			options["per_brush_verts"] = hull_verts
		if collision_mode >= 2:
			options["brush_visgroups"] = visgroups
		var mesh: Node3D = root.baker.build_mesh_from_groups(
			chunk_groups[coord], layer, STATIC_BODY_MASK, options
		)
		if mesh == null:
			continue
		if collision_mode >= 2:
			_partition_collision_by_visgroup(mesh, hull_verts, visgroups, options)
		built.append({"coord": coord, "node": mesh})
	if built.is_empty():
		return null
	if built.size() == 1:
		return built[0]["node"]
	var container := Node3D.new()
	container.name = String(BAKED_CONTAINER_NAME)
	for entry in built:
		var coord: Vector3i = entry["coord"]
		var node: Node3D = entry["node"]
		node.name = "BakedChunk_%s_%s_%s" % [coord.x, coord.y, coord.z]
		container.add_child(node)
	return container


func get_bake_chunk_count() -> int:
	if root.bake_chunk_size <= 0.0:
		var total = count_brushes_in(root.draft_brushes_node)
		total += count_brushes_in(root.generated_floors)
		total += count_brushes_in(root.generated_walls)
		if root.commit_freeze:
			total += count_brushes_in(root.committed_node)
		return 1 if total > 0 else 0
	var size = max(0.001, root.bake_chunk_size)
	var chunks = _collect_all_chunks(size)
	# A boolean that reaches across a chunk boundary is a CSG problem: a cutter
	# in one chunk has to cut a solid in the next, and separate CSG trees cannot.
	# The per-face path has no booleans to preserve, so it chunks anyway -- and it
	# is the default, which is why this asks which path will run rather than
	# assuming the CSG one (#656).
	if not root.bake_use_face_materials and _chunking_has_cross_boundary_interactions(chunks):
		return 1
	var count := 0
	for coord in chunks:
		var entry: Dictionary = chunks[coord]
		var brushes: Array = entry.get("brushes", [])
		var committed: Array = entry.get("committed", [])
		var generated: Array = entry.get("generated", [])
		if brushes.is_empty() and committed.is_empty() and generated.is_empty():
			continue
		count += 1
	return count


func _collect_all_chunks(chunk_size: float) -> Dictionary:
	var chunks: Dictionary = {}
	collect_chunk_brushes(root.draft_brushes_node, chunk_size, chunks, "brushes")
	if root.commit_freeze and root.committed_node:
		collect_chunk_brushes(root.committed_node, chunk_size, chunks, "committed")
	collect_chunk_brushes(root.generated_floors, chunk_size, chunks, "generated")
	collect_chunk_brushes(root.generated_walls, chunk_size, chunks, "generated")
	return chunks


func _chunking_has_cross_boundary_interactions(chunks: Dictionary) -> bool:
	if chunks.size() < 2:
		return false
	var assigned: Array[Dictionary] = []
	for coord in chunks:
		var entry: Dictionary = chunks[coord]
		for key in [&"brushes", &"committed", &"generated"]:
			for candidate in entry.get(key, []):
				if not (candidate is DraftBrush) or not is_instance_valid(candidate):
					continue
				var brush := candidate as DraftBrush
				if not _shown_for_bake(brush):
					continue
				assigned.append({"coord": coord, "bounds": _brush_world_aabb(brush)})
	# Sweep on X so ordinary separated chunks remain close to O(n log n), while
	# still handling very large brushes that span many chunk coordinates.
	assigned.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			return (left["bounds"] as AABB).position.x < (right["bounds"] as AABB).position.x
	)
	for index in range(assigned.size()):
		var left: Dictionary = assigned[index]
		var left_bounds: AABB = left["bounds"]
		for other_index in range(index + 1, assigned.size()):
			var right: Dictionary = assigned[other_index]
			var right_bounds: AABB = right["bounds"]
			if right_bounds.position.x >= left_bounds.end.x:
				break
			if left["coord"] == right["coord"]:
				continue
			if left_bounds.intersects(right_bounds):
				return true
	return false


func bake_dry_run() -> Dictionary:
	var draft_count = count_brushes_in(root.draft_brushes_node)
	var pending_count = count_brushes_in(root.pending_node)
	var committed_count = count_brushes_in(root.committed_node)
	var generated_floors = count_brushes_in(root.generated_floors)
	var generated_walls = count_brushes_in(root.generated_walls)
	var heightmap_floors := 0
	if root.generated_heightmap_floors:
		heightmap_floors = root.generated_heightmap_floors.get_child_count()
	var chunk_count = get_bake_chunk_count()
	return {
		"draft": draft_count,
		"pending": pending_count,
		"committed": committed_count,
		"generated_floors": generated_floors,
		"generated_walls": generated_walls,
		"heightmap_floors": heightmap_floors,
		"chunk_count": chunk_count,
		"use_face_materials": root.bake_use_face_materials,
		"chunk_size": root.bake_chunk_size
	}


## The options to bake `csg` with. A convex collision mode gets the pieces of its
## brushes as `per_brush_verts`, and each piece's visgroups as `brush_visgroups`
## for Mode 2 to partition by (#1513).
##
## When the pieces cannot follow a cut, both are left out and the bake keeps the
## CSG's own triangles, which are exact, and the mapper is told why. Hulls that
## ignored the cut would fill it in.
func _csg_bake_options(csg: CSGCombiner3D, options: Dictionary) -> Dictionary:
	var collision_mode: int = int(options.get("collision_mode", 0))
	if collision_mode < 1:
		return options
	var out := options.duplicate()
	var pieces := _csg_collision_pieces(csg)
	if pieces.has("error"):
		var message := (
			"Collision Mode %d baked the cut mesh's triangles instead of hulls: %s"
			% [collision_mode, pieces["error"]]
		)
		root.emit_signal("user_message", message, 1)
		root._log(message)
		return out
	out["per_brush_verts"] = pieces["hull_verts"]
	out["brush_visgroups"] = pieces["visgroups"]
	return out


## What the convex collision modes hull on the CSG path: every convex piece of
## every brush in `csg`, with the cuts carved out of them (#1513).
##
## The CSG's output cannot say where one brush ends and the next begins, so the
## pieces come from the brushes, read off the operands so they are exactly the
## ones the boolean took. CSG applies its operands in order and a cut carves only
## what came before it, so a brush drawn after a cut is whole in the mesh and
## whole here. A cut carves by its planes, as Carve does, leaving the convex
## pieces round it: a doorway stays open, and a floor with a drain in it is floor
## all round the drain.
##
## Returns `{"hull_verts": Array, "visgroups": Array}`, one entry per piece, the
## points in the CSG node's own space, where its mesh comes out. `{"error": String}`
## when a cut that reaches a solid cannot be carved by planes, or an operand's
## brush has no solid to read.
func _csg_collision_pieces(csg: CSGCombiner3D) -> Dictionary:
	var into_csg := csg.global_transform.affine_inverse()
	var solids: Array = []
	for operand in csg.get_children():
		var shape := operand as CSGShape3D
		if shape == null:
			continue
		var source: Variant = null
		if shape.has_meta(CSG_SOURCE_META):
			source = shape.get_meta(CSG_SOURCE_META)
		if not is_instance_valid(source) or not (source is DraftBrush):
			return {"error": "a brush in it is gone"}
		var draft := source as DraftBrush
		root.brush_system._ensure_faces(draft)
		var faces: Array = draft.get_faces()
		if faces.size() < HFConvexClip.MIN_SOLID_FACES:
			return {"error": "a brush in it has no faces to hull"}
		var visgroups := PackedStringArray()
		if root.visgroup_system:
			visgroups = root.visgroup_system.get_visgroups_of(draft)
		var solid := _collision_solid(faces, into_csg * draft.global_transform, visgroups)
		if shape.operation == CSGShape3D.OPERATION_UNION:
			solids.append(solid)
			continue
		if shape.operation != CSGShape3D.OPERATION_SUBTRACTION:
			return {"error": "a brush in it is neither a solid nor a cut"}
		var refused := _carve_collision_solids(solids, solid)
		if refused != "":
			return {"error": refused}
	var hull_verts: Array = []
	var visgroups_of_pieces: Array = []
	for solid: Dictionary in solids:
		hull_verts.append(solid["points"])
		visgroups_of_pieces.append(solid["visgroups"])
	return {"hull_verts": hull_verts, "visgroups": visgroups_of_pieces}


## One solid for `_csg_collision_pieces()`: its faces in their own space, the
## transform into the CSG's, and its corners and bounds there.
static func _collision_solid(
	faces: Array, xform: Transform3D, visgroups: PackedStringArray
) -> Dictionary:
	var points := PackedVector3Array()
	for face in faces:
		var data := face as FaceData
		if data != null:
			points.append_array(xform * data.local_verts)
	var bounds := AABB(points[0], Vector3.ZERO) if not points.is_empty() else AABB()
	for point in points:
		bounds = bounds.expand(point)
	return {
		"faces": faces, "xform": xform, "points": points, "bounds": bounds, "visgroups": visgroups
	}


## Carve `cutter` out of every solid in `solids` it reaches, leaving the convex
## pieces round it. "" when it carved, or why it could not, with `solids` as it was.
##
## A cut that is not convex, or has more faces than a boolean takes, cannot be
## carved by planes. That only matters once it reaches a solid.
static func _carve_collision_solids(solids: Array, cutter: Dictionary) -> String:
	var cutter_faces: Array = cutter["faces"]
	var reach: AABB = cutter["bounds"]
	var checked := false
	var kept: Array = []
	for solid: Dictionary in solids:
		if not reach.intersects(solid["bounds"]):
			kept.append(solid)
			continue
		if not checked:
			var interior := HFConvexClip.interior_point(cutter_faces)
			if not HFConvexClip.boolean_plane_budget(cutter_faces, interior)["ok"]:
				return "a cut has more than %d faces" % HFConvexClip.MAX_BOOLEAN_PLANES
			if not HFConvexClip.is_convex_solid(cutter_faces, interior):
				return "a cut is not convex"
			checked = true
		var solid_xform: Transform3D = solid["xform"]
		var cutter_xform: Transform3D = cutter["xform"]
		var planes := HFConvexClip.face_planes_in_space(
			cutter_faces, solid_xform.affine_inverse() * cutter_xform
		)
		var carved := HFConvexClip.progressive_remainder(solid["faces"], planes)
		if not carved["separated"]:
			kept.append(solid)
			continue
		for piece: Array in carved["pieces"]:
			kept.append(_collision_solid(piece, solid_xform, solid["visgroups"]))
	solids.assign(kept)
	return ""


func _is_trigger_brush(brush: DraftBrush) -> bool:
	var bec = str(brush.get_meta("brush_entity_class", ""))
	return bec.begins_with("trigger_")


## Only a brush tied to no entity class is world. `func_wall` used to count as
## world too, so it merged into the static mesh with no node left to answer the
## Enable and Disable its definition declares (#827).
func _is_structural_brush(brush: DraftBrush) -> bool:
	return str(brush.get_meta("brush_entity_class", "")) == ""


func _has_nonstructural_sources() -> bool:
	return not _collect_nonstructural_brushes().is_empty()


func _collect_nonstructural_brushes(filter: Variant = null) -> Array:
	var out: Array = []
	var sources: Array = []
	if filter != null:
		sources = filter
	else:
		for container in [root.draft_brushes_node, root.generated_floors, root.generated_walls]:
			if container:
				sources.append_array(container.get_children())
	for child in sources:
		if not (child is DraftBrush):
			continue
		if root.is_entity_node(child):
			continue
		var draft := child as DraftBrush
		if draft.operation == CSGShape3D.OPERATION_SUBTRACTION:
			continue
		if _root_bool("bake_visible_only", false) and not draft.visible:
			continue
		if _root_bool("cordon_enabled", false) and not _brush_in_cordon(draft):
			continue
		if _is_structural_brush(draft):
			continue
		out.append(draft)
	return out


func _append_nonstructural_brushes(container: Node3D, filter: Variant = null) -> void:
	if not container:
		return
	var existing: Node = container.get_node_or_null("Nonstructural")
	if existing:
		container.remove_child(existing)
		existing.free()
	var brushes: Array = _collect_nonstructural_brushes(filter)
	if brushes.is_empty():
		return
	var holder := Node3D.new()
	holder.name = "Nonstructural"
	container.add_child(holder)
	# A brush the runtime has to find by name stays its own node; everything else
	# is grouped by material the way the structural path already groups. Trim and
	# clutter is most of a finished map, and `func_detail` reads like the cheap
	# option while costing one MeshInstance3D, one StaticBody3D and one
	# CollisionShape3D each - eighty crates in a room were eighty-one draw calls
	# where the structural path would have made one (#712).
	var grouped: Array = []
	var idx := 0
	for draft in brushes:
		if _is_trigger_brush(draft):
			_append_trigger_volume(holder, draft, idx)
		elif _needs_its_own_node(draft):
			_append_detail_mesh(holder, draft, idx)
		else:
			grouped.append(draft)
		idx += 1
	_append_grouped_detail(holder, grouped)


## Whether this brush has to survive the bake as a node of its own.
##
## A name is the address an I/O connection targets and outputs are what it
## dispatches, so a brush carrying either has to stay findable, and so does one
## whose class takes part in I/O, since a wire can aim at a brush by the node name
## the editor shows. `func_detail` has no inputs, no outputs and no name - it is
## excluded from the structural CSG and nothing else - so it does not need to be
## its own node at all. The readable name every brush is given since #1065 is not
## a name a mapper chose, and reading it as one left no brush grouped (#1139).
func _needs_its_own_node(draft: DraftBrush) -> bool:
	if not (draft.get_meta("entity_io_outputs", []) as Array).is_empty():
		return true
	if _class_takes_part_in_io(str(draft.get_meta("brush_entity_class", ""))):
		return true
	if str(draft.get_meta("entity_name", "")) != "":
		return true
	if authored_entity_name(draft) == "":
		return false
	return not (root.brush_system and root.brush_system.has_readable_name(draft))


## Whether a brush entity class declares an input or an output, or is one that
## moves. A class with no definition might, since nothing says it does not.
func _class_takes_part_in_io(entity_class: String) -> bool:
	if entity_class in MOVER_CLASSES:
		return true
	var definition: Dictionary = root.get_entity_definition(entity_class)
	if definition.is_empty():
		return true
	for key in ["inputs", "outputs"]:
		var declared: Variant = definition.get(key, [])
		if declared is Array and not (declared as Array).is_empty():
			return true
	return false


## One mesh per material and one collision body for every detail brush that does
## not need a node of its own. The same grouping the structural path uses, run a
## second time over the brushes that path skipped.
func _append_grouped_detail(holder: Node3D, brushes: Array) -> void:
	if brushes.is_empty():
		return
	if not root.baker:
		# Nothing to group with. Fall back to what this path did before, so a level
		# with only clutter in it still bakes rather than failing on the way in.
		var idx := 0
		for draft in brushes:
			_append_detail_mesh(holder, draft, idx)
			idx += 1
		return
	var options := build_bake_options()
	var use_atlas: bool = bool(options.get("use_atlas", false))
	var groups: Dictionary = {}
	var hull_verts: Array = []
	for draft in brushes:
		root.baker.collect_brush_face_groups(
			draft, root.material_manager, root.bake_material_override, use_atlas, groups
		)
		var snapshot: Dictionary = root.baker.snapshot_brush_faces(
			draft, root.material_manager, root.bake_material_override, use_atlas
		)
		hull_verts.append(snapshot.get("hull_verts", PackedVector3Array()))
	if groups.is_empty():
		return
	var layer := 1
	if root.has_method("_layer_from_index"):
		layer = root._layer_from_index(root.bake_collision_layer_index)
	# Per-brush convex hulls, so a merged pile of clutter still collides as the
	# separate solids it is rather than as one hull around all of them.
	var detail_options := options.duplicate(true)
	detail_options["collision_mode"] = maxi(1, int(options.get("collision_mode", 0)))
	detail_options["per_brush_verts"] = hull_verts
	var built: Node3D = root.baker.build_mesh_from_groups(
		groups, layer, STATIC_BODY_MASK, detail_options
	)
	if not built:
		return
	built.name = "DetailGeometry"
	holder.add_child(built)


## The authored name an entity is wired to. Brushes get a Godot generated node
## name unless the author renamed them, so fall back to the node name only when
## it is not one of those generated names.
static func authored_entity_name(draft: Node) -> String:
	if not draft:
		return ""
	var meta_name := str(draft.get_meta("entity_name", ""))
	if meta_name != "":
		return meta_name
	var node_name := str(draft.name)
	if node_name == "" or node_name.begins_with("@") or node_name == "DraftBrush":
		return ""
	return node_name


## The brush's own node name, on the node the bake makes for a brush of a named
## entity. The editor takes it as an address of the entity, as it takes the name
## (`HFEntitySystem._node_answers_to()`), and the target dropdown offered it. The
## node is named after the entity, so nothing in the game answered to it (#1149).
static func _keep_brush_address(node: Node, draft: Node) -> void:
	var entity_name := str(draft.get_meta(HFBrushEntity.NAME_META, ""))
	if entity_name != "" and str(draft.name) != entity_name:
		node.set_meta(HFBrushEntity.BRUSH_NAME_META, str(draft.name))


## Add what the bake made of `draft` under `parent`. An entity of several brushes
## makes a node per brush under one authored name, and Godot named each one after
## the first `@Node3D@20`, which is what the game scene showed (#1169). Such a node
## takes the node name of its brush instead, which `_keep_brush_address()` makes
## an address of the entity already, so the game answers to no new name. Godot's
## own numbering would give `gate2`, the name of another door in plenty of levels.
static func _add_piece(parent: Node, piece: Node, draft: Node) -> void:
	var brush_name := str(draft.name)
	if parent.has_node(NodePath(str(piece.name))) and not brush_name.begins_with("@"):
		piece.name = brush_name
	parent.add_child(piece, true)


func _append_detail_mesh(holder: Node3D, draft: DraftBrush, idx: int) -> void:
	var mesh: Mesh = null
	var source: Node3D = draft
	if draft.mesh_instance and draft.mesh_instance.mesh:
		mesh = draft.mesh_instance.mesh
		source = draft.mesh_instance
	var authored := authored_entity_name(draft)
	var mi := MeshInstance3D.new()
	mi.name = authored if authored != "" else "FuncDetail_%d" % idx
	# A mover's identity belongs to the holder, so the holder takes the authored
	# name and the mesh under it becomes a leaf. `_cache_entities()` keys a node by
	# its name as well as by its `entity_name` meta, so a mesh still called `gate`
	# would answer to `gate` however its metadata read - and it is the one thing
	# under there that cannot act on an input (#687).
	var bec_early := str(draft.get_meta("brush_entity_class", ""))
	if bec_early in MOVER_CLASSES and authored != "":
		mi.name = "%s_Leaf_%d" % [authored, idx]
	if root.baker and root.baker.has_method("postprocess_detail_mesh"):
		var options := build_bake_options()
		if bec_early in MOVER_CLASSES:
			options["unwrap_uv2"] = false
		mesh = root.baker.postprocess_detail_mesh(mesh, options)
	mi.mesh = mesh
	if source is MeshInstance3D:
		mi.material_override = source.material_override
	if bec_early in MOVER_CLASSES:
		mi.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	if authored != "":
		mi.set_meta("entity_name", authored)
	# The same three the trigger volume below carries. A `func_door` went through
	# here rather than `_append_trigger_volume()` and kept only its name, so the
	# playtest scene had a node the runtime could find and nothing saying what it
	# was or what it was wired to -- `HFIORuntime` had nothing to dispatch `Open`
	# against (#668). `_cache_entity_under_key()` holds several nodes per name by
	# design, so a two leaf door is two meshes answering to one name and both
	# receive the input, which is what a two leaf door should do.
	var bec := str(draft.get_meta("brush_entity_class", ""))
	if bec != "":
		mi.set_meta("brush_entity_class", bec)
	var tie := HFBrushEntity.tie_to_bake(draft)
	if tie != "":
		mi.set_meta("brush_entity_group", tie)
	var outputs: Array = draft.get_meta("entity_io_outputs", [])
	if not outputs.is_empty():
		mi.set_meta("entity_io_outputs", outputs.duplicate(true))
	# A class that moves gets a holder of its own, so its mesh and its collision
	# travel together. A door that slid its mesh and left its collision behind
	# would be worse than one that does not move at all (#687).
	var parent: Node3D = holder
	var mover: Node3D = null
	if bec in MOVER_CLASSES:
		mover = Node3D.new()
		mover.name = authored if authored != "" else "Door_%d" % idx
		_add_piece(holder, mover, draft)
		parent = mover
	_add_piece(parent, mi, draft)
	mi.transform = _source_transform_in_baked_container(source, holder.get_parent() as Node3D)
	var body := StaticBody3D.new()
	body.name = "FuncDetailCollision_%d" % idx
	# What a ray that hits this body has hit. A button is pressed by the player
	# looking at it, and what a ray returns is the collider, not the mesh beside it
	# that carries the wiring (#686).
	if authored != "":
		body.set_meta("entity_name", authored)
	if bec != "":
		body.set_meta("brush_entity_class", bec)
	if tie != "":
		body.set_meta("brush_entity_group", tie)
	var layer := 1
	if root.has_method("_layer_from_index"):
		layer = root._layer_from_index(root.bake_collision_layer_index)
	body.collision_layer = layer
	body.collision_mask = STATIC_BODY_MASK
	# A button's lock and wait, on the body the player's ray hits and on the mesh
	# beside it, which `HFIORuntime.press_button()` reads (#1121).
	if bec == "func_button":
		var button_data: Dictionary = HFBrushEntity.properties(
			root.get_entity_definition(bec), draft
		)
		if not button_data.is_empty():
			mi.set_meta("entity_data", button_data.duplicate())
			body.set_meta("entity_data", button_data.duplicate())
	parent.add_child(body)
	body.transform = mi.transform
	var col := CollisionShape3D.new()
	col.shape = _shape_for_draft(draft, mesh)
	col.transform = body.transform.affine_inverse() * mi.transform
	body.add_child(col)
	if mover:
		_make_it_a_door(mover, mi, draft, authored, bec)
	_keep_brush_address(mover if mover else mi, draft)


## Move the identity onto the holder and give it the script that moves it.
##
## The name and the wiring go to the holder rather than the mesh, because the
## holder is what has to receive `Open` - `_cache_entity_under_key()` holds every
## node answering to a name, so leaving them on the mesh as well would deliver
## the input twice, once to something that cannot act on it.
func _make_it_a_door(
	mover: Node3D, mi: MeshInstance3D, draft: DraftBrush, authored: String, entity_class: String
) -> void:
	mover.set_meta("brush_entity_class", entity_class)
	mi.remove_meta("brush_entity_class")
	if mi.has_meta("brush_entity_group"):
		mover.set_meta("brush_entity_group", mi.get_meta("brush_entity_group"))
		mi.remove_meta("brush_entity_group")
	if authored != "":
		mover.set_meta("entity_name", authored)
		mi.remove_meta("entity_name")
	var outputs: Array = draft.get_meta("entity_io_outputs", [])
	if not outputs.is_empty():
		mover.set_meta("entity_io_outputs", outputs.duplicate(true))
		mi.remove_meta("entity_io_outputs")
	# The authored values, or the class defaults where the mapper set none. A
	# brush entity's properties can only be set by a `.map` import today (#728),
	# so on a level drawn here this is the defaults every time.
	var authored_data: Dictionary = HFBrushEntity.properties(
		root.get_entity_definition(entity_class), draft
	)
	if not authored_data.is_empty():
		mover.set_meta("entity_data", authored_data.duplicate())
	mover.set_script(HFDoorRuntime)
	if mover.has_method("apply_entity_data"):
		mover.call("apply_entity_data", authored_data)


func _append_trigger_volume(holder: Node3D, draft: DraftBrush, idx: int) -> void:
	var authored := authored_entity_name(draft)
	var area := Area3D.new()
	area.name = authored if authored != "" else "Trigger_%d" % idx
	area.monitoring = true
	area.monitorable = true
	if authored != "":
		area.set_meta("entity_name", authored)
	var bec := str(draft.get_meta("brush_entity_class", ""))
	if bec != "":
		area.set_meta("brush_entity_class", bec)
	var tie := HFBrushEntity.tie_to_bake(draft)
	if tie != "":
		area.set_meta("brush_entity_group", tie)
	var outputs: Array = draft.get_meta("entity_io_outputs", [])
	if not outputs.is_empty():
		area.set_meta("entity_io_outputs", outputs.duplicate(true))
	_keep_brush_address(area, draft)
	# Its properties as well, the way a door's holder gets them, or a
	# `trigger_multiple` fires on every body that enters whatever its wait says
	# (#1121).
	var authored_data: Dictionary = HFBrushEntity.properties(root.get_entity_definition(bec), draft)
	if not authored_data.is_empty():
		area.set_meta("entity_data", authored_data.duplicate())
	_add_piece(holder, area, draft)
	var source: Node3D = draft
	if draft.mesh_instance:
		source = draft.mesh_instance
	area.transform = _source_transform_in_baked_container(source, holder.get_parent() as Node3D)
	var col := CollisionShape3D.new()
	var mesh: Mesh = draft.mesh_instance.mesh if draft.mesh_instance else null
	col.shape = _shape_for_draft(draft, mesh)
	area.add_child(col)


func _shape_for_draft(draft: DraftBrush, mesh: Mesh) -> Shape3D:
	if mesh:
		var convex: Shape3D = mesh.create_convex_shape(true, false)
		if convex:
			return convex
		var tri: Shape3D = mesh.create_trimesh_shape()
		if tri:
			return tri
	var box := BoxShape3D.new()
	box.size = draft.size if draft.size.length() > 0.001 else Vector3.ONE
	return box


func collect_chunk_brushes(
	source: Node3D, chunk_size: float, chunks: Dictionary, key: String
) -> void:
	if not source:
		return
	_begin_walk()
	for child in source.get_children():
		if not (child is DraftBrush):
			continue
		if root.is_entity_node(child):
			continue
		if root.cordon_enabled and not _brush_in_cordon(child as DraftBrush):
			continue
		# func_detail and trigger brushes skip structural CSG
		if not _is_structural_brush(child as DraftBrush):
			continue
		var coord = chunk_coord((child as Node3D).global_position, chunk_size)
		if not chunks.has(coord):
			chunks[coord] = {"brushes": [], "committed": [], "generated": []}
		if not chunks[coord].has(key):
			chunks[coord][key] = []
		chunks[coord][key].append(child)
	_end_walk()


func chunk_coord(position: Vector3, chunk_size: float) -> Vector3i:
	var s = max(0.001, chunk_size)
	return Vector3i(
		int(floor(position.x / s)), int(floor(position.y / s)), int(floor(position.z / s))
	)


func append_draft_brushes_to_csg(
	source: Node3D, target: CSGCombiner3D, force_subtract: bool = false, only_additive: bool = false
) -> void:
	if not source or not target:
		return
	append_brush_list_to_csg(source.get_children(), target, force_subtract, only_additive)


func append_generated_brushes_to_csg(target: CSGCombiner3D, only_additive: bool = false) -> void:
	if not target:
		return
	if root.generated_floors:
		append_brush_list_to_csg(root.generated_floors.get_children(), target, false, only_additive)
	if root.generated_walls:
		append_brush_list_to_csg(root.generated_walls.get_children(), target, false, only_additive)


func collect_face_bake_brushes() -> Array:
	var out: Array = []
	_append_face_bake_container(root.draft_brushes_node, out)
	_append_face_bake_container(root.generated_floors, out)
	_append_face_bake_container(root.generated_walls, out)
	return out


func _append_face_bake_container(container: Node3D, out: Array) -> void:
	if not container:
		return
	for child in container.get_children():
		if child is DraftBrush and child.operation != CSGShape3D.OPERATION_SUBTRACTION:
			if root.bake_visible_only and not child.visible:
				continue
			if root.cordon_enabled and not _brush_in_cordon(child as DraftBrush):
				continue
			if not _is_structural_brush(child as DraftBrush):
				continue
			out.append(child)


## The mesh a brush has to be cut with because the prefab factory cannot build it.
##
## `PrefabFactory.create_prefab()` knows the primitives and falls back to a box for
## anything else, and CUSTOM is the only shape that reaches that fallback. So a
## vertex-edited wedge, a polygon extrusion, a bevelled brush or a hull imported
## from a `.map` went into the CSG as a rectangular box and baked as one. Its own
## mesh is what it looks like on screen and what `HFSubtractPreview` already cuts
## with, so the bake now cuts with the same thing.
##
## Null for every shape the factory does build, and for a custom brush whose mesh
## has not been built yet: the box is wrong, but it is better than dropping the
## brush out of the bake without a word.
static func _authored_brush_mesh(draft: DraftBrush) -> Mesh:
	if draft.shape != DraftBrush.BrushShape.CUSTOM:
		return null
	if draft.mesh_instance == null:
		return null
	return draft.mesh_instance.mesh


func append_brush_list_to_csg(
	brushes: Array, target: CSGCombiner3D, force_subtract: bool = false, only_additive: bool = false
) -> void:
	if not target:
		return
	_begin_walk()
	for child in brushes:
		if not (child is DraftBrush):
			continue
		if root.is_entity_node(child):
			continue
		if not _shown_for_bake(child as DraftBrush):
			continue
		if root.cordon_enabled and not _brush_in_cordon(child as DraftBrush):
			continue
		if not _is_structural_brush(child as DraftBrush):
			continue
		var draft: DraftBrush = child
		if (
			only_additive
			and (force_subtract or draft.operation == CSGShape3D.OPERATION_SUBTRACTION)
		):
			continue
		var subtracts: bool = force_subtract or draft.operation == CSGShape3D.OPERATION_SUBTRACTION
		var csg_shape: CSGShape3D = null
		var placement := draft.global_transform
		# A cutter goes in as a mesh for the same reason a solid does: the
		# boolean writes the material of the face that cut through to the face it
		# carved, so the cutter's own texturing is what fills the interior it
		# exposes (#746).
		#
		# A mirrored cutter is the exception, and since #749 it is a backstop
		# rather than a live path: `normalize_handedness()` takes the mirror off
		# at the two doors a brush can arrive through, so one should not reach
		# here. If one does, its negative determinant inverts face winding, and
		# the boolean reads an inverted mesh operand differently from the
		# primitive it regenerates from `size`: measured on one wall and one
		# cutter, 25.5000 against 25.6792. Both are wrong, but a mapper painting a
		# cutter must not move the cut, so a mirrored one stays on the primitive.
		# Same shape as the closed-solid guard below, and for the same reason: on
		# this side a bad operand is a wrong cut.
		var face_mesh: Mesh = null
		if not (subtracts and draft.global_transform.basis.determinant() < 0.0):
			face_mesh = _face_material_csg_mesh(draft)
		if face_mesh != null:
			var csg_faces := CSGMesh3D.new()
			csg_faces.mesh = face_mesh
			csg_faces.use_collision = true
			csg_shape = csg_faces
			# The face records are in the brush's own space, which is where the
			# snapshot's basis and origin put them back from.
		else:
			var authored: Mesh = _authored_brush_mesh(draft)
			if authored != null:
				var csg_mesh := CSGMesh3D.new()
				csg_mesh.mesh = authored
				csg_mesh.use_collision = true
				csg_shape = csg_mesh
				# The mesh is in the mesh instance's own space, so that is where it goes.
				placement = draft.mesh_instance.global_transform
			else:
				csg_shape = PrefabFactory.create_prefab(
					draft.shape, draft.size, max(3, draft.sides)
				)
				# The factory sizes an ellipsoid, a torus and the platonic solids
				# by the shape's own scale, and placing the shape over it baked
				# them at unit size (#1523). It goes inside the brush's placement.
				placement = placement * csg_shape.transform
		csg_shape.operation = (
			CSGShape3D.OPERATION_SUBTRACTION if force_subtract else draft.operation
		)
		# Setting `material` on a CSGMesh3D overrides every surface of its mesh
		# with the one, which is the whole of #693. A brush that brought its own
		# materials keeps them.
		if face_mesh == null:
			# An untextured brush bakes bare, as the face path bakes it. The
			# editor's translucent preview, red for a cut and blue for a solid, must
			# never reach a bake: the blue one made an unpainted room see-through
			# once it had a doorway (#1092).
			var mat = draft.material_override
			if mat:
				csg_shape.set("material", mat)
				csg_shape.set("material_override", mat)
		# The combiner is parented to LevelRoot, so it carries the root's
		# transform. Place the shape after it is in the tree, or the assignment
		# writes a local transform and the root lands on it a second time.
		target.add_child(csg_shape)
		csg_shape.global_transform = placement
		csg_shape.set_meta(CSG_SOURCE_META, draft)
	_end_walk()


## Mode 2's split of what a CSG bake built with `csg_options`, which
## `_csg_bake_options()` made, into one body per visgroup. Every CSG bake goes
## through here; Bake Selected used to leave it out (#1524). Nothing to do in the
## other modes, or when the pieces could not follow a cut and the triangles stand.
func _partition_csg_collision(baked: Node3D, csg_options: Dictionary) -> void:
	if int(csg_options.get("collision_mode", 0)) < 2 or not csg_options.has("per_brush_verts"):
		return
	_partition_collision_by_visgroup(
		baked, csg_options["per_brush_verts"], csg_options["brush_visgroups"], csg_options
	)


## Replace existing collision bodies with per-visgroup StaticBody3D nodes.
## [param hull_verts] is an Array[PackedVector3Array], one per brush.
## [param brush_visgroups] is a parallel Array[PackedStringArray].
## Brushes with no visgroup go into a "_default" body.
func _partition_collision_by_visgroup(
	baked: Node3D, hull_verts: Array, brush_visgroups: Array, options: Dictionary
) -> void:
	var convex_clean: bool = bool(options.get("convex_clean", true))
	var convex_simplify: float = float(options.get("convex_simplify", 0.0))
	var layer: int = 0
	var mask: int = 0
	# Remove existing collision bodies (FaceCollision from face-bake, FloorCollision from CSG)
	for body_name in ["FaceCollision", "FloorCollision"]:
		var old_body: Node = baked.get_node_or_null(body_name)
		if old_body:
			if old_body is StaticBody3D:
				layer = old_body.collision_layer
				mask = old_body.collision_mask
			old_body.get_parent().remove_child(old_body)
			old_body.free()
	# Group per-brush hull verts by visgroup name
	var vg_buckets: Dictionary = {}  # visgroup_name -> Array[PackedVector3Array]
	for i in range(hull_verts.size()):
		var hull: PackedVector3Array = (
			hull_verts[i] if hull_verts[i] is PackedVector3Array else PackedVector3Array()
		)
		if hull.is_empty():
			continue
		var vgs: PackedStringArray = (
			brush_visgroups[i] if i < brush_visgroups.size() else PackedStringArray()
		)
		if vgs.is_empty():
			if not vg_buckets.has("_default"):
				vg_buckets["_default"] = []
			vg_buckets["_default"].append(hull)
		else:
			for vg_name in vgs:
				if not vg_buckets.has(vg_name):
					vg_buckets[vg_name] = []
				vg_buckets[vg_name].append(hull)
	# Create one StaticBody3D per visgroup
	for vg_name in vg_buckets:
		var verts_list: Array = vg_buckets[vg_name]
		var shapes: Array = Baker.build_convex_collision_shapes(
			verts_list, convex_clean, convex_simplify
		)
		if shapes.is_empty():
			continue
		var body := StaticBody3D.new()
		var safe_name: String = vg_name.replace(" ", "_").replace("/", "_")
		body.name = "Collision_%s" % safe_name
		body.collision_layer = layer
		body.collision_mask = mask
		for shape in shapes:
			var col := CollisionShape3D.new()
			col.shape = shape
			body.add_child(col)
		baked.add_child(body)


func collect_generated_heightmap_meshes() -> Array:
	var out: Array = []
	if not root.generated_heightmap_floors:
		return out
	for child in root.generated_heightmap_floors.get_children():
		if child is MeshInstance3D:
			out.append(child)
	return out


func _bake_heightmap_only(layer: int) -> Node3D:
	var container := Node3D.new()
	container.name = BAKED_CONTAINER_NAME
	_append_heightmap_meshes_to_baked(container, layer)
	if container.get_child_count() == 0:
		container.free()
		return null
	return container


func _append_heightmap_meshes_to_baked(container: Node3D, layer: int) -> void:
	var hm_meshes := collect_generated_heightmap_meshes()
	if hm_meshes.is_empty():
		return
	var body := container.get_node_or_null("FloorCollision") as StaticBody3D
	if not body:
		body = StaticBody3D.new()
		body.name = "FloorCollision"
		body.collision_layer = layer
		body.collision_mask = STATIC_BODY_MASK
		container.add_child(body)
	for hm in hm_meshes:
		var dup: MeshInstance3D = hm.duplicate()
		container.add_child(dup)
		dup.transform = _source_transform_in_baked_container(hm, container)
		if dup.mesh:
			var col := CollisionShape3D.new()
			col.shape = dup.mesh.create_trimesh_shape()
			col.transform = body.transform.affine_inverse() * dup.transform
			body.add_child(col)


func _source_transform_in_baked_container(source: Node3D, container: Node3D) -> Transform3D:
	# Unparented bake products are installed directly under LevelRoot.
	var eventual_container_world := root.global_transform * container.transform
	if container.is_inside_tree():
		eventual_container_world = container.global_transform
	return eventual_container_world.affine_inverse() * source.global_transform


## The confirmed definitions followed by automatic boundaries not yet confirmed.
## Validation reads this same list, including its rule for malformed entries.
func connector_definitions(layers: Object) -> Array:
	var definitions: Array = []
	var known: Dictionary = {}
	var paint_tool = root.get("paint_tool")
	if paint_tool != null:
		known = paint_tool.confirmed_keys()
		for definition in paint_tool.connector_defs:
			if definition is HFConnectorTool.ConnectorDef:
				definitions.append(definition)
	if root.bake_auto_connectors and layers != null:
		var gen := HFAutoConnector.new()
		var settings := HFAutoConnector.Settings.from_level(root)
		var segments := gen.detect_boundaries(layers)
		for definition in gen.defs_from_groups(gen.group_segments(segments), settings):
			if known.has(definition.boundary_key()):
				continue
			known[definition.boundary_key()] = true
			definitions.append(definition)
	return definitions


func _append_auto_connectors(container: Node3D) -> void:
	if not root.paint_layers or root.paint_layers.layers.size() < 2:
		return
	var gen := HFAutoConnector.new()
	var definitions := connector_definitions(root.paint_layers)
	var results := gen.generate_definitions(definitions, root.paint_layers)
	if results.is_empty():
		return
	var body := container.get_node_or_null("FloorCollision") as StaticBody3D
	if not body:
		body = StaticBody3D.new()
		body.name = "FloorCollision"
		container.add_child(body)
	var idx := 0
	for entry: Dictionary in results:
		var mesh: ArrayMesh = entry.get("mesh")
		if not mesh:
			continue
		var xform: Transform3D = entry.get("transform", Transform3D.IDENTITY)
		var mi := MeshInstance3D.new()
		mi.name = "AutoConnector_%d" % idx
		mi.mesh = mesh
		mi.transform = xform
		container.add_child(mi)
		var col := CollisionShape3D.new()
		col.shape = mesh.create_trimesh_shape()
		col.transform = body.transform.affine_inverse() * mi.transform
		body.add_child(col)
		idx += 1
	if idx > 0:
		root._log("Auto-connectors: generated %d connector(s)" % idx)


## Bake the navigation region under the baked container.
##
## The parse source is the collision this bake just wrote, not the visual mesh,
## less what moves and plus the props the export will build.
## Both an empty parse and an empty bake are silent in the engine, so a level
## could launch Test Level with navigation that does nothing and say so nowhere
## (#788). Every nav bake now names its source and its polygon count, and an
## empty region is a warning that says which of the two ways it came out empty.
func bake_navmesh(container: Node3D) -> void:
	if not container:
		return
	var nav_region = container.get_node_or_null("BakedNavmesh") as NavigationRegion3D
	if not nav_region:
		nav_region = NavigationRegion3D.new()
		nav_region.name = "BakedNavmesh"
		container.add_child(nav_region)
	var nav_mesh = nav_region.navigation_mesh
	if not nav_mesh:
		nav_mesh = NavigationMesh.new()
		nav_region.navigation_mesh = nav_mesh
	nav_mesh.cell_size = root.bake_navmesh_cell_size
	nav_mesh.cell_height = root.bake_navmesh_cell_height
	nav_mesh.agent_height = root.bake_navmesh_agent_height
	# Ceil agent_radius to cell_size units to avoid precision warning
	var cs: float = root.bake_navmesh_cell_size
	nav_mesh.agent_radius = ceil(root.bake_navmesh_agent_radius / cs) * cs
	# The two that decide whether an agent can use the stairs this plugin builds.
	# They were left at Godot's defaults while the four above them were set (#701).
	nav_mesh.agent_max_climb = root.bake_navmesh_agent_max_climb
	nav_mesh.agent_max_slope = root.bake_navmesh_agent_max_slope
	# Parse collision shapes instead of visual meshes (avoids GPU readback stall).
	_set_parsed_geometry_type(nav_mesh, NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS)
	# -1 keeps "the region baked itself and never told us" apart from "it parsed
	# nothing", which are different things to tell the user.
	var source_vertices := -1
	if (
		ClassDB.class_has_method("NavigationServer3D", "parse_source_geometry_data")
		and ClassDB.class_has_method("NavigationServer3D", "bake_from_source_geometry_data")
		and ClassDB.class_exists("NavigationMeshSourceGeometryData3D")
	):
		var source = NavigationMeshSourceGeometryData3D.new()
		var props := _stand_in_props_for_parse(container)
		var lifted := _lift_movers_out_of_parse(container)
		NavigationServer3D.parse_source_geometry_data(nav_mesh, source, container)
		for body: StaticBody3D in lifted:
			body.collision_layer = int(lifted[body])
		if props:
			container.remove_child(props)
			props.free()
		source_vertices = source.get_vertices().size()
		NavigationServer3D.bake_from_source_geometry_data(nav_mesh, source)
	elif nav_region.has_method("bake_navigation_mesh"):
		nav_region.call("bake_navigation_mesh")
	report_navmesh_bake(nav_mesh, source_vertices)


## Take every body of a brush entity that moves off its layers for the parse, and
## return each with the layer to give back. The navmesh is baked once, with every
## door shut, so a door the parse read made its doorway a wall to every agent,
## open or shut (#1196). The layer is back before anything else runs, so the
## player meets the door as before.
func _lift_movers_out_of_parse(container: Node3D) -> Dictionary:
	var lifted := {}
	for node: Node in container.find_children("*", "StaticBody3D", true, false):
		var at := node
		while at and at != container:
			if str(at.get_meta("brush_entity_class", "")) in MOVER_CLASSES:
				var body := node as StaticBody3D
				lifted[body] = body.collision_layer
				body.collision_layer = 0
				break
			at = at.get_parent()
	return lifted


## Put what the export builds for each entity into the container for the parse,
## where it brings a static collider, under one holder the caller frees. A
## `prop_static` is built only at export, so the navmesh never saw its model and
## agents planned paths straight through it (#1197). Built by the export's own
## builder, so the navmesh is cut by what the game will have there.
func _stand_in_props_for_parse(container: Node3D) -> Node3D:
	if not root.entities_node or not container.is_inside_tree():
		return null
	var holder: Node3D = null
	for entity: Node in root.entities_node.get_children():
		if not (entity is Node3D):
			continue
		var built: Node = root._playtest_node_for_entity(entity as Node3D)
		if built == null:
			continue
		if (
			not (built is StaticBody3D)
			and built.find_children("*", "StaticBody3D", true, false).is_empty()
		):
			built.free()
			continue
		if holder == null:
			holder = Node3D.new()
			holder.name = "NavmeshProps"
			container.add_child(holder)
		holder.add_child(built)
		if built is Node3D:
			(built as Node3D).global_transform = (entity as Node3D).global_transform
	return holder


## What the navmesh was told to parse, read back rather than assumed.
## _set_parsed_geometry_type() can fail on a build that names the property
## something else, and then the source is Godot's default and not ours. Naming
## the value we asked for instead of the one that stuck would be a lie in the
## one case where the reader needs the truth.
static func parsed_geometry_name(nav_mesh: NavigationMesh) -> String:
	var value = nav_mesh.get("geometry_parsed_geometry_type")
	if value == null:
		value = nav_mesh.get("parsed_geometry_type")
	if value == null:
		return "an unknown source"
	match int(value):
		NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS:
			return "collision"
		NavigationMesh.PARSED_GEOMETRY_MESH_INSTANCES:
			return "visual meshes"
		NavigationMesh.PARSED_GEOMETRY_BOTH:
			return "collision and visual meshes"
	return "an unknown source"


## Say what the nav bake produced, and why it produced nothing when it did.
##
## Empty for two different reasons, which want two different fixes: no geometry
## reached the parse at all, or geometry reached it and no polygon survived the
## agent size. source_vertices is -1 when the parse count is unavailable.
func report_navmesh_bake(nav_mesh: NavigationMesh, source_vertices: int) -> void:
	var source_name := parsed_geometry_name(nav_mesh)
	var polygons := nav_mesh.get_polygon_count()
	if polygons > 0:
		var plural := "" if polygons == 1 else "s"
		var line := "Navmesh: %d polygon%s from %s" % [polygons, plural, source_name]
		root.emit_signal("user_message", line, 0)
		return
	var detail := "Navmesh is empty: %s produced nothing walkable" % source_name
	if source_vertices == 0:
		detail += " (no geometry reached the parse)"
	elif source_vertices > 0:
		detail += (
			" (geometry reached the parse, but agent radius %.2f / height %.2f left no polygon)"
			% [nav_mesh.agent_radius, nav_mesh.agent_height]
		)
	HFLog.warn(detail)
	root.emit_signal("user_message", detail, 1)


## Set the parsed-geometry-type on a NavigationMesh (or any Object with the
## expected property), handling the property rename between Godot versions
## (parsed_geometry_type → geometry_parsed_geometry_type).
## Returns true if the property was set, false if neither name was found.
static func _set_parsed_geometry_type(target: Object, value: int) -> bool:
	if "geometry_parsed_geometry_type" in target:
		target.set("geometry_parsed_geometry_type", value)
		return true
	if "parsed_geometry_type" in target:
		target.set("parsed_geometry_type", value)
		return true
	HFLog.warn("NavigationMesh has neither geometry_parsed_geometry_type nor parsed_geometry_type")
	return false


## How far a brush may be from a cordon and still touch it, in metres. Godot's
## `AABB.intersects()` leaves out two boxes that only share a face, so a floor
## with a cordon typed on its top was left out of the bake (#1206).
const CORDON_TOUCH := 0.001


func _brush_in_cordon(brush: DraftBrush) -> bool:
	var regions: Array[AABB] = root.get_cordon_regions()
	# Every cordon switched off cuts nothing, as with the cordon off. Taken as an
	# empty region list, it refused every brush and baked an empty level.
	if regions.is_empty():
		return true
	var bounds := _brush_world_aabb(brush).grow(CORDON_TOUCH)
	for region in regions:
		if region.intersects(bounds):
			return true
	# A cutter goes with what it cuts. Left out because it lay outside the cordon,
	# the brush the cordon took baked whole, with floor where the level has a pit.
	if not _cuts(brush):
		return false
	var solids: Array[AABB] = []
	if _walk_solids is Array:
		solids = _walk_solids
	else:
		solids = _cordon_solid_bounds(regions)
		if _walk_depth > 0:
			_walk_solids = solids
	for solid in solids:
		if solid.intersects(bounds):
			return true
	return false


## The solids the cordons take, kept while one walk over the brushes asks about
## cutter after cutter, and null outside a walk. Each cutter outside every cordon
## reads every brush, so sixty of them on a level of six hundred brushes made the
## dry run thirty times slower. Dropped when the walk ends, because a brush can
## move between two walks and nothing tells this system.
var _walk_solids: Variant = null
var _walk_depth := 0


func _begin_walk() -> void:
	_walk_depth += 1


func _end_walk() -> void:
	_walk_depth = maxi(_walk_depth - 1, 0)
	if _walk_depth == 0:
		_walk_solids = null


## Whether the bake cuts with this brush: a subtraction, or a frozen committed cut,
## which the bake forces to one whatever its own operation says.
func _cuts(brush: DraftBrush) -> bool:
	if brush.operation == CSGShape3D.OPERATION_SUBTRACTION:
		return true
	return root.committed_node != null and brush.get_parent() == root.committed_node


## The bounds of the structural solids the cordons take, which are what a cutter
## can cut. A brush with a class does not go into the boolean, so no cutter cuts it.
func _cordon_solid_bounds(regions: Array[AABB]) -> Array[AABB]:
	var out: Array[AABB] = []
	for container in [root.draft_brushes_node, root.generated_floors, root.generated_walls]:
		if not container:
			continue
		for child in container.get_children():
			if not (child is DraftBrush) or root.is_entity_node(child):
				continue
			var solid := child as DraftBrush
			if _cuts(solid) or not _is_structural_brush(solid):
				continue
			if root.bake_visible_only and not solid.visible:
				continue
			var bounds := _brush_world_aabb(solid)
			var grown := bounds.grow(CORDON_TOUCH)
			for region in regions:
				if region.intersects(grown):
					out.append(bounds)
					break
	return out


func _brush_world_aabb(brush: DraftBrush) -> AABB:
	return brush_world_aabb(brush, brush.global_transform)


## A brush's bounds in the level, with the brush at `xform`: its mesh when it has
## one, which is the only thing that counts a sculpt, else its faces, else its
## size, each carried through the transform. The heightmap and the subtract
## preview ask this too (#901). Their own copies boxed the size around the
## brush's position, which is the wrong box for a brush that has been turned.
## `xform` lets a caller ask about a brush that is not in the tree yet.
static func brush_world_aabb(brush: DraftBrush, xform: Transform3D) -> AABB:
	var mesh_instance := brush.mesh_instance
	if mesh_instance and is_instance_valid(mesh_instance) and mesh_instance.mesh:
		return _transform_aabb(mesh_instance.mesh.get_aabb(), xform * mesh_instance.transform)
	if not brush.faces.is_empty():
		var has_vertex := false
		var face_bounds := AABB()
		for face in brush.faces:
			if not face:
				continue
			for local_vertex in face.local_verts:
				var world_vertex: Vector3 = xform * local_vertex
				if has_vertex:
					face_bounds = face_bounds.expand(world_vertex)
				else:
					face_bounds = AABB(world_vertex, Vector3.ZERO)
					has_vertex = true
		if has_vertex:
			return face_bounds
	return _transform_aabb(AABB(-brush.size * 0.5, brush.size), xform)


static func _transform_aabb(local_bounds: AABB, world_transform: Transform3D) -> AABB:
	var minimum := local_bounds.position
	var maximum := local_bounds.end
	var first: Vector3 = world_transform * minimum
	var result := AABB(first, Vector3.ZERO)
	for x in [minimum.x, maximum.x]:
		for y in [minimum.y, maximum.y]:
			for z in [minimum.z, maximum.z]:
				result = result.expand(world_transform * Vector3(x, y, z))
	return result


# ---------------------------------------------------------------------------
# Automated occluder generation
# ---------------------------------------------------------------------------

## Angle threshold (radians) for grouping coplanar triangles.
const _OCCLUDER_NORMAL_THRESHOLD := 0.087  # ~5 degrees
## Distance threshold for plane membership.
const _OCCLUDER_PLANE_DIST_THRESHOLD := 0.1
## Vertex positions are rounded to this before they are compared, so two
## triangles that meet at a corner are recognised as meeting there. It is the
## same order as the validator's weld tolerance, and small enough that two
## surfaces a mapper drew apart never round together.
const _OCCLUDER_WELD := 0.001


## Scan baked MeshInstance3D children, group their triangles into flat surfaces,
## and create one OccluderInstance3D per surface.
##
## A surface is triangles that are coplanar **and touching**. The coplanarity
## test on its own is what #614 was: two triangles facing the same way and lying
## in the same infinite plane were put in the same occluder whether they shared
## an edge or were a level apart, so every floor at y = 0 became one occluder and
## every wall on a shared line joined it. Godot gives an OccluderInstance3D a
## single bounding volume, so one of those is never itself culled and stands for
## a surface that is mostly holes. Forty boxes in a row produced an occluder
## spanning all 10,113 units between the first and the last.
##
## Touching is tested on welded vertex positions, which is what "shares an edge
## with it" comes to for baked geometry: the triangles of one wall come from one
## brush face and hold its corners exactly, and two walls a room apart hold none
## in common. Two brushes that abut without sharing vertices give two occluders
## rather than one, which is the right answer either way round.
##
## The grouping is transitive, so a run of triangles that turns gently stays one
## occluder shaped like the run. That is what an occluder should be. It is a
## single pass keyed on vertex position rather than the old scan of every plane
## found so far for every triangle, which was quadratic in the triangle count.
func _generate_occluders(container: Node3D) -> void:
	# Remove previously generated occluders so re-bake is idempotent.
	var existing: Node = container.find_child("Occluders", false, false)
	if existing:
		container.remove_child(existing)
		existing.free()

	var min_area: float = _root_float("bake_occluder_min_area", 4.0)
	var tris: Array = _collect_occluder_triangles(container)
	var surfaces: Array = _group_touching_coplanar(tris)

	# Filter by minimum area and build occluder nodes.
	var occluder_container := Node3D.new()
	occluder_container.name = "Occluders"
	var count := 0
	for surface in surfaces:
		var members: Array = surface
		var area := 0.0
		for i in members:
			area += float(tris[i]["area"])
		if area < min_area:
			continue
		var verts := PackedVector3Array()
		var indices := PackedInt32Array()
		for i in members:
			var tri: Dictionary = tris[i]
			var base := verts.size()
			verts.append(tri["a"])
			verts.append(tri["b"])
			verts.append(tri["c"])
			indices.append(base)
			indices.append(base + 1)
			indices.append(base + 2)
		var occ := ArrayOccluder3D.new()
		occ.vertices = verts
		occ.indices = indices
		var inst := OccluderInstance3D.new()
		inst.occluder = occ
		inst.name = "Occluder_%d" % count
		occluder_container.add_child(inst)
		count += 1

	if count > 0:
		container.add_child(occluder_container)
		root._assign_owner_recursive(occluder_container)
		root._log(
			(
				"Occluders: generated %d from %d flat surfaces in %d triangles"
				% [count, surfaces.size(), tris.size()]
			)
		)
	else:
		occluder_container.free()


## Every triangle of every baked mesh, in container space, with the plane it lies
## on. One Dictionary per triangle: `a`, `b`, `c`, `normal`, `dist`, `area`.
##
## Triangles too small to have a reliable normal are dropped here rather than
## carried, because a degenerate one has no plane to be grouped by.
func _collect_occluder_triangles(container: Node3D) -> Array:
	var out: Array = []
	for mi: MeshInstance3D in _collect_mesh_instances(container):
		var mesh: Mesh = mi.mesh
		if not mesh:
			continue
		# Transform relative to container so occluders are in container-local space.
		var xform: Transform3D = container.global_transform.affine_inverse() * mi.global_transform
		# A brush entity bakes in its own frame, so this carries the brush's own
		# scale, and a stretched slope's normal needs the inverse transpose (#884).
		var to_normal := FaceData.normal_basis(xform.basis)
		for surf_idx in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(surf_idx)
			if arrays.is_empty():
				continue
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			if verts.is_empty():
				continue
			var normals_arr: PackedVector3Array = (
				arrays[Mesh.ARRAY_NORMAL]
				if (
					arrays.size() > Mesh.ARRAY_NORMAL
					and arrays[Mesh.ARRAY_NORMAL] is PackedVector3Array
				)
				else PackedVector3Array()
			)
			var indices: PackedInt32Array = (
				arrays[Mesh.ARRAY_INDEX]
				if (
					arrays.size() > Mesh.ARRAY_INDEX
					and arrays[Mesh.ARRAY_INDEX] is PackedInt32Array
				)
				else PackedInt32Array()
			)
			var corners: PackedInt32Array = indices
			if corners.size() < 3:
				corners = PackedInt32Array()
				for i in verts.size():
					corners.append(i)
			var i := 0
			while i + 2 < corners.size():
				var first: int = corners[i]
				var a: Vector3 = xform * verts[first]
				var b: Vector3 = xform * verts[corners[i + 1]]
				var c: Vector3 = xform * verts[corners[i + 2]]
				i += 3
				var n: Vector3 = (c - a).cross(b - a)
				var area: float = n.length() * 0.5
				if area < 0.001:
					continue
				n = n.normalized()
				# Use normal from mesh data if available.
				if normals_arr.size() > first:
					var mesh_n: Vector3 = (to_normal * normals_arr[first]).normalized()
					if mesh_n.length_squared() > 0.5:
						n = mesh_n
				out.append({"a": a, "b": b, "c": c, "normal": n, "dist": n.dot(a), "area": area})
	return out


## The triangles grouped into flat surfaces: coplanar and touching. Returns one
## `PackedInt32Array` of indices into `tris` per surface.
##
## Two triangles are joined when they hold a vertex in common and lie on the same
## plane within the angle and distance thresholds. Holding a vertex in common is
## what makes this one pass: each vertex names the handful of triangles that meet
## there, and only those are ever compared. Nothing walks the list of surfaces
## found so far.
## `Array[int]` rather than `PackedInt32Array` for `parent`: the union-find writes
## to it from inside a call, and an Array is unambiguously the caller's array
## rather than a copy-on-write view of it. Typed, so `parent[i]` still has a type
## to infer from and `resize()` fills with zeros rather than nulls.
static func _group_touching_coplanar(tris: Array) -> Array:
	var parent: Array[int] = []
	parent.resize(tris.size())
	for i in tris.size():
		parent[i] = i

	# vertex position -> the triangles that touch it
	var at_vertex: Dictionary = {}
	for i in tris.size():
		var tri: Dictionary = tris[i]
		for corner in ["a", "b", "c"]:
			var key := _weld_key(tri[corner])
			if not at_vertex.has(key):
				at_vertex[key] = []
			at_vertex[key].append(i)

	for key in at_vertex:
		var here: Array = at_vertex[key]
		for x in range(here.size()):
			for y in range(x + 1, here.size()):
				if _same_plane(tris[here[x]], tris[here[y]]):
					_union(parent, here[x], here[y])

	var by_root: Dictionary = {}
	for i in tris.size():
		var r := _find(parent, i)
		if not by_root.has(r):
			by_root[r] = []
		by_root[r].append(i)
	return by_root.values()


## A vertex position rounded to the weld tolerance, so two triangles that meet
## at a corner agree on where that corner is.
static func _weld_key(v: Vector3) -> Vector3i:
	return Vector3i(
		roundi(v.x / _OCCLUDER_WELD), roundi(v.y / _OCCLUDER_WELD), roundi(v.z / _OCCLUDER_WELD)
	)


static func _same_plane(one: Dictionary, other: Dictionary) -> bool:
	return (
		(one["normal"] as Vector3).dot(other["normal"]) >= cos(_OCCLUDER_NORMAL_THRESHOLD)
		and absf(float(one["dist"]) - float(other["dist"])) < _OCCLUDER_PLANE_DIST_THRESHOLD
	)


static func _find(parent: Array[int], i: int) -> int:
	var top := i
	while parent[top] != top:
		top = parent[top]
	# Path compression, so a long chain is walked once rather than once per query.
	while parent[i] != top:
		var next := parent[i]
		parent[i] = top
		i = next
	return top


static func _union(parent: Array[int], a: int, b: int) -> void:
	var ra := _find(parent, a)
	var rb := _find(parent, b)
	if ra != rb:
		parent[rb] = ra


## Recursively collect all MeshInstance3D nodes under a container, walking into
## intermediary nodes like BakedChunk_* without picking up non-mesh children.
static func _collect_mesh_instances(node: Node) -> Array:
	var result: Array = []
	for child in node.get_children():
		if child is MeshInstance3D:
			result.append(child)
		elif child is Node3D and child.name != "Occluders":
			result.append_array(_collect_mesh_instances(child))
	return result


func _root_bool(property_name: String, default_value: bool) -> bool:
	if not root or not _root_has_property(property_name):
		return default_value
	return bool(root.get(property_name))


func _root_float(property_name: String, default_value: float) -> float:
	if not root or not _root_has_property(property_name):
		return default_value
	return float(root.get(property_name))


func _root_has_property(property_name: String) -> bool:
	if not root or property_name == "":
		return false
	for prop in root.get_property_list():
		if prop.get("name", "") == property_name:
			return true
	return false
