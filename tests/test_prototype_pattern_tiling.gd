extends GutTest

## The hex and triangles prototype textures are drawn as their names say (#1330).
##
## Both families come from tools/make_prototype_patterns.py, on one lattice:
## five columns across the 128 px tile and six rows down it, in the two tones
## the colour family's other patterns use. The lattice is the contract, so its
## numbers are repeated here. A regenerated set has to keep each file the
## 128 px SVG the importer expects, use only its family's two tones, repeat at
## the lattice pitch so the tile wraps without a seam, and keep a light cell
## or triangle where the name says one is.

const HFProto = preload("res://addons/hammerforge/hf_prototype_textures.gd")

const PROTOTYPES := "res://addons/hammerforge/textures/prototypes/"
const PATTERNS := ["hex", "triangles"]
const TILE := 128
const COLUMNS := 5
const ROWS := 6

## Rendered 120 px wide the pitch is a whole number of pixels, 24 across and
## 40 down for two rows, so a pixel has to equal the one a pitch away: the
## rasteriser lands on the same sub-pixel phase both times. A seam or a row
## that drifts shows as most of the contrast; the rasteriser's own rounding is
## never more than 2 of 255.
const RENDER := 120
const PITCH_X := RENDER / COLUMNS
const PITCH_Y := 2 * RENDER / ROWS
const TOLERANCE := 4.0 / 255.0


func _text(pattern: String, colour: String) -> String:
	return FileAccess.get_file_as_string(PROTOTYPES + pattern + "_" + colour + ".svg")


func _fills(text: String) -> Array:
	var regex := RegEx.new()
	regex.compile('fill="(#[0-9a-f]{6})"')
	var found := {}
	for found_match in regex.search_all(text):
		found[found_match.get_string(1)] = true
	var fills := found.keys()
	fills.sort()
	return fills


func _render(pattern: String, colour: String) -> Image:
	var image := Image.new()
	var err := image.load_svg_from_string(_text(pattern, colour), float(RENDER) / TILE)
	assert_eq(err, OK, "%s_%s renders" % [pattern, colour])
	assert_eq(image.get_size(), Vector2i(RENDER, RENDER), "%s_%s render size" % [pattern, colour])
	return image


func _same(a: Color, b: Color) -> bool:
	return (
		absf(a.r - b.r) <= TOLERANCE
		and absf(a.g - b.g) <= TOLERANCE
		and absf(a.b - b.b) <= TOLERANCE
	)


## The darker and lighter of a family's two tones, as the checker uses them.
func _tones(colour: String) -> Array[Color]:
	var fills := _fills(_text("checker", colour))
	assert_eq(fills.size(), 2, "fixture: checker_%s has two tones" % colour)
	var tones: Array[Color] = [Color.html(str(fills[0])), Color.html(str(fills[1]))]
	if tones[0].get_luminance() > tones[1].get_luminance():
		tones.reverse()
	return tones


func test_each_file_is_the_128_px_svg_the_importer_expects():
	for pattern in PATTERNS:
		for colour in HFProto.COLORS:
			var name := "%s_%s" % [pattern, colour]
			var text := _text(pattern, colour)
			var parser := XMLParser.new()
			assert_eq(parser.open_buffer(text.to_utf8_buffer()), OK, "%s opens as XML" % name)
			var root := ""
			while root == "" and parser.read() == OK:
				if parser.get_node_type() == XMLParser.NODE_ELEMENT:
					root = parser.get_node_name()
			assert_eq(root, "svg", "%s root element" % name)
			assert_eq(parser.get_named_attribute_value_safe("width"), "128", "%s width" % name)
			assert_eq(parser.get_named_attribute_value_safe("height"), "128", "%s height" % name)
			assert_eq(
				parser.get_named_attribute_value_safe("viewBox"), "0 0 128 128", "%s viewBox" % name
			)
			var image := Image.new()
			assert_eq(image.load_svg_from_string(text), OK, "%s rasterises" % name)
			assert_eq(image.get_size(), Vector2i(TILE, TILE), "%s is the shared tile size" % name)


