@tool
extends RefCounted
## What a level holds, row by row, and what each file format leaves out of it
## (#1706).
##
## `docs/HammerForge_Data_Portability.md` opens with one table: a row for each
## thing a level holds, a column for each file it can go through. This counts
## each row in a level, so `tests/test_format_table.gd` can round trip a level
## through each format and hold every cell of the table to what came back, and so
## an export can name what it left out, as "left out 2 cordons, 1 note, paint on
## 14 faces". `LOSES` is each format's Lost cells, which that test holds to the
## table as well.

# Preloaded under its global name so the script parses before Godot has
# registered the global classes, as on a fresh clone.
@warning_ignore_start("shadowed_global_identifier")
const DraftBrush = preload("brush_instance.gd")
const DraftEntity = preload("draft_entity.gd")
const HFBrushEntity = preload("hf_brush_entity.gd")
const HFNotes = preload("hf_notes.gd")
const HFBakeSplit = preload("hf_bake_split.gd")
const HFEntityPropUtils = preload("ui/hf_entity_prop_utils.gd")
const HFTranslationType = preload("res://addons/hammerforge/hf_translation.gd")
@warning_ignore_restore("shadowed_global_identifier")

## The metas that tie a piece to a structure and to a prefab copy, as
## `HFGeneratorSystem.GENERATOR_META` and `HFPrefabSystem.INSTANCE_META` name them.
const GENERATOR_META := &"hf_generator_id"
const INSTANCE_META := &"hf_prefab_instance"

## The rows, in the table's order: the key and the row's name in the table.
## `_phrase()` says how a count of each reads.
const ROWS := [
	["brushes", "Brushes"],
	["shapes", "Brush shapes"],
	["cuts", "Cuts"],
	["face_materials", "Face materials"],
	["uv_settings", "Texture settings"],
	["custom_uvs", "Hand laid UVs"],
	["paint", "Face paint"],
	["sculpts", "Sculpts"],
	["smoothing", "Smoothing groups"],
	["hidden_faces", "Hidden faces"],
	["texture_groups", "Texture groups"],
	["entities", "Point entities"],
	["entity_properties", "Entity properties"],
	["wires", "I/O wires"],
	["brush_entities", "Brush entities"],
	["visgroups", "Visgroups"],
	["groups", "Groups"],
	["structures", "Structures"],
	["prefab_links", "Prefab copies"],
	["cordons", "Cordons"],
	["bake_settings", "Bake options"],
	["brush_bake", "A brush's bake options"],
	["floor_paint", "Floor paint"],
	["notes", "Notes"],
]

## What each format loses: the rows it has as Lost in the table.
const LOSES := {
	".map":
	[
		"shapes",
		"cuts",
		"custom_uvs",
		"paint",
		"sculpts",
		"smoothing",
		"texture_groups",
		"visgroups",
		"groups",
		"structures",
		"prefab_links",
		"cordons",
		"bake_settings",
		"brush_bake",
		"floor_paint",
		"notes",
	],
	".glb": ["entities", "entity_properties", "wires", "notes"],
	".hfprefab": ["visgroups", "structures", "prefab_links"],
}


## How many of `row` the level `root` holds, or of the nodes in `only` when it
## is not empty: a selection, which holds none of what belongs to the level
## alone, its cordons, its bake options and its floor paint.
static func count(root: Node, row: String, only: Array = []) -> int:
	var brushes := _within(_brushes(root), only)
	match row:
		"brushes":
			return brushes.size()
		"shapes":
			return brushes.filter(_has_own_shape).size()
		"cuts":
			return _within(_cuts(root), only).size()
		"face_materials":
			return _faces(root, only, func(face): return face.material_idx >= 0)
		"uv_settings":
			return _faces(root, only, _laid_on)
		"custom_uvs":
			return _faces(root, only, func(face): return face.has_hand_layout())
		"paint":
			return _faces(root, only, func(face): return not face.paint_layers.is_empty())
		"sculpts":
			return _faces(root, only, func(face): return face.displacement != null)
		"smoothing":
			return _faces(root, only, func(face): return face.smoothing_group > 0)
		"hidden_faces":
			return _faces(root, only, func(face): return face.is_hidden())
		"texture_groups":
			return _faces(root, only, func(face): return face.uv_group != 0)
		"entities":
			return _within(_point_entities(root), only).size()
		"entity_properties":
			return _within(_point_entities(root), only).filter(_has_properties).size()
		# A brush entity of several brushes is one entity, and each of its brushes
		# holds its wires: a door of two leaves was the wires of 2 entities (#1958).
		"wires":
			var wired := _within(_entities(root), only).filter(_has_wires).size()
			for each in HFBrushEntity.entities_in(brushes):
				if (each as Array).any(_has_wires):
					wired += 1
			return wired
		"brush_entities":
			return HFBrushEntity.entities_in(brushes).size()
		"visgroups":
			return _visgroups(root, only)
		"groups":
			return _groups(root, only)
		"structures":
			if not only.is_empty():
				return _tags(only, GENERATOR_META).size()
			return root.generator_system.generators.size() if root.get("generator_system") else 0
		"prefab_links":
			if not only.is_empty():
				return _tags(only, INSTANCE_META).size()
			return root.prefab_system._instances.size() if root.get("prefab_system") else 0
		"cordons":
			return _cordons(root) if only.is_empty() else 0
		"bake_settings":
			return _bake_options(root) if only.is_empty() else 0
		"brush_bake":
			return brushes.filter(_has_own_bake).size()
		"floor_paint":
			return _floor_paint(root) if only.is_empty() else 0
		"notes":
			return _within(HFNotes.notes(root), only).size()
	return 0


