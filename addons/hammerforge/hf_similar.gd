@tool
extends RefCounted
## What Select Similar matches on (#1698).
##
## It matched faces by material and normal and brushes by size, and nothing else
## could be asked for, so "every brush with this material" took a click on each
## one. The keys ticked in Selection Filters are kept in the user prefs, and
## Shift+S matches on them next time too. A candidate is similar when it agrees
## with one of the selected ones on every ticked key. Hidden brushes and entities
## are left out, as every bulk filter leaves them out.

# Preloaded under its global name so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const DraftBrush = preload("brush_instance.gd")
const DraftEntity = preload("draft_entity.gd")
const HFBrushEntity = preload("hf_brush_entity.gd")
const HFGeneratorSystem = preload("systems/hf_generator_system.gd")
@warning_ignore_restore("shadowed_global_identifier")
const HFBrushSystemType = preload("systems/hf_brush_system.gd")

const BRUSH_KEYS := [
	"material", "shape", "operation", "size", "visgroup", "group", "structure", "brush_entity"
]
const FACE_KEYS := ["material", "uv_scale", "normal"]
const ENTITY_KEYS := ["class", "property"]
const LABELS := {
	"material": "Material",
	"shape": "Shape",
	"operation": "Add or cut",
	"size": "Size",
	"visgroup": "Visgroup",
	"group": "Group",
	"structure": "Structure",
	"brush_entity": "Entity class",
	"uv_scale": "UV scale",
	"normal": "Normal",
	"class": "Class",
	"property": "Property",
}
## The pref each kind's keys are kept under.
const PREFS := {
	"brush": "similar_brush_keys", "face": "similar_face_keys", "entity": "similar_entity_keys"
}
## What each kind matched on before it could be told, and still does untouched.
const DEFAULTS := {"brush": ["size"], "face": ["material", "normal"], "entity": ["class"]}
## The entity property the Property key compares.
const PROPERTY_PREF := "similar_property"

## A face's world normal within about 15 degrees of the selected face's.
const NORMAL_DOT := 0.966
## How far apart two brushes' sides may be, as a share of the selected one's.
const SIZE_TOLERANCE := 0.2


## Every key `kind` can match on: "brush", "face" or "entity".
static func known_keys(kind: String) -> Array:
	match kind:
		"brush":
			return BRUSH_KEYS
		"face":
			return FACE_KEYS
		"entity":
			return ENTITY_KEYS
	return []


## The keys `kind` matches on, as `prefs` keep them, or the defaults when they
## keep none. A key this build does not know is dropped.
static func keys_for(prefs: Object, kind: String) -> Array:
	var saved: Variant = prefs.get_pref(PREFS[kind], null) if prefs != null else null
	if not (saved is Array):
		return DEFAULTS[kind].duplicate()
	var out: Array = []
	for key in saved:
		if known_keys(kind).has(str(key)) and not out.has(str(key)):
			out.append(str(key))
	return out


## The entity property the Property key compares, as `prefs` keep it.
static func property_for(prefs: Object) -> String:
	return str(prefs.get_pref(PROPERTY_PREF, "")).strip_edges() if prefs != null else ""


## The keys read as a person would: "material and size".
static func describe(keys: Array) -> String:
	var words: Array = []
	for key in keys:
		words.append(str(LABELS.get(key, key)).to_lower())
	if words.size() < 2:
		return "".join(words)
	return "%s and %s" % [", ".join(words.slice(0, -1)), words[-1]]


## The visible brushes similar to a brush of `seeds` on every key of `keys`.
static func brushes(root: Node, seeds: Array, keys: Array) -> Array:
	var refs: Array = []
	for node in seeds:
		if is_instance_valid(node) and node is DraftBrush:
			refs.append(node)
	var picked: Array = []
	if refs.is_empty():
		return picked
	for node in _pick_nodes(root):
		if not (node is DraftBrush) or not (node as DraftBrush).is_visible_in_tree():
			continue
		for ref in refs:
			if brush_agrees(root, node, ref, keys):
				picked.append(node)
				break
	return picked


## Whether `brush` agrees with `ref` on every key of `keys`.
static func brush_agrees(root: Node, brush: DraftBrush, ref: DraftBrush, keys: Array) -> bool:
	for key in keys:
		match str(key):
			"material":
				if not wears(brush, main_material(ref)):
					return false
			"shape":
				if brush.shape != ref.shape:
					return false
			"operation":
				if cuts(root, brush) != cuts(root, ref):
					return false
			"size":
				if not size_similar(brush.size, ref.size, SIZE_TOLERANCE):
					return false
			"visgroup":
				if _visgroups(root, brush) != _visgroups(root, ref):
					return false
			"group":
				if _group(root, brush) != _group(root, ref):
					return false
			"structure":
				if _structure(brush) != _structure(ref):
					return false
			"brush_entity":
				if HFBrushEntity.entity_class(brush) != HFBrushEntity.entity_class(ref):
					return false
	return true


