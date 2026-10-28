@tool
extends RefCounted
class_name HFValidationSystem

# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const DraftBrush = preload("../brush_instance.gd")
const HFPaintGrid = preload("../paint/hf_paint_grid.gd")
const HFBakeSystemType = preload("hf_bake_system.gd")
const HFSpawnSystemType = preload("hf_spawn_system.gd")
const HFTraversalCheck = preload("hf_traversal_check.gd")
const HFBrushEntity = preload("../hf_brush_entity.gd")
const HFVertexWeld = preload("../hf_vertex_weld.gd")
const HFBakeSplit = preload("../hf_bake_split.gd")
const HFConvexClip = preload("../hf_convex_clip.gd")
const HFHiddenFaceSearch = preload("../hf_hidden_face_search.gd")
const HFSolidMeasure = preload("../hf_solid_measure.gd")
const HFNotes = preload("../hf_notes.gd")
const HFDimensions = preload("../hf_dimensions.gd")
const HFAcceptedFindings = preload("../hf_accepted_findings.gd")
const HFValidationChecks = preload("../hf_validation_checks.gd")

## Two brushes this close everywhere are the same brush, for the near duplicate
## finding (#1708). A solid brush inside another to within this is inside it.
const NEAR_DUPLICATE := 0.001

## The kinds of finding a row can carry for the Test tab to select together.
const KIND_CUTS_NOTHING := "cut_cuts_nothing"
const KIND_INSIDE := "solid_inside_solid"
const KIND_NEAR_DUPLICATE := "near_duplicate"
const KIND_HIDDEN_IN_THE_OPEN := "hidden_face_in_the_open"
@warning_ignore_restore("shadowed_global_identifier")

var root: Node3D

## Vertex welding tolerance — vertices closer than this are considered coincident.
## Increase for legacy .map imports with floating-point drift (e.g. 0.01–0.1).
var weld_tolerance: float = 0.001

## Maximum allowed distance a vertex may deviate from its face plane before
## the face is flagged as non-planar. Increase for imported geometry.
var planarity_tolerance: float = 0.01

## Diagnostic: how many brush pairs reached an AABB test in the last
## `check_bake_issues()` pass. Read by the scale test and useful when profiling a
## cutter-heavy level. Reset at the start of every pass.
var pair_tests: int = 0

## Diagnostic: how many times the last `check_bake_issues()` pass worked out the
## connectors the bake would build. Both connector checks want the same list and
## it costs a walk of every painted cell, so anything above one is the memo
## below having stopped working. Reset at the start of every pass.
var connector_scans: int = 0

## The connector definitions for the pass in flight, or null before the first
## check asks for them. Cleared by `check_bake_issues()` rather than held
## between presses, because painting a cell changes the answer and nothing tells
## this system when that happens.
var _connector_memo: Variant = null

## The findings of the `validate()` call in flight, each naming its object.
var _findings: Array = []

## Findings accepted for this level, key to `{message, note, date, fingerprint}`
## (#1731). `HFAcceptedFindings` reads and writes it; it travels in the level's
## registries.
var accepted: Dictionary = {}
## How many whole passes `validate()` has made, and how many `recheck()` passes
## over changed brushes. Read by the tests that hold an edit to a recheck.
var full_passes := 0
var rechecks := 0
## How many brushes the last `recheck()` looked at: the changed ones and those
## near them.
var last_recheck_brushes := 0
## The kind of check in flight, which `_found()` stamps on each finding, and the
## kinds the project leaves out, read once a pass (`HFValidationChecks`).
var _check := ""
var _skipped := PackedStringArray()


func _init(level_root: Node3D) -> void:
	root = level_root


func check_missing_dependencies() -> Array:
	var warnings: Array = []
	if not root:
		return warnings
	# Material palette checks
	if root.material_manager:
		var materials: Array = root.material_manager.materials
		for i in range(materials.size()):
			var mat = materials[i]
			if mat == null:
				warnings.append("Material palette entry %d is null" % i)
				continue
			if mat.resource_path != "" and not ResourceLoader.exists(mat.resource_path):
				warnings.append("Material %d path missing: %s" % [i, mat.resource_path])
			if mat is ShaderMaterial:
				var shader_mat := mat as ShaderMaterial
				if shader_mat.shader == null:
					warnings.append("ShaderMaterial %d has no shader" % i)
	# A prefab instance whose source file has gone. The instance keeps working --
	# the brushes are real brushes -- so nothing looked wrong until someone
	# pressed Cycle Variant and got an empty string back, or Propagate and got
	# "0 instances updated", with no clue that the source was the problem (#669).
	# It is the case that gets worse with time: a project that has moved its
	# prefabs once has every instance in every level pointing at the old path.
	if root.prefab_system:
		var instances: Dictionary = root.prefab_system.get_all_instances()
		for instance_id in instances:
			var record = instances[instance_id]
			if record == null:
				continue
			var source := str(record.source_path)
			if source != "" and not FileAccess.file_exists(source):
				warnings.append(
					(
						"Prefab instance '%s' points at a file that is not there: %s"
						% [str(instance_id), source]
					)
				)
	# Blend shader check for heightmaps
	var has_heightmap := false
	if root.paint_layers:
		for layer in root.paint_layers.layers:
			if layer and layer.has_heightmap():
				has_heightmap = true
				break
	if not has_heightmap and root.generated_heightmap_floors:
		has_heightmap = root.generated_heightmap_floors.get_child_count() > 0
	if has_heightmap:
		var blend_path := "res://addons/hammerforge/paint/hf_blend.gdshader"
		if not ResourceLoader.exists(blend_path):
			warnings.append("Missing blend shader: %s" % blend_path)
	# A face pointing at a palette slot that is not there. `bake_use_face_materials`
	# has been the default since #491 and the palette starts empty, so the pairing
	# on its own is now the ordinary state of a level nobody has touched. What is
	# still worth saying is that a face was painted and the bake has nothing to
	# paint it with.
	if root.bake_use_face_materials and root.material_manager:
		if root.material_manager.materials.is_empty() and _any_face_names_a_material():
			warnings.append("A face is painted but the material palette is empty")
	return warnings


## True when some face carries a palette index, rather than sitting at the unset
## default every new brush is built with.
func _any_face_names_a_material() -> bool:
	if not root.draft_brushes_node:
		return false
	for child in root.draft_brushes_node.get_children():
		if not (child is DraftBrush):
			continue
		for face in child.faces:
			if face != null and int(face.material_idx) >= 0:
				return true
	return false


## Check the level, and with `auto_fix` repair what has one honest repair.
## Returns `issues`, the text of every finding, `fixed`, how many repairs it made,
## and `findings`, the same findings as `{type, severity, message, node}` with the
## object each names, as `check_bake_issues()` gives them, for the Test tab's list
## (#1004).
##
## Each finding carries its `check`, one of `HFValidationChecks.KINDS`, and the
## kinds the project leaves out are not run. Findings accepted for this level
## come back under `accepted` and are left out of `issues` and `findings`, unless
## what they name has changed since (#1731).
func validate(auto_fix: bool = false) -> Dictionary:
	var issues: Array = []
	var fixed := 0
	_findings = []
	if not root:
		return {"issues": issues, "fixed": fixed, "findings": _findings, "accepted": []}
	full_passes += 1
	_skipped = HFValidationChecks.skipped()

	# Dependencies
	_check = "data"
	for warning in check_missing_dependencies():
		_found(issues, "Dependency: %s" % str(warning))

	# Zero-size brushes
	var brush_nodes: Array = []
	if root.draft_brushes_node:
		brush_nodes.append_array(root.draft_brushes_node.get_children())
	if root.pending_node:
		brush_nodes.append_array(root.pending_node.get_children())
	if root.committed_node:
		brush_nodes.append_array(root.committed_node.get_children())
	var geometry_repairs: Array[DraftBrush] = []
	var brushes_to_delete: Array[DraftBrush] = []
	_check = "geometry"
	if _runs("geometry"):
		for node in brush_nodes:
			if node is DraftBrush:
				fixed += _check_brush_basics(
					node, issues, auto_fix, geometry_repairs, brushes_to_delete
				)

	# The repairs and the deletion happen after the walk, so the loop is not
	# mutating the list it is reading.
	if auto_fix:
		for brush in geometry_repairs:
			var repaired := fix_non_planar_faces(brush)
			repaired += weld_brush_vertices(brush)
			repaired += reverse_inward_faces(brush)
			if repaired > 0:
				fixed += repaired
				root.tag_brush_dirty(str(brush.brush_id))
		for brush in brushes_to_delete:
			if is_instance_valid(brush) and root.brush_system:
				root.brush_system.delete_brush(brush)
				fixed += 1

	# Hidden faces with open space in front of them (#1719): a hint that one may be
	# seen, not a fault, so it is a row and not in the count.
	if _runs("geometry"):
		_hint_hidden_faces_in_the_open()

	# Invalid face indices in selection
	_check = "data"
	var invalid_indices := 0
	var next_selection: Dictionary = {}
	for key in root.face_selection.keys():
		var brush = root._find_brush_by_key(str(key))
		var indices: Array = root.face_selection.get(key, [])
		if not brush or not (brush is DraftBrush):
			invalid_indices += indices.size()
			continue
		var max_idx = (brush as DraftBrush).faces.size()
		var filtered: Array = []
		for idx in indices:
			var value = int(idx)
			if value >= 0 and value < max_idx:
				filtered.append(value)
			else:
				invalid_indices += 1
		if filtered.size() > 0:
			next_selection[key] = filtered
	if invalid_indices > 0:
		_found(issues, "Face selection contains %d invalid indices" % invalid_indices)
		if auto_fix:
			root.face_selection = next_selection
			fixed += invalid_indices

	# Face material indices out of palette bounds
	var palette_count = root.material_manager.materials.size() if root.material_manager else 0
	var invalid_face_mats := 0
	var invalid_projections := 0
	for node in brush_nodes:
		if not (node is DraftBrush):
			continue
		var brush := node as DraftBrush
		for face in brush.faces:
			if face == null:
				continue
			var idx = int(face.material_idx)
			# -1 is the default slot. Anything else has to be in the palette —
			# below it as well as past the end, which a level can acquire from a
			# file written against a longer palette or by a call that was never
			# checked.
			if idx < -1 or idx >= palette_count:
				invalid_face_mats += 1
				if auto_fix:
					face.material_idx = -1
			if not FaceData.is_valid_projection(int(face.uv_projection)):
				invalid_projections += 1
				if auto_fix:
					# Box UV, the one projection that suits a face facing any way.
					face.uv_projection = FaceData.UVProjection.BOX_UV
					face.custom_uvs = PackedVector2Array()
	if invalid_face_mats > 0:
		_found(issues, "Faces reference missing materials: %d" % invalid_face_mats)
		if auto_fix:
			fixed += invalid_face_mats
			if root.brush_system:
				root.brush_system._refresh_brush_previews()
	if invalid_projections > 0:
		_found(issues, "Faces carry a UV projection that is not one: %d" % invalid_projections)
		if auto_fix:
			fixed += invalid_projections
			if root.brush_system:
				root.brush_system._refresh_brush_previews()

	_check = "entities"
	if _runs("entities"):
		_check_entities(issues)

	_check = "data"
	# Paint layers without grid
	if root.paint_layers:
		var grid_template: HFPaintGrid = root.paint_layers.base_grid
		for layer in root.paint_layers.layers:
			if layer == null:
				continue
			if layer.grid == null:
				_found(issues, "Paint layer %s has no grid" % str(layer.layer_id))
				if auto_fix:
					if grid_template == null:
						grid_template = HFPaintGrid.new()
						root.paint_layers.base_grid = grid_template
					var grid = grid_template.duplicate() as HFPaintGrid
					if grid == null:
						grid = HFPaintGrid.new()
					grid.layer_y = root.grid_plane_origin.y
					layer.grid = grid
					fixed += 1

	_check = "geometry"
	if _runs("geometry"):
		_check_convexity(brush_nodes, issues)
	_check = "overlap"
	if _runs("overlap"):
		_check_coincident_brushes(brush_nodes, issues)
		_check_brushes_that_add_nothing(brush_nodes, issues)
	_check = "data"
	_check_duplicate_brush_ids(brush_nodes, issues)
	_check = "spawn"
	if _runs("spawn"):
		_check_spawn(issues)
	_check = "notes"
	if _runs("notes"):
		_check_open_todo_notes(issues)
	# A dimension held to the player, or to a length, that the level breaks (#1699).
	_check = "dimensions"
	if _runs("dimensions"):
		_check_dimensions(issues)
	# Stairs, doorways and ramps built from brushes, against the player (#1046).
	_check = "traversal"
	if _runs("traversal"):
		for finding in HFTraversalCheck.findings(root, brush_nodes):
			finding["check"] = "traversal"
			issues.append(finding["message"])
			_findings.append(finding)
	_check = ""

	return _set_aside_accepted(issues, fixed)


