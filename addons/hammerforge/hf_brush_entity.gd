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
const OUTPUTS_META := "entity_io_outputs"
## Every one of them, in the order a brush record has always listed them. The
## record a capture writes, the brush a rebuild makes, `carried()` and `give()`
## all go by this list, so a field added here reaches each of them (#1224).
const FIELDS := [CLASS_META, OUTPUTS_META, TIE_META, DATA_META, NAME_META]
## On a baked node of a named entity, the node name of the brush it came from,
## which the editor takes as an address of the entity as well (#1149).
const BRUSH_NAME_META := "brush_node_name"

## Collision the player cannot see. The bake, the editor's tint, the `.map` import
## and export and Validate each treat it apart from the other classes (#1409).
const CLIP_CLASS := "func_clip"

## What an identity puts before a name, and before a tie.
const NAME_PREFIX := "@"
const TIE_PREFIX := "@#"

## How many ties `mint_tie()` has made this session, so two minted in the same
## microsecond still differ.
static var _ties_minted := 0


## A tie no brush has yet: what makes brushes one entity when they are tied
## together, by `tie_brushes_to_entity()`, a `.map` import or a placed prefab.
## The clock and the count both start again with each session, and a level keeps
## its ties, so a random part keeps a tie minted now off one saved before (#1228).
static func mint_tie() -> String:
	_ties_minted += 1
	return "beg_%x_%d_%08x" % [Time.get_ticks_usec(), _ties_minted, randi()]


## The class a brush or a baked node is tied to, or "" for plain geometry.
static func entity_class(node: Node) -> String:
	return str(node.get_meta(CLASS_META, ""))


## Whether a brush or a baked node is a `func_clip`.
static func is_clip(node: Node) -> bool:
	return entity_class(node) == CLIP_CLASS


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


## Everything that makes a brush part of a brush entity, as `give()` puts it on
## another brush: its class, name, tie, wires and properties. Empty for plain
## geometry.
static func carried(brush: Node) -> Dictionary:
	if entity_class(brush) == "":
		return {}
	return fields(brush)


## Each field of `FIELDS` a brush holds, as a brush record stores it: the ones with
## nothing in them left out, the lists and dictionaries copied. A record keeps what
## the brush has, so a name or a wire on a brush with no class is kept as well.
static func fields(brush: Node) -> Dictionary:
	var out: Dictionary = {}
	for key in FIELDS:
		if brush.has_meta(key) and _holds_something(key, brush.get_meta(key)):
			out[key] = _copied(brush.get_meta(key))
	return out


## Make `brush` part of the entity `carried()` read off another one. `entity` can
## be a whole brush record, of which only the fields of `FIELDS` are read.
static func give(brush: Node, entity: Dictionary) -> void:
	for key in FIELDS:
		if not entity.has(key) or not _holds_something(key, entity[key]):
			continue
		var value: Variant = _copied(entity[key])
		if key == CLASS_META and brush.has_method("set_brush_entity_class"):
			brush.call("set_brush_entity_class", value)
		else:
			brush.set_meta(key, value)


## Whether a field says anything: wires in a list, properties in a dictionary, and
## for the rest some text.
static func _holds_something(key: String, value: Variant) -> bool:
	match key:
		OUTPUTS_META:
			return value is Array and not (value as Array).is_empty()
		DATA_META:
			return value is Dictionary and not (value as Dictionary).is_empty()
	return value != null and str(value) != ""


static func _copied(value: Variant) -> Variant:
	if value is Array or value is Dictionary:
		return value.duplicate(true)
	return str(value)


## What each piece of a brush that is cut up carries: the whole of its entity, so
## a door clipped to fit a frame is still one door, with its name, properties and
## wires on every piece (#1194). Every brush of an entity holds its wires, and the
## runtime and the `.map` export each take a wire every brush holds once. A brush
## that is an entity with neither a name nor a tie gives its pieces a new tie, so
## they are one entity as it was.
static func carried_into_pieces(brush: Node) -> Dictionary:
	var out := carried(brush)
	if not out.is_empty() and identity(brush) == "":
		out[TIE_META] = mint_tie()
	return out


## Whether `brushes` are all one brush entity, or all plain geometry: what one
## brush made of them can be without a door losing a leaf to a wall, or two doors
## becoming one (#1194).
static func are_one_entity(brushes: Array) -> bool:
	if brushes.is_empty():
		return true
	var wanted_class := entity_class(brushes[0])
	var key := identity(brushes[0])
	for brush in brushes.slice(1):
		if entity_class(brush) != wanted_class:
			return false
		if wanted_class != "" and (key == "" or identity(brush) != key):
			return false
	return true


## What one brush made of all of `brushes`, one entity, carries: the first one's
## entity, with every wire and property any of the others holds as well, as the
## `.map` export writes the entity from all of them (#1128).
static func carried_by_all(brushes: Array) -> Dictionary:
	if brushes.is_empty():
		return {}
	var out := carried(brushes[0])
	if out.is_empty():
		return out
	var wires: Array = out.get(OUTPUTS_META, [])
	var data: Dictionary = out.get(DATA_META, {})
	for brush in brushes.slice(1):
		var theirs := carried(brush)
		for wire in theirs.get(OUTPUTS_META, []):
			if not wires.has(wire):
				wires.append(wire)
		data.merge(theirs.get(DATA_META, {}))
	if not wires.is_empty():
		out[OUTPUTS_META] = wires
	if not data.is_empty():
		out[DATA_META] = data
	return out


## Make one copy's records into entities of their own, before anything is built
## from them, and return the authored names that changed, old to new: a fresh tie
## for each tie the copy holds, and a name of its own in the level for each
## authored name, the same for every brush of one entity. The records are changed
## in place. A placed prefab (#1158, #1159), a paste and a duplicate (#1161) are
## copies, and a copy that kept the tie or the name it was made from joined the
## entity it came from: a duplicated door was one door of four leaves.
##
## `kept` maps an authored name to the name a copy being rebuilt answers to now,
## which it gets back instead of a free one (#1168). `reserved` are names the
## caller gives back itself, to records with no authored name, so no free name
## chosen here is one of them (#1274).
static func fresh_identities(
	brush_infos: Array,
	entity_infos: Array,
	entity_system,
	kept: Dictionary = {},
	reserved: Array = []
) -> Dictionary:
	var ties: Dictionary = {}
	var addresses: Dictionary = {}
	# Spoken for before any free name is chosen, so none is handed out twice.
	var given: Dictionary = {}
	for value in kept.values() + reserved:
		given[value] = true
	for info in brush_infos + entity_infos:
		var tie := str(info.get(TIE_META, ""))
		if tie != "":
			if not ties.has(tie):
				ties[tie] = mint_tie()
			info[TIE_META] = ties[tie]
		var authored := str(info.get(NAME_META, ""))
		if authored == "":
			continue
		if not addresses.has(authored):
			if kept.has(authored):
				addresses[authored] = str(kept[authored])
			else:
				addresses[authored] = _free_name(entity_system, authored, given)
			given[addresses[authored]] = true
		info[NAME_META] = addresses[authored]
	return addresses


## A name nothing in the level answers to yet, nor anything this copy has already
## been given.
static func _free_name(entity_system, wanted: String, given: Dictionary) -> String:
	if entity_system == null or not entity_system.has_method("unique_authored_name"):
		return wanted
	var candidate: String = entity_system.unique_authored_name(wanted)
	var next := 2
	while given.has(candidate):
		candidate = entity_system.unique_authored_name("%s_%d" % [wanted, next])
		next += 1
	return candidate


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