## The faces similar to the faces selected now, keyed as `face_selection` is: a
## face on a visible brush that agrees with one of them on every key of `keys`.
## Empty when no selected face can be found.
static func faces(root: Node, keys: Array) -> Dictionary:
	var refs: Array = []
	for key in root.face_selection.keys():
		var brush = root._find_brush_by_key(str(key))
		if not brush:
			continue
		var basis: Basis = brush.global_transform.basis if brush is Node3D else Basis.IDENTITY
		var brush_faces: Array = brush.get_faces() if brush.has_method("get_faces") else []
		for fi in root.face_selection.get(key, []):
			if int(fi) >= 0 and int(fi) < brush_faces.size():
				var face = brush_faces[int(fi)]
				refs.append({"face": face, "normal": face.normal_through(basis)})
	var out: Dictionary = {}
	if refs.is_empty():
		return out
	for node in _pick_nodes(root):
		if not (node is DraftBrush) or not (node as DraftBrush).is_visible_in_tree():
			continue
		var brush := node as DraftBrush
		var basis: Basis = brush.global_transform.basis
		var brush_faces: Array = brush.get_faces()
		var indices: Array = []
		for i in brush_faces.size():
			var face = brush_faces[i]
			if face == null:
				continue
			var normal: Vector3 = face.normal_through(basis)
			for ref in refs:
				if _face_agrees(face, normal, ref, keys):
					indices.append(i)
					break
		if not indices.is_empty():
			out[HFBrushSystemType.face_key(brush)] = indices
	return out


static func _face_agrees(face: Object, normal: Vector3, ref: Dictionary, keys: Array) -> bool:
	for key in keys:
		match str(key):
			"material":
				if face.material_idx != ref["face"].material_idx:
					return false
			"uv_scale":
				if not face.uv_scale.is_equal_approx(ref["face"].uv_scale):
					return false
			"normal":
				if normal.dot(ref["normal"]) <= NORMAL_DOT:
					return false
	return true


## The visible entities similar to an entity of `seeds` on every key of `keys`.
## `property` names the property the Property key compares; an entity without
## it is not similar on it.
static func entities(root: Node, seeds: Array, keys: Array, property: String) -> Array:
	var refs: Array = []
	for node in seeds:
		if is_instance_valid(node) and node is DraftEntity:
			refs.append(node)
	var picked: Array = []
	if refs.is_empty():
		return picked
	for node in _pick_nodes(root):
		if not (node is DraftEntity) or not (node as DraftEntity).is_visible_in_tree():
			continue
		for ref in refs:
			if entity_agrees(node, ref, keys, property):
				picked.append(node)
				break
	return picked


static func entity_agrees(
	entity: DraftEntity, ref: DraftEntity, keys: Array, property: String
) -> bool:
	for key in keys:
		match str(key):
			"class":
				if entity.entity_class != ref.entity_class:
					return false
			"property":
				if property == "":
					return false
				if not entity.entity_data.has(property) or not ref.entity_data.has(property):
					return false
				if entity.entity_data[property] != ref.entity_data[property]:
					return false
	return true


## The palette slot most of `brush`'s faces wear, the lowest on a tie.
static func main_material(brush: DraftBrush) -> int:
	var counts: Dictionary = {}
	for face in brush.faces:
		if face != null:
			counts[int(face.material_idx)] = int(counts.get(int(face.material_idx), 0)) + 1
	var best := -1
	var most := 0
	for slot in counts:
		if counts[slot] > most or (counts[slot] == most and int(slot) < best):
			best = int(slot)
			most = counts[slot]
	return best


static func wears(brush: DraftBrush, slot: int) -> bool:
	for face in brush.faces:
		if face != null and int(face.material_idx) == slot:
			return true
	return false


## A cut: a subtract brush, or one waiting to be carved.
static func cuts(root: Node, brush: Node) -> bool:
	if brush.get("operation") == CSGShape3D.OPERATION_SUBTRACTION:
		return true
	var pending = root.get("pending_node")
	return pending != null and brush.get_parent() == pending


static func size_similar(a: Vector3, b: Vector3, tolerance: float) -> bool:
	var sa := sorted_vec(a)
	var sb := sorted_vec(b)
	for i in range(3):
		var ref_val: float = maxf(sb[i], 0.01)
		if absf(sa[i] - sb[i]) / ref_val > tolerance:
			return false
	return true


static func sorted_vec(v: Vector3) -> Array:
	var arr := [v.x, v.y, v.z]
	arr.sort()
	return arr


static func _pick_nodes(root: Node) -> Array:
	return root._iter_pick_nodes() if root.has_method("_iter_pick_nodes") else []


static func _visgroups(root: Node, node: Node) -> Array:
	var system = root.get("visgroup_system")
	if system == null:
		return []
	var names := Array(system.get_visgroups_of(node))
	names.sort()
	return names


static func _group(root: Node, node: Node) -> String:
	var system = root.get("visgroup_system")
	return str(system.get_group_of(node)) if system != null else ""


static func _structure(brush: Node) -> String:
	return str(brush.get_meta(HFGeneratorSystem.GENERATOR_META, ""))
