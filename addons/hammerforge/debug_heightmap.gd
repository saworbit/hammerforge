@tool
extends EditorScript
## Run from Script Editor: File -> Run (Ctrl+Shift+X)
## Output goes to the Output panel at the bottom of the editor.


func _run() -> void:
	print("=== HammerForge Diagnostic START ===")

	# Test 1: basic class instantiation
	print("1. HFPaintGrid...")
	var grid := HFPaintGrid.new()
	print("   OK: cell_size=%s" % grid.cell_size)

	# Test 2: paint layer
	print("2. HFPaintLayer...")
	var layer := HFPaintLayer.new()
	layer.chunk_size = 4
	layer.grid = grid
	layer.set_cell(Vector2i(0, 0), true)
	print("   OK: get_cell(0,0)=%s" % layer.get_cell(Vector2i(0, 0)))

	# Test 3: material/blend
	print("3. Material + Blend...")
	layer.set_cell_material(Vector2i(0, 0), 2)
	layer.set_cell_blend(Vector2i(0, 0), 0.5)
	print(
		(
			"   OK: mat=%d blend=%.2f"
			% [layer.get_cell_material(Vector2i(0, 0)), layer.get_cell_blend(Vector2i(0, 0))]
		)
	)

	# Test 4: heightmap IO
	print("4. HFHeightmapIO...")
	var hm := HFHeightmapIO.generate_noise(16, 16)
	print("   OK: noise %dx%d" % [hm.get_width(), hm.get_height()])

	# Test 5: heightmap on layer
	print("5. Heightmap layer...")
	layer.heightmap = hm
	layer.height_scale = 5.0
	print(
		(
			"   OK: has_heightmap=%s height_at(0,0)=%.2f"
			% [layer.has_heightmap(), layer.get_height_at(Vector2i(0, 0))]
		)
	)

	# Test 6: heightmap synth
	print("6. HFHeightmapSynth...")
	var synth := HFHeightmapSynth.new()
	var settings := HFGeometrySynth.SynthSettings.new()
	var chunk_ids: Array[Vector2i] = [Vector2i(0, 0)]
	var results = synth.build_for_chunks(layer, chunk_ids, settings)
	print("   OK: %d results" % results.size())

	# Test 7: generated model
	print("7. HFGeneratedModel...")
	var model := HFGeneratedModel.new()
	if results.size() > 0:
		var hf := HFGeneratedModel.HeightmapFloor.new()
		hf.id = results[0].id
		hf.mesh = results[0].mesh
		model.heightmap_floors.append(hf)
	print("   OK: heightmap_floors=%d" % model.heightmap_floors.size())

	# Test 8: geometry synth (flat floors/walls)
	print("8. HFGeometrySynth...")
	var geo := HFGeometrySynth.new()
	var flat_model = geo.build_for_chunks(layer, chunk_ids, settings)
	print("   OK: floors=%d walls=%d" % [flat_model.floors.size(), flat_model.walls.size()])

	# Test 9: reconciler
	print("9. HFGeneratedReconciler...")
	var rec := HFGeneratedReconciler.new()
	print("   OK: instantiated")

	# Test 10: connector
	print("10. HFConnectorTool...")
	var conn := HFConnectorTool.new()
	print(
		(
			"   OK: RAMP=%d STAIRS=%d"
			% [HFConnectorTool.ConnectorType.RAMP, HFConnectorTool.ConnectorType.STAIRS]
		)
	)

	# Test 11: foliage
	print("11. HFFoliagePopulator...")
	var fol := HFFoliagePopulator.new()
	var fs := HFFoliagePopulator.FoliageSettings.new()
	print("   OK: density=%.1f" % fs.density)

	# Test 12: systems
	print("12. Systems...")
	var dummy := Node3D.new()
	var ps := HFPaintSystem.new(dummy)
	var bs := HFBakeSystem.new(dummy)
	print("   OK: PaintSystem + BakeSystem")
	dummy.free()

	layer.free()
	print("=== Diagnostic DONE ===")
