@tool
extends RefCounted
class_name HFBrushEntity

## What makes a set of brushes one brush entity, and what that entity's name,
## members and properties are (#1148).
##
## The bake, the runtime dispatcher, the `.map` export, the Entity panel and MCP
## each worked this out from the raw metadata by themselves, so a change to the
## rule reached them one at a time: the export split an entity (#1128), the
## import split it (#1134), the runtime fired once per brush (#1133) and a door's
## `OnOpen` went quiet (#1145). They ask here instead.
##
## On a draft brush the rule is this. A brush with a class is a brush entity. Its
## entity is its authored name when it has one, and otherwise the tie it was made
## in. Brushes with the same class and the same of those are one entity, and a
## brush with neither is an entity of its own. `tie_brushes_to_entity()` mints a
## tie, and a `.map` import mints one per block.
##
## A baked node says the same thing another way, which `baked_identity()` reads.
## Every node the bake makes for a brush entity carries a name: its entity's, or
## the brush's own when the entity has none. So on a baked node the name cannot
## tell an unnamed tie's brushes apart. The bake writes the tie only on the nodes
## of an entity with no name (`tie_to_bake()`), and there the tie decides first.
## `test_brush_entity_rule.gd` holds the two forms to the same entities.

## The metadata a brush entity is made of.
const CLASS_META := "brush_entity_class"
const NAME_META := "entity_name"
const TIE_META := "brush_entity_group"
const DATA_META := "brush_entity_data"
## On a baked node of a named entity, the node name of the brush it came from,
## which the editor takes as an address of the entity as well (#1149).
const BRUSH_NAME_META := "brush_node_name"

## What an identity puts before a name, and before a tie.
const NAME_PREFIX := "@"
const TIE_PREFIX := "@#"

## How many ties `mint_tie()` has made this session, so two minted in the same
## microsecond still differ.
static var _ties_minted := 0


## A tie no brush has yet: what makes brushes one entity when they are tied
## together, by `tie_brushes_to_entity()`, a `.map` import or a placed prefab.
static func mint_tie() -> String:
	_ties_minted += 1
	return "beg_%x_%d" % [Time.get_ticks_usec(), _ties_minted]


## The class a brush or a baked node is tied to, or "" for plain geometry.
static func entity_class(node: Node) -> String:
	return str(node.get_meta(CLASS_META, ""))


## Which brush entity a draft brush is part of: `@` and its authored name, or `@#`
## and its tie when it has no name. "" for plain geometry, and for a brush entity
## with neither, which is an entity of its own.
static func identity(brush: Node) -> String:
	if entity_class(brush) == "":
		return ""
	var entity_name := str(brush.get_meta(NAME_META, ""))
	if entity_name != "":
		return NAME_PREFIX + entity_name
	var tie := str(brush.get_meta(TIE_META, ""))
	return "" if tie == "" else TIE_PREFIX + tie


## The brushes among `candidates` that are one entity with `brush`, itself first:
## the same class and the same `identity()`. A brush that is no entity, or one
## with neither a name nor a tie, is only itself.
static func members(brush: Node, candidates: Array) -> Array:
	var found: Array = [brush]
	var key := identity(brush)
	if key == "":
		return found
	var wanted_class := entity_class(brush)
	for other in candidates:
		if other == brush or not (other is Node) or not is_instance_valid(other):
			continue
		if entity_class(other) == wanted_class and identity(other) == key:
			found.append(other)
	return found


## What a brush was tied as: its class and the tie it was made in, empty for a
## brush never tied. Brushes alike in this were made one entity on purpose. Two
## ties under one name are one entity by `identity()` too, but nobody said so,
## which is what Validate's duplicate name check is there to point out (#1151).
static func tie_key(brush: Node) -> String:
	return "%s|%s" % [entity_class(brush), str(brush.get_meta(TIE_META, ""))]


## A brush entity's properties as the game gets them: every default `definition`
## declares, with what was set on the brush over them.
static func properties(definition: Dictionary, brush: Node) -> Dictionary:
	var out: Dictionary = {}
	for prop in definition.get("properties", []):
		if not (prop is Dictionary):
			continue
		var prop_name := str(prop.get("name", ""))
		if prop_name != "" and prop.has("default"):
			out[prop_name] = prop["default"]
	var stored: Variant = brush.get_meta(DATA_META, {})
	if stored is Dictionary:
		for key in stored as Dictionary:
			out[str(key)] = stored[key]
	return out


## The tie the bake writes on the nodes it makes of `brush`: its tie when its
## entity has no name, and "" when it has one, which is one entity by its name.
static func tie_to_bake(brush: Node) -> String:
	if str(brush.get_meta(NAME_META, "")) != "":
		return ""
	return str(brush.get_meta(TIE_META, ""))


## Which brush entity a baked node is part of, in the form `identity()` gives for
## the brush it came from: `@#` and the tie when it carries one, otherwise `@` and
## its name. "" for a node of no brush entity, which is one entity per node.
static func baked_identity(node: Node) -> String:
	if entity_class(node) == "":
		return ""
	var tie := str(node.get_meta(TIE_META, ""))
	if tie != "":
		return TIE_PREFIX + tie
	var entity_name := str(node.get_meta(NAME_META, ""))
	return "" if entity_name == "" else NAME_PREFIX + entity_name
