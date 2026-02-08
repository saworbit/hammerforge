@tool
class_name HFHeightmapIO
extends RefCounted


static func load_from_file(path: String) -> Image:
	var img := Image.new()
	var err := img.load(path)
	if err != OK:
		push_error("HFHeightmapIO: Failed to load '%s': %s" % [path, error_string(err)])
		return null
	img.convert(Image.FORMAT_RF)
	return img


static func generate_noise(width: int, height: int, settings: Dictionary = {}) -> Image:
	var noise := FastNoiseLite.new()
	noise.noise_type = int(settings.get("type", FastNoiseLite.TYPE_SIMPLEX_SMOOTH))
	noise.frequency = float(settings.get("frequency", 0.01))
	noise.fractal_octaves = int(settings.get("octaves", 4))
	noise.seed = int(settings.get("seed", 0))
	var img := noise.get_image(width, height, false, false)
	img.convert(Image.FORMAT_RF)
	return img


static func encode_to_base64(img: Image) -> String:
	if img == null or img.is_empty():
		return ""
	var png := img.save_png_to_buffer()
	return Marshalls.raw_to_base64(png)


static func decode_from_base64(data: String) -> Image:
	if data == "":
		return null
	var raw := Marshalls.base64_to_raw(data)
	var img := Image.new()
	if img.load_png_from_buffer(raw) != OK:
		push_error("HFHeightmapIO: Failed to decode heightmap from base64")
		return null
	img.convert(Image.FORMAT_RF)
	return img
