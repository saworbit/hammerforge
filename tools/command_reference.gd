extends RefCounted
## `docs/commands.md`, built from `HFCommandRegistry` and the default keymap
## (#1658). `tools/gen_command_reference.gd` writes it, and
## `tests/test_command_reference.gd` fails when the committed page is not what
## this builds, so the page cannot drift from the registry.

const HFCommandRegistryType = preload("res://addons/hammerforge/hf_command_registry.gd")
const HFKeymapType = preload("res://addons/hammerforge/hf_keymap.gd")

const PATH := "res://docs/commands.md"
const REGENERATE := "godot --headless -s res://tools/gen_command_reference.gd --path ."
## The palette's order, then any other category in the order it first appears.
const CATEGORY_ORDER := [
	"Workflow", "Tools", "Editing", "Transform", "Selection", "Paint", "Axis Lock"
]


## The whole page, from the registry and the default keymap.
static func build() -> String:
	var keymap := HFKeymapType.load_or_default("")
	var lines := PackedStringArray(
		[
			"---",
			"title: Commands",
			(
				'description: "Every HammerForge command with its default key, what it needs,'
				+ ' whether the palette lists it and, for the Agent Bridge, its parameters."'
			),
			"---",
			"",
			"# Commands",
			"",
			"Every command a HammerForge surface can run, from `HFCommandRegistry`. A key is",
			"the default; the shortcut dialog (**?** on the toolbar) changes it. **Needs** is",
			"what the selection must hold for the palette, a menu or a key to run it.",
			"",
			"This page is written by `tools/gen_command_reference.gd`. Do not edit it by",
			"hand: change the registry and run `%s`." % REGENERATE,
			"",
		]
	)
	for category in categories():
		lines.append("## %s" % category)
		lines.append("")
		lines.append("| Command | Key | Needs | Palette | What it does |")
		lines.append("|---|---|---|---|---|")
		for entry in HFCommandRegistryType.COMMANDS:
			if str(entry.get("category", "")) != category:
				continue
			var id := str(entry["id"])
			(
				lines
				. append(
					(
						"| %s (`%s`) | %s | %s | %s | %s |"
						% [
							_cell(str(entry.get("label", id))),
							id,
							_cell(_key(keymap, id)),
							needs(entry),
							"yes" if in_palette(keymap, id) else "no",
							_cell(str(entry.get("help", ""))),
						]
					)
				)
			)
		lines.append("")
	lines.append_array(_bridge_section())
	return "\n".join(lines).strip_edges() + "\n"


## The categories the registry uses, the palette's first.
static func categories() -> PackedStringArray:
	var out := PackedStringArray()
	for category in CATEGORY_ORDER:
		out.append(category)
	for entry in HFCommandRegistryType.COMMANDS:
		var category := str(entry.get("category", ""))
		if not out.has(category):
			out.append(category)
	var used := PackedStringArray()
	for category in out:
		for entry in HFCommandRegistryType.COMMANDS:
			if str(entry.get("category", "")) == category:
				used.append(category)
				break
	return used


## What the selection must hold, in words.
static func needs(entry: Dictionary) -> String:
	var selection: Dictionary = entry.get("selection", {})
	var parts := PackedStringArray()
	if selection.get("mixed_only") == true:
		parts.append("no mix of HammerForge and Godot nodes")
	elif not selection.is_empty():
		var minimum := int(selection.get("minimum", 1))
		var brushes: bool = selection.get("brushes_only") == true
		var thing := "brush" if minimum == 1 else "brushes"
		if not brushes:
			thing = "item" if minimum == 1 else "items"
		if minimum <= 0:
			parts.append("nothing")
		else:
			parts.append("%d %s" % [minimum, thing])
		if selection.get("allow_faces") == true:
			parts[0] = parts[0] + " or faces"
	if entry.get("needs_level") == true:
		parts.append("a level")
	return ", ".join(parts) if not parts.is_empty() else "-"


## Whether the palette offers command `id`: one it lists, or a keymap action
## with a key.
static func in_palette(keymap: HFKeymap, id: String) -> bool:
	if HFCommandRegistryType.palette_ids().has(id):
		return true
	return keymap.has_action(id) and keymap.get_display_string(id) != ""


static func _key(keymap: HFKeymap, id: String) -> String:
	if not keymap.has_action(id):
		return "none"
	var shown := keymap.get_display_string(id)
	return shown if shown != "" else "none"


## The bridge's commands, each with what the agent reads and a table of params.
static func _bridge_section() -> PackedStringArray:
	var lines := PackedStringArray(
		[
			"## Agent Bridge",
			"",
			"These commands an agent may run over the bridge with `hf_run_command`, on the",
			"brushes and entities it names, never on the selection. `hf_list_commands` gives",
			"the same parameters as JSON Schema.",
			"",
		]
	)
	for id in HFCommandRegistryType.bridge_ids():
		var bridge := HFCommandRegistryType.bridge(id)
		lines.append("### %s (`%s`)" % [HFCommandRegistryType.label(id), id])
		lines.append("")
		lines.append(str(bridge.get("description", "")).strip_edges())
		lines.append("")
		var params: Array = bridge.get("params", [])
		if params.is_empty():
			lines.append("No parameters.")
			lines.append("")
			continue
		lines.append("| Param | Type | Range | Default | Description |")
		lines.append("|---|---|---|---|---|")
		for param in params:
			(
				lines
				. append(
					(
						"| `%s`%s | %s | %s | %s | %s |"
						% [
							str(param.get("key", "")),
							" (required)" if param.get("required") == true else "",
							_type(param),
							_range(param),
							_cell(_default(param)),
							_cell(str(param.get("description", ""))),
						]
					)
				)
			)
		lines.append("")
	return lines


static func _type(param: Dictionary) -> String:
	var kind := str(param.get("type", ""))
	if kind == "enum" and param.get("options") is Array:
		return "enum: %s" % ", ".join(PackedStringArray(param["options"]))
	return kind


static func _range(param: Dictionary) -> String:
	var low: Variant = param.get("min")
	var high: Variant = param.get("max")
	if low == null and high == null:
		return "-"
	return (
		"%s to %s" % ["-" if low == null else _number(low), "-" if high == null else _number(high)]
	)


static func _default(param: Dictionary) -> String:
	if not param.has("default"):
		return "-"
	var value: Variant = param["default"]
	if value is float or value is int:
		return _number(value)
	return JSON.stringify(value) if not (value is String) else str(value)


static func _number(value: Variant) -> String:
	var number := float(value)
	return str(int(number)) if number == roundf(number) else str(number)


## A table cell: a pipe would end it and a lone backtick would start code.
static func _cell(text: String) -> String:
	return text.replace("|", "\\|").replace("`", "&#96;").replace("\n", " ")