## What exporting `root`, or the nodes in `only`, as `format` leaves out, as
## "2 cordons, 1 note", or "" when it leaves out nothing there. The sender puts it
## in its sentence as a word of `HFTranslation.message()`.
static func left_out(root: Node, format: String, only: Array = []) -> String:
	var parts: PackedStringArray = []
	for row in ROWS:
		if not (LOSES.get(format, []) as Array).has(row[0]):
			continue
		var many := count(root, row[0], only)
		if many > 0:
			parts.append(_phrase(str(row[0]), many))
	return HFTranslationType.joined(parts)


## How `many` of the row `key` reads in what an export says it left out.
static func _phrase(key: String, many: int) -> String:
	match key:
		"brushes":
			return HFTranslationType.message_n("{count} brush", "{count} brushes", many)
		"shapes":
			return HFTranslationType.message_n(
				"the shape of {count} brush", "the shape of {count} brushes", many
			)
		"cuts":
			return HFTranslationType.message_n("{count} cut", "{count} cuts", many)
		"face_materials":
			return HFTranslationType.message_n(
				"the material of {count} face", "the material of {count} faces", many
			)
		"uv_settings":
			return HFTranslationType.message_n(
				"the texture settings of {count} face",
				"the texture settings of {count} faces",
				many
			)
		"custom_uvs":
			return HFTranslationType.message_n(
				"the hand laid UVs of {count} face", "the hand laid UVs of {count} faces", many
			)
		"paint":
			return HFTranslationType.message_n(
				"paint on {count} face", "paint on {count} faces", many
			)
		"sculpts":
			return HFTranslationType.message_n(
				"the sculpt of {count} face", "the sculpt of {count} faces", many
			)
		"smoothing":
			return HFTranslationType.message_n(
				"the smoothing of {count} face", "the smoothing of {count} faces", many
			)
		"hidden_faces":
			return HFTranslationType.message_n("{count} Hidden face", "{count} Hidden faces", many)
		"texture_groups":
			return HFTranslationType.message_n(
				"the texture groups of {count} face", "the texture groups of {count} faces", many
			)
		"entities":
			return HFTranslationType.message_n(
				"{count} point entity", "{count} point entities", many
			)
		"entity_properties":
			return HFTranslationType.message_n(
				"the properties of {count} entity", "the properties of {count} entities", many
			)
		"wires":
			return HFTranslationType.message_n(
				"the wires of {count} entity", "the wires of {count} entities", many
			)
		"brush_entities":
			return HFTranslationType.message_n(
				"{count} brush entity", "{count} brush entities", many
			)
		"visgroups":
			return HFTranslationType.message_n("{count} visgroup", "{count} visgroups", many)
		"groups":
			return HFTranslationType.message_n("{count} group", "{count} groups", many)
		"structures":
			return HFTranslationType.message_n("{count} structure", "{count} structures", many)
		"prefab_links":
			return HFTranslationType.message_n("{count} prefab copy", "{count} prefab copies", many)
		"cordons":
			return HFTranslationType.message_n("{count} cordon", "{count} cordons", many)
		"bake_settings":
			return HFTranslationType.message_n("{count} bake option", "{count} bake options", many)
		"brush_bake":
			return HFTranslationType.message_n(
				"the bake options of {count} brush", "the bake options of {count} brushes", many
			)
		"floor_paint":
			return HFTranslationType.message_n(
				"{count} floor paint layer", "{count} floor paint layers", many
			)
		"notes":
			return HFTranslationType.message_n("{count} note", "{count} notes", many)
	return ""


