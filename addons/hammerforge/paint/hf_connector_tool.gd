@tool
class_name HFConnectorTool
extends RefCounted

enum ConnectorType { RAMP, STAIRS }


class ConnectorDef:
	var from_layer_index: int = 0
	var to_layer_index: int = 1
	var from_cell: Vector2i = Vector2i.ZERO
	var to_cell: Vector2i = Vector2i.ZERO
	var connector_type: int = ConnectorType.RAMP
	var width_cells: int = 2
	var stair_step_height: float = 0.25


func generate_connector(def: ConnectorDef, layers: HFPaintLayerManager) -> ArrayMesh:
	if def.from_layer_index < 0 or def.from_layer_index >= layers.layers.size():
		return null
	if def.to_layer_index < 0 or def.to_layer_index >= layers.layers.size():
		return null
	var from_layer: HFPaintLayer = layers.layers[def.from_layer_index]
	var to_layer: HFPaintLayer = layers.layers[def.to_layer_index]
	if not from_layer or not from_layer.grid or not to_layer or not to_layer.grid:
		return null

	var from_y := from_layer.grid.layer_y + from_layer.get_height_at(def.from_cell)
	var to_y := to_layer.grid.layer_y + to_layer.get_height_at(def.to_cell)

	match def.connector_type:
		ConnectorType.RAMP:
			return _generate_ramp(def, from_layer.grid, from_y, to_y)
		ConnectorType.STAIRS:
			return _generate_stairs(def, from_layer.grid, from_y, to_y, def.stair_step_height)
	return null


func _generate_ramp(def: ConnectorDef, grid: HFPaintGrid, from_y: float, to_y: float) -> ArrayMesh:
	var cs := grid.cell_size
	var dir := Vector2(def.to_cell.x - def.from_cell.x, def.to_cell.y - def.from_cell.y)
	var length := dir.length()
	if length < 0.001:
		return null
	dir = dir.normalized()
	var perp := Vector2(-dir.y, dir.x)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var steps := int(ceil(length))
	var hw := float(def.width_cells) * 0.5
	for i in range(steps):
		var t0 := float(i) / float(steps)
		var t1 := float(i + 1) / float(steps)
		var y0 := lerpf(from_y, to_y, t0)
		var y1 := lerpf(from_y, to_y, t1)
		var p0 := Vector2(def.from_cell.x, def.from_cell.y) + dir * float(i)
		var p1 := p0 + dir
		# Left and right edges of the ramp
		var l0 := p0 + perp * (-hw)
		var r0 := p0 + perp * hw
		var l1 := p1 + perp * (-hw)
		var r1 := p1 + perp * hw
		var v_l0 := Vector3(l0.x * cs, y0, l0.y * cs)
		var v_r0 := Vector3(r0.x * cs, y0, r0.y * cs)
		var v_l1 := Vector3(l1.x * cs, y1, l1.y * cs)
		var v_r1 := Vector3(r1.x * cs, y1, r1.y * cs)
		# Two triangles for top surface
		st.set_uv(Vector2(0, t0))
		st.add_vertex(v_l0)
		st.set_uv(Vector2(1, t0))
		st.add_vertex(v_r0)
		st.set_uv(Vector2(1, t1))
		st.add_vertex(v_r1)
		st.set_uv(Vector2(0, t0))
		st.add_vertex(v_l0)
		st.set_uv(Vector2(1, t1))
		st.add_vertex(v_r1)
		st.set_uv(Vector2(0, t1))
		st.add_vertex(v_l1)

	st.generate_normals()
	st.generate_tangents()
	return st.commit()


func _generate_stairs(
	def: ConnectorDef, grid: HFPaintGrid, from_y: float, to_y: float, step_h: float
) -> ArrayMesh:
	var cs := grid.cell_size
	var height_diff := to_y - from_y
	var num_steps := maxi(1, int(ceil(absf(height_diff) / maxf(step_h, 0.01))))
	var dir := Vector2(def.to_cell.x - def.from_cell.x, def.to_cell.y - def.from_cell.y)
	var length := dir.length()
	if length < 0.001:
		return null
	dir = dir.normalized()
	var perp := Vector2(-dir.y, dir.x)
	var hw := float(def.width_cells) * 0.5

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for i in range(num_steps):
		var t0 := float(i) / float(num_steps)
		var t1 := float(i + 1) / float(num_steps)
		var y_top := lerpf(from_y, to_y, t1)
		var y_bot := lerpf(from_y, to_y, t0)
		var p0 := Vector2(def.from_cell.x, def.from_cell.y) + dir * length * t0
		var p1 := Vector2(def.from_cell.x, def.from_cell.y) + dir * length * t1
		var l0 := p0 + perp * (-hw)
		var r0 := p0 + perp * hw
		var l1 := p1 + perp * (-hw)
		var r1 := p1 + perp * hw
		# Horizontal tread
		var v_l0 := Vector3(l0.x * cs, y_top, l0.y * cs)
		var v_r0 := Vector3(r0.x * cs, y_top, r0.y * cs)
		var v_l1 := Vector3(l1.x * cs, y_top, l1.y * cs)
		var v_r1 := Vector3(r1.x * cs, y_top, r1.y * cs)
		st.set_uv(Vector2(0, 0))
		st.add_vertex(v_l0)
		st.set_uv(Vector2(1, 0))
		st.add_vertex(v_r0)
		st.set_uv(Vector2(1, 1))
		st.add_vertex(v_r1)
		st.set_uv(Vector2(0, 0))
		st.add_vertex(v_l0)
		st.set_uv(Vector2(1, 1))
		st.add_vertex(v_r1)
		st.set_uv(Vector2(0, 1))
		st.add_vertex(v_l1)
		# Vertical riser (front face of step)
		if i > 0 or absf(height_diff) > 0.001:
			var v_l0_bot := Vector3(l0.x * cs, y_bot, l0.y * cs)
			var v_r0_bot := Vector3(r0.x * cs, y_bot, r0.y * cs)
			st.set_uv(Vector2(0, 0))
			st.add_vertex(v_l0_bot)
			st.set_uv(Vector2(1, 0))
			st.add_vertex(v_r0_bot)
			st.set_uv(Vector2(1, 1))
			st.add_vertex(v_r0)
			st.set_uv(Vector2(0, 0))
			st.add_vertex(v_l0_bot)
			st.set_uv(Vector2(1, 1))
			st.add_vertex(v_r0)
			st.set_uv(Vector2(0, 1))
			st.add_vertex(v_l0)

	st.generate_normals()
	st.generate_tangents()
	return st.commit()