func test_each_file_uses_only_its_colour_family_s_two_tones():
	for colour in HFProto.COLORS:
		var tones := _fills(_text("checker", colour))
		assert_eq(tones.size(), 2, "fixture: checker_%s has two tones" % colour)
		for pattern in PATTERNS:
			assert_eq(
				_fills(_text(pattern, colour)),
				tones,
				"%s_%s uses its family's tones" % [pattern, colour]
			)


func test_each_tile_repeats_at_the_lattice_pitch_in_both_directions():
	for pattern in PATTERNS:
		for colour in HFProto.COLORS:
			var image := _render(pattern, colour)
			var seams := 0
			for y in RENDER:
				for x in RENDER:
					var here := image.get_pixel(x, y)
					if x + PITCH_X < RENDER and not _same(here, image.get_pixel(x + PITCH_X, y)):
						seams += 1
					if y + PITCH_Y < RENDER and not _same(here, image.get_pixel(x, y + PITCH_Y)):
						seams += 1
			assert_eq(
				seams, 0, "%s_%s: pixels that differ from the one a pitch away" % [pattern, colour]
			)


## A tile of one flat colour repeats at any pitch, so both tones have to show.
func test_both_tones_cover_a_share_of_each_tile():
	for pattern in PATTERNS:
		for colour in HFProto.COLORS:
			var tones := _tones(colour)
			var image := _render(pattern, colour)
			var counts := [0, 0]
			for y in RENDER:
				for x in RENDER:
					var pixel := image.get_pixel(x, y)
					for i in 2:
						if _same(pixel, tones[i]):
							counts[i] += 1
			var share := RENDER * RENDER / 20
			assert_gt(
				counts[0], share, "%s_%s: the dark tone covers a twentieth" % [pattern, colour]
			)
			assert_gt(
				counts[1], share, "%s_%s: the light tone covers a twentieth" % [pattern, colour]
			)


## Every cell centre is a light cell and the point midway to the next cell is
## the dark wall between them. The old drawing painted every other cell the
## ground colour and left a gap of it around each, so it read as ovals.
func test_hex_is_light_cells_with_a_dark_wall_between_them():
	for colour in HFProto.COLORS:
		var tones := _tones(colour)
		var image := _render("hex", colour)
		var cells := 0
		var walls := 0
		for row in ROWS:
			var shift := PITCH_X / 2 if row % 2 == 1 else 0
			var y := row * PITCH_Y / 2 + 13  # two thirds of a row down is the centre
			for column in COLUMNS:
				var x := column * PITCH_X + shift
				if x < RENDER and _same(image.get_pixel(x, y), tones[1]):
					cells += 1
				var wall_x := x + PITCH_X / 2
				if wall_x < RENDER and _same(image.get_pixel(wall_x, y), tones[0]):
					walls += 1
		# Odd rows are shifted half a pitch, so their last wall falls off the edge.
		assert_eq(cells, ROWS * COLUMNS, "hex_%s: light cell centres" % colour)
		assert_eq(walls, ROWS * COLUMNS - ROWS / 2, "hex_%s: dark walls between cells" % colour)


## Every triangle pointing up is light and every one pointing down is dark, so
## each one has the other tone on all three sides. The old drawing split
## squares and let same-coloured halves meet, which read as diagonal bands.
func test_triangles_alternate_light_up_and_dark_down():
	for colour in HFProto.COLORS:
		var tones := _tones(colour)
		var image := _render("triangles", colour)
		var light_up := 0
		var dark_down := 0
		for row in ROWS:
			var shift := PITCH_X / 2 if row % 2 == 1 else 0
			var top := row * PITCH_Y / 2
			for column in COLUMNS:
				var apex_x := column * PITCH_X + PITCH_X / 2 + shift
				if apex_x < RENDER and _same(image.get_pixel(apex_x, top + 13), tones[1]):
					light_up += 1
				var down_x := apex_x + PITCH_X / 2
				if down_x < RENDER and _same(image.get_pixel(down_x, top + 6), tones[0]):
					dark_down += 1
		# The last one in a row falls off the right edge: the up triangle in odd
		# rows, the down triangle in every row.
		assert_eq(light_up, ROWS * COLUMNS - ROWS / 2, "triangles_%s: light triangles up" % colour)
		assert_eq(dark_down, ROWS * COLUMNS - ROWS, "triangles_%s: dark triangles down" % colour)
