@tool
extends RefCounted
class_name HFRebuildCarry

## What a copy keeps of itself when a rebuild makes it again (#1221).
##
## A prefab copy is rebuilt on a variant switch, a Pull and a propagation
## (`HFPrefabSystem._apply_variant()`), and a generated structure on Update
## (`HFGeneratorSystem.regenerate()`). Both delete the copy's nodes and make new
## ones from the source, so whatever a node has that the source does not say is
## lost unless it is read off first and put back after. Each path used to carry
## each property by hand, and every one it missed was a bug report: node names
## (#1165, #1178), authored names (#1168), the brush entity (#1163, #1237), and
## visgroups and group (#1190, #1201).
##
## A property is read and given back here and nowhere else, and
## `test_rebuild_carry.gd` holds every rebuild to every one in `PROPERTIES`. A path
## carries the ones its source does not hold: a prefab holds its look and its
## entities, all but their names, and a generator holds only its shape.

# Preloaded under their global names so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const FaceData = preload("res://addons/hammerforge/face_data.gd")
const HFBrushEntity = preload("res://addons/hammerforge/hf_brush_entity.gd")
@warning_ignore_restore("shadowed_global_identifier")

## A node's name, which the editor takes as an address.
const NODE_NAME := "name"
## The authored name a brush or point entity answers to, which wires aim at.
const ENTITY_NAME := "entity_name"
## The visgroups and the group a node is in, hidden while one of those visgroups is.
const MEMBERSHIP := "membership"
## The brush entity a brush is part of, as `HFBrushEntity.carried()` reads it: its
## class, authored name, tie, properties and wires.
const ENTITY := "entity"
## A brush's whole-brush material and each face's look, custom UVs and paint.
const APPEARANCE := "appearance"

## Every property a rebuild can carry. One added here is read by `_read()`, given
## back by `_give()`, and needs a row in `test_rebuild_carry.gd`.
const PROPERTIES := [NODE_NAME, ENTITY_NAME, MEMBERSHIP, ENTITY, APPEARANCE]

## A name is an address, so it is kept for one node only, and "" is no name.
const _ADDRESSES := [NODE_NAME, ENTITY_NAME]
## What a node a rebuild adds, or puts back in place of one deleted, joins: what
## every node had, and the whole-brush material most of them had (#1526).
const _SHARED := [MEMBERSHIP, ENTITY, APPEARANCE]

var _properties: Array = []
var _visgroups = null
## Each key's own, as `{key: {property: value}}`.
var _kept: Dictionary = {}
## What every node had, as `{property: value}`, for the properties in `_SHARED`.
var _shared: Dictionary = {}


## Read `properties` off `pieces`, each `[key, node]`. A node keeps its own under
## its key, for the node a rebuild makes under that key, and the first node under
## a key keeps it. A node under "" has no node made in its place, and counts only
## towards what every node had.
static func capture(pieces: Array, properties: Array, visgroups = null) -> HFRebuildCarry:
	var carry := HFRebuildCarry.new()
	carry._visgroups = visgroups
	for property in properties:
		# Membership lives in the visgroup system, and with none there is nothing
		# to read it from or give it back to.
		if property != MEMBERSHIP or visgroups != null:
			carry._properties.append(property)
	var everyone: Dictionary = {}
	var given: Dictionary = {}
	for piece in pieces:
		var key := str(piece[0])
		var node: Node = piece[1]
		for property in carry._properties:
			var value: Variant = carry._read(node, property)
			if property in _SHARED:
				(everyone.get_or_add(property, []) as Array).append(value)
			var own: Dictionary = carry._kept.get(key, {})
			if key == "" or own.has(property):
				continue
			if property in _ADDRESSES:
				var taken: Dictionary = given.get_or_add(property, {})
				if str(value) == "" or taken.has(value):
					continue
				taken[value] = true
			own[property] = value
			carry._kept[key] = own
	if everyone.has(MEMBERSHIP):
		carry._shared[MEMBERSHIP] = visgroups.shared_membership(everyone[MEMBERSHIP])
	if everyone.has(ENTITY):
		carry._shared[ENTITY] = _entity_every_node_shared(everyone[ENTITY])
	if everyone.has(APPEARANCE):
		carry._shared[APPEARANCE] = {"override": _material_most_had(everyone[APPEARANCE])}
	return carry