## The findings accepted for this level, taken out of `issues` and `findings`
## and handed back under `accepted` (#1731).
func _set_aside_accepted(issues: Array, fixed: int) -> Dictionary:
	var sorted := HFAcceptedFindings.sort(root, _findings)
	_findings = sorted["open"]
	for finding in sorted["accepted"]:
		var at := issues.find(finding.get("message", ""))
		if at >= 0:
			issues.remove_at(at)
	return {"issues": issues, "fixed": fixed, "findings": _findings, "accepted": sorted["accepted"]}


## Whether the project runs `kind` this pass.
func _runs(kind: String) -> bool:
	return not _skipped.has(kind)


## Check again only what an edit touched (#1731): the changed brushes' own size,
## place and faces, and the overlap checks between them and the brushes near
## them, and with `entities_changed` the entity names and wiring. Level wide
## checks, the spawn, the traversal and the To Do notes wait for the next full
## pass. Returns `{open, accepted}`, as `HFAcceptedFindings.sort()` splits them,
## holding only findings that name a changed brush, or any entity finding.
func recheck(changed_ids: Array, entities_changed: bool = false) -> Dictionary:
	var issues: Array = []
	_findings = []
	rechecks += 1
	last_recheck_brushes = 0
	if not root:
		return {"open": [], "accepted": []}
	_skipped = HFValidationChecks.skipped()
	var changed: Array = []
	var everything: Array = []
	for container in [root.draft_brushes_node, root.pending_node, root.committed_node]:
		if container:
			everything.append_array(container.get_children())
	for node in everything:
		if node is DraftBrush and changed_ids.has(str(node.brush_id)):
			changed.append(node)
	var none_repaired: Array[DraftBrush] = []
	var none_deleted: Array[DraftBrush] = []
	_check = "geometry"
	if _runs("geometry"):
		for brush in changed:
			_check_brush_basics(brush, issues, false, none_repaired, none_deleted)
		_check_convexity(changed, issues)
	var near := _with_neighbours(changed, everything)
	last_recheck_brushes = near.size()
	_check = "overlap"
	if _runs("overlap") and not changed.is_empty():
		var before := _findings.size()
		_check_coincident_brushes(near, issues)
		_check_brushes_that_add_nothing(near, issues)
		var kept: Array = _findings.slice(0, before)
		for finding in _findings.slice(before):
			if changed.has(finding.get("node")) or changed.has(finding.get("other_node")):
				kept.append(finding)
		_findings = kept
	_check = "entities"
	if entities_changed and _runs("entities"):
		_check_entities(issues)
	_check = ""
	var sorted := HFAcceptedFindings.sort(root, _findings)
	_findings = []
	return sorted


## `brushes` and every brush in `among` whose box reaches one of theirs.
func _with_neighbours(brushes: Array, among: Array) -> Array:
	var out: Array = brushes.duplicate()
	if brushes.is_empty():
		return out
	var boxes: Array = []
	for brush in brushes:
		boxes.append(HFSolidMeasure.bounds(HFSolidMeasure.world_faces(brush)).grow(NEAR_DUPLICATE))
	for node in among:
		if not (node is DraftBrush) or out.has(node):
			continue
		var box := HFSolidMeasure.bounds(HFSolidMeasure.world_faces(node))
		for other in boxes:
			if other.intersects(box):
				out.append(node)
				break
	return out


## One brush's size, place and faces, as `validate()` and `recheck()` check them.
## Returns how many repairs it made; the geometry repairs and deletions it
## gathers are made by the caller, after the walk.
func _check_brush_basics(
	brush: DraftBrush,
	issues: Array,
	auto_fix: bool,
	geometry_repairs: Array[DraftBrush],
	brushes_to_delete: Array[DraftBrush]
) -> int:
	var repaired := 0
	var size = brush.size
	# Finite first, then the sign. Every comparison against NaN is false and
	# an infinite size is legitimately `> 0.0`, so the sign test below could
	# not see either — and this is the backstop: a mapper with a NaN-sized
	# brush saw a clean badge, baked, and got a mesh with a poisoned AABB
	# with nothing anywhere naming the brush responsible. The brush cannot be
	# found by eye either, because a NaN size draws nothing.
	if not size.is_finite():
		_found(issues, "Brush size is not a number: %s" % brush.name, brush)
		if auto_fix:
			brush.size = root.brush_size_default
			repaired += 1
	elif size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
		# A negative size is not a zero size. It builds the brush inside out,
		# with every face normal pointing the opposite way from the vertices
		# it holds, and saying "zero" sends the reader looking for the wrong
		# thing.
		var negative: bool = size.x < 0.0 or size.y < 0.0 or size.z < 0.0
		var label: String = "Inverted brush" if negative else "Zero-size brush"
		_found(issues, "%s: %s" % [label, brush.name], brush)
		if auto_fix:
			var next = Vector3(max(0.1, abs(size.x)), max(0.1, abs(size.y)), max(0.1, abs(size.z)))
			brush.size = next
			repaired += 1
	# The transform has the same effect and nothing checked it either. There
	# is no honest repair for a non-finite origin or basis, so this reports.
	if not brush.global_transform.is_finite():
		_found(issues, "Brush position is not a number: %s" % brush.name, brush)
	_check_brush_geometry(brush, issues, geometry_repairs, brushes_to_delete)
	return repaired


## Entity names and wiring: two entities answering to one name, a wire with a
## field missing, and a wire aimed at a name nothing answers to.
func _check_entities(issues: Array) -> void:
	# Two entities answering to the same authored name, and wiring with a field
	# missing. A level can get either from a paste, a `.map` import or a hand
	# edit, so the check at the setter is not enough on its own.
	# Brush entities are in this too. A door or a button is addressed by the same
	# authored name a point entity is, and it carries its own outputs, so leaving
	# them out meant a colliding name and a broken connection on a brush entity
	# were both invisible here.
	# Who answers to each name: a brush entity's `tie_key()`, so the brushes of one
	# tie count once (#1151), or a point entity itself.
	var seen_names: Dictionary = {}
	# Each name answered to twice, with the second node to answer to it.
	var duplicate_names: Dictionary = {}
	var broken_connections := 0
	# Wiring is held by name, and the ways a name goes stale are ordinary: the
	# target was renamed, deleted, or came back from a file without its authored
	# name. `cleanup_dangling_connections()` only runs on the delete path, so a
	# rename left a wire pointing at nothing and nothing anywhere said so (#620).
	# With no entity system there is no index to resolve against, and an empty one
	# would report every wire in the level as broken.
	var check_dangling := root.entity_system != null
	var name_index: Dictionary = root.entity_system.build_name_index() if check_dangling else {}
	# Each report, with the node whose wire it is.
	var dangling_targets: Dictionary = {}
	for child in _named_io_nodes():
		var authored := str(child.get_meta("entity_name", "")).strip_edges()
		if authored != "":
			var who := "node:%d" % child.get_instance_id()
			if HFEntitySystem.is_brush_io_target(child):
				who = "tie:" + HFBrushEntity.tie_key(child)
			if seen_names.has(authored) and seen_names[authored] != who:
				if not duplicate_names.has(authored):
					duplicate_names[authored] = child
			seen_names[authored] = who
		for connection in child.get_meta("entity_io_outputs", []):
			if not (connection is Dictionary):
				broken_connections += 1
				continue
			var fields: Dictionary = connection
			var delay = fields.get("delay", 0.0)
			if (
				str(fields.get("output_name", "")).strip_edges() == ""
				or str(fields.get("target_name", "")).strip_edges() == ""
				or str(fields.get("input_name", "")).strip_edges() == ""
				or not is_finite(float(delay))
				or float(delay) < 0.0
			):
				broken_connections += 1
				continue
			var target_name := str(fields.get("target_name", "")).strip_edges()
			if check_dangling and not name_index.has(target_name):
				var source_name := authored if authored != "" else str(child.name)
				var wire := (
					"%s.%s" % [source_name, str(fields.get("output_name", "")).strip_edges()]
				)
				var report := (
					"I/O connection points at '%s', which no entity answers to: %s"
					% [target_name, wire]
				)
				if not dangling_targets.has(report):
					dangling_targets[report] = child
	for authored in duplicate_names:
		var message := "Entity name '%s' is answered to by more than one entity" % authored
		_found(issues, message, duplicate_names[authored])
	if broken_connections > 0:
		_found(
			issues,
			(
				"I/O connections with a missing field or a delay that is not one: %d"
				% broken_connections
			)
		)
	for report in dangling_targets:
		_found(issues, report, dangling_targets[report])


