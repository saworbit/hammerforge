@tool
class_name HFNotes
extends RefCounted
## Notes left in the level for the people working on it (#1700): a `note` point
## entity with a title, a body, a kind (Note, To Do or Playtest), an author and
## a done flag. Notes save with the level and its prefabs like any entity, and
## never reach a bake, an export or a running game: their class says
## `"editor_only": true`, which `is_editor_only()` reads.

const CLASS := DraftEntity.NOTE_CLASS
const KINDS := ["Note", "To Do", "Playtest"]
## How near, in pixels, the cursor must come to a note to show its body.
const HOVER_PIXELS := 24.0

static var _hovered: WeakRef = null


## Whether `node` is a Note entity.
static func is_note(node: Variant) -> bool:
	return node is DraftEntity and (node as DraftEntity).entity_type == CLASS


## Whether an entity is for the editor only, by its class.
static func is_editor_only(root: Node, node: Node) -> bool:
	if not (node is DraftEntity) or root == null or not root.has_method("get_entity_definition"):
		return false
	return root.get_entity_definition((node as DraftEntity).entity_type).get("editor_only") == true


## Every note in the level, as `{node, path, title, body, kind, author, done}`.
static func notes(root: Node) -> Array:
	var out: Array = []
	var holder = root.get("entities_node") if root else null
	if holder == null:
		return out
	for child in holder.get_children():
		if not is_note(child):
			continue
		var data: Dictionary = child.entity_data
		(
			out
			. append(
				{
					"node": child,
					"path": str(root.get_path_to(child)),
					"title": str(data.get("title", "Note")),
					"body": str(data.get("body", "")),
					"kind": kind_of(child),
					"author": str(data.get("author", "")),
					"done": data.get("done") is bool and data.get("done"),
				}
			)
		)
	return out


## A note's kind, one of `KINDS`; anything else reads as Note.
static func kind_of(note: Node) -> String:
	var kind := str(note.entity_data.get("kind", "Note")) if note is DraftEntity else "Note"
	return kind if KINDS.has(kind) else "Note"


## How many notes of each kind are open (not done), and how many in all.
static func summary(root: Node) -> Dictionary:
	var open := {}
	for kind in KINDS:
		open[kind] = 0
	var all := notes(root)
	for note in all:
		if not note["done"]:
			open[note["kind"]] += 1
	return {"total": all.size(), "open": open}


## The note under `mouse` in `camera`'s view, within `HOVER_PIXELS`, or null.
static func note_at(root: Node, camera: Camera3D, mouse: Vector2) -> Node:
	var best: Node = null
	var best_distance := HOVER_PIXELS
	for note in notes(root):
		var node: Node3D = note["node"]
		if camera.is_position_behind(node.global_position):
			continue
		var distance := camera.unproject_position(node.global_position).distance_to(mouse)
		if distance <= best_distance:
			best = node
			best_distance = distance
	return best


## Show the body of the note under the cursor, and hide the one shown before.
static func hover(root: Node, camera: Camera3D, mouse: Vector2) -> void:
	var under := note_at(root, camera, mouse) if root and camera else null
	var before: Node = _hovered.get_ref() if _hovered else null
	if under == before:
		return
	if before and is_instance_valid(before) and before.has_method("show_note_body"):
		before.show_note_body(false)
	_hovered = weakref(under) if under else null
	if under and under.has_method("show_note_body"):
		under.show_note_body(true)
