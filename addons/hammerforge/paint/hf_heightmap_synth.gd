@tool
class_name HFHeightmapSynth
extends RefCounted

const HFHash = preload("hf_hash.gd")
const HFGeometrySynth = preload("hf_geometry_synth.gd")


class HeightmapMeshResult:
	var id: StringName
	var mesh: ArrayMesh
	var transform: Transform3D
	var blend_image: Image = null
	var slot_textures: Array = []
	var slot_uv_scales: Array[float] = []
	var slot_tints: Array[Color] = []


func build_for_chunks(
	layer: HFPaintLayer, chunk_ids: Array[Vector2i], settings: HFGeometrySynth.SynthSettings
) -> Array[HeightmapMeshResult]:
	var results: Array[HeightmapMeshResult] = []
	for cid in chunk_ids:
		var result := _build_chunk_mesh(layer, cid, settings)
		if result:
			results.append(result)
	return results


func _build_chunk_mesh(
	layer: HFPaintLayer, cid: Vector2i, _settings: HFGeometrySynth.SynthSettings
) -> HeightmapMeshResult:
	var size := layer.chunk_size
	var origin := Vector2i(cid.x * size, cid.y * size)
	var grid := layer.grid
	if not grid:
		return null

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_verts := false

	for ly in range(size):
		for lx in range(size):
			var cell := origin + Vector2i(lx, ly)
			if not layer.get_cell(cell):
				continue
			has_verts = true
			_add_cell_quad(st, layer, grid, cell, size)

	if not has_verts:
		return null

	st.generate_normals()
	st.generate_tangents()

	var result := HeightmapMeshResult.new()
	result.id = HFHash.floor_id(layer.layer_id, cid, origin, Vector2i(size, size))
	result.mesh = st.commit()
	result.transform = Transform3D(grid.basis, grid.origin)
	result.blend_image = _build_blend_image(layer, origin, size)
	result.slot_textures = layer.get_terrain_slot_textures()
	result.slot_uv_scales = layer.get_terrain_slot_uv_scales()
	result.slot_tints = layer.get_terrain_slot_tints()
	return result


func _add_cell_quad(
	st: SurfaceTool, layer: HFPaintLayer, grid: HFPaintGrid, cell: Vector2i, chunk_size: int
) -> void:
	var cs := grid.cell_size
	# 4 corner positions: (0,0), (1,0), (1,1), (0,1)
	var offsets: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]
	var corners: Array[Vector3] = []
	for off in offsets:
		var corner_cell := cell + off
		var h := layer.get_height_at(corner_cell)
		corners.append(Vector3(corner_cell.x * cs, grid.layer_y + h, corner_cell.y * cs))

	# UVs tiled per cell
	var uv00 := Vector2(0.0, 0.0)
	var uv10 := Vector2(1.0, 0.0)
	var uv11 := Vector2(1.0, 1.0)
	var uv01 := Vector2(0.0, 1.0)

	# UV2 for blend map: position within chunk
	var local_x := posmod(cell.x, chunk_size)
	var local_y := posmod(cell.y, chunk_size)
	var inv := 1.0 / float(chunk_size)
	var uv2_00 := Vector2(float(local_x) * inv, float(local_y) * inv)
	var uv2_10 := Vector2(float(local_x + 1) * inv, float(local_y) * inv)
	var uv2_11 := Vector2(float(local_x + 1) * inv, float(local_y + 1) * inv)
	var uv2_01 := Vector2(float(local_x) * inv, float(local_y + 1) * inv)

	# Triangle 1: 0-1-2
	st.set_uv(uv00)
	st.set_uv2(uv2_00)
	st.add_vertex(corners[0])
	st.set_uv(uv10)
	st.set_uv2(uv2_10)
	st.add_vertex(corners[1])
	st.set_uv(uv11)
	st.set_uv2(uv2_11)
	st.add_vertex(corners[2])
	# Triangle 2: 0-2-3
	st.set_uv(uv00)
	st.set_uv2(uv2_00)
	st.add_vertex(corners[0])
	st.set_uv(uv11)
	st.set_uv2(uv2_11)
	st.add_vertex(corners[2])
	st.set_uv(uv01)
	st.set_uv2(uv2_01)
	st.add_vertex(corners[3])


func _build_blend_image(layer: HFPaintLayer, origin: Vector2i, size: int) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in range(size):
		for x in range(size):
			var cell := origin + Vector2i(x, y)
			var w1 := layer.get_cell_blend_slot(cell, 1)
			var w2 := layer.get_cell_blend_slot(cell, 2)
			var w3 := layer.get_cell_blend_slot(cell, 3)
			img.set_pixel(x, y, Color(w1, w2, w3, 1.0))
	return img