## Say one thing `validate()` found: its text into `issues`, which is what the
## Console, the status board and Validate's count read, and the finding with the
## object it names into `_findings`, for the rows under the Test tab.
## `extra` is merged into the finding: a `kind` the Test tab selects together,
## and an `other_node` for a finding about a pair.
func _found(issues: Array, message: String, node: Node = null, extra: Dictionary = {}) -> void:
	if _skipped.has(_check):
		return
	issues.append(message)
	var finding := {
		"type": "validate", "severity": 1, "message": message, "node": node, "check": _check
	}
	finding.merge(extra)
	_findings.append(finding)


## One Info row for each brush with a Hidden face no brush is right in front of
## (#1719). Such a face may be one somebody sees, and the bake leaves it out.
func _hint_hidden_faces_in_the_open() -> void:
	if _skipped.has(_check):
		return
	var counts: Dictionary = {}
	var order: Array = []
	for entry in HFHiddenFaceSearch.facing_open_space(root):
		if not counts.has(entry[0]):
			order.append(entry[0])
		counts[entry[0]] = int(counts.get(entry[0], 0)) + 1
	for brush in order:
		var count := int(counts[brush])
		(
			_findings
			. append(
				{
					"type": "validate",
					"severity": 0,
					"message":
					(
						"Hidden face%s on '%s' with open space in front: %s may be seen"
						% [
							"s" if count > 1 else "",
							brush.name,
							"they" if count > 1 else "it",
						]
					),
					"node": brush,
					"check": _check,
					"kind": KIND_HIDDEN_IN_THE_OPEN,
				}
			)
		)


## Two brushes in the same place.
##
## The most common mistake in brush editing: Ctrl+D and then a drag that did not
## take. The copy is exactly on the original, so nothing looks wrong in the
## viewport, and what the level gets is doubled triangles over the whole overlap
## and z-fighting on every coincident face - which shows up in the game as
## flickering surfaces that are hard to trace back to their cause (#702).
##
## Overlap in general is not a defect: brushes are meant to intersect. The check
## is the narrow one, brushes whose position, size and shape all match within an
## epsilon, which catches the duplicate left in place without flagging ordinary
## intersecting geometry. No `auto_fix`, because deleting one of a pair is a
## guess about which one the mapper wants.
func _check_coincident_brushes(brush_nodes: Array, issues: Array) -> void:
	var groups: Dictionary = {}
	for node in brush_nodes:
		if not (node is DraftBrush):
			continue
		var brush := node as DraftBrush
		var key := _coincidence_key(brush)
		if key == "":
			continue
		if not groups.has(key):
			groups[key] = []
		groups[key].append(brush)
	for key in groups:
		var brushes: Array = groups[key]
		if brushes.size() < 2:
			continue
		var names := PackedStringArray()
		for brush in brushes:
			names.append(str(brush.name))
		# The row selects the second, the copy a Ctrl+D left in place.
		var message := "%d brushes occupy the same space: %s" % [names.size(), ", ".join(names)]
		_found(issues, message, brushes[1])


## What `_check_coincident_brushes()` groups a brush by, or "" for one it skips.
func _coincidence_key(brush: DraftBrush) -> String:
	# `auto_fix` deletes brushes on its way through, and this runs afterwards,
	# so some of what it was handed is gone or out of the tree by now - and
	# `global_position` on a node outside the tree is an error, not a position.
	if not is_instance_valid(brush) or not brush.is_inside_tree():
		return ""
	if root.is_entity_node(brush):
		return ""
	if not brush.size.is_finite() or not brush.global_position.is_finite():
		return ""
	return (
		"%s|%s|%d"
		% [
			_quantised(brush.global_position),
			_quantised(brush.size),
			int(brush.shape) if "shape" in brush else -1,
		]
	)


## Brushes that add nothing to the bake (#1708), none of which shows in the
## viewport:
##
## - a cut that cuts no solid brush, left behind when the wall it cut moved or
##   placed a little off. It removes nothing, and it still counts as a cutter, so
##   it still sends the whole bake down the CSG path;
## - a solid brush wholly inside another, which adds nothing to the outside and
##   leaves faces inside the solid;
## - two brushes the same to within a millimetre, which the exact check above
##   does not catch.
##
## The cut is measured against each solid it could reach as convex solids, as
## `hf_measure` measures them, so a turned cut whose box crosses a wall it misses
## is still found. No `auto_fix`, for the reason the exact check gives. The Test
## tab selects every brush of a kind, and offers Keep First for the near pairs.
func _check_brushes_that_add_nothing(brush_nodes: Array, issues: Array) -> void:
	var records: Array = []
	for node in brush_nodes:
		var record := _solid_record(node)
		if not record.is_empty():
			records.append(record)
	var solids := records.filter(func(r): return not r["subtract"])
	for record in records:
		if record["subtract"] and _cut_reaches(record, solids).is_empty():
			var brush: DraftBrush = record["brush"]
			_found(
				issues,
				"Cut brush cuts no solid brush: %s" % brush.name,
				brush,
				{"kind": KIND_CUTS_NOTHING}
			)
	for pair in _box_pairs(records):
		var a: Dictionary = records[pair[0]]
		var b: Dictionary = records[pair[1]]
		if a["subtract"] != b["subtract"]:
			continue
		var first: DraftBrush = a["brush"]
		var second: DraftBrush = b["brush"]
		if _same_within(a, b, NEAR_DUPLICATE):
			# The exact check has said this pair already.
			if _coincidence_key(first) != _coincidence_key(second):
				# On the later one, as the exact check does: the copy.
				_found(
					issues,
					"Brushes are the same to within 1 mm: %s, %s" % [first.name, second.name],
					second,
					{"kind": KIND_NEAR_DUPLICATE, "other_node": first}
				)
		elif not a["subtract"]:
			for inner_outer in [[a, b], [b, a]]:
				if _inside(inner_outer[0], inner_outer[1], NEAR_DUPLICATE):
					var inner: DraftBrush = inner_outer[0]["brush"]
					var outer: DraftBrush = inner_outer[1]["brush"]
					_found(
						issues,
						(
							"Solid brush is wholly inside another: %s inside %s"
							% [inner.name, outer.name]
						),
						inner,
						{"kind": KIND_INSIDE, "other_node": outer}
					)


## The cuts in the level that cut no solid brush, for the bake to name (#1708).
func cuts_that_cut_nothing() -> Array:
	var records: Array = []
	# A committed cut still cuts while the level freezes them, as the bake counts.
	var containers: Array = [root.draft_brushes_node, root.pending_node]
	if root.commit_freeze:
		containers.append(root.committed_node)
	for container in containers:
		if container:
			for node in container.get_children():
				var record := _solid_record(node, true)
				if not record.is_empty():
					records.append(record)
	var solids := records.filter(func(r): return not r["subtract"])
	var out: Array = []
	for record in records:
		if record["subtract"] and _cut_reaches(record, solids).is_empty():
			out.append(record["brush"])
	return out


## A brush as the checks above measure it: its world faces and their box, and
## whether it cuts. `{}` for one they leave alone: a brush tied to an entity
## class, which no cut reaches, one that cannot be measured, and unless
## `with_committed` one of the cuts Commit Cuts froze, which Validate leaves be.
func _solid_record(node: Variant, with_committed: bool = false) -> Dictionary:
	if not (node is DraftBrush) or not is_instance_valid(node):
		return {}
	var brush := node as DraftBrush
	if root.is_entity_node(brush) or not HFBakeSystemType.is_structural_brush(brush):
		return {}
	var committed: bool = root.committed_node and brush.get_parent() == root.committed_node
	if committed and not with_committed:
		return {}
	if not _brush_is_measurable(brush):
		return {}
	var faces := HFSolidMeasure.world_faces(brush)
	if faces.size() < 4:
		return {}
	return {
		"brush": brush,
		"faces": faces,
		"aabb": HFSolidMeasure.bounds(faces),
		"subtract": committed or brush.operation == CSGShape3D.OPERATION_SUBTRACTION,
	}


## The solids `cut` goes into, past touching.
func _cut_reaches(cut: Dictionary, solids: Array) -> Array:
	var reached: Array = []
	var box: AABB = cut["aabb"]
	for solid in solids:
		if not box.intersects((solid["aabb"] as AABB).grow(HFSolidMeasure.TOUCH)):
			continue
		if HFSolidMeasure.solid_gap(cut["faces"], solid["faces"]) < 0.0:
			reached.append(solid)
	return reached


## The pairs of `records` whose boxes meet, as index pairs, by the sweep
## `_sweep_subtract_pairs()` uses, so a big level is not every pair.
func _box_pairs(records: Array) -> Array:
	var axis := _widest_axis(records)
	var order: Array = range(records.size())
	order.sort_custom(
		func(a: int, b: int) -> bool:
			return (
				(records[a]["aabb"] as AABB).position[axis]
				< (records[b]["aabb"] as AABB).position[axis]
			)
	)
	var pairs: Array = []
	var active: Array = []
	for index: int in order:
		var aabb: AABB = (records[index]["aabb"] as AABB).grow(NEAR_DUPLICATE)
		var still_open: Array = []
		for other: int in active:
			var other_aabb: AABB = (records[other]["aabb"] as AABB).grow(NEAR_DUPLICATE)
			if other_aabb.end[axis] < aabb.position[axis]:
				continue
			still_open.append(other)
			if other_aabb.intersects(aabb):
				pairs.append([mini(other, index), maxi(other, index)])
		still_open.append(index)
		active = still_open
	pairs.sort()
	return pairs


