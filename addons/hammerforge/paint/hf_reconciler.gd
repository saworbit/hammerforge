@tool
class_name HFGeneratedReconciler
extends RefCounted

const DraftBrush = preload("../brush_instance.gd")
const LevelRootType = preload("../level_root.gd")
const HFHash = preload("hf_hash.gd")

# Required: a stable container path under HammerForge root, eg "Generated/Floors" and "Generated/Walls"
var floors_root: Node
var walls_root: Node
var owner: Node = null

# Used to keep a fast index from stable-id -> node
var _index: Dictionary = {} # Dictionary[StringName, Node]

func build_index() -> void:
	_index.clear()
	_index_children(floors_root)
	_index_children(walls_root)

func reconcile(model: HFGeneratedModel, grid: HFPaintGrid, settings: HFGeometrySynth.SynthSettings, dirty_chunks: Array[Vector2i] = []) -> void:
	if not floors_root or not walls_root:
		return
	var scope: Dictionary = {}
	for cid in dirty_chunks:
		scope["%s,%s" % [cid.x, cid.y]] = true
	_index.clear()
	_index_children(floors_root, scope)
	_index_children(walls_root, scope)
	var want: Dictionary = {}
	for fr in model.floors:
		if not fr:
			continue
		want[fr.id] = true
		_upsert_floor(fr, grid)
	for ws in model.walls:
		if not ws:
			continue
		want[ws.id] = true
		_upsert_wall(ws, grid)
	for gid in _index.keys():
		if not want.has(gid):
			var node = _index.get(gid)
			if node and node.is_inside_tree():
				node.queue_free()

func _index_children(root: Node, scope: Dictionary = {}) -> void:
	if not root:
		return
	for child in root.get_children():
		if not child.has_meta("hf_gid"):
			continue
		var chunk_tag = str(child.get_meta("hf_chunk", ""))
		if scope.size() > 0 and not scope.has(chunk_tag):
			continue
		_index[child.get_meta("hf_gid")] = child

func _upsert_floor(fr: HFGeneratedModel.FloorRect, grid: HFPaintGrid) -> void:
	var node = _index.get(fr.id)
	if not node or not is_instance_valid(node):
		node = DraftBrush.new()
		node.name = "Floor__%s" % fr.id
		node.shape = LevelRootType.BrushShape.BOX
		node.operation = CSGShape3D.OPERATION_UNION
		floors_root.add_child(node)
		if owner:
			node.owner = owner
		_index[fr.id] = node
		_set_gen_meta(node, fr.id, "floor")
	var min_uv = grid.cell_to_uv(fr.min_cell)
	var max_uv = grid.cell_to_uv(fr.min_cell + fr.size)
	var center_uv = (min_uv + max_uv) * 0.5
	var center_world = grid.uv_to_world(center_uv, fr.layer_y + fr.thickness * 0.5)
	var width_world = fr.size.x * grid.cell_size
	var depth_world = fr.size.y * grid.cell_size
	node.global_transform = Transform3D(grid.basis, center_world)
	node.size = Vector3(width_world, fr.thickness, depth_world)

func _upsert_wall(ws: HFGeneratedModel.WallSeg, grid: HFPaintGrid) -> void:
	var node = _index.get(ws.id)
	if not node or not is_instance_valid(node):
		node = DraftBrush.new()
		node.name = "Wall__%s" % ws.id
		node.shape = LevelRootType.BrushShape.BOX
		node.operation = CSGShape3D.OPERATION_UNION
		walls_root.add_child(node)
		if owner:
			node.owner = owner
		_index[ws.id] = node
		_set_gen_meta(node, ws.id, "wall")
	var a_uv = Vector2(ws.a.x * grid.cell_size, ws.a.y * grid.cell_size)
	var b_uv = Vector2(ws.b.x * grid.cell_size, ws.b.y * grid.cell_size)
	var mid_uv = (a_uv + b_uv) * 0.5
	var outward_uv = Vector2(ws.outward.x, ws.outward.y) * (ws.thickness * 0.5)
	mid_uv += outward_uv
	var center_world = grid.uv_to_world(mid_uv, ws.layer_y + ws.height * 0.5)
	var length_world = a_uv.distance_to(b_uv)
	var size: Vector3
	if ws.a.y == ws.b.y:
		size = Vector3(length_world, ws.height, ws.thickness)
	else:
		size = Vector3(ws.thickness, ws.height, length_world)
	node.global_transform = Transform3D(grid.basis, center_world)
	node.size = size

func _set_gen_meta(node: Node, gid: StringName, kind: String) -> void:
	node.set_meta("hf_gid", gid)
	node.set_meta("hf_gen", true)
	node.set_meta("hf_kind", kind)
	node.set_meta("hf_chunk", HFHash.chunk_tag_from_id(gid))
