extends GutTest

const HFHeightmapIO = preload("res://addons/hammerforge/paint/hf_heightmap_io.gd")

# ===========================================================================
# Base64 encode / decode round-trip
# ===========================================================================


func test_encode_decode_round_trip():
	var img = Image.create(16, 16, false, Image.FORMAT_RF)
	# Set some known pixel values
	img.set_pixel(0, 0, Color(0.25, 0, 0, 1))
	img.set_pixel(8, 8, Color(0.75, 0, 0, 1))
	img.set_pixel(15, 15, Color(1.0, 0, 0, 1))
	var b64 = HFHeightmapIO.encode_to_base64(img)
	assert_true(b64 != "", "Encoded string should not be empty")
	var decoded = HFHeightmapIO.decode_from_base64(b64)
	assert_not_null(decoded, "Decoded image should not be null")
	assert_eq(decoded.get_width(), 16, "Width preserved")
	assert_eq(decoded.get_height(), 16, "Height preserved")
	assert_almost_eq(decoded.get_pixel(0, 0).r, 0.25, 0.01, "Pixel (0,0) preserved")
	assert_almost_eq(decoded.get_pixel(8, 8).r, 0.75, 0.01, "Pixel (8,8) preserved")
	assert_almost_eq(decoded.get_pixel(15, 15).r, 1.0, 0.01, "Pixel (15,15) preserved")


func test_encode_decode_large_image():
	var img = Image.create(128, 128, false, Image.FORMAT_RF)
	img.fill(Color(0.42, 0, 0, 1))
	var b64 = HFHeightmapIO.encode_to_base64(img)
	var decoded = HFHeightmapIO.decode_from_base64(b64)
	assert_not_null(decoded)
	assert_eq(decoded.get_width(), 128)
	assert_eq(decoded.get_height(), 128)
	assert_almost_eq(decoded.get_pixel(64, 64).r, 0.42, 0.01, "Center pixel preserved")


func test_encode_null_returns_empty():
	var b64 = HFHeightmapIO.encode_to_base64(null)
	assert_eq(b64, "", "Null image should encode to empty string")


func test_encode_empty_image_returns_empty():
	var img = Image.new()
	var b64 = HFHeightmapIO.encode_to_base64(img)
	assert_eq(b64, "", "Empty image should encode to empty string")


func test_decode_empty_string_returns_null():
	var decoded = HFHeightmapIO.decode_from_base64("")
	assert_null(decoded, "Empty string should decode to null")


func test_encode_returns_nonempty_for_valid_image():
	var img = Image.create(4, 4, false, Image.FORMAT_RF)
	img.fill(Color(0.5, 0, 0, 1))
	var b64 = HFHeightmapIO.encode_to_base64(img)
	assert_true(b64.length() > 10, "Valid image should encode to substantial base64 string")


# ===========================================================================
# Noise generation
# ===========================================================================


func test_generate_noise_creates_image():
	var img = HFHeightmapIO.generate_noise(32, 32)
	assert_not_null(img, "Noise generation should create an image")
	assert_eq(img.get_width(), 32, "Width should match")
	assert_eq(img.get_height(), 32, "Height should match")


func test_generate_noise_format_rf():
	var img = HFHeightmapIO.generate_noise(16, 16)
	assert_eq(img.get_format(), Image.FORMAT_RF, "Noise should be FORMAT_RF")


func test_generate_noise_has_variation():
	var img = HFHeightmapIO.generate_noise(32, 32)
	# Sample multiple pixels — noise should have variation
	var min_val := 1.0
	var max_val := 0.0
	for x in range(0, 32, 4):
		for y in range(0, 32, 4):
			var val = img.get_pixel(x, y).r
			min_val = min(min_val, val)
			max_val = max(max_val, val)
	var range_val = max_val - min_val
	assert_true(range_val > 0.01, "Noise should have some variation (range: %.3f)" % range_val)


func test_generate_noise_with_settings():
	var settings = {
		"type": FastNoiseLite.TYPE_PERLIN,
		"frequency": 0.05,
		"octaves": 2,
		"seed": 42,
	}
	var img = HFHeightmapIO.generate_noise(16, 16, settings)
	assert_not_null(img, "Noise with custom settings should create image")
	assert_eq(img.get_width(), 16)


func test_generate_noise_deterministic():
	var settings = {"seed": 12345, "frequency": 0.02}
	var img1 = HFHeightmapIO.generate_noise(16, 16, settings)
	var img2 = HFHeightmapIO.generate_noise(16, 16, settings)
	# Same seed + settings should produce same image
	var match_count := 0
	for x in range(16):
		for y in range(16):
			if is_equal_approx(img1.get_pixel(x, y).r, img2.get_pixel(x, y).r):
				match_count += 1
	assert_eq(match_count, 256, "Same seed should produce identical noise")


# ===========================================================================
# Noise → base64 → decode round-trip
# ===========================================================================


func test_noise_encode_decode_round_trip():
	var original = HFHeightmapIO.generate_noise(32, 32, {"seed": 99})
	var b64 = HFHeightmapIO.encode_to_base64(original)
	var decoded = HFHeightmapIO.decode_from_base64(b64)
	assert_not_null(decoded)
	assert_eq(decoded.get_width(), 32)
	# Spot-check a few pixels
	assert_almost_eq(
		decoded.get_pixel(5, 5).r, original.get_pixel(5, 5).r, 0.01, "Pixel (5,5) survives"
	)
	assert_almost_eq(
		decoded.get_pixel(20, 20).r, original.get_pixel(20, 20).r, 0.01, "Pixel (20,20) survives"
	)