## What each key keeps of `property`, as `{key: value}`.
func kept(property: String) -> Dictionary:
	var out: Dictionary = {}
	for key in _kept:
		if _kept[key].has(property):
			out[key] = _kept[key][property]
	return out


## Give each node of `made`, each `[key, node]`, what the node under its key had,
## and a node with nothing under its key what every node had, where that is kept.
func restore(made: Array) -> void:
	for property in _properties:
		if property == NODE_NAME:
			_give_back_names(made)
			continue
		for entry in made:
			var own: Dictionary = _kept.get(str(entry[0]), {})
			if own.has(property):
				_give(entry[1], property, own[property])
			elif _shared.has(property):
				_give(entry[1], property, _shared[property])


## The transform most of `frames` agree on, two agreeing when `same` says so, as
## `[the first of them to say it, how many did]`. The first to say one wins a tie.
## `[Transform3D.IDENTITY, 0]` when there are none.
##
## Both rebuilds ask each piece where the copy is and go by the answer most of them
## give, so a piece moved or deleted does not move the rest. What counts as the
## same answer, and how many must give it, is each path's own: see
## `HFPrefabSystem._instance_frame()` and `HFGeneratorSystem._relocation_vote()`.
## `_material_most_had()` asks it of the material a node a rebuild adds takes.
static func most_agreed(frames: Array, same: Callable) -> Array:
	var groups: Array = []
	for frame in frames:
		var joined := false
		for group in groups:
			if same.call(frame, group[0]):
				group[1] = int(group[1]) + 1
				joined = true
				break
		if not joined:
			groups.append([frame, 1])
	var best: Array = [Transform3D.IDENTITY, 0]
	for group in groups:
		if int(group[1]) > int(best[1]):
			best = group
	return best


func _read(node: Node, property: String) -> Variant:
	match property:
		NODE_NAME:
			return str(node.name)
		ENTITY_NAME:
			return str(node.get_meta(HFBrushEntity.NAME_META, ""))
		MEMBERSHIP:
			return _visgroups.membership_of(node)
		ENTITY:
			return HFBrushEntity.carried(node)
		APPEARANCE:
			return _appearance_of(node)
	return null


func _give(node: Node, property: String, value: Variant) -> void:
	match property:
		ENTITY_NAME:
			node.set_meta(HFBrushEntity.NAME_META, value)
		MEMBERSHIP:
			_visgroups.give_back_membership(node, value)
		ENTITY:
			HFBrushEntity.give(node, value)
		APPEARANCE:
			_apply_appearance(node, value)


## Give back each kept node name, from a node made earlier in the same rebuild if
## that one took it. Godot numbers a taken name on to the first free one, and with
## the copy's own nodes gone that can be the name a later node of it is about to
## get back (#1178).
func _give_back_names(made: Array) -> void:
	var ours: Dictionary = {}
	for entry in made:
		ours[entry[1]] = true
	for entry in made:
		var node: Node = entry[1]
		var wanted := str(_kept.get(str(entry[0]), {}).get(NODE_NAME, ""))
		var parent := node.get_parent()
		if wanted == "" or str(node.name) == wanted or parent == null:
			continue
		var holder: Node = parent.get_node_or_null(NodePath(wanted))
		if holder and not ours.has(holder):
			continue
		var had := str(node.name)
		if holder:
			holder.name = "_hf_rebuild_swap"
		node.name = wanted
		if holder:
			holder.name = had


## The brush entity every node was part of, or empty when they were not all one.
## A deleted node has no say, as it was not read, and letting it count as plain
## geometry untied every piece put back or added (#1237).
static func _entity_every_node_shared(entities: Array) -> Dictionary:
	var shared: Dictionary = {}
	for entity in entities:
		if entity.is_empty():
			return {}
		if shared.is_empty():
			shared = entity
			continue
		for key in [HFBrushEntity.CLASS_META, HFBrushEntity.NAME_META, HFBrushEntity.TIE_META]:
			if str(entity.get(key, "")) != str(shared.get(key, "")):
				return {}
	return shared