## Whether every corner of each is within `tolerance` of a corner of the other.
func _same_within(a: Dictionary, b: Dictionary, tolerance: float) -> bool:
	var box_a: AABB = a["aabb"]
	var box_b: AABB = b["aabb"]
	if not _near(box_a.position, box_b.position, tolerance):
		return false
	if not _near(box_a.end, box_b.end, tolerance):
		return false
	var points_a := _corners(a["faces"])
	var points_b := _corners(b["faces"])
	return _all_near(points_a, points_b, tolerance) and _all_near(points_b, points_a, tolerance)


## Whether every corner of `inner` is inside `outer`, or within `tolerance` out.
func _inside(inner: Dictionary, outer: Dictionary, tolerance: float) -> bool:
	if not (outer["aabb"] as AABB).grow(tolerance).encloses(inner["aabb"]):
		return false
	for point in _corners(inner["faces"]):
		if HFSolidMeasure.point_gap(point, outer["faces"]) > tolerance:
			return false
	return true


static func _near(a: Vector3, b: Vector3, tolerance: float) -> bool:
	return (
		absf(a.x - b.x) <= tolerance
		and absf(a.y - b.y) <= tolerance
		and absf(a.z - b.z) <= tolerance
	)


static func _corners(faces: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for face in faces:
		out.append_array(HFSolidMeasure.ring(face))
	return out


static func _all_near(
	points: PackedVector3Array, others: PackedVector3Array, tolerance: float
) -> bool:
	for point in points:
		var found := false
		for other in others:
			if point.distance_to(other) <= tolerance:
				found = true
				break
		if not found:
			return false
	return true


## Two brushes in one level answering to the same id.
##
## `brush_id` is the address for everything that refers to a brush without
## holding a reference: visgroup and group membership, the hollow and array
## records, `nudge_brushes_by_id`, `tie_brushes_to_entity`, the Console. The
## brush cache is keyed by it, so the second brush to register overwrites the
## first and one of the two becomes unreachable -- every later lookup answers
## with whichever won, and the other cannot be addressed at all (#696).
##
## Within one level, because that is the scope an id is unique in. Two instances
## of the same saved level piece carry the same ids on purpose and each root
## resolves its own children, so walking a whole scene here would report every
## brush in both copies for an arrangement that works.
##
## The ways in are ordinary: a hand-edited `.hflevel`, a `.tscn` where a
## `DraftBrush` was copied with Godot's own node duplication rather than Ctrl+D,
## or a state record naming the same id twice. `restore_state()` already refuses
## the last of those; nothing said anything about the other two.
##
## No `auto_fix`. Re-minting one of the pair silently re-points whichever
## registry entries happened to mean it, and which one the mapper wants is not
## knowable from here.
func _check_duplicate_brush_ids(brush_nodes: Array, issues: Array) -> void:
	var seen: Dictionary = {}
	# Each id answered to twice, with the second brush to answer to it.
	var duplicated: Dictionary = {}
	for node in brush_nodes:
		if not (node is DraftBrush):
			continue
		# An absent id is the absence of a value, not a value two brushes share.
		var brush_id := str((node as DraftBrush).brush_id).strip_edges()
		if brush_id == "":
			continue
		if seen.has(brush_id):
			if not duplicated.has(brush_id):
				duplicated[brush_id] = node
			continue
		seen[brush_id] = true
	for brush_id in duplicated:
		var message := (
			"Brush id '%s' is answered to by more than one brush in this level" % brush_id
		)
		_found(issues, message, duplicated[brush_id])


## A position rounded to the coincidence epsilon, as a string that can key a
## dictionary. A tenth of a grid unit is far below anything a mapper places on
## purpose and far above float noise from a round trip.
func _quantised(value: Vector3) -> String:
	return "%d,%d,%d" % [round(value.x * 1000.0), round(value.y * 1000.0), round(value.z * 1000.0)]


## Every brush is a convex solid, or it is not a brush.
##
## `HFVertexSystem.check_solid()` is the plugin's own test and already gates the
## vertex tools, and Validate never consulted it, so a non-convex brush was
## clean here while the vertex tools refused to open on it (#666). Merge could
## make one out of two brushes that do not touch, and a `.map` import or a hand
## edited `.tscn` can produce one too -- this catches whichever made it, and
## anything a future operation produces that nobody has written yet.
##
## No `auto_fix`: there is no honest repair. A non-convex brush is two solids or
## a bent one, and guessing which the mapper meant would throw geometry away.
func _check_convexity(brush_nodes: Array, issues: Array) -> void:
	if not root.vertex_system:
		return
	for node in brush_nodes:
		if not (node is DraftBrush) or not is_instance_valid(node):
			continue
		var brush := node as DraftBrush
		if not _brush_is_measurable(brush):
			continue
		# Turned the right way it is convex, and the faces pointing into it are
		# the finding: `check_solid()` reads each face's plane by its winding.
		if (
			not HFSolidMeasure.inward_faces(brush.faces).is_empty()
			and HFSolidMeasure.is_convex(brush.faces)
		):
			continue
		var problem := str(root.vertex_system.check_solid(brush))
		if problem != "":
			_found(issues, NOT_CONVEX % [brush.name, problem], brush)


const INWARD_FACES := "Brush has %d %s pointing into it, which draw as holes and bake inside out: %s"


## Turn back each face of a convex brush that points into it, as a load turns
## the faces of an old save (`DraftBrush._migrate_face_winding()`): the corners
## reversed, and the texture's corners with them. A displaced face is left, since
## its sculpt would turn inside out with it. Returns how many faces it turned.
func reverse_inward_faces(brush: DraftBrush) -> int:
	if not brush or not HFSolidMeasure.is_convex(brush.faces):
		return 0
	var turned := 0
	for index in HFSolidMeasure.inward_faces(brush.faces):
		var face: FaceData = brush.faces[index]
		if face == null or face.displacement != null:
			continue
		face.local_verts.reverse()
		if face.custom_uvs.size() == face.local_verts.size():
			face.custom_uvs.reverse()
		face.ensure_geometry()
		turned += 1
	if turned > 0:
		brush.refresh_editor_look()
	return turned


## What a bent brush costs, said with the finding: a torus is one by design, and
## a warning that only says so leaves the mapper nothing to weigh (#1035).
const NOT_CONVEX := (
	"Brush %s is not a convex solid: %s. The vertex tools will not open on it, and"
	+ " where collision is built per brush (detail, brush entities, visgroups) it"
	+ " collides as its hull"
)


## Whether asking this brush about its shape will get an answer rather than an
## error.
##
## Everything refused here is already reported by the pass above: a non-finite
## size or transform, a vertex that is not a number. `check_solid()` builds plane
## normals out of those and normalising a NaN vector is an engine error per face,
## so running it anyway would bury the real finding in console noise. A brush the
## auto-fix has just deleted is gone from the tree while still in the list this
## walk was given, and asking a freed node for its global transform is another.
func _brush_is_measurable(brush: DraftBrush) -> bool:
	if not brush.is_inside_tree():
		return false
	if not brush.size.is_finite() or not brush.global_transform.is_finite():
		return false
	for face in brush.faces:
		if face == null:
			continue
		for v in face.local_verts:
			if not v.is_finite():
				return false
	return true


## Where the level starts is part of whether the level works.
##
## `hf_validation_system.gd` contained the word "spawn" zero times, so the one
## surface a mapper presses before pressing Test Level was the one that never
## looked at where testing starts (#657). Create Starter, build a room, Test
## Level is the shortest path through the tool, and it dropped the player through
## the ceiling with a Healthy badge the whole way.
##
## Deliberately geometric rather than `validate_spawn()`, which is the richer
## check and the wrong one here: it raycasts, so it needs collision, and the
## collision comes from the bake. `dock_manage_handler.gd` bakes before it calls
## it for exactly that reason. Validate runs on an unbaked level, which is most
## levels most of the time, so asking the physics space would report "no floor
## below" for every one of them -- a check that cries wolf is worse than the
## silence it replaced. The level's own AABB needs nothing but the brushes, and
## it catches the case the issue is about: a spawn above the ceiling of anything
## that was built.
##
## Reported rather than fixed. Moving where the player starts is the mapper's to
## agree to, and `auto_fix_spawn()` is on the button that asks them.
func _check_spawn(issues: Array) -> void:
	if not root.spawn_system or not root.brush_system:
		return
	# An empty scene has nothing to say about where a level starts.
	if root.brush_system.get_live_brush_count() == 0:
		return
	# A level with no spawn yet is a level being built, not a broken one --
	# `create_default_spawn()` makes one and the playtest export makes one -- so
	# saying so on every press would be the crying wolf this check is trying to
	# avoid. Only a spawn that exists and is somewhere unusable is reported.
	var spawn = root.spawn_system.get_active_spawn()
	if spawn == null or not is_instance_valid(spawn):
		return
	if not root.has_method("_compute_level_aabb"):
		return
	var bounds: AABB = root._compute_level_aabb()
	if bounds.size == Vector3.ZERO:
		return
	# A spawn stands on what is built, so one standing on the level's top is in
	# it: the ground of an outdoor level is its top. `create_default_spawn()` puts
	# a spawn there, at the height `validate_spawn()` asks for, with its slack.
	var standing: float = (
		HFSpawnSystemType.FEET_OFFSET
		+ root.spawn_system._get_entity_float(spawn, "height_offset", 1.0)
		+ 0.3
	)
	bounds.size.y += standing
	if bounds.has_point(spawn.global_position):
		return
	_found(
		issues,
		(
			"Player spawn is outside the level: it is at %s, and the level spans %s to %s"
			% [spawn.global_position, bounds.position, bounds.end]
		),
		spawn
	)


## Each dimension whose check fails, named, with its length and what it needs. One
## held to a check with an end come loose is named as that, with no length: the
## length it reads is not a measurement (#2004).
func _check_dimensions(issues: Array) -> void:
	for dimension in HFDimensions.dimensions(root):
		var measured := HFDimensions.measure(root, dimension)
		if bool(measured["detached"]) and str(measured["check"]) != "None":
			_found(issues, HFDimensions.detached_text(dimension), dimension)
		elif not bool(measured["passes"]):
			_found(issues, HFDimensions.failure_text(dimension, measured), dimension)


## Each To Do note not marked Done, when the level asks for it (#1818), so a ship
## check names what is left to do. Its row selects the note. Plain and Playtest
## notes never warn, and nothing is said with the setting off.
func _check_open_todo_notes(issues: Array) -> void:
	if not bool(root.get("validate_warns_open_todos")):
		return
	for note in HFNotes.notes(root):
		if note["kind"] == "To Do" and not note["done"]:
			_found(issues, "Open To Do note: %s" % note["title"], note["node"])


# ---------------------------------------------------------------------------
# Bake-specific issue detection
# ---------------------------------------------------------------------------


## Scan for issues that affect bake quality. Returns Array of Dictionaries:
## {type: String, severity: int (0=info,1=warn,2=error), message: String, node: Node3D or null}
func check_bake_issues() -> Array:
	var issues: Array = []
	if not root:
		return issues
	var brush_nodes: Array = []
	if root.draft_brushes_node:
		brush_nodes.append_array(root.draft_brushes_node.get_children())
	if root.committed_node:
		brush_nodes.append_array(root.committed_node.get_children())

	# One pass builds every world AABB the subtraction checks need, and one sweep
	# answers both of them. Testing each subtraction against the whole brush list
	# and then every subtraction against every other made the two checks cost
	# roughly brushes times subtractions plus subtractions squared, on a level
	# where most of those pairs are nowhere near each other.
	pair_tests = 0
	connector_scans = 0
	_connector_memo = null
	var records := _build_brush_records(brush_nodes)
	var overlaps := _sweep_subtract_pairs(records)

	for node in brush_nodes:
		if not (node is DraftBrush):
			continue
		var brush := node as DraftBrush
		if root.is_entity_node(brush):
			continue
		_check_degenerate_brush(brush, issues)
		_check_floating_subtract(brush, overlaps["grounded"], issues)
		_check_non_manifold(brush, issues)
		_check_non_planar_faces(brush, issues)
		_check_visgroup_cast_shadows(brush, issues)

	_report_overlapping_subtracts(records, overlaps["subtract_pairs"], issues)
	_check_micro_gaps(brush_nodes, issues)
	_check_stairs_are_climbable(issues)
	_check_ramps_are_walkable(issues)
	issues.append_array(check_occlusion_coverage())
	return issues


## The stairs this level will bake, measured against the height the navmesh
## agent will climb.
##
## The auto-connector's step defaults to the same 0.25 as Godot's default max
## climb, so a generated staircase sits exactly on the limit and a mapper raising
## the step for a chunkier stair puts it out of reach of everything in the game
## (#701).
##
## Which boundaries become stairs is not a setting on its own. Ramp is the
## default connector mode and builds no stairs at all, Auto picks per boundary
## against the stair threshold, and a connector the mapper committed by hand
## carries its own type and its own step whether or not auto-connectors are on.
## Reading `bake_connector_stair_height` alone answered none of that: it warned
## about generated stairs in Ramp mode, where the bake reads neither, and stayed
## quiet about a committed staircase, which bakes regardless (#802). So this
## works the boundaries out the same way the ramp half does, off the connectors
## the bake will actually build.
##
## Reports once with a count rather than once per staircase, for the same reason
## as the ramp half: a terrace edge is one boundary per cell along its length,
## and a connector has no node to click through to until the bake makes one.
func _check_stairs_are_climbable(issues: Array) -> void:
	if not root.bake_navmesh:
		return
	var climb: float = root.bake_navmesh_agent_max_climb
	# `LevelRoot` bounds it at 0.01, so zero here is a field written past the
	# setter rather than a mapper who set it to nothing, and there is no climb to
	# measure against.
	if climb <= 0.0:
		return
	# Held as a Variant and tested with `is_instance_valid()`, because a freed
	# node is neither null nor safe to call `get()` on, and assigning one to a
	# typed `Object` is itself the error.
	var layers: Variant = root.get("paint_layers")
	if not is_instance_valid(layers):
		return
	var layer_list: Variant = layers.get("layers")
	if not (layer_list is Array) or (layer_list as Array).size() < 2:
		return

	var tallest := 0.0
	var tallest_cell := Vector2i.ZERO
	var count := 0
	for definition in _pending_connector_definitions(layers):
		if definition.connector_type != HFConnectorTool.ConnectorType.STAIRS:
			continue
		if not _connector_builds(definition, layer_list as Array):
			continue
		var step: float = definition.stair_step_height
		# A step that is not a number is unmeasurable, same as one the bake will
		# not build. Every comparison against NaN is false, so an unguarded one
		# would fall through the limit test and report itself as a nan rise.
		if not is_finite(step) or step <= 0.0:
			continue
		# Equal is deliberately fine, and it is the value every fresh project
		# has. Tightening this to `<` warns on the Bake Check of a stock level.
		# `tests/test_bake_issues_stair_climb.gd` holds that boundary.
		if step <= climb:
			continue
		count += 1
		if step > tallest:
			tallest = step
			tallest_cell = definition.from_cell
	if count == 0:
		return
	# Same shape as every other entry on this report: `on_bake_check_issues()`
	# reads `severity` off each one to count errors against warnings.
	issues.append(
		{
			"type": "stairs_above_agent_climb",
			"severity": 1,
			"message":
			(
				(
					"%d connector staircase%s will bake a step taller than the navmesh "
					+ "agent can climb: the tallest rises %.2f per step from cell "
					+ "(%d, %d) and the agent climbs %.2f"
				)
				% [count, "" if count == 1 else "s", tallest, tallest_cell.x, tallest_cell.y, climb]
			),
			"node": root
		}
	)


## The ramps this level will bake, measured against the slope the navmesh agent
## will accept.
##
## The stairs half of this pair compares two settings, because a step's rise is
## a setting. A ramp's slope is not: it is the height difference between two
## painted cells over one cell of run, so the only way to know whether an agent
## can walk it is to work out the connectors the bake would build and measure
## them (#798). Ramp is the default connector mode and Auto is a ramp below the
## stair threshold, so this is the half most levels actually hit, and it was the
## half with no check at all.
##
## Reports once with a count rather than once per ramp. A painted terrace a
## metre above its neighbour is one boundary per cell along its whole edge, and
## a connector has no node to click through to until the bake makes one.
func _check_ramps_are_walkable(issues: Array) -> void:
	if not root.bake_navmesh:
		return
	# Slope is the angle from horizontal in degrees, so 90 accepts a wall and
	# there is nothing left to warn about.
	var max_slope: float = root.bake_navmesh_agent_max_slope
	if max_slope <= 0.0 or max_slope >= 90.0:
		return
	# Held as a Variant and tested with `is_instance_valid()`, because a freed
	# node is neither null nor safe to call `get()` on, and assigning one to a
	# typed `Object` is itself the error.
	var layers: Variant = root.get("paint_layers")
	if not is_instance_valid(layers):
		return
	var layer_list: Variant = layers.get("layers")
	if not (layer_list is Array) or (layer_list as Array).size() < 2:
		return

	var steepest := -1.0
	var steepest_cell := Vector2i.ZERO
	var count := 0
	for definition in _pending_connector_definitions(layers):
		if definition.connector_type != HFConnectorTool.ConnectorType.RAMP:
			continue
		var slope := _ramp_slope_degrees(definition, layer_list as Array)
		if slope <= max_slope:
			continue
		count += 1
		if slope > steepest:
			steepest = slope
			steepest_cell = definition.from_cell
	if count == 0:
		return
	issues.append(
		{
			"type": "ramp_above_agent_slope",
			"severity": 1,
			"message":
			(
				(
					"%d connector ramp%s will bake steeper than the navmesh agent can "
					+ "walk: the steepest rises at %.1f degrees from cell (%d, %d) and "
					+ "the agent accepts %.1f"
				)
				% [
					count,
					"" if count == 1 else "s",
					steepest,
					steepest_cell.x,
					steepest_cell.y,
					max_slope
				]
			),
			"node": root
		}
	)


## The connector definitions a bake would build from the level as it stands: the
## ones the mapper committed with the connector tool, plus the detected ones
## when auto-connectors are on.
##
## Same two sources in the same order as `HFBakeSystem._append_auto_connectors()`,
## deduplicated on the same boundary key, so this measures what will actually be
## built rather than a second opinion about it.
func _pending_connector_definitions(layers: Object) -> Array:
	# Both connector checks run inside one `check_bake_issues()` pass and want
	# the same list. `detect_boundaries()` walks every cell of every chunk of
	# every layer, so building it twice is the whole cost of the check on a
	# painted level. Same reasoning as the one subtract sweep that answers both
	# subtraction checks above.
	if _connector_memo is Array:
		return _connector_memo
	connector_scans += 1
	_connector_memo = root.bake_system.connector_definitions(layers)
	return _connector_memo


## Whether `definition` points at two painted cells in layers that exist.
##
## The test `HFConnectorTool.generate_connector()` runs before it returns a mesh,
## so a definition that fails this bakes nothing and neither half of this pair
## has anything to measure. A connector the mapper committed and then painted
## over is how it happens: the definition outlives the cells it was drawn
## between.
func _connector_builds(definition: Object, layer_list: Array) -> bool:
	var from_index: int = definition.from_layer_index
	var to_index: int = definition.to_layer_index
	if from_index < 0 or from_index >= layer_list.size():
		return false
	if to_index < 0 or to_index >= layer_list.size():
		return false
	var from_layer: Object = layer_list[from_index]
	var to_layer: Object = layer_list[to_index]
	if from_layer == null or from_layer.grid == null:
		return false
	if to_layer == null or to_layer.grid == null:
		return false
	# Its cells are by index, so on two cell sizes they name no place (#2011).
	if not is_equal_approx(from_layer.grid.cell_size, to_layer.grid.cell_size):
		return false
	if not from_layer.get_cell(definition.from_cell):
		return false
	if not to_layer.get_cell(definition.to_cell):
		return false
	return true


## The slope in degrees of the ramp `definition` would build, or -1.0 when it
## does not point at two painted cells and so builds nothing.
##
## Mirrors `HFConnectorTool.generate_connector()`: the rise is the difference
## between the two cells' world heights and the run is the distance between the
## cells in the from-layer's own cell size. Auto-detected boundaries are always
## one cell apart; a committed connector can span more.
func _ramp_slope_degrees(definition: Object, layer_list: Array) -> float:
	if not _connector_builds(definition, layer_list):
		return -1.0
	var from_layer: Object = layer_list[definition.from_layer_index]
	var to_layer: Object = layer_list[definition.to_layer_index]
	var run: float = (
		Vector2(definition.to_cell - definition.from_cell).length() * from_layer.grid.cell_size
	)
	if run <= 0.0:
		return -1.0
	var from_y: float = from_layer.grid.layer_y + from_layer.get_height_at(definition.from_cell)
	var to_y: float = to_layer.grid.layer_y + to_layer.get_height_at(definition.to_cell)
	var slope := rad_to_deg(atan(absf(to_y - from_y) / run))
	# A NaN height makes a NaN slope, and every comparison against it is false,
	# so it would be counted as too steep and then reported as a negative angle.
	# Unmeasurable, same as a definition pointing at nothing.
	if not is_finite(slope):
		return -1.0
	return slope


## A brush whose visgroups disagree about how it casts shadows (#1444). The first
## of them in the visgroup list decides, which is a rule and not something the
## mapper chose, so the brush is named. A brush that chose for itself is not:
## its own setting beats every visgroup's. A cut makes no mesh to cast one.
func _check_visgroup_cast_shadows(brush: DraftBrush, issues: Array) -> void:
	if brush.operation == CSGShape3D.OPERATION_SUBTRACTION:
		return
	if HFBakeSplit.brush_cast_shadow(brush) != HFBakeSplit.LEVEL_DEFAULT:
		return
	var visgroups: Variant = root.get("visgroup_system")
	if visgroups == null or not visgroups.has_method("cast_shadow_overrides_of"):
		return
	var overrides: Array = visgroups.cast_shadow_overrides_of(brush)
	if overrides.size() < 2:
		return
	var said := PackedStringArray()
	var differ := false
	for entry: Array in overrides:
		said.append("'%s' says %s" % [entry[0], HFBakeSplit.cast_shadow_name(int(entry[1]))])
		differ = differ or int(entry[1]) != int(overrides[0][1])
	if not differ:
		return
	var decides := "'%s'" % overrides[0][0]
	var bakes := HFBakeSplit.cast_shadow_name(int(overrides[0][1]))
	var message := (
		"Brush '%s' is in visgroups that disagree on Cast Shadows (%s). It bakes %s, from %s, "
		% [brush.name, ", ".join(said), bakes, decides]
	)
	message += "the first of them in the visgroup list"
	issues.append(
		{"type": "visgroup_cast_shadow_conflict", "severity": 1, "message": message, "node": brush}
	)


func _check_degenerate_brush(brush: DraftBrush, issues: Array) -> void:
	var size = brush.size
	var min_dim := minf(size.x, minf(size.y, size.z))
	var thin := min_dim < HFConvexClip.NEAR_ZERO_THICKNESS
	if thin and (size.x > 0.0 or size.y > 0.0 or size.z > 0.0):
		issues.append(
			{
				"type": "degenerate",
				"severity": 2,
				"message": "Near-zero thickness brush '%s' (%.3f)" % [brush.name, min_dim],
				"node": brush
			}
		)
	var max_dim := maxf(size.x, maxf(size.y, size.z))
	if max_dim > 2048.0:
		issues.append(
			{
				"type": "oversized",
				"severity": 1,
				"message": "Very large brush '%s' (%.0f units)" % [brush.name, max_dim],
				"node": brush
			}
		)


## Every brush the subtraction checks care about, with its world AABB measured
## once, in the order the level lists them.
##
## The box is the brush's own bounds in the level, turn included, as the bake
## reads them. It was the brush's size placed at its origin, so a doorway cut into
## a wall turned a quarter turn overlapped nothing, and two cuts turned with it
## were read across the wall rather than along it (#1967).
func _build_brush_records(brush_nodes: Array) -> Array:
	var records: Array = []
	for node in brush_nodes:
		if not (node is DraftBrush):
			continue
		var brush := node as DraftBrush
		if root.is_entity_node(brush):
			continue
		(
			records
			. append(
				{
					"brush": brush,
					"aabb": HFBakeSystemType.brush_world_aabb(brush, brush.global_transform),
					"subtract": brush.operation == CSGShape3D.OPERATION_SUBTRACTION,
					# A brush tied to an entity class bakes from its own faces and
					# no cutter reaches it, so it cannot be what a cut lands on (#942).
					"ground": HFBakeSystemType.is_structural_brush(brush),
				}
			)
		)
	return records


## Sort along one axis and walk it, keeping only the boxes still open at the
## current position. Two boxes that intersect must overlap on that axis, so they
## are both in the active list at the same moment and every intersecting pair is
## seen exactly once. Boxes that are far apart never meet.
##
## The axis is whichever one the level is widest on, because that is the one that
## separates the most brushes. A level is usually a floor plan, so it is normally
## X or Z and almost never Y.
##
## Returns the subtractions that landed on an additive world brush, keyed by instance
## id, and the subtraction pairs that overlap each other, as index pairs into
## `records`. Boxes that meet are only a first pass: `_records_meet()` says
## whether the brushes do, and is asked only for a pair one of the two answers
## still needs.
func _sweep_subtract_pairs(records: Array) -> Dictionary:
	var grounded: Dictionary = {}
	var subtract_pairs: Array = []
	var axis := _widest_axis(records)
	var order: Array = []
	for i in range(records.size()):
		order.append(i)
	order.sort_custom(
		func(a: int, b: int) -> bool:
			return (
				(records[a]["aabb"] as AABB).position[axis]
				< (records[b]["aabb"] as AABB).position[axis]
			)
	)
	var active: Array = []
	for index: int in order:
		var record: Dictionary = records[index]
		var aabb: AABB = record["aabb"]
		var still_open: Array = []
		for other_index: int in active:
			var other: Dictionary = records[other_index]
			var other_aabb: AABB = other["aabb"]
			if other_aabb.end[axis] < aabb.position[axis]:
				continue
			still_open.append(other_index)
			pair_tests += 1
			if not other_aabb.intersects(aabb):
				continue
			if record["subtract"] and other["subtract"]:
				if _records_meet(other, record):
					subtract_pairs.append([other_index, index])
			elif record["subtract"] or other["subtract"]:
				var cut: Dictionary = record if record["subtract"] else other
				var solid: Dictionary = other if record["subtract"] else record
				var cut_id := (cut["brush"] as Node).get_instance_id()
				if solid["ground"] and not grounded.has(cut_id) and _records_meet(cut, solid):
					grounded[cut_id] = true
		still_open.append(index)
		active = still_open
	return {"grounded": grounded, "subtract_pairs": subtract_pairs}


## Whether two brushes whose boxes meet go into each other. A brush square to the
## world fills its box, so for two of them the boxes meeting says so, as it always
## has. A turned one's box holds more than the brush, so then their faces decide,
## as convex solids, the way `_cut_reaches()` measures a cut (#1967). A brush whose
## faces cannot be measured is taken at its box.
func _records_meet(a: Dictionary, b: Dictionary) -> bool:
	var a_faces := _record_faces(a)
	var b_faces := _record_faces(b)
	if a_faces.size() < 4 or b_faces.size() < 4:
		return true
	if a["square"] and b["square"]:
		return true
	# A doorway's or a window's middle is inside the wall it cuts, which is quick
	# to see and says the rest.
	if HFSolidMeasure.point_gap(HFSolidMeasure.vertex_centre(a_faces), b_faces) < 0.0:
		return true
	return HFSolidMeasure.solid_gap(a_faces, b_faces) < 0.0


## A record's brush as world faces, read the first time a pair asks for them, and
## whether it is square to the world: every face facing along an axis, so that
## the brush is its box.
func _record_faces(record: Dictionary) -> Array:
	if not record.has("faces"):
		var brush: DraftBrush = record["brush"]
		var faces: Array = HFSolidMeasure.world_faces(brush) if _brush_is_measurable(brush) else []
		var square := true
		for face in faces:
			var normal := HFSolidMeasure.face_normal(face).abs()
			if maxf(normal.x, maxf(normal.y, normal.z)) < 0.9999:
				square = false
				break
		record["faces"] = faces
		record["square"] = square
	return record["faces"]


## The axis the brushes are most spread out along, as an index into Vector3.
static func _widest_axis(records: Array) -> int:
	if records.is_empty():
		return Vector3.AXIS_X
	var low: Vector3 = (records[0]["aabb"] as AABB).position
	var high: Vector3 = low
	for record in records:
		var aabb: AABB = record["aabb"]
		low = Vector3(
			minf(low.x, aabb.position.x), minf(low.y, aabb.position.y), minf(low.z, aabb.position.z)
		)
		high = Vector3(
			maxf(high.x, aabb.position.x),
			maxf(high.y, aabb.position.y),
			maxf(high.z, aabb.position.z)
		)
	var spread: Vector3 = high - low
	if spread.x >= spread.y and spread.x >= spread.z:
		return Vector3.AXIS_X
	if spread.z >= spread.y:
		return Vector3.AXIS_Z
	return Vector3.AXIS_Y


func _check_floating_subtract(brush: DraftBrush, grounded: Dictionary, issues: Array) -> void:
	if brush.operation != CSGShape3D.OPERATION_SUBTRACTION:
		return
	if grounded.has(brush.get_instance_id()):
		return
	issues.append(
		{
			"type": "floating_subtract",
			"severity": 1,
			"message": "Cut brush '%s' does not overlap any solid brush" % brush.name,
			"node": brush
		}
	)


## Report the overlapping pairs in level order, so the list reads the same as it
## did when both loops walked the brushes from the top.
func _report_overlapping_subtracts(records: Array, pairs: Array, issues: Array) -> void:
	var ordered: Array = []
	for pair in pairs:
		var first: int = mini(pair[0], pair[1])
		var second: int = maxi(pair[0], pair[1])
		ordered.append([first, second])
	ordered.sort_custom(
		func(a: Array, b: Array) -> bool: return a[0] < b[0] if a[0] != b[0] else a[1] < b[1]
	)
	for pair in ordered:
		var a: DraftBrush = records[pair[0]]["brush"]
		var b: DraftBrush = records[pair[1]]["brush"]
		issues.append(
			{
				"type": "overlapping_subtract",
				"severity": 1,
				"message": "Overlapping cut brushes: '%s' and '%s'" % [a.name, b.name],
				"node": a
			}
		)


## Check for non-manifold and open-edge geometry by analyzing the edge adjacency
## of a brush's faces. An edge shared by exactly 2 faces is manifold; 1 = open edge;
## 3+ = non-manifold edge.
func _check_non_manifold(brush: DraftBrush, issues: Array) -> void:
	if brush.faces.is_empty():
		return
	# Build edge→face count map. Edge key = sorted pair of rounded vertex positions.
	var edge_counts: Dictionary = {}  # String -> int
	for face_idx in range(brush.faces.size()):
		var face = brush.faces[face_idx]
		if not face or face.local_verts.size() < 3:
			continue
		var verts: PackedVector3Array = face.local_verts
		for i in range(verts.size()):
			var a: Vector3 = verts[i]
			var b: Vector3 = verts[(i + 1) % verts.size()]
			var key: Array = _edge_key(a, b)
			edge_counts[key] = edge_counts.get(key, 0) + 1
	var open_count := 0
	var non_manifold_count := 0
	for key: Array in edge_counts:
		var count: int = edge_counts[key]
		if count == 1:
			open_count += 1
		elif count > 2:
			non_manifold_count += 1
	if open_count > 0:
		issues.append(
			{
				"type": "open_edge",
				"severity": 1,
				"message":
				(
					"Brush '%s' has %d open edge(s) — geometry is not watertight"
					% [brush.name, open_count]
				),
				"node": brush
			}
		)
	if non_manifold_count > 0:
		issues.append(
			{
				"type": "non_manifold",
				"severity": 2,
				"message":
				(
					"Brush '%s' has %d non-manifold edge(s) — may cause bake artifacts"
					% [brush.name, non_manifold_count]
				),
				"node": brush
			}
		)


## Create a canonical edge key from two vertices (order-independent, rounded to 0.001).
## This tolerance is intentionally fixed — it must NOT vary with weld_tolerance,
## because non-manifold/open-edge detection depends on stable topology hashing.
## An edge as the pair of grid cells its ends fall in, smaller end first so
## (A,B) and (B,A) are one edge.
##
## Deliberately a pair of Vector3i rather than a formatted string. This runs for
## every edge of every face of every brush, and building the string cost more
## than everything it was a key for.
func _edge_key(a: Vector3, b: Vector3) -> Array:
	var ai := HFVertexWeld.cell(a, 0.001)
	var bi := HFVertexWeld.cell(b, 0.001)
	if (
		ai.x < bi.x
		or (ai.x == bi.x and ai.y < bi.y)
		or (ai.x == bi.x and ai.y == bi.y and ai.z < bi.z)
	):
		return [ai, bi]
	return [bi, ai]


## The geometry checks validate() had none of.
##
## Fixing the setters that create these states does nothing for a `.hflevel`
## saved last week, a `.map` imported from another editor, or a file that was
## hand-edited. The validator is what covers that ground, and it checked brush
## size, face selection indices, material slots, UV projections, entity names,
## I/O fields and paint layer grids — and nothing about the faces themselves,
## while owning two geometry repairs that nothing called.
func _check_brush_geometry(
	brush: DraftBrush, issues: Array, repairs: Array[DraftBrush], to_delete: Array[DraftBrush]
) -> void:
	if brush.faces.is_empty():
		# A live, selectable, saved brush with no geometry. It exports as a solid
		# with no planes, which is malformed in both `.map` formats, and the
		# mapper cannot find it to delete it because it draws nothing. There is
		# nothing to repair, so the fix is to remove it.
		_found(issues, "Brush has no faces: %s" % brush.name, brush)
		to_delete.append(brush)
		return
	var non_finite := 0
	var worst_drift := 0.0
	var coincident := false
	for face in brush.faces:
		if face == null:
			continue
		var verts: PackedVector3Array = face.local_verts
		for v in verts:
			if not v.is_finite():
				non_finite += 1
		if verts.size() < 3:
			continue
		for i in verts.size():
			for j in range(i + 1, verts.size()):
				# Near but not identical, which is what weld_brush_vertices()
				# repairs: it snaps a group to its average, so afterwards the pair
				# is exactly coincident rather than gone. A pair that is already
				# exactly coincident is a degenerate face, not a weld job.
				var gap := verts[i].distance_to(verts[j])
				if gap > 0.0 and gap <= weld_tolerance:
					coincident = true
		worst_drift = maxf(worst_drift, _face_plane_drift(face))
	if non_finite > 0:
		# No honest repair: there is no nearest position to a NaN, and the value
		# poisons the brush AABB and normal and propagates through any later clip
		# or carve. Report it and name the brush.
		var message := "Brush has %d vertices that are not numbers: %s" % [non_finite, brush.name]
		_found(issues, message, brush)
	if worst_drift > planarity_tolerance:
		var message := "Brush face is not a plane (%.4f unit drift): %s" % [worst_drift, brush.name]
		_found(issues, message, brush)
		repairs.append(brush)
	elif coincident:
		_found(issues, "Brush has vertices a weld apart: %s" % brush.name, brush)
		repairs.append(brush)
	if non_finite > 0:
		return
	# A face wound the wrong way points into its brush: culled seen from outside,
	# and baked facing into the solid (#1869). A negative size above is one cause
	# of it, and many fixed bugs made others. Only a convex brush can be read by
	# which way its faces point from its middle: a torus's inner faces point at
	# its middle by design, and it is reported as not convex below.
	if not HFSolidMeasure.is_convex(brush.faces):
		return
	var inward := HFSolidMeasure.inward_faces(brush.faces).size()
	if inward > 0:
		var message := INWARD_FACES % [inward, "face" if inward == 1 else "faces", brush.name]
		_found(issues, message, brush)
		if not repairs.has(brush):
			repairs.append(brush)


## How far the furthest vertex of a face sits off the plane through its first
## three non-collinear vertices, or 0.0 when the face has no measurable plane.
func _face_plane_drift(face) -> float:
	var verts: PackedVector3Array = face.local_verts
	if verts.size() < 4:
		return 0.0  # triangles are always planar
	var anchor: Vector3 = verts[0]
	if not anchor.is_finite():
		return 0.0
	var normal := Vector3.ZERO
	for i in range(1, verts.size() - 1):
		if not verts[i].is_finite() or not verts[i + 1].is_finite():
			continue
		# Both edges have to be real edges. A pair of near-coincident vertices
		# normalises to a direction that has nothing to do with the face, and the
		# plane built from it reports the rest of the face as drift — so a brush
		# with two vertices welded together came back as "not a plane" instead.
		if (
			(verts[i] - anchor).length() <= weld_tolerance
			or (verts[i + 1] - anchor).length() <= weld_tolerance
		):
			continue
		var candidate: Vector3 = (verts[i + 1] - anchor).normalized().cross(
			(verts[i] - anchor).normalized()
		)
		if candidate.length() > 0.0001:
			normal = candidate.normalized()
			break
	if normal.length_squared() < 0.0001 or not normal.is_finite():
		return 0.0
	var drift := 0.0
	for v in verts:
		if not v.is_finite():
			continue
		drift = maxf(drift, absf(normal.dot(v - anchor)))
	return drift


# ---------------------------------------------------------------------------
# Non-planar face detection
# ---------------------------------------------------------------------------


## Check whether any face has vertices that deviate from the face plane beyond
## planarity_tolerance.  Returns issues appended to the provided array.
func _check_non_planar_faces(brush: DraftBrush, issues: Array) -> void:
	for face_idx in range(brush.faces.size()):
		var face = brush.faces[face_idx]
		if not face or face.local_verts.size() < 4:
			continue  # triangles are always planar
		var verts: PackedVector3Array = face.local_verts
		var normal: Vector3 = face.normal
		if normal.length_squared() < 0.0001:
			# Compute from first 3 verts
			normal = (verts[2] - verts[0]).cross(verts[1] - verts[0]).normalized()
		if normal.length_squared() < 0.0001:
			continue
		var plane_d: float = normal.dot(verts[0])
		var max_deviation := 0.0
		for i in range(1, verts.size()):
			var dev: float = absf(normal.dot(verts[i]) - plane_d)
			if dev > max_deviation:
				max_deviation = dev
		if max_deviation > planarity_tolerance:
			issues.append(
				{
					"type": "non_planar",
					"severity": 1,
					"message":
					(
						"Brush '%s' face %d has %.4f unit vertex drift (tolerance %.4f)"
						% [brush.name, face_idx, max_deviation, planarity_tolerance]
					),
					"node": brush
				}
			)


# ---------------------------------------------------------------------------
# Micro-gap detection (near-coincident but not welded vertices between brushes)
# ---------------------------------------------------------------------------


## Detect vertices across different brushes that are within weld_tolerance of each
## other but not exactly coincident.  These cause micro-gaps after bake.
## Uses spatial hashing with 27-cell neighbor lookup so pairs straddling a bucket
## boundary are never missed.
func _check_micro_gaps(all_brushes: Array, issues: Array) -> void:
	var tol: float = weld_tolerance
	# Collect all world-space vertices into spatial hash
	var entries: Array = []  # Array of {brush: DraftBrush, pos: Vector3}
	var cells: Dictionary = {}  # cell_key -> Array[int] (indices into entries)
	for node in all_brushes:
		if not (node is DraftBrush):
			continue
		var brush := node as DraftBrush
		if root.is_entity_node(brush):
			continue
		for face in brush.faces:
			if not face or face.local_verts.size() < 3:
				continue
			for vi in range(face.local_verts.size()):
				var world_v: Vector3 = brush.global_transform * face.local_verts[vi]
				var idx: int = entries.size()
				entries.append({"brush": brush, "pos": world_v})
				var key: Vector3i = _snap_key(world_v, tol)
				if not cells.has(key):
					cells[key] = []
				(cells[key] as Array).append(idx)
	# For each vertex, search own cell + 26 neighbors for cross-brush near-pairs
	var flagged_pairs: Dictionary = {}  # avoid duplicate warnings
	for i in range(entries.size()):
		var pos_i: Vector3 = entries[i]["pos"]
		for cell_key: Vector3i in _cell_keys(pos_i, tol):
			for j: int in cells.get(cell_key, []):
				if j <= i:
					continue  # ordered pair dedup
				if entries[i]["brush"] == entries[j]["brush"]:
					continue
				var dist: float = pos_i.distance_to(entries[j]["pos"])
				if dist > _touching_distance(pos_i) and dist <= tol:
					var a: DraftBrush = entries[i]["brush"]
					var b: DraftBrush = entries[j]["brush"]
					if a.name > b.name:
						var swap := a
						a = b
						b = swap
					var pair_key := "%d|%d" % [a.get_instance_id(), b.get_instance_id()]
					if not flagged_pairs.has(pair_key):
						flagged_pairs[pair_key] = {"a": a, "b": b, "count": 0}
					flagged_pairs[pair_key]["count"] += 1
	for pair_key: String in flagged_pairs:
		var pair: Dictionary = flagged_pairs[pair_key]
		var message := (
			"Micro-gap: %d near-coincident vertex pair(s) between '%s' and '%s'"
			% [pair["count"], pair["a"].name, pair["b"].name]
		)
		message += " (weld tolerance %.4f)" % weld_tolerance
		# Both brushes, so Select and the bridge can point at the pair (#1037).
		var finding := {"type": "micro_gap", "severity": 1, "message": message}
		finding["node"] = pair["a"]
		finding["other_node"] = pair["b"]
		issues.append(finding)


## Below this two vertices are the same point, off by float32 rounding: faces
## placed to touch come out a few roundings apart, 1e-7 m near the origin, and a
## gap that small is nothing a bake or a player can see (#1058). A float32 is
## good to about one part in 8 million, so the bound grows with the coordinate.
func _touching_distance(at: Vector3) -> float:
	var far := at.abs()
	return maxf(1e-5, maxf(far.x, maxf(far.y, far.z)) * 1e-6)


# ---------------------------------------------------------------------------
# Auto-fix: weld near-coincident vertices within a brush
# ---------------------------------------------------------------------------


## Snap vertices that are within weld_tolerance of each other to a shared position.
## Operates on face local_verts in local space. `HFVertexWeld` decides which
## vertices join, the same way the `.map` import does, and each group moves to
## its average. Returns number of vertices welded.
func weld_brush_vertices(brush: DraftBrush) -> int:
	if not brush or brush.faces.is_empty():
		return 0
	# Every corner in one flat list, with the face and slot it came from.
	var points := PackedVector3Array()
	var face_of := PackedInt32Array()
	var slot_of := PackedInt32Array()
	for fi in range(brush.faces.size()):
		var face = brush.faces[fi]
		if not face:
			continue
		var verts: PackedVector3Array = face.local_verts
		for vi in range(verts.size()):
			points.append(verts[vi])
			face_of.append(fi)
			slot_of.append(vi)
	var welded := 0
	var dirty_faces: Dictionary = {}  # fi -> true
	for group: PackedInt32Array in HFVertexWeld.cluster(points, weld_tolerance):
		var avg := HFVertexWeld.average(points, group)
		for i in group:
			var fi: int = face_of[i]
			var vi: int = slot_of[i]
			var face = brush.faces[fi]
			var verts: PackedVector3Array = face.local_verts
			if verts[vi].distance_to(avg) > 0.0:
				verts[vi] = avg
				face.local_verts = verts
				welded += 1
				dirty_faces[fi] = true
	# Refresh derived state (normal, bounds) on every modified face
	for fi: int in dirty_faces:
		brush.faces[fi].ensure_geometry()
	return welded


# ---------------------------------------------------------------------------
# Auto-fix: project drifting vertices back onto their face plane
# ---------------------------------------------------------------------------


## For each face with >3 vertices, compute the best-fit plane from the first 3
## vertices and project any drifting vertices back onto it.  Returns number of
## vertices corrected.
func fix_non_planar_faces(brush: DraftBrush) -> int:
	if not brush or brush.faces.is_empty():
		return 0
	var fixed := 0
	for face in brush.faces:
		if not face or face.local_verts.size() < 4:
			continue
		var verts: PackedVector3Array = face.local_verts
		var normal: Vector3 = (verts[2] - verts[0]).cross(verts[1] - verts[0]).normalized()
		if normal.length_squared() < 0.0001:
			continue
		var plane_d: float = normal.dot(verts[0])
		for i in range(1, verts.size()):
			var dev: float = normal.dot(verts[i]) - plane_d
			if absf(dev) > planarity_tolerance:
				verts[i] = verts[i] - normal * dev
				fixed += 1
		face.local_verts = verts
		if fixed > 0:
			face.ensure_geometry()
	return fixed


## The grid cell a point falls in, at `tol` spacing. `HFVertexWeld` owns the
## grid, so the micro-gap scan buckets a point exactly where the weld does.
func _snap_key(v: Vector3, tol: float) -> Vector3i:
	return HFVertexWeld.cell(v, tol)


## Return all 27 cell keys (self + 26 neighbors) for a spatial hash lookup.
## Guarantees that any point within `cell_size` distance shares at least one cell.
## This cell and its 26 neighbours, so a pair straddling a boundary is still
## found.
##
## In index space the neighbours are just +/-1, which is why this is the change
## that mattered: the old version formatted 27 strings for every vertex of every
## brush, and that was almost the whole cost of a Check Issues pass.
func _cell_keys(v: Vector3, cell_size: float) -> Array:
	var c := HFVertexWeld.cell(v, cell_size)
	var keys: Array = []
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				keys.append(Vector3i(c.x + dx, c.y + dy, c.z + dz))
	return keys


# ---------------------------------------------------------------------------
# Occlusion coverage analysis
# ---------------------------------------------------------------------------


## Estimate how much of the baked geometry AABB is covered by OccluderInstance3D
## nodes.  Returns an array of validation issues (severity 0 = info, 1 = warn).
func check_occlusion_coverage() -> Array:
	var issues: Array = []
	if not root:
		return issues
	if not _object_has_property(root, "baked_container"):
		return issues
	var container: Node3D = root.get("baked_container") as Node3D
	if not container or not is_instance_valid(container):
		return issues

	# Compute total baked mesh AABB (recurse into BakedChunk_* nodes).
	var baked_aabb := AABB()
	var has_mesh := false
	# The bake's own walk, so validation reads the meshes the bake made (#903).
	var all_meshes: Array = HFBakeSystemType._collect_mesh_instances(container)
	for mi: MeshInstance3D in all_meshes:
		if mi.mesh:
			var mi_aabb: AABB = (
				(container.global_transform.affine_inverse() * mi.global_transform)
				* mi.mesh.get_aabb()
			)
			if has_mesh:
				baked_aabb = baked_aabb.merge(mi_aabb)
			else:
				baked_aabb = mi_aabb
				has_mesh = true
	if not has_mesh:
		return issues

	# Compute total occluder area vs baked surface area estimate.
	var occluder_node: Node = container.find_child("Occluders", false, false)
	var occluder_area := 0.0
	var occluder_count := 0
	if occluder_node:
		for child in occluder_node.get_children():
			if child is OccluderInstance3D:
				var inst: OccluderInstance3D = child as OccluderInstance3D
				occluder_count += 1
				var occ = inst.occluder
				if occ is ArrayOccluder3D:
					occluder_area += _array_occluder_area(occ)

	# Estimate baked surface area from AABB (2 * (xy + xz + yz)).
	var s: Vector3 = baked_aabb.size
	var baked_surface: float = 2.0 * (s.x * s.y + s.x * s.z + s.y * s.z)
	if baked_surface < 0.01:
		return issues

	var coverage: float = occluder_area / baked_surface
	if occluder_count == 0 and _object_property_as_bool(root, "bake_generate_occluders", false):
		(
			issues
			. append(
				{
					"type": "OcclusionMissing",
					"severity": 1,
					"message":
					"Occluder generation enabled but no occluders were created (surfaces may be too small)",
					"node": container
				}
			)
		)
	elif occluder_count > 0:
		issues.append(
			{
				"type": "OcclusionCoverage",
				"severity": 0,
				"message":
				(
					"Occlusion: %d occluders covering ~%.0f%% of baked AABB surface"
					% [occluder_count, coverage * 100.0]
				),
				"node": occluder_node
			}
		)
	return issues


func _array_occluder_area(occ: ArrayOccluder3D) -> float:
	var verts: PackedVector3Array = occ.vertices
	var indices: PackedInt32Array = occ.indices
	var area := 0.0
	var i := 0
	while i + 2 < indices.size():
		var a: Vector3 = verts[indices[i]]
		var b: Vector3 = verts[indices[i + 1]]
		var c: Vector3 = verts[indices[i + 2]]
		area += (c - a).cross(b - a).length() * 0.5
		i += 3
	return area


static func _object_has_property(obj: Object, property_name: String) -> bool:
	if not obj or property_name == "":
		return false
	for prop in obj.get_property_list():
		if prop.get("name", "") == property_name:
			return true
	return false


static func _object_property_as_bool(
	obj: Object, property_name: String, default_value: bool
) -> bool:
	if not _object_has_property(obj, property_name):
		return default_value
	return bool(obj.get(property_name))


## Every node in the level that carries an authored name and I/O outputs: the
## point entities, and the brushes tied to an entity class. `HFEntitySystem`
## resolves a connection against both, so the validator has to look at both.
func _named_io_nodes() -> Array:
	var out: Array = []
	if root.entities_node:
		out.append_array(root.entities_node.get_children())
	if root.draft_brushes_node:
		for child in root.draft_brushes_node.get_children():
			if HFEntitySystem.is_brush_io_target(child):
				out.append(child)
	return out
