extends SceneTree
## Render the prototype texture contact sheet for the docs.
##
## One column per pattern and one row per colour, each cell the imported
## texture the Material Browser shows, labelled with the names the catalog
## uses. Renders into a fixed-size SubViewport, so the output is the same on
## every machine. Must run WITHOUT --headless: the dummy renderer writes a
## blank image.
##
## Usage:
##   godot --path . -s res://tools/capture_prototype_sheet.gd

const OUT_PATH := "res://docs/images/prototype_textures.png"

const CELL := 72
const GAP := 8
const MARGIN := 24
const ROW_LABEL_WIDTH := 72
const COLUMN_LABEL_HEIGHT := 56
const FONT_SIZE := 13

const BACKGROUND := Color(0.11, 0.12, 0.14)
const LABEL_COLOR := Color(0.80, 0.82, 0.86)


func _initialize() -> void:
	_run()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Refusing to run headless: the dummy renderer writes blank images.")
		quit(1)
		return

	var patterns: Array[String] = HFPrototypeTextures.PATTERNS
	var colors: Array[String] = HFPrototypeTextures.COLORS
	var pitch := CELL + GAP
	var size := Vector2i(
		MARGIN * 2 + ROW_LABEL_WIDTH + patterns.size() * pitch - GAP,
		MARGIN * 2 + COLUMN_LABEL_HEIGHT + colors.size() * pitch - GAP
	)

	var sub := SubViewport.new()
	sub.size = size
	sub.transparent_bg = false
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(sub)

	var background := ColorRect.new()
	background.color = BACKGROUND
	background.size = Vector2(size)
	sub.add_child(background)

	var grid_left := MARGIN + ROW_LABEL_WIDTH
	var grid_top := MARGIN + COLUMN_LABEL_HEIGHT
	for column in range(patterns.size()):
		# One word a line: stripes_horizontal is wider than its column.
		var heading := _label(patterns[column].replace("_", "\n"))
		heading.position = Vector2(grid_left + column * pitch - GAP / 2.0, MARGIN)
		heading.size = Vector2(pitch, COLUMN_LABEL_HEIGHT - 10)
		heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		heading.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		sub.add_child(heading)

	var missing := 0
	for row in range(colors.size()):
		var row_label := _label(colors[row])
		row_label.position = Vector2(MARGIN, grid_top + row * pitch)
		row_label.size = Vector2(ROW_LABEL_WIDTH - 10, CELL)
		row_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		sub.add_child(row_label)
		for column in range(patterns.size()):
			var texture := HFPrototypeTextures.load_texture(patterns[column], colors[row])
			if texture == null:
				missing += 1
				continue
			var cell := TextureRect.new()
			cell.texture = texture
			cell.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			cell.stretch_mode = TextureRect.STRETCH_SCALE
			cell.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			cell.position = Vector2(grid_left + column * pitch, grid_top + row * pitch)
			cell.size = Vector2(CELL, CELL)
			sub.add_child(cell)

	if missing > 0:
		printerr(missing, " prototype textures did not load; run --import first.")
		quit(1)
		return

	for _i in range(4):
		await process_frame
	RenderingServer.force_draw()
	await process_frame

	var image: Image = sub.get_texture().get_image()
	if image == null:
		printerr("Failed to capture the contact sheet.")
		quit(1)
		return
	var err := image.save_png(OUT_PATH)
	if err != OK:
		printerr("Failed to save ", OUT_PATH, ": error ", err)
		quit(1)
		return
	print("wrote ", OUT_PATH, " (", image.get_width(), "x", image.get_height(), ")")
	quit(0)


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", LABEL_COLOR)
	return label