## The whole-brush material most nodes had, the earliest node's when as many had
## another. A node with none counts too, so a structure left mostly plain does not
## spread one painted piece's material over every piece an Update adds. A node
## added takes only this, since it has no faces of its own to take a look from.
static func _material_most_had(looks: Array) -> Material:
	var materials: Array = []
	for look in looks:
		if look is Dictionary and not look.is_empty():
			materials.append(look.get("override"))
	if materials.is_empty():
		return null
	return most_agreed(materials, func(a, b): return a == b)[0]


## What a brush looks like. The override material is the whole-brush one. The face
## entries are what the Paint tab writes, which is per face and is the work most
## worth not losing: painting a generated arch and then nudging its radius should
## not reset it. Empty for a node with no faces.
static func _appearance_of(brush) -> Dictionary:
	if not ("faces" in brush):
		return {}
	var faces: Array = []
	for face in brush.faces:
		faces.append(_face_appearance(face))
	return {"override": brush.material_override, "faces": faces}


## A face's look, held on a face of its own so `copy_appearance_from()` decides
## what that is, `.map` name included (#859). Custom UVs and paint are kept with it,
## since the Paint tab writes those per face too, and so is the way the face
## pointed, which is how a box piece finds it again.
static func _face_appearance(face) -> FaceData:
	if face == null:
		return null
	var held := FaceData.new()
	held.copy_appearance_from(face)
	held.custom_uvs = face.custom_uvs
	held.paint_layers = face.paint_layers
	held.normal = face.normal
	return held


## Put back what a brush looked like.
##
## Faces are matched by index, which is a real correspondence only while the
## rebuilt brush has the same faces in the same order, and on a box piece by the
## way each face points (`_stored_face_for_each()`). A brush whose face count
## changed keeps the whole-brush material and takes default faces, and
## `HFGeneratorSystem.appearance_at_risk()` is what says so before an Update.
static func _apply_appearance(brush, appearance) -> void:
	if not (appearance is Dictionary) or appearance.is_empty() or not ("faces" in brush):
		return
	if appearance.get("override", null) != null:
		brush.material_override = appearance["override"]
	var stored: Array = appearance.get("faces", [])
	var faces: Array = brush.faces
	if stored.size() != faces.size():
		return
	var sources := _stored_face_for_each(brush, stored)
	for i in faces.size():
		_restore_face(faces[i], stored[sources[i]])
	brush.rebuild_preview()


## Which stored face each face of `brush` takes its look from: the one at its
## index, except on a box piece, which takes the one that pointed its way.
##
## A box piece's faces point along the axes at every size, so the direction names
## the face where the index may not. A step made before #867 lists its faces the
## way the stairs builder made them, a step made since the way the box builder
## does, and an `.hflevel` load rebuilds neither, so an Update after one put every
## look on another side.
static func _stored_face_for_each(brush, stored: Array) -> PackedInt32Array:
	var sources := PackedInt32Array(range(stored.size()))
	if int(brush.shape) != brush.BrushShape.BOX:
		return sources
	for i in brush.faces.size():
		var face = brush.faces[i]
		if face == null:
			continue
		var best_dot := -INF
		for j in stored.size():
			var held = stored[j]
			if held == null:
				continue
			var alignment: float = held.normal.dot(face.normal)
			if alignment > best_dot:
				best_dot = alignment
				sources[i] = j
	return sources


static func _restore_face(face, stored) -> void:
	if face == null or not (stored is FaceData):
		return
	face.copy_appearance_from(stored)
	if stored.custom_uvs.size() == face.local_verts.size():
		face.custom_uvs = stored.custom_uvs
	if not stored.paint_layers.is_empty():
		face.paint_layers.assign(stored.paint_layers)
