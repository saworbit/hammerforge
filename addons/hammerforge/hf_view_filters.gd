@tool
extends RefCounted
## Hide things by kind in the editor (#1720): world brushes, cuts, clip brushes,
## triggers and the other brush entities, point entities, structures, prefab
## copies, decals, I/O wires and cordons, and each brush entity or point entity
## class on its own row.
##
## What got in the way was a kind, not a group: the triggers over a doorway, the
## clip brushes along a ledge, a light's gizmo everywhere. Hiding them took a
## visgroup kept up to date by hand, and a trigger made the next day was not in
## it. A filter is a rule, so anything of a hidden kind is hidden, made later or
## not. It is the editor's own view, like the camera: the level's `view_filters`
## is never saved, visgroups still decide on top of it, and the bake ignores it.

# Preloaded under its global name so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const DraftBrush = preload("brush_instance.gd")
const DraftEntity = preload("draft_entity.gd")
const HFBrushEntity = preload("hf_brush_entity.gd")
const HFGeneratorSystem = preload("systems/hf_generator_system.gd")
@warning_ignore_restore("shadowed_global_identifier")

## The kinds the View Filters list starts with, in its order.
const KINDS := [
	"world",
	"cut",
	"clip",
	"trigger",
	"brush_entity",
	"entity",
	"structure",
	"prefab",
	"decal",
	"wires",
	"cordons",
]
const LABELS := {
	"world": "World brushes",
	"cut": "Cut brushes",
	"clip": "Clip brushes",
	"trigger": "Triggers",
	"brush_entity": "Brush entities",
	"entity": "Point entities",
	"structure": "Structures",
	"prefab": "Prefab copies",
	"decal": "Decals",
	"wires": "I/O wires",
	"cordons": "Cordons",
}
## A class row's key is its kind and the class: `brush_entity:func_door`.
const CLASS_KINDS := ["brush_entity", "entity"]


## The row a key reads as: a kind's label, or a class name.
static func label_for(key: String) -> String:
	if LABELS.has(key):
		return LABELS[key]
	var at := key.find(":")
	return key.substr(at + 1) if at >= 0 else key


## Every filter key `node` answers to: its kind, its class row, and whether it
## is a structure piece or a prefab copy.
static func keys_of(root: Node, node: Node) -> PackedStringArray:
	var out := PackedStringArray()
	if node is DraftEntity:
		out.append("entity")
		var entity_class := str((node as DraftEntity).entity_class)
		if entity_class != "":
			out.append("entity:%s" % entity_class)
	elif node is DraftBrush:
		var brush := node as DraftBrush
		var entity_class := HFBrushEntity.entity_class(brush)
		var pending = root.get("pending_node")
		if (
			brush.operation == CSGShape3D.OPERATION_SUBTRACTION
			or (pending != null and brush.get_parent() == pending)
		):
			out.append("cut")
		elif entity_class == HFBrushEntity.CLIP_CLASS:
			out.append("clip")
		elif entity_class != "":
			out.append("brush_entity")
			out.append("brush_entity:%s" % entity_class)
			if entity_class.begins_with("trigger"):
				out.append("trigger")
		else:
			out.append("world")
		if str(brush.get_meta(HFGeneratorSystem.GENERATOR_META, "")) != "":
			out.append("structure")
	else:
		return out
	var prefabs = root.get("prefab_system")
	if prefabs != null and prefabs.instance_of(node) != null:
		out.append("prefab")
	return out


## Whether the level's view filters hide `node`.
static func hides(root: Node, node: Node) -> bool:
	var hidden = root.get("view_filters") if root != null else null
	if not (hidden is Dictionary) or (hidden as Dictionary).is_empty():
		return false
	for key in keys_of(root, node):
		if (hidden as Dictionary).has(key):
			return true
	return false


## The brush entity and point entity classes in the level, sorted, as
## `{"brush_entity": [...], "entity": [...]}`, for the class rows.
static func classes_in(root: Node) -> Dictionary:
	var found := {"brush_entity": {}, "entity": {}}
	var nodes: Array = root._iter_pick_nodes() if root.has_method("_iter_pick_nodes") else []
	for node in nodes:
		if node is DraftEntity:
			var entity_class := str((node as DraftEntity).entity_class)
			if entity_class != "":
				found["entity"][entity_class] = true
		elif node is DraftBrush:
			var brush_class := HFBrushEntity.entity_class(node)
			if brush_class != "" and brush_class != HFBrushEntity.CLIP_CLASS:
				found["brush_entity"][brush_class] = true
	var out := {}
	for kind in found:
		var names: Array = (found[kind] as Dictionary).keys()
		names.sort()
		out[kind] = names
	return out