static func _within(nodes: Array, only: Array) -> Array:
	if only.is_empty():
		return nodes
	return nodes.filter(func(node): return only.has(node))


static func _brushes(root: Node) -> Array:
	var out: Array = []
	if root == null or root.get("draft_brushes_node") == null:
		return out
	for child in root.draft_brushes_node.get_children():
		if child is DraftBrush and not child.is_queued_for_deletion():
			if (child as DraftBrush).operation == CSGShape3D.OPERATION_UNION:
				out.append(child)
	return out


## A cut aimed, committed or plain, as the `.map` export tells one.
static func _cuts(root: Node) -> Array:
	var out: Array = []
	var draft = root.get("draft_brushes_node")
	for container in [draft, root.get("pending_node"), root.get("committed_node")]:
		if container == null:
			continue
		for child in container.get_children():
			if not (child is DraftBrush) or child.is_queued_for_deletion():
				continue
			if (
				container != draft
				or (child as DraftBrush).operation == CSGShape3D.OPERATION_SUBTRACTION
			):
				out.append(child)
	return out


static func _has_own_shape(brush: Variant) -> bool:
	var shape: int = (brush as DraftBrush).shape
	return shape != DraftBrush.BrushShape.BOX and shape != DraftBrush.BrushShape.CUSTOM


static func _laid_on(face: Variant) -> bool:
	return face.uv_scale != Vector2.ONE or face.uv_offset != Vector2.ZERO or face.uv_rotation != 0.0


static func _faces(root: Node, only: Array, test: Callable) -> int:
	var many := 0
	for brush in _within(_brushes(root) + _cuts(root), only):
		for face in brush.faces:
			if face != null and test.call(face):
				many += 1
	return many


static func _entities(root: Node) -> Array:
	var out: Array = []
	if root == null or root.get("entities_node") == null:
		return out
	for child in root.entities_node.get_children():
		if child is DraftEntity and not child.is_queued_for_deletion():
			out.append(child)
	return out


static func _point_entities(root: Node) -> Array:
	return _entities(root).filter(func(e): return not HFNotes.is_note(e))


static func _has_properties(entity: Variant) -> bool:
	return not HFEntityPropUtils.get_entity_data(entity).is_empty()


static func _has_wires(node: Variant) -> bool:
	var outputs: Variant = node.get_meta("entity_io_outputs", [])
	return outputs is Array and not (outputs as Array).is_empty()


## The visgroups with a member: in the level, or among `only`.
static func _visgroups(root: Node, only: Array) -> int:
	if root.get("visgroup_system") == null:
		return 0
	var many := 0
	for vg_name in root.visgroup_system.get_visgroup_names():
		var members: Array = root.visgroup_system.get_members_of(vg_name)
		if not _within(members, only).is_empty():
			many += 1
	return many


static func _groups(root: Node, only: Array) -> int:
	if root.get("visgroup_system") == null:
		return 0
	if only.is_empty():
		return root.visgroup_system.groups.size()
	return _tags(only, &"group_id").size()


## The distinct values of `meta` on `nodes`.
static func _tags(nodes: Array, meta: StringName) -> Dictionary:
	var seen := {}
	for node in nodes:
		if node is Node and node.has_meta(meta) and str(node.get_meta(meta)) != "":
			seen[str(node.get_meta(meta))] = true
	return seen


static func _cordons(root: Node) -> int:
	if not root.get("cordon_enabled"):
		return 0
	return 1 + (root.get("cordon_extra_aabbs") as Array).size()


## The level's bake options a profile sets that are off their defaults.
static func _bake_options(root: Node) -> int:
	var bake_system = root.get("bake_system")
	if bake_system == null:
		return 0
	var many := 0
	for option in bake_system.profile_setting_names():
		if root.get(option) != root.get_script().get_property_default_value(option):
			many += 1
	return many


## A brush that sets its own Cast Shadows or Lightmap Scale.
static func _has_own_bake(brush: Variant) -> bool:
	return (
		brush.has_meta(HFBakeSplit.CAST_SHADOW_META)
		or brush.has_meta(HFBakeSplit.LIGHTMAP_SCALE_META)
	)


static func _floor_paint(root: Node) -> int:
	var layers = root.get("paint_layers")
	if layers == null:
		return 0
	var many := 0
	for layer in layers.layers:
		if layer != null and not layer.get_chunk_ids().is_empty():
			many += 1
	return many
